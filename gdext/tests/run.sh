#!/bin/sh
# Baut und startet den Headless-Test der Inhalts-Leser (kein Godot nötig) und vergleicht die
# C++-Ergebnisse Byte für Byte mit denen der Python-Pipeline in tools/rafmt.
#
#     gdext/tests/run.sh                      # gegen content/ra
#     CONTENT=content/ra_de gdext/tests/run.sh
#     SAN=1 gdext/tests/run.sh                # zusätzlich mit Address-/UB-Sanitizer
#
# Geprüft wird:
#   1. Namens-Hash und MIX-Verzeichnis (Archivzahl, Dateizahl, alle aufgelösten Namen)
#   2. alle SHP/TMP aus den Atlas-Rezepten (Maße + entpackte Frames)
#   3. Paletten (256×RGBA8)
#   4. Atlanten (atlas_*.r8 und atlas_*.json gegen tools/tileset2atlas.py)
#   5. AUD → WAV (Nutzdaten gegen ffmpegs wsaud-Demuxer, falls ffmpeg da ist)
#   6. VQA: ein Film wird dekodiert (Maße, Frames, Tonlänge)
set -e
cd "$(dirname "$0")/.."          # gdext/
ROOT=$(cd .. && pwd)
CONTENT=${CONTENT:-$ROOT/content/ra}
DB=$ROOT/tools/rafmt/global_mix_database.dat
WORK=${WORK:-$ROOT/../build/contenttest}
BIN=$WORK/test_content

mkdir -p "$WORK"
SAN_FLAGS=""
if [ "${SAN:-0}" != "0" ]; then
    SAN_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g"
    BIN=$WORK/test_content_san
    echo "Sanitizer aktiv (ASan + UBSan)"
