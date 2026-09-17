#!/usr/bin/env python3

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from rafmt import ContentSet, NameDatabase

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONTENT = ROOT / "content" / "ra"
DB = ROOT / "tools" / "rafmt" / "global_mix_database.dat"
OUT = ROOT / "game" / "assets" / "video"
DEFAULT_MOVIES = ["redintro", "prolog"]
MAPS = ROOT / "reference" / "OpenRA" / "mods" / "ra" / "maps"
MISSION_KEYS = ("BackgroundVideo", "BriefingVideo", "StartVideo", "WinVideo", "LossVideo")


FFMPEG = "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"
if not Path(FFMPEG).exists():
    FFMPEG = "ffmpeg"


def mission_videos(maps_dir: Path) -> list[str]:

    import re
    found: set[str] = set()
    for m in sorted(maps_dir.iterdir()) if maps_dir.is_dir() else []:
        for fname in ("rules.yaml", "map.yaml"):
            f = m / fname
            if not f.is_file():
                continue
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                for key in MISSION_KEYS:
                    mm = re.match(r"^\s*%s:\s*([^\s#]+)\s*$" % key, line)
                    if mm:
                        found.add(mm.group(1).lower().removesuffix(".vqa"))
    return sorted(found)
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--quality", type=int, default=3, help="Theora-Qualität 0..10 (3 ≈ halbe Größe von 7, auf 320×200 kaum sichtbar)")
    ap.add_argument("--start", type=float, default=0.0, help="Sekunden am Anfang abschneiden")
    ap.add_argument("--as-name", default="", help="Zieldateiname ohne .ogv (bei einem Film)")
    ap.add_argument("--missions", action="store_true", help="alle MissionData-Videos der Kampagnenkarten")
    ap.add_argument("--maps", type=Path, default=MAPS)
    ap.add_argument("--force", action="store_true", help="vorhandene .ogv neu wandeln")
    ap.add_argument("--scale", default="", help="ffmpeg-Skalierung, z. B. 640:400 (leer = Originalgröße)")
    ap.add_argument("names", nargs="*", default=DEFAULT_MOVIES)
    a = ap.parse_args()
    if a.missions:
        a.names = sorted(set(list(a.names if a.names != DEFAULT_MOVIES else []) + mission_videos(a.maps) + DEFAULT_MOVIES))
    cs = ContentSet(a.content, NameDatabase(DB))
    a.out.mkdir(parents=True, exist_ok=True)
    rc = 0
    missing: list[str] = []
    skipped: list[str] = []
    done = 0
    for n in a.names:
        name = n.lower().removesuffix(".vqa")
        dst_check = a.out / f"{a.as_name or name}.ogv"
        if dst_check.exists() and not a.force:
            skipped.append(name)
            continue
        hit = cs.find(name + ".vqa")
        if hit is None:
            print(f"{name}.vqa: in keinem MIX unter {a.content} (CD-MAIN.MIX mit movies1.mix nach content/ra/cd1/ kopieren)", file=sys.stderr)
            missing.append(name)
            rc = 1
            continue
        with tempfile.NamedTemporaryFile(suffix=".vqa", delete=False) as tmp:
            tmp.write(cs.read(name + ".vqa"))
            src = Path(tmp.name)
        dst = a.out / f"{a.as_name or name}.ogv"

        cmd = [FFMPEG, "-y", "-loglevel", "error", "-i", str(src)] + (["-ss", str(a.start)] if a.start > 0 else []) \
            + (["-vf", "scale=" + a.scale] if a.scale else []) \
            + ["-c:v", "libtheora", "-q:v", str(a.quality),
               "-pix_fmt", "yuv420p", "-c:a", "libvorbis", "-q:a", "1", "-ac", "1", str(dst)]
        r = subprocess.run(cmd)
        src.unlink(missing_ok=True)
        if r.returncode != 0:
            print(f"{name}: ffmpeg fehlgeschlagen", file=sys.stderr)
            rc = 1
            continue
        done += 1
        print(f"{name}.vqa → {dst.name} ({dst.stat().st_size // 1024} KB)")
    total = sum(f.stat().st_size for f in a.out.glob("*.ogv"))
    print(f"{done} gewandelt, {len(skipped)} vorhanden, {len(missing)} nicht im Inhalt: {' '.join(missing)}")
    print(f"{len(list(a.out.glob('*.ogv')))} Videos in {a.out}, zusammen {total / 1048576:.1f} MB")
    return rc


if __name__ == "__main__":
    sys.exit(main())
