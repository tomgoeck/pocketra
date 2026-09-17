#!/usr/bin/env python3


import argparse
import hashlib
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rafmt import ContentSet, NameDatabase

ROOT = Path(__file__).resolve().parent.parent
NAME_DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"


SCORES_FAKE = {"hell226m.aud": "rabeep1.aud", "bigf226m.aud": "bleep5.aud"}


FREEWARE_MIX = [
    "conquer.mix", "temperat.mix", "snow.mix", "interior.mix",
    "lores.mix", "hires.mix", "local.mix", "sounds.mix", "speech.mix",
    "allies.mix", "russian.mix",
]


def classic_hash(name: str) -> int:

    name = name.upper()
    data = name.encode("ascii")
    pad = (-len(data)) % 4
    if pad:
        data += bytes(pad)
    acc = 0
    for i in range(0, len(data), 4):
        (chunk,) = struct.unpack_from("<I", data, i)
        acc = ((acc << 1) | (acc >> 31)) & 0xFFFFFFFF
        acc = (acc + chunk) & 0xFFFFFFFF
    return acc


def mix_bytes(files: dict[str, bytes]) -> bytes:

    entries = sorted(((classic_hash(n), d) for n, d in files.items()), key=lambda e: e[0])
    body = b""
    index = []
    for h, data in entries:
        index.append((h, len(body), len(data)))
        body += data
    out = struct.pack("<HI", len(entries), len(body))
    for h, off, ln in index:
        out += struct.pack("<III", h, off, ln)
    out += body
    return out


def write_mix(path: Path, files: dict[str, bytes]) -> None:
    path.write_bytes(mix_bytes(files))


def make_iso(work: Path, out_iso: Path, main_mix: Path) -> None:

    stage = work / "isoroot"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    shutil.copy(main_mix, stage / "MAIN.MIX")
    if out_iso.exists():
        out_iso.unlink()
    if shutil.which("hdiutil"):
        subprocess.run(["hdiutil", "makehybrid", "-iso", "-o", str(out_iso), str(stage)],
                       check=True, capture_output=True)
    elif shutil.which("mkisofs"):
        subprocess.run(["mkisofs", "-quiet", "-o", str(out_iso), str(stage)], check=True)
    elif shutil.which("xorrisofs"):
        subprocess.run(["xorrisofs", "-quiet", "-o", str(out_iso), str(stage)], check=True)
    else:
        sys.exit("Weder hdiutil noch mkisofs/xorrisofs gefunden — ISO-Attrappe nicht baubar")


def build_scores(content: Path) -> bytes:

    cs = ContentSet(content, NameDatabase(NAME_DB))
    files: dict[str, bytes] = {}
    for target, source in SCORES_FAKE.items():
        try:
            files[target] = cs.read(source)
        except KeyError:
            print(f"  fehlt: {source} (scores.mix-Attrappe wird kleiner)")
    if not files:
        return b"RA-TEST-SCORES" * 64
    return mix_bytes(files)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "build" / "testcontent"))
    ap.add_argument("--content", default=str(ROOT / "content" / "ra"))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    content = Path(args.content)

    zip_path = out / "freeware.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        n = 0
        for name in FREEWARE_MIX:
            src = content / name
            if not src.exists():
                print(f"  fehlt: {src}")
                continue
            z.write(src, name)
            n += 1
    sha1 = hashlib.sha1(zip_path.read_bytes()).hexdigest()
    print(f"freeware.zip: {n} Archive, {zip_path.stat().st_size / 1048576:.1f} MB, SHA-1 {sha1}")

    scores = build_scores(content)
    main_mix = out / "MAIN.MIX"
    write_mix(main_mix, {
        "movies1.mix": b"RA-TEST-MOVIES1" * 64,
        "scores.mix": scores,
    })
    iso = out / "allied.iso"
    make_iso(out, iso, main_mix)
    main_mix.unlink()
    print(f"allied.iso: {iso.stat().st_size / 1024:.0f} KB (MAIN.MIX mit movies1.mix + scores.mix, "
          f"{len(SCORES_FAKE)} Titel)")

    (out / "server.txt").write_text(
        f"sha1={sha1}\nfreeware=http://127.0.0.1:8124/freeware.zip\niso=http://127.0.0.1:8124/allied.iso\n")
    print(f"\n  (cd {out} && python3 -m http.server 8124 --bind 127.0.0.1 &)")


if __name__ == "__main__":
    main()
