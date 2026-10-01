#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKOUT="$(cd "$HERE/../.." && pwd)"
COMMON="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
MAIN="${COMMON:+$(dirname "$COMMON")}"
MAIN="${MAIN:-$CHECKOUT}"

VENV="$MAIN/build/.venv_laya"
MODEL="${LAYA_MODEL_DIR:-$MAIN/build/laya/multilingual-int8}"
LOGDIR="$MAIN/build/laya"
LOG="$LOGDIR/service.log"
PIDFILE="$LOGDIR/service.pid"
PORT="${LAYA_PORT:-8765}"
URL="http://127.0.0.1:$PORT/decide"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

ONLY_SERVICE=0
USE_GODOT=0
GAME_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --nur-dienst) ONLY_SERVICE=1 ;;
    --godot) USE_GODOT=1 ;;
    --) shift; GAME_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unbekannt: $1 (siehe --help)" >&2; exit 2 ;;
  esac
  shift
done

probe() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST -H 'Content-Type: application/json' \
    --data '{"state":"health check","questions":{"ok":{"type":"noul","instructions":"Is the service up?"}}}' \
    "$URL" 2>/dev/null || true
}

mkdir -p "$LOGDIR"

if [ "$(probe)" = "200" ]; then
  echo "Laya-Dienst läuft schon: $URL"
else
  if [ ! -x "$VENV/bin/python" ]; then
    PY="$(command -v python3.13 || command -v python3)"
    echo "Lege venv an: $VENV ($PY)"
    "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install -q -r "$HERE/requirements.txt"
  fi
  if ! "$VENV/bin/python" -c 'import onnxruntime, tokenizers, fastapi, uvicorn' 2>/dev/null; then
    echo "Installiere Pakete aus requirements.txt"
    "$VENV/bin/pip" install -q -r "$HERE/requirements.txt"
  fi
  if [ ! -f "$MODEL/model.onnx" ] || [ ! -f "$MODEL/tokenizer/tokenizer.json" ]; then
    echo "Lade Modell nach $MODEL (rund 360 MB)"
    "$VENV/bin/python" "$HERE/download_model.py" --out "$MODEL"
  fi
  echo "Starte Laya-Dienst auf Port $PORT, Log: $LOG"
  LAYA_MODEL_DIR="$MODEL" LAYA_PORT="$PORT" nohup "$VENV/bin/python" "$HERE/service.py" >>"$LOG" 2>&1 &
  echo $! >"$PIDFILE"
  for i in $(seq 1 90); do
    if [ "$(probe)" = "200" ]; then
      echo "Laya-Dienst bereit nach ${i} s: $URL"
      break
    fi
    if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Laya-Dienst ist beim Start abgestürzt, letzte Zeilen aus $LOG:" >&2
      tail -n 20 "$LOG" >&2
      exit 1
    fi
    sleep 1
  done
  if [ "$(probe)" != "200" ]; then
    echo "Laya-Dienst antwortet nach 90 s nicht, siehe $LOG" >&2
    exit 1
  fi
fi

if [ "$ONLY_SERVICE" = 1 ]; then exit 0; fi

APP=""
for c in "$CHECKOUT/build/macos-dist/PocketRA.app" "$MAIN/build/macos-dist/PocketRA.app"; do
  if [ -d "$c" ]; then APP="$c"; break; fi
done
if [ "$USE_GODOT" = 0 ] && [ -n "$APP" ]; then
  echo "Starte $APP mit --commander-url $URL ${GAME_ARGS[*]:-}"
  open -n "$APP" --args -- --no-update-pack --commander-url "$URL" ${GAME_ARGS[@]+"${GAME_ARGS[@]}"}
else
  echo "Starte Godot --path $CHECKOUT/game mit --commander-url $URL ${GAME_ARGS[*]:-}"
  "$GODOT" --path "$CHECKOUT/game" -- --no-update-pack --commander-url "$URL" ${GAME_ARGS[@]+"${GAME_ARGS[@]}"}
fi
echo "Dienst beenden: tools/laya/stop.sh"
