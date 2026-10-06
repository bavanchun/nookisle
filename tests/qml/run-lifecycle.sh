#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# Keep the known-broken baseline runnable after the installed host is repaired.
# An explicit source can additionally verify the original host snapshot.
baseline_source=${NOOKISLE_BASELINE_HOST_SOURCE:-$project_dir/tests/qml/legacy-service-finalize.js}
diff -u \
  <(awk '/function finalize\(\)/ { body=1; next } body { print; if (/_services = snext/) exit }' "$baseline_source" | sed 's/^[[:space:]]*//') \
  <(awk '/function finalize\(comp,/ { body=1; next } body && /var shell = host/ { next } body { print; if (/_services = snext/) exit }' "$project_dir/tests/qml/lifecycle-harness.qml" | sed 's/^[[:space:]]*//')
if [ "${NOOKISLE_TEST_DIR:-}" = "out" ]; then
  cp -a "$project_dir/out"/* "$project_dir/build/package/"
else
  cmake --install "$project_dir/build" --prefix "$project_dir/build/package"
fi
runtime_dir=$(mktemp -d /tmp/nookisle-lifecycle.XXXXXX)
log_file="$runtime_dir/test.log"
mkdir -p "$runtime_dir/bin"
cat > "$runtime_dir/bin/xdg-open" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" > "$SHELF_OPEN_LOG"
EOF
chmod 700 "$runtime_dir/bin/xdg-open"
# A fake clipboard. Each "--type text/uri-list" or "--type text" request
# serves that type's next numbered fixture in turn; a missing fixture (or any
# other type) fails as wl-paste does for a type the clipboard does not offer.
cat > "$runtime_dir/bin/nookisle-fake-paste" <<'EOF'
#!/bin/sh
type=""; prev=""
for arg in "$@"; do [ "$prev" = --type ] && type=$arg; prev=$arg; done
case $type in
  text) kind=text ;;
  text/uri-list) kind=uri ;;
  *) exit 1 ;;
esac
n=$(cat "$FAKE_PASTE_DIR/next-$kind" 2>/dev/null || echo 1)
echo $((n + 1)) > "$FAKE_PASTE_DIR/next-$kind"
[ -f "$FAKE_PASTE_DIR/$kind-$n" ] || exit 1
cat "$FAKE_PASTE_DIR/$kind-$n"
EOF
chmod 700 "$runtime_dir/bin/nookisle-fake-paste"
mkdir -p "$runtime_dir/paste"
printf 'https://example.org/pasted' > "$runtime_dir/paste/text-1"
printf 'a pasted note\nsecond line' > "$runtime_dir/paste/text-2"
# The fourth paste offers both types; the uri-list must win.
printf 'https://example.org/from-uri-list\r\nfile:///tmp/pasted-file.txt\r\n' > "$runtime_dir/paste/uri-4"
printf 'plain text that must not be used' > "$runtime_dir/paste/text-4"
# The temporary bus has no activation directories and the test cannot access
# the user's Wayland/X11 session. timeout owns the entire foreground test run.
env -u WAYLAND_DISPLAY -u DISPLAY \
  XDG_RUNTIME_DIR="$runtime_dir" XDG_CONFIG_HOME="$runtime_dir/config" \
  XDG_STATE_HOME="$runtime_dir/state" XDG_CACHE_HOME="$runtime_dir/cache" \
  SHELF_OPEN_LOG="$runtime_dir/open.log" FAKE_PASTE_DIR="$runtime_dir/paste" PATH="$runtime_dir/bin:$PATH" \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=generic QSG_RHI_BACKEND=software \
  NO_AT_BRIDGE=1 GIO_USE_VFS=local \
  dbus-run-session --config-file="$project_dir/tests/qml/session-bus.conf" -- \
  timeout 30s quickshell --path "$project_dir/lifecycle-test.qml" --no-color \
  2>&1 | tee "$log_file"
if ! rg -q 'LIFECYCLE_RESULT failures=0' "$log_file" || rg -q 'FAIL |TypeError:|ReferenceError:|Failed to load|Binding loop|in Connections element' "$log_file"; then
  printf 'Lifecycle test failed; log: %s\n' "$log_file" >&2
  exit 1
fi
# A passing run leaves nothing behind; a failing one keeps its log for diagnosis.
rm -rf "$runtime_dir"
printf 'Lifecycle test passed\n'
