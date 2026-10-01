#!/usr/bin/env python3

import argparse
import hashlib
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = "soyelmismo/laya-multilingual-onnx"
REVISION = "0966c4fa58da6878b39e7e14cb5e93313b82d828"


COMMON = [
    ("tokenizer/tokenizer.json", "tokenizer/tokenizer.json",
     "609d8f4c067cd3950f88594c5a802616cea245823836ef5848ee4fc40aab5b6f"),
    ("tokenizer/tokenizer_config.json", "tokenizer/tokenizer_config.json", None),
    ("rl_agent_config.json", "rl_agent_config.json", None),
]
VARIANTS = {
    "int8": ("model-int8.onnx", "d389d2304822a59569387e257067360a84e016aed43b407f1cfde87dadb7e485"),
    "fp32": ("model-fp32.onnx", "7147e7651132da5ee2c1791c52ea25d4b9f7d9d187b15b60b1373467a436d626"),
}


def main_checkout() -> Path:

    here = Path(__file__).resolve().parent
    try:
        common = subprocess.check_output(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd=here, text=True, stderr=subprocess.DEVNULL).strip()
        return Path(common).parent
    except Exception:
        return here.parents[1]


def default_dir(variant: str) -> Path:
    return main_checkout() / "build" / "laya" / f"multilingual-{variant}"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch(src: str, dst: Path, digest) -> None:
    if dst.exists() and (digest is None or sha256(dst) == digest):
        print(f"vorhanden  {dst}")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://huggingface.co/{REPO}/resolve/{REVISION}/{src}"
    tmp = dst.with_suffix(dst.suffix + ".part")
    print(f"lade       {url}")
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        while True:
            block = r.read(1 << 20)
            if not block:
                break
            f.write(block)
            done += len(block)
            if total and sys.stdout.isatty():
                print(f"\r  {done / 1e6:8.1f} / {total / 1e6:.1f} MB", end="", flush=True)
    if sys.stdout.isatty():
        print()
    if digest is not None:
        got = sha256(tmp)
        if got != digest:
            tmp.unlink()
            raise SystemExit(f"Pruefsumme falsch fuer {src}: {got} statt {digest}")
    tmp.rename(dst)
    print(f"fertig     {dst}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--variant", choices=sorted(VARIANTS), default="int8")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()
    out = args.out or default_dir(args.variant)
    for src, name, digest in COMMON:
        fetch(src, out / name, digest)
    src, digest = VARIANTS[args.variant]
    fetch(src, out / "model.onnx", digest)
    print(f"\nCheckpoint liegt in {out}\nDienst: LAYA_MODEL_DIR={out} (Standard, wenn nichts gesetzt ist)")


if __name__ == "__main__":
    main()
