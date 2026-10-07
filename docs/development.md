# Nookisle Development & Build Guide

This guide covers building, testing, and developing Nookisle from source on Linux (specifically Omarchy or Arch-based systems).

---

## 1. Prerequisites & Dependencies

To build Nookisle from source, install the necessary compiler toolchain, CMake, Qt 6, and development libraries:

### System Packages (Arch Linux / Omarchy)
- **Toolchain & Build System:** `base-devel`, `cmake`, `ninja`, `pkgconf`, `git`
- **Qt 6 Framework:** `qt6-base`, `qt6-declarative`, `qt6-multimedia`
- **Audio & Hardware Libraries:** `libpipewire`, `systemd-libs` (libudev)
- **Utilities & Cryptography:** `openssl`, `nlohmann-json`
- **Testing & Tooling:** `python`, `nodejs`, `iproute2`, `dbus`

---

## 2. CMake Build Configuration

Nookisle provides pre-configured CMake presets in `CMakePresets.json`:

```bash
# Configure with the release preset
cmake --preset release

# Or configure manually with Ninja
cmake -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DNOOKISLE_REQUIRE_ALL_FEATURES=ON \
  -DNOOKISLE_HOST_TESTS=ON
```

### CMake Options
- `NOOKISLE_REQUIRE_ALL_FEATURES=ON`: Strictly requires `libudev` and `libpipewire` (fails configuration if either is missing instead of disabling components).
- `NOOKISLE_HOST_TESTS=ON`: Enables host-dependent integration tests requiring Quickshell and QML runtime.
- `NOOKISLE_CALENDAR=ON`: Enables calendar helper and iCal/CalDAV support.
- `NOOKISLE_BUILD_REVISION`: Overrides the 40-character hexadecimal Git revision hash stamped into `manifest.json`.

---

## 3. Building

Compile the project using CMake and Ninja:

```bash
cmake --build --preset release
# Or: cmake --build build
```

The compiled helper executables will be located in `build/bin/` and test executables in `build/tests/`.

---

## 4. Running Tests

Run the full test suite via CTest:

```bash
ctest --preset release --output-on-failure
```

### Running Specific Tests
```bash
# Run unit tests only
ctest --preset release -R "helper-*"

# Run source contract verification
python3 tests/source-contract.py

# Run the isolated QML lifecycle gate
bash tests/qml/run-lifecycle.sh

# Run install plugin script test suite
python3 tests/test-install-plugin.py

# Run the version guard and bump script tests
python3 tests/test-release-guard.py
```

CI builds with `NOOKISLE_HOST_TESTS=OFF` and runs 18 non-QML tests (`.github/workflows/ci.yml`), so a green CI run says nothing about the QML suites. `ctest --preset release` run locally is the gate for any change that touches QML.

### Network-Isolated Tests
The test `helper-artwork-network` is labeled `needs-netns` because it verifies artwork download behavior inside an isolated network namespace. Run it individually:
```bash
ctest --preset release -R helper-artwork-network --verbose
```

---

## 5. Local Staging & Assembly

To test the installation staging and distribution packaging without affecting your live desktop:

```bash
# 1. Install to local build prefix
cmake --install build --strip --prefix stage

# 2. Assemble the distribution tree into out/
scripts/assemble-dist.sh stage out

# 3. Validate the assembled plugin using Omarchy CLI
omarchy plugin validate out/

# 4. Verify QML lifecycle against out/
NOOKISLE_TEST_DIR=out bash tests/qml/run-lifecycle.sh
```

---

## 6. Code Style & Architecture Contracts

Nookisle enforces architectural boundaries via `tests/source-contract.py`:
- Helper binary must never link `Qt6::Gui`.
- Image decoder child process must never link `Qt6::Network` or `Qt6::DBus`.
- All QML files and C++ sources follow strict naming, header include, and permission patterns.

Verify your changes against the source contract before submitting pull requests:
```bash
python3 tests/source-contract.py
```

---

## 7. Branches and Contributions

`dist` is the default branch of the repository, and `main` is where the work happens.

- **Why `dist` is the default.** `omarchy plugin add` clones only the default branch, and `omarchy plugin update` fast-forwards to the remote `HEAD` ([`omarchy-plugin-update`](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-plugin-update)). The Omarchy marketplace verifies and lists a commit of the plugin repository ([verification document](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md)). The installed tree needs the compiled `libexec/` binaries, and `main` holds source only, so the default branch has to be the CI-built `dist` tree. `main` and `dist` share no history, so switching the default would strand existing users.
- **Trunk.** `main` is the trunk and the only source of release tags. `dist` is written only by `release.yml`; never push to it by hand. There is no `develop` branch and no release branch.
- **Topic branches.** Branch from `main` as `feat/`, `fix/`, `docs/`, `ci/` or `chore/` plus a short name, keep the branch short-lived, and open the pull request against `main`. Pull requests are squash-merged (the repository allows no other merge method) and the branch is deleted on merge. Release 1.0.4 is pushed directly to `main`; the pull-request rule is enforced after it.
- **A pull request opened against `dist`** is aimed at the wrong branch: a branch cut from `main` shares no history with `dist`, so it cannot be merged there. Close it with a pointer to `main`.
- **Identity.** Commit with the repository's GitHub noreply address. A local `pre-push` hook refuses any push whose history contains the old repository root, which guards against publishing the pre-rewrite history.
- **Never merge with `--admin`.** A merge that skips the required checks defeats the point of having them.
- **Dependabot** opens one grouped weekly pull request for GitHub Actions updates against `main`, and waits seven days after a new action release (`.github/dependabot.yml`). Dependabot reads its config from the default branch, so an edit takes effect at the next release, when `assemble-dist.sh` ships the file to `dist`. Container digests and the Arch Linux Archive date are bumped by hand.
- **Hotfixes** are the next patch release cut from `main`.

### Version and release preparation

`scripts/bump-version.sh X.Y.Z` moves the manifest, the CMake version and every `vX.Y.Z` reference in `README.md` and `docs/*.md` to the new version, creates the release notes template at `docs/releases/X.Y.Z.md`, and runs `tests/source-contract.py`. `scripts/check-release-version.sh` is the one guard behind both CI and the release workflow; see [release.md](release.md).
