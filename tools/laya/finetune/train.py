#!/usr/bin/env python3

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import random
import shutil
import subprocess
import sys
import time

import torch
from safetensors.torch import load_file, save_file

ATTRIBUTION = ("Training loop adapted from Laya (https://github.com/NandhaKishorM/laya), by Convai "
               "Innovations, Apache License 2.0: notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb.")


def default_base() -> str:
    hits = glob.glob(os.path.expanduser(
        "~/.cache/huggingface/hub/models--convaiinnovations--laya/snapshots/*/multilingual"))
    return hits[0] if hits else ""


def log(fh, msg: str) -> None:
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    fh.write(line + "\n")
    fh.flush()


def rss_gb() -> float:
    try:
        out = subprocess.check_output(["ps", "-o", "rss=", "-p", str(os.getpid())], text=True)
        return int(out.strip()) / 1024 / 1024
    except Exception:
        return 0.0


def mps_gb() -> float:
    try:
        return torch.mps.driver_allocated_memory() / 1024 ** 3
    except Exception:
        return 0.0


def build_items(path: str, tok, cfg, limit: int = 0, seed: int = 1):

    from laya.common import QTYPES, build_sequence, render_options

    rows = [json.loads(line) for line in open(path)]
    if limit and len(rows) > limit:
        random.Random(seed).shuffle(rows)
        rows = rows[:limit]
    items = []
    for row in rows:
        state = json.loads(row["state"])
        questions = json.loads(row["questions"])
        gold = json.loads(row["gold"])
        for qid, q in questions.items():
            if qid not in gold:
                continue
            t, crit, g = q["type"], q.get("criteria", {}), gold[qid]
            if t == "choice":
                target = [g["probabilities"].get(k, 0.0) for k in crit.keys()]
            elif t == "noul":
                target = [g["probabilities"].get("false", 0.5), g["probabilities"].get("true", 0.5)]
            else:
                n_levels = len(crit) if isinstance(crit, list) else 4
                target = [g["probabilities"].get(str(i), 0.0) for i in range(n_levels)]
            s = sum(target)
            target = [v / s for v in target] if s > 0 else [1.0 / len(target)] * len(target)
            k = len(render_options({"t": t, "crit": crit}))
            seq, markers = build_sequence(tok, state, {"t": t, "ins": q["instructions"], "crit": crit},
                                          cfg["max_len"], cfg["head_max_len"])
            if len(markers) != k:
                continue
            items.append({"ids": seq, "markers": markers, "qtype": QTYPES[t], "target": target,
                          "label": target.index(max(target)), "qid": qid, "match": row.get("match", "")})
    return items


def collate(items, pad_id):
    n, L = len(items), max(len(it["ids"]) for it in items)
    kmax = max(len(it["markers"]) for it in items)
    ids = torch.full((n, L), pad_id, dtype=torch.long)
    att = torch.zeros((n, L), dtype=torch.long)
    mpos = torch.zeros((n, kmax), dtype=torch.long)
    mmask = torch.zeros((n, kmax), dtype=torch.bool)
    target = torch.zeros((n, kmax), dtype=torch.float32)
    for i, it in enumerate(items):
        ids[i, :len(it["ids"])] = torch.tensor(it["ids"])
        att[i, :len(it["ids"])] = 1
        k = len(it["markers"])
        mpos[i, :k] = torch.tensor(it["markers"])
        mmask[i, :k] = True
        target[i, :len(it["target"])] = torch.tensor(it["target"], dtype=torch.float32)
    return {"input_ids": ids, "attention_mask": att, "marker_pos": mpos, "marker_mask": mmask,
            "target": target, "qtype": torch.tensor([it["qtype"] for it in items])}


def fit_one_temp(sel):
    if len(sel) < 10:
        return 1.0
    kmax = max(len(z) for z, _ in sel)
    Z = torch.full((len(sel), kmax), -1e4)
    T = torch.zeros((len(sel), kmax))
    for i, (z, t) in enumerate(sel):
        Z[i, :len(z)] = torch.tensor(z)
        T[i, :len(t)] = torch.tensor(t, dtype=torch.float32)
    log_t = torch.zeros(1, requires_grad=True)
    opt = torch.optim.LBFGS([log_t], lr=0.1, max_iter=100)

    def closure():
        opt.zero_grad()
        loss = -(T * torch.log_softmax(Z / log_t.exp(), -1)).sum(-1).mean()
        loss.backward()
        return loss
    opt.step(closure)
    return float(torch.clamp(log_t.exp(), 0.1, 10.0).item())


