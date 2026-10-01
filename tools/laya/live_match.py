#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import statistics
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import ai_tournament as T

KENNZAHLEN = ["lebend", "ertrag", "armee", "gebaut", "tuerme", "erster_angriff", "trupps",
              "gebaut_schiffe", "schiffe_versenkt", "t_gefunden", "spieler_lebend"]


def run(godot: str, karte: str, strategien: list[str], seed: int, ticks: int, staerke: str,
        credits: int, url: str, out: Path) -> list[dict]:
    args = [godot, "--headless", "--path", str(ROOT / "game"),
            "--quit-after", str(max(120000, ticks * 80)), "--",
            "--autostart", "--map", karte, "--ai", str(len(strategien)), "--seed", str(seed),
            "--starting-units", "none", "--credits", str(credits),
            "--test-ai", "--test-ai-until", str(ticks), "--ai-difficulty", staerke,
            "--ai-strategies", ",".join(strategien), "--game-speed", "4", "--ki-log"]
    if url:
        args += ["--commander-url", url]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=60 * 30)
    text = proc.stdout + proc.stderr
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{karte}_{staerke}_s{seed}.out").write_text(text)
    T.schreibe_kommandeur(text, out, karte, strategien, seed, staerke)
    rows = []
    for line in text.splitlines():
        m = T.ROW.match(line.strip())
        if m:
            d = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
            d.update(seed=str(seed), karte=karte)
            rows.append(d)
    if rows:
        with (out / f"{karte}_{staerke}_s{seed}.csv").open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=sorted({k for r in rows for k in r}))
            w.writeheader()
            w.writerows(rows)
    return rows


def auswertung_log(files: list[Path]) -> dict:
    n = ext = 0
    lat, doc = [], {}
    for p in files:
        for line in p.open():
            r = json.loads(line)
            if "summary" not in r:
                continue
            n += 1
            if r.get("source") == "external":
                ext += 1
                v = r.get("latency_ms", (r.get("directive") or {}).get("latency_ms"))
                if v is not None:
                    lat.append(float(v))
            d = (r.get("directive") or {}).get("doctrine", "?")
            doc[d] = doc.get(d, 0) + 1
    lat.sort()
    return {"zeilen": n, "external": ext, "anteil_external": round(ext / n, 3) if n else None,
            "latenz_median_ms": statistics.median(lat) if lat else None,
            "latenz_p95_ms": lat[int(0.95 * (len(lat) - 1))] if lat else None,
            "latenz_max_ms": lat[-1] if lat else None, "doktrin": doc}


def mittel(rows: list[dict]) -> dict:
    out = {"plaetze": len(rows)}
    for k in KENNZAHLEN:
        vals = [float(r[k]) for r in rows if r.get(k) not in (None, "")]
        if k == "erster_angriff":
            mit = [v for v in vals if v > 0]
            out[k] = round(sum(mit) / len(mit)) if mit else 0
            out["plaetze_mit_angriff"] = len(mit)
        else:
            out[k] = round(sum(vals) / len(vals), 2) if vals else None
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", default=T.GODOT_DEFAULT)
    ap.add_argument("--karte", required=True)
    ap.add_argument("--paare", default="normal:normal")
    ap.add_argument("--seeds", nargs="+", type=int, default=[1, 2])
    ap.add_argument("--ticks", type=int, default=12000)
    ap.add_argument("--staerke", default="hard")
    ap.add_argument("--credits", type=int, default=5000)
    ap.add_argument("--url", default="http://127.0.0.1:8765/decide", help="leer = Regel-Kommandeur")
    ap.add_argument("--out", required=True)
    ap.add_argument("--parallel", type=int, default=2)
    ap.add_argument("--regel", nargs="*", default=[], help="CSV eines Regel-Laufs zum Vergleich")
    args = ap.parse_args()
    out = Path(args.out)
    strat = args.paare.split(":")
    with ThreadPoolExecutor(args.parallel) as ex:
        res = list(ex.map(lambda s: run(args.godot, args.karte, strat, s, args.ticks, args.staerke,
                                        args.credits, args.url, out), args.seeds))
    rows = [r for rs in res for r in rs]
    logs = [out / f"{args.karte}_{'-'.join(strat)}_{args.staerke}_s{s}.jsonl" for s in args.seeds]
    bericht = {"karte": args.karte, "seeds": args.seeds, "url": args.url,
               "kommandeur": auswertung_log([p for p in logs if p.exists()]), "laya": mittel(rows)}
    if args.regel:
        regel_rows = [r for p in args.regel for r in T.lies_csv(Path(p))]
        bericht["regel"] = mittel(regel_rows)
    (out / f"bericht_{args.karte}.json").write_text(json.dumps(bericht, indent=1, ensure_ascii=False))
    print(json.dumps(bericht, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
