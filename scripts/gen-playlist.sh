#!/usr/bin/env bash
#
# Generate site/playlist.json from the mp3 files in ./music.
#
# Track title  = file name without extension (underscores -> spaces).
# Track artist = parsed from "Artist - Title.mp3" if a " - " is present,
#                otherwise "Unknown artist".
#
# Run this whenever you add or remove mp3s, then deploy with scripts/deploy.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUSIC_DIR="$ROOT/music"
OUT="$ROOT/site/playlist.json"

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Collect *.mp3 (case-insensitive) into FILES, portable to bash 3.2 (no mapfile).
FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && FILES+=("$f")
done < <(cd "$MUSIC_DIR" && ls -1 2>/dev/null | grep -iE '\.mp3$' | sort)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No mp3 files found in $MUSIC_DIR — nothing to do." >&2
  echo '{ "tracks": [] }' > "$OUT"
  exit 0
fi

{
  echo '{'
  echo '  "tracks": ['
  for i in "${!FILES[@]}"; do
    file="${FILES[$i]}"
    base="${file%.*}"
    if [[ "$base" == *" - "* ]]; then
      artist="${base%% - *}"
      title="${base#* - }"
    else
      artist="Unknown artist"
      title="${base//_/ }"
    fi
    comma=","
    [ "$i" -eq $(( ${#FILES[@]} - 1 )) ] && comma=""
    printf '    { "title": "%s", "artist": "%s", "src": "music/%s" }%s\n' \
      "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$file")" "$comma"
  done
  echo '  ]'
  echo '}'
} > "$OUT"

echo "Wrote ${#FILES[@]} track(s) to $OUT"
