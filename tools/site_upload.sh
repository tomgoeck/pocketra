#!/bin/sh
# Website (website/) nach pocketra.net hochladen — statische Dateien, kein Build-Schritt.
#   tools/site_upload.sh            # rsync nach $TARGET
#   tools/site_upload.sh --dry-run  # nur zeigen, was sich ändern würde
# Ziel: Umgebungsvariable POCKETRA_SITE_TARGET oder build/site/upload.conf (gitignored), Format wie
# beim Aktualisierungspaket (build/update/upload.conf):
#   TARGET=host:/var/www/pocketra/
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
