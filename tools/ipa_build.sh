#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=/Applications/Godot.app/Contents/MacOS/Godot
TEAM=9HW65ZP3L9
PRESETS="$ROOT/game/export_presets.cfg"
BUNDLE=$(sed -n 's|^application/bundle_identifier="\(.*\)"|\1|p' "$PRESETS" | head -1)
[ -n "$BUNDLE" ] || { echo "Bundle-ID nicht im Preset gefunden ($PRESETS)"; exit 1; }
OUT="$ROOT/build/ios"
CONF="$ROOT/build/ios-upload.conf"
IPA="$OUT/pocketra.ipa"
CONFIG=Debug
EXPORT=--export-debug
INSTALL=""
UNSIGNED=""
DEVICE=""
STORE=""
VALIDATE=""
UPLOAD=""
UPLOAD_ONLY=""
BUMP=1
while [ $# -gt 0 ]; do
    arg=$1
    case "$arg" in
        --device) DEVICE=$2; shift ;;
        --install) INSTALL=1 ;;
        --release) CONFIG=Release; EXPORT=--export-release ;;
        --unsigned) UNSIGNED=1 ;;
        --store) STORE=1; CONFIG=Release; EXPORT=--export-release ;;
        --validate) STORE=1; VALIDATE=1; CONFIG=Release; EXPORT=--export-release ;;
        --upload) STORE=1; VALIDATE=1; UPLOAD=1; CONFIG=Release; EXPORT=--export-release ;;
        --upload-only) UPLOAD_ONLY=1; VALIDATE=1; UPLOAD=1; BUMP="" ;;
        --no-bump) BUMP="" ;;
        *) echo "unbekannt: $arg"; exit 1 ;;
    esac
    shift
done

if [ "$CONFIG" = Release ]; then TARGET=template_release; else TARGET=template_debug; fi

ASC_KEY_ID=""; ASC_ISSUER_ID=""; ASC_KEY_PATH=""
if [ -f "$CONF" ]; then . "$CONF"; fi
if [ -n "$ASC_KEY_ID" ] && [ -z "$ASC_KEY_PATH" ]; then
    ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
fi
if [ -n "$ASC_KEY_ID" ] && [ ! -f "$ASC_KEY_PATH" ]; then
    echo "Schluesseldatei fehlt: $ASC_KEY_PATH"; exit 1
fi
if [ -n "$VALIDATE" ] && [ -z "$UPLOAD" ] && [ -z "$ASC_KEY_ID" ]; then
    echo "--validate braucht einen App-Store-Connect-Schluessel: $CONF mit ASC_KEY_ID und"
    echo "ASC_ISSUER_ID anlegen (Anleitung im Kopf dieses Skripts). --upload geht auch ohne."
    exit 1
fi

APPLE_PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

xcb() {
    if [ -n "$ASC_KEY_ID" ] && [ -f "$ASC_KEY_PATH" ]; then
        PATH="$APPLE_PATH" xcodebuild "$@" -authenticationKeyPath "$ASC_KEY_PATH" \
            -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    else
        PATH="$APPLE_PATH" xcodebuild "$@"
    fi
}

upload_ipa() {
    [ -f "$IPA" ] || { echo "keine .ipa unter $IPA"; exit 1; }
    SHORT=$(sed -n 's|^application/short_version="\(.*\)"|\1|p' "$PRESETS" | head -1)
    BUILDNR=$(sed -n 's|^application/version="\(.*\)"|\1|p' "$PRESETS" | head -1)
    echo "TestFlight: $BUNDLE $SHORT ($BUILDNR) — $(du -m "$IPA" | cut -f1) MB"

    if [ -z "$ASC_KEY_ID" ]; then
        [ -n "$UPLOAD" ] || { echo "Ohne Schluessel gibt es keine getrennte Vorpruefung."; return 0; }
        echo "Kein Schluessel in $CONF — Upload ueber das in Xcode angemeldete Konto."
        [ -d "$OUT/pocketra.xcarchive" ] || { echo "kein Archiv unter $OUT/pocketra.xcarchive"; exit 1; }
        cat > "$OUT/upload_options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>$TEAM</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST
        if ! PATH="$APPLE_PATH" xcodebuild -exportArchive -archivePath "$OUT/pocketra.xcarchive" \
                -exportOptionsPlist "$OUT/upload_options.plist" -exportPath "$OUT/upload" \
                -allowProvisioningUpdates > "$OUT/upload.log" 2>&1; then
            tail -30 "$OUT/upload.log"
            echo "Upload fehlgeschlagen (ganzes Protokoll: $OUT/upload.log)."
            exit 1
        fi
        tail -5 "$OUT/upload.log"
        echo "Hochgeladen. Apple verarbeitet den Build ein paar Minuten, danach steht er in"
        echo "App Store Connect → TestFlight. Interne Tester bekommen ihn ohne Pruefung."
        return 0
    fi

    if ! xcrun altool --validate-app -f "$IPA" -t ios \
            --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" > "$OUT/validate.log" 2>&1; then
        tail -25 "$OUT/validate.log"
        echo "Vorpruefung fehlgeschlagen — NICHT hochgeladen (ganzes Protokoll: $OUT/validate.log)"
        exit 1
    fi
    tail -5 "$OUT/validate.log"
    if [ -n "$UPLOAD" ]; then
        if ! xcrun altool --upload-app -f "$IPA" -t ios \
                --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" > "$OUT/upload.log" 2>&1; then
            tail -25 "$OUT/upload.log"
            echo "Upload fehlgeschlagen (ganzes Protokoll: $OUT/upload.log). Nach einem Netzabbruch"
            echo "genuegt tools/ipa_build.sh --upload-only, die .ipa bleibt liegen."
            exit 1
        fi
        tail -5 "$OUT/upload.log"
        echo "Hochgeladen. Apple verarbeitet den Build ein paar Minuten, danach steht er in"
        echo "App Store Connect → TestFlight. Interne Tester bekommen ihn ohne Pruefung."
    fi
}

