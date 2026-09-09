#!/bin/sh
# APK (oder andere Dateien) als GitHub-Release-Anhang hochladen — Release TAG anlegen, falls es fehlt,
# gleichnamige Anhänge ersetzen. Die Website verlinkt IMMER
#   https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-dist.apk
# darum: Anhang immer als pocketra-dist.apk (--as), Release nie als Pre-Release (sonst zählt es
# nicht als "latest"), und die Notizen in kurzen englischen Sätzen — die Seite zeigt sie unter
# "What's new" an.
#   tools/gh_release.sh [--notes "Text" | --notes-file DATEI] [--as NAME] TAG DATEI [DATEI…]
#   tools/gh_release.sh --notes-file build/update/notes.en.md --as pocketra-dist.apk v0.15 build/redalert-dist.apk
# Token: Umgebungsvariable GITHUB_TOKEN oder Datei build/github_token (gitignored, nur dieses Repo,
# Contents: Read and write).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO="tomgoeck/pocketra"
NOTES=""; AS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --notes) NOTES="$2"; shift 2 ;;
        --notes-file) NOTES=$(cat "$2"); shift 2 ;;
        --as) AS="$2"; shift 2 ;;
        *) break ;;
    esac
done
TAG="$1"; shift || true
[ -n "$TAG" ] && [ $# -ge 1 ] || { echo "Aufruf: tools/gh_release.sh [--notes TEXT|--notes-file DATEI] [--as NAME] TAG DATEI…"; exit 1; }
TOKEN="${GITHUB_TOKEN:-}"
[ -z "$TOKEN" ] && [ -f "$ROOT/build/github_token" ] && TOKEN=$(head -1 "$ROOT/build/github_token")
[ -n "$TOKEN" ] || { echo "kein Token: GITHUB_TOKEN setzen oder build/github_token anlegen"; exit 1; }
API="https://api.github.com/repos/$REPO"
auth() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }
jget() { python3 -c 'import sys,json; d=json.load(sys.stdin); v=d
for k in sys.argv[1:]: v=v.get(k,"") if isinstance(v,dict) else ""
print(v if v is not None else "")' "$@"; }

RELEASE=$(auth "$API/releases/tags/$TAG" || true)
ID=$(printf '%s' "$RELEASE" | jget id)
if [ -z "$ID" ]; then
    BODY=$(python3 -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": "PocketRA " + sys.argv[1], "body": sys.argv[2], "draft": False, "prerelease": False}))' "$TAG" "$NOTES")
    RELEASE=$(auth -X POST "$API/releases" -d "$BODY")
    ID=$(printf '%s' "$RELEASE" | jget id)
    [ -n "$ID" ] || { echo "Release konnte nicht angelegt werden:"; printf '%s\n' "$RELEASE" | head -5; exit 1; }
    echo "Release $TAG angelegt (#$ID)"
elif [ -n "$NOTES" ]; then
    BODY=$(python3 -c 'import json,sys; print(json.dumps({"body": sys.argv[1], "prerelease": False}))' "$NOTES")
    auth -X PATCH "$API/releases/$ID" -d "$BODY" >/dev/null && echo "Notizen von $TAG aktualisiert"
fi
UPLOAD_URL=$(printf '%s' "$RELEASE" | jget upload_url | sed 's/{.*//')

for FILE in "$@"; do
    NAME="${AS:-$(basename "$FILE")}"
    OLD=$(auth "$API/releases/$ID/assets" | python3 -c 'import sys,json; n=sys.argv[1]; print(" ".join(str(a["id"]) for a in json.load(sys.stdin) if a["name"]==n))' "$NAME")
    for A in $OLD; do auth -X DELETE "$API/releases/assets/$A" >/dev/null; done
    echo "lade $NAME hoch ($(du -h "$FILE" | cut -f1)) …"
    auth -X POST -H "Content-Type: application/octet-stream" --data-binary @"$FILE" "$UPLOAD_URL?name=$NAME" \
        | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("browser_download_url") or d)'
done
