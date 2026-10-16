#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repository"
source .palladium/pins.env
state=$repository/.palladium/state
builder_root=$state/home
deadline=${PALLADIUM_CI_DEADLINE:?}
mkdir -p "$state"

if [ "$(id -u)" = 0 ]; then
  pacman -Syu --noconfirm --needed git nodejs npm rustup sudo python-gobject xorg-server-xvfb xorg-xauth dbus pipewire-pulse wireplumber
  bash .palladium/scripts/build-webkit.sh --print-dependencies arch \
    | sed 's/^sudo //; s/pacman -S /pacman -S --noconfirm /' | bash
  id builder >/dev/null 2>&1 || useradd --create-home --home-dir "$builder_root" builder
  install -d -o builder -g builder /usr/lib/palladium
  chown -R builder:builder "$repository"
  trap 'chown -R "${PALLADIUM_HOST_OWNER:?}" "$repository"' EXIT
  exec_status=0
  runuser --user builder -- env HOME="$builder_root" PALLADIUM_CI_DEADLINE="$deadline" \
    bash .palladium/scripts/ci-build.sh || exec_status=$?
  exit "$exec_status"
fi

export PATH="$HOME/.cargo/bin:$PATH"
bwrap --ro-bind / / --unshare-user --unshare-pid --proc /proc -- /usr/bin/true
rustup default stable
export WEBKIT_PREFIX=$HOME/.local/share/palladium/webkit-$WEBKIT_VERSION
export WEBKIT_SRC=$HOME/.cache/palladium/webkit-build
export WEBKIT_SOURCE=$WEBKIT_SRC/webkitgtk-$WEBKIT_VERSION
export LIBRICE_SOURCE=$HOME/.cache/palladium/librice
export WEBKIT_PATCH_FILE=$WEBKIT_SRC/palladium.patch
bash .palladium/scripts/prepare-source.sh "$WEBKIT_SRC"
fingerprint=$(sha256sum "$WEBKIT_PATCH_FILE" | cut -d' ' -f1)
dependencies=$(pacman -Q | sha256sum | cut -d' ' -f1)

if [ -f "$state/dependencies" ] && [ "$(cat "$state/dependencies")" != "$dependencies" ]; then
  rm -rf "$WEBKIT_SOURCE/build" "$WEBKIT_PREFIX"
fi
printf '%s\n' "$dependencies" > "$state/dependencies"

if [ ! -f "$WEBKIT_PREFIX/lib/pkgconfig/rice-io.pc" ]; then
  RUST_TEST_THREADS=2 bash .palladium/scripts/build-librice.sh
fi

if [ ! -f "$state/complete" ] || [ "$(cat "$state/complete")" != "$fingerprint:$dependencies" ]; then
  remaining=$(( deadline - $(date +%s) ))
  if [ "$remaining" -lt 600 ]; then
    printf '%s\n' checkpointed > "$state/result"
    exit 0
  fi
  memory_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  jobs=$(( memory_kib / 4194304 ))
  if [ "$jobs" -lt 1 ]; then jobs=1; fi
  if [ "$jobs" -gt "$(nproc)" ]; then jobs=$(nproc); fi
  result=0
  started=$(date +%s)
  JOBS=$jobs timeout --kill-after=60 "$remaining" bash .palladium/scripts/build-webkit.sh || result=$?
  elapsed=$(( $(date +%s) - started ))
  previous=$(cat "$state/compile-seconds" 2>/dev/null || printf 0)
  printf '%s\n' "$(( previous + elapsed ))" > "$state/compile-seconds"
  if [ "$result" = 124 ] || [ "$result" = 137 ]; then
    printf '%s\n' checkpointed > "$state/result"
    exit 0
  fi
  if [ "$result" != 0 ]; then exit "$result"; fi
  printf '%s\n' "$fingerprint:$dependencies" > "$state/complete"
fi

# Only the Rice licenses are needed when restoring an already compiled prefix.
if [ ! -f "$LIBRICE_SOURCE/LICENSE-MIT" ]; then
  mkdir -p "$LIBRICE_SOURCE"
  for license in LICENSE-MIT LICENSE-APACHE; do
    curl --fail --location --retry 3 "https://raw.githubusercontent.com/ystreet/librice/$LIBRICE_REVISION/$license" -o "$LIBRICE_SOURCE/$license"
  done
fi

export LD_LIBRARY_PATH="$WEBKIT_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GI_TYPELIB_PATH="$WEBKIT_PREFIX/lib/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
export WEBKIT_EXEC_PATH=$WEBKIT_PREFIX/lib/webkit2gtk-4.1
export WEBKIT_INJECTED_BUNDLE_PATH=$WEBKIT_EXEC_PATH/injected-bundle
export WEBKIT_FORCE_SANDBOX=1
bash .palladium/scripts/test-runtime.sh
bash .palladium/scripts/package-release.sh
printf '%s\n' complete > "$state/result"