if [ -n "$UPLOAD_ONLY" ]; then
    upload_ipa
    exit 0
fi

if [ -n "$STORE" ] && [ -n "$BUMP" ]; then
    CUR=$(sed -n 's|^application/version="\([0-9]*\)"|\1|p' "$PRESETS" | head -1)
    [ -n "$CUR" ] || { echo "application/version nicht im Preset gefunden"; exit 1; }
    NEXT=$((CUR + 1))
    sed -i '' "s|^application/version=\"$CUR\"|application/version=\"$NEXT\"|" "$PRESETS"
    echo "Buildnummer $CUR → $NEXT (game/export_presets.cfg, bitte mitcommitten)"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
(cd "$ROOT/gdext" && scons platform=ios arch=arm64 target=$TARGET -j10 | tail -1)
"$G" --headless --path "$ROOT/game" --import 2>&1 | grep -c 'SCRIPT ERROR' | sed 's/^/Skriptfehler beim Import: /'
"$G" --headless --path "$ROOT/game" $EXPORT "iOS" "$IPA" 2>&1 | grep -E 'DONE.*export|^ERROR' | head -3

if [ -n "$UNSIGNED" ]; then
    PATH="$APPLE_PATH" xcodebuild -project "$OUT/pocketra.xcodeproj" -scheme pocketra \
        -configuration "$CONFIG" -destination 'generic/platform=iOS' \
        -archivePath "$OUT/pocketra.xcarchive" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
        CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" \
        archive | tail -3
    du -sh "$OUT/pocketra.xcarchive/Products/Applications/pocketra.app"
    exit 0
fi

xcb -project "$OUT/pocketra.xcodeproj" -scheme pocketra \
    -configuration "$CONFIG" -destination 'generic/platform=iOS' \
    -archivePath "$OUT/pocketra.xcarchive" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
    CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    archive | tail -3

if [ -n "$STORE" ]; then
    cat > "$OUT/store_options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>$TEAM</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST
    xcb -exportArchive -archivePath "$OUT/pocketra.xcarchive" \
        -exportOptionsPlist "$OUT/store_options.plist" -exportPath "$OUT" \
        -allowProvisioningUpdates | tail -3
else
    PATH="$APPLE_PATH" xcodebuild -exportArchive -archivePath "$OUT/pocketra.xcarchive" \
        -exportOptionsPlist "$OUT/pocketra/export_options.plist" -exportPath "$OUT" \
        -allowProvisioningUpdates | tail -3
fi
ls -la "$OUT"/*.ipa | awk '{print "IPA: " $9 " — " $5/1e6 " MB"}'

if [ -n "$VALIDATE$UPLOAD" ]; then
    upload_ipa
fi

if [ -n "$INSTALL" ]; then
    APP="$OUT/pocketra.xcarchive/Products/Applications/pocketra.app"
    LISTE=$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' | grep -v unavailable)
    if [ -n "$DEVICE" ]; then LISTE=$(printf '%s\n' "$LISTE" | grep -i "$DEVICE"); fi
    DEV=$(printf '%s\n' "$LISTE" \
        | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | head -1)
    [ -n "$DEV" ] || { echo "kein erreichbares iPhone/iPad (xcrun devicectl list devices)"; exit 1; }
    printf '%s\n' "$LISTE" | head -1 | sed 's/  .*//; s/^/Ziel: /'

    xcrun devicectl device install app --device "$DEV" "$APP" | tail -3
    xcrun devicectl device process launch --device "$DEV" "$BUNDLE" | tail -2
fi
