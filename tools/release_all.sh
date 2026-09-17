#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ONLY="android,windows,macos,ios,web,server,github"
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

step "rules.json + Karten"
python3 tools/rules2json.py
python3 tools/mapconvert.py

if [ -z "$SKIP_TESTS" ]; then
    step "Sim-Tests"
    sh sim/tests/run.sh
fi

if tut android; then
    step "Android (Verteilfassung)"
    tools/apk_build.sh --dist --ref "$BRANCH"
fi

if tut windows; then
    step "Windows (Verteilfassung)"
    tools/win_build.sh --dist
fi

if tut macos; then
    step "macOS (Verteilfassung)"
    if [ -n "$NO_NOTARIZE" ]; then
        tools/mac_build.sh --no-notarize
    else
        tools/mac_build.sh
    fi
fi

if tut ios; then
    step "iOS → TestFlight"
    tools/ipa_build.sh --release --upload
fi

if tut web; then
    step "Browser-Fassung"
    EMSDK_DIR=${EMSDK_DIR:-$ROOT/build/emsdk} tools/web_build.sh --no-ext --full
    for pat in assets/atlas assets/sfx assets/video; do
        n=$(strings -a website/play/full/index.pck | grep -c "res://$pat" || true)
        [ "$n" = "0" ] || { echo "ABBRUCH: $n Verweise auf $pat im Web-Paket"; exit 1; }
    done
    echo "  Web-Paket ohne EA-Inhalte geprueft"
    tools/site_upload.sh
fi

if tut github; then
    step "GitHub: Quellcode"
    python3 tools/publish.py --git https://github.com/tomgoeck/pocketra.git
    [ -n "${GITHUB_TOKEN:-}" ] || [ -f "$ROOT/build/github_token" ] || { echo "kein Token: GITHUB_TOKEN setzen oder build/github_token anlegen"; exit 1; }
    TOKEN="${GITHUB_TOKEN:-$(head -1 "$ROOT/build/github_token")}"
    AUTH=$(printf 'x-access-token:%s' "$TOKEN" | base64)
    (cd build/public && git -c http.extraheader="Authorization: Basic $AUTH" push -f -q origin public:main)
    echo "Quellcode gepusht (public → main)"

    step "GitHub: Release-Anhaenge ($TAG)"
    tools/update_pack.sh --slim --notes "$NOTES"
    NOTES_FILE="$ROOT/build/update/notes.en.md"
    NOTES_ARG=""
    [ -f "$NOTES_FILE" ] && NOTES_ARG="--notes-file $NOTES_FILE"
    for pair in \
        "build/pocketra-dist.apk:pocketra-dist.apk" \
        "build/pocketra-windows-dist.exe:pocketra-windows-setup.exe" \
        "build/pocketra-macos.dmg:pocketra-macos.dmg" \
        "build/update/update.pck:update.pck"; do
        FILE=${pair%%:*}; AS=${pair##*:}
        if [ -f "$ROOT/$FILE" ]; then
            tools/gh_release.sh $NOTES_ARG --as "$AS" "$TAG" "$ROOT/$FILE"
            echo "  $AS → $TAG"
        else
            echo "  Hinweis: $FILE fehlt, $AS nicht im Release"
        fi
    done
fi

if tut server; then
    step "Server (pocketra.net): version.json"
    tools/update_pack.sh --slim --upload --notes "$NOTES"
fi

step "fertig"
echo "Android: $([ -f build/pocketra-dist.apk ] && du -m build/pocketra-dist.apk | cut -f1 || echo -)MB"
echo "Windows: $([ -f build/pocketra-windows-dist.exe ] && du -m build/pocketra-windows-dist.exe | cut -f1 || echo -)MB"
echo "macOS:   $([ -f build/pocketra-macos.dmg ] && du -m build/pocketra-macos.dmg | cut -f1 || echo -)MB"
