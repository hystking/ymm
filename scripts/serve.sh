#!/usr/bin/env bash
#
# Run the ymm player locally for development / preview — no AWS, no deploy.
#
# Regenerates playlist.json from ./music, then serves ./site over HTTP with
# /music/* transparently mapped to ./music, so the player behaves exactly as
# it does on CloudFront. Open the printed URL in your browser.
#
# The player fetches playlist.json over HTTP, so opening site/index.html via
# file:// does NOT work — use this server instead.
#
# Usage:
#   scripts/serve.sh            # serve on http://127.0.0.1:8000
#   scripts/serve.sh 9000       # serve on port 9000
#   PORT=9000 scripts/serve.sh  # same, via env var
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-${PORT:-8000}}"

PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "python3 is required for the local server but was not found." >&2; exit 1; }

# 1. Regenerate playlist.json from the local mp3 files.
"$ROOT/scripts/gen-playlist.sh"

# 2. Serve the site, mapping /music/* to the repo's music directory.
echo
echo "  ymm — local preview"
echo "  ▶  http://127.0.0.1:$PORT"
echo "  serving ./site (music from ./music) — press Ctrl+C to stop"
echo
exec "$PY" "$ROOT/scripts/serve.py" "$ROOT/site" "$ROOT/music" "$PORT"
