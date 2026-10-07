#!/usr/bin/env bash
# bump-version.sh — Move the repository to a new release version.
#
#   bump-version.sh X.Y.Z
#
# Edits manifest.json and the CMake project VERSION, rewrites vOLD to vNEW in README.md and
# docs/*.md (docs/releases/ keeps its history), writes the release notes template with a TODO
# marker on every heading, and finishes with tests/source-contract.py. The notes still have to be
# written by hand: scripts/check-release-version.sh rejects the template.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 X.Y.Z" >&2
    exit 2
fi
new="$1"
if ! [[ "${new}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: '${new}' is not a version of the form X.Y.Z" >&2
    exit 2
fi

old=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${ROOT}/manifest.json" | head -n 1)
if [ -z "${old}" ]; then
    echo "ERROR: Failed to parse version from manifest.json" >&2
    exit 1
fi
if [ "${new}" = "${old}" ]; then
    echo "ERROR: manifest.json is already at ${old}" >&2
    exit 1
fi

notes="${ROOT}/docs/releases/${new}.md"
if [ -e "${notes}" ]; then
    echo "ERROR: ${notes#"${ROOT}"/} already exists; refusing to overwrite it" >&2
    exit 1
fi

old_re="${old//./\\.}"
sed -i "s/^\\(  \"version\"[[:space:]]*:[[:space:]]*\"\\)${old_re}\"/\\1${new}\"/" "${ROOT}/manifest.json"
sed -i "s/^\\(project(.*VERSION[[:space:]]\\+\\)${old_re}\\b/\\1${new}/" "${ROOT}/CMakeLists.txt"

targets=("${ROOT}/README.md")
while IFS= read -r doc; do
    targets+=("${doc}")
done < <(find "${ROOT}/docs" -maxdepth 1 -name '*.md' | LC_ALL=C sort)
sed -i "s/\\bv${old_re}\\b/v${new}/g" "${targets[@]}"

mkdir -p "${ROOT}/docs/releases"
cat > "${notes}" <<TEMPLATE
## What changed

<!-- TODO: plain-language description of the user-facing changes -->

## Fixed

<!-- TODO: bug fixes and behavioural corrections -->

## Known limitations

<!-- TODO: trade-offs, caveats and platform-specific limits -->

## What was tested

<!-- TODO: test counts, and what was checked on hardware versus CI versus only on the maintainer's machine -->
TEMPLATE

echo "Bumped ${old} -> ${new}; write docs/releases/${new}.md before tagging."
python3 "${ROOT}/tests/source-contract.py"
