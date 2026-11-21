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

# Stop any older instance already listening on PORT so code updates take effect
if command -v lsof >/dev/null 2>&1; then
    OLD_PIDS="$(lsof -tiTCP:"${PORT}" -sTCP:LISTEN || true)"
    if [ -n "$OLD_PIDS" ]; then
        kill $OLD_PIDS 2>/dev/null || true
        sleep 0.4
    fi
fi

# Open browser automatically on macOS after the server starts
if command -v open >/dev/null 2>&1; then
    (sleep 1.2 && open "http://127.0.0.1:${PORT}") &
fi

exec "$PYTHON" "$SCRIPT_DIR/server.py"
