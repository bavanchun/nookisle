# Architecture and decisions

Nookisle controls playback already owned by another application. The
product targets the Spotify desktop app and Spotify, YouTube, and YouTube Music
in Google Chrome, primarily desktop and web-app windows. Browser MPRIS endpoint
identity cannot prove a tab's identity. The optional site-restricted extension
provides a separate document-scoped transport; live site support must still be
verified against the [support matrix](support-matrix.md).

## Ownership boundaries

The optional calendar backend is compiled into the native helper by
`NOOKISLE_CALENDAR` (on by default). [CalendarService](../helper/calendar-service.cpp)
handles additive calendar protocol requests. [CalendarSources](../helper/calendar-sources.cpp)
owns local watchers, remote requests, source errors, pagination and completion
writes; [CalendarParser](../helper/calendar-parser.cpp) owns the bounded ICS
subset and recurrence expansion. Reading local sources and parsing every
source's ICS run on Qt's thread pool, never on the helper's event loop, so IPC
and media control stay responsive while a large calendar loads; only the
newest load of a source is applied. A load belongs to the configuration that
started it: a reconfiguration stops every later step of an older load (network
callbacks, parse results and CalDAV's event-then-reminder continuation), so a
source that keeps its ID never receives the old load's data.
[CalendarSource.qml](../components/CalendarSource.qml)
is the QML request owner. The Service loads it while `showCalendar`,
island mode and UI admission hold, retaining configured sources while the
island hides. The Home calendar
panel consumes its items, and the settings window hosts the source editor.

The helper serves the local-zone window from seven days before today through
fourteen days after today. It expands that window once per source change and
serves pages as slices of it; each page stays below the 64 KiB frame limit
and carries an offset for the next page. Recurrence expansion has a
per-source step budget. Local file and remote ICS sources are
read-only; vdir completion uses `QSaveFile`, and CalDAV uses ETag-guarded PUT.
Remote ICS and CalDAV are polled no faster than every five minutes while the
source is active. See [privacy](privacy.md#calendar-backend) for stored source
locations, credentials and network restrictions, and [protocol](protocol.md#calendar)
for the helper messages.

Display backlight changes come from the helper's own watch on udev's netlink
socket ([protocol](protocol.md#backlight-events)), not from a `udevadm`
child: the socket lives as long as the helper, and a helper restart
re-establishes it with the connection.

The camera mirror on Home and the welcome window's camera test both load
[CameraSource.qml](../components/CameraSource.qml), the only file that imports
QtMultimedia, through a Loader that exists only while its gate holds. Qt keeps
the device open while an inactive Camera object still exists, so every gate
destroys the object rather than deactivating it
([privacy](privacy.md#camera)). The camera asks for the smallest capture
format at least twice the tile's size in both directions, the largest one
when none is that big ([CaptureFormat.js](../qml/CaptureFormat.js)), and sets
it before it starts. The Service owns the settings and welcome
windows and opens them only while the panel is allowed.

[manifest.json](../manifest.json) declares the host entry points.
[Service.qml](../Service.qml) owns the coordinator and its child helper;
[Panel.qml](../Panel.qml) owns presentation. Discovery and playback authority
belong in [MprisRegistry](../helper/mpris-registry.cpp), keeping the panel free
of a second player registry or service lifecycle.

Metadata is untrusted presentation, never a command address. A title, artwork,
friendly application name, or track ID cannot authorize routing. Commands must
retain the captured D-Bus owner lifetime so a replacement player cannot receive
a stale click. The routing and replacement oracle live in
[registry tests](../tests/helper/mpris-registry-test.cpp). An asynchronous method
reply means the call completed; subsequent source state determines whether
playback changed. Retrying a toggle after a timeout could reverse the user's
intent, so commands are not automatically replayed.

## Process and transport

The native helper was chosen to make owner-bound D-Bus calls and asynchronous
results explicit. It uses Qt Core, DBus and Network, never Qt Gui: every image
operation (artwork and thumbnails) runs in the decoder child, and the helper
reads only a PNG's header. It creates no second desktop shell. A short-lived decoder child
has a separate wall/resource limit and links only Qt Core and Gui
([image-decode.cpp](../helper/image-decode.cpp)), never the network or D-Bus
stacks. Remote artwork is downloaded by another short-lived child,
`nookisle-artwork-fetch`, so the TLS stack and certificate store never stay
resident in the helper. The optional Chrome-owned native host uses
its own stdio and a private authenticated socket, not the service's stdin.
[helper/main.cpp](../helper/main.cpp) owns the process lease and startup;
[lifecycle tests](../tests/helper/lifecycle-test.cpp) exercise contention and
handoff. The lease protects against simultaneous active helpers, but cannot
repair the host's service registration or guarantee availability. Closed stdin
and SIGTERM (the Service's stop) both end the helper cleanly, removing its
socket and its artwork cache, `nookisle-art-<session>-XXXXXX` in the
runtime directory. A helper killed outright cannot clean up, so each new lease
holder first removes its own session's leftover caches: holding that
session's lease proves no live helper owns them. It never removes another
session's cache or follows a link. Older builds named their cache
`nookisle-art-XXXXXX`, with no session, and such a helper may still run
under another session, so those caches stay until the runtime directory is
cleared at logout.

IPC is private newline-delimited JSON over child-process stdio. Both producers
escape Unicode as ASCII JSON because Quickshell converts raw output chunks to
strings before JavaScript sees them; a byte split inside UTF-8 must not corrupt
metadata. This preserves Unicode content while making wire-byte accounting
predictable. [ipc-protocol.h](../helper/ipc-protocol.h) owns helper budgets,
[ipc-protocol.cpp](../helper/ipc-protocol.cpp) owns framing and snapshot
production, and [Protocol.js](../qml/Protocol.js) owns QML reception.

Presentation may be reduced to fit the transport budget; routing identity must
remain intact. Atomic snapshot publication prevents the panel from mixing
different source generations. [Protocol tests](../tests/helper/ipc-protocol-test.cpp)
provide the helper-side executable checks; serialized limits are not a measured
heap or process-memory bound.

The Service also owns the optional spectrum capture,
`libexec/nookisle-spectrum` ([spectrum-main.cpp](../helper/spectrum-main.cpp)).
It captures the default sink's monitor through PipeWire and prints one line of
12 space-separated integers `0..99` per frame, and nothing while the signal is
silent. The binary allows up to 30 frames a second; the Service starts it with
`--fps 15` (`spectrumFps`), because each line costs the shell one repaint and
at 30 or 20 lines that exceeded the collapsed-playing CPU budget. The Service starts it only while
`visualizer`, island mode, `islandShowing` (written by `Panel.qml`: the island
itself, not the legacy panel, is on screen), UI admission and a `Playing`
selected source all hold, and stops it as soon as any of them drops. A
`SplitParser` hands each line to `onSpectrumLine`, which drops anything but
exactly 12 integers in range and assigns `spectrumLevels` only while
collapsed, skipping a line that would move no bar by a whole pixel
(`Spectrum.shouldDraw` compares against the line on show using the closed
notch's current rendered bar span). An unexpected exit, including exit code 1 when PipeWire drops the
stream (a daemon restart or a removed node), retries after 1, 2 and 4 s (3 per
60 s); exit code 2 (the stream failed), a missing binary, or exhausted retries set
`spectrumState` to `unavailable` until the next start condition, and the pill
falls back to its static play-state glyph.

## Host and session constraints

Host properties arrive after QML construction. The coordinator must establish
current registration and lock state before admitting UI commands. Unresolved
lock state on a reachable provider must fail closed. [Service.qml](../Service.qml) owns those
guards and the helper admission handshake. A lock barrier takes effect when
the helper observes it; a method already dispatched remotely may still finish.
Stale UI completion must not trigger a compensating toggle.

The lock contract accepts the sole enabled `omarchy.lock` service or an enabled
manifest explicitly declaring `omarchy.clonedFrom: "omarchy.lock"`. On a
reachable provider, an unresolved stranded lock or missing readiness properties
fail closed. When no single provider is reachable - absent, ambiguous, or scoped
away from third-party plugins, as current Omarchy hosts do - the panel admits
instead of hiding for the life of the session, relying on ext-session-lock to
keep every other surface off screen while locked. The plugin never changes the
user's locker.

The sleep timer is the one actuator that fires without a surface, so the
compositor argument does not cover it. It is still allowed on a host with no
reachable provider, because the only command it can ever send is `Pause`, and
pausing a locked session is harmless. Where a provider is reachable, locking
closes admission and cancels it. The Service exposes `sleepLockVerified` so the
UI states which case applies rather than promising a cancellation it cannot
observe. Details of arming and expiry are in the
[interface specification](interface.md#sleep-timer).
The production resolver and pin/Auto reducer live in
[SourceState.js](../qml/SourceState.js), with
[contract tests](../tests/qml/tst-source-state.qml). These tests do not substitute
for a live lock/unlock check.

## Selection and view subscription

Manual selection pins an exact endpoint lifetime, including while paused or
unavailable. A replacement bearing the same name is not rebound. Auto retains
a playing endpoint, otherwise prefers newly activated playback, then retains
an available paused endpoint. Selecting a source never controls playback.

UI gestures capture endpoint, track, admission epoch, connection, and selection
revision. Changed selection or lifecycle rejects unsent intent; seek additionally
checks the captured track. Pending results are correlated back to that intent.
The helper remains the final capability and unique-owner authority.

Visible, admitted, playing views subscribe to monotonic progress samples:
expanded views at 250ms, and the collapsed island at 1000ms for its progress
hairline (a 240px line over a whole track moves about a pixel a second). The
collapsed legacy panel still sends no subscription. The UI renders samples
without a second playback clock.
Subscribe/refresh acknowledgements release bounded IPC write credits. Controls
require an acknowledged gate; error presentation only requires safe unlocked
panel ownership, so helper failure can expose Retry without admitting commands.

User settings are stored under the Nookisle plugin entry in the host
config: in its `settings` object on hosts that offer `shellConfigMutator`, and
as flat keys written through `updateEntryInline` on hosts that scope the
registry away from third-party plugins, as Omarchy does since 2026-09. The
scoped host refreshes the plugin's public bar config copy only when the plugin
set changes, so the Service layers what it just wrote over that copy until a
fresh one arrives. Typed settings live in the plugin's own
`settings.json`, validated against [Settings.js](../qml/Settings.js). The
Service logs an invalid document and preserves its bytes as `settings.json.bad`
before any replacement write; a failed backup refuses that write.
`nookisle` IPC target exposes redacted `status`, `retry`, `configure(json)`
for every schema key, `settings` and `onboarding` to open those windows, and
`keyboardBacklightChanged` and the read-only `hudReadout(kind, device)` for the
media-key bindings. It never returns titles,
URLs, or listening history. Status adds `island`, `hud`, `visualizer`, `peek`,
`tint`, `power`, `lyrics`, `shelfCount`, `brightnessHud`, `spectrum` (`off`,
`running` or `unavailable`) and the resolved typed `settings` (without calendar
source definitions); the count is the only shelf fact it reports, and
[source-contract.py](../tests/source-contract.py) pins the key set and the IPC
surface.

The Service owns the shelf: typed items (files, web links, text) in
`shelfEntries`, with identity keys, insertion order and the `shelfLimit` cap
(64 by default) computed by [Shelf.js](../qml/Shelf.js); `shelfItems` is the
derived list of file URIs that the Shelf tab's item count and the clipboard
guard use. Overflow is
refused rather than evicting what the user already shelved. It is written to
disk only when the opt-in `shelfPersist` setting is on
([privacy](privacy.md#file-shelf)). Every process a shelf action starts goes
through [ShelfActions.qml](../components/ShelfActions.qml), whose builders
return argument arrays and whose runner enforces the timeout and output cap.
Thumbnails come from the helper's `thumbnail` request
([protocol](protocol.md#shelf-thumbnails)). The list survives a
helper restart, because `stopOwned()` also runs on reconnect, and is cleared on
disposal and retirement, so a reload or a superseding instance never inherits
it. `islandPointerActive` is a plain flag the panel writes and the bar widget
reads; it carries no user data.

It also exposes transport verbs for media keys and local callers: `playPause`,
`next`, `previous`, `shuffle`, `repeat`, and `seek(seconds)`. Only `seek` takes
a bounded numeric argument, so no action string crosses the
boundary. They drive the selected source and return only `ok` (dispatched, not
proof that playback changed), `busy` or `unavailable`. Their results never write
the panel's error line, which describes the user's own last command. No window,
focus or presence verb, `Raise` included, is exposed over IPC: a focus steal
mid-typing would redirect keystrokes into a page the caller chose.

These verbs extend same-user local callers a new capability - actuating
extension-transport browser documents, which have no D-Bus presence and so no
`playerctl` equivalent - that no other session mechanism reaches. The risk is
accepted deliberately: a caller able to reach this socket already runs code as
the user, and skipping a track is not a meaningful escalation from there. They
follow ordinary admission, so a visible lock refuses them; where the host hides
the lock provider they stay available while locked, matching the desktop's own
media-key bindings, which Omarchy declares with `locked = true`.

Pending-load ownership belongs to the host: plugin-side refusal and a helper
lease cannot restore availability after the host replaces a fresh registration
with a stale one. The [legacy lifecycle harness](../tests/qml/lifecycle-harness.qml)
preserves that regression, while the
[patched-host runner](../tests/qml/run-patched-host-lifecycle.sh) verifies the
host's production loader against the actual Service and helper. Deterministic
service-layer evidence is a prerequisite for session acceptance, not proof of
a successful full desktop reload.

Host repair is managed separately as an explicitly approved Omarchy package
change. Nookisle's integration remains within plugin-owned files; its
installation must not patch vendor shell code. That separate repair does not
establish compatibility with other host versions or lock services. Package
installation and live acceptance are separate from isolated host-contract tests.

The legacy panel uses a tinted fallback and the island is solid black; neither
needs backdrop blur. The plugin never enables compositor blur by itself; only
the installer's opt-in bindings block does, and it says so before editing
([install](install.md#one-on-screen-display-for-media-keys)). Real compositor placement,
input regions, focus, output changes, and performance need session evidence
before release. No RAM, CPU, frame-time, or universal Linux compatibility claim
follows from compiling or packaging the project.

Only the current mode's tree exists. The legacy panel (`IslandContent`) and the
island surface (`IslandSurface`, with its Home, camera and shelf) each sit behind
a Loader in Panel.qml that is active only in its own mode, and a live switch
unloads the other tree, releasing its camera and focus. In legacy mode Panel
reads `root.surface`, an inert stand-in (collapsed, not interactive, the same
resolved settings), and extra-screen islands exist only in island mode. Inside the island,
Home (player, calendar and camera tile) is built the first time the island is
hovered, opened or summoned and then kept, so a closed island that was never
opened holds none of it; the hover dwell covers building it before the open.

In island mode the window moves to `WlrLayer.Overlay` (`exclusionMode:
Ignore`, `margins.top: 0`), instead of the legacy panel's `WlrLayer.Top`. The
host bar itself renders on `WlrLayer.Top` and is recreated on screen changes,
so stacking within that one layer depends on map order; `Overlay` stacks
above it deterministically regardless of map order, which a live
native probe verified. The window keeps only its top anchor, so the layer-shell
compositor centres it horizontally on the output; there is no per-screen slot
registry and no `margins.left` arithmetic for island mode. This placement is
correct only when [BarWidget.qml](../BarWidget.qml)'s spacer is the bar's own
centre anchor on a full-width top bar (`centerAnchor:
"io.github.bavanchun.nookisle"`), because that is what makes the bar's centre equal the
screen's centre; a differently configured bar keeps the pill screen-centred
while the spacer reserves the wrong place, and `island:false` is the stated
remedy. [Panel.qml](../Panel.qml) picks the island's screen with
[Displays.js](../qml/Displays.js) for the `displayMode` setting. In `follow`,
the default, that is one screen at a time - `Hyprland.focusedMonitor`,
falling back to the first screen; in `fixed`, `preferredDisplay` while it is
connected, else as `follow`. It moves only while the island is collapsed,
deferring a focus or output change until the next collapse so the surface
never jumps under the pointer mid-interaction. This differs from the legacy
panel's screen binding, which always tracks the current target and forces a
collapse when it changes.

In `all`, Panel's own window is the primary: it stays on `preferredDisplay`
(or the first screen) whatever has focus, takes the keyboard summon, and
publishes the island's state to the Service. A `Variants` of
[IslandWindow.qml](../components/IslandWindow.qml) adds one window for each
other screen, following screens as they come and go. Each extra window has
its own surface, so its busy guard, its HUD input growth and its drag catch
zone stay per window, and it reads the fullscreen policy from its own
monitor. It never takes the keyboard. The models stay single, shared by every
window: the level readout, the peeks, the battery, the lyrics and the one
helper behind the Service. Two things that would repeat per screen are
narrowed to one: only the visible island under the pointer draws the live
spectrum (with the pointer on none, the primary, or the first visible island
while the primary is hidden; the others show the still glyph), its lines
pausing only while that island itself is open (`Service.spectrumPaused`),
and only the island opened last may run the camera; when it closes, the camera
goes back to the island opened before it that is still open. The Service's view state
(visible, and the position rate), the lyrics gate and the bar's centre-peek
suppression read every window: any visible island, any open one, any Home or
Lyrics view, and the island the pointer is on. The shared readout and peeks
are suppressed only when no visible window can show them, and a held HUD bar
belongs to the island it is on (`HudModel.heldBy`), so a drag on one screen
never latches another screen's fullscreen state or defers its open and close;
a HUD view destroyed with its screen ends its own hold. Every owner is chosen
from the visible windows (`Panel.islandStates`) and re-evaluated as windows
show, hide or go with their screen.
The rules are pure functions in [Displays.js](../qml/Displays.js); with one
island each reduces to that island's own.

## Artwork and browser integration

One artwork loader serves native and extension selections. Selection, track,
URL generation, admission and policy changes cancel stale jobs. QML sees only
sanitized private runtime paths; disabling remote artwork clears both registries
and the presentation boundary, and only a native player's local `file:` cover is
then selected again, read without the network. The decoder is a disposable bounded child,
not image parsing on the shell's UI thread. See [privacy](privacy.md).

The browser transport uses an extension-owned content port per top-level
document, a Chrome-owned native messaging process, and the core's authenticated
same-user socket. Endpoint media lifetime and track lifetime are distinct:
changing songs preserves a pinned document but invalidates an old seek. Browser
state updates and sampled progress are separate; hidden position-only DOM
changes do not publish a playback stream, but a seek republishes the endpoint
so a paused seek shows at once. See the
[bridge contract](../bridge/README.md) and [controller protocol](protocol.md).
The site adapter reads a like control's accessible state before advertising
`CanFavorite`; its click goes through the same document-bound command route.

Synced lyrics are fetched in QML, not by the helper.
[LyricsSource.qml](../components/LyricsSource.qml) is the only network client
in QML (the helper owns artwork and calendar requests): one `XMLHttpRequest`
at a time to LRCLIB's `/api/get`, gated by the opt-in `lyrics` setting and an
open island showing Home or the Lyrics view, with an 8 s timeout,
a 256 KiB cap and an in-memory LRU of 16. `Panel.qml` holds the one instance,
so the cache outlives view changes, and feeds it the selected endpoint and the
expanded view's 250 ms position; there is no second clock.
[Lyrics.js](../qml/Lyrics.js) is the pure part (LRC parsing, line selection,
the request URL, the cache and the reading of an answer), and
[IslandLyrics.qml](../components/IslandLyrics.qml) draws it. Routing lyrics
through the helper would have reused the artwork loader's bounds, but it would
add protocol frames, C++ state and tests for plain text; the helper keeps its
narrow MPRIS and artwork role. `tests/source-contract.py` pins that no other
shipped file uses `XMLHttpRequest` or names the LRCLIB URL. See
[privacy](privacy.md#lyrics).

See the [README](../README.md) for build, test, and local packaging instructions.
