#!/bin/sh
# Aktualisierungspaket bauen und (optional) auf Toms Webserver hochladen.
#
# Toms Wunsch (2026-09-04): Freunde sollen nicht staendig eine neue APK bekommen. Stufe 1 ist ein
# Godot-Ressourcenpaket mit allen Skripten/Szenen/Daten; die App laedt es beim Start nach und haengt
# es beim naechsten Start ein (game/scripts/update/update_boot.gd).
#
#   tools/update_pack.sh                      # Paket + version.json nach build/update/
#   tools/update_pack.sh --notes "Text"       # Hinweistext (Statuszeile/Sperrseite)
#   tools/update_pack.sh --min-supported 0.5  # aeltere App-Versionen stilllegen
#   tools/update_pack.sh --disable            # Notschalter: JEDE Fassung stilllegen
#   tools/update_pack.sh --slim               # kleines Paket (ohne Musik/Menuebild/Intro, ~32 statt 116 MB)
#   tools/update_pack.sh --version-only       # nur version.json neu schreiben (Paket bleibt)
#   tools/update_pack.sh --upload             # zusaetzlich hochladen (s. unten)
#
# Auf dem Server liegen nur statische Dateien (HTTPS, kein Serverskript):
#   <BASE>/version.json            Versionsdatei, die die App abfragt
#   <BASE>/update.pck              das Paket
#   <BASE>/pocketra.apk            Verteilfassung (ohne EA-Inhalte) — DIE Adresse, die Tom weitergibt
# Toms Regel 2026-09-09: Es wird NUR NOCH die Verteilfassung (pocketra.apk, ohne Fremdinhalte)
# verteilt - die Vollfassung mit EA-Inhalten in der APK geht nicht mehr auf den Server, um sich
# nicht angreifbar zu machen. version.json traegt deshalb kein apk_url_full mehr; UpdateConfig.
# apk_choice() faellt ohne dieses Feld von selbst auf apk_url zurueck (Zeile 124/125 dort).
# <BASE> ist die URL, die in game/scripts/update/update_config.gd als DEFAULT_URL steht
# (bzw. user://settings.cfg [update] url) — ohne den Dateinamen version.json.
#
# Upload-Ziel: Umgebungsvariable POCKETRA_UPDATE_TARGET oder die Datei build/update/upload.conf
# (gitignored, build/ liegt komplett ausserhalb von Git). Format der Datei:
#   TARGET=pocketra-upload:/var/www/pocketra/  # rsync/scp-Ziel (SSH-Alias, s. docs/UMBENENNUNG-POCKETRA.md)
#   BASE_URL=https://pocketra.net
#   RSYNC_OPTS=-avz --chmod=F644             # optional
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

# --- Paket bauen -----------------------------------------------------------
# --export-pack schreibt nur die PCK (kein Plattform-Template noetig). Vorher importieren, sonst
# fehlen frisch angelegte Skripte/Szenen im Paket.
if [ -z "$VERSION_ONLY" ]; then
    "$G" --headless --path "$ROOT/game" --import 2>&1 | grep -c 'SCRIPT ERROR' \
        | sed 's/^/Skriptfehler beim Import: /'
    "$G" --headless --path "$ROOT/game" --export-pack "$PRESET" "$PCK" 2>&1 \
        | grep -E 'ERROR|error' | head -5 || true
fi
[ -f "$PCK" ] || { echo "kein Paket unter $PCK"; exit 1; }

# --- Kennzahlen ------------------------------------------------------------
SHA=$(shasum -a 256 "$PCK" | awk '{print $1}')
SIZE=$(wc -c < "$PCK" | tr -d ' ')
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)
LABEL="$(date +%Y-%m-%d)-$COMMIT"
# Laufende Nummer: die alte version.json plus eins (die App vergleicht rein numerisch).
PREV=0
if [ -f "$VERSION_JSON" ]; then
    PREV=$(python3 -c 'import json,sys;print(int(json.load(open(sys.argv[1])).get("pack_version",0)))' "$VERSION_JSON")
fi
if [ -n "$VERSION_ONLY" ]; then
    PACK_VERSION=$PREV
