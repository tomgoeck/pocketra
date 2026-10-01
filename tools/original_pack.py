#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rafmt import ContentSet, NameDatabase

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
DB = TOOLS / "rafmt" / "global_mix_database.dat"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", type=Path, default=ROOT / "content" / "ra")
    ap.add_argument("--out", type=Path, default=ROOT / "build" / "original")
    ap.add_argument("--lang", default="", help="Sprachordner für die Filme (z. B. de); leer = sprachunabhängig")
    ap.add_argument("--no-music", action="store_true")
    ap.add_argument("--no-video", action="store_true")
    ap.add_argument("--quality", type=int, default=6, help="Theora-Qualität 0..10")
    a = ap.parse_args()
    cs = ContentSet(a.content, NameDatabase(DB))
    rc = 0
    if not a.no_music:
        scores = [m for m in cs.mixes if m.path.name.lower() == "scores.mix"]
        names = sorted({e.name for m in scores for e in m.entries if e.name and e.name.lower().endswith(".aud")})
        if not names:
            print("Keine scores.mix gefunden (CD-MAIN.MIX nach content/ra/ kopieren)", file=sys.stderr)
            rc = 1
        else:
            out = a.out / "music"
            out.mkdir(parents=True, exist_ok=True)
            cmd = [sys.executable, str(TOOLS / "audconvert.py"), "--content", str(a.content), "--music", *names, "-o", str(out)]
            rc |= subprocess.run(cmd).returncode
    if not a.no_video:
        movies = [m for m in cs.mixes if m.path.name.lower().startswith("movies")]
        names = sorted({e.name[:-4] for m in movies for e in m.entries if e.name and e.name.lower().endswith(".vqa")})
        if not names:
            print("Keine movies*.mix gefunden (CD-MAIN.MIX nach content/ra/ kopieren)", file=sys.stderr)
            rc = 1
        else:
            out = a.out / "video" / a.lang if a.lang else a.out / "video"
            cmd = [sys.executable, str(TOOLS / "vqa2ogv.py"), "--content", str(a.content), "--out", str(out), "--quality", str(a.quality), *names]
            rc |= subprocess.run(cmd).returncode
    print(f"Original-Inhalte unter {a.out}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
