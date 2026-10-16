#!/usr/bin/env bash
set -euo pipefail

prefix=
output=
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cache_root=${XDG_CACHE_HOME:-${HOME:?}/.cache}
webkit_source=${WEBKIT_SOURCE:-$cache_root/palladium/webkit-build/webkitgtk-2.54.1}
librice_source=${LIBRICE_SOURCE:-$cache_root/palladium/librice}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      prefix=${2:-}
      shift 2
      ;;
    --output)
      output=${2:-}
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ "$(uname -s)" != Linux ] && [ "${PALLADIUM_PACKAGE_TEST:-0}" != 1 ]; then
  printf '%s\n' 'The private WebKitGTK runtime can only be packaged on Linux.' >&2
  exit 2
fi

if [ -z "$prefix" ] || [ -z "$output" ]; then
  printf '%s\n' 'usage: package-linux-runtime.sh --prefix PATH --output PATH' >&2
  exit 2
fi

if [ ! -d "$prefix/lib" ] || [ -e "$output" ]; then
  printf '%s\n' 'The runtime prefix must exist and the output path must not exist.' >&2
  exit 2
fi

output_parent=$(dirname "$output")
mkdir -p "$output_parent"
staging=$(mktemp -d "$output_parent/.palladium-runtime.XXXXXX")
cleanup() {
  if [ -d "$staging" ]; then
    rm -rf "$staging"
  fi
}
trap cleanup EXIT

mkdir -p "$staging/lib"
for pattern in 'libwebkit2gtk-4.1.so*' 'libjavascriptcoregtk-4.1.so*' 'librice-proto.so*' 'librice-io.so*'; do
  find "$prefix/lib" -maxdepth 1 \( -type f -o -type l \) -name "$pattern" -exec cp -a {} "$staging/lib/" \;
done

if [ ! -d "$prefix/lib/webkit2gtk-4.1" ]; then
  printf '%s\n' 'The WebKitGTK helper-process directory is missing.' >&2
  exit 2
fi
cp -a "$prefix/lib/webkit2gtk-4.1" "$staging/lib/"
if [ -d "$prefix/lib/girepository-1.0" ]; then
  cp -a "$prefix/lib/girepository-1.0" "$staging/lib/"
fi
node "$root/scripts/relocate-linux-runtime.mjs" "$staging" "$prefix"

webcore_license=$webkit_source/Source/WebCore/LICENSE-LGPL-2.1
javascriptcore_license=$webkit_source/Source/JavaScriptCore/COPYING.LIB
for path in "$webcore_license" "$javascriptcore_license" "$librice_source/LICENSE-APACHE" "$librice_source/LICENSE-MIT"; do
  if [ ! -f "$path" ]; then
    printf 'missing runtime license: %s\n' "$path" >&2
    exit 2
  fi
done
mkdir -p "$staging/share/licenses/webkitgtk/patches" "$staging/share/licenses/librice"
install -m 644 "$webcore_license" "$staging/share/licenses/webkitgtk/WebCore-LGPL-2.1"
install -m 644 "$javascriptcore_license" "$staging/share/licenses/webkitgtk/JavaScriptCore-COPYING.LIB"
install -m 644 "$librice_source/LICENSE-APACHE" "$staging/share/licenses/librice/LICENSE-APACHE"
install -m 644 "$librice_source/LICENSE-MIT" "$staging/share/licenses/librice/LICENSE-MIT"
install -m 644 "${WEBKIT_PATCH_FILE:?}" "$staging/share/licenses/webkitgtk/patches/palladium.patch"

for path in \
  "$staging/lib/libwebkit2gtk-4.1.so.0" \
  "$staging/lib/libjavascriptcoregtk-4.1.so.0" \
  "$staging/lib/webkit2gtk-4.1/WebKitWebProcess" \
  "$staging/lib/webkit2gtk-4.1/WebKitNetworkProcess" \
  "$staging/lib/webkit2gtk-4.1/WebKitGPUProcess" \
  "$staging/lib/webkit2gtk-4.1/injected-bundle/libwebkit2gtkinjectedbundle.so"; do
  if [ ! -e "$path" ]; then
    printf 'missing private runtime component: %s\n' "$path" >&2
    exit 2
  fi
done

if ! find "$staging/lib" -maxdepth 1 -name 'librice-proto.so*' -print -quit | grep -q .; then
  printf '%s\n' 'The private runtime is missing librice-proto.' >&2
  exit 2
fi
if ! find "$staging/lib" -maxdepth 1 -name 'librice-io.so*' -print -quit | grep -q .; then
  printf '%s\n' 'The private runtime is missing librice-io.' >&2
  exit 2
fi

printf 'WEBKITGTK=2.54.1\nWEBKITGTK_SHA256=ea0bbb02dbdbc596874a4e7ad35b66645b3e0a232bd0e4081de5ed92eb0a397d\nLIBRICE=0.4.3\nLIBRICE_REVISION=afd70fdd7ca96a39824c55e6b373bac97311f2ba\n' > "$staging/VERSION"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

(
  cd "$staging"
  find . \( -type f -o -type l \) ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r path; do
    digest=$(hash_file "$path")
    printf '%s  %s\n' "$digest" "${path#./}"
  done > manifest.sha256
)

epoch=${SOURCE_DATE_EPOCH:-0}
if touch -h -d "@$epoch" "$staging" 2>/dev/null; then
  find "$staging" -exec touch -h -d "@$epoch" {} +
fi

chmod 755 "$staging"
mv "$staging" "$output"
trap - EXIT
printf 'Private Linux runtime staged at %s\n' "$output"
