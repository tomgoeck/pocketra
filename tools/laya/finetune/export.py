#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import time

import torch

KEEP_FP32 = ("scorer", "act_head", "type_emb")


def export_fp32(model_dir: str, path: str) -> None:
    from laya.agent import Agent

    agent = Agent(model_dir, compile=False, device="cpu")
    model = agent.model.float().eval()
    inputs = (torch.randint(0, 100, (1, 16), dtype=torch.long), torch.ones((1, 16), dtype=torch.long),
              torch.tensor([[1, 5]], dtype=torch.long), torch.tensor([[True, True]], dtype=torch.bool),
              torch.tensor([0], dtype=torch.long))
    dynamic_axes = {
        "input_ids": {0: "batch_size", 1: "seq_len"}, "attention_mask": {0: "batch_size", 1: "seq_len"},
        "marker_pos": {0: "batch_size", 1: "num_markers"}, "marker_mask": {0: "batch_size", 1: "num_markers"},
        "qtype": {0: "batch_size"}, "logits": {0: "batch_size", 1: "num_markers"}, "act_logits": {0: "batch_size"},
    }
    torch.onnx.export(model, inputs, path, export_params=True, opset_version=18, do_constant_folding=True,
                      input_names=["input_ids", "attention_mask", "marker_pos", "marker_mask", "qtype"],
                      output_names=["logits", "act_logits"], dynamic_axes=dynamic_axes, dynamo=False)


def node_scope(n) -> str:
    for p in n.metadata_props:
        if p.key in ("namespace", "pkg.torch.onnx.name_scopes"):
            return p.value
    return n.name


def quantize(fp32_path: str, out_path: str) -> dict:
    import onnx
    from onnxruntime.quantization import QuantType, quantize_dynamic

    model = onnx.load(fp32_path)
    del model.graph.value_info[:]
    exclude = [n.name for n in model.graph.node
               if n.op_type in ("MatMul", "Gather") and any(k in node_scope(n) for k in KEEP_FP32)]
    tmp = out_path + ".src.onnx"
    onnx.save(model, tmp, save_as_external_data=True, location=os.path.basename(tmp) + ".data")
    quantize_dynamic(model_input=tmp, model_output=out_path, op_types_to_quantize=["MatMul", "Gather"],
                     weight_type=QuantType.QInt8, per_channel=True, nodes_to_exclude=exclude)
    for f in (tmp, tmp + ".data"):
        if os.path.exists(f):
            os.remove(f)
    q = onnx.load(out_path, load_external_data=False)
    ops = {}
    for n in q.graph.node:
        ops[n.op_type] = ops.get(n.op_type, 0) + 1
    return {"excluded": len(exclude), "MatMulInteger": ops.get("MatMulInteger", 0),
            "MatMul_fp32": ops.get("MatMul", 0), "DequantizeLinear": ops.get("DequantizeLinear", 0)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True, help="Checkpoint-Ordner (train.py .../final)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tokenizer-from", default="",
                    help="tokenizer/ aus diesem Ordner (Standard: der Checkpoint)")
    ap.add_argument("--keep-fp32", action="store_true", help="FP32-Export behalten (model-fp32.onnx)")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    work = os.path.join(args.out, "_fp32")
    os.makedirs(work, exist_ok=True)
    fp32 = os.path.join(work, "model-fp32.onnx")
    t0 = time.time()
    export_fp32(args.model, fp32)
    t1 = time.time()
    info = quantize(fp32, os.path.join(args.out, "model.onnx"))
    t2 = time.time()
    if args.keep_fp32:
        for f in os.listdir(work):
            shutil.move(os.path.join(work, f), os.path.join(args.out, f))
    shutil.rmtree(work, ignore_errors=True)

    with open(os.path.join(args.model, "rl_agent_config.json")) as f:
        cfg = json.load(f)
    with open(os.path.join(args.out, "rl_agent_config.json"), "w") as f:
        json.dump(cfg, f, indent=2)
    tok_src = os.path.join(args.tokenizer_from or args.model, "tokenizer")
    tok_dst = os.path.join(args.out, "tokenizer")
    if os.path.exists(tok_dst):
        shutil.rmtree(tok_dst)
    os.makedirs(tok_dst)
    for name in ("tokenizer.json", "tokenizer_config.json"):
        shutil.copy(os.path.join(tok_src, name), os.path.join(tok_dst, name))
    size = os.path.getsize(os.path.join(args.out, "model.onnx")) / 1e6
    print(json.dumps({"export_s": round(t1 - t0, 1), "quantize_s": round(t2 - t1, 1), "model_mb": round(size, 1),
                      "temperature": cfg.get("temperature"), **info}, indent=1))


if __name__ == "__main__":
    main()
