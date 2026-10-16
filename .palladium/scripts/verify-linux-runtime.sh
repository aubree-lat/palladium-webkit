#!/usr/bin/env bash
set -euo pipefail

print_required() {
  printf '%s\n' 'libwebkit2gtk-4.1.so'
  printf '%s\n' 'librice-proto'
  printf '%s\n' 'librice-io'
  printf '%s\n' 'libgstwebrtc'
  printf '%s\n' 'pipewiresrc'
  printf '%s\n' 'opusenc opusdec'
  printf '%s\n' 'vp8enc vp8dec'
  printf '%s\n' 'xdg-desktop-portal'
}

if [ "${1:-}" = --print-required ]; then
  print_required
  exit 0
fi

if [ -n "${1:-}" ]; then
  printf 'unknown argument: %s\n' "$1" >&2
  exit 2
fi

if [ "$(uname -s)" != Linux ]; then
  printf '%s\n' 'The private WebKitGTK runtime can only be verified on Linux.' >&2
  exit 2
fi

data_root=${XDG_DATA_HOME:-${HOME:?}/.local/share}
prefix=${WEBKIT_PREFIX:-$data_root/palladium/webkit-2.54.1}
library=$prefix/lib/libwebkit2gtk-4.1.so
status=0

for path in "$library" "$prefix/lib/pkgconfig/rice-proto.pc" "$prefix/lib/pkgconfig/rice-io.pc"; do
  if [ ! -e "$path" ]; then
    printf 'missing runtime file: %s\n' "$path" >&2
    status=1
  fi
done

for tool in ldd pkg-config gst-inspect-1.0; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing runtime diagnostic tool: %s\n' "$tool" >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then exit "$status"; fi

export LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

if [ "$(pkg-config --modversion webkit2gtk-4.1)" != 2.54.1 ]; then
  printf '%s\n' 'webkit2gtk-4.1 does not resolve to version 2.54.1.' >&2
  status=1
fi

for module in rice-proto rice-io; do
  if [ "$(pkg-config --modversion "$module")" != 0.4.3 ]; then
    printf '%s does not resolve to version 0.4.3.\n' "$module" >&2
    status=1
  fi
done

if ! ldd "$library" | grep -F "$prefix/lib/librice-proto" >/dev/null; then
  printf '%s\n' 'WebKitGTK does not resolve librice-proto from the private runtime.' >&2
  status=1
fi

for element in webrtcbin pipewiresrc opusenc opusdec vp8enc vp8dec; do
  if ! gst-inspect-1.0 "$element" >/dev/null 2>&1; then
    printf 'missing GStreamer element: %s\n' "$element" >&2
    status=1
  fi
done

if ! command -v xdg-desktop-portal >/dev/null 2>&1 && [ ! -x /usr/lib/xdg-desktop-portal ] && [ ! -x /usr/libexec/xdg-desktop-portal ] && ! pgrep -x xdg-desktop-portal >/dev/null 2>&1; then
  printf '%s\n' 'xdg-desktop-portal is not installed or running.' >&2
  status=1
fi

if [ "$status" -ne 0 ]; then exit "$status"; fi
printf 'Private Linux media runtime verified at %s\n' "$prefix"
