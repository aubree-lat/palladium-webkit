#!/usr/bin/env bash
set -euo pipefail

repository=$(git rev-parse --show-toplevel)
source "$repository/.palladium/pins.env"
output=${1:?usage: prepare-source.sh OUTPUT_DIRECTORY}
mkdir -p "$output"

if ! git cat-file -e "$WEBKIT_UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
  git fetch --filter=blob:none --depth=1 https://github.com/WebKit/WebKit.git "$WEBKIT_UPSTREAM_COMMIT"
fi
git diff --binary --no-ext-diff "$WEBKIT_UPSTREAM_COMMIT" -- Source Tools CMakeLists.txt > "$output/palladium.patch"
if [ ! -s "$output/palladium.patch" ]; then
  printf '%s\n' 'The fork contains no downstream source changes.' >&2
  exit 1
fi
archive=$output/webkitgtk-$WEBKIT_VERSION.tar.xz
if [ ! -f "$archive" ]; then
  curl --fail --location --retry 3 --output "$archive.part" "https://webkitgtk.org/releases/webkitgtk-$WEBKIT_VERSION.tar.xz"
  mv "$archive.part" "$archive"
fi
printf '%s  %s\n' "$WEBKIT_SHA256" "$archive" | sha256sum --check --status
if [ "${PALLADIUM_SOURCE_CHECK_ONLY:-0}" = 1 ]; then
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT
  tar -xf "$archive" -C "$temporary"
  patch -d "$temporary/webkitgtk-$WEBKIT_VERSION" -p1 --batch --dry-run < "$output/palladium.patch"
fi
