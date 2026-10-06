#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
runtime_dir=$(mktemp -d /tmp/nookisle-lyrics-fetch.XXXXXX)
log_file="$runtime_dir/test.log"
fake_script="$runtime_dir/fake-lyrics-fetch.sh"

cat << 'EOF' > "$fake_script"
#!/usr/bin/env python3
import sys, os, time

runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
argv_file = os.path.join(runtime_dir, "argv.log")
with open(argv_file, "w") as f:
    for arg in sys.argv:
        f.write(arg + "\n")

url = sys.argv[2] if len(sys.argv) > 2 else ""

if url == "case-ok-200":
    sys.stdout.write('ok 200\n{"lyrics":"sync content","plainLyrics":"plain content"}')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-ok-404":
    sys.stdout.write('ok 404\nNot Found')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-err-too-large":
    sys.stdout.write('error too-large\n')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-err-timeout":
    sys.stdout.write('error timeout\n')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-err-unknown":
    sys.stdout.write('error strange-error\n')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-garbage":
    sys.stdout.write('<!DOCTYPE html><html><body>502 Bad Gateway</body></html>')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-nonzero-exit":
    sys.stderr.write('fatal crash\n')
    sys.stderr.flush()
    sys.exit(42)
elif url == "case-slow-a":
    time.sleep(0.8)
    sys.stdout.write('ok 200\n{"url":"slow-a"}')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-fast-b":
    time.sleep(0.1)
    sys.stdout.write('ok 200\n{"url":"fast-b"}')
    sys.stdout.flush()
    sys.exit(0)
elif url == "case-linger":
    time.sleep(30)
    sys.exit(0)
else:
    sys.stdout.write('ok 200\n{"url":"' + url + '"}')
    sys.stdout.flush()
    sys.exit(0)
EOF
chmod +x "$fake_script"

env -u WAYLAND_DISPLAY -u DISPLAY \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QSG_RHI_BACKEND=software NO_AT_BRIDGE=1 \
  timeout 25s quickshell --path "$project_dir/lyrics-fetch-test.qml" --no-color \
  2>&1 | tee "$log_file"

if ! rg -q 'LYRICS_FETCH_RESULT failures=0' "$log_file" || rg -q 'FAIL |TypeError:|ReferenceError:|Failed to load|Binding loop' "$log_file"; then
  printf 'LyricsFetch test failed; log: %s\n' "$log_file" >&2
  exit 1
fi

if pgrep -f "$fake_script.*case-linger" >/dev/null 2>&1; then
  printf 'Error: lingering fake-lyrics-fetch process found!\n' >&2
  pkill -9 -f "$fake_script" || true
  exit 1
fi

rm -rf "$runtime_dir"
printf 'LyricsFetch test passed\n'
