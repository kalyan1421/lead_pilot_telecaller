#!/usr/bin/env bash
#
# run-dev.sh — one command to develop the telecaller app on a device.
#
# Keeps the `adb reverse tcp:8000 tcp:8000` tunnel alive (so the app can reach
# the backend at 127.0.0.1:8000 — see keep-adb-reverse.sh for why) AND runs
# `flutter run` in the foreground. When you quit flutter (press q), the tunnel
# watcher is stopped automatically.
#
# Usage:  ./tool/run-dev.sh                 # run on the connected device
#         ./tool/run-dev.sh -d <device-id>  # pick a device
#         ./tool/run-dev.sh --release       # any flutter-run args pass through
#
# NOTE: this does NOT start the backend. Start that separately, e.g.:
#   cd ../voicesummary-main && uvicorn app.main:app --host 0.0.0.0 --port 8000
#
set -euo pipefail

PORT="${PORT:-8000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "run-dev: waiting for a device…"
adb wait-for-device

# Set the tunnel up immediately so the very first request works, then start the
# watcher to re-establish it on every reconnect for the rest of the session.
adb reverse "tcp:${PORT}" "tcp:${PORT}" >/dev/null 2>&1 || true
echo "run-dev: adb reverse tcp:${PORT} -> tcp:${PORT} is up"

PORT="$PORT" "${SCRIPT_DIR}/keep-adb-reverse.sh" >/dev/null 2>&1 &
WATCHER_PID=$!

# Always stop the watcher when flutter exits (quit, Ctrl-C, or error).
cleanup() {
  kill "$WATCHER_PID" >/dev/null 2>&1 || true
  echo "run-dev: stopped tunnel watcher"
}
trap cleanup EXIT

echo "run-dev: starting flutter run (tunnel watcher pid ${WATCHER_PID})"
cd "$PROJECT_DIR"
flutter run "$@"
