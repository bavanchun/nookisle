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

# Run install plugin script test suite
python3 tests/test-install-plugin.py
```

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
NOOKISLE_TEST_DIR=out tests/qml/run-lifecycle.sh
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
