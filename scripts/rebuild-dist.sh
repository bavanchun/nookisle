#!/usr/bin/env bash
# rebuild-dist.sh — Rebuild Nookisle dist tree in the pinned container and diff SHA256SUMS.
# Note: Best-effort tool for verification; reproducible rebuild is best-effort.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <tag-or-commit> [reference-sha256sums-file]" >&2
    exit 1
fi

TAG="$1"
REF_SUMS="${2:-}"

# Load container and ALA pins
if [ -f "${REPO_ROOT}/release.env" ]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/release.env"
else
    echo "ERROR: release.env not found in ${REPO_ROOT}" >&2
    exit 1
fi

CONTAINER_TOOL=""
if command -v podman >/dev/null 2>&1; then
    CONTAINER_TOOL="podman"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_TOOL="docker"
else
    echo "ERROR: Neither podman nor docker found on system" >&2
    exit 1
fi

# Resolve source commit SHA
TAG_SHA=$(git -C "${REPO_ROOT}" rev-parse "${TAG}^{commit}" 2>/dev/null || git -C "${REPO_ROOT}" rev-parse "${TAG}" 2>/dev/null || echo "")
if [ -z "${TAG_SHA}" ]; then
    echo "WARNING: Could not resolve git commit for '${TAG}', using HEAD" >&2
    TAG_SHA=$(git -C "${REPO_ROOT}" rev-parse HEAD)
fi

echo "==> Rebuilding dist for ${TAG} (${TAG_SHA})"
echo "    Container: ${ARCHLINUX_IMAGE}"
echo "    ALA Date:  ${ALA_DATE}"
echo "    Tool:      ${CONTAINER_TOOL}"

WORK_DIR=$(mktemp -d /tmp/nookisle-rebuild.XXXXXX)
trap 'rm -rf "${WORK_DIR}"' EXIT

REBUILD_SUMS="${WORK_DIR}/SHA256SUMS"

# Run container build
# Pass NOOKISLE_ALLOW_DANGLING_LINKS=1 in case docs contain pre-Phase 5 links
"${CONTAINER_TOOL}" run --rm \
    -v "${REPO_ROOT}":/src:ro \
    -v "${WORK_DIR}":/dest:rw \
    -e ALA_DATE="${ALA_DATE}" \
    -e TAG="${TAG}" \
    -e TAG_SHA="${TAG_SHA}" \
    -e NOOKISLE_ALLOW_DANGLING_LINKS="${NOOKISLE_ALLOW_DANGLING_LINKS:-1}" \
    "${ARCHLINUX_IMAGE}" bash -c '
set -euo pipefail
echo "Server = https://archive.archlinux.org/repos/${ALA_DATE}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
pacman -Syuu --noconfirm base-devel cmake ninja git qt6-base qt6-declarative qt6-multimedia nlohmann-json openssl libpipewire systemd-libs pkgconf python python-gobject nodejs iproute2 dbus >/dev/null
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
dbus-uuidgen --ensure

mkdir -p /build-src
cp -a /src/. /build-src/
cd /build-src

# Clean any existing build artifacts inside copied tree
rm -rf build out stage

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DNOOKISLE_HOST_TESTS=OFF \
    -DNOOKISLE_REQUIRE_ALL_FEATURES=ON \
    -DNOOKISLE_BUILD_REVISION="${TAG_SHA}" >/dev/null

cmake --build build >/dev/null
cmake --install build --strip --prefix stage >/dev/null

NOOKISLE_TAG="${TAG}" scripts/assemble-dist.sh stage out >/dev/null

cp out/SHA256SUMS /dest/SHA256SUMS
'

echo "==> Container build complete."

if [ -z "${REF_SUMS}" ]; then
    # Look for reference SHA256SUMS in origin/dist or current out/
    if [ -f "${REPO_ROOT}/out/SHA256SUMS" ]; then
        REF_SUMS="${REPO_ROOT}/out/SHA256SUMS"
    elif git -C "${REPO_ROOT}" show origin/dist:SHA256SUMS > "${WORK_DIR}/ref_sums.txt" 2>/dev/null; then
        REF_SUMS="${WORK_DIR}/ref_sums.txt"
    fi
fi

if [ -n "${REF_SUMS}" ] && [ -f "${REF_SUMS}" ]; then
    echo "==> Comparing against reference: ${REF_SUMS}"
    if diff -u "${REF_SUMS}" "${REBUILD_SUMS}"; then
        echo "SUCCESS: Rebuilt dist SHA256SUMS matches reference exactly!"
        exit 0
    else
        echo "NOTICE: Rebuilt dist SHA256SUMS differs from reference (best-effort rebuild)." >&2
        exit 1
    fi
else
    echo "Generated SHA256SUMS:"
    cat "${REBUILD_SUMS}"
fi
