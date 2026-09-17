#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZONE_NAME=${ZONE_NAME:-pocketra.net}
TOKEN="${CLOUDFLARE_API_TOKEN:-}"
[ -z "$TOKEN" ] && [ -f "$ROOT/build/cloudflare_token" ] && TOKEN=$(head -1 "$ROOT/build/cloudflare_token" | tr -d ' \n\r')
if [ -z "$TOKEN" ]; then
    echo "Cache nicht geleert: kein Token."
    echo "  Im Cloudflare-Dashboard unter My Profile, API Tokens ein Token mit den Rechten"
    echo "  'Zone - Cache Purge' und 'Zone - Read' fuer $ZONE_NAME anlegen, dann:"
    echo "    echo 'TOKEN' > build/cloudflare_token && chmod 600 build/cloudflare_token"
    exit 0
fi
API="https://api.cloudflare.com/client/v4"
cf() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }

ZONE=$(cf "$API/zones?name=$ZONE_NAME" | python3 -c "import json,sys;d=json.load(sys.stdin);r=d.get('result') or [];print(r[0]['id'] if r else '')")
[ -n "$ZONE" ] || { echo "Cache nicht geleert: Zone $ZONE_NAME nicht gefunden (Token-Rechte pruefen)."; exit 0; }

if [ "$1" = "--all" ]; then
    BODY='{"purge_everything":true}'
    WAS="alles"
else
    BODY=$(cd "$ROOT/website/play/full" 2>/dev/null && ls | head -28 | python3 -c "
import json,sys
files=[l.strip() for l in sys.stdin if l.strip()]
print(json.dumps({'files': ['https://pocketra.net/play/full/' + f for f in files]}))
") || { echo "Cache nicht geleert: website/play/full/ fehlt."; exit 0; }
    WAS=$(echo "$BODY" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['files']))")" Adressen"
fi
OK=$(cf -X POST "$API/zones/$ZONE/purge_cache" --data "$BODY" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('success'));[print('  ',e.get('message')) for e in d.get('errors',[])]")
echo "Cloudflare-Cache geleert ($WAS): success=$OK"
