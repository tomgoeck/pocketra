#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/build/mp-bg-test}
PORT=${PORT:-8795}
KARTE=${KARTE:-keep-off-the-grass-2}
RESUME=${RESUME:-90}
PAUSE=${PAUSE:-60}
VENV=$ROOT/build/.venv_mp/bin/python
[ -x "$VENV" ] || { echo "build/.venv_mp fehlt — siehe server/README.md"; exit 1; }
mkdir -p "$OUT"
rm -f "$OUT"/*.log

"$VENV" "$ROOT/server/mp_server.py" --host 127.0.0.1 --port $PORT --resume-s $RESUME \
    --create-per-min 30 > "$OUT/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true; pkill -f pocketra-bg-host >/dev/null 2>&1 || true; pkill -f "mp-join $CODE" >/dev/null 2>&1 || true; true' EXIT INT TERM
sleep 1

ARGS="--no-intro --mp ws://127.0.0.1:$PORT/mp --map $KARTE --mp-players 3 --mp-log"
( cd "$ROOT" && Godot --path "$ROOT/game" --position 40,60 --resolution 900x560 -- $ARGS \
    --mp-create --mp-name Tom --pocketra-bg-host > "$OUT/host.log" 2>&1 & echo $! > "$OUT/host.pid" )
n=0
while [ $n -lt 90 ]; do
    CODE=$(grep -oa 'MP-CODE: [A-Z0-9]*' "$OUT/host.log" 2>/dev/null | head -1 | cut -d' ' -f2)
    [ -n "$CODE" ] && break
    n=$((n + 1)); sleep 1
done
[ -z "$CODE" ] && { echo "kein Spielcode — siehe $OUT/host.log"; exit 1; }
echo "Spielcode: $CODE"
( cd "$ROOT" && Godot --path "$ROOT/game" --position 980,60 --resolution 900x560 -- $ARGS \
    --mp-join "$CODE" --mp-name Jan > "$OUT/gast.log" 2>&1 & echo $! > "$OUT/gast.pid" )
sleep 20

pgrep -f "pocketra-bg-host" > /dev/null || { echo "Gastgeberprozess nicht gefunden"; exit 1; }
echo "== Hintergrund: SIGSTOP auf den Gastgeber fuer ${PAUSE}s =="
pkill -STOP -f "pocketra-bg-host"
sleep $PAUSE
echo "== zurueck aus dem Hintergrund: SIGCONT =="
pkill -CONT -f "pocketra-bg-host"
sleep 25
pkill -f pocketra-bg-host > /dev/null 2>&1 || true
pkill -f "mp-join $CODE" > /dev/null 2>&1 || true
sleep 2                      # kein `wait`: der Vermittler laeuft als Kindprozess weiter

echo
echo "--- Vermittler ---"
grep -E "create|join|seat_absent|resume|room_closed|resume_expired|disconnect" "$OUT/server.log" || true
echo
echo "--- Gastgeber: Wiederverbinden ---"
grep -aE '"t":"resume"|"t":"session"|"t":"lobby"' "$OUT/host.log" | tail -6 || true
echo
echo "--- Gast: sah er den Platz als absent? ---"
grep -ac '"absent":true' "$OUT/gast.log" | sed 's/^/lobby-Zeilen mit absent: /'
echo
if grep -q "room_closed" "$OUT/server.log"; then
    echo "FEHL: der Raum wurde geschlossen"
    RC=1
else
    echo "ok  : der Raum blieb bestehen"
    RC=0
fi
if grep -q " resume " "$OUT/server.log"; then
    echo "ok  : resume hat den Platz zurueckgeholt"
else
    echo "FEHL: kein resume im Protokoll"
    RC=1
fi
exit $RC
