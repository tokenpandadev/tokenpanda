#!/bin/sh
# The status line hook. Copies the feed Claude Code hands it to one file per session, atomically,
# then hands the same input to the status line command that was configured before, if any.
# It parses nothing and needs nothing but sh. The app fills in DIR and PREV at install time.
DIR="__DIR__"
PREV='__PREV__'
input=$(cat)
sid=$(printf '%s' "$input" | sed -n 's/.*"session_id":"\([0-9a-fA-F-]*\)".*/\1/p' | head -n 1)
mkdir -p "$DIR"
if [ -n "$sid" ]; then
  printf '%s' "$input" > "$DIR/$sid.json.tmp" && mv -f "$DIR/$sid.json.tmp" "$DIR/$sid.json"
else
  printf '%s' "$input" > "$DIR/latest.json.tmp" && mv -f "$DIR/latest.json.tmp" "$DIR/latest.json"
fi
if [ -n "$PREV" ]; then printf '%s' "$input" | sh -c "$PREV"; fi
exit 0
