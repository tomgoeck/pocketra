#!/bin/sh
# Hintergrundwechsel im Mehrspieler pruefen (docs/MULTIPLAYER.md §10, Toms Befund 2026-09-09:
# „Raum war weg, nachdem ich in WhatsApp geschrieben habe").
#
#   sh tools/mp_bg_test.sh [AUSGABEORDNER]
#
# Ablauf: eigener Vermittler auf 127.0.0.1, zwei Godot-Fenster in einer Lobby (drei Plaetze gewuenscht,
# also startet nichts von allein), dann bekommt der **Gastgeber** SIGSTOP — genau das macht Android
# mit der App, wenn man zu WhatsApp wechselt: die Hauptschleife steht, `WebSocketPeer.poll()` laeuft
# nicht mehr, der Vermittler bekommt keine Pong-Rahmen und trennt. Nach der Pause SIGCONT.
#
# Erwartet:
#   * Vermittler protokolliert `seat_absent` (Platz bleibt reserviert), NICHT `room_closed`
#   * der Gast bekommt eine `lobby` mit `absent: true` fuer Platz 0 — der Raum bleibt stehen
#   * nach SIGCONT: `resume` im Protokoll, derselbe Platz, derselbe Gastgeber
#
# WICHTIG: mit `sh` starten, nicht mit `zsh`.
# Absolute Pfade fuer `--path`: parallele Arbeitsbaeume raeumen mit `pkill -f 'Godot --path game'`
# auf und wuerden diesen Lauf sonst mit abraeumen.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/build/mp-bg-test}
PORT=${PORT:-8795}
KARTE=${KARTE:-keep-off-the-grass-2}
# So lange bleibt der Platz reserviert; die Pause muss kuerzer sein.
RESUME=${RESUME:-90}
# Der Vermittler merkt einen eingefrorenen Client erst ueber die WebSocket-Pings
# (ping_interval 20 s + ping_timeout 20 s) — die Pause muss darueber liegen.
PAUSE=${PAUSE:-60}
VENV=$ROOT/build/.venv_mp/bin/python
[ -x "$VENV" ] || { echo "build/.venv_mp fehlt — siehe server/README.md"; exit 1; }
mkdir -p "$OUT"
rm -f "$OUT"/*.log

"$VENV" "$ROOT/server/mp_server.py" --host 127.0.0.1 --port $PORT --resume-s $RESUME \
    --create-per-min 30 > "$OUT/server.log" 2>&1 &
SRV=$!
# Der EXIT-Handler darf den Rueckgabewert nicht ueberschreiben — deshalb `true` am Ende.
# Jeder Befehl mit `|| true`: unter `set -e` bricht ein erfolgloses `pkill` sonst den Handler ab
# und schiebt dessen 1 als Rueckgabewert des ganzen Skripts nach vorn.
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

# Godot laeuft in einer Huelle; `pkill -f` trifft beide — nur so steht die Schleife wirklich still.
pgrep -f "pocketra-bg-host" > /dev/null || { echo "Gastgeberprozess nicht gefunden"; exit 1; }
echo "== Hintergrund: SIGSTOP auf den Gastgeber fuer ${PAUSE}s =="
pkill -STOP -f "pocketra-bg-host"
sleep $PAUSE
echo "== zurueck aus dem Hintergrund: SIGCONT =="
pkill -CONT -f "pocketra-bg-host"
sleep 25
# Erst die Fenster schliessen, dann auswerten — sonst schiebt die Jobverwaltung der Shell ihre
# "Terminated"-Meldungen mitten in die Zusammenfassung.
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
