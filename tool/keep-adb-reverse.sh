#!/usr/bin/env bash
#
# keep-adb-reverse.sh — keep the backend reachable from the device.
#
# The app targets http://127.0.0.1:8000 (see lib/src/core/api/api_config.dart),
# which only reaches the Mac's backend through an `adb reverse` tunnel. On a
# Wi-Fi-ADB device that tunnel drops every time ADB/USB reconnects, and the app
# then reports "can't connect to server". This watcher re-establishes the tunnel
# automatically whenever it goes missing, so you never have to re-run it by hand.
#
# Usage:  ./tool/keep-adb-reverse.sh        # leave it running in a terminal
#         PORT=8000 ./tool/keep-adb-reverse.sh
#
set -euo pipefail

PORT="${PORT:-8000}"
INTERVAL="${INTERVAL:-3}"   # seconds between checks
MAPPING="tcp:${PORT} tcp:${PORT}"

echo "keep-adb-reverse: ensuring 'adb reverse ${MAPPING}' stays up (every ${INTERVAL}s). Ctrl-C to stop."

last_state=""
while true; do
  # Only act when exactly one device is actually connected & ready.
  if adb get-state >/dev/null 2>&1; then
    if [ "$last_state" != "device" ]; then
      echo "$(date '+%H:%M:%S') device connected"
      last_state="device"
    fi
    # Re-add the reverse only if it isn't already present (idempotent, cheap).
    if ! adb reverse --list 2>/dev/null | grep -q "tcp:${PORT} tcp:${PORT}"; then
      if adb reverse "tcp:${PORT}" "tcp:${PORT}" >/dev/null 2>&1; then
        echo "$(date '+%H:%M:%S') re-established adb reverse ${MAPPING}"
      fi
    fi
  else
    if [ "$last_state" != "offline" ]; then
      echo "$(date '+%H:%M:%S') waiting for device…"
      last_state="offline"
    fi
  fi
  sleep "$INTERVAL"
done
