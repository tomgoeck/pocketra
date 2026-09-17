#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
DIST=""
NOEXT=""
for arg in "$@"; do
    case "$arg" in
        --dist) DIST=1 ;;
        --no-ext) NOEXT=1 ;;
        *) echo "unbekannt: $arg"; exit 1 ;;
    esac
done
if [ -n "$DIST" ]; then
    PRESET="Windows Verteilung"
    OUT="$ROOT/build/windows-dist"
    SETUP="$ROOT/build/pocketra-windows-dist.exe"
else
    PRESET="Windows"
    OUT="$ROOT/build/windows"
    ZIP="$ROOT/build/pocketra-windows.zip"
fi
DLL=librasim.windows.x86_64.dll

if [ -n "$DIST" ]; then
    command -v makensis >/dev/null || { echo "makensis fehlt: brew install makensis"; exit 1; }
fi
if [ -z "$NOEXT" ]; then
    command -v x86_64-w64-mingw32-g++ >/dev/null || { echo "mingw-w64 fehlt: brew install mingw-w64"; exit 1; }
    (cd "$ROOT/gdext" && scons platform=windows arch=x86_64 target=template_debug use_mingw=yes -j6 | tail -1)
fi
[ -f "$ROOT/game/bin/$DLL" ] || { echo "keine $DLL"; exit 1; }

FREMD=$(x86_64-w64-mingw32-objdump -p "$ROOT/game/bin/$DLL" | sed -n 's/.*DLL Name: //p' \
    | grep -iE 'libgcc|libstdc|libwinpthread' || true)
[ -z "$FREMD" ] || { echo "FEHLER: DLL braucht Fremdbibliotheken:"; echo "$FREMD"; exit 1; }

"$G" --headless --path "$ROOT/game" --import 2>&1 | grep -c 'SCRIPT ERROR' | sed 's/^/Skriptfehler beim Import: /'
rm -rf "$OUT"
mkdir -p "$OUT"
"$G" --headless --path "$ROOT/game" --export-debug "$PRESET" "$OUT/pocketra.exe" 2>&1 \
    | grep -E '^ERROR|DONE.*savepack' | head -3
[ -f "$OUT/pocketra.exe" ] || { echo "Export fehlgeschlagen"; exit 1; }

if [ -n "$DIST" ]; then
    NSI="$OUT/installer.nsi"
    VERSION=$(sed -n 's/^version\/name="\(.*\)"/\1/p' "$ROOT/game/export_presets.cfg" | head -1)
    sed -e "s|__OUTFILE__|$SETUP|" -e "s|__SRCDIR__|$OUT|" -e "s|__VERSION__|${VERSION:-0.0}|" \
        "$ROOT/tools/win_installer.nsi.tmpl" > "$NSI"
    rm -f "$SETUP"
    makensis -V2 "$NSI" | tail -10
    [ -f "$SETUP" ] || { echo "makensis hat keinen Installer erzeugt"; exit 1; }
    ls -la "$SETUP" | awk '{print "Installer (" p "): " $5/1e6 " MB"}' p="$PRESET"
else
    rm -f "$ZIP"
    (cd "$OUT" && zip -q -r -9 "$ZIP" pocketra.exe pocketra.pck "$DLL")
    ls -la "$ZIP" | awk '{print "ZIP (" p "): " $5/1e6 " MB"}' p="$PRESET"
fi
