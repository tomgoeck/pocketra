#!/usr/bin/env python3


import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase

DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
DEFAULT_CONTENT = Path(__file__).resolve().parent.parent / "content" / "ra"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_list = sub.add_parser("list"); p_list.add_argument("mix", nargs="?")
    p_ext = sub.add_parser("extract"); p_ext.add_argument("-o", "--out", type=Path, required=True); p_ext.add_argument("names", nargs="+")
    p_find = sub.add_parser("find"); p_find.add_argument("names", nargs="+")
    a = ap.parse_args()

    cs = ContentSet(a.content, NameDatabase(DB))

    if a.cmd == "list":
        if a.mix:
            for m in cs.mixes:
                if m.path.name.lower() == a.mix.lower():
                    for e in sorted(m.entries, key=lambda e: (e.name or "", e.hash)):
                        print(f"{e.name or f'?{e.hash:08x}':20} {e.length:8}")
                    return 0
            print(f"{a.mix} nicht gefunden", file=sys.stderr); return 1
        for m in cs.mixes:
            print(f"{str(m.path.relative_to(cs.root)):28} {'verschlüsselt' if m.encrypted else 'klar':13} {len(m.entries):5} Dateien, {m.unresolved} unaufgelöst")
        return 0

    if a.cmd == "find":
        rc = 0
        for n in a.names:
            hit = cs.find(n)
            if hit: print(f"{n:20} {hit[0].path.relative_to(cs.root)}  ({hit[1].length} Bytes)")
            else: print(f"{n:20} —"); rc = 1
        return rc

    a.out.mkdir(parents=True, exist_ok=True)
    rc = 0
    for n in a.names:
        try:
            (a.out / n.lower()).write_bytes(cs.read(n)); print(n)
        except KeyError as ex:
            print(f"fehlt: {ex}", file=sys.stderr); rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
