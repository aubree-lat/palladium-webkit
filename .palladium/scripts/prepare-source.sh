#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repository/.palladium/pins.env"
output=${1:?usage: prepare-source.sh OUTPUT_DIRECTORY}
mkdir -p "$output"

cp "$repository/.palladium/patches/source.patch" "$output/palladium.patch"
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
  patch -d "$temporary/webkitgtk-$WEBKIT_VERSION" -p1 --batch < "$output/palladium.patch"
  (cd "$temporary/webkitgtk-$WEBKIT_VERSION" && sha256sum --check "$repository/.palladium/source-files.sha256")
fi
