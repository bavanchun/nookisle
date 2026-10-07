# Island gestures, keys and verification

This reference continues the [interface](interface.md) with input behavior and verification.

## Gestures and keys

### Media-key readout ownership

The opt-in media-key helper asks `hudReadout <kind> <device>` before acting.
Only a prompt `ok` gives the readout to the island. An `unavailable` reply,
failure, or a query past its 90 ms deadline gives it to Omarchy's command and
OSD. The outer timeout kills a query that ignores TERM after another 40 ms.
The query is read-only; a reply that arrives after the deadline cannot claim
the readout.

Before changing a device, the helper atomically replaces
`$XDG_RUNTIME_DIR/nookisle/key-readout.<kind>` with a private, single-line
record: `<kind> <pid>-<microsecond timestamp> <island|fallback> <expiry in Unix
milliseconds>`. The token distinguishes successive key events. Panel reads
the record synchronously when a volume, microphone, display, or keyboard
sample reaches the HUD. A current `fallback` record suppresses the island
readout while Omarchy owns the OSD; a current `island` record allows it. The
record expires after two seconds, so an unrelated later device change is not
silenced. An unexpired fallback record makes subsequent keys of the same kind
skip the query, take Omarchy's path, and extend that expiry. The helper checks
the record both before and after a query under a short file lock, so an
in-flight prompt reply cannot replace a fallback decision during a key-repeat
burst. The write precedes the fallback action, which prevents a late source
sample from racing ahead of its ownership decision. An island wheel step or
HUD bar drag reserves its own next source sample before writing the device;
that sample can still show the island readout during a media-key fallback
window. Brightness and keyboard drags keep only one pending reservation per
kind because their queued writes can coalesce. An unrelated external change
of the same kind during that window is
still suppressed. While a HUD bar is held, another kind's key is assigned to
Omarchy because the held bar keeps its own kind visible. With no
`XDG_RUNTIME_DIR`, the helper skips the island query
and takes Omarchy's path; neither process uses `/tmp` for ownership records. See
[installation](install.md#one-on-screen-display-for-media-keys) for the
opt-in bindings and action routing.

[IslandSurface.qml](../components/IslandSurface.qml) handles the pointer
gestures and the summoned keys; the pure key map and the wheel volume
arithmetic live in [IslandKeys.js](../qml/IslandKeys.js). Every playback action
goes through a freshly captured intent, needs the same capability as the
matching button (`CanControl` plus `CanPlay`/`CanPause`, `CanGoNext`,
`CanGoPrevious`, `CanSetPosition` with a known length, or `CanSetVolume`), and is not
sent while another command is pending. Nookisle always uses this island interaction surface.

Local IPC callers can use `shuffle()` to toggle the selected source,
`repeat()` to cycle off → playlist → track → off, and `seek(seconds)` to move
by a signed offset of at most one hour. They return `ok` when dispatched,
`busy` while a command is pending, or `unavailable` when the source lacks the
capability or the offset is invalid. The selected source's next state is read
from MPRIS or the browser extension; dispatch does not pre-change the display.

**Wheel on the collapsed pill** (also while a peek shows; the peek body beyond
the pill takes no input):

- The vertical wheel changes the system output volume by 2% per 120 units (one
  mouse notch; touchpad fractions carry over). The write goes through
  [VolumeSource.qml](../components/VolumeSource.qml)'s `adjust()`, and the
  resulting sample shows the level readout, as a volume key would. Stepping up
  unmutes and stops at 100%; a sink already above 100% (set elsewhere) is left
  there until the wheel goes down. `VolumeSource` loads only with `hud` on, so
  with `hud:false` the wheel does nothing: the plugin then neither reads nor
  shows levels.
- A horizontal swipe skips once per gesture: once the horizontal deltas of one
  gesture add up to 240 units, a leftward swipe (negative x) sends `Next` and a
  rightward one `Previous`. The gesture ends after 300 ms without a wheel event.
  The pill (or the peek) nudges 6px the way the track went and springs back,
  a finite 400 ms motion that reduced motion skips. `swipeSign` is the one
  constant that flips the direction.
- Natural scrolling does not flip either gesture: an event marked `inverted`
  has its deltas turned back, as Qt's own sliders do, so the same finger or
  wheel motion raises the volume or picks the same skip on any touchpad
  setting.
- Each event counts once, on whichever axis dominates it. Scrolling on the pill
  cancels a pending hover dwell, so a volume or skip gesture never opens the
  card underneath. The expanded card ignores the wheel; its lists and sliders
  scroll as usual.

**Double-click on the cover** (the 90px artwork in Home) toggles play/pause,
and the cover and its glow dip and spring back. While playing, a single click
raises the source app when it allows that, after the double-click interval;
while paused, a single click resumes. A tap on
the closed notch still expands it at once.

**Summoned keys.** A keyboard summon focuses the surface root, and the
header's tabs wear a focus ring while it holds focus. The shortcut keys act only
while the island is expanded, and never with Ctrl, Alt or Meta held:

| Key | Action |
|---|---|
| Space | Play/pause (once per press, not at the key repeat rate) |
| Left / Right | Seek 5 s back / forward, within the track |
| Up / Down | Player volume 5% up / down; the volume slider moves with it |
| N / P | Next / previous track (once per press) |
| Tab / Shift+Tab | Next / previous tab, only while the root itself holds focus; Lyrics steps as Home |
| Return / Enter | Step into the view, only while the root itself holds focus |
| Escape | The view's ladder first (source or settings), then Lyrics back to Home, then collapse |

Return focuses the play button (or the source button when no source is shown)
in Home, the first control in Shelf, and Try again (when it shows) or
the view itself in Lyrics. From there Tab keeps its normal
traversal through the view's controls; Shelf's Share tile and item tiles take
focus, Return activates Share when a picker is available, and focused tiles
select their item before Return opens it. Inside Shelf, Ctrl+V shelves the
local files and http(s) links on the clipboard's `text/uri-list`, or, when
there is none, its plain text as a drop would ([Shelf](features.md#shelf)). The tabs are also buttons in the header.
A focused control keeps the keys it takes (a button keeps Space, a
slider its arrows, the source list Tab and the arrows), and the island takes
the rest: N still skips while a button holds focus. The summoned island asks
for exclusive keyboard focus: on Hyprland 0.56 an on-demand request did not
move focus to the already-mapped layer when a summon flipped its
interactivity, so the keys reached the window underneath. With exclusive
focus, Space, N, P, Tab and Escape were verified live.

## Verification

[The panel load test](../tests/qml/run-panel-load.sh) installs the package,
copies the host's `Commons` module beside it, and loads the complete
`Panel.qml` under Quickshell on the offscreen platform, first without a host
and then as the island over a top bar with a stub coordinator. Any QML error
or warning fails it, so a merge can never ship a panel that does not load.
It also checks that `status()`'s activity follows an island built while a
recording already runs (privacy indicators off), including a hidden or non-top
bar without a fallback UI.
Its one substitution is the layer-shell window: `PanelWindow` needs a Wayland
backend the offscreen platform lacks, so the package's layer windows become
[TestPanelWindow](../tests/qml/panel-load/TestPanelWindow.qml), a plain
window with the same members, and their layer-shell bindings become plain
properties; every other file runs as installed.

[Control tests](../tests/qml/tst-controls.qml) exercise pointer/keyboard
single-commit gestures, source/track/lock cancellation, volume limits, and
disabled/pending actions. [Source-state tests](../tests/qml/tst-source-state.qml)
exercise truthful platform labels; [tint tests](../tests/qml/tst-tint.qml) cover
artwork rendering, crossfades and rapid skips. Home and settings suites cover
their own states and controls.
[Island surface tests](../tests/qml/tst-island-surface.qml) exercise the hover
dwell/leave-grace state machine, tap and drag-in expansion, the explicit-open
and mid-gesture collapse guards, the notch corners, the HUD row, Escape on
the Shelf view, the header tabs and capsule, the pull gestures, the summon
auto-close and the close guard, and the Lyrics sub-view, fallback, lines,
glide and states. [Input tests](../tests/qml/tst-island-input.qml) exercise the
wheel volume steps, the swipe, the art double-click, the summoned keys, the
Tab rule inside a real surface, and the Escape ladder after a summon.
The Home, header, closed-notch, HUD, battery, calendar, shelf, camera,
settings-window and onboarding suites are registered with the others in
[tests/CMakeLists.txt](../tests/CMakeLists.txt).
[Lyrics tests](../tests/qml/tst-lyrics.qml) exercise LRC parsing, line
selection, the request URL and cache, and the lookup's states, cache, timeout,
size cap and opt-in gates against a local fixture server
([lyrics-fixture-server.py](../tests/qml/lyrics-fixture-server.py), started
and stopped by [run-lyrics.sh](../tests/qml/run-lyrics.sh)); they never reach
the real network. The [lifecycle harness](../tests/qml/lifecycle-harness.qml) drives the real Service
and helper through arming, re-arming, early wake, busy re-fire, source change,
expiry, lock cancellation and supersession by assigning `sleepDeadline` directly,
since the shortest real deadline is far outside the test's time budget. They
render actual production components with explicitly labeled fixture metadata.
PNG evidence is generated under `build/ui-preview/` by the CTest suite.

These offscreen checks verify component behavior and rendering, not live
Wayland hit regions, keyboard focus, output hotplug, fullscreen behavior, or
performance. Quickshell cannot create `PanelWindow` under the offscreen Qt
platform because no native window backend is loaded. Those checks require
separate native-session acceptance.
