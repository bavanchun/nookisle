# Support and evidence

The intended platforms are Spotify and YouTube only. Chrome is the target
browser. The YouTube desktop launcher is a Chrome web-app window, not proof of
a separate native endpoint. Other MPRIS players may appear as unclassified
endpoints; this is not a tested-support promise for those applications.

## Transport boundaries

| Source | Identity and scope | Controls | Current evidence |
|---|---|---|---|
| Spotify desktop | MPRIS application identity, unique-owner lifetime | Relative seek when `CanSeek`; no favorite, shuffle, or loop controls | Spotify 1.2.96.518-3 acknowledges `Shuffle` and `LoopStatus` writes but leaves values unchanged and emits no `PropertiesChanged` signal (live probe); isolated bus tests verify routing and the capability policy |
| Chrome MPRIS | Browser endpoint, not a fixed tab | Same MPRIS capability rules; no favorite | Real endpoint discovered; exact-tab claims prohibited for this transport |
| YouTube extension | Specific top-level Chrome document/media lifetime | Media controls and relative seek when available; no favorite, shuffle, or loop | Adapter/bridge fixtures; live site remains unverified |
| YouTube Music extension | Specific top-level Chrome document/media lifetime | Media controls and relative seek; favorite only when an enabled like button has readable state; no shuffle or loop | Adapter/bridge fixtures; live site remains unverified |
| Spotify web extension | Specific top-level Chrome document/media lifetime | Favorite only when an enabled like button has readable state; seek needs a usable media element; no shuffle or loop | Adapter/bridge fixtures; protected-player behavior requires real-site verification |

No command falls back to another transport. A pinned source disappearing stays
unavailable, including across native-owner replacement and browser reconnect.
Selecting another source never transfers or pauses playback implicitly.

## Reference installation

Read-only inventory on 2026-09-05 found Omarchy 4.0.2-1.1 (local host lifecycle
repair), Quickshell 0.3.1-1, Hyprland 0.56.2-1, Qt Base 6.11.2-2, Spotify
1:1.2.96.518-2, and Google Chrome 152.0.7977.82-1. Spotify and Chrome each exposed
an MPRIS endpoint and both reported Paused at inventory time. This proves
discovery and transport presence, not successful playback, seeking or volume
control through the finished island.

The active locker is a declared clone of `omarchy.lock`. The resolver accepts
only a sole enabled provider with the required unlocked/stranded-lock state;
missing readiness properties on that provider fail closed. With no single
reachable provider - including hosts that hide it from third-party plugins -
the island admits and relies on the session lock to cover it. Isolated tests exercise clone
selection, lock-admission barriers and host reload ownership. Live screen-lock,
hotplug, compositor input-mask and frame performance remain separate checks.

## Interpretation

`Verified` must name an actual test and version. `Unsupported` is a known
capability gap. `Degraded` means a working fallback with a disclosed boundary,
such as tint without backdrop blur or browser scope without the extension.
`Not tested` is not a pass. Automated fixtures validate invariants without
pretending to be Spotify's protected player or a current YouTube release.

The built-in global media keys still use Omarchy's native media router. Music
Island's captured-target guarantee applies to its own controls, not unrelated
keyboard bindings. No universal zero-error or all-Linux-version guarantee is
made.

## Raise

Per-source support for the `Raise` action is **not verified**. The helper derives
`CanRaise` from root-property presence, so a source that does not advertise it
disables the control with a stated reason and nothing misbehaves. Whether Spotify
for Linux advertises and honours it, and whether the extension worker's tab
activation is granted by the compositor, both require a live session to
establish. The extension declares no additional permission for it:
`chrome.tabs.update({active})` and `chrome.windows.update({focused})` are not
gated by the `tabs` permission, which covers reading `url`, `title` and
`favIconUrl`.

## Dynamic island

The island was checked live on one output (eDP-1, 1920x1200) with Hyprland
0.56.2, Quickshell 0.3.1 and Qt 6.11.2. The checks and their evidence are in the
native probe results and live reports.

