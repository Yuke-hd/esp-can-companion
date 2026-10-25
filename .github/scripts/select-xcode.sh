#!/usr/bin/env bash
# Selects the newest installed Xcode 16 or later; falls back to the image
# default if none match.
set -euo pipefail
xcode=$(ls -d /Applications/Xcode_*.app 2>/dev/null \
  | grep -E 'Xcode_(1[6-9]|[2-9][0-9])(\.[0-9]+)*\.app$' | sort -V | tail -1 || true)
if [ -n "$xcode" ]; then sudo xcode-select -s "$xcode"; fi
xcodebuild -version
