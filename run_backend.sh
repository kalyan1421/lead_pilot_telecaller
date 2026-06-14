#!/usr/bin/env bash
# Launch the FastAPI "AI layer" backend (voicesummary-main) for the Flutter app.
# Usage:  ./run_backend.sh        (from the lead_pilot_telecaller folder)
# See RUNBOOK.md for one-time setup (Postgres, venv, deps, .env).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$HERE/../voicesummary-main"

if [[ ! -d "$BACKEND" ]]; then
  echo "✗ Backend not found at: $BACKEND" >&2
  exit 1
fi
cd "$BACKEND"

# Ensure Postgres is up (Homebrew Postgres 14).
if command -v pg_isready >/dev/null 2>&1 && ! pg_isready -q; then
  echo "→ Starting PostgreSQL…"
  brew services start postgresql@14 >/dev/null 2>&1 || \
    pg_ctl -D /opt/homebrew/var/postgresql@14 -l /tmp/pg14.log start || true
fi

if [[ ! -x ".venv/bin/python" ]]; then
  echo "✗ No venv at $BACKEND/.venv — run the one-time setup in RUNBOOK.md §1b" >&2
  exit 1
fi
# shellcheck disable=SC1091
source .venv/bin/activate

echo "→ Backend on http://0.0.0.0:8000  (docs: http://localhost:8000/docs)"
exec python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
