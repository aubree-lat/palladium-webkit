#!/usr/bin/env bash
set -euo pipefail

LIBRICE_REVISION=${LIBRICE_REVISION:-afd70fdd7ca96a39824c55e6b373bac97311f2ba}
CARGO_C_VERSION=${CARGO_C_VERSION:-0.10.25+cargo-0.99.0}
RUST_MINIMUM=1.96.0

if [ "${1:-}" = --print-pin ]; then
  printf 'LIBRICE_REVISION=%s\n' "$LIBRICE_REVISION"
  printf 'CARGO_C_VERSION=%s\n' "$CARGO_C_VERSION"
  printf 'RUST_MINIMUM=%s\n' "$RUST_MINIMUM"
  exit 0
fi

if [ -n "${1:-}" ]; then
  printf 'unknown argument: %s\n' "$1" >&2
  exit 2
fi

if [ "$(uname -s)" != Linux ]; then
  printf '%s\n' 'librice for the WebKitGTK runtime can only be built on Linux.' >&2
  exit 2
fi

for tool in cargo git pkg-config rustc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing build tool: %s\n' "$tool" >&2
    exit 2
  fi
done

rust_version=$(rustc --version | awk '{ print $2 }')
IFS=. read -r rust_major rust_minor rust_patch <<< "$rust_version"
if [ "$rust_major" -lt 1 ] || { [ "$rust_major" -eq 1 ] && [ "$rust_minor" -lt 96 ]; }; then
  printf 'Rust %s or newer is required; found %s.\n' "$RUST_MINIMUM" "$rust_version" >&2
  exit 2
fi

data_root=${XDG_DATA_HOME:-${HOME:?}/.local/share}
cache_root=${XDG_CACHE_HOME:-${HOME:?}/.cache}
prefix=${WEBKIT_PREFIX:-$data_root/palladium/webkit-2.54.1}
source_dir=${LIBRICE_SRC:-$cache_root/palladium/librice}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v cargo-cinstall >/dev/null 2>&1 || ! cargo-cinstall --version | grep -Fq "0.10.25"; then
  cargo install cargo-c --version "$CARGO_C_VERSION" --locked
fi

mkdir -p "$(dirname "$source_dir")" "$prefix"
if [ -e "$source_dir" ] && [ ! -d "$source_dir/.git" ]; then
  printf '%s exists but is not a Git checkout\n' "$source_dir" >&2
  exit 2
fi
if [ ! -d "$source_dir/.git" ]; then
  git clone https://github.com/ystreet/librice.git "$source_dir"
fi

git -C "$source_dir" fetch --depth 1 origin "$LIBRICE_REVISION"
if [ -n "$(git -C "$source_dir" status --porcelain)" ] && [ "$(git -C "$source_dir" rev-parse HEAD)" != "$LIBRICE_REVISION" ]; then
  printf '%s\n' 'The librice checkout has local changes and cannot switch to the pinned revision.' >&2
  exit 2
fi
git -C "$source_dir" checkout --detach "$LIBRICE_REVISION"

if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$LIBRICE_REVISION" ]; then
  printf '%s\n' 'The librice checkout does not match the pinned revision.' >&2
  exit 2
fi

cd "$source_dir"
if [ -f "$root/patches/librice/series" ]; then
  while IFS= read -r patch_name; do
    if [ -z "$patch_name" ]; then continue; fi
    if git apply --check "$root/patches/librice/$patch_name"; then
      git apply "$root/patches/librice/$patch_name"
    elif ! git apply --reverse --check "$root/patches/librice/$patch_name"; then
      printf 'cannot apply librice patch: %s\n' "$patch_name" >&2
      exit 2
    fi
  done < "$root/patches/librice/series"
fi

cargo test --workspace --locked
for crate in rice-proto rice-io; do
  cargo cinstall -p "$crate" --release --locked --prefix="$prefix" --libdir="$prefix/lib" --includedir="$prefix/include"
done

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
for module in rice-proto rice-io; do
  if [ "$(pkg-config --modversion "$module")" != 0.4.3 ]; then
    printf '%s did not install as version 0.4.3\n' "$module" >&2
    exit 2
  fi
done

printf 'librice %s installed at %s\n' "$LIBRICE_REVISION" "$prefix"
