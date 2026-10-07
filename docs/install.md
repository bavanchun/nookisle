# Install, configure, and remove

## Install via Omarchy Marketplace

Install directly through Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/bavanchun/nookisle --enable
```

### Requirements
- Omarchy 4.x with a top bar
- x86_64 architecture
- Qt ≥ 6.8

### Runtime Packages
Provided by standard Omarchy / Arch Linux installations:
`qt6-base`, `qt6-multimedia`, `libpipewire`, `systemd-libs`, `openssl`, `libglvnd`, `python`.

### Optional Packages
- `libsecret`: required for CalDAV calendar credentials via Secret Service.
- `zip`, `imagemagick`: required for shelf archive and image conversion actions.

The first time the island is usable, a short welcome window opens. It lets you pick
the idle look, online covers, the player to follow, lyrics, the calendar and
the mirror, and shows the summon key; nothing changes until you pick. The
gear in the open island opens every setting later.

## Updating

Update the installed plugin via Omarchy:

```sh
omarchy plugin update io.github.bavanchun.nookisle
omarchy-restart-shell
```

Restarting the shell (`omarchy-restart-shell`) is required because `keepLoaded` keeps the running plugin and helper processes loaded until the shell restarts.

Updates contain pre-built binaries. Before restarting, you can verify package checksums and build provenance with:

```sh
cd ~/.config/omarchy/plugins/io.github.bavanchun.nookisle
sha256sum -c SHA256SUMS
gh attestation verify SHA256SUMS --repo bavanchun/nookisle --signer-workflow bavanchun/nookisle/.github/workflows/release.yml --source-ref refs/tags/v1.0.3 --deny-self-hosted-runners
```

## Removal

To remove Nookisle:

```sh
omarchy plugin remove io.github.bavanchun.nookisle
omarchy-restart-shell
```

Restarting the shell (`omarchy-restart-shell`) is required because `keepLoaded` keeps the running plugin and helper processes loaded until restart.

Then undo anything you set up by hand:
1. If configured, remove the media-key bindings block: delete the lines between `-- >>> nookisle media keys >>>` and `-- <<< nookisle media keys <<<` in `~/.config/hypr/bindings.lua`, then run `hyprctl reload`.
2. Remove any summon key binding line added to `~/.config/hypr/bindings.lua`, then run `hyprctl reload`.
3. Reset `bar.centerAnchor` in `~/.config/omarchy/shell.json` if configured.
4. If using the Chrome or Chromium extension, remove the extension from the browser, delete the native messaging host manifest (`rm -f ~/.config/google-chrome/NativeMessagingHosts/io.github.bavanchun.nookisle.json` or `~/.config/chromium/NativeMessagingHosts/io.github.bavanchun.nookisle.json`), and delete `~/.config/nookisle/native-host.json`.
5. Delete saved settings, shelf data, and credentials:
   - `rm -rf ~/.config/nookisle`
   - `rm -rf ~/.local/state/nookisle`
   - `secret-tool clear service nookisle` (to clear any saved CalDAV passwords)

## Build from source

To build, test, and develop Nookisle from source, see the [Development Guide](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/development.md).

## Configure calendar sources

The calendar backend is off until `showCalendar` is true. Source definitions
live in the mode-0600 `$XDG_CONFIG_HOME/nookisle/settings.json` file
(or `~/.config/nookisle/settings.json`). The file format is
`{"version":1,"values":{"showCalendar":true,"calendarSources":[...]}}`.
Set `umask 077` before creating or editing this file, keep its parent
directory at mode 0700, and keep the file at mode 0600. Use absolute paths
for local sources:

```json
[
  {"kind":"file","path":"/absolute/path/to/calendar.ics"},
  {"kind":"vdir","path":"/absolute/path/to/calendar-folder"},
  {"kind":"ics-url","url":"https://example.com/private.ics"},
  {"kind":"caldav","url":"https://calendar.example.com/remote.php/dav/calendars/user/personal/","user":"user"}
]
```

If the file is malformed, the plugin logs that it is using defaults. Before
the next settings save replaces it, the original bytes are kept at
`settings.json.bad` in the same private directory so they can be recovered.

Add the desired objects to the `calendarSources` array; `calendarRefresh`
defaults to 15 minutes and cannot be set below 5. For a Nextcloud or
Radicale server on a private LAN, add `"allowLocalNetwork":true` to that
source. Google Calendar uses its **secret address in iCal format** as an
`ics-url` source. Google does not accept app passwords over CalDAV. Treat that
URL as a secret and avoid entering it as a literal shell command argument.

For CalDAV, store an app password in Secret Service under the exact source
URL and user. Enter the value with terminal echo disabled and send it on
standard input:

```sh
read -rs calendar_password
printf '%s' "$calendar_password" | secret-tool store --label='Nookisle CalDAV' service nookisle caldav 'https://calendar.example.com/remote.php/dav/calendars/user/personal/' user 'user'
unset calendar_password
```

Replace the sample URL and user with the values in `calendarSources`.
The helper looks up the same attributes when the visible calendar connects.
Removing a CalDAV source through the settings editor also clears its stored
password, unless another source uses the same account. If you edit
`calendarSources` by hand, clear the removed account's password with the same
attributes:

```sh
secret-tool clear service nookisle caldav 'https://calendar.example.com/remote.php/dav/calendars/user/personal/' user 'user'
```

Loopback and private-network servers, `http://localhost` included, also need
`"allowLocalNetwork": true` on the source. See
[privacy](privacy.md#calendar-backend) for the data flow.

The calendar source editor (hosted by the settings window) does the same
without a terminal. It adds an ICS file, a vdir folder, an iCal link or a
CalDAV account; a remote source needs an explicit "allow this server" tick,
and a LAN server a second one. A CalDAV password typed there goes straight to
the helper, and on to the keyring on standard input; saving a password needs
the calendar on and the island open, and the editor says whether it was
saved. Removing an account removes it from the settings and then deletes
its stored password, unless another source uses the same account; this works
with the island closed. Test loads that source afresh and shows "Connected" or its
error.

## Bar centring and placement

For the island on a full-width top bar, the widget must be first in the centre section and the bar's centre anchor, so the bar reserves the notch's room exactly under it.

To centre the widget manually:
```sh
omarchy bar move io.github.bavanchun.nookisle --section center --index 0
```
Then set `"centerAnchor": "io.github.bavanchun.nookisle"` in `~/.config/omarchy/shell.json` under `"bar"`, and reload the shell config.
To undo, move the widget to another section or remove the `"centerAnchor"` line.

### One on-screen display for media keys

To get exactly one readout per media key, the island's HUD or Omarchy's OSD
but never both, add the following Lua configuration block to `~/.config/hypr/bindings.lua`, then run `hyprctl reload`:

```lua
-- >>> nookisle media keys >>>
-- nookisle: created-file=false; added-newline=false
-- Enables blur globally because Hyprland requires it for layer blur
hl.config({ decoration = { blur = { enabled = true } } })
hl.layer_rule({ match = { namespace = "^nookisle$" }, blur = true, ignore_alpha = 0.5, no_anim = true })
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
hl.unbind("XF86AudioMute")
hl.unbind("XF86AudioMicMute")
hl.unbind("XF86MonBrightnessUp")
hl.unbind("XF86MonBrightnessDown")
hl.unbind("SHIFT + XF86MonBrightnessUp")
hl.unbind("SHIFT + XF86MonBrightnessDown")
hl.unbind("XF86KbdBrightnessUp")
hl.unbind("XF86KbdBrightnessDown")
hl.unbind("XF86KbdLightOnOff")
hl.unbind("ALT + XF86AudioRaiseVolume")
hl.unbind("ALT + XF86AudioLowerVolume")
hl.unbind("ALT + XF86MonBrightnessUp")
hl.unbind("ALT + XF86MonBrightnessDown")
o.bind("XF86AudioRaiseVolume", "Nookisle Volume up", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys volume raise", { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Nookisle Volume down", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys volume lower", { locked = true, repeating = true })
o.bind("XF86AudioMute", "Nookisle Mute", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys volume mute-toggle", { locked = true })
o.bind("XF86AudioMicMute", "Nookisle Mute microphone", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys mic-toggle", { locked = true })
o.bind("XF86MonBrightnessUp", "Nookisle Brightness up", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys brightness +5%", { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Nookisle Brightness down", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys brightness 5%-", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessUp", "Nookisle Brightness maximum", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys brightness 100%", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessDown", "Nookisle Brightness minimum", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys brightness 1%", { locked = true, repeating = true })
o.bind("XF86KbdBrightnessUp", "Nookisle Keyboard brightness up", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys keyboard up", { locked = true, repeating = true })
o.bind("XF86KbdBrightnessDown", "Nookisle Keyboard brightness down", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys keyboard down", { locked = true, repeating = true })
o.bind("XF86KbdLightOnOff", "Nookisle Keyboard backlight cycle", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys keyboard cycle", { locked = true })
o.bind("ALT + XF86AudioRaiseVolume", "Nookisle Volume up precise", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys volume +1", { locked = true, repeating = true })
o.bind("ALT + XF86AudioLowerVolume", "Nookisle Volume down precise", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys volume -1", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessUp", "Nookisle Brightness up precise", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys brightness +1%", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessDown", "Nookisle Brightness down precise", "~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-media-keys brightness 1%-", { locked = true, repeating = true })
-- <<< nookisle media keys <<<
```

To undo: delete the lines between `-- >>> nookisle media keys >>>` and `-- <<< nookisle media keys <<<` in `~/.config/hypr/bindings.lua`, then run `hyprctl reload`.

The bindings block sends the volume, mic, display brightness and keyboard brightness keys to the
packaged `libexec/nookisle-media-keys` script. Before each key it asks the
island, with `omarchy-shell nookisle hudReadout <kind> <device>`, whether
the island will draw that readout. A prompt `ok` gives the readout to the island. Timeout, `unavailable`, and failure give
it to Omarchy; the helper records that decision before acting so a later
island source sample cannot duplicate the fallback OSD. The ownership record
is described in the [interaction reference](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/interaction-reference.md#media-key-readout-ownership).

Without the bindings block, Omarchy's own OSD handles every one of these keys.
Media playback and source-switching keys remain on their default bindings.

### Summon with auto-close

The host's summon opens the island with keyboard focus. Add `"autoClose": true`
to its payload to have it close again by itself after the `summonAutoClose`
setting (3000ms by default; `0` never closes), unless you point at it, press
on it or type into it first. Add this line to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + M", "Nookisle", [[omarchy-shell shell summon io.github.bavanchun.nookisle '{"autoClose":true}']])
```

Change the delay with `omarchy-shell nookisle configure '{"summonAutoClose":5000}'`.

## Preferences and diagnostics

Nookisle always shows the island at the top centre of the screen: hover or
tap it to open Home, or summon it from a key. It keeps the island with a hidden,
bottom, side or vertical bar too. `autoShow: false` hides it until an explicit
summon; panel IPC still works.
The `nookisle` service IPC exposes redacted status and retry:

```sh
omarchy-shell nookisle status
omarchy-shell nookisle retry
omarchy-shell nookisle configure '{"reducedMotion":true}'
omarchy-shell nookisle configure '{"highContrast":true}'
omarchy-shell nookisle configure '{"autoShow":false}'
omarchy-shell nookisle configure '{"hud":false}'
omarchy-shell nookisle settings     # open the settings window
omarchy-shell nookisle onboarding   # show the welcome steps again
```

Of the island's own switches, live spectrum, tint and power are on by
default; track peeks, synced lyrics and online artwork start off. The
[settings guide](settings.md) describes every one with its default:

```sh
omarchy-shell nookisle configure '{"lyrics":true}'       # turn synced lyrics on
omarchy-shell nookisle configure '{"remoteArtwork":true}' # web covers and their tint
omarchy-shell nookisle configure '{"visualizer":false}'   # static glyph instead of live bars
omarchy-shell nookisle configure '{"peek":true}'
omarchy-shell nookisle configure '{"tint":false}'
omarchy-shell nookisle configure '{"power":false}'
```

Turning lyrics on sends the track's title, first artist, album and length to
lrclib.net whenever the open island shows Home or the Lyrics view (details in
[privacy](privacy.md#lyrics)); `configure '{"lyrics":false}'` turns it off and
clears the in-memory cache. A player's local cover file always shows. Covers
fetched from the web (Spotify's, and every browser source's) need
`remoteArtwork`, which stays off by default; without it such a source shows a
music glyph and the island keeps the theme accent.

Browser exact-document control requires the [Chrome extension and native bridge](https://github.com/bavanchun/nookisle/blob/v1.0.3/bridge/README.md); MPRIS-only Chrome
entries remain explicitly browser-scoped.

### Optional compositor blur and layer animation

A default installation does not enable compositor blur; the notch is solid
black and needs none. Hyprland blurs a layer only while its global blur
is on, and Omarchy ships it off (`decoration.blur.enabled = false` in
`/usr/share/omarchy/default/hypr/looknfeel.lua`).

To turn on blur behind translucent island pixels and drop the layer fade, add
this to a file your Hyprland config loads, such as
`~/.config/hypr/looknfeel.lua`, then run `hyprctl reload`:

```lua
-- Nookisle: compositor blur and no layer fade.
hl.config({ decoration = { blur = { enabled = true } } })
hl.layer_rule({ match = { namespace = "^nookisle$" }, blur = true, ignore_alpha = 0.5, no_anim = true })
```

Remove the lines and reload to undo them.
