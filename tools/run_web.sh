#!/bin/bash
# Start CORS proxy and Flutter web in one command.
# Usage: ./tools/run_web.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Start CORS proxy if not already running
if ! lsof -i :9090 >/dev/null 2>&1; then
  echo "Starting CORS proxy on port 9090..."
  node "$SCRIPT_DIR/cors_proxy.js" &
  PROXY_PID=$!
  sleep 1
  echo "CORS proxy started (PID: $PROXY_PID)"
else
  echo "CORS proxy already running on port 9090"
  PROXY_PID=""
fi

# Run Flutter web
cd "$PROJECT_DIR"
flutter run -d chrome

# Cleanup proxy on exit
if [ -n "$PROXY_PID" ]; then
  echo "Stopping CORS proxy..."
  kill $PROXY_PID 2>/dev/null
fi
