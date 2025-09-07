#!/usr/bin/env bash
set -euo pipefail

# go to pocketbase folder and run the binary exactly as you wanted
cd /app/release/pocketbase

# graceful shutdown handler
_term() {
  echo "Caught termination signal, stopping pocketbase..."
  kill -TERM "${PB_PID}" 2>/dev/null || true
  wait "${PB_PID}" || true
  exit 0
}
trap _term SIGINT SIGTERM

echo "Starting PocketBase on 127.0.0.1:8090 ..."
./pocketbase serve --http="127.0.0.1:8090" &

PB_PID=$!

# small wait to let PB bind
sleep 1

echo "Starting nginx (foreground) ..."
exec nginx -g "daemon off;"