@torch.no_grad()
def eval_items(model, items, pad_id, device, amp, bs=32):

    model.eval()
    ce_sum = kl_sum = hit = 0.0
    preds = []
    for i in range(0, len(items), bs):
        chunk = items[i:i + bs]
        b = collate(chunk, pad_id)
        with torch.autocast(device.type, dtype=torch.bfloat16, enabled=amp):
            logits, _ = model(b["input_ids"].to(device), b["attention_mask"].to(device),
                              b["marker_pos"].to(device), b["marker_mask"].to(device), b["qtype"].to(device))
        logits = logits.float().cpu()
        mask = b["marker_mask"]
        lp = torch.log_softmax(logits.masked_fill(~mask, -1e4), -1)
        t = b["target"]
        ce = -(t * lp).sum(-1)
        ent = -(t * torch.log(t.clamp_min(1e-12))).sum(-1)
        ce_sum += float(ce.sum())
        kl_sum += float((ce - ent).sum())
        for r, it in enumerate(chunk):
            k = len(it["markers"])
            z = logits[r, :k]
            hit += int(int(z.argmax()) == it["label"])
            preds.append((it["qtype"], z.tolist(), it["target"]))
    model.train()
    n = max(1, len(items))
    return {"ce": ce_sum / n, "kl": kl_sum / n, "acc": hit / n}, preds


