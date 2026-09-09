#!/bin/sh
# Mehrspieler-Prüflauf am Mac (docs/MULTIPLAYER.md §7): mehrere Godot-Fenster gegen den lokalen
# Vermittler, gleiches Befehlsskript auf allen Seiten, danach `tools/mp_diff.py`.
#
#   build/.venv_mp/bin/python server/mp_server.py --host 127.0.0.1 --port 8787 &
#   SPIELER=2 RAHMEN=400 tools/mp_local_test.sh [AUSGABEORDNER]
#
# Umgebung: SPIELER (2..6), RAHMEN (Netzrahmen bis zum Ende), KARTE, PORT, OEFFENTLICH, TEAMS,
# STARTPUNKTE, FUNK.
# FUNK=team|all: Sprechfunk mitlaufen lassen (`--mp-voice`, Sinuston statt Mikrofon) — jede Instanz
# schreibt `MP-FUNK seat N an/aus`, sobald sie einen anderen Platz hoert (docs/MULTIPLAYER.md §11).
# OEFFENTLICH=1: der Gastgeber legt einen **oeffentlichen** Raum an (`create.public`), die uebrigen
# Instanzen tippen ihn in der Raumliste der Beitreten-Seite an (`--mp-join-list`) statt den Code
# einzutippen — der Weg aus Toms Wunsch 2026-09-07.
# TEAMS="1 1": je Instanz eine Teamzahl (0 = kein Team) — die Instanz schickt `slot{team}` und
# meldet sich erst danach bereit. STARTPUNKTE="0 3": dasselbe fuer `slot{spawn}`.
# Damit prueft man Toms Befund 2026-09-09 („beide Team 1, im Spiel trotzdem Gegner"):
#   TEAMS="1 1" SPIELER=2 RAHMEN=120 sh tools/mp_local_test.sh build/mp-team
#   grep -a 'Mehrspieler-Teams' build/mp-team/p*.log   # Gegnerliste muss leer sein
# Ergebnis: <AUSGABE>/p<N>.log je Instanz, Bildschirmfotos in <AUSGABE>/shots.
# WICHTIG: mit `sh` starten, nicht mit `zsh` — zsh zerlegt $ARGS nicht in einzelne Wörter.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/build/mp-test}
SPIELER=${SPIELER:-2}
RAHMEN=${RAHMEN:-400}
KARTE=${KARTE:-keep-off-the-grass-2}
PORT=${PORT:-8787}
NAMEN="Tom Jan Ada Bo Kim Lea"
mkdir -p "$OUT/shots"
rm -f "$OUT"/p*.log
ARGS="--no-intro --mp ws://127.0.0.1:$PORT/mp --map $KARTE --mp-players $SPIELER --mp-autoplay $RAHMEN --mp-shot $OUT/shots --mp-chat-every 15"
[ -n "$FUNK" ] && ARGS="$ARGS --mp-voice $FUNK"
# Team- und Startpunktwunsch je Instanz (leer = wie bisher, der Vermittler wuerfelt)
platz_args() {
    n=$1; out=""; k=1
    for t in $TEAMS; do
        [ "$k" = "$n" ] && out="$out --mp-team $t"
        k=$((k + 1))
    done
    k=1
    for s in $STARTPUNKTE; do
        [ "$k" = "$n" ] && out="$out --mp-spawn $s"
        k=$((k + 1))
    done
    echo "$out"
}
i=1
for name in $NAMEN; do
    [ "$i" -gt "$SPIELER" ] && break
    X=$(( 40 + (i - 1) % 2 * 920 ))
    Y=$(( 60 + (i - 1) / 2 * 600 ))
    PLATZ=$(platz_args "$i")
    if [ "$i" = 1 ]; then
        [ -n "$OEFFENTLICH" ] && PUB="--mp-public" || PUB=""
        ( cd "$ROOT" && Godot --path game --position $X,$Y --resolution 900x560 -- $ARGS $PUB $PLATZ \
            --mp-create --mp-name "$name" --mp-chat-lobby "Alle bereit?" > "$OUT/p1.log" 2>&1 & )
        # auf den Spielcode warten (Godot braucht am Mac gut 15 s bis zum Menü)
        n=0
        while [ $n -lt 60 ]; do
            CODE=$(grep -oa 'MP-CODE: [A-Z0-9]*' "$OUT/p1.log" 2>/dev/null | head -1 | cut -d' ' -f2)
            [ -n "$CODE" ] && break
            n=$((n + 1)); sleep 1
        done
        [ -z "$CODE" ] && { echo "kein Spielcode — Vermittler laeuft?"; exit 1; }
        echo "Spielcode: $CODE"
    else
        [ -n "$OEFFENTLICH" ] && WEG="--mp-join-list" || WEG="--mp-join $CODE"
        ( cd "$ROOT" && Godot --path game --position $X,$Y --resolution 900x560 -- $ARGS $PLATZ \
            $WEG --mp-name "$name" --mp-chat-lobby "Bin da." > "$OUT/p$i.log" 2>&1 & )
        sleep 3
    fi
    i=$((i + 1))
done
echo "$SPIELER Instanzen gestartet, $RAHMEN Rahmen. Danach:"
echo "  python3 $ROOT/tools/mp_diff.py $OUT/p1.log $OUT/p2.log"
