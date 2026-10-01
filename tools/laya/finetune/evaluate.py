#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from laya_core import LayaModel


def dist_of(ans, q):
    if q["type"] == "choice":
        return [float(ans["probabilities"][k]) for k in q["criteria"].keys()]
    if q["type"] == "noul":
        p = float(ans["noul"])
        return [1.0 - p, p]
    return [float(ans["probabilities"][str(i)]) for i in range(len(q["criteria"]))]


def gold_dist(g, q):
    if q["type"] == "choice":
        t = [float(g["probabilities"].get(k, 0.0)) for k in q["criteria"].keys()]
    elif q["type"] == "noul":
        t = [float(g["probabilities"]["false"]), float(g["probabilities"]["true"])]
    else:
        t = [float(g["probabilities"].get(str(i), 0.0)) for i in range(len(q["criteria"]))]
    s = sum(t)
    return [x / s for x in t]


def evaluate(model_dir: str, rows, batch: int = 16, threads: int = 0):
    m = LayaModel(model_dir, threads=threads)
    acc = defaultdict(lambda: {"n": 0, "hit": 0, "ce": 0.0, "kl": 0.0, "tv": 0.0, "mae": 0.0})
    pred_hist = defaultdict(lambda: defaultdict(int))
    gold_hist = defaultdict(lambda: defaultdict(int))
    pairs = defaultdict(list)
    t0 = time.time()
    for i in range(0, len(rows), batch):
        chunk = rows[i:i + batch]
        enc = []
        all_rows = []
        for r in chunk:
            state, qs = json.loads(r["state"]), json.loads(r["questions"])
            ids, internal, seqs = m.encode_request(state, qs)
            enc.append((r, qs, ids, internal, seqs, len(all_rows)))
            all_rows.extend(seqs)
        logits, act = m.run_rows(all_rows)
        for r, qs, ids, internal, seqs, off in enc:
            answers = m.decode(logits, act, seqs, ids, internal, off)
            gold = json.loads(r["gold"])
            for qid in ids:
                if qid not in gold:
                    continue
                q = qs[qid]
                p = dist_of(answers[qid], q)
                t = gold_dist(gold[qid], q)
                a = acc[qid]
                a["n"] += 1
                pa, ta = max(range(len(p)), key=p.__getitem__), max(range(len(t)), key=t.__getitem__)
                a["hit"] += int(pa == ta)
                ce = -sum(ti * math.log(max(pi, 1e-12)) for ti, pi in zip(t, p))
                ent = -sum(ti * math.log(ti) for ti in t if ti > 0)
                a["ce"] += ce
                a["kl"] += ce - ent
                a["tv"] += 0.5 * sum(abs(ti - pi) for ti, pi in zip(t, p))
                if q["type"] == "score":
                    k = len(p) - 1
                    a["mae"] += abs(sum(j * x for j, x in enumerate(p)) - sum(j * x for j, x in enumerate(t))) / k
                keys = list(q["criteria"].keys()) if q["type"] == "choice" else (
                    ["false", "true"] if q["type"] == "noul" else [str(j) for j in range(len(p))])
                pairs[qid].append((keys[pa], keys[ta]))
                pred_hist[qid][keys[pa]] += 1
                gold_hist[qid][keys[ta]] += 1
    out = {}
    tot = {"n": 0, "hit": 0, "ce": 0.0, "kl": 0.0}
    for qid, a in acc.items():
        n = max(1, a["n"])
        out[qid] = {"n": a["n"], "argmax_acc": round(a["hit"] / n, 4), "ce": round(a["ce"] / n, 4),
                    "kl": round(a["kl"] / n, 4), "tv": round(a["tv"] / n, 4),
                    "pred": dict(pred_hist[qid]), "rule": dict(gold_hist[qid])}


        maj = max(gold_hist[qid], key=gold_hist[qid].get)
        rest = [(p, g) for p, g in pairs[qid] if g != maj]
        out[qid]["majority"] = maj
        out[qid]["majority_acc"] = round(gold_hist[qid][maj] / n, 4)
        out[qid]["n_non_majority"] = len(rest)
        out[qid]["acc_non_majority"] = round(sum(p == g for p, g in rest) / len(rest), 4) if rest else None
        if a["mae"]:
            out[qid]["score_mae"] = round(a["mae"] / n, 4)
        for k in tot:
            tot[k] += a[k]
    n = max(1, tot["n"])
    out["_all"] = {"n": tot["n"], "argmax_acc": round(tot["hit"] / n, 4), "ce": round(tot["ce"] / n, 4),
                   "kl": round(tot["kl"] / n, 4), "seconds": round(time.time() - t0, 1)}
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", required=True)
    ap.add_argument("--model", action="append", required=True)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--threads", type=int, default=0, help="ORT-Threads (0 = Vorgabe)")
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    rows = [json.loads(line) for line in open(args.data)]
    if args.limit:
        rows = rows[:args.limit]
    res = {}
    for md in args.model:
        res[md] = evaluate(md, rows, threads=args.threads)
        print(json.dumps({md: res[md]}, indent=1), flush=True)
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w") as f:
            json.dump(res, f, indent=1)


if __name__ == "__main__":
    main()
