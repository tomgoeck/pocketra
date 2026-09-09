#!/bin/sh
# macOS-Verteilfassung bauen: GDExtension → Godot-Export (Preset „macOS") → codesign (Developer ID)
# → Notarisierung → Stapling → DMG (Ziehen-in-Programme-Fenster) → Notarisierung/Stapling der DMG
# selbst. Gegenstück zu tools/win_build.sh, mit derselben Aufgabenteilung wie tools/ipa_build.sh bei
# iOS: Godot liefert nur das Rohbündel, xcrun/codesign signieren und reichen es extern bei Apple ein.
#
#   tools/mac_build.sh              # Extension + Export + Signieren + Notarisieren + DMG
#   tools/mac_build.sh --no-ext     # nur Export + Signieren (Extension bleibt, wie sie ist)
#   tools/mac_build.sh --no-notarize   # Bauprüfung: signiert, aber ohne Apple einzureichen
#                                       # (läuft NUR auf diesem Mac — jeder andere blockt Gatekeeper)
#
# Ergebnis:
#   game/bin/librasim.macos.arm64.dylib   die Extension (in rasim.gdextension eingetragen)
#   build/macos-dist/PocketRA.app         signiert, notarisiert, gestapelt
#   build/pocketra-macos.dmg              DMG mit PocketRA.app + Verknüpfung auf /Applications
#                                          (Toms Wunsch 2026-09-09: „Standardfenster", per
#                                          create-dmg — das Paket für GitHub/Server
#
# Voraussetzungen (einmalig):
#   1. Zertifikat „Developer ID Application" im Schlüsselbund (security find-identity -v -p basic)
#      — für dieses Projekt bereits vorhanden: „Developer ID Application: Tom Goeckeritz (9HW65ZP3L9)".
#   2. Notarisierungs-Zugang als Schlüsselbund-Profil hinterlegen (EINMALIG, interaktiv, braucht ein
#      App-spezifisches Passwort von appleid.apple.com — das kann dieses Skript nicht für Dich tun):
#        xcrun notarytool store-credentials pocketra-notary \
#            --apple-id tom@attomic.de --team-id 9HW65ZP3L9 --password <App-spezifisches-Passwort>
#      Profilname überschreibbar über die Umgebungsvariable NOTARY_PROFILE.
#   3. `create-dmg` (Homebrew: `brew install create-dmg`) — baut das Ziehen-in-Programme-Fenster
#      per Finder-Automatisierung, braucht darum eine angemeldete grafische Sitzung (läuft bei
#      Tom lokal, nicht headless/über SSH ohne Bildschirm).
#
# Verteilung ohne EA-Inhalte (Toms Entscheidung 2026-09-09, wie „Android Verteilung"/„Windows
# Verteilung"): das Preset „macOS" schließt assets/atlas|sfx|video aus, Atlanten/Sound/Filme lädt
# die App zur Laufzeit über „Spielinhalte einrichten" nach. Es gibt bewusst keine Mac-Vollfassung
# analog zum Preset „Windows" — Tom entwickelt/prüft direkt aus dem Quellbaum (README „Spiel am Mac
# starten und prüfen").
#
# Architektur: der Godot-4.7.2-Exporttemplate liefert die Engine nur als universelles Bündel
# (x86_64+arm64), das Preset setzt binary_format/architecture=universal entsprechend. Die eigene
# GDExtension (game/bin/librasim.macos.arm64.dylib) ist NUR arm64 — ein Intel-Mac lädt die Engine,
# aber nicht die Erweiterung, und die App bricht dort früh ab. Bekannte Lücke, nicht stillschweigend:
# auf einem Apple-Silicon-Mac (das Übliche seit 2020) läuft die Fassung einwandfrei.
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

# Hardened Runtime ist Pflicht für die Notarisierung (Apple lehnt sonst ab). Von innen nach außen
# signieren (--deep reicht bei einem einzelnen Framework, macht es hier trotzdem explizit): erst die
# GDExtension, dann das Bündel als Ganzes — sonst verwirft die äußere Signatur die innere.
codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/$DYLIB"
codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -5

# Notarisierung nimmt eine einzelne Datei (zip oder dmg) — dieselbe Prüf-/Fehlerkette für das
# App-Bündel (als Zip, Apple akzeptiert kein nacktes .app) und später die fertige DMG.
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
    # Für die Einreichung bei Apple: ditto statt zip erhält Resource-Forks/Attribute, wie Apple es
    # für notarytool empfiehlt. Das App-Bündel selbst wird gestapelt, das Zip war nur der Transport.
    SUBMIT_ZIP="$OUT/submit.zip"
    rm -f "$SUBMIT_ZIP"
    ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
    notarize_and_staple "$APP" "$SUBMIT_ZIP"
    rm -f "$SUBMIT_ZIP"
fi

# DMG mit Ziehen-in-Programme-Fenster (Toms Wunsch 2026-09-09, „Standardfenster") — create-dmg
# steuert dafür den Finder per AppleScript, braucht also eine angemeldete grafische Sitzung.
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
# create-dmg meldet in seltenen Fällen einen Fehlercode, obwohl die DMG fertig ist (bekannte
# Finder-Eigenheit der Bibliothek) — darum die Datei prüfen statt nur den Exit-Code.

# Die DMG selbst braucht eine eigene Signatur — ohne sie lehnt Gatekeepers Download-Prüfung
# (`spctl -a -t open --context context:primary-signature`) sie mit „no usable signature" ab, auch
# wenn Ticket und App-Signatur längst gültig sind (an genau der Stelle geprüft, s. project-docs).
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
if [ -z "$NO_NOTARIZE" ]; then
    notarize_and_staple "$DMG" "$DMG"
fi
ls -la "$DMG" | awk '{print "DMG: " $5/1e6 " MB"}'
