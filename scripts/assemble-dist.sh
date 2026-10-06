#!/usr/bin/env bash
# assemble-dist.sh — Assemble the clean Nookisle distribution tree for dist branch.
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <stage-prefix> <output-dir>" >&2
    exit 1
fi

STAGE_DIR="$(cd "$1" && pwd)"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Assembling dist tree from '${STAGE_DIR}' into '${OUT_DIR}'"

# 1. Clean output directory and copy files from stage
rm -rf "${OUT_DIR:?}"/*
cp -a "${STAGE_DIR}"/* "${OUT_DIR}/"

# Ensure LICENSE and README.md are copied
if [ -f "${SOURCE_ROOT}/LICENSE" ] && [ ! -f "${OUT_DIR}/LICENSE" ]; then
    cp "${SOURCE_ROOT}/LICENSE" "${OUT_DIR}/"
fi
if [ -f "${SOURCE_ROOT}/README.md" ] && [ ! -f "${OUT_DIR}/README.md" ]; then
    cp "${SOURCE_ROOT}/README.md" "${OUT_DIR}/"
fi
if [ -f "${SOURCE_ROOT}/preview.png" ]; then
    cp "${SOURCE_ROOT}/preview.png" "${OUT_DIR}/"
fi

# Exclude unneeded bridge documentation from dist tree
if [ -f "${OUT_DIR}/bridge/README.md" ]; then
    rm -f "${OUT_DIR}/bridge/README.md"
fi

# 2. Check libexec entries: exactly the six expected binaries
EXPECTED_LIBEXEC=(
    "nookisle-artwork-decoder"
    "nookisle-artwork-fetch"
    "nookisle-helper"
    "nookisle-media-keys"
    "nookisle-native-host"
    "nookisle-spectrum"
)

ACTUAL_LIBEXEC=($(ls -1 "${OUT_DIR}/libexec" | LC_ALL=C sort))
if [ "${EXPECTED_LIBEXEC[*]}" != "${ACTUAL_LIBEXEC[*]}" ]; then
    echo "ERROR: libexec entries mismatch!" >&2
    echo "Expected: ${EXPECTED_LIBEXEC[*]}" >&2
    echo "Actual:   ${ACTUAL_LIBEXEC[*]}" >&2
    exit 1
fi
echo "  [OK] Exactly 6 libexec entries present"

# 3. Check with readelf -d that helper has NEEDED libudev and spectrum exists
if ! command -v readelf >/dev/null 2>&1; then
    echo "ERROR: readelf command not found" >&2
    exit 1
fi

if ! readelf -d "${OUT_DIR}/libexec/nookisle-helper" | grep -q 'NEEDED.*libudev'; then
    echo "ERROR: nookisle-helper does not have NEEDED libudev!" >&2
    exit 1
fi
echo "  [OK] nookisle-helper has NEEDED libudev"

if [ ! -f "${OUT_DIR}/libexec/nookisle-spectrum" ]; then
    echo "ERROR: nookisle-spectrum binary missing!" >&2
    exit 1
fi
echo "  [OK] nookisle-spectrum binary present"

# 4. Check that manifest.build matches ^[0-9a-f]{40}$
MANIFEST_FILE="${OUT_DIR}/manifest.json"
if [ ! -f "${MANIFEST_FILE}" ]; then
    echo "ERROR: manifest.json missing in dist tree!" >&2
    exit 1
fi

BUILD_REV=$(python3 -c 'import json, sys; m=json.load(open(sys.argv[1])); print(m.get("build", ""))' "${MANIFEST_FILE}")
if ! [[ "${BUILD_REV}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "ERROR: manifest.json 'build' is '${BUILD_REV}', expected 40 hex characters!" >&2
    exit 1
fi
echo "  [OK] manifest.json build is valid 40-hex SHA (${BUILD_REV})"

# 5. Exactly one manifest at depth <= 1, no symlinks, and every libexec file executable
MANIFESTS_DEPTH_LE_1=($(find "${OUT_DIR}" -maxdepth 2 -name "manifest.json"))
if [ "${#MANIFESTS_DEPTH_LE_1[@]}" -ne 1 ] || [ "${MANIFESTS_DEPTH_LE_1[0]}" != "${OUT_DIR}/manifest.json" ]; then
    echo "ERROR: Expected exactly one manifest.json at depth <= 1, found: ${MANIFESTS_DEPTH_LE_1[*]}" >&2
    exit 1
fi
echo "  [OK] Exactly one manifest.json at depth <= 1"

SYMLINKS=($(find "${OUT_DIR}" -type l))
if [ "${#SYMLINKS[@]}" -ne 0 ]; then
    echo "ERROR: Symlinks found in dist tree: ${SYMLINKS[*]}" >&2
    exit 1
fi
echo "  [OK] No symlinks in dist tree"

for bin in "${OUT_DIR}/libexec"/*; do
    if [ ! -x "${bin}" ]; then
        echo "ERROR: libexec file is not executable: ${bin}" >&2
        exit 1
    fi
    # Ensure permission mode is 100755
    chmod 755 "${bin}"
done
echo "  [OK] All libexec entries are executable (0755)"

# 6. Rejects any file over 512 KiB other than ELF binaries
LARGE_FILES_REJECTED=0
while IFS= read -r -d '' file; do
    # 512 KiB = 524288 bytes
    size=$(stat -c '%s' "${file}")
    if [ "${size}" -gt 524288 ]; then
        if ! file "${file}" | grep -q 'ELF'; then
            echo "ERROR: File '${file}' is over 512 KiB (${size} bytes) and is not an ELF binary!" >&2
            LARGE_FILES_REJECTED=1
        fi
    fi
done < <(find "${OUT_DIR}" -type f -print0)

if [ "${LARGE_FILES_REJECTED}" -ne 0 ]; then
    exit 1
fi
echo "  [OK] No non-ELF files over 512 KiB"

# 7. Rejects plans, tests or *.cpp in the tree
FORBIDDEN=($(find "${OUT_DIR}" -name "plans" -o -name "tests" -o -name "*.cpp"))
if [ "${#FORBIDDEN[@]}" -ne 0 ]; then
    echo "ERROR: Forbidden files/directories found in dist tree: ${FORBIDDEN[*]}" >&2
    exit 1
fi
echo "  [OK] No plans, tests or *.cpp in dist tree"

# 8. Checks that relative links in shipped *.md files resolve inside the tree
ALLOW_DANGLING="${NOOKISLE_ALLOW_DANGLING_LINKS:-0}"
LINK_CHECK_FAILED=0

python3 - <<EOF
import os, sys, re, pathlib

out_dir = pathlib.Path("${OUT_DIR}").resolve()
allow_dangling = ("${ALLOW_DANGLING}" in ("1", "true", "TRUE"))
link_re = re.compile(r'!?\[[^\]]*\]\(([^)]+)\)')

md_files = sorted(out_dir.rglob("*.md"))
dangling = []

for md in md_files:
    text = md.read_text(encoding="utf-8", errors="replace")
    for match in link_re.finditer(text):
        raw_target = match.group(1).split('#')[0].strip()
        if not raw_target:
            continue
        if raw_target.startswith(("http://", "https://", "mailto:")):
            continue
        # Relative link
        resolved = (md.parent / raw_target).resolve()
        try:
            rel = resolved.relative_to(out_dir)
            if not resolved.exists():
                dangling.append((md.relative_to(out_dir), raw_target, f"resolved to missing path {rel}"))
        except ValueError:
            dangling.append((md.relative_to(out_dir), raw_target, "resolves outside dist tree"))

if dangling:
    if allow_dangling:
        print(f"WARNING: Found {len(dangling)} dangling/external link(s) in shipped markdown files (NOOKISLE_ALLOW_DANGLING_LINKS=1):")
        for f, target, reason in dangling:
            print(f"  [WARN] {f}: '{target}' -> {reason}")
    else:
        print(f"ERROR: Found {len(dangling)} dangling/external link(s) in shipped markdown files:", file=sys.stderr)
        for f, target, reason in dangling:
            print(f"  [FAIL] {f}: '{target}' -> {reason}", file=sys.stderr)
        sys.exit(1)
else:
    print("  [OK] All relative links in shipped *.md files resolve inside dist tree")
EOF

# 9. Writes SHA256SUMS over every file in the tree, with header '# nookisle <tag> <source sha>'
TAG="${NOOKISLE_TAG:-${GITHUB_REF_NAME:-v1.0.0}}"
# Strip refs/tags/ if full ref passed
TAG="${TAG#refs/tags/}"

rm -f "${OUT_DIR}/SHA256SUMS"

echo "# nookisle ${TAG} ${BUILD_REV}" > "${OUT_DIR}/SHA256SUMS"
(
    cd "${OUT_DIR}"
    find . -type f ! -name "SHA256SUMS" | LC_ALL=C sort | while IFS= read -r f; do
        rel_path="${f#./}"
        sha256sum "${rel_path}"
    done >> "${OUT_DIR}/SHA256SUMS"
)
echo "  [OK] SHA256SUMS generated with $(wc -l < "${OUT_DIR}/SHA256SUMS") lines (including header)"

echo "==> assemble-dist.sh completed successfully."
