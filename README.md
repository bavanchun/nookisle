# Nookisle

![Nookisle island opening and closing with music playback](https://github.com/user-attachments/assets/42af95c6-d19c-4927-b422-92560cdc38f9)

<video src="https://github.com/user-attachments/assets/68e311bd-019f-4316-b516-2257dfea5e57" controls muted></video>

<p>
  <img src="https://github.com/user-attachments/assets/417c6a6a-804b-4950-8e92-d2b0e18c4114" width="49%" alt="Closed notch showing cover, title and live spectrum">
  <img src="https://github.com/user-attachments/assets/31fc357c-1c9b-433f-b8c0-df95ef44aeda" width="49%" alt="Home view with player, synced lyric line and calendar">
</p>
<p>
  <img src="https://github.com/user-attachments/assets/e5f43b1b-e436-464b-a559-4471d39ff157" width="49%" alt="Lyrics view with three synced lines">
  <img src="https://github.com/user-attachments/assets/15f27425-614c-48bf-b636-e62c38680f09" width="49%" alt="Shelf tab with the Share tile and the drop zone">
</p>
<p>
  <img src="https://github.com/user-attachments/assets/e074bef3-235f-4680-9c23-92d459ee7bff" width="49%" alt="Volume HUD shown inside the closed notch">
  <img src="https://github.com/user-attachments/assets/aae2dadb-ee0f-49a7-821d-155ed7591bc2" width="49%" alt="Microphone and camera privacy dots in the closed notch">
</p>

Media note: on-screen track names and cover art belong to their owners. The video is silent; lyric lines come from LRCLIB at runtime.

Nookisle is a dynamic island for Omarchy: music controls and synced lyrics, a file shelf, calendar, camera mirror and volume/brightness HUD in a black notch at the centre of your top bar.

## Why Nookisle

| What you get | What backs it up |
|---|---|
| An island alongside your bar | A native Omarchy plugin; your bar stays in place. See [installation](docs/install.md). |
| Spectrum from real audio | Local PipeWire monitor levels drive the bars; no audio leaves the capture process. See [privacy](docs/privacy.md#spectrum). |
| Opt-in synced lyrics | LRCLIB lookups send title, first artist, album and rounded length; a normal lookup is one request, with at most four after a busy response and a real miss. See [the lyrics contract](docs/privacy.md#lyrics). |
| Cover colour with a contrast guard | Colour stays on graphics, with contrast checks against the black notch. See [the interface](docs/interface.md). |
| Reduced motion that stops loops | Reduced motion stops the live spectrum and idle animation loops. See [settings](docs/settings.md). |
| Verifiable release binaries | GitHub build attestations and `SHA256SUMS`; see [build provenance](#build-provenance). |
| Fast-forward updates | The protected distribution branch moves forward through the release workflow. See [updating](#updating). |
| A local release gate | 64 CTest suites cover helper, lyrics, UI, lifecycle, packaging and browser contracts. See [development](https://github.com/bavanchun/nookisle/blob/v1.0.4/docs/development.md). |

Updates fast-forward only. Every binary is attested.

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
See the [bridge documentation](https://github.com/bavanchun/nookisle/blob/v1.0.4/bridge/README.md).
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

The pre-compiled plugin bundle contains binaries in `libexec/`. Each binary's source code is available at the pinned `v1.0.4` tag:

| Binary | Function | When it runs | Source |
|---|---|---|---|
| `libexec/nookisle-helper` | Coordinates D-Bus session communication, MPRIS players, backlight, system events, and calendar sync | Runs continuously while the plugin service is loaded in the shell | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.4/helper) |
| `libexec/nookisle-artwork-decoder` | Isolated sandbox without network or D-Bus access that sanitizes and re-encodes image files to 256 px | Spawned on demand by the helper to decode local or downloaded artwork | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.4/helper) |
| `libexec/nookisle-artwork-fetch` | Fetches opt-in remote album artwork over HTTPS; in `--lyrics` mode, queries LRCLIB for synced lyrics with streaming 256 KiB cap and no decompression | Spawned on demand when remote artwork or synced lyrics are enabled | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.4/helper) |
| `libexec/nookisle-spectrum` | Reads PipeWire audio monitor levels to compute 12-band frequency amplitudes; no audio samples leave the process | Runs while audio is actively playing and the visualizer is desired and visible | [`helper/`](https://github.com/bavanchun/nookisle/tree/v1.0.4/helper) |
| `libexec/nookisle-media-keys` | Evaluates whether the island HUD or desktop OSD handles volume and brightness changes | Executed on media hotkey presses when bound in `bindings.lua` | [`scripts/`](https://github.com/bavanchun/nookisle/tree/v1.0.4/scripts) |
| `libexec/nookisle-native-host` | Connects the optional Chrome/Chromium extension to the helper over a private local UNIX domain socket | Started by Chrome/Chromium when the extension connects | [`bridge/`](https://github.com/bavanchun/nookisle/tree/v1.0.4/bridge) |

## Privacy and permissions

Nookisle is a local controller. No audio, browsing history, or telemetry leave the machine; calendar credentials are sent only to the CalDAV server the user configures.

### System Access
- **State read:** MPRIS media properties, Hyprland IPC window and workspace events, UPower battery status, PipeWire audio spectrum, `/proc/<pid>/fd` links of the user's own processes (to show camera activity dots while excluding system daemons), and Omarchy's recording marker in `/tmp`.
- **System services:** `systemctl --user stop` is used only for the user's own reminder timers.
- **Privacy gates:** The camera mirror is off by default; enabling Mirror on Home keeps its feed running while that view is open. CalDAV accounts connect only when configured. Online album artwork and synced lyrics (from LRCLIB) are strictly opt-in and disabled by default; lyrics requests run in a separate short-lived process (`nookisle-artwork-fetch --lyrics`) that refuses oversized responses (over 256 KiB) while reading and never decompresses.
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
gh attestation verify SHA256SUMS --repo bavanchun/nookisle --signer-workflow bavanchun/nookisle/.github/workflows/release.yml --source-ref refs/tags/v1.0.4 --deny-self-hosted-runners
```

## Build provenance

Release builds and distribution packages are generated automatically by GitHub Actions:
- **Signer workflow:** [release.yml](https://github.com/bavanchun/nookisle/actions/workflows/release.yml)
- **Attestation verification:** Verify any downloaded release artifact or binary with the GitHub CLI:
  ```sh
  gh attestation verify <file> --repo bavanchun/nookisle --signer-workflow bavanchun/nookisle/.github/workflows/release.yml --source-ref refs/tags/v1.0.4 --deny-self-hosted-runners
  ```
- **SHA256SUMS header:** Shipped packages contain an attested `SHA256SUMS` (GitHub build provenance) file with the header `# nookisle <tag> <source sha>` that binds the release tag to the exact commit SHA on `main`.
- **Reproducible rebuild:** The release can be rebuilt in the pinned container using [scripts/rebuild-dist.sh](https://github.com/bavanchun/nookisle/blob/v1.0.4/scripts/rebuild-dist.sh).

## Development

`dist` (the default branch) is the CI-built tree that `omarchy plugin add` installs; the source is on `main`. Open pull requests against `main`.

For building from source, running tests, and developing Nookisle, see the [Development Guide](https://github.com/bavanchun/nookisle/blob/v1.0.4/docs/development.md).

## Security

See [SECURITY.md](SECURITY.md) for the security policy and vulnerability reporting.

## License

MIT License. See [LICENSE](LICENSE).
