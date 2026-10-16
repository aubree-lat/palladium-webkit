#!/usr/bin/env bash
set -euo pipefail

repository=$(git rev-parse --show-toplevel)
source "$repository/.palladium/pins.env"
if ! git cat-file -e "$WEBKIT_UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
  git fetch --filter=blob:none --depth=1 https://github.com/WebKit/WebKit.git "$WEBKIT_UPSTREAM_COMMIT"
fi
base=$(
  cat "$repository/.palladium/pins.env" \
    "$repository/.palladium/scripts/build-librice.sh" \
    "$repository/.palladium/scripts/build-webkit.sh" | sha256sum | cut -d' ' -f1
)
source_hash=$(git diff --binary --no-ext-diff "$WEBKIT_UPSTREAM_COMMIT" -- Source Tools CMakeLists.txt | sha256sum | cut -d' ' -f1)
printf 'base=%s\nsource=%s\n' "$base" "$source_hash"
