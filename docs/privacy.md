# Privacy and input boundaries

Nookisle is a local controller. Audio stays in Spotify or Chrome; there is
no streaming service, login, OAuth token, listening-history database, telemetry,
or cloud backend in this project.

MPRIS exposes player metadata on the user's session bus. Metadata and artwork
are untrusted presentation, never command-routing authority. The helper binds
commands to the selected endpoint lifetime, and the panel does not fall back
to another player when an operation fails. Browser MPRIS identifies a browser
endpoint; exact-document control requires the site-restricted extension.
The extension reads a supported site's like-button state and sends only the
current liked boolean and capability to the local helper. A favorite command
clicks that site's button in the selected document; no like history is stored
by Nookisle.

## Artwork

Remote artwork is disabled by default and can be enabled explicitly. It
governs network fetches only. A native player that names a local cover file
(`mpris:artUrl` `file:///…`, as mpv and many local players do) shows its cover
with remote artwork off, because reading it sends nothing off the machine.
Only the selected visible source is eligible, including paused or compact views. Closing
the island, locking, disabling the plugin, or changing source cancels work.
Artwork requests necessarily disclose the requester's IP and the selected
artwork resource to its server. No cookies, credentials or referrer are sent.
Titles and artwork URLs, including query strings, are not diagnostic logs.

The bounded pipeline admits HTTPS public destinations only, rechecks redirects,
pins the validated numeric destination with TLS verification for the original
host, and rejects private/loopback/link-local addresses and downgrade redirects.
The compressed input, redirects, wall deadline, static-image dimensions and
decoded size are capped. The fetch itself runs in a short-lived child process
(`nookisle-artwork-fetch`) that exits after each
download, and the helper bounds its output and deadline. A separate decoder child has OS resource limits and
can be killed by the parent without blocking the shell's event loop. The
helper publishes the child's PNG as it is, after checking its header, and
never decodes or keeps the pixels itself.

QML receives only a sanitized local image path from a private runtime directory,
not an arbitrary network URL. That directory is removed when the helper stops,
and any a killed helper left behind is removed by the next one in the same
D-Bus session. An untagged cache from an older build stays until logout
clears the runtime directory, because its helper may still be running. Files and transient cache state are bounded and
owned by the helper instance. Only the selected, visible source advertises a
path: when the selection moves, is cancelled or is hidden, every endpoint,
browser ones included, stops advertising its path before the cached file can
expire.

