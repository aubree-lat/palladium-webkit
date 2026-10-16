#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repository/.palladium/pins.env"
base=$(
  cat "$repository/.palladium/pins.env" \
    "$repository/.palladium/scripts/build-librice.sh" \
    "$repository/.palladium/scripts/native-targets.py" \
    "$repository/.palladium/scripts/build-webkit.sh" | sha256sum | cut -d' ' -f1
)
source_hash=$(sha256sum "$repository/.palladium/patches/source.patch" | cut -d' ' -f1)
printf 'base=%s\nsource=%s\n' "$base" "$source_hash"
