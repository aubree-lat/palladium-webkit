#!/usr/bin/env bash
set -euo pipefail

source .palladium/pins.env
output=$PWD/.palladium/dist
mkdir -p "$output"
work=$(mktemp -d)
runtime=/usr/lib/palladium/runtime
if [ -e "$runtime" ] || [ ! -w /usr/lib/palladium ]; then
  printf '%s\n' 'Packaged-runtime tests require a fresh writable CI runtime directory.' >&2
  rm -rf "$work"
  exit 1
fi
trap 'rm -rf "$work" "$runtime"' EXIT
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)
bash .palladium/scripts/package-linux-runtime.sh --prefix "${WEBKIT_PREFIX:?}" --output "$runtime"
export LD_LIBRARY_PATH="$runtime/lib"
export GI_TYPELIB_PATH="$runtime/lib/girepository-1.0"
export WEBKIT_EXEC_PATH=$runtime/lib/webkit2gtk-4.1
export WEBKIT_INJECTED_BUNDLE_PATH=$WEBKIT_EXEC_PATH/injected-bundle
PALLADIUM_TEST_LOG_DIR=$PWD/.palladium/state/packaged-test-logs bash .palladium/scripts/test-runtime.sh
git rev-parse HEAD > "$runtime/SOURCE_COMMIT"
cp .palladium/pins.env "$runtime/BUILD_INPUTS"
pacman -Q > "$runtime/BUILD_DEPENDENCIES"
cp -a .palladium/state/test-logs/*.json "$runtime/"
for result in .palladium/state/packaged-test-logs/*.json; do
  cp "$result" "$runtime/packaged-$(basename "$result")"
done
python3 - "$runtime" .palladium/state/compile-seconds <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
seconds = pathlib.Path(sys.argv[2])
metrics = {'compileSeconds': int(seconds.read_text()) if seconds.exists() else None,
           'runtimeBytes': sum(p.stat().st_size for p in root.rglob('*') if p.is_file() and not p.is_symlink()),
           'profile': 'clang-O2-unified-no-lto', 'manualDiscordCallValidated': False,
           'syntheticProbeMemory': {p.stem: json.loads(p.read_text()).get('processMemory') for p in root.glob('*.json')}}
(root / 'build-metrics.json').write_text(json.dumps(metrics, indent=2) + '\n')
PY
(
  cd "$runtime"
  find . -type f ! -name manifest.sha256 -print | LC_ALL=C sort | while IFS= read -r path; do
    sha256sum "${path#./}"
  done > manifest.sha256
)
revision=$(git rev-parse --short=12 HEAD)
archive=palladium-webkit-$WEBKIT_VERSION-arch-x86_64-$revision.tar.zst
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C /usr/lib/palladium -I 'zstd -T0 -10' -cf "$output/$archive" runtime
cp "${WEBKIT_PATCH_FILE:?}" "$output/palladium-source.patch"
cp .palladium/pins.env "$output/BUILD_INPUTS"
(
  cd "$output"
  sha256sum "$archive" palladium-source.patch BUILD_INPUTS > SHA256SUMS
)
printf 'Verified runtime archive created at %s/%s\n' "$output" "$archive"