| Behaviour | Status |
|---|---|
| Overlay layer above the bar, centred on the screen, input only inside the pill | Verified live |
| Square top edge and rounded bottom corners | Verified live and by an offscreen software-renderer check |
| Hover expands after the dwell and collapses on leave; a quick pass does not expand | Verified live |
| Volume HUD from the PipeWire default sink; brightness HUD from the helper's unprivileged udev backlight watch | Verified live with `wpctl` and `brightnessctl`. Physical keys run the same commands but were not pressed |
| Automatic display backlight selection, configured override, display floor and keyboard LED re-read | Isolated `qml-lifecycle` fixture covers discovery, sysfs levels, display backlight event filtering (the helper's event filter is covered by `helper-backlight`), the `keyboardBacklightChanged()` IPC verb producing one keyboard event, and fixture `brightnessctl` writes including the 1% display floor. LED brightness changes emit no uevent (verified live with `udevadm monitor --subsystem-match=leds`), so keyboard events depend on the installed bindings calling the verb. Live keyboard and display keys remain untested for this change |
| Mic mute HUD source | Pure baseline and mute-flip tests plus packaged QML load check. Panel wiring and live PipeWire mute changes remain untested |
| `fullscreenBehavior` selection | `qml-fullscreen-policy` covers all three modes and exact selected-app matching, and Panel applies the policy to the fullscreen client on the island's monitor. Live compositor behavior remains untested |
| Inline, below and open HUD visuals and draggable bar | Offscreen `qml-hud-styles` and `qml-hud-bar` cover all layouts, direct level requests, timer renewal and active-only hit rectangles. The inline volume and brightness readouts and the volume pill below the notch were captured live (inline volume, inline brightness, and below-the-notch readouts); a live pointer drag of the bar remains untested |
| `hud:false` stops the backlight monitor | Verified live |
| Shelf paste (Ctrl+V), copy (Ctrl+C) and remove (Delete or the menu) | Verified by `qml-shelf-view` (keys and menu), `qml-shelf` (the `Shelf.js` model) and `qml-lifecycle` (the Service's clipboard processes); the `text/uri-list` clipboard round trip was verified live |
| Dragging files into and out of the shelf | **Not tested.** Both paths ship enabled; Ctrl+V and Ctrl+C are the proven route |
| Shelf tab placement, close guard and drag catch zone | Verified offscreen by `qml-island-surface` (ShelfView in the Shelf tab with room for its notice, busy pairing through the real surface, catch-zone states and drag-open, a Share tile drop keeping the island open), `qml-catch-zone` (row detection and free span) and `qml-bar-widget` (the spacer measuring occupied left and right rows, and publishing -1 without them). The live drag into the catch zone is **not tested** |
| Shelf model, persistence and salvage | Verified by `qml-shelf-model`, `qml-lifecycle` and `shelf-private-writer` (0600 on first atomic save, per-entry salvage, deleted when turned off) |
| Shelf thumbnails | PNG and JPEG verified by `helper-artwork` and `qml-lifecycle`, including stale cache and EXIF rotation cases; other files use theme icons from `xdg-mime` |
| Shelf actions (zip, rename, convert, PDF, open, Show in Files) | Command arrays and a real mixed-folder zip verified by `qml-shelf-actions`; zip, rename and failed-output cleanup also run in `qml-lifecycle`. Convert and PDF need `magick`, Remove Background needs `rembg`. **No live run yet** |
| Share (LocalSend, KDE Connect, open folder) | Provider choice and commands verified by `qml-shelf-actions`. KDE Connect shares to the first reachable device from `--list-available`. **No live run yet** |
| Hiding over fullscreen, centre-peek suppression | Covered offscreen only. Escape on a keyboard-summoned island was later verified live (see Island experience below) |
| More than one output | **Not tested.** One island follows the focused monitor and moves once it collapses; only one output was attached |

## Island experience

The live pill, peeks, artwork tint, springy morph, gestures, summoned keys and
synced lyrics were checked on 2026-09-25 against the installed package on the
same single output (eDP-1, 1920x1200, Hyprland 0.56.2, Quickshell 0.3.1,
PipeWire 1.6.8). The evidence is in the live acceptance report.

| Behaviour | Status |
|---|---|
| Spectrum bars (`visualizer`, on by default) move while playing and hold flat while paused; the capture is one `nookisle-spectrum` node started with `--fps 15`, and it stops on pause | Verified live with 16 bands at 30 lines a second; on the 12-band, 20-line build and again on the final 15-line default the moving bars and the single node were rechecked |
| With `visualizer` off, the playing pill shows the static play-state glyph and no capture runs | Verified live |
| The capture stops with `visualizer:false`, a hidden island (`autoShow:false`) | Verified live |
| The capture while the screen is locked | **Known limitation.** The stock Omarchy host hides its lock service from plugins, so a playing, visible island keeps capturing behind the lock. A reachable lock provider is covered by `qml-lifecycle` |
| No recording indicator on the bar | Verified for this layout, which has no Microphone widget. Omarchy's optional Microphone widget counts every input stream, this capture included |
| Track peek on a song change, settled by 4 s, clear of the bar's left and right sections | Verified live |
| Charger and battery peeks | `qml-peek` and `qml-island-surface`; UPower's 0..1 level scale was checked live. A real plug or unplug was **not performed** |
| Artwork tint of the spectrum, sliders, hairline and glow, at a vibrance floor, with the island's text, tabs, card and filled controls kept neutral; `tint:false` restores the theme | `qml-tint`; the earlier live check with `remoteArtwork:true` predates the neutral chrome, which awaits live acceptance |
| Grow with a slight overshoot into the spare strip, clean collapse, nothing clipped at the sides | Verified live from screen captures |
| Summoned Space, N, P, Tab and Escape | Verified live with exclusive keyboard focus, sent only to the island or a throwaway window |
| Wheel volume and horizontal swipe on the pill | `qml-island-input` only. **Not performed live**: nobody scrolled in the 60 s window and no pointer injector is installed. The swipe direction under natural scrolling is also unverified live |
| Double-click on the expanded art toggles play/pause | `qml-island-input` only |
| Synced lyrics from LRCLIB follow the song; `lyrics:false` returns to Now playing (now Home) | Verified live with one real lookup |
| Lyrics settle while skipping tracks; no lookup while hidden or locked | `qml-lyrics` and the source contract only |
| `hud:false` | Verified live |
| More than one output, frame timing and GPU budgets | **Not tested** |

## Notch parity

The boring.notch parity work was checked on the same output (eDP-1,
1920x1200, scale 1) with Hyprland 0.56.2 and Quickshell 0.3.1. Captures are
linked where they exist; a row without one was checked by its tests only.

| Behaviour | Status |
|---|---|
| Black notch with concave flares, closed and open sizes, spring morph, fixed window and input region | `qml-notch-shape`, `qml-motion` and `qml-island-surface`; captured live closed and open |
| Header tabs, capsule, gear, battery slot and summon auto-close | `qml-island-surface` and `qml-panel-screen-selection`; captured live. The capsule slide and the Shift-wheel pull were not observed live |
| Home player: cover, badge, title and artist, lyric line, scrubber, toolbar and volume | `qml-home`; captured live with a real track. A long-title marquee was not captured live |
| Closed live activity, pause grace and idle face | `qml-closed-model`, `qml-spectrum-frames` and `qml-island-surface`; captured live |
| Shuffle, repeat, ±15 s and favorite buttons | `qml-home`, `helper-registry` and `extension-routing`. Spotify desktop hides shuffle and repeat (see [transport boundaries](#transport-boundaries)), so no live toggle was possible |
| Battery gauge, popover and charger banner | `qml-battery`; no real plug or unplug was performed |
| Calendar and reminders from local ICS, vdir folders, iCal links and CalDAV | `helper-calendar`, `qml-calendar` and `qml-lifecycle`. No live remote server was checked |
| Camera mirror | `qml-camera-gate`; live on the installed package, the device is held only while the island is open on Home and is released about 50 ms after it closes (verified in live camera gate report) |
| Welcome camera test | `qml-onboarding` covers the explicit press and every closing path. A standalone live window released the device 47 ms after leaving the step; the host's `onboarding()` verb path was not checked live |
| Settings window and welcome steps | `qml-settings-window`, `qml-settings` and `qml-onboarding` |
| Shelf strip, menu, drag-out and share | See the shelf rows under [dynamic island](#dynamic-island) |
| Media-key bindings block and optional blur | `tests/test-install-plugin.py` covers the marked block, backup, verification and removal against a disposable config |
| One readout per media key | `tests/test-install-plugin.py` runs the helper with faked commands: the island's `ok` keeps Omarchy's OSD away, while `unavailable`, no answer and external or Apple displays run only Omarchy's own command. `qml-lifecycle` covers the `hudReadout` answers for `hud:false`, a hidden island and an unwatched backlight. Physical keys, a real disabled plugin and a DDC display remain untested live |

## Features beyond parity

Checked by tests only; none of these has been exercised on the live desktop
yet. The offscreen probes used a throwaway `pw-record` stream and the paired
devices as they were, and changed nothing.

| Behaviour | Status |
|---|---|
| Closed-notch activities (compact and minimal) and the sleep timer's glyph | `qml-activity-model`, `qml-closed-model` and `qml-island-surface` |
| Helper desktop signals (camera holders, recording marker, screenshots, reminder units) | `helper-system-watch` against fake `/dev`, `/proc` and folders; `helper-lifecycle` for the watch acknowledgement; `qml-lifecycle` shelves a screenshot the real helper saw |
| Privacy indicators | `qml-privacy` and `qml-island-surface`. An offscreen Quickshell probe against the live PipeWire graph named a microphone capture and ignored a sink-monitor capture. A browser camera and a portal screen cast were not checked live |
| Device and output peeks | `qml-device-events`, `qml-peek` and `qml-island-surface`. An offscreen probe listed the paired devices; no connect, battery report or output switch was performed |
| Timers | `qml-timers`, `qml-island-surface` and `source-contract` (IPC verbs, fixed commands). No reminder was started or cancelled live |
| Screen recording activity and shelving | `qml-island-surface` and `qml-lifecycle`; no real recording was made |
| Screenshots to the shelf | `qml-lifecycle` end to end through the real helper and a private folder; no real Omarchy screenshot was taken |
