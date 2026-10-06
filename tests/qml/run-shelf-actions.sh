#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
runtime_dir=$(mktemp -d /tmp/nookisle-shelf-actions.XXXXXX)
log_file="$runtime_dir/test.log"
mkdir -p "$runtime_dir/zip-fixture/left/DirA" "$runtime_dir/zip-fixture/right/DirB"
printf 'one\n' > "$runtime_dir/zip-fixture/left/DirA/one.txt"
printf 'two\n' > "$runtime_dir/zip-fixture/right/DirB/two.txt"
# A three-frame animated GIF; converting it must yield one file.
mkdir -p "$runtime_dir/frame-fixture/out"
magick -size 8x8 xc:red xc:green xc:blue -loop 0 "$runtime_dir/frame-fixture/anim.gif"
mkdir -p "$runtime_dir/rename-fixture/Documents"
printf 'foo\n' > "$runtime_dir/rename-fixture/foo.txt"
printf 'taken\n' > "$runtime_dir/rename-fixture/taken.txt"
env -u WAYLAND_DISPLAY -u DISPLAY \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QSG_RHI_BACKEND=software NO_AT_BRIDGE=1 \
  timeout 25s quickshell --path "$project_dir/shelf-actions-test.qml" --no-color \
  2>&1 | tee "$log_file"
if ! rg -q 'SHELF_ACTIONS_RESULT failures=0' "$log_file" || rg -q 'FAIL |TypeError:|ReferenceError:|Failed to load|Binding loop' "$log_file"; then
  printf 'ShelfActions test failed; log: %s\n' "$log_file" >&2
  exit 1
fi
rm -rf "$runtime_dir"
printf 'ShelfActions test passed\n'
