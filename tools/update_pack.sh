#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
OUT="$ROOT/build/update"
PCK="$OUT/update.pck"
VERSION_JSON="$OUT/version.json"
CONF="$OUT/upload.conf"
PRESET="Update-Paket"

NOTES=""
MIN_SUPPORTED=""
MIN_SUPPORTED_PACK=""
DISABLED="false"
UPLOAD=""
VERSION_ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --notes) NOTES="$2"; shift 2 ;;
        --min-supported) MIN_SUPPORTED="$2"; shift 2 ;;
        --min-supported-pack) MIN_SUPPORTED_PACK="$2"; shift 2 ;;
        --disable) DISABLED="true"; shift ;;
        --upload) UPLOAD=1; shift ;;
        --version-only) VERSION_ONLY=1; shift ;;
        --slim) PRESET="Update-Paket schlank"; shift ;;
        *) echo "unbekannt: $1"; exit 1 ;;
    esac
done

mkdir -p "$OUT"
[ -f "$CONF" ] && . "$CONF"
BASE_URL=${BASE_URL:-https://example.invalid/pocketra}
DL_BASE=${DL_BASE:-https://github.com/tomgoeck/pocketra/releases/latest/download}

if [ -z "$VERSION_ONLY" ]; then
    "$G" --headless --path "$ROOT/game" --import 2>&1 | grep -c 'SCRIPT ERROR' \
        | sed 's/^/Skriptfehler beim Import: /'
    "$G" --headless --path "$ROOT/game" --export-pack "$PRESET" "$PCK" 2>&1 \
        | grep -E 'ERROR|error' | head -5 || true
fi
[ -f "$PCK" ] || { echo "kein Paket unter $PCK"; exit 1; }

SHA=$(shasum -a 256 "$PCK" | awk '{print $1}')
SIZE=$(wc -c < "$PCK" | tr -d ' ')
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)
LABEL="$(date +%Y-%m-%d)-$COMMIT"
PREV=0
if [ -f "$VERSION_JSON" ]; then
    PREV=$(python3 -c 'import json,sys;print(int(json.load(open(sys.argv[1])).get("pack_version",0)))' "$VERSION_JSON")
fi
LIVE=$(curl -sS --max-time 15 "$BASE_URL/version.json" 2>/dev/null | python3 -c 'import json,sys;print(int(json.load(sys.stdin).get("pack_version",0)))' 2>/dev/null || echo 0)
if [ "${LIVE:-0}" -gt "$PREV" ]; then
    echo "Zaehler: Server steht auf $LIVE, lokal $PREV — es gilt der Server."
    PREV=$LIVE
fi
if [ -n "$VERSION_ONLY" ]; then
    PACK_VERSION=$PREV
else
    PACK_VERSION=$((PREV + 1))
fi
MIN_EXT=$(sed -n 's/.*const char\* version() { return "\(.*\)".*/\1/p' "$ROOT/sim/src/world/wmath.cpp")
MIN_EXT=${MIN_EXT:-0}
APK_VERSION=$(sed -n 's/^version\/name="\(.*\)"/\1/p' "$ROOT/game/export_presets.cfg" | head -1)
APK_VERSION=${APK_VERSION:-0.5}
APK_SIZE=$([ -f "$ROOT/build/pocketra-dist.apk" ] && wc -c < "$ROOT/build/pocketra-dist.apk" | tr -d ' ' || echo 0)

WIN_EXE="$ROOT/build/pocketra-windows-dist.exe"
WINDOWS_EXE=""
WINDOWS_SIZE=0
if [ -f "$WIN_EXE" ]; then
    WINDOWS_EXE="$WIN_EXE"
    WINDOWS_SIZE=$(wc -c < "$WIN_EXE" | tr -d ' ')
fi

MAC_DMG="$ROOT/build/pocketra-macos.dmg"
MACOS_DMG=""
MACOS_SIZE=0
if [ -f "$MAC_DMG" ]; then
    MACOS_DMG="$MAC_DMG"
    MACOS_SIZE=$(wc -c < "$MAC_DMG" | tr -d ' ')
fi

WINDOWS_EXE="$WINDOWS_EXE" WINDOWS_SIZE="$WINDOWS_SIZE" \
MACOS_DMG="$MACOS_DMG" MACOS_SIZE="$MACOS_SIZE" \
PACK_VERSION="$PACK_VERSION" LABEL="$LABEL" BASE_URL="$BASE_URL" DL_BASE="$DL_BASE" SHA="$SHA" SIZE="$SIZE" \
MIN_EXT="$MIN_EXT" APK_VERSION="$APK_VERSION" NOTES="$NOTES" MIN_SUPPORTED="$MIN_SUPPORTED" \
MIN_SUPPORTED_PACK="$MIN_SUPPORTED_PACK" DISABLED="$DISABLED" \
APK_SIZE="$APK_SIZE" \
python3 - "$VERSION_JSON" <<'PY'
import json, os, sys
prev = {}
try:
    prev = json.load(open(sys.argv[1]))
except Exception:
    pass
base = os.environ["BASE_URL"].rstrip("/")
dl = os.environ["DL_BASE"].rstrip("/")
size = int(os.environ["APK_SIZE"]) or int(prev.get("apk_size", 0))
d = {
    "pack_version": int(os.environ["PACK_VERSION"]),
    "pack_label": os.environ["LABEL"],
    "pack_url": dl + "/update.pck",
    "pack_sha256": os.environ["SHA"],
    "pack_size": int(os.environ["SIZE"]),
    "min_extension": os.environ["MIN_EXT"],
    "apk_version": os.environ["APK_VERSION"],
    "apk_url": dl + "/pocketra-dist.apk",
    "apk_size": size,
    "notes": os.environ["NOTES"],
}
if os.environ.get("WINDOWS_EXE"):
    d["windows_url"] = dl + "/pocketra-windows-setup.exe"
    d["windows_size"] = int(os.environ["WINDOWS_SIZE"])
if os.environ.get("MACOS_DMG"):
    d["mac_url"] = dl + "/pocketra-macos.dmg"
    d["mac_size"] = int(os.environ["MACOS_SIZE"])
if os.environ["MIN_SUPPORTED"]:
    d["min_supported"] = os.environ["MIN_SUPPORTED"]
if os.environ["MIN_SUPPORTED_PACK"]:
    d["min_supported_pack"] = int(os.environ["MIN_SUPPORTED_PACK"])
d["disabled"] = os.environ["DISABLED"] == "true"
json.dump(d, open(sys.argv[1], "w"), indent=2, ensure_ascii=False)
print("version.json: Paket %d (%s), %.2f MB, min_extension %s, apk %s, disabled %s%s" % (
    d["pack_version"], d["pack_label"], d["pack_size"] / 1e6, d["min_extension"],
    d["apk_version"], d["disabled"],
    ", min_supported " + d["min_supported"] if "min_supported" in d else ""))
print("  APK: nur Verteilfassung %s (%s) - die Vollfassung wird nicht mehr verteilt" % (
    d["apk_url"].rsplit("/", 1)[-1], "%d MB" % round(size / 1e6) if size else "Groesse unbekannt"))
if "windows_url" in d:
    print("  Windows: %s (%.1f MB)" % (d["windows_url"].rsplit("/", 1)[-1], d["windows_size"] / 1e6))
if "mac_url" in d:
    print("  macOS: %s (%.1f MB)" % (d["mac_url"].rsplit("/", 1)[-1], d["mac_size"] / 1e6))
PY

if [ -n "$UPLOAD" ]; then
    TARGET=${POCKETRA_UPDATE_TARGET:-$TARGET}
    [ -n "$TARGET" ] || { echo "kein Upload-Ziel: POCKETRA_UPDATE_TARGET setzen oder $CONF anlegen"; exit 1; }
    rsync ${RSYNC_OPTS:--avz} "$VERSION_JSON" "$TARGET"
    echo "version.json hochgeladen nach $TARGET"
    echo "Hinweis: APK, Installer, DMG und update.pck gehen ueber tools/gh_release.sh zu GitHub,"
    echo "         nicht mehr auf den Server (Toms Entscheidung 2026-09-17)."
fi

ls -la "$OUT"
