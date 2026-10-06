#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
host_source=${1:?Usage: run-patched-host-lifecycle.sh /path/to/patched/shell.qml}
run_dir=$(mktemp -d "$project_dir/build/patched-host-lifecycle.XXXXXX")
# Unix IPC socket paths are bounded; keep the runtime prefix short.
runtime_dir=$(mktemp -d /tmp/island-host.XXXXXX)
mkdir -p "$run_dir/home"
log_file="$run_dir/test.log"
cmake --install "$project_dir/build" --prefix "$run_dir/package"

# Generate from the supplied production block. The only substitution is the
# Qt factory boundary used to schedule stale callbacks deterministically.
node - "$host_source" "$project_dir/tests/qml/patched-host-harness.qml" "$run_dir/patched-host-harness.qml" <<'JS'
const fs = require('fs')
const crypto = require('crypto')
const source = fs.readFileSync(process.argv[2], 'utf8')
const start = source.indexOf('  property var _services:')
const end = source.indexOf('  Connections {\n    target: shell.pluginRegistry', start)
if (start < 0 || end < 0) throw new Error('Cannot locate production service loader')
const block = source.slice(start, end)
const boundary = 'Qt.createComponent(url, Component.PreferSynchronous)'
if (!block.includes('function _serviceLoadCurrent(') || block.split(boundary).length !== 2)
    throw new Error('Expected patched loader with exactly one Qt factory boundary')
const template = fs.readFileSync(process.argv[3], 'utf8')
if (template.split('// PRODUCTION_SERVICE_LOADER').length !== 2)
    throw new Error('Expected exactly one production insertion marker')
fs.writeFileSync(process.argv[4], template.replace('// PRODUCTION_SERVICE_LOADER',
    block.replace(boundary, 'test.createServiceComponent(url, Component.PreferSynchronous)')))
console.log('Host source SHA-256: ' + crypto.createHash('sha256').update(source).digest('hex'))
console.log('Production service block SHA-256: ' + crypto.createHash('sha256').update(block).digest('hex'))
JS

# Unique package paths support exact process counts. No display or live bus is
# reachable; the foreground timeout owns the entire test process group.
env -u WAYLAND_DISPLAY -u DISPLAY -u QT_IM_MODULE \
  HOME="$run_dir/home" XDG_CONFIG_HOME="$run_dir/home/config" \
  XDG_CACHE_HOME="$run_dir/home/cache" XDG_DATA_HOME="$run_dir/home/data" \
  XDG_STATE_HOME="$run_dir/home/state" XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
  QSG_RHI_BACKEND=software QML_DISABLE_DISK_CACHE=1 \
  NO_AT_BRIDGE=1 GIO_USE_VFS=local \
  dbus-run-session --config-file="$project_dir/tests/qml/session-bus.conf" -- \
  timeout 25s quickshell --path "$run_dir/patched-host-harness.qml" --no-color \
  2>&1 | tee "$log_file"
if ! rg -q 'PATCHED_HOST_RESULT failures=0 cycles=5' "$log_file" || \
   rg -q 'FAIL |ERROR |TypeError:|ReferenceError:|Failed to load|Binding loop|Invalid attempt' "$log_file"; then
  printf 'Patched host lifecycle failed; log: %s\n' "$log_file" >&2
  exit 1
fi
printf 'Patched host lifecycle passed; log: %s\n' "$log_file"
