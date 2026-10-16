#!/usr/bin/env bash
set -euo pipefail

WEBKIT_PINNED_VERSION=2.54.1
WEBKIT_PINNED_SHA256=ea0bbb02dbdbc596874a4e7ad35b66645b3e0a232bd0e4081de5ed92eb0a397d
WEBKIT_VERSION=${WEBKIT_VERSION:-$WEBKIT_PINNED_VERSION}
WEBKIT_SHA256=${WEBKIT_SHA256:-$WEBKIT_PINNED_SHA256}
USE_LIBRICE=${USE_LIBRICE:-ON}

print_pins() {
  printf 'WEBKIT_VERSION=%s\n' "$WEBKIT_VERSION"
  printf 'WEBKIT_SHA256=%s\n' "$WEBKIT_SHA256"
  printf 'USE_LIBRICE=%s\n' "$USE_LIBRICE"
}

detect_distro() {
  if [ -n "${PALLADIUM_DISTRO:-}" ]; then
    printf '%s\n' "$PALLADIUM_DISTRO"
    return
  fi
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}:${ID_LIKE:-}" in
      arch:*|*:arch*) printf '%s\n' arch ;;
      ubuntu:*|*:ubuntu*|*:debian*) printf '%s\n' ubuntu ;;
      *) printf '%s\n' unsupported ;;
    esac
    return
  fi
  printf '%s\n' unsupported
}

print_dependencies() {
  case "$(detect_distro)" in
    arch)
      printf '%s\n' 'sudo pacman -S --needed base-devel bubblewrap ca-certificates ccache clang cmake curl enchant git glib2-devel gobject-introspection gperf gst-libav gst-plugin-pipewire gst-plugins-bad gst-plugins-base gst-plugins-good gtk3 harfbuzz-icu hyphen lcms2 libavif libportal-gtk3 libpulse libsoup3 libsecret libseccomp libtasn1 libwebp libxslt lld mesa ninja openssl patch pipewire pkgconf ruby ruby-erb rustup unifdef wayland-protocols woff2 xdg-dbus-proxy xdg-desktop-portal xdg-desktop-portal-gtk xz zstd'
      ;;
    ubuntu)
      printf '%s\n' 'sudo apt update'
      printf '%s\n' 'sudo apt install bison bubblewrap build-essential ca-certificates ccache clang cmake curl flex gettext git gobject-introspection gperf gstreamer1.0-libav gstreamer1.0-pipewire gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-tools libavif-dev libenchant-2-dev libgbm-dev libgirepository1.0-dev libglib2.0-dev libgstreamer-plugins-bad1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev libgtk-3-dev libhyphen-dev libicu-dev libjpeg-dev liblcms2-dev libpipewire-0.3-dev libpng-dev libportal-gtk3-dev libsecret-1-dev libseccomp-dev libsoup-3.0-dev libsqlite3-dev libssl-dev libtasn1-6-dev libwebp-dev libwoff-dev libxml2-dev libxslt1-dev lld mesa-common-dev ninja-build patch perl pkg-config pulseaudio-utils python3 ruby unifdef wayland-protocols xdg-dbus-proxy xz-utils zstd'
      ;;
    *)
      printf '%s\n' 'Supported dependency sets are Arch Linux and Ubuntu.' >&2
      return 1
      ;;
  esac
}

case "${1:-}" in
  --print-pins) print_pins; exit 0 ;;
  --print-dependencies)
    if [ -n "${3:-}" ]; then printf '%s\n' 'too many arguments' >&2; exit 2; fi
    if [ -n "${2:-}" ]; then PALLADIUM_DISTRO=$2; fi
    print_dependencies
    exit 0
    ;;
  "") ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

if [ "$WEBKIT_VERSION" != "$WEBKIT_PINNED_VERSION" ] || [ "$WEBKIT_SHA256" != "$WEBKIT_PINNED_SHA256" ]; then
  printf '%s\n' 'WebKitGTK version and checksum must match the phase-one pin.' >&2
  exit 2
fi

if [ "$USE_LIBRICE" != ON ]; then
  printf '%s\n' 'Palladium phase one requires the librice NetworkProcess path.' >&2
  exit 2
fi

if [ "$(uname -s)" != Linux ]; then
  printf '%s\n' 'The private WebKitGTK runtime can only be built on Linux.' >&2
  exit 2
fi

case "$(detect_distro)" in
  arch|ubuntu) ;;
  *) print_dependencies; exit 2 ;;
esac

for tool in cmake curl gperf ninja pkg-config ruby sha256sum tar unifdef; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing build tool: %s\n' "$tool" >&2
    print_dependencies >&2
    exit 2
  fi
done

data_root=${XDG_DATA_HOME:-${HOME:?}/.local/share}
cache_root=${XDG_CACHE_HOME:-${HOME:?}/.cache}
prefix=${WEBKIT_PREFIX:-$data_root/palladium/webkit-$WEBKIT_VERSION}
source_root=${WEBKIT_SRC:-$cache_root/palladium/webkit-build}
jobs=${JOBS:-$(nproc)}
archive=$source_root/webkitgtk-$WEBKIT_VERSION.tar.xz
source_dir=$source_root/webkitgtk-$WEBKIT_VERSION
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export WK_USE_CCACHE=YES
export CCACHE_BASEDIR="$source_root"
export CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-2G}
export CCACHE_COMPILERCHECK=content

