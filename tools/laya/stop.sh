#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
MAIN="${COMMON:+$(dirname "$COMMON")}"
MAIN="${MAIN:-$(cd "$HERE/../.." && pwd)}"
PIDFILE="$MAIN/build/laya/service.pid"
PORT="${LAYA_PORT:-8765}"

pids=""
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  pids="$(cat "$PIDFILE")"
fi
for p in $(lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true); do
  if ps -o command= -p "$p" | grep -q "laya/service.py"; then
    case " $pids " in *" $p "*) ;; *) pids="$pids $p" ;; esac
  fi
done
if [ -z "${pids// /}" ]; then
  echo "Kein Laya-Dienst gefunden (Port $PORT)."
  rm -f "$PIDFILE"
  exit 0
fi
kill $pids
for i in $(seq 1 10); do
  alive=0
  for p in $pids; do if kill -0 "$p" 2>/dev/null; then alive=1; fi; done
  if [ "$alive" = 0 ]; then break; fi
  sleep 0.5
done
for p in $pids; do if kill -0 "$p" 2>/dev/null; then kill -9 "$p"; fi; done
rm -f "$PIDFILE"
echo "Laya-Dienst beendet (PID ${pids# })."
