#!/bin/bash
# Start CORS proxy and Flutter web in one command.
# Usage: ./tools/run_web.sh
#
# curl-impersonate (opt-in): some sources (e.g. manga18.club, api.comick.dev)
# sit behind a Cloudflare TLS/JA3 fingerprint check that Node's https.request
# cannot pass (403). Setting CURL_IMPERSONATE_HOSTS routes those exact hosts
# through curl-impersonate (real Chrome fingerprint) instead. Only the main
# API hosts are listed; image CDNs (cdn.manga18.club, meo.comick.pictures)
# keep the fast native path.
# Requires: brew install lexiforest/tap/curl-impersonate
# Override the wrapper via CURL_IMPERSONATE_BIN (default: curl_chrome136).
CURL_IMPERSONATE_HOSTS="${CURL_IMPERSONATE_HOSTS:-manga18.club,api.comick.dev}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Start CORS proxy if not already running
if ! lsof -i :9090 >/dev/null 2>&1; then
  echo "Starting CORS proxy on port 9090..."
  HTTPS_PROXY="http://127.0.0.1:2222" CURL_IMPERSONATE_HOSTS="$CURL_IMPERSONATE_HOSTS" node "$SCRIPT_DIR/cors_proxy.js" &
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
