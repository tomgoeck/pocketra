#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
EMSDK_DIR="${EMSDK_DIR:-}"
if [[ -z "$EMSDK_DIR" ]]; then
  for candidate in "$PWD/build/emsdk" "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/../build/emsdk"; do
    if [[ -f "$candidate/emsdk_env.sh" ]]; then EMSDK_DIR="$candidate"; break; fi
  done
fi
BUILD_EXT=1
DO_FULL=1
DO_DEMO=1
for arg in "$@"; do
  case "$arg" in
    --no-ext) BUILD_EXT=0 ;;
    --full)   DO_DEMO=0 ;;
    --demo)   DO_FULL=0 ;;
    *) echo "Unbekanntes Argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ $BUILD_EXT -eq 1 ]]; then
  if [[ ! -f "$EMSDK_DIR/emsdk_env.sh" ]]; then
    echo 'Emscripten fehlt. emsdk installieren und aktivieren; EMSDK_DIR setzen.' >&2
    exit 1
  fi
  source "$EMSDK_DIR/emsdk_env.sh"
  rm -rf gdext/godot-cpp/gen
  (cd gdext && scons platform=web arch=wasm32 target=template_release threads=no -j8)
  rm -rf gdext/godot-cpp/gen
fi

if [[ -f game/assets/atlas/atlas_temperat.json ]]; then
  python3 tools/web_atlas.py || echo 'Hinweis: web_atlas.py übersprungen' >&2
fi

mkdir -p website/play/demo website/play/full
"$GODOT_BIN" --headless --path game --import

if [[ $DO_FULL -eq 1 ]]; then
  "$GODOT_BIN" --headless --path game --export-release 'Web Vollversion' ../website/play/full/index.html
fi
if [[ $DO_DEMO -eq 1 ]]; then
  "$GODOT_BIN" --headless --path game --export-release 'Web Demo' ../website/play/demo/index.html
fi

echo
echo 'Fertig. Lokal ansehen:'
echo '  python3 -m http.server 8097 --bind 127.0.0.1 --directory website'
echo '  http://127.0.0.1:8097'