for module in rice-proto rice-io; do
  if ! pkg-config --exists "$module"; then
    printf 'missing %s in PKG_CONFIG_PATH; run npm run setup:librice first\n' "$module" >&2
    exit 2
  fi
  if [ "$(pkg-config --modversion "$module")" != 0.4.3 ]; then
    printf '%s must be version 0.4.3\n' "$module" >&2
    exit 2
  fi
done

mkdir -p "$source_root" "$prefix"
if [ ! -f "$archive" ]; then
  curl --fail --location --output "$archive.part" "https://webkitgtk.org/releases/webkitgtk-$WEBKIT_VERSION.tar.xz"
  mv "$archive.part" "$archive"
fi

actual_sha256=$(sha256sum "$archive" | awk '{ print $1 }')
if [ "$actual_sha256" != "$WEBKIT_SHA256" ]; then
  printf 'WebKitGTK checksum mismatch: expected %s, found %s\n' "$WEBKIT_SHA256" "$actual_sha256" >&2
  exit 2
fi

if [ ! -d "$source_dir" ]; then
  tar xf "$archive" -C "$source_root"
fi

cd "$source_dir"

patch_file=${WEBKIT_PATCH_FILE:?}
patch_stamp=$source_root/applied.patch
if [ -f "$patch_stamp" ] && ! cmp -s "$patch_stamp" "$patch_file"; then
  patch -p1 --batch --reverse < "$patch_stamp"
  rm "$patch_stamp"
fi
if [ ! -f "$patch_stamp" ]; then
  patch -p1 --batch --forward < "$patch_file"
  cp "$patch_file" "$patch_stamp"
fi

if [ "${CLEAN:-0}" = 1 ] && [ -d build ]; then
  rm -rf build
fi

cmake \
  -U 'Rice*' \
  -U 'PC_RICE*' \
  -U 'pkgcfg_lib_PC_RICE*' \
  -U '__pkg_config_*RICE*' \
  -B build -G Ninja \
  -D PORT=GTK \
  -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -D CMAKE_C_COMPILER=clang \
  -D CMAKE_CXX_COMPILER=clang++ \
  -D CMAKE_C_FLAGS_RELEASE='-O2 -DNDEBUG' \
  -D CMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG' \
  -D LTO_MODE=OFF \
  -D ENABLE_UNIFIED_BUILDS=ON \
  -D ENABLE_EXPERIMENTAL_FEATURES=OFF \
  -D ENABLE_API_TESTS=OFF \
  -D ENABLE_LAYOUT_TESTS=OFF \
  -D CMAKE_INSTALL_PREFIX="$prefix" \
  -D CMAKE_INSTALL_LIBDIR=lib \
  -D CMAKE_INSTALL_LIBEXECDIR=lib \
  -D ENABLE_BUBBLEWRAP_SANDBOX=ON \
  -D ENABLE_DOCUMENTATION=OFF \
  -D ENABLE_GAMEPAD=OFF \
  -D ENABLE_INTROSPECTION=ON \
  -D ENABLE_JOURNALD_LOG=OFF \
  -D ENABLE_MEDIA_RECORDER=ON \
  -D ENABLE_MEDIA_STREAM=ON \
  -D ENABLE_MHTML=OFF \
  -D ENABLE_CONTENT_EXTENSIONS=OFF \
  -D ENABLE_MINIBROWSER=OFF \
  -D ENABLE_PDFJS=OFF \
  -D ENABLE_SPEECH_SYNTHESIS=OFF \
  -D ENABLE_WEB_RTC=ON \
  -D ENABLE_WEBDRIVER=OFF \
  -D ENABLE_WK_WEB_EXTENSIONS=OFF \
  -D ENABLE_WEBXR=OFF \
  -D ENABLE_WEBGPU=OFF \
  -D USE_VULKAN=OFF \
  -D USE_AVIF=ON \
  -D USE_FLITE=OFF \
  -D USE_GTK4=OFF \
  -D USE_LIBBACKTRACE=OFF \
  -D USE_LIBRICE=ON \
  -D USE_JPEGXL=OFF \
  -D USE_SOUP2=OFF \
  -D CMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
  -D CMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld

for setting in ENABLE_WEB_RTC ENABLE_MEDIA_STREAM ENABLE_MEDIA_RECORDER USE_LIBRICE; do
  if ! grep -qE "^$setting:.*=ON" build/CMakeCache.txt; then
    printf '%s was not enabled by WebKitGTK configuration\n' "$setting" >&2
    exit 2
  fi
done

for expected in \
  "RiceProto_INCLUDE_DIR:PATH=$prefix/include/rice" \
  "RiceIo_INCLUDE_DIR:PATH=$prefix/include/rice" \
  "Rice_PROTO_LIBRARY:FILEPATH=$prefix/lib/librice-proto.so" \
  "Rice_IO_LIBRARY:FILEPATH=$prefix/lib/librice-io.so"; do
  if ! grep -Fq "$expected" build/CMakeCache.txt; then
    printf 'WebKitGTK resolved an unexpected librice path instead of %s\n' "$expected" >&2
    exit 2
  fi
done

mapfile -t native_targets < <(python3 "$root/scripts/native-targets.py" build/compile_commands.json)
if [ "${#native_targets[@]}" -eq 0 ]; then
  printf '%s\n' 'No encoded-transform compilation targets were found.' >&2
  exit 1
fi
ninja -C build -j "$jobs" "${native_targets[@]}"
ninja -C build -j "$jobs"
ninja -C build install
WEBKIT_PREFIX="$prefix" bash "$root/scripts/verify-linux-runtime.sh"
printf 'WebKitGTK %s installed at %s\n' "$WEBKIT_VERSION" "$prefix"