A local cover is read only when the selected player names it. The path must be
an absolute `file:` URL with no host (or `localhost`), query or user
information. The file must be a regular file of at most 32 MiB, never a
device, pipe or directory, and its bytes must begin as a PNG or JPEG: the
extension is not trusted. The bytes decode in the same bounded child, which
re-encodes fresh pixels without metadata at 256 px. Browser (extension)
artwork is always a network fetch and still needs remote artwork. A player
on the session bus runs as you and could read the same file itself; the
island only draws it as an image and sends nothing anywhere. With `tint` on, the island reads
the colours of that same local file in memory; no colour, file or URL leaves
the machine for it. Exact policies and adversarial
checks live in [the loader](https://github.com/bavanchun/nookisle/blob/v1.0.4/helper/artwork-loader.cpp) and
[its tests](https://github.com/bavanchun/nookisle/blob/v1.0.4/tests/helper/artwork-loader-test.cpp).

## Level readout

The plugin reads output volume through PipeWire in
[VolumeSource.qml](../components/VolumeSource.qml). While the HUD is enabled,
[BrightnessSource.qml](../components/BrightnessSource.qml) finds the first
display backlight with a nonzero maximum (or the configured device), reads
its level and the keyboard backlight level from local sysfs, and listens for
the display's unprivileged udev change events, which the helper watches on
udev's netlink socket. The keyboard level is re-read
only when a local caller (the installed key bindings) runs the
`keyboardBacklightChanged()` IPC verb. A dragged HUD bar may write a requested
level through `brightnessctl -d`; the device name selected in settings is
stored in the plugin's local settings file. `Service.qml` forwards only the
transient levels and reports whether the display monitor is running.

[MicSource.qml](../components/MicSource.qml) reads the default PipeWire input
source's mute bit when Panel loads it for the HUD. It establishes a silent
baseline when the source changes and emits only later mute flips. No audio
samples are captured by this source. These levels and the mic mute state are
not logged or written to disk; `hud:false` stops the backlight readers and
prevents the Panel-owned audio sources from loading.

## Spectrum

While music plays and the island is on screen, `visualizer` (on by default)
runs a small local capture of the default output's monitor to draw the pill's
bars. The audio never leaves that process: it reduces each frame to 12 band
levels, prints only those numbers to the Service, and writes nothing to disk,
logs or the network. The capture is a visible PipeWire stream named
`nookisle-spectrum` ("Nookisle spectrum") in `pw-cli ls Node` and in
audio tools, and it exists only while music plays on the visible island
(it keeps running while the island is expanded, to avoid a reconnect on every
hover). It stops when
playback pauses, motion is reduced (the pill shows a still glyph instead), or
the island is hidden,
and on lock when the host exposes its lock service. On a host that
scopes the lock service away from plugins (Omarchy since 2026-09) there is no
lock signal to read, so a playing, visible island keeps the capture running
behind the lock screen; the compositor hides the island and nothing leaves the
process, but the CPU cost continues. `visualizer:false` turns it off.

## Power

With `power` on (the default) and the island in use, the plugin reads the
UPower display device (charge level, whether it is a present laptop
battery) and whether the machine runs on battery, through
[PowerSource.qml](../components/PowerSource.qml), to draw power peeks or banners and the
battery UI. The values stay in memory as the last sample the
peek compares against; nothing is written to disk, logged, sent anywhere or
exposed through `status()` or IPC. `power:false` or withdrawn panel admission unloads the reader entirely.
Bar placement and visibility do not disable the island or its power reader.

The same reader also collects what the header battery gauge and its popover
show: the charge state, UPower's time to full or empty, the laptop battery's
health (energy when full against its design capacity), and whether
power-profiles-daemon is in power-saver mode. Like the level, these stay in
memory for display only. When it loads, the reader runs `command -v` once to
find an Omarchy power program for the popover's button; it runs that program
only when the button is pressed.

## Camera

The camera mirror is opt-in: `showMirror` is off by default. Its capture
source is created only while the mirror is on, the island is open with its open
spring settled, Home is shown, and the tile is visible, and never before the
tile has finished revealing. Closing the island, changing tabs, opening an
overlay over Home, hiding the mirror with the header's camera toggle, tapping
the mirror tile to stop it, or turning `showMirror` off unloads the source and destroys its Camera object, as
does the host hiding the island's window while it is open.
The battery popover also counts as an overlay over Home: opening it unloads
the camera until the popover closes.
This matters because stopping a Camera without destroying it leaves the device
file open on this Qt backend; a Quickshell probe measured device release about
46 ms after unload.

The welcome window's Camera test step uses the same panel and source. Reaching
the step opens nothing: the camera starts only after the user presses Test
camera, and it closes when they press Stop test, move to another step, skip,
finish or close the window, and when the screen locks. Returning to the step
needs a new press. It does not stop when the window is merely out of sight on
another workspace: Qt tells QML only whether the window is shown, and a
window on a background workspace is still shown (mapped) on Wayland, so the
plugin cannot see that. The test runs only after that explicit press, and
Stop test, a step change, closing the window or a lock ends it.

The preview is local to the QML scene. The plugin does not request microphone
input, record frames, save images, or send camera content to a network service.
An unavailable device or camera error shows a static "Camera unavailable" tile.

## Privacy indicators

The indicators (`privacyIndicators`, on by default) read only local state:
the PipeWire graph's node types, links and the application names of streams
that capture a microphone, a camera or the screen, and, from the helper, the
command names (`/proc/<pid>/comm`) of this user's processes that hold a
`/dev/videoN` open, found by reading this user's own `/proc/<pid>/fd` links
after an open or close on a camera device. Nothing is recorded, logged,
stored or sent anywhere; the names are shown in the island and then dropped.
The IPC `status()` carries only how many apps capture each device, never
which; the source contract pins that.
The helper cannot read other users' processes, and it excludes the shell that
hosts the island, itself, `pipewire` and `wireplumber`. Turning the setting
off unloads the PipeWire reader and stops the camera watch.

## Bluetooth

Device peeks (`deviceEvents`) read the paired devices' names, icons,
connection state and battery level from BlueZ through Quickshell, locally.
Nothing is stored beyond the running session's baselines, and nothing is
sent anywhere. `off` unloads the reader.

## Screen recordings and screenshots

The helper reads Omarchy's recording marker (`/tmp/omarchy-screenrecord-filename`,
the path of the video being written) and, with the screenshot option on,
notices new `screenshot-*.png` files in the screenshot folder. The island
never reads the videos or images themselves beyond a small peek thumbnail.
Adding them to the shelf is opt-in (`recordingsToShelf`, `screenshotsToShelf`),
because a persisted shelf keeps their paths in
`$XDG_STATE_HOME/nookisle/shelf.json`.

## Lyrics

The Lyrics view is off by
default. Turn it on with the "Synced lyrics" row in the island's settings, or
`omarchy-shell nookisle configure '{"lyrics":true}'`; `lyrics:false`
turns it off again.

- **What is sent.** A normal lookup is one HTTPS `GET` to
  `https://lrclib.net/api/get` carrying the track title, its first artist, the
  album (when the source has one) and the length rounded to whole seconds, plus
  a `Lrclib-Client` header naming Nookisle. Like any HTTPS request it also
  reveals the machine's IP address and ordinary request headers to LRCLIB and
  its CDN. No player name, file path, artwork, account or position is sent.
  Two cases send more, up to four requests in all, to the same endpoint and
  never while the island is closed: when LRCLIB answers "busy" the same
  request is repeated once after 2 s, and when it answers "not found" the
  lookup tries the same track without the album, then with the title minus a
  remaster mark or a trailing "(feat. …)", carrying the same fields or fewer.
  A narrower answer is used only when its length is within a second of the
  track's. A redirect to any other host is refused.
- **Which sources.** Every source is eligible, browser tabs included: with
  lyrics on, a YouTube tab's title goes to LRCLIB the same way a Spotify
  track's does.
- **When.** Only while lyrics is on, the island is on screen
  and open, and it shows Home (for its one-line lyric) or the Lyrics view:
  once when either opens, and once per track change while one stays open,
  after the new track has held for 0.4 s, so skipping through tracks does not
  send each one. A track that reports no length, title or artist is never
  looked up. Closing the island, switching to the Shelf or turning the setting
  off sends nothing further, including a repeat that was waiting.
- **Bounds.** The request runs in a separate short-lived process
  (`nookisle-artwork-fetch --lyrics`) that refuses any answer over 256 KiB while
  reading it and never decompresses (`Accept-Encoding: identity`), with an 8 s
  timeout. An answer that declares more than 256 KiB, or delivers more while
  streaming, is refused before bytes beyond the cap can accumulate; Qt never
  buffers an unverified remote body in the shell process. Parsing is capped again
  at 262,144 characters, 2000 lines and 512 characters a line.
- **What is kept.** Answers live in memory only, in a cache of the last 16
  tracks (including "not found", so a missing track is not asked for again
  during the session; turning lyrics off and on forgets it). An error, such as
  a busy or unreachable LRCLIB, is never kept, so Try again asks the service
  again. Nothing is written to disk, logged, or exposed through
  `status()` or IPC. Turning lyrics off aborts a request in flight and empties
  the cache; unloading the plugin forgets it too.

Lyrics come from [LRCLIB](https://lrclib.net), a third-party, community-run
service; coverage and availability are its own. The view credits it.

## Calendar backend

Calendar access is off by default (`showCalendar:false`). The helper reads
only configured `.ics` files or vdir folders, and only while the calendar
source is active: while `showCalendar` is on and the panel is admitted (unlocked). That includes times the island is hidden
(`autoShow:false`, or over fullscreen), so the data is ready when it shows.
While the source is active the helper watches those paths for changes (a burst
of changes, such as a sync, is read once about 300 ms after it settles), and
remote sources refresh every `calendarRefresh` minutes, hidden or not.
The day window and parsed items stay in memory. Vdir reminder completion
rewrites that reminder's `.ics` file atomically; a read-only file or ICS URL
is never modified. A CalDAV completion sends a conditional PUT with its ETag.

When a CalDAV source is removed, its account's stored password is deleted.
Until the helper confirms that, the settings file keeps that account's
identifiers, its CalDAV URL and user name and nothing else, under the
internal `calendarPendingClears` key, so the deletion still happens after a
restart. They are removed as soon as the helper answers, or when the same
account is added again, and they are never shown in `status()`.

Remote ICS and CalDAV are opt-in per source; the source editor asks for that
consent, and separately for local-network access, each time one is added, and
never shows an iCal link in full. Clicking a calendar row opens only a local
source's file or folder. A Google secret iCal URL acts as
a bearer secret: anyone with it can read that calendar. It is stored in the
plugin's mode-0600 settings file with the other source definitions; it is
redacted from `status()`. CalDAV passwords are stored only by the desktop
Secret Service under `service=nookisle`, `caldav=<url>`, `user=<user>`.
The helper passes a new password to `secret-tool store` on standard input,
and uses `secret-tool lookup` when connecting; it never puts the password in
process arguments, settings, status, or logs. Only an explicit clear request
removes that Secret Service entry; reconfiguring or hand-editing the source
list never deletes a password.

A source URL never holds a user name or password (`https://user:pass@host`).
The editor refuses such a link and points to the password field, `configure`
rejects it, and a hand-edited `settings.json` that contains one loads without
that source, with a log line that gives only how many sources were ignored,
never the URL. The next save rewrites the file without it. The helper refuses
such a URL as well, so it never reaches `secret-tool`'s command line, and its
calendar code writes no logs.

The closed island shows in every screenshot and screen share, unlike the
open panel. So calendar data reaches it only with `showCalendar` and
`idleNextEvent` both on (both off by default): the idle glance then shows
when the next event starts and in its calendar's colour, and names it only
with `idleEventTitles` on as well. This adds no data flow: the glance reads
the items the calendar source already holds.

Remote requests use HTTPS, except `http://localhost` for a local test source.
The helper rejects private, loopback (localhost included), link-local, IPv6 ULA,
CGNAT (100.64.0.0/10, e.g. Tailscale), benchmark (198.18.0.0/15), multicast/reserved,
6to4, Teredo, NAT64, and IPv4-mapped private destinations unless `allowLocalNetwork:true`
is set on that source; it checks DNS answers, connects to the checked numeric
address with the original TLS hostname and `Host` header, over HTTP/1.1 only
(HTTP/2 would name the numeric address as the request's authority, and a server
that picks its site by name would answer the wrong one), keeps no cookies, and refuses
redirects to another scheme, host, or port. Requests have an 8-second deadline,
a 4 MiB response cap (and a matching read buffer), and send credentials only to
the matching origin. A remote server learns the machine's IP address and the requested
calendar URL; CalDAV additionally receives its Basic authorization header, at every
refresh while the source is active, including while the island is hidden. The helper
does not fetch while the calendar source is inactive (calendar off or locked), and closes its pooled connections whenever the sources are reconfigured.

## File shelf

The shelf holds links to local files, web links and dropped text, added by
Paste or a drag. For files it keeps the link, never a copy of the contents.
Dropped text of up to 64 KiB is held in the shelf itself, never written to a
temporary file. By default everything lives only in memory for the life of
one plugin load (`Service.shelfEntries`, `shelfLimit` items, 64 by default),
and is cleared on dispose or retirement.

**Opt-in persistence.** With `shelfPersist` on (off by default), the shelf is
also saved to `$XDG_STATE_HOME/nookisle/shelf.json`
(`~/.local/state/nookisle/shelf.json` by default): the directory is mode
0700, the file 0600, and every write is atomic. The file holds each item's
kind, file URI, web link or text, display name and time added; it never holds
file contents or temporary items. On load, each stored entry is checked on its
own and invalid entries are dropped. Turning `shelfPersist` off deletes the
file, and nothing else does: an instance that is being reloaded, retired or
disposed, or that does not own the plugin's registration, never deletes it,
even when a save it started finishes late.

The state writer creates a mode-0600 temporary file and renames it into place,
so the first save is private before it becomes `shelf.json`.

**Thumbnails and icons.** For a shelved PNG or JPEG the island first looks up
the freedesktop thumbnail cache (`~/.cache/thumbnails/normal` and `large`,
named by the MD5 of the file URI). On a miss, the helper reads the file and
decodes it only in its resource-limited decoder child (no network, capped
input, memory and CPU), then writes a 128 px entry to
`~/.cache/thumbnails/normal` (directory 0700, file 0600) carrying the file's
URI and modification time, as the specification requires. Other apps that use
the shared cache can see that entry, exactly as with any file manager's
thumbnails. Every other file shows its theme icon, found by
`xdg-mime query filetype` on the local path.

The helper accepts a cached thumbnail only when its embedded URI and
modification time match the current file; a stale entry is regenerated.
Because other applications write the same cache, an existing entry is parsed
only in the decoder child, which re-encodes it with nothing but those two
keys; the island only ever shows that re-encoded copy, never another
application's file. JPEG
thumbnail orientation follows its EXIF tag without retaining the tag in the
output.

**File actions and sharing.** Actions run only when the user picks them: Open,
Open With, Show in Files, Copy, Copy Path, Compress, Rename, Convert Image,
Create PDF, Remove Background (only if `rembg` is installed) and Remove. Each
runs a local tool with an argument list, never through a shell. Non-interactive
tools are stopped after 30 seconds, and their output is capped. Zips,
conversions and PDFs are written to `$XDG_RUNTIME_DIR/nookisle/shelf/`
(mode 0700). They are deleted when their item is removed or the plugin unloads,
and anything left there is pruned when the island next starts. Generated
outputs that fail or cannot be added because the shelf is full are deleted
immediately. A rename creates no output, so a failed rename deletes nothing. Show in Files passes the file URI to the file manager over the
session bus. Sharing sends the chosen files only to the provider the user
picked (`shareProvider`):
LocalSend's own window, KDE Connect (the first reachable paired device) or, as a last resort, the containing folder.
Nookisle itself sends nothing over the network.

The clipboard is
touched only on an explicit Paste, Copy or Copy Path press. Paste (Ctrl+V in
the shelf) reads the current clipboard's `text/uri-list` entries and keeps
local `file://` and web links. Only when the clipboard offers no
`text/uri-list` does it read the clipboard's plain text instead. A lone web
URL becomes a link, a local file URI becomes a file, and other text becomes a
text item of at most 64 KiB of UTF-8. Each read is capped at 131,072
JavaScript string code units.
Pasted text is stored like any shelf item: in memory, and in `shelf.json`
only while `shelfPersist` is on. Copy sends shelved URIs, links or text back over the clipboard tool's
standard input, never as a
command-line argument, so the shelved path never lingers readable in
`/proc/<pid>/cmdline` for as long as the clipboard tool keeps serving the
selection. Copy also refuses any URI that is not already on the shelf. No
other clipboard type is read, and nothing is read without a press. A missing
clipboard tool, a busy
clipboard request or an empty clipboard states that in the shelf's notice row
rather than failing silently. A clipboard request that hangs is killed after
a bounded timeout rather than disabling Paste/Copy forever.

## Browser bridge and diagnostics

The optional extension has access only to the Spotify web player, YouTube and
YouTube Music sites named by its manifest. It has no history or all-sites
permission. The native host accepts the configured extension origin and speaks
to a private same-user socket. Reconnect and document/media lifetime changes
invalidate old targets. There is no browser-tab lookup by title or artwork.

The status endpoint reports counts, booleans, setting values and diagnostic
codes, not song titles, page URLs or a tab history. The media-key verbs return only `ok`,
`busy` or `unavailable`. They do give any same-user process a way to play,
pause or skip an extension-controlled browser document, which no other session
mechanism can reach; see [architecture documentation](https://github.com/bavanchun/nookisle/blob/v1.0.4/docs/architecture.md#selection-and-view-subscription)
for why that is accepted. Local debug/test artifacts should be
reviewed before sharing; system process inventories and screenshots can still
include personal information outside the plugin's own diagnostics.

## Settings file

Typed settings are stored in `$XDG_CONFIG_HOME/nookisle/settings.json`
(or `~/.config/nookisle/settings.json`), in a directory with mode 0700 and
a file with mode 0600. Besides preferences such as hover timings, it can hold
calendar source paths, CalDAV account names, and remote URLs when you add
those sources. It never stores a CalDAV password, title, artist or listening
history. `status()` omits the calendar source definitions while reporting
other setting values.
If the file cannot be parsed, a warning names no stored values and defaults
are used. Before a later write, the original is copied to `settings.json.bad`
in the same private directory; that backup can contain the same source paths,
account names and URLs as the original and is restricted to mode 0600.