else
    PACK_VERSION=$((PREV + 1))
fi
# min_extension: die Version der Extension, gegen die dieses Paket gebaut wurde
# (sim/src/world/wmath.cpp -> ra::version() -> RaSim.version()).
MIN_EXT=$(sed -n 's/.*const char\* version() { return "\(.*\)".*/\1/p' "$ROOT/sim/src/world/wmath.cpp")
MIN_EXT=${MIN_EXT:-0}
# App-Version aus dem Export-Preset (dieselbe Zahl wie ProjectSettings application/config/version)
APK_VERSION=$(sed -n 's/^version\/name="\(.*\)"/\1/p' "$ROOT/game/export_presets.cfg" | head -1)
APK_VERSION=${APK_VERSION:-0.5}
# Groesse der Verteil-APK (nur Anzeige: "Verteilfassung (130 MB)"). Liegt die Datei gerade nicht in
# build/ (etwa bei --version-only), bleibt der Wert aus der alten version.json stehen — sonst
# verlöre die App die Angabe bei jedem reinen Versionslauf.
APK_SIZE=$([ -f "$ROOT/build/pocketra-dist.apk" ] && wc -c < "$ROOT/build/pocketra-dist.apk" | tr -d ' ' || echo 0)

# Windows-Verteilfassung (Toms Entscheidung 2026-09-09, tools/win_build.sh --dist): ohne
# EA-Inhalte, wie die Android-Verteil-APK — darf deshalb, anders als die fruehere Windows-Vollfassung,
# wieder auf den Server. Die Vollfassung (tools/win_build.sh, ohne --dist) bleibt weiterhin lokal.
# Seit 2026-09-09 ein NSIS-Installer (.exe) statt eines ZIPs (Toms Wunsch).
WIN_EXE="$ROOT/build/pocketra-windows-dist.exe"
WINDOWS_EXE=""
WINDOWS_SIZE=0
if [ -f "$WIN_EXE" ]; then
    WINDOWS_EXE="$WIN_EXE"
    WINDOWS_SIZE=$(wc -c < "$WIN_EXE" | tr -d ' ')
fi

# macOS-Verteilfassung (tools/mac_build.sh): dieselbe Ueberlegung, ohne EA-Inhalte. Seit 2026-09-09
# eine DMG mit Ziehen-in-Programme-Fenster (Toms Wunsch) statt eines ZIPs.
MAC_DMG="$ROOT/build/pocketra-macos.dmg"
MACOS_DMG=""
MACOS_SIZE=0
if [ -f "$MAC_DMG" ]; then
    MACOS_DMG="$MAC_DMG"
    MACOS_SIZE=$(wc -c < "$MAC_DMG" | tr -d ' ')
fi

WINDOWS_EXE="$WINDOWS_EXE" WINDOWS_SIZE="$WINDOWS_SIZE" \
MACOS_DMG="$MACOS_DMG" MACOS_SIZE="$MACOS_SIZE" \
PACK_VERSION="$PACK_VERSION" LABEL="$LABEL" BASE_URL="$BASE_URL" SHA="$SHA" SIZE="$SIZE" \
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
# Fehlt die APK gerade in build/, die zuletzt gemeldete Groesse behalten (s. Kommentar oben).
size = int(os.environ["APK_SIZE"]) or int(prev.get("apk_size", 0))
d = {
    "pack_version": int(os.environ["PACK_VERSION"]),
    "pack_label": os.environ["LABEL"],
    "pack_url": base + "/update.pck",
    "pack_sha256": os.environ["SHA"],
    "pack_size": int(os.environ["SIZE"]),
    "min_extension": os.environ["MIN_EXT"],
    "apk_version": os.environ["APK_VERSION"],
    # Nur die Verteilfassung (Toms Regel 2026-09-09). Kein apk_url_full mehr — UpdateConfig.
    # apk_choice() faellt dann von selbst auf apk_url zurueck, auch auf einem Vollfassungs-Geraet.
    "apk_url": base + "/pocketra.apk",
    "apk_size": size,
    "notes": os.environ["NOTES"],
}
# Windows-/macOS-Verteilfassung (ohne EA-Inhalte, Toms Entscheidung 2026-09-09; Installer/DMG statt
# ZIP seit 2026-09-09). Reiner Downloadhinweis fuer die App und die Seite — die App liest die
# Felder nur fuer den plattformeigenen Aktualisierungsknopf (UpdateConfig.app_choice()), sie laeuft
# ja schon auf dem Geraet. Stehen nur drin, wenn die jeweilige Datei wirklich gebaut wurde
# (tools/win_build.sh --dist bzw. tools/mac_build.sh), sonst zeigte die Adresse auf eine 404.
if os.environ.get("WINDOWS_EXE"):
    d["windows_url"] = os.environ["BASE_URL"].rstrip("/") + "/pocketra-windows-setup.exe"
    d["windows_size"] = int(os.environ["WINDOWS_SIZE"])
