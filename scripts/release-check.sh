#!/bin/sh
# Release check: no leftover placeholder text and no absolute home path in any text file of the repository.
# The one allowed home path is the generic example /Users/someone in tests and fixtures.
# Casks/tokenpanda.rb is skipped: its RELEASE_VERSION and RELEASE_SHA256 are set by each release.
#   scripts/release-check.sh
cd "$(dirname "$0")/.." || exit 2
EXCLUDES="--exclude-dir=.git --exclude-dir=.build --exclude-dir=build --exclude=release-check.sh --exclude=tokenpanda.rb"
PLACEHOLDERS=$(grep -rniIE 'goes here|placeholder|<app>|no name yet|the owner' $EXCLUDES . 2>/dev/null)
PATHS=$(grep -rnIE '/Users/[A-Za-z0-9._-]' $EXCLUDES . 2>/dev/null | sed 's#/Users/someone##g' | grep -E '/Users/[A-Za-z0-9._-]')
if [ -n "$PLACEHOLDERS$PATHS" ]; then
  [ -n "$PLACEHOLDERS" ] && { echo "placeholders:"; echo "$PLACEHOLDERS"; }
  [ -n "$PATHS" ] && { echo "absolute paths:"; echo "$PATHS"; }
  exit 1
fi
echo "release check: 0 hits"
