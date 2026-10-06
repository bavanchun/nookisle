# Nookisle Release Runbook

This document is the operational runbook for Nookisle maintainers. It defines the release gates, tagging procedure, CI/CD pipeline, attestation verification, and marketplace update process.

---

## 1. Local Release Gates

Before tagging a release, the maintainer must run the full test suite locally on an Arch Linux host.

```bash
# 1. Clean build and run host tests
cmake --preset release
cmake --build --preset release
ctest --preset release --output-on-failure

# 2. Run network-dependent helper tests requiring network namespace isolation
# helper-artwork-network is labeled "needs-netns" and excluded from container CI
ctest --preset release -R helper-artwork-network --verbose
```

### Critical Gate Requirements
- **64/64 tests green:** All unit, integration, and contract tests must pass.
- **Strict link check:** The environment override `NOOKISLE_ALLOW_DANGLING_LINKS=1` is **strictly forbidden** for releases. It is an internal development aid only. Every relative link in shipped documentation (`README.md`, `docs/*.md`) must resolve to a valid file within the assembled `dist` tree.
- **Contract check:** `python3 tests/source-contract.py` must pass with zero violations.

---

## 2. Pinned Build Environment & ALA Policy

To ensure consistent builds and reproducible binaries, all distribution builds run inside a pinned Arch Linux container image against a fixed Arch Linux Archive (ALA) snapshot.

The environment pins are stored in `release.env`:
- `ARCHLINUX_IMAGE`: The container image pinned by immutable cryptographic SHA256 digest (`archlinux@sha256:...`).
- `ALA_DATE`: The Arch Linux Archive snapshot date (`YYYY/MM/DD`).

### Bumping Policy
1. The `ALA_DATE` must **never** be bumped ahead of the current Arch Linux stable repository.
2. Bumps should be tested locally using `scripts/rebuild-dist.sh` to ensure package compatibility and that no unexpected Qt symbol version jumps occur.
3. Dependabot monitors GitHub Actions SHA pins in `.github/dependabot.yml`.

---

## 3. Cutting a Release Tag

Releases are triggered by Git tags following semantic versioning (`vX.Y.Z`).

### Ancestor Guard
The release workflow enforces that the tagged commit is a direct ancestor of `origin/main`. Never tag an unmerged experimental branch or detached commit.

### Tagging Procedure
```bash
# Ensure local main is up to date with origin
git checkout main
git pull --ff-only origin main

# Verify HEAD matches desired commit
git rev-parse HEAD

# Create an annotated, signed release tag
git tag -s v1.0.0 -m "release: nookisle v1.0.0"

# Push the tag to GitHub
git push origin v1.0.0
```

---

## 4. Release Pipeline (`release.yml`)

The release workflow consists of three strictly isolated jobs:

1. **`build` (archlinux container):**
   - Validates that the tag commit is an ancestor of `main`.
   - Points pacman to the pinned ALA snapshot and installs dependencies.
   - Configures CMake with `-DCMAKE_BUILD_TYPE=Release`, `-DNOOKISLE_REQUIRE_ALL_FEATURES=ON`, `-DNOOKISLE_HOST_TESTS=OFF`, and `-DNOOKISLE_BUILD_REVISION=${GITHUB_SHA}`.
   - Runs test suite: `ctest -LE needs-netns`.
   - Installs and strips binaries, then runs `scripts/assemble-dist.sh stage out`.
   - Verifies symbol boundaries: ensures no `Qt_6_PRIVATE_API` symbols are referenced, and records the maximum Qt symbol version.
   - Uploads `out/` and `out-meta/` build artifacts.

2. **`attest` (GitHub Actions runner):**
   - Downloads the build artifact.
   - Generates cryptographically verifiable build provenance attestations for all executables in `libexec/` and `SHA256SUMS` using GitHub's artifact attestation service (`actions/attest-build-provenance`).

3. **`publish` (Environment `release`):**
   - Requires manual authorization by the repository owner (`release` environment gate).
   - Loads the dedicated deploy key (`NOOKISLE_DIST_DEPLOY_KEY`) with write permissions restricted to the `dist` branch.
   - *Ruleset limitation note:* On GitHub personal repositories, ruleset bypass lists cannot be restricted exclusively to a deploy key (only organization roles, teams, or apps are supported). Therefore, the `protect-dist` ruleset enforces deletion and non-fast-forward protection, while branch write access is managed via the environment-scoped deploy key and repository access controls.
   - **Idempotent check:** Verifies if the existing `dist` branch already contains a commit for this tag. If so, skips commit creation.
   - Fast-forwards/commits the assembled `dist` tree to branch `dist`.
   - Creates a notes-only GitHub release containing the `SHA256SUMS`, the maximum Qt version, and provenance verification instructions. No tarballs or binaries are attached to the release.

---

## 5. Verifying Provenance Attestations

Anyone can verify that the binaries published in the `dist` branch were built directly from the official repository and workflow using the GitHub CLI:

```bash
gh attestation verify libexec/nookisle-helper \
  --repo bavanchun/nookisle \
  --signer-workflow bavanchun/nookisle/.github/workflows/release.yml \
  --source-ref refs/tags/v1.0.0 \
  --deny-self-hosted-runners
```

Repeat for each binary in `libexec/` or verify `SHA256SUMS`:

```bash
gh attestation verify SHA256SUMS \
  --repo bavanchun/nookisle \
  --signer-workflow bavanchun/nookisle/.github/workflows/release.yml \
  --source-ref refs/tags/v1.0.0 \
  --deny-self-hosted-runners
```

---

## 6. Verifying Reproducible Rebuilds (Best-Effort)

To independently rebuild the distribution tree from source using the pinned container and diff against the published `SHA256SUMS`:

```bash
scripts/rebuild-dist.sh v1.0.0
```

The script runs the build in the identical container environment and compares the resulting `SHA256SUMS` against the reference.

---

## 7. Omarchy Marketplace Verification Update

After the release workflow finishes and publishes the updated `dist` branch:

1. Obtain the exact Git commit SHA of the `dist` branch:
   ```bash
   git fetch origin dist
   git rev-parse origin/dist
   ```
2. Navigate to the Omarchy Marketplace repository or verification portal.
3. Submit the new `dist` commit SHA to update the verified plugin entry for `io.github.bavanchun.nookisle`.
4. Verify that the marketplace scanner completes successfully.
