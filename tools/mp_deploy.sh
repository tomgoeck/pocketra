#!/bin/sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOST=${POCKETRA_MP_HOST:-pocketra-upload}
DIR=${POCKETRA_MP_DIR:-/opt/pocketra-mp}
SITE=${POCKETRA_MP_SITE:-/etc/nginx/sites-available/pocketra.net}
URL=${POCKETRA_MP_URL:-https://pocketra.net/mp}
USER_NAME=pocketra-mp
PORT=8787
SKIP_NGINX=""
CHECK_ONLY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        --site) SITE="$2"; shift 2 ;;
        --url) URL="$2"; shift 2 ;;
        --skip-nginx) SKIP_NGINX=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unbekannt: $1"; exit 1 ;;
    esac
done

say() { printf '\n== %s\n' "$1"; }

if [ -z "$CHECK_ONLY" ]; then
    say "Dateien nach $HOST:$DIR"
    ssh "$HOST" "mkdir -p '$DIR'"
    rsync -az --chmod=F644 \
        "$ROOT/server/mp_server.py" \
        "$ROOT/server/mp_smoke.py" \
        "$ROOT/server/pocketra-mp.service" \
        "$ROOT/server/nginx-mp.conf" \
        "$HOST:$DIR/"

    say "Benutzer, venv, systemd auf $HOST"
    ssh "$HOST" "DIR='$DIR' USER_NAME='$USER_NAME' PORT='$PORT' sh -s" <<'FERN'
set -e
if ! id "$USER_NAME" >/dev/null 2>&1; then
    useradd --system --home-dir "$DIR" --shell /usr/sbin/nologin "$USER_NAME"
    echo "Benutzer $USER_NAME angelegt"
else
    echo "Benutzer $USER_NAME vorhanden"
fi

if [ ! -x "$DIR/venv/bin/python" ]; then
    echo "lege venv an"
    if ! python3 -m venv "$DIR/venv" 2>/dev/null; then
        echo "python3-venv fehlt — wird nachinstalliert"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3-venv >/dev/null
        python3 -m venv "$DIR/venv"
    fi
fi
if ! "$DIR/venv/bin/python" -c "import websockets" 2>/dev/null; then
    echo "installiere websockets"
    if ! "$DIR/venv/bin/pip" install -q --upgrade pip websockets; then
        echo "pip schlug fehl — nehme das Debian-Paket python3-websockets"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3-websockets >/dev/null
        rm -rf "$DIR/venv"
        python3 -m venv --system-site-packages "$DIR/venv"
    fi
fi
echo "websockets $("$DIR/venv/bin/python" -c 'import websockets;print(websockets.__version__)')"
chown -R "$USER_NAME:$USER_NAME" "$DIR"
chmod 0755 "$DIR"

if ! cmp -s "$DIR/pocketra-mp.service" /etc/systemd/system/pocketra-mp.service; then
    install -m 0644 "$DIR/pocketra-mp.service" /etc/systemd/system/pocketra-mp.service
    systemctl daemon-reload
    echo "Unit eingespielt"
else
    echo "Unit unveraendert"
fi
systemctl enable pocketra-mp >/dev/null 2>&1 || true
FERN
fi

if [ -z "$SKIP_NGINX" ]; then
    say "nginx-Site $SITE (nur wenn der Block 'location /mp' fehlt)"
    ssh "$HOST" "DIR='$DIR' SITE='$SITE' python3 -" <<'FERN'
import os, subprocess, sys
site, d = os.environ["SITE"], os.environ["DIR"]
text = open(site, encoding="utf-8").read()
if "location /mp" in text:
    print("location /mp steht schon in der Site")
    sys.exit(0)
snippet = open(os.path.join(d, "nginx-mp.conf"), encoding="utf-8").read()
snippet = "".join(l for l in snippet.splitlines(True) if not l.lstrip().startswith("#"))

pos, ziel = 0, None
while True:
    i = text.find("server", pos)
    if i < 0:
        break
    j = text.find("{", i)
    if j < 0:
        break
    tiefe, k = 1, j + 1
    while k < len(text) and tiefe:
        if text[k] == "{":
            tiefe += 1
        elif text[k] == "}":
            tiefe -= 1
        k += 1
    block = text[j:k]
    if "listen 443" in block or "listen [::]:443" in block:
        ziel = k - 1
        break
    pos = k
if ziel is None:
    print("FEHLER: kein 443-Block in %s gefunden" % site)
    sys.exit(1)
open(site + ".bak-mp", "w", encoding="utf-8").write(text)
neu = text[:ziel] + "\n" + snippet + text[ziel:]
open(site, "w", encoding="utf-8").write(neu)
print("location /mp eingefuegt (Sicherung: %s.bak-mp)" % site)
if subprocess.call(["nginx", "-t"]) != 0:
    open(site, "w", encoding="utf-8").write(text)
    print("FEHLER: nginx -t schlug fehl — Site zurueckgesetzt")
    sys.exit(1)
subprocess.check_call(["systemctl", "reload", "nginx"])
print("nginx neu geladen")
FERN
fi

if [ -z "$CHECK_ONLY" ]; then
    say "Dienst neu starten"
    ssh "$HOST" "systemctl restart pocketra-mp; sleep 1; systemctl is-active pocketra-mp"
fi

say "Zustand"
ssh "$HOST" "systemctl is-active pocketra-mp; systemctl is-enabled pocketra-mp; \
    ss -ltnp 2>/dev/null | grep ':$PORT ' || true; \
    journalctl -u pocketra-mp -n 5 --no-pager -o cat"

say "Probe: WebSocket-Handschlag gegen $URL (101 erwartet)"
code=$(curl -s -o /tmp/mp_probe.$$ -D /tmp/mp_head.$$ -w '%{http_code}' -N --max-time 10 \
    --http1.1 \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    "$URL" || true)
head -1 /tmp/mp_head.$$ 2>/dev/null || true
grep -i '^sec-websocket-accept' /tmp/mp_head.$$ 2>/dev/null || true
rm -f /tmp/mp_probe.$$ /tmp/mp_head.$$
if [ "$code" = "101" ]; then
    printf '\nOK — der Vermittler antwortet mit 101 Switching Protocols.\n'
    printf 'Rauchtest:  python3 server/mp_smoke.py --url %s\n' \
        "$(echo "$URL" | sed 's|^https://|wss://|; s|^http://|ws://|')"
    exit 0
fi
printf '\nFEHLER — HTTP %s statt 101. Logs: ssh %s journalctl -u pocketra-mp -n 50\n' "$code" "$HOST"
exit 1
