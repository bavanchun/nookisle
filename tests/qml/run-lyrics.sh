#!/usr/bin/env bash
# Runs tst-lyrics.qml against the local LRCLIB fixture server, never the real
# network. Usage: run-lyrics.sh <qmltestrunner> <build dir>
set -euo pipefail
runner=${1:?qmltestrunner path}
build_dir=${2:?build directory}
tests_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fixture_dir="$build_dir/lyrics-fixture"
mkdir -p "$fixture_dir"
# A port.js left by an earlier run would point the test at a dead port.
rm -f "$fixture_dir/port.js"
python3 "$tests_dir/lyrics-fixture-server.py" "$fixture_dir" &
server_pid=$!
# Stop this run's own server only, by its PID.
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  [[ -s "$fixture_dir/port.js" ]] && break
  if ! kill -0 "$server_pid" 2>/dev/null; then
    printf 'Lyrics fixture server exited early\n' >&2
    exit 1
  fi
  sleep 0.1
done
if [[ ! -s "$fixture_dir/port.js" ]]; then
  printf 'Lyrics fixture server did not publish its port\n' >&2
  exit 1
fi
status=0
env -u DISPLAY -u WAYLAND_DISPLAY \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 \
  QML_DISABLE_DISK_CACHE=1 \
  dbus-run-session --config-file="$tests_dir/session-bus.conf" -- \
  "$runner" -input "$tests_dir/tst-lyrics.qml" || status=$?
exit "$status"
