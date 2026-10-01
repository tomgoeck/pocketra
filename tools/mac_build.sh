#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
OUT="$ROOT/build/macos-dist"
APP="$OUT/PocketRA.app"
DMG="$ROOT/build/pocketra-macos.dmg"
DYLIB=librasim.macos.arm64.dylib
IDENTITY=${MAC_SIGN_IDENTITY:-"Developer ID Application: Tom Goeckeritz (9HW65ZP3L9)"}
NOTARY_PROFILE=${NOTARY_PROFILE:-pocketra-notary}
ENTITLEMENTS="$ROOT/tools/mac_entitlements.plist"

NO_NOTARIZE=""
for arg in "$@"; do
    case "$arg" in
        --no-ext) NO_EXT=1 ;;
        --no-notarize) NO_NOTARIZE=1 ;;
        *) echo "unbekannt: $arg"; exit 1 ;;
    esac
done

if [ -z "$NO_EXT" ]; then
    (cd "$ROOT/gdext" && scons platform=macos arch=arm64 target=template_release -j10 | tail -1)
fi
[ -f "$ROOT/game/bin/$DYLIB" ] || { echo "keine $DYLIB — zuerst ohne --no-ext bauen"; exit 1; }

security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY" \
    || { echo "Zertifikat fehlt im Schlüsselbund: $IDENTITY"; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg fehlt — brew install create-dmg"; exit 1; }

"$G" --headless --path "$ROOT/game" --import 2>&1 | grep -c 'SCRIPT ERROR' \
    | sed 's/^/Skriptfehler beim Import: /'
rm -rf "$OUT"
mkdir -p "$OUT"
"$G" --headless --path "$ROOT/game" --export-release "macOS" "$APP" 2>&1 \
    | grep -E '^ERROR|DONE.*export' | head -5
[ -d "$APP" ] || { echo "Export fehlgeschlagen"; exit 1; }

codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/$DYLIB"
codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -5

notarize_and_staple() {
    TARGET="$1"; SUBMIT="$2"
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
        echo "Kein Notarisierungs-Profil „$NOTARY_PROFILE“ im Schlüsselbund — einmalig anlegen:"
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
        echo "      --apple-id tom@attomic.de --team-id 9HW65ZP3L9 --password <App-spezifisches Passwort>"
        echo "(Passwort erzeugen unter appleid.apple.com → Anmelden und Sicherheit → App-spezifische Passwörter)"
        exit 1
    }
    echo "reiche $(basename "$TARGET") bei Apple zur Notarisierung ein …"
    if ! xcrun notarytool submit "$SUBMIT" --keychain-profile "$NOTARY_PROFILE" \
            --wait > "$OUT/notarize.log" 2>&1; then
        tail -30 "$OUT/notarize.log"
        echo "Notarisierung fehlgeschlagen (ganzes Protokoll: $OUT/notarize.log)"
        exit 1
    fi
    tail -8 "$OUT/notarize.log"
    grep -q 'status: Accepted' "$OUT/notarize.log" || {
        echo "Apple hat NICHT angenommen — Protokoll: $OUT/notarize.log"; exit 1; }
    xcrun stapler staple "$TARGET"
}

if [ -n "$NO_NOTARIZE" ]; then
    echo "Nicht notarisiert (--no-notarize) — läuft NUR auf diesem Mac, Gatekeeper blockt sie überall"
    echo "sonst. Für eine echte Weitergabe ohne diese Fahne erneut bauen."
else
    SUBMIT_ZIP="$OUT/submit.zip"
    rm -f "$SUBMIT_ZIP"
    ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
    notarize_and_staple "$APP" "$SUBMIT_ZIP"
    rm -f "$SUBMIT_ZIP"
fi

rm -f "$DMG"
create-dmg \
    --volname "PocketRA" \
    --window-size 660 400 \
    --icon-size 100 \
    --icon "PocketRA.app" 160 185 \
    --hide-extension "PocketRA.app" \
    --app-drop-link 480 185 \
    "$DMG" \
    "$APP" \
    || [ -f "$DMG" ] || { echo "create-dmg fehlgeschlagen, keine DMG entstanden"; exit 1; }

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
if [ -z "$NO_NOTARIZE" ]; then
    notarize_and_staple "$DMG" "$DMG"
fi
ls -la "$DMG" | awk '{print "DMG: " $5/1e6 " MB"}'
