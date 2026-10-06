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
- **Contract and stale-reference check:** `python3 tests/source-contract.py` must pass with zero violations. This includes the mechanical invariants as well as the stale-reference check requiring all `vMAJOR.MINOR.PATCH` mentions in `README.md` and `docs/*.md` to match the manifest version (exempting historical notes in `docs/releases/`).
- **Version consistency and release notes guard:** `manifest.json` version must match `CMakeLists.txt` project VERSION, and a non-empty release notes file must exist at `docs/releases/<version>.md` before tagging. The release workflow enforces this before building.

---

## 2. Pinned Build Environment & ALA Policy

To ensure consistent builds and reproducible binaries, all distribution builds run inside a pinned Arch Linux container image against a fixed Arch Linux Archive (ALA) snapshot.

The environment pins are stored in `release.env`:
- `ARCHLINUX_IMAGE`: The container image pinned by immutable cryptographic SHA256 digest (`archlinux@sha256:...`).
- `ALA_DATE`: The Arch Linux Archive snapshot date (`YYYY/MM/DD`).

### Bumping Policy
1. The `ALA_DATE` must **never** be bumped ahead of the current Arch Linux stable repository.
2. Bumps should be tested locally using `scripts/rebuild-dist.sh` to ensure package compatibility and that no unexpected Qt symbol version jumps occur.
3. Dependabot monitors GitHub Actions SHA pins in `.github/dependabot.yml`. Dependabot reads its config only from the default branch, so `scripts/assemble-dist.sh` ships a copy to `dist`, and the copy targets `main`.

---

## 3. Cutting a Release Tag

Releases are triggered by Git tags following semantic versioning (`vX.Y.Z`).

### Release Notes File and Template

Every release requires a hand-written release notes document committed at `docs/releases/<version>.md` (for example, `docs/releases/1.0.4.md`) before creating the tag. The release workflow refuses any tag if this file is missing or empty, and uses its body as the primary text of the published GitHub release.

The release notes file must follow this structure:
- **What changed**: Plain-language description of user-facing changes, features, and enhancements.
- **Fixed**: Bug fixes, regressions resolved, and behavioral corrections.
- **Known limitations**: Known trade-offs, temporary caveats, or platform-specific limitations.
- **What was tested**: A dedicated paragraph explicitly stating test counts (e.g. 64/64 tests green) and an honest, plain-words summary of what was tested on hardware vs. CI or what was checked only on the maintainer's own machine.

### Ancestor Guard
The release workflow enforces that the tagged commit is a direct ancestor of `origin/main`. Never tag an unmerged experimental branch or detached commit.

### Tagging Procedure

In the examples below, `vX.Y.Z` stands for the release being cut.

```bash
# Ensure local main is up to date with origin
git checkout main
git pull --ff-only origin main

# Verify HEAD matches desired commit
git rev-parse HEAD

# Create an annotated, signed release tag matching manifest.json version
git tag -s vX.Y.Z -m "release: nookisle vX.Y.Z"

# Push the tag to GitHub
git push origin vX.Y.Z
```

---

## 4. Release Pipeline (`release.yml`)

The release workflow consists of three strictly isolated jobs:

1. **`build` (archlinux container):**
   - Validates that the tag matches `manifest.json` and `CMakeLists.txt` project VERSION, and ensures `docs/releases/<version>.md` exists and is non-empty before any build steps.
   - Validates that the tag commit is an ancestor of `main`.
   - Points pacman to the pinned ALA snapshot and installs dependencies.
   - Configures CMake with `-DCMAKE_BUILD_TYPE=Release`, `-DNOOKISLE_REQUIRE_ALL_FEATURES=ON`, `-DNOOKISLE_HOST_TESTS=OFF`, and `-DNOOKISLE_BUILD_REVISION=${GITHUB_SHA}`.
   - Runs test suite: `ctest -LE needs-netns`.
   - Installs and strips binaries, then runs `scripts/assemble-dist.sh stage out`.
   - Verifies symbol boundaries: ensures no `Qt_6_PRIVATE_API` symbols are referenced, and records the maximum Qt symbol version.
   - Uploads `out/` and `out-meta/` build artifacts (including the release notes document).

2. **`attest` (GitHub Actions runner):**
   - Downloads the build artifact.
   - Generates cryptographically verifiable build provenance attestations for all executables in `libexec/` and `SHA256SUMS` using GitHub's artifact attestation service (`actions/attest-build-provenance`).

3. **`publish` (Environment `release`):**
   - Requires manual authorization by the repository owner (`release` environment gate).
   - Loads the dedicated deploy key (`NOOKISLE_DIST_DEPLOY_KEY`) with write permissions restricted to the `dist` branch.
   - *Ruleset limitation note:* On GitHub personal repositories, ruleset bypass lists cannot be restricted exclusively to a deploy key (only organization roles, teams, or apps are supported). Therefore, the `protect-dist` ruleset enforces deletion and non-fast-forward protection, while branch write access is managed via the environment-scoped deploy key and repository access controls.
   - **Idempotent check:** Verifies if the existing `dist` branch already contains a commit for this tag. If so, skips commit creation.
   - Fast-forwards/commits the assembled `dist` tree to branch `dist`.
   - Creates a notes-only GitHub release containing the contents of `docs/releases/<version>.md`, followed by the verification instructions and `SHA256SUMS`. No tarballs or binaries are attached to the release.

---

## 5. Verifying Provenance Attestations

Anyone can verify that the binaries published in the `dist` branch were built directly from the official repository and workflow using the GitHub CLI:

```bash
gh attestation verify libexec/nookisle-helper \
  --repo bavanchun/nookisle \
  --signer-workflow bavanchun/nookisle/.github/workflows/release.yml \
  --source-ref refs/tags/vX.Y.Z \
  --deny-self-hosted-runners
```

Repeat for each binary in `libexec/` or verify `SHA256SUMS`:

```bash
gh attestation verify SHA256SUMS \
  --repo bavanchun/nookisle \
  --signer-workflow bavanchun/nookisle/.github/workflows/release.yml \
  --source-ref refs/tags/vX.Y.Z \
  --deny-self-hosted-runners
```

---

## 6. Verifying Reproducible Rebuilds (Best-Effort)

To independently rebuild the distribution tree from source using the pinned container and diff against the published `SHA256SUMS`:

```bash
scripts/rebuild-dist.sh vX.Y.Z
```

The script runs the build in the identical container environment and compares the resulting `SHA256SUMS` against the reference.

---

## 7. Omarchy Marketplace Verification Update

After the release workflow finishes and publishes the updated `dist` branch:

1. Obtain the exact 40-character Git commit SHA of the updated `dist` branch:
   ```bash
   git fetch origin dist
   git rev-parse origin/dist
   ```
2. Open the **Plugin verification** issue form (`verify-plugin.yml`) on the Omarchy marketplace repository.
3. Select **"Verify and publish a newer upstream commit"**.
4. Fill in the form fields:
   - **Plugin ID**: `io.github.bavanchun.nookisle`
   - **Repository URL**: `https://github.com/bavanchun/nookisle`
   - **Commit SHA**: The full 40-character `origin/dist` SHA from step 1.
5. Wait for the automated bot reports to complete.
6. A marketplace maintainer conducts review and applies the `approved-and-verified` label.
7. **Operational notes:**
   - An unpromoted update shows in the marketplace catalog as "Update unverified".
   - The `dist` branch **must not move again** while a request is pending because approval binds to the exact 40-character commit SHA submitted.
