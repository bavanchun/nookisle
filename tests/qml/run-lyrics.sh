#!/usr/bin/env bash
# Runs tst-lyrics.qml with qmltestrunner using an in-QML fake fetcher.
# Usage: run-lyrics.sh <qmltestrunner> <build dir>
set -euo pipefail
runner=${1:?qmltestrunner path}
build_dir=${2:?build directory}
tests_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

status=0
env -u DISPLAY -u WAYLAND_DISPLAY \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 \
  QML_DISABLE_DISK_CACHE=1 \
  dbus-run-session --config-file="$tests_dir/session-bus.conf" -- \
  "$runner" -input "$tests_dir/tst-lyrics.qml" || status=$?
exit "$status"
