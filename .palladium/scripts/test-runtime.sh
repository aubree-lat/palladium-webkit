#!/usr/bin/env bash
set -euo pipefail

if [ "${PALLADIUM_TEST_SESSION:-0}" != 1 ]; then
  export XDG_RUNTIME_DIR
  XDG_RUNTIME_DIR=$(mktemp -d)
  export XDG_DATA_HOME=$XDG_RUNTIME_DIR/data
  export XDG_CONFIG_HOME=$XDG_RUNTIME_DIR/config
  export XDG_STATE_HOME=$XDG_RUNTIME_DIR/state
  export XDG_CACHE_HOME=$XDG_RUNTIME_DIR/cache
  export GIO_USE_VFS=local
  mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d"
  cat > "$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d/palladium-test.conf" <<'EOF'
wireplumber.profiles = {
  main = {
    hardware.audio = disabled
    hardware.bluetooth = disabled
    hardware.video-capture = disabled
    monitor.alsa = disabled
    monitor.bluez = disabled
    monitor.v4l2 = disabled
    monitor.libcamera = disabled
  }
}
EOF
  cleanup_session() {
    for mount in doc gvfs; do
      if mountpoint -q "$XDG_RUNTIME_DIR/$mount"; then fusermount3 -u "$XDG_RUNTIME_DIR/$mount" || true; fi
    done
    rm -rf --one-file-system "$XDG_RUNTIME_DIR"
  }
  trap cleanup_session EXIT
  dbus-run-session -- xvfb-run -a env PALLADIUM_TEST_SESSION=1 bash "$0" "$@"
  exit
fi

export GDK_BACKEND=x11
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export XDG_CURRENT_DESKTOP=GNOME
export LIBGL_ALWAYS_SOFTWARE=1
export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR
log_dir=${PALLADIUM_TEST_LOG_DIR:-.palladium/state/test-logs}
mkdir -p "$log_dir"
pipewire > "$log_dir/pipewire.log" 2>&1 &
pipewire_pid=$!
pipewire-pulse > "$log_dir/pipewire-pulse.log" 2>&1 &
pulse_pid=$!
wireplumber > "$log_dir/wireplumber.log" 2>&1 &
wireplumber_pid=$!
trap 'kill "$pipewire_pid" "$pulse_pid" "$wireplumber_pid" "${loopback_pid:-}" 2>/dev/null || true' EXIT
ready=0
for attempt in $(seq 1 40); do
  if pactl info >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.25
done
if [ "$ready" != 1 ]; then cat "$log_dir/pipewire-pulse.log" >&2; exit 1; fi
sleep 1
pactl load-module module-null-sink sink_name=palladium-test
sleep 1
pactl set-default-sink palladium-test
pactl load-module module-null-sink sink_name=palladium-test-second
pw-loopback -C palladium-test -i 'stream.capture.sink=true node.passive=true' \
  -o 'media.class=Audio/Source node.name=palladium-test-microphone node.description="Palladium test microphone"' \
  > "$log_dir/loopback.log" 2>&1 &
loopback_pid=$!
for attempt in $(seq 1 40); do
  if pactl set-default-source palladium-test-microphone 2>/dev/null; then break; fi
  sleep 0.1
done
pactl set-default-source palladium-test-microphone
probes=(images audio encoded-audio staggered-audio devices)
if [ "$#" -gt 0 ]; then probes=("$@"); fi
for probe in "${probes[@]}"; do
  case "$probe" in images|audio|encoded-audio|staggered-audio|devices) ;; *) exit 2 ;; esac
  python3 .palladium/tests/probe.py ".palladium/tests/$probe.js" | tee "$log_dir/$probe.json"
done
