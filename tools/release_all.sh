#!/bin/sh
# EINE Veröffentlichungsrunde über alle Plattformen: Android/Windows/macOS (Server pocketra.net),
# iOS (TestFlight), Quellcode (GitHub). Ersetzt/ergänzt die einzelnen Aufrufe aus CLAUDE.md
# „Veröffentlichung" — nach jeder abgeschlossenen Änderungsrunde (Merge in den Integrationszweig,
# Tests grün) genügt EIN Kommando:
#
#   tools/release_all.sh
#
# Nur einzelne Beine:
#   tools/release_all.sh --only android,ios          # Komma-Liste aus android,windows,macos,ios,
#                                                      # server,github
#   tools/release_all.sh --skip-tests                 # sim/tests/run.sh überspringen (schneller)
#   tools/release_all.sh --no-notarize                # macOS ungeprüft bauen (läuft nur hier lokal)
#   tools/release_all.sh --dry-run                     # nur zeigen, was laufen würde
#   tools/release_all.sh --notes "Text"                # Hinweistext in version.json
#
# WAS AUTOMATISCH GEHT UND WAS NICHT:
#   Android, Windows, macOS: nur die Verteilfassungen ohne EA-Inhalte (Toms Entscheidung
#   2026-09-09) — apk_build.sh --dist, win_build.sh --dist, mac_build.sh. Diese drei plus das
#   Aktualisierungspaket gehen NUR auf pocketra.net (Toms Entscheidung 2026-09-09: nicht auch als
#   GitHub-Release-Anhänge — GitHub bleibt reine Quellcode-Ablage für die GPL-Pflicht).
#   iOS geht NUR an interne TestFlight-Tester automatisch (ipa_build.sh --release --upload) — kein
#   App-Store-Review, kein öffentlicher Link; das bleibt Toms manueller Schritt in App Store Connect.
#   Der Quellcode (kommentarfreie Kopie) geht auf den öffentlichen main-Branch von GitHub.
#
# VORAUSSETZUNGEN (einmalig, s. auch die Kopfkommentare der einzelnen Skripte):
#   - Android: JDK 17, Android SDK (apk_build.sh)
#   - Windows: mingw-w64 (win_build.sh)
#   - macOS: Developer-ID-Zertifikat (vorhanden) + notarytool-Schlüsselbundprofil „pocketra-notary“
#     (einmalig: xcrun notarytool store-credentials, s. tools/mac_build.sh)
#   - iOS: App-Store-Connect-Eintrag mit der Bundle-ID aus dem Preset (vorhanden); Upload läuft ohne
#     eigenen Schlüssel über das in Xcode angemeldete Konto, s. tools/ipa_build.sh
#   - Server: build/update/upload.conf (TARGET=…, BASE_URL=…)
#   - GitHub: build/github_token (Contents: Read and write) — nur noch für den Quellcode-Push
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ONLY="android,windows,macos,ios,server,github"
SKIP_TESTS=""
NO_NOTARIZE=""
DRY=""
NOTES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY=$2; shift ;;
        --skip-tests) SKIP_TESTS=1 ;;
        --no-notarize) NO_NOTARIZE=1 ;;
        --dry-run) DRY=1 ;;
        --notes) NOTES=$2; shift ;;
        *) echo "unbekannt: $1"; exit 1 ;;
    esac
    shift
done
tut() { case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' game/project.godot | head -1)
TAG="v${VERSION:-0.0}"
echo "Zweig $BRANCH @ $COMMIT (${DIRTY} unversionierte Änderungen), Fassung $VERSION → Tag $TAG"
echo "Schritte: $ONLY"
[ -n "$DRY" ] && { echo "(--dry-run: nichts wird gebaut oder hochgeladen)"; exit 0; }

step() { echo; echo "── $1 ──────────────────────────────────────────────────────────"; }

# ── Vorbereitung: erzeugte Daten frisch, Sim-Tests grün ─────────────────────────────────────────
step "rules.json + Karten"
python3 tools/rules2json.py
python3 tools/mapconvert.py

if [ -z "$SKIP_TESTS" ]; then
    step "Sim-Tests"
    sh sim/tests/run.sh
fi

# ── Android: Verteil-APK ─────────────────────────────────────────────────────────────────────────
if tut android; then
    step "Android (Verteilfassung)"
    tools/apk_build.sh --dist --ref "$BRANCH"
fi

# ── Windows: Verteilfassung ──────────────────────────────────────────────────────────────────────
if tut windows; then
    step "Windows (Verteilfassung)"
    tools/win_build.sh --dist
fi

# ── macOS: Verteilfassung, signiert + notarisiert ───────────────────────────────────────────────
if tut macos; then
    step "macOS (Verteilfassung)"
    if [ -n "$NO_NOTARIZE" ]; then
        tools/mac_build.sh --no-notarize
    else
        tools/mac_build.sh
    fi
fi

# ── iOS: Release-Bau, direkt zu TestFlight ──────────────────────────────────────────────────────
if tut ios; then
    step "iOS → TestFlight"
    tools/ipa_build.sh --release --upload
fi

# ── Server: Aktualisierungspaket + die drei Verteilfassungen + version.json ────────────────────
if tut server; then
    step "Server (pocketra.net)"
    tools/update_pack.sh --slim --upload --notes "$NOTES"
fi

# ── GitHub: nur Quellcode (main) — die Verteilfassungen gehen nicht auf GitHub, s. Kopf ──────────
if tut github; then
    step "GitHub: Quellcode"
    python3 tools/publish.py --git https://github.com/tomgoeck/pocketra.git
    [ -n "${GITHUB_TOKEN:-}" ] || [ -f "$ROOT/build/github_token" ] || { echo "kein Token: GITHUB_TOKEN setzen oder build/github_token anlegen"; exit 1; }
    TOKEN="${GITHUB_TOKEN:-$(head -1 "$ROOT/build/github_token")}"
    (cd build/public && git -c http.extraheader="AUTHORIZATION: bearer $TOKEN" push -q origin public:main)
    echo "Quellcode gepusht (public → main)"
fi

step "fertig"
echo "Android: $([ -f build/pocketra-dist.apk ] && du -m build/pocketra-dist.apk | cut -f1 || echo -)MB"
echo "Windows: $([ -f build/pocketra-windows-dist.exe ] && du -m build/pocketra-windows-dist.exe | cut -f1 || echo -)MB"
echo "macOS:   $([ -f build/pocketra-macos.dmg ] && du -m build/pocketra-macos.dmg | cut -f1 || echo -)MB"
