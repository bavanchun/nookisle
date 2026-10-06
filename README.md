# Nookisle

Nookisle is a native music controller for Omarchy, modelled on [boring.notch](https://github.com/TheBoredTeam/boring.notch). On a top bar it becomes a black notch over the bar's centre: music with a lyric line, a file shelf, calendar, camera mirror and HUD.

*Note: Nookisle is a Linux desktop component for Omarchy and is entirely unrelated to macOS notch applications.*

![Nookisle preview](preview.png)

## Install

Install directly through Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/bavanchun/nookisle --enable
```

Nookisle is also listed in the [Omarchy Plugins directory](https://omarchyplugins.com/plugin.html?id=io.github.bavanchun.nookisle).

### Requirements
- Omarchy 4.x with a top bar
- x86_64 architecture
- Qt ≥ 6.8

### Runtime Packages
Runtime package dependencies (provided by standard Omarchy installations, named here in prose):
`qt6-base`, `qt6-multimedia`, `libpipewire`, `systemd-libs`, `openssl`, `libglvnd`, and `python`.

### Optional Packages
- `libsecret`: required for CalDAV calendar password storage via Secret Service.
- `zip` and `imagemagick`: required for shelf archive and image conversion actions.

## Usage

- **Hover and click:** Hover the notch to open the Home panel; move the pointer away to collapse. Click or tap to expand immediately.
- **Summon key:** Press the configured summon shortcut (such as SUPER+M) to open the island with full keyboard focus; Escape collapses it.
- **Header tabs:** Switch between the **Home** player and the **Shelf** file tray.
- **Welcome flow:** On the first run, an onboarding window opens to introduce the idle look, online covers, remembered player, synced lyrics, calendar, and camera mirror. Nothing changes until you choose.

## Configure

Open settings at any time by clicking the gear icon in the open island's header, or run `omarchy-shell nookisle settings`.
Settings are saved to `~/.config/nookisle/settings.json` (mode 0600).

Nothing is edited automatically. Optional manual steps, each with its exact configuration change and how to undo it:

### 1. Bar Centring
To center the island on a full-width top bar, move the widget to the center section:
```sh
omarchy bar move io.github.bavanchun.nookisle --section center --index 0
```
Then set `"centerAnchor": "io.github.bavanchun.nookisle"` in `~/.config/omarchy/shell.json` under `"bar"`, and reload the shell.
- **To undo:** Move the widget to another section or remove `"centerAnchor"` from `shell.json`.

### 2. Summon Key Binding
To summon Nookisle with a global shortcut, add this line to `~/.config/hypr/bindings.lua`:
```lua
o.bind("SUPER + M", "Nookisle", [[omarchy-shell shell summon io.github.bavanchun.nookisle '{"autoClose":true}']])
```
- **To undo:** Delete the line from `~/.config/hypr/bindings.lua`.

### 3. Level Readout (HUD)
Enable the island's on-screen volume and brightness readout:
```sh
omarchy-shell nookisle configure '{"hud":true}'
```
Enabling the HUD may produce duplicate on-screen displays alongside Omarchy's default OSD unless media keys are rebound (see [docs/install.md](docs/install.md#one-on-screen-display-for-media-keys)).
- **To undo:** Run `omarchy-shell nookisle configure '{"hud":false}'`.

### 4. Chrome Extension & Native Host
For exact-document tab control in Google Chrome or Chromium, register the native messaging host:
See the [bridge documentation](https://github.com/bavanchun/nookisle/blob/v1.0.3/bridge/README.md).
- **To undo:** Remove the extension in the browser, delete the native messaging host manifest from `~/.config/google-chrome/NativeMessagingHosts/io.github.bavanchun.nookisle.json` (or `~/.config/chromium/NativeMessagingHosts/io.github.bavanchun.nookisle.json` for Chromium), and delete `~/.config/nookisle/native-host.json`.

## Remove

To remove the plugin:

```sh
omarchy plugin remove io.github.bavanchun.nookisle
omarchy-restart-shell
```

Restarting the shell (`omarchy-restart-shell`) is necessary because `keepLoaded` keeps the running plugin and helper service loaded until restart.

Then undo anything you set up by hand:
1. If configured, remove the media-key bindings: delete the lines between `-- >>> nookisle media keys >>>` and `-- <<< nookisle media keys <<<` in `~/.config/hypr/bindings.lua`, then run `hyprctl reload`.
2. Remove any summon key binding added to `~/.config/hypr/bindings.lua`, then run `hyprctl reload`.
3. Reset `bar.centerAnchor` in `~/.config/omarchy/shell.json` if configured.
4. If configured, remove the Chrome or Chromium extension, delete the native messaging manifest (`rm -f ~/.config/google-chrome/NativeMessagingHosts/io.github.bavanchun.nookisle.json` or `~/.config/chromium/NativeMessagingHosts/io.github.bavanchun.nookisle.json`), and delete `~/.config/nookisle/native-host.json`.
5. Delete saved settings, shelf state, and credentials as detailed in [Files Nookisle saves](#files-nookisle-saves):
   - `rm -rf ~/.config/nookisle`
   - `rm -rf ~/.local/state/nookisle`
   - `secret-tool clear service nookisle`

## Files Nookisle saves

| Path | Contents | Permissions | Removal |
|---|---|---|---|
| `~/.config/nookisle/settings.json` | Saved preferences (sources, HUD, lyrics, theme, calendar options) | `0600` (directory `0700`) | `rm -rf ~/.config/nookisle` |
| `~/.config/nookisle/settings.json.bad` | Preserved corrupt settings backup if repair occurred | `0600` (directory `0700`) | `rm -rf ~/.config/nookisle` |
| `~/.config/nookisle/native-host.json` | Chrome/Chromium native messaging bridge authorization key | `0600` (directory `0700`) | `rm -rf ~/.config/nookisle` |
| `~/.local/state/nookisle/shelf.json` | Persisted file shelf items, labels, and order | `0600` (directory `0700`) | `rm -rf ~/.local/state/nookisle` |
| `$XDG_RUNTIME_DIR/nookisle*` | Helper lease `nookisle-<session>.lock`, decoded artwork cache directories `nookisle-art-*`, browser bridge directory `nookisle-<session>/` (`browser.sock` socket and `browser.json`), and `nookisle/` directory (media-key readout records, shelf temporary files under `nookisle/shelf`) | `0700` (files `0600`) | Removed on logout, or `rm -rf "$XDG_RUNTIME_DIR"/nookisle*` |
| `~/.cache/thumbnails/{normal,large}/*` | FreeDesktop thumbnail cache for shelf items only | `0600` | Delete matching files in `~/.cache/thumbnails/` |
| Secret Service (`service=nookisle`) | CalDAV calendar account passwords stored in system keyring | Kept encrypted by keyring daemon | `secret-tool clear service nookisle` |

## Bundled binaries and their source

The pre-compiled plugin bundle contains binaries in `libexec/`. Each binary's source code is available at the pinned `v1.0.3` tag:

| Binary | Function | When it runs | Source |
|---|---|---|---|
| `libexec/nookisle-helper` | Coordinates D-Bus session communication, MPRIS players, backlight, system events, and calendar sync | Runs continuously while the plugin service is loaded in the shell | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.3/helper) |
| `libexec/nookisle-artwork-decoder` | Isolated sandbox without network or D-Bus access that sanitizes and re-encodes image files to 256 px | Spawned on demand by the helper to decode local or downloaded artwork | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.3/helper) |
| `libexec/nookisle-artwork-fetch` | Fetches opt-in remote album artwork over HTTPS; in `--lyrics` mode, queries LRCLIB for synced lyrics with streaming 256 KiB cap and no decompression | Spawned on demand when remote artwork or synced lyrics are enabled | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.3/helper) |
| `libexec/nookisle-spectrum` | Reads PipeWire audio monitor levels to compute 12-band frequency amplitudes; no audio samples leave the process | Runs while audio is actively playing and the visualizer is desired and visible | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.3/helper) |
| `libexec/nookisle-media-keys` | Evaluates whether the island HUD or desktop OSD handles volume and brightness changes | Executed on media hotkey presses when bound in `bindings.lua` | [`scripts/`](https://github.com/bavanchun/nookisle/tree/v1.0.3/scripts) |
| `libexec/nookisle-native-host` | Connects the optional Chrome/Chromium extension to the helper over a private local UNIX domain socket | Started by Chrome/Chromium when the extension connects | [`bridge/`](https://github.com/bavanchun/nookisle/tree/v1.0.3/bridge) |

## Privacy and permissions

Nookisle is a local controller. No audio, browsing history, or telemetry leave the machine; calendar credentials are sent only to the CalDAV server the user configures.

### System Access
- **State read:** MPRIS media properties, Hyprland IPC window and workspace events, UPower battery status, PipeWire audio spectrum, `/proc/<pid>/fd` links of the user's own processes (to show camera activity dots while excluding system daemons), and Omarchy's recording marker in `/tmp`.
- **System services:** `systemctl --user stop` is used only for the user's own reminder timers.
- **Privacy gates:** The camera mirror activates only upon explicit user opening. CalDAV accounts connect only when configured. Online album artwork and synced lyrics (from LRCLIB) are strictly opt-in and disabled by default; lyrics requests run in a separate short-lived process (`nookisle-artwork-fetch --lyrics`) that refuses oversized responses (over 256 KiB) while reading and never decompresses.
- **Boundaries:** No elevated privileges, no system-level services, and no remote builds.

## Updating

Update the plugin to the latest version:

```sh
omarchy plugin update io.github.bavanchun.nookisle
omarchy-restart-shell
```

Restarting the shell (`omarchy-restart-shell`) is necessary because `keepLoaded` keeps the previous plugin and helper service loaded until restart.

Updates contain pre-compiled binaries. You can verify the checksums and GitHub build provenance before restarting:

```sh
cd ~/.config/omarchy/plugins/io.github.bavanchun.nookisle
sha256sum -c SHA256SUMS
gh attestation verify SHA256SUMS --repo bavanchun/nookisle --signer-workflow bavanchun/nookisle/.github/workflows/release.yml --source-ref refs/tags/v1.0.3 --deny-self-hosted-runners
```

## Build provenance

Release builds and distribution packages are generated automatically by GitHub Actions:
- **Signer workflow:** [release.yml](https://github.com/bavanchun/nookisle/actions/workflows/release.yml)
- **Attestation verification:** Verify any downloaded release artifact or binary with the GitHub CLI:
  ```sh
  gh attestation verify <file> --repo bavanchun/nookisle --signer-workflow bavanchun/nookisle/.github/workflows/release.yml --source-ref refs/tags/v1.0.3 --deny-self-hosted-runners
  ```
- **SHA256SUMS header:** Shipped packages contain an attested `SHA256SUMS` (GitHub build provenance) file with the header `# nookisle <tag> <source sha>` that binds the release tag to the exact commit SHA on `main`.
- **Reproducible rebuild:** The release can be rebuilt in the pinned container using [scripts/rebuild-dist.sh](https://github.com/bavanchun/nookisle/blob/v1.0.3/scripts/rebuild-dist.sh).

## Development

For building from source, running tests, and developing Nookisle, see the [Development Guide](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/development.md).

## Security

See [SECURITY.md](SECURITY.md) for the security policy and vulnerability reporting.

## License

MIT License. See [LICENSE](LICENSE).

Crediting [boring.notch](https://github.com/TheBoredTeam/boring.notch) as the design inspiration for the notch presentation (no code copied).
