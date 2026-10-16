#!/usr/bin/env bash
set -euo pipefail

if [ "${PALLADIUM_TEST_SESSION:-0}" != 1 ]; then
  export XDG_RUNTIME_DIR
  XDG_RUNTIME_DIR=$(mktemp -d)
  trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
  dbus-run-session -- xvfb-run -a env PALLADIUM_TEST_SESSION=1 bash "$0" "$@"
  exit
fi

export GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=GNOME
export LIBGL_ALWAYS_SOFTWARE=1
export PULSE_SERVER=unix:$XDG_RUNTIME_DIR/pulse/native
log_dir=.palladium/state/test-logs
mkdir -p "$log_dir"
pipewire > "$log_dir/pipewire.log" 2>&1 &
pipewire_pid=$!
pipewire-pulse > "$log_dir/pipewire-pulse.log" 2>&1 &
pulse_pid=$!
wireplumber > "$log_dir/wireplumber.log" 2>&1 &
wireplumber_pid=$!
trap 'kill "$pipewire_pid" "$pulse_pid" "$wireplumber_pid" 2>/dev/null || true' EXIT
ready=0
for attempt in $(seq 1 40); do
  if pactl info >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.25
done
if [ "$ready" != 1 ]; then cat "$log_dir/pipewire-pulse.log" >&2; exit 1; fi
pactl load-module module-null-sink sink_name=palladium-test
pactl set-default-sink palladium-test
pactl load-module module-null-sink sink_name=palladium-test-second
pactl load-module module-remap-source master=palladium-test.monitor source_name=palladium-test-microphone
pactl set-default-source palladium-test-microphone
probes=(audio encoded-audio staggered-audio devices)
if [ "$#" -gt 0 ]; then probes=("$@"); fi
for probe in "${probes[@]}"; do
  case "$probe" in audio|encoded-audio|staggered-audio|devices) ;; *) exit 2 ;; esac
  python3 .palladium/tests/probe.py ".palladium/tests/$probe.js" | tee "$log_dir/$probe.json"
done
