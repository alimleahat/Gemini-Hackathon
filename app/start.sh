#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$REPO_ROOT/.venv/bin/python" ]; then
    PYTHON="$REPO_ROOT/.venv/bin/python"
else
    PYTHON="python3"
fi

PORT="${PORT:-8000}"

# Open browser automatically on macOS after the server starts
if command -v open >/dev/null 2>&1; then
    (sleep 1.2 && open "http://127.0.0.1:${PORT}") &
fi

exec "$PYTHON" "$SCRIPT_DIR/server.py"