if os.environ.get("MACOS_DMG"):
    d["mac_url"] = os.environ["BASE_URL"].rstrip("/") + "/pocketra-macos.dmg"
    d["mac_size"] = int(os.environ["MACOS_SIZE"])
# Optionale Stilllegung (Toms Zusatzwunsch): nur schreiben, wenn gesetzt — ein leeres
# min_supported bzw. disabled=false hebt eine frueher gesetzte Sperre beim Client wieder auf.
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

# --- Hochladen -------------------------------------------------------------
if [ -n "$UPLOAD" ]; then
    TARGET=${POCKETRA_UPDATE_TARGET:-$TARGET}
    [ -n "$TARGET" ] || { echo "kein Upload-Ziel: POCKETRA_UPDATE_TARGET setzen oder $CONF anlegen"; exit 1; }
    # Reihenfolge zaehlt: erst das Paket und die APKs, danach version.json — sonst zeigt die
    # Versionsdatei kurzzeitig auf ein Paket, das noch nicht vollstaendig auf dem Server liegt.
    [ -f "$PCK" ] && rsync ${RSYNC_OPTS:--avz} "$PCK" "$TARGET"
    # Toms Vorgabe 2026-09-09: die Verteilfassung liegt auf dem Server unter GENAU EINEM Namen,
    # naemlich pocketra.apk — das ist die Adresse, die er weitergibt (https://pocketra.net/pocketra.apk)
    # und die version.json als apk_url nennt. Der frueher zusaetzlich hochgeladene "-dist"-Zwilling
    # entfaellt; zwei gleiche 130-MB-Dateien nebeneinander waren nur eine Fehlerquelle.
    APK="$ROOT/build/pocketra-dist.apk"
    if [ -f "$APK" ]; then
        rsync ${RSYNC_OPTS:--avz} "$APK" "${TARGET%/}/pocketra.apk"
    else
        echo "Hinweis: $APK fehlt (tools/apk_build.sh --dist) — nur version.json/update.pck"
    fi
    # Die Vollfassung (EA-Inhalte in der APK) wird seit Toms Regel 2026-09-09 NICHT mehr
    # hochgeladen — nur die Verteilfassung geht auf den Server. Windows/macOS ebenso: nur die
    # -dist-Fassungen ohne EA-Inhalte (tools/win_build.sh --dist, tools/mac_build.sh). Vor
    # version.json hochladen, aus demselben Grund wie das Paket.
    if [ -n "$WINDOWS_EXE" ]; then
        rsync ${RSYNC_OPTS:--avz} "$WINDOWS_EXE" "${TARGET%/}/pocketra-windows-setup.exe"
    else
        echo "Hinweis: $WIN_EXE fehlt (tools/win_build.sh --dist) - kein pocketra-windows-setup.exe"
    fi
    if [ -n "$MACOS_DMG" ]; then
        rsync ${RSYNC_OPTS:--avz} "$MACOS_DMG" "${TARGET%/}/pocketra-macos.dmg"
    else
        echo "Hinweis: $MAC_DMG fehlt (tools/mac_build.sh) - keine pocketra-macos.dmg"
    fi
    rsync ${RSYNC_OPTS:--avz} "$VERSION_JSON" "$TARGET"
    echo "hochgeladen nach $TARGET"
fi

ls -la "$OUT"