def save_checkpoint(model, cfg, base, out_dir, temps=None, meta=None):
    os.makedirs(out_dir, exist_ok=True)
    sd = {k: v.detach().half().contiguous().cpu() for k, v in model.state_dict().items()}
    save_file(sd, os.path.join(out_dir, "model.safetensors"))
    for sub in ("encoder", "tokenizer"):
        dst = os.path.join(out_dir, sub)
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(os.path.join(base, sub), dst)
    c = dict(cfg)
    c.pop("gradient_checkpointing", None)
    c.pop("max_tokens_per_batch", None)
    if temps is not None:
        c["fine_tuned"] = True
        c["model_name"] = "laya-pocketra-commander"
        c["temperature"] = temps
        c.pop("temperature_by_options", None)
    with open(os.path.join(out_dir, "rl_agent_config.json"), "w") as f:
        json.dump(c, f, indent=2)
    if meta:
        with open(os.path.join(out_dir, "checkpoint_meta.json"), "w") as f:
            json.dump(meta, f, indent=2)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=default_base(), help="PyTorch-Checkpoint (HF-Cache .../multilingual)")
    ap.add_argument("--data", default="build/laya/dataset", help="Ordner mit train.jsonl")
    ap.add_argument("--out", default="build/laya/train/run1")
    ap.add_argument("--device", default="mps", choices=["mps", "cpu"])
    ap.add_argument("--amp", default="none", choices=["none", "bf16"])
    ap.add_argument("--epochs", type=int, default=2)
    ap.add_argument("--micro-batch", type=int, default=8)
    ap.add_argument("--grad-accum", type=int, default=8, help="effektiver Stapel = micro * accum (Notebook 64)")
    ap.add_argument("--lr-encoder", type=float, default=2.5e-5)
    ap.add_argument("--lr-head", type=float, default=1.0e-4)
    ap.add_argument("--group-size", type=int, default=4)
    ap.add_argument("--sigma-start", type=float, default=0.4)
    ap.add_argument("--sigma-end", type=float, default=0.1)
    ap.add_argument("--freeze-embeddings", action="store_true")
    ap.add_argument("--limit-rows", type=int, default=0, help="nur so viele Entscheidungen (Teilmenge)")
    ap.add_argument("--val-items", type=int, default=600, help="Validierungs-Items fuer den Verlauf")
    ap.add_argument("--eval-every", type=int, default=100, help="Updates zwischen Validierungen")
    ap.add_argument("--max-minutes", type=float, default=90.0)
    ap.add_argument("--max-rss-gb", type=float, default=10.0)
    ap.add_argument("--save-every", type=int, default=100, help="Updates zwischen Checkpoints (0 = nur je Epoche)")
    ap.add_argument("--init-weights", default="", help="model.safetensors aus diesem Ordner statt aus --base")
    ap.add_argument("--seed", type=int, default=20260929)
    args = ap.parse_args()

    from transformers import AutoTokenizer
    from laya.agent import _fix_tokenizer_config
    from laya.common import build_model, proper_reward

    os.makedirs(args.out, exist_ok=True)
    fh = open(os.path.join(args.out, "train.log"), "a")
    metrics = open(os.path.join(args.out, "metrics.jsonl"), "a")
    log(fh, "Start: " + json.dumps(vars(args)))
    torch.manual_seed(args.seed)
    random.seed(args.seed)
    device = torch.device(args.device if args.device == "cpu" or torch.backends.mps.is_available() else "cpu")
    amp = args.amp == "bf16"

    base = args.base
    _fix_tokenizer_config(base)
    tok = AutoTokenizer.from_pretrained(os.path.join(base, "tokenizer"))
    with open(os.path.join(base, "rl_agent_config.json")) as f:
        cfg = json.load(f)
    cfg["max_len"], cfg["head_max_len"] = 1024, 256

    t_prep = time.time()
    all_items = build_items(os.path.join(args.data, "train.jsonl"), tok, cfg, args.limit_rows, args.seed)
    val_path = os.path.join(args.data, "test.jsonl")
    val_items = build_items(val_path, tok, cfg) if os.path.exists(val_path) else []
    random.Random(args.seed).shuffle(val_items)
    val_items = val_items[:args.val_items]
    log(fh, "Vorverarbeitung %.0f s: %d Trainings-Items, %d Validierungs-Items (Verlauf), Laenge Mittel %.0f Token"
        % (time.time() - t_prep, len(all_items), len(val_items),
           sum(len(i["ids"]) for i in all_items) / max(1, len(all_items))))

    order = list(range(len(all_items)))
    random.Random(20260922).shuffle(order)
    n_calib = min(400, len(all_items) // 10)
    calib_items = [all_items[i] for i in sorted(order[:n_calib])]
    train_items = [all_items[i] for i in sorted(order[n_calib:])]

    model = build_model(cfg, encoder_dir=os.path.join(base, "encoder"))
    model.load_state_dict(load_file(os.path.join(args.init_weights or base, "model.safetensors")), strict=True)
    model = model.float()
    model.encoder.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
    model.head_checkpointing = True
    if args.freeze_embeddings:
        emb = model.encoder.get_input_embeddings()
        emb.weight.requires_grad_(False)
    model.to(device)
    model.train()
    n_train = sum(p.numel() for p in model.parameters() if p.requires_grad)
    n_all = sum(p.numel() for p in model.parameters())
    log(fh, "Modell: %d Parameter, davon %d trainierbar, Geraet %s, AMP %s" % (n_all, n_train, device, args.amp))

    enc_params = [p for n, p in model.named_parameters() if n.startswith("encoder.") and p.requires_grad]
    head_params = [p for n, p in model.named_parameters() if not n.startswith("encoder.") and p.requires_grad]
    optimizer = torch.optim.AdamW([{"params": enc_params, "lr": args.lr_encoder},
                                   {"params": head_params, "lr": args.lr_head}], weight_decay=0.01)
    steps_per_epoch = math.ceil(len(train_items) / args.micro_batch)
    total_updates = max(1, (steps_per_epoch // args.grad_accum) * args.epochs)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=total_updates, eta_min=1e-6)

    pad_id = tok.pad_token_id
    v0, _ = eval_items(model, val_items, pad_id, device, amp) if val_items else ({}, None)
    log(fh, "Validierung vor dem Training: %s" % json.dumps(v0))
    metrics.write(json.dumps({"update": 0, "epoch": 0, "val": v0}) + "\n")
    metrics.flush()

    t0 = time.time()
    deadline = t0 + args.max_minutes * 60
    stop_reason = ""
    updates = 0
    peak_rss = peak_mps = 0.0
    epochs_done = 0.0
    for epoch in range(args.epochs):
        random.Random(42 + epoch).shuffle(train_items)
        progress = epoch / max(1, args.epochs - 1)
        sigma = args.sigma_start + (args.sigma_end - args.sigma_start) * progress
        run_loss = run_ce = 0.0
        run_n = 0
        optimizer.zero_grad(set_to_none=True)
        for step, b_idx in enumerate(range(0, len(train_items), args.micro_batch)):
            chunk = train_items[b_idx:b_idx + args.micro_batch]
            batch = collate(chunk, pad_id)
            with torch.autocast(device.type, dtype=torch.bfloat16, enabled=amp):
                logits, act = model(batch["input_ids"].to(device), batch["attention_mask"].to(device),
                                    batch["marker_pos"].to(device), batch["marker_mask"].to(device),
                                    batch["qtype"].to(device))
            logits = logits.float()
            mask = batch["marker_mask"].to(device)
            k = mask.sum(-1, keepdim=True).float()
            target = batch["target"].to(device)
            eps = torch.randn((args.group_size,) + logits.shape, device=device) * sigma * mask
            eps = (eps - eps.sum(-1, keepdim=True) / k) * mask
            z = logits.detach().unsqueeze(0) + eps
            q = torch.softmax(z.masked_fill(~mask, -1e4), -1)
            with torch.no_grad():
                r = proper_reward(q, target.unsqueeze(0), batch["qtype"].to(device), mask, w_sph=0.75, w_rps=1.0)
                adv = r - r.mean(0, keepdim=True)
                adv = adv / (adv.std() + 1e-6)
            logp = -(((z - logits.unsqueeze(0)) ** 2) * mask).sum(-1) / (2 * sigma ** 2)
            loss_rl = -(adv * logp).mean()
            loss_ce = -(target * torch.log_softmax(logits.masked_fill(~mask, -1e4), -1)).sum(-1).mean()
            loss = (loss_rl + loss_ce) / args.grad_accum + 0.0 * act.sum()
            loss.backward()
            run_loss += float(loss.item()) * args.grad_accum
            run_ce += float(loss_ce.item())
            run_n += 1
            last = (b_idx + args.micro_batch) >= len(train_items)
            if (step + 1) % args.grad_accum == 0 or last:
                torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1.0)
                optimizer.step()
                scheduler.step()
                optimizer.zero_grad(set_to_none=True)
                updates += 1
                if updates % 10 == 0:
                    peak_rss, peak_mps = max(peak_rss, rss_gb()), max(peak_mps, mps_gb())
                if updates % 25 == 0:
                    el = time.time() - t0
                    log(fh, "Epoche %d Update %d/%d | Verlust %.4f | CE %.4f | sigma %.2f | LR %.2e | %.1f min | RSS %.2f GB | MPS %.2f GB"
                        % (epoch + 1, updates, total_updates, run_loss / run_n, run_ce / run_n, sigma,
                           scheduler.get_last_lr()[0], el / 60, rss_gb(), mps_gb()))
                    metrics.write(json.dumps({"update": updates, "epoch": epoch + 1, "loss": run_loss / run_n,
                                              "ce": run_ce / run_n, "min": el / 60}) + "\n")
                    metrics.flush()
                    run_loss = run_ce = 0.0
                    run_n = 0
                if val_items and updates % args.eval_every == 0:
                    v, _ = eval_items(model, val_items, pad_id, device, amp)
                    log(fh, "  Validierung nach %d Updates: %s" % (updates, json.dumps(v)))
                    metrics.write(json.dumps({"update": updates, "epoch": epoch + 1, "val": v}) + "\n")
                    metrics.flush()
                if args.save_every and updates % args.save_every == 0:
                    save_checkpoint(model, cfg, base, os.path.join(args.out, "checkpoint_latest"),
                                    meta={"epoch": epoch + 1, "updates": updates})
                cur = max(rss_gb(), mps_gb()) if updates % 10 == 0 else 0.0
                if cur > args.max_rss_gb:
                    stop_reason = "Speicherdeckel %.1f GB erreicht (%.2f GB)" % (args.max_rss_gb, cur)
                if time.time() > deadline:
                    stop_reason = "Zeitdeckel %.0f min erreicht" % args.max_minutes
                if stop_reason:
                    epochs_done = epoch + (b_idx + len(chunk)) / len(train_items)
                    break
        if stop_reason:
            break
        epochs_done = epoch + 1
        log(fh, "=== Epoche %d fertig nach %.1f min ===" % (epoch + 1, (time.time() - t0) / 60))
        save_checkpoint(model, cfg, base, os.path.join(args.out, "checkpoint_latest"),
                        meta={"epoch": epoch + 1, "updates": updates})

    train_min = (time.time() - t0) / 60
    if stop_reason:
        log(fh, "Abbruch: " + stop_reason)


    _, calib_preds = eval_items(model, calib_items, pad_id, device, amp)
    temps = [1.2, 1.2, 1.2]
    try:
        for qt in range(3):
            sel = [(z, t) for q_type, z, t in calib_preds if q_type == qt]
            if sel:
                temps[qt] = fit_one_temp(sel)
    except Exception as e:
        log(fh, "Temperatur-Rueckfall: %s" % e)
    log(fh, "Temperaturen (choice, score, noul): %s" % [round(t, 3) for t in temps])
    v1, _ = eval_items(model, val_items, pad_id, device, amp) if val_items else ({}, None)
    log(fh, "Validierung nach dem Training (ohne Temperatur): %s" % json.dumps(v1))
    meta = {"epochs_done": round(epochs_done, 3), "updates": updates, "train_minutes": round(train_min, 1),
            "stop_reason": stop_reason, "train_items": len(train_items), "calib_items": len(calib_items),
            "peak_rss_gb": round(peak_rss, 2), "peak_mps_gb": round(peak_mps, 2), "val_before": v0,
            "val_after": v1, "temperatures": temps, "args": vars(args)}
    save_checkpoint(model, cfg, base, os.path.join(args.out, "final"), temps=temps, meta=meta)
    metrics.write(json.dumps({"final": meta}) + "\n")
    log(fh, "Fertig: %s" % os.path.join(args.out, "final"))


if __name__ == "__main__":
    main()
