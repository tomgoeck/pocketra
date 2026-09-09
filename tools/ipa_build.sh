#!/bin/sh
# iOS-Fassung bauen: GDExtension (statisches .xcframework) → Godot-Export (Xcode-Projekt) →
# xcodebuild (signiertes Archiv) → .ipa. Optional aufs angeschlossene Gerät spielen oder als
# TestFlight-Fassung an App Store Connect schicken.
#
#   tools/ipa_build.sh                # Debug-Bau, signiert fuer das eigene Geraet
#   tools/ipa_build.sh --install      # zusaetzlich aufs angeschlossene iPad spielen und starten
#   tools/ipa_build.sh --release      # Release-Bau (Extension ebenfalls template_release)
#   tools/ipa_build.sh --unsigned     # nur Baupruefung (ohne Signierung, laeuft auf keinem Geraet)
#   tools/ipa_build.sh --store        # Release + App-Store-Signierung → hochladbare .ipa
#   tools/ipa_build.sh --validate     # --store und die .ipa von Apple vorpruefen lassen
#   tools/ipa_build.sh --upload       # --store, vorpruefen UND zu TestFlight hochladen
#   tools/ipa_build.sh --upload-only  # nur die vorhandene build/ios/*.ipa erneut hochladen
#   tools/ipa_build.sh --upload --no-bump   # ohne die Buildnummer hochzuzaehlen (Wiederholversuch)
#
# Anders als tools/apk_build.sh baut dieses Skript aus dem AKTUELLEN Arbeitsbaum (kein eigener
# Worktree): die iOS-Fassung steckt noch in der Entwicklung, und der Xcode-Umweg soll direkt an dem
# Stand hängen, den man gerade prüft.
#
# Signierung: automatisch über Xcode mit der Identität „Apple Development: tom@attomic.de
# (HF45S99Z5G)" aus dem Schlüsselbund. Achtung: die Klammer im Zertifikatsnamen ist NICHT die Team-ID
# — die steht im Zertifikat als OU=9HW65ZP3L9 (Tom Göckeritz). Mit HF45S99Z5G als DEVELOPMENT_TEAM
# bricht xcodebuild mit „No Account for Team" ab. Zu 9HW65ZP3L9 gibt es bereits das Sammelprofil
# „iOS Team Provisioning Profile: *" (9HW65ZP3L9.*), das jede eigene Bundle-ID mit abdeckt; ein neues
# Gerät nimmt `-allowProvisioningUpdates` aber nur auf, wenn die Apple-ID in
# Xcode → Settings → Accounts angemeldet ist.
#
# ── TestFlight (--store/--validate/--upload) ─────────────────────────────────────────────────────
# Fuer den Store braucht es andere Papiere als fuers eigene Geraet: ein Zertifikat „Apple
# Distribution" statt „Apple Development" und ein „App Store"-Bereitstellungsprofil. Beides legt
# xcodebuild mit -allowProvisioningUpdates selbst an, sobald es sich anmelden kann — entweder ueber
# die in Xcode angemeldete Apple-ID oder ueber den App-Store-Connect-Schluessel unten.
#
# Einmalig von Hand (nicht automatisierbar, Apple verlangt die Weboberflaeche):
#   1. App Store Connect → Apps → „+" → neue App mit genau der Bundle-ID aus dem Preset anlegen.
#      Die Bundle-ID muss vorher unter Certificates, Identifiers & Profiles als Identifier stehen.
#   2. App Store Connect → Benutzer und Zugriff → Integrationen → App Store Connect API →
#      Schluessel erzeugen (Rolle „App Manager" genuegt). Die .p8-Datei gibt es genau EINMAL zum
#      Herunterladen. Ablegen als:
#        ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8      (chmod 600)
#      Dort sucht altool von selbst; xcodebuild bekommt den Pfad hier ausdruecklich mit.
#   3. build/ios-upload.conf anlegen (gitignored, build/ liegt komplett ausserhalb von Git):
#        ASC_KEY_ID=ABCD123456
#        ASC_ISSUER_ID=11111111-2222-3333-4444-555555555555
#        # ASC_KEY_PATH=...    optional, sonst der Standardpfad oben
#
# Buildnummer: TestFlight nimmt jede Buildnummer (CFBundleVersion) nur EINMAL an. Der Store-Modus
# zaehlt darum `application/version` im Preset vor jedem Bau um eins hoch (mit --no-bump abschaltbar);
# `application/short_version` (die sichtbare Fassung, z. B. 0.13) bleibt unberuehrt und wird wie
# bisher von Hand gepflegt.
#
# Pruefung von Apple: interne Tester (bis 100 Mitglieder des eigenen Teams) bekommen den Build ohne
# Beta App Review sofort. Externe Tester und der oeffentliche TestFlight-Link durchlaufen eine
# Pruefung durch Apple — dafuer gelten dieselben Ueberlegungen wie fuer die Website: keine fremden
# Inhalte mitliefern (s. CLAUDE.md, „Verteilung ohne EA-Inhalte"). Das Preset „iOS" packt derzeit
# `assets/**` vollstaendig ein, also auch Musik, Filme und Sprachdateien aus dem Original.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=/Applications/Godot.app/Contents/MacOS/Godot
TEAM=9HW65ZP3L9
PRESETS="$ROOT/game/export_presets.cfg"
# Bundle-ID nicht doppelt pflegen: sie steht im Preset „iOS" und wandert bei einer Umbenennung
# (2026-09-09: dev.tom.redalert → dev.tom.pocketra) von selbst mit.
BUNDLE=$(sed -n 's|^application/bundle_identifier="\(.*\)"|\1|p' "$PRESETS" | head -1)
[ -n "$BUNDLE" ] || { echo "Bundle-ID nicht im Preset gefunden ($PRESETS)"; exit 1; }
# Name unter dem Symbol auf dem Startbildschirm: kommt aus project.godot
# (application/config/name = „Red Alert", config/name_localized de = „Alarmstufe Rot"). Godots
# iOS-Export schreibt daraus INFOPLIST_KEY_CFBundleDisplayName="Red Alert" ins Xcode-Projekt und je
# Sprache eine <lang>.lproj/InfoPlist.strings — dieses Skript setzt den Namen deshalb NICHT mehr
# selbst; eine feste Zeile hier würde die englische Fassung überschreiben und die Lokalisierung
# aushebeln.
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
# --device nimmt einen Wert; darum eine while-Schleife statt for über "$@".
while [ $# -gt 0 ]; do
    arg=$1
    case "$arg" in
        --device) DEVICE=$2; shift ;;
        --install) INSTALL=1 ;;
        --release) CONFIG=Release; EXPORT=--export-release ;;
        # Nur zur Bauprüfung: baut ohne Signierung durch (läuft auf keinem Gerät, zeigt aber, ob
        # Übersetzen und Linken der Extension in Ordnung sind — nützlich, solange keine Apple-ID in
        # Xcode hinterlegt ist).
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