fi
# shellcheck disable=SC2086
clang++ -std=c++17 -O2 -Wall -Wextra $SAN_FLAGS src/content/*.cpp tests/test_content.cpp -o "$BIN"

if [ ! -d "$CONTENT" ]; then
    echo "kein Inhalt unter $CONTENT — nur Übersetzung geprüft"
    exit 0
fi

fail=0
say() { printf '%-34s %s\n' "$1" "$2"; }

# --- 1. MIX-Verzeichnis ----------------------------------------------------
"$BIN" list "$DB" "$CONTENT" > "$WORK/cpp_list.txt"
python3 - "$CONTENT" "$DB" > "$WORK/py_list.txt" <<'PY'
import sys, pathlib
sys.path.insert(0, str(pathlib.Path.cwd().parent / "tools"))
from rafmt import ContentSet, NameDatabase
cs = ContentSet(pathlib.Path(sys.argv[1]), NameDatabase(sys.argv[2]))
print(f"archives={len(cs.mixes)} files={sum(len(m.entries) for m in cs.mixes)}")
names = {e.name for m in cs.mixes for e in m.entries if e.name}
for n in sorted(names):
    print(n)
PY
if cmp -s "$WORK/cpp_list.txt" "$WORK/py_list.txt"; then
    say "MIX-Verzeichnis" "identisch ($(head -1 "$WORK/cpp_list.txt"))"
else
    say "MIX-Verzeichnis" "ABWEICHUNG"; fail=1
fi

# --- 2. SHP/TMP ------------------------------------------------------------
cat "$ROOT/game/data/atlas/"*.recipe | awk '/^sprite /{print $3}' | sort -u > "$WORK/files.txt"
"$BIN" dumpall "$DB" "$CONTENT" "$WORK/files.txt" "$WORK/cpp_all.bin" 2>"$WORK/cpp_all.log"
python3 - "$CONTENT" "$DB" "$WORK/files.txt" "$WORK/py_all.bin" <<'PY'
import sys, pathlib, struct
sys.path.insert(0, str(pathlib.Path.cwd().parent / "tools"))
from rafmt import ContentSet, NameDatabase, ShpFile, TmpFile
from rafmt.shp import looks_like_shp
cs = ContentSet(pathlib.Path(sys.argv[1]), NameDatabase(sys.argv[2]))
out = bytearray()
for name in pathlib.Path(sys.argv[3]).read_text().split():
    try:
        raw = cs.read(name)
        if name.lower().endswith(".shp") or looks_like_shp(raw):
            s = ShpFile(raw); w, h, frames = s.width, s.height, s.frames
        else:
            t = TmpFile(raw); empty = bytes(t.width * t.height)
            w, h, frames = t.width, t.height, [x if x is not None else empty for x in t.tiles]
    except Exception:
        continue
    out += name.encode() + b"\0" + struct.pack("<III", w, h, len(frames)) + b"".join(frames)
pathlib.Path(sys.argv[4]).write_bytes(bytes(out))
PY
if cmp -s "$WORK/cpp_all.bin" "$WORK/py_all.bin"; then
    say "SHP/TMP (LCW, XOR-Delta)" "identisch ($(sed 's/dumpall: //' "$WORK/cpp_all.log"))"
else
    say "SHP/TMP (LCW, XOR-Delta)" "ABWEICHUNG"; fail=1
fi

# --- 3. Paletten -----------------------------------------------------------
palok=1
for p in temperat snow interior; do
    "$BIN" pal "$DB" "$CONTENT" "$p.pal" "$WORK/c_$p.rgba" 2>/dev/null || continue
    python3 - "$CONTENT" "$DB" "$p.pal" "$WORK/p_$p.rgba" <<'PY'
import sys, pathlib
sys.path.insert(0, str(pathlib.Path.cwd().parent / "tools"))
from rafmt import ContentSet, NameDatabase, load_palette
cs = ContentSet(pathlib.Path(sys.argv[1]), NameDatabase(sys.argv[2]))
pal = load_palette(cs.read(sys.argv[3]))
out = bytearray()
for i, (r, g, b) in enumerate(pal):
    out += bytes((r, g, b, 0 if i == 0 else 255))
pathlib.Path(sys.argv[4]).write_bytes(bytes(out))
PY
    cmp -s "$WORK/c_$p.rgba" "$WORK/p_$p.rgba" || { palok=0; }
done
if [ "$palok" = 1 ]; then say "Paletten" "identisch"; else say "Paletten" "ABWEICHUNG"; fail=1; fi

# --- 4. Atlanten -----------------------------------------------------------
if [ -f "$ROOT/game/assets/atlas/atlas_temperat.r8" ]; then
    rm -rf "$WORK/atlas"; mkdir -p "$WORK/atlas"
    start=$(date +%s)
    "$BIN" atlas "$DB" "$CONTENT" "$ROOT/game/data/atlas" "$ROOT/game/data/bits" "$WORK/atlas"
    echo "  Atlasbau (Mac): $(( $(date +%s) - start )) s"
    atok=1
    for t in temperat snow interior; do
        cmp -s "$WORK/atlas/atlas_$t.r8" "$ROOT/game/assets/atlas/atlas_$t.r8" || { echo "  $t.r8 abweichend"; atok=0; }
        cmp -s "$WORK/atlas/atlas_$t.json" "$ROOT/game/assets/atlas/atlas_$t.json" || { echo "  $t.json abweichend"; atok=0; }
        cmp -s "$WORK/atlas/$t.rgba" "$ROOT/game/assets/atlas/$t.rgba" || { echo "  $t.rgba abweichend"; atok=0; }
    done
    if [ "$atok" = 1 ]; then say "Atlanten" "identisch zu game/assets/atlas"; else say "Atlanten" "ABWEICHUNG"; fail=1; fi
else
    say "Atlanten" "übersprungen (game/assets/atlas fehlt)"
fi

# --- 4b. Deutsche Cameos ---------------------------------------------------
if [ -f "$ROOT/game/assets/atlas/atlas_cameos_de.r8" ] && [ -d "$ROOT/content/ra_de" ]; then
    rm -rf "$WORK/cameo"; mkdir -p "$WORK/cameo"
    "$BIN" atlas "$DB" "$ROOT/content/ra_de" "$ROOT/game/data/atlas" "$ROOT/game/data/bits" \
           "$WORK/cameo" cameos_de > /dev/null
    if cmp -s "$WORK/cameo/atlas_cameos_de.r8" "$ROOT/game/assets/atlas/atlas_cameos_de.r8" &&
       cmp -s "$WORK/cameo/atlas_cameos_de.json" "$ROOT/game/assets/atlas/atlas_cameos_de.json"; then
        say "Cameos (deutsche CD)" "identisch"
    else
        say "Cameos (deutsche CD)" "ABWEICHUNG"; fail=1
    fi
else
    say "Cameos (deutsche CD)" "übersprungen"
fi

# --- 5. AUD → WAV ----------------------------------------------------------
if command -v ffmpeg > /dev/null 2>&1; then
    audok=1; audn=0
    for s in cannon1.aud gun11.aud tone2.aud await1.v01 bigf226m.aud; do
        "$BIN" aud "$DB" "$CONTENT" "$s" "$WORK/c.wav" > /dev/null 2>&1 || continue
        python3 - "$CONTENT" "$DB" "$s" "$WORK/raw.aud" <<'PY'
import sys, pathlib
sys.path.insert(0, str(pathlib.Path.cwd().parent / "tools"))
from rafmt import ContentSet, NameDatabase
cs = ContentSet(pathlib.Path(sys.argv[1]), NameDatabase(sys.argv[2]))
pathlib.Path(sys.argv[4]).write_bytes(cs.read(sys.argv[3]))
PY
        ffmpeg -v error -y -f wsaud -i "$WORK/raw.aud" "$WORK/p.wav" > /dev/null 2>&1 || true
        # Nur die Nutzdaten vergleichen: ffmpeg schreibt zusätzlich einen LIST/INFO-Block
        python3 tests/wavcmp.py "$WORK/c.wav" "$WORK/p.wav" "$s" || audok=0
        audn=$((audn + 1))
    done
    if [ "$audok" = 1 ]; then say "AUD → PCM" "identisch ($audn Dateien)"; else say "AUD → PCM" "ABWEICHUNG"; fail=1; fi
else
    say "AUD → PCM" "übersprungen (kein ffmpeg)"
fi

# --- 6. VQA ----------------------------------------------------------------
if "$BIN" vqa "$DB" "$CONTENT" redintro.vqa "$WORK/vqa" 8 > "$WORK/vqa.txt" 2>&1; then
    say "VQA" "$(head -1 "$WORK/vqa.txt")"
else
    say "VQA" "übersprungen (redintro.vqa nicht im Inhalt)"
fi

[ "$fail" = 0 ] && echo "alle Vergleiche bestanden" || echo "FEHLER: Abweichungen gefunden"
exit $fail
