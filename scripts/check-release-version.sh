#!/usr/bin/env bash
# check-release-version.sh — Guard version consistency and release notes.
#
#   check-release-version.sh              CI on main and pull requests
#   check-release-version.sh --tag vX.Y.Z release workflow
#
# The manifest version must equal the CMake project VERSION. With --tag the tag must be
# v<version> and docs/releases/<version>.md must exist, be non-empty and hold no TODO marker.
# Without --tag the notes are required only while v<version> does not exist as a tag yet.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tag=""
case "$#" in
    0) ;;
    2) if [ "$1" = "--tag" ]; then tag="$2"; else tag="?"; fi ;;
    *) tag="?" ;;
esac
if [ "${tag}" = "?" ] || { [ "$#" -eq 2 ] && [ -z "${tag}" ]; }; then
    echo "Usage: $0 [--tag vX.Y.Z]" >&2
    exit 2
fi

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

manifest_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${ROOT}/manifest.json" | head -n 1)
if [ -z "${manifest_version}" ]; then
    fail "Failed to parse version from manifest.json. Fix manifest.json."
fi

cmake_version=$(sed -n 's/.*project(.*VERSION[[:space:]]\+\([0-9.]\+\).*/\1/p' "${ROOT}/CMakeLists.txt" | head -n 1)
if [ "${cmake_version}" != "${manifest_version}" ]; then
    fail "CMakeLists.txt project VERSION '${cmake_version}' does not match manifest.json version '${manifest_version}'. Fix CMakeLists.txt."
fi

if [ -n "${tag}" ] && [ "${tag}" != "v${manifest_version}" ]; then
    fail "Tag '${tag}' does not match manifest.json version 'v${manifest_version}'. Fix manifest.json or tag."
fi

notes_file="docs/releases/${manifest_version}.md"
need_notes=true
if [ -z "${tag}" ] && git -C "${ROOT}" rev-parse -q --verify "refs/tags/v${manifest_version}" >/dev/null 2>&1; then
    need_notes=false
fi

if [ "${need_notes}" = true ]; then
    if [ ! -s "${ROOT}/${notes_file}" ]; then
        fail "Commit the release notes at ${notes_file} before tagging."
    fi
    if grep -qF 'TODO' "${ROOT}/${notes_file}"; then
        fail "${notes_file} still contains a TODO marker. Write the notes before tagging."
    fi
    echo "Guard passed: manifest.json and CMakeLists.txt agree on ${manifest_version}, and ${notes_file} is written"
else
    echo "Guard passed: manifest.json and CMakeLists.txt agree on ${manifest_version}; v${manifest_version} is already tagged, so no notes file is required"
fi