# Extension zur Konfiguration passend bauen: ein template_debug-xcframework in einem Release-Archiv
# waere eine stille Mischung (godot-cpp und Engine-Vorlage sollen dieselbe Zielart haben).
if [ "$CONFIG" = Release ]; then TARGET=template_release; else TARGET=template_debug; fi

# ── App-Store-Connect-Zugang einlesen (nur noetig zum Hoch- oder Vorpruefen) ────────────────────
ASC_KEY_ID=""; ASC_ISSUER_ID=""; ASC_KEY_PATH=""
# Als if-Zweige und nicht als „[ … ] && …": unter set -e beendet eine UND-Liste, deren erster Test
# fehlschlaegt, das ganze Skript — die fehlende Konfigurationsdatei ist aber der Normalfall.
if [ -f "$CONF" ]; then . "$CONF"; fi
if [ -n "$ASC_KEY_ID" ] && [ -z "$ASC_KEY_PATH" ]; then
    ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
fi
# Der Schluessel ist optional: ohne ihn laedt xcodebuild ueber das in Xcode angemeldete Apple-Konto
# hoch (Xcode → Settings → Accounts) — kein zusaetzliches Geheimnis noetig, geprueft 2026-09-09
# (echter Upload nach TestFlight erfolgreich). Fuer einen unbeaufsichtigten Lauf ist der Schluessel
# trotzdem vorzuziehen, die Anmeldung kann ablaufen. Ist einer eingetragen, muss die Datei auch da
# sein. Apples getrennte Vorpruefung (--validate ohne --upload) gibt es NUR mit Schluessel.
if [ -n "$ASC_KEY_ID" ] && [ ! -f "$ASC_KEY_PATH" ]; then
    echo "Schluesseldatei fehlt: $ASC_KEY_PATH"; exit 1
