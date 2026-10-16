#!/usr/bin/env bash
set -euo pipefail
repository=$(git rev-parse --show-toplevel)
cd "$repository"
source .palladium/pins.env
mkdir -p .palladium/patches
git diff --binary --no-ext-diff "$WEBKIT_UPSTREAM_COMMIT" -- Source Tools CMakeLists.txt > .palladium/patches/source.patch
git diff --name-only "$WEBKIT_UPSTREAM_COMMIT" -- Source Tools CMakeLists.txt | LC_ALL=C sort | while IFS= read -r path; do
  sha256sum "$path"
done > .palladium/source-files.sha256
