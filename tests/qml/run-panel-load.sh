#!/usr/bin/env bash
# Loads the complete installed Panel.qml under Quickshell (offscreen) and
# fails on any QML error or warning, so no merge can ship an unloadable or
# noisy panel. The host's own Commons module is copied beside it; nothing
# else of the host is used. Only PanelWindow is substituted (see below).
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
commons=${NOOKISLE_HOST_COMMONS:-/usr/share/omarchy/shell/Commons}
run_dir=$(mktemp -d "$project_dir/build/panel-load.XXXXXX")
runtime_dir=$(mktemp -d /tmp/nookisle-panel.XXXXXX)
log_file="$run_dir/test.log"
cmake --install "$project_dir/build" --prefix "$run_dir/package" >/dev/null
cp -r "$commons" "$run_dir/Commons"
cp "$project_dir/tests/qml/panel-load/shell.qml" "$run_dir/shell.qml"
# The one substitution: PanelWindow needs a Wayland backend the offscreen
# platform lacks, so the package's layer windows become TestPanelWindow (a
# plain window with the same members). Every file is otherwise as installed.
for dir in "$run_dir/package" "$run_dir/package/components"; do
  cp "$project_dir"/tests/qml/panel-load/TestPanel*.qml "$dir/"
done
windows=$(grep -l 'PanelWindow {' "$run_dir/package"/*.qml "$run_dir/package/components"/*.qml | grep -v TestPanel)
[ -n "$windows" ] || { echo "no PanelWindow found in the package" >&2; exit 1; }
# The layer-shell attached properties need a real layer surface too; their
# bindings stay, evaluated as plain properties of the stand-in window.
sed -i -e 's/\bPanelWindow {/TestPanelWindow {/' \
  -e 's/WlrLayershell\.namespace:/property string layerNamespace:/' \
  -e 's/WlrLayershell\.layer:/property int layerLevel:/' \
  -e 's/WlrLayershell\.keyboardFocus:/property int layerKeyboardFocus:/' $windows
if grep -q 'WlrLayershell\.' $windows; then echo "an unhandled layer-shell binding remains" >&2; exit 1; fi
env -u WAYLAND_DISPLAY -u DISPLAY \
  XDG_RUNTIME_DIR="$runtime_dir" XDG_CONFIG_HOME="$runtime_dir/config" \
  XDG_STATE_HOME="$runtime_dir/state" XDG_CACHE_HOME="$runtime_dir/cache" \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QSG_RHI_BACKEND=software \
  NO_AT_BRIDGE=1 GIO_USE_VFS=local \
  dbus-run-session --config-file="$project_dir/tests/qml/session-bus.conf" -- \
  timeout 30s quickshell --path "$run_dir/shell.qml" --no-color \
  > "$log_file" 2>&1 || true
# Any QML warning or error fails the run, not only a load failure. The
# launcher's notes about the offscreen platform, the Hyprland and PipeWire
# modules' notes that no compositor or audio server is reachable, and the
# offscreen platform's lack of window masks are the environment, not QML.
problems=$(grep -E ' (WARN|ERROR|CRIT)|PANEL_LOAD_FAIL|TypeError|ReferenceError|Property value set multiple times|Failed to load|Binding loop|is not a type|Cannot assign|Unable to assign' "$log_file" \
  | grep -v -E 'WAYLAND_DISPLAY is present|QT_QPA_PLATFORM is "offscreen"|most functionality will be broken|--- WARNING ---|Unable to find hyprland socket|quickshell\.hyprland\.ipc: Error making request|quickshell\.service\.pipewire\.loop: Failed to connect|does not support setting window masks' || true)
if [ -n "$problems" ] || ! grep -q 'PANEL_LOAD_RESULT failures=0' "$log_file"; then
  printf '%s\n' "$problems" >&2
  printf 'Panel load test failed; log: %s\n' "$log_file" >&2
  exit 1
fi
rm -rf "$run_dir" "$runtime_dir"
printf 'Panel load test passed\n'