fi
if [ -n "$VALIDATE" ] && [ -z "$UPLOAD" ] && [ -z "$ASC_KEY_ID" ]; then
    echo "--validate braucht einen App-Store-Connect-Schluessel: $CONF mit ASC_KEY_ID und"
    echo "ASC_ISSUER_ID anlegen (Anleitung im Kopf dieses Skripts). --upload geht auch ohne."
    exit 1
fi

# Apples eigenes rsync muss vor dem von Homebrew stehen. Xcodes Schritt „CreateIPA" ruft rsync auf
# und bricht mit dem Homebrew-Bau (3.4.x) ab: „rsync error: syntax or usage error (code 1) …
# [server=3.4.1]", nach aussen sichtbar nur als „error: exportArchive Copy failed" (Toms Befund
# 2026-09-09, zweiter Fund desselben Tages). Unter /usr/bin liegt Apples openrsync
# (2.6.9-kompatibel), mit dem es durchlaeuft. Homebrew bleibt im Pfad, nur eben dahinter.
APPLE_PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# xcodebuild mit den Schluesselargumenten aufrufen, wenn es einen Schluessel gibt: dann kann es
# Zertifikat und Profil auch ohne in Xcode angemeldete Apple-ID anlegen (unbeaufsichtigter Lauf).
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
        # Kein Schluessel hinterlegt: xcodebuild laedt selbst hoch, angemeldet mit dem Apple-Konto
        # aus Xcode → Settings → Accounts. Keine getrennte Vorpruefung auf diesem Weg — xcodebuild
        # prueft beim Hochladen selbst und bricht bei einer Ablehnung ebenso ab.
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

    # Vorpruefung: findet fehlende Symbole, falsche Signatur, verbotene Schluessel in der Info.plist
    # usw., ohne eine Buildnummer zu verbrauchen. Erst danach der eigentliche Upload.
    # Nicht "| tail" ohne Weiteres: in einer Pipe zaehlt nur der Rueckgabewert von tail, eine
    # gescheiterte Pruefung bliebe unbemerkt und der Upload liefe trotzdem los.
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

# ── Buildnummer hochzaehlen (nur Store-Modus) ──────────────────────────────────────────────────
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

# Godot traegt in die Release-Konfiguration CODE_SIGN_IDENTITY "Apple Distribution" ein, stellt den
# Stil aber auf Automatic — Xcode bricht dann ab: „automatically signed for development, but a
# conflicting code signing identity Apple Distribution has been manually specified" (Toms Befund
# 2026-09-09). Richtig ist: mit Entwicklungsidentitaet ARCHIVIEREN, und erst der Export signiert
# ueber method „app-store-connect" + signingStyle „automatic" auf das Verteilzertifikat um.
xcb -project "$OUT/pocketra.xcodeproj" -scheme pocketra \
    -configuration "$CONFIG" -destination 'generic/platform=iOS' \
    -archivePath "$OUT/pocketra.xcarchive" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
    CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    archive | tail -3

if [ -n "$STORE" ]; then
    # Godot schreibt sein export_options.plist aus dem Preset (dort steht Development). Fuer den
    # Store braucht es method „app-store-connect" — das erzwingt beim Export das
    # Verteilzertifikat („Apple Distribution") und ein App-Store-Profil, beide legt
    # -allowProvisioningUpdates bei Bedarf selbst an. manageAppVersionAndBuildNumber=false, damit
    # Xcode unsere hochgezaehlte Buildnummer nicht eigenmaechtig ersetzt.
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
    # Gerätekennung ist eine UUID; Name und Modell in der Tabelle enthalten Leerzeichen, darum nicht
    # nach Spalten schneiden. „unavailable" enthält „available" als Teilwort — erst ausfiltern.
    # Jedes erreichbare iPhone oder iPad zaehlt; mit --device NAME gezielt eines waehlen.
    LISTE=$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' | grep -v unavailable)
    if [ -n "$DEVICE" ]; then LISTE=$(printf '%s\n' "$LISTE" | grep -i "$DEVICE"); fi
    DEV=$(printf '%s\n' "$LISTE" \
        | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | head -1)
    [ -n "$DEV" ] || { echo "kein erreichbares iPhone/iPad (xcrun devicectl list devices)"; exit 1; }
    printf '%s\n' "$LISTE" | head -1 | sed 's/  .*//; s/^/Ziel: /'

    xcrun devicectl device install app --device "$DEV" "$APP" | tail -3
    xcrun devicectl device process launch --device "$DEV" "$BUNDLE" | tail -2
fi
