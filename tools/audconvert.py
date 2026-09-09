#!/usr/bin/env python3


import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase

DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"
DEFAULT_CONTENT = Path(__file__).resolve().parent.parent / "content" / "ra"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "sfx"
DEFAULT_EXTRA = [Path(__file__).resolve().parent.parent / "reference" / "OpenRA" / "mods" / "ra" / "bits"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="+")
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--content", type=Path, default=DEFAULT_CONTENT)
    ap.add_argument("--extra-dir", type=Path, action="append", default=None,
                    help="Klartextverzeichnis, das vor den MIX-Archiven durchsucht wird")
    ap.add_argument("--music", action="store_true", help="MP3 statt WAV (für Musik: ~10× kleiner; Godot spielt MP3 nativ)")
    ap.add_argument("--diff-against", type=Path, default=None, metavar="DIR",
                    help="nur Clips ablegen, die sich byteweise von derselben Datei unter DIR unterscheiden")
    a = ap.parse_args()

    extra = a.extra_dir if a.extra_dir is not None else DEFAULT_EXTRA
    extra = [d for d in extra if d.is_dir()]
    db = NameDatabase(DB)
    cs = ContentSet(a.content, db)
    ref = ContentSet(a.diff_against, db) if a.diff_against else None

    def lookup(content: ContentSet, name: str):
        for d in extra:
            f = d / name
            if f.is_file():
                return f.read_bytes()
        try:
            return content.read(name)
        except KeyError:
            return None

    a.out.mkdir(parents=True, exist_ok=True)
    ok = 0
    missing: list[str] = []
    same = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name in a.names:
            raw = lookup(cs, name)
            if raw is None:
                missing.append(name)
                continue
            if ref is not None and raw == lookup(ref, name):
                same += 1
                continue
            src = Path(tmp) / (Path(name).stem + ".aud")
            src.write_bytes(raw)

            stem = Path(name).stem if name.lower().endswith(".aud") else name.replace(".", "_")
            dst = a.out / f"{stem}.{'mp3' if a.music else 'wav'}"


            codec = ["-c:a", "libmp3lame", "-b:a", "80k", "-ac", "1"] if a.music else []
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "wsaud", "-i", str(src), *codec, str(dst)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if dst.exists() and dst.stat().st_size > 44:
                ok += 1
            else:
                print(f"Konvertierung fehlgeschlagen: {name}", file=sys.stderr)
    if ref is not None:
        print(f"{same} Clips identisch mit {a.diff_against} (übersprungen)")
        if missing:
            print(f"{len(missing)} nicht in {a.content} (Rückfall auf die Grunddatei): {' '.join(missing)}")
    else:
        for name in missing:
            print(f"fehlt: {name}", file=sys.stderr)
    print(f"{ok}/{len(a.names) - same - (len(missing) if ref is not None else 0)} Sounds → {a.out}")
    return 0 if ok == len(a.names) - same - (len(missing) if ref is not None else 0) else 1


if __name__ == "__main__":
    sys.exit(main())
