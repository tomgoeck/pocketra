#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONF="$ROOT/build/site/upload.conf"
TARGET="${POCKETRA_SITE_TARGET:-}"
if [ -z "$TARGET" ] && [ -f "$CONF" ]; then
    TARGET=$(sed -n 's/^TARGET=//p' "$CONF" | head -1)
fi
[ -n "$TARGET" ] || { echo "kein Upload-Ziel: POCKETRA_SITE_TARGET setzen oder $CONF anlegen (TARGET=host:/pfad/)"; exit 1; }
DRY=""
[ "$1" = "--dry-run" ] && DRY="--dry-run"
rsync -avz --delete $DRY --exclude .DS_Store "$ROOT/website/" "$TARGET"
