# Nookisle interface

With `island` on (the default) and a top bar, Nookisle is a black notch
over the bar's centre, after boring.notch's. Closed, it shows the live
activity; hovered, tapped or summoned, it opens into a 640×190 panel with Home
and Shelf tabs. This page covers the notch, its header, Home, gestures, keys
and settings; [island features](features.md) covers the level readout, peeks,
battery, lyrics, the shelf and the calendar. When the host exposes a lock
provider, either form shows only once that provider reports the session
unlocked. Current Omarchy hosts hide the provider from plugins, so the plugin
then relies on the compositor's session lock to keep it off screen (see
[host and session constraints](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/architecture.md#host-and-session-constraints)).

With `island:false`, or on a bottom, side or vertical bar, the resident widget
is inline in the existing status bar instead. Clicking its
title toggles one shared detail panel below the clicked widget, on that display.
The panel aligns to the widget's left edge, constrained by the output edges,
so its origin remains clear beside the workspaces. [Panel.qml](../Panel.qml)
retains center anchoring for older explicit IPC callers.
There is no resident floating window. Closing the panel returns to the bar;
output changes close details and cancel gestures. None of these actions changes
playback. The widget follows the host bar's fullscreen visibility policy.

## Geometry and appearance

[DesignTokens.qml](../components/DesignTokens.qml) owns dimensions, spacing,
fallback colors and finite motion timings. [Panel.qml](../Panel.qml) binds its
palette, typography and corners to Omarchy's live Commons Color/Style tokens;
[BarWidget.qml](../BarWidget.qml) follows the bar's foreground and font without
an independent filled capsule. This keeps the controller part of the user's
shell theme rather than imposing its own brand, including square corners when
the shell requests them. Native logical pixels follow the display scale.

In the legacy widget, the bar adapts to the title width, up to 280 logical pixels. Title and playback
share one continuous hover surface, which stays highlighted while details are
open; their click actions remain separate. The panel emphasizes larger artwork
and a grouped transport row, with source mode and count in the footer.

With `island` on and the widget hosted on a top, non-vertical bar,
`BarWidget.qml` becomes an invisible spacer exactly as wide as the closed
notch's body, `DesignTokens.liveWidth − 2·flareClosed` (268) logical pixels;
the notch's top flares overhang it by `flareClosed` (6px) on each side. It
publishes no click targets, no tooltip and no
click-through geometry, because the notch ([island interaction](#island-interaction))
is the screen-centred surface the user actually sees and clicks. This only
reserves space correctly when the widget is the bar's centre anchor on a
full-width top bar (`centerAnchor: "io.github.bavanchun.nookisle"` in
`~/.config/omarchy/shell.json`), so flanking modules do not slide under the
pill; on any other bar position the spacer would reserve the wrong place, and
`island:false` is the remedy. The spacer reports whether its centre sits
within 2 px of the bar's middle (`CatchZone.offCentre`, through
`noteBarPlacement`); the Service's `islandOffCentre` is true while any screen's
island is away from it, and the welcome then explains how to make it the
centre anchor. On a bottom/side bar or a vertical layout the
widget keeps today's inline title-and-playback controls unchanged, because
there is no top-edge notch to reserve room for there. While the pill is
hovered or expanded, the spacer calls the host's
`setCenterHoverRevealSuppressed` so the centre-section indicator peek does not
compete with the island; it writes `false` again only on its own transitions
(hover/expansion ending, or widget destruction), matching the contract the
first-party clock and weather panels use for the same shared flag.

The bar delegates hover help to the host's native tooltip popup because an
in-window tooltip would be clipped by the bar's shallow window. BarWidget owns
bounded tooltip text and refreshes it when metadata or control status changes
during a stationary hover. Panel help uses
[IslandToolTip.qml](../components/IslandToolTip.qml) to wrap text within its window.

The legacy detail surface gives metadata, playback and utility controls distinct
space. [IslandContent.qml](../components/IslandContent.qml) owns their hierarchy
and the separate volume row at narrow widths; Panel owns the matching window
height. This preserves control targets instead of squeezing them together.
The reserved error area keeps recovery instructions readable without replacing
artist metadata or moving the footer when a command fails. Geometry and larger
font examples are covered by the [state tests](https://github.com/bavanchun/nookisle/blob/v1.0.3/tests/qml/tst-island-state.qml).

The legacy panel's tinted surface and hairline work without backdrop blur, and
the island is solid black and needs none. The plugin never changes compositor
blur by itself; only the installer's opt-in
[bindings block](install.md#one-on-screen-display-for-media-keys) turns on
global blur and adds a blur rule for the `nookisle` layer. Production colors follow the
shell theme; Qt's light/dark scheme is only a standalone fallback. High contrast
uses opaque surfaces. Settings also expose reduced
motion, status-bar visibility, and opt-in remote artwork through the Service
configuration contract.

The window reserves no workspace strip. The legacy panel requests keyboard
focus on demand while expanded. The island takes the keyboard only while it is
summoned (explicitly opened), and then exclusively, until Escape, a host
toggle, a collapse or anything that hides it (a lock, a screen change,
`island:false`) releases it; a hover-opened island never takes the keyboard
(`IslandKeys.keyboardFocus`). When the settings or welcome window opens while
the island is summoned (the header gear, or a verb), the island stays open but
lends that window the keyboard, and takes it back when the window closes. A
window that was already open does not hold the keyboard against a summon, so
keys never go to it on another workspace: every summon takes the keyboard
back. Pressing the header gear while summoned lends the keyboard to the
settings window even when it was already open. A summon is refused while the panel is not
allowed, so none can wait behind a lock and take the keyboard on unlock. Its input region follows the
shell's corner radius. Escape closes the source/settings view,
then closes details. Details remain closed until explicitly opened again.

With `island` on, [Panel.qml](../Panel.qml) hosts
[IslandSurface.qml](../components/IslandSurface.qml) instead of the legacy
card, in the same fixed-size Overlay window anchored to the top edge only; the
compositor centres it on the output because the bar widget spacer reserves
the matching centre width (see "Geometry and appearance" above and
[architecture documentation](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/architecture.md#host-and-session-constraints)). The window
is never shown while `hostBar.position` is not `top` or the bar is hidden,
mirroring the bar widget's own island-mode gate. The host's open state
(`isPluginOpen`, which `shell.qml` reads as `loader.item.opened`) mirrors the
island's `expanded` property for both a hover-driven and a keyboard-summoned
expansion: a host `toggle` on a hover-open island therefore collapses it, and
a second `toggle` reopens it explicitly with keyboard focus. A keyboard summon (`open()`) calls
`IslandSurface.expandTo("home")` and focuses the surface; `close()` calls
`IslandSurface.collapse()`. The island follows `Hyprland.focusedMonitor`,
but only while collapsed: a focus or output change while expanded is deferred
until the next collapse, so the surface never jumps away from underneath the
pointer. The Overlay window stays hidden over a fullscreen workspace unless
the island was opened explicitly, matching the host bar's own
fullscreen policy. The window is
always mapped at its final fixed size; only the in-window `IslandSurface`
card geometry morphs, so switching between the legacy card and the island
surface, and the pill-to-card expansion itself, never resizes the layer
window or changes its input region per frame.

## Controls and state

The legacy panel's [content component](../components/IslandContent.qml) consumes only the
Service facade. Compact mode shows artwork, title, source, and play/pause.
Expanded mode adds artists, source scope, capability-aware previous/next,
volume where supported, progress, source selection, and settings.
[SourcePicker.qml](../components/SourcePicker.qml) owns the bounded source list
and Tab/Backtab or Down/Up navigation, keeping the focused source in view. It
opens as an overlay below the header rather than replacing the player, so the
source being switched away from stays visible; below the narrow threshold it
covers the whole stage. The covered stage stays visible but becomes `enabled:
false`, and that is what cancels captured intent on the controls underneath —
`IntentSlider` and `IslandButton` each cancel on `onEnabledChanged`, and
`commitGesture` refuses while disabled, because opening the overlay flips two
independent bindings whose evaluation order Qt does not guarantee.

A "Show player" control raises the source's window through the `Raise` action.
It is gated on `capabilities.CanRaise` and disabled with a stated reason when the
source does not advertise it. A successful reply does not prove the window came
forward; the plugin cannot observe compositor activation and claims nothing.
Returning from sources or [settings](../components/IslandSettings.qml) restores
focus to the opener so keyboard navigation retains its place. Document-targeted
sources show both the verified platform and host; generic browser sources
remain labeled as browser controls. Pin/Auto only changes selection. A pin
lasts for the session; the remembered player (`preferredSource`, chosen in
the welcome) is saved and steers Auto whenever that app is present, so a
restart never leaves a pin to a player that is gone.

Buttons capture intent at press, and sliders at gesture start. Sliders preview
locally and submit once on release, including keyboard arrow gestures. Endpoint
or track changes, lock, hide, capability loss, Escape, and focus loss cancel
unsent slider intent. [IntentSlider.qml](../components/IntentSlider.qml) owns
this cancellation boundary: leaving a control must not submit an unfinished
adjustment later. No control looks up a replacement endpoint when releasing a gesture.
The Service independently validates connection, admission epoch, and selection.
The bar registers click targets with the host's reorder layer. A passive pointer
observer captures the original play-button press before a forwarded click;
dragging the widget does not dispatch playback.
Pending indicators reflect actual outstanding commands. Failure text never
optimistically changes playback or retries a toggle.
[IslandButton.qml](../components/IslandButton.qml) owns focus, press, disabled
and pending feedback; its primary focus outline remains distinct from the fill,
and pending controls do not suggest that another press sends another command.
A `tonal` button is the quiet action for an empty state ("Sources" on Home,
"Add calendar" in the calendar): a pill washed with the ink at 0.14, 0.20 when
hovered and 0.24 when pressed. The filled primary style stays for the one
action that fixes an error (Retry, Try again).

Empty, unavailable pin, helper failure, and unsupported controls have explicit
states. A disconnected helper removes playable metadata and offers Retry;
panel visibility depends on safe unlocked ownership, while controls additionally
require the acknowledged helper gate. Disabled controls remain keyboard
discoverable with an accessible explanation. Lock removes the entire UI.

## Sleep timer

Settings offers Off, 15, 30 and 60 minutes. Arming records the selected
source's token and an absolute deadline and sends nothing. The settings row and
the player's status band show a fixed "Pauses at HH:MM" computed once; there is
no countdown, because it would repaint every second for up to an hour and say
nothing a fixed time does not. The closed notch shows the same fixed time
beside a moon, as its minimal activity glyph. The indicator yields the status
band to an action error so the band height never changes. The timer is runtime state and
is not persisted through `configure()`.

At expiry the Service captures a fresh intent, because the selection revision
and admission epoch rotate over minutes and a stored intent would be refused. It
sends one `Pause` only if that intent still targets the armed token and the
source still advertises `CanPause`; otherwise it sends nothing and states that
the source is gone. It never pauses a different source. A timer that wakes
before its deadline, such as after a suspend, reschedules for the remainder.
If a user command is outstanding at expiry, it re-fires once two seconds later,
then reports that it could not pause instead of retrying.

Arming needs a selected source that advertises `CanPause`; otherwise the options
are disabled with a stated reason, and Off stays reachable. The Service's
teardown funnel cancels the timer on lock, helper exit, protocol error,
retirement, supersession and disposal, so no orphaned instance keeps one armed.
Locking the screen cancels it only when the plugin can see the lock provider.
Current Omarchy hosts hide that provider from third-party plugins; the timer
then stays available and keeps running across a lock, and the settings row says
so. This is deliberate, not a bug to fix: see
[host and session constraints](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/architecture.md#host-and-session-constraints).

Settings scroll when their content outgrows the card, with the scroll bar always
drawn while there is more below. Tab focus scrolls the focused row into view.

## Resource ownership

Only the Service subscribes to playback progress. QML renders supplied samples;
it has no recurring playback timer. The bar fetches no artwork and subscribes
to no progress updates. Expanded content unloads on collapse or
hide. Opening fades the card at its final window dimensions: avoiding
per-frame layer-window resizing keeps text and controls stable. There is no
perpetual animation. Reduced motion is the `reducedMotion` switch or, with
`followDesktopMotion` on (the default), Hyprland running without animations;
it also replaces the live spectrum with the still play glyph and stops its
capture. Hide, lock, and reduced motion stop and settle motion
immediately. Press feedback is immediate.

[Artwork.qml](../components/Artwork.qml) accepts only sanitized local paths
from the helper. A bounded, event-driven Canvas applies rounded clipping so
artwork also works under the Qt Quick software renderer. It repaints when an
image loads or geometry changes, not each playback tick. The hidden Image
supplies dimensions and error state; both decode paths receive the helper's
already bounded raster. When the path changes to a new cover, the shown cover
stays drawn (a second canvas holds it) while the new one loads and fades in
over it for 180ms, then is unloaded, so a track change never flashes the
placeholder. A skip while the next cover is still loading keeps the last cover
that was on screen until a successor is paintable, so at most two covers are
held: the one displayed and the one loading or fading in. A path that clears
or fails drops the old cover at once, and hide unloads both.
Hide/reduced motion stops the fade immediately. It does not blur the desktop.

## Island interaction

[IslandSurface.qml](../components/IslandSurface.qml) is the pure-QtQuick notch
component that `Panel.qml` hosts in island mode. It
is a fixed-size `Item` that never imports Quickshell, so `qmltestrunner` loads
and drives it offscreen; an accidental Quickshell import would fail that load
outright.

**Closed notch.** Closed, the notch follows boring.notch's closed live
activity. [ClosedModel.qml](../components/ClosedModel.qml), a pure QtQuick
model the surface hosts, picks one state, in priority order: `hudInline` (the
level readout, 380px), `battery` (a charger or battery event, 640px, or 380px
when that does not fit), `peek`, `activity` (a screen recording or a timer,
280px), `live` (music, 280px) and `idle` (280px for the glance, 233px for the
face, 120px for Horizon, 185px empty).
Every width includes the flares and is clamped to the screen. Music is live
while it plays and for `pauseGrace` ms after a pause (3000 by default,
0–10000), so a pause between tracks does not shrink the notch. Changing that
setting during a pause updates the remaining time from the original pause;
setting it to zero ends the live state immediately. The same timeout controls
when the closed row gives way to the idle style. A track that
was already paused when the island started is idle. `musicLiveActivity` off
keeps the notch idle while music plays. The width springs between states
(0.42, 0.8), while the body's input region jumps to its resting width and
never grows past the 280px live notch the bar spacer reserves, nor shrinks
below the 185px base notch (Horizon keeps the base notch's region over the
bar centre the spacer reserves, so it stays as easy to hover).

**Activities.** [ActivityModel.qml](../components/ActivityModel.qml), after
the Dynamic Island's compact and minimal presentations, ranks what is going
on: a screen recording, then music, then a running timer, then an armed sleep
timer ([qml/Activities.js](../qml/Activities.js)). The highest one fills the
notch; music keeps the `live` state, and a recording or a timer ahead of it
is the `activity` state: its glyph on the left (a red dot and "REC", or a
draining ring), its label in the centre when `hardwareNotch` is off, and its
minutes on the right ("12m", "1h 05m", "<1m"). The next activity down shrinks
to a 14px glyph, beside music, an activity or idle but never over the HUD, a
banner or a peek: a red dot, the cover, a ring, or a moon with the sleep
timer's time. A sleep timer is only ever that glyph. With `hardwareNotch` off
it closes the centre region, 8px before the right wing's bars or minutes,
which stay at their inset, and the centre's title or label gives way. Over a
camera cutout, and while idle with nothing on the right, it takes the outer
end instead and the right wing's content moves in beside it; the notch widens
by 22px for it only over a camera cutout or with a small idle style. A third
activity waits. The
labels step once a minute on the activity's own minutes, from a single-shot
timer that runs only while the island's window is on screen, so the closed
notch never shows seconds and never loops.

**Idle.** While nothing plays, `idleStyle` picks what the closed notch shows:
the glance (the default), the face, Horizon or the empty base notch; see
[the idle notch](features.md#idle-notch). The separate
HUD and drag catch regions are described with the
[level readout](features.md#level-readout) and the [shelf](features.md#shelf).

[ClosedNotch.qml](../components/ClosedNotch.qml) fills the two wings either
side of the idle body. Only a screen with a camera cutout needs that body
empty, so it stays empty only with `hardwareNotch` on (off by default).
Otherwise the live notch shows the track title in the body's centre, between
the cover and the bars (8px from each), in the caption size and centred.
After a track change, while playing, a title too long to fit scrolls through
exactly one [Marquee](../components/Marquee.qml) pass (the 3s pause, then
the scroll) and then rests elided, so the closed notch never loops a
marquee; a paused track never scrolls. Live, the left wing holds the 20px
cover (radius 4) or a music glyph 10px (`closedInset`) in from the body's
left end, and the right wing the 12 live spectrum bars
([SpectrumBars.qml](../components/SpectrumBars.qml)), packed a pixel apart
into 35px (`closedSpectrumWidth`) and as far in from the right end, so the
wings mirror each other and the bars clear the rounded corner. They are tinted when
`coloredSpectrogram` is on (the default) and in the text colour otherwise, with
a 2px progress hairline along the bottom, inset by the bottom radius. The art
and bars shrink to fit above the hairline on the 26px bar. The bars step with
each spectrum line, with no easing of their own (the binary already smooths
the fall), so the notch repaints at the line rate and stops when the lines
stop. On a pause, or when the capture stops, the last line falls flat over
300ms (`spectrumDecayDuration`, one finite tween; instant under reduced
motion), and the bars then lie flat in the muted secondary colour while the
capture is silent. With `visualizer` off, or when the spectrum binary is
unavailable, the right wing shows the static three-bar play-state glyph
instead. Paused within the pause grace, once the bars have fallen, a static
two-bar pause glyph replaces them (or the play-state glyph) at the same
inset, fading in over 100ms, so the rest state says "paused" rather than
showing a row of flat dots. The music slot keeps the same width playing and
paused (the wider of the bars or play-state glyph and the pause glyph), so
the centre title and a minimal activity glyph never move on a pause. The cover box stays
empty while its art loads; the music glyph stands in only when the track
has no art or the art has not arrived 150ms after it was asked for. Paused
within the pause grace, the cover dims to 60 % (`pausedWingOpacity`) over
100ms, as the open player's art dims.

The shape moves first, as the Dynamic Island's compact views do. A change of
closed content fades the old wings out over 90ms (`closedFadeOut`) while the
width already springs, so the content leaves with the shrink instead of a
frame before it, and the new content fades in over 130ms (`closedFadeIn`)
and, while the width is still moving, only over the last 30 % of the move.
Content that draws nothing in the wings (an empty idle notch, the inline
HUD) swaps at once. Reduced motion swaps at once. The hairline fills with
`positionSeconds / lengthSeconds` and steps at most once a second. The inline
HUD puts its icon in the left wing and its level bar and percentage in the
right; without a hardware notch the two halves meet across a 12px gap as one
centred row, instead of either side of the 173px camera gap.

**Header.** The open notch starts with
[NotchHeader.qml](../components/NotchHeader.qml), after boring.notch's
header. On the left, **Home** and **Shelf** are icon tabs (a house and a
tray, 16px, full ink when selected and secondary ink otherwise); Shelf adds its
item count as a small badge once the shelf holds something, and never shows a
zero. A 26px capsule, a 14% wash of the ink, slides under the selected tab by
animating its x and width over 350ms (`tabDuration`, `OutCubic`; none under
reduced motion). Each tab's accessible name is its word, with the count for
Shelf ("Shelf, 2 items"). The
tabs show while `alwaysShowTabs` is on (the default) or the shelf holds
files. Turning on Remember last tab also turns on Always show tabs, so a
remembered empty Shelf remains reachable. The centre is a span exactly as wide as the closed notch's
body. With `hardwareNotch` on it stays empty, so nothing sits under a camera
cutout; otherwise it holds the activity chips
([ActivityChips.qml](../components/ActivityChips.qml)): the soonest timer's
minutes, which open the Timers view, and the privacy chip naming the apps
that capture. On the right are the camera toggle, the Timers button (a stopwatch, with
the soonest timer's minutes left beside it while one runs and the row has
room for it; washed like a
selected tab while the Timers view is open; named "Timers", "Timers, Tea, 13m
left" or "Close timers" for assistive tech), with
`hardwareNotch` on a red Stop button while a screen recording runs, the
settings gear and the battery slot; each hides while its feature is off.
The right-hand row never crosses into the centre span (which sits under a
camera cutout with `hardwareNotch` on); [HeaderSlots.js](../qml/HeaderSlots.js)
plans it by priority: Stop, battery, Timers, camera toggle, gear. It shows
every entry at full width when they fit; otherwise it first drops Timers'
time left, then the battery's percentage; if the row still does not fit, a
"more" button (three dots) at the row's inner end takes the least important
entries into a menu, never keeping a less important entry in the row while
a more important one is folded. The menu lists each folded entry under the
same name it has in the row (its button is named "More: …" with them), opens
from the keyboard with its first entry focused (Tab moves, Return runs,
Escape closes back to the button), and runs the same action. The menu
belongs to the open view: a tab change, any collapse or host reset, and the
readout taking the row's place each close it. The pointer on the menu counts
as inside the island, so moving from the button into an entry never starts
the leave grace; leaving the menu for outside the island starts it as
leaving the island does. The inline battery is a keyboard button too: Tab
reaches it, and Return, Enter or Space opens the battery popover. The open-notch
readout that takes the row's place narrows its bar to the same room. The
tabs on the left fit their side down to a 500px header. The camera toggle shows while `showMirror` is on and hides or
shows the mirror for the session: the choice holds across closes until the
shell reloads. The gear opens the settings window in one click. Shelf is the
shelf view. The battery detail menu stays below the header and scrolls its
details when they exceed the 190px open notch, so its Power settings button
stays reachable.

**Home.** [HomeView.qml](../components/HomeView.qml) fills the open notch
under the header with a row: [PlayerPanel.qml](../components/PlayerPanel.qml),
then [CalendarPanel.qml](../components/CalendarPanel.qml) when `showCalendar`
is on and the camera mirror when `showMirror` is on (both off by default).
The gaps are 15px, or 10px with the mirror shown, and the player takes the
width left over. Home, the header and Shelf sit 12px inside the notch body, as
in boring.notch. The columns share a top line, the cover's top edge 5px in:
the capitals of the first text line (the title, or the glance's time) and of
the calendar's month start on it (placed from the font's ascent and capital
height), and the mirror is aligned with the cover. The player's buttons sit
at Home's foot, level with the end of the calendar column, and never over the
scrubber. The open notch stays 640×190 with Calendar shown; the
calendar's event list uses the height left below its header and day wheel.
Calendar days, event rows and reminder checks take Tab focus; Return or Space
selects a day, opens a local event, or completes a reminder respectively.
Tab and Shift+Tab keep the focused day or event row inside its visible list.
Tab moves from the last day into the event list; after the final event or
reminder check (or from the last day when the list is empty) it leaves the
calendar for the next Tab stop, and Shift+Tab from the first day leaves for
the one before, so the calendar never traps focus inside Home.
When today's list opens, its current or next event aligns at the top after
wrapped row heights settle. User scrolling then takes precedence.

The mirror is [CameraPanel.qml](../components/CameraPanel.qml): a 120px square
of the default camera, mirrored, clipped to a 13px rounded square or to a
circle (`mirrorShape`, `rectangle` by default), revealing on a (0.32, 0.76)
spring. Its camera runs only while the mirror is shown, the island's window
is shown, the island is open with its open spring settled, Home is the view
and the tile is visible (no overlay over it). The capture source loads once the reveal has finished, as
opening the device stalls the GUI thread for about 140ms; losing any of these
conditions destroys it and releases the device. A missing device or camera
error shows a caution icon and "Camera unavailable". The tile itself (#141414
with a 4% white hairline, a grey camera glyph and "Mirror") is always drawn
while the mirror shows, and only the feed reveals over it, so Home has no gap
while the island opens or the device starts. A tap on the tile stops the
camera and shows the tile; another tap starts it again (for the session).

The player, after boring.notch's:

- **Cover.** 90px, radius 13. A tap raises the source app (MPRIS `Raise`, when
  the source allows it), once the double-click interval has passed without a
  second tap; a double tap toggles play/pause and dips the cover. Paused, it
  springs to `pausedArtScale` (0.85) and darkens: under a flat black veil at
  0.5 without GPU effects, under a blurred dark copy at 0.8 with them. A white
  play glyph fades in over it, and one tap on a paused cover resumes at once
  (the second press of a double tap does not pause it again).
- **Glow.** With GPU effects, a copy of the cover blurred (blurMax 40),
  stretched 1.3 × 1.4 and turned 92°, at opacity 0.5 while playing and 0 while
  paused; without them, the tint rings. `lightingEffect` turns it off. Both
  paths need an active artwork tint, including on hardware renderers.
- **App badge.** The source app's icon, 30px, overhanging the cover's
  bottom-right corner by 10px. `Panel.qml` resolves it from the source's MPRIS
  `DesktopEntry` first (that entry's icon, then the entry id as a theme icon),
  then from its app name (a matching desktop entry's icon, then a theme icon of
  that name); a source glyph on a small raised tile takes its place when none
  resolves (`SourceState.badgeIconCandidates`). Tapping or pressing Return on either
  opens the source picker over Home. Closing it from the keyboard (Escape, or
  choosing a source) returns focus to the control that opened it, or to the
  player's controls if that control is gone.
- **Title and artist.** The title in bold ink, the artist in the secondary
  ink; neither takes the artwork colour. Both scroll when they
  do not fit ([Marquee.qml](../components/Marquee.qml)): two copies 20px apart
  move left at 30px/s after a 3s pause, only while visible and overflowing,
  and never under reduced motion. A scrolling line fades out over 12px at
  its trailing edge, and at its leading edge while it moves: gradients in the
  black it sits on, so the software renderer draws them too.
  When the helper trims overlong metadata, Home shows a focusable marker with
  an explanation beside the title.
- **Lyric or status line.** With lyrics on, the line keeps its row for every
  track, so the block never moves as lyrics arrive. A synced line is drawn in
  full ink, medium weight, dropping in from above as it changes (clipped to its
  row); the time before the first line and a break show a note in the tint.
  Anything else is a state message in the dimmed secondary colour that appears
  in place: "Looking up lyrics…" (only after one second of lookup, so a quick
  answer never flashes it; the row is blank until then), "No synced lyrics",
  "Unsynced lyrics only", a tinted note then "Instrumental", "Lyrics
  unavailable" for any error (the Lyrics view carries Try again), "Lyrics need
  the track length" and "Nothing to look up". Home and the Lyrics view read one
  state name, `LyricsSource.displayState`, so their wording cannot drift apart.
  Hovering the line shows the view's detail line. It scrolls like the title when
  it does not fit and fades out on pause; a tap while playing opens the Lyrics
  view. Arabic and Persian lines use Vazirmatn when it is installed. An
  action's error, or the connection state while no source shows, takes the
  line's place.
- **Scrubber.** The position slider across the column, with the elapsed and
  total times under its ends in tabular figures. Without a source there is no
  scrubber and no button row. Its track is 5px, springing (0.35, 0.7) to 9px while dragged, and its fill
  follows `sliderColor`: the artwork colour (`albumArt`, the default for a new
  install), white, or the theme accent. The elapsed and total times stay neutral.
- **Buttons** ([MusicToolbar.qml](../components/MusicToolbar.qml)). The
  `musicControlSlots` setting lists up to five of `shuffle`, `previous`,
  `playPause`, `next`, `repeat`, `volume`, `favorite`, `back15`, `forward15`
  and `none`, cut to `musicControlSlotLimit` (3–5). A button hides when the
  source lacks its capability: shuffle needs `CanShuffle`, repeat `CanLoop`,
  the ±15s buttons `CanSeek`, volume `CanSetVolume`. Spotify's desktop app
  reports neither shuffle nor repeat, so those two hide for it. Favorite
  always shows and dims to 0.35 without `CanFavorite`. With both side panels
  shown and five slots, the first and last drop. Shuffle and repeat are
  dimmed to the secondary ink while off, and full ink with a 4px dot under
  them while on; repeat shows repeat-one for a repeated track. Every
  button dips to 0.9 while pressed on a (0.3, 0.3) spring, on the raised
  `#141414` surface with a 4% white stroke when hovered.
- **Volume.** The volume button slides a 48 × 8px slider out beside it over
  120ms, and back over 200ms; dragging it writes the player volume at most
  every 100ms. Changing source or losing volume support closes the slider;
  updates from the same source, including volume changes, keep it open. A
  slider that closes while it has the keyboard hands it to the volume button.

With no selected source, Home shows a Sources button, including when a pinned
source has disappeared; the chooser can switch back to Auto. A healthy empty
source list asks the user to open a player. A disconnected controller also
shows Retry.

The views are `home` and `shelf`. `lyrics` is a sub-view of Home: Home stays
the selected tab, and a back chevron takes the tabs' place until Escape or
the chevron returns to Home. A stored or passed `player`, Home's old name,
opens Home.

**Timings.** The `hoverDwell` setting (300ms by default, 0–1000) is how long
the pointer rests on the closed notch before it opens, and `leaveGrace` (100ms
by default, 0–1000) how long it stays open after the pointer leaves. Both are
intent timings, not decorative motion, so reduced motion does not shorten
them. A tap
expands immediately. A file drag entering the pill expands straight into the
Shelf view. Hover never starts while a mouse button is held, and the leave
grace is deferred while a slider on Home is mid-gesture
(`HomeView.interacting`) or a shelf drag is in progress
(`IslandSurface.shelfDragActive`: a drag out of the shelf strip, or a drag
held over it); the grace timer restarts once that interaction ends if the
pointer has already left.
The closed body's drop target and the wider catch zone stay in place for a
drag already over them while Shelf opens. They accept Copy only after at
least one item is added; a full shelf or a duplicate refuses the drop.

**Pull gestures.** While closed, a downward drag on the notch (mouse, touch,
touchpad or stylus), or a Shift-wheel down, pulls it open; while open, an
upward drag on the header, or a Shift-wheel up, pushes it closed. Past an 8px
dead zone, so a tap never moves the notch, the progress is travel /
`gestureTravel` × 20; the notch stretches vertically to `max(0.6, 1 +
progress × 0.01)` about its top, and a push dims the open content by
`min(|progress| × 0.1, 0.3)`. At `gestureTravel` (200px by default, 100–300)
it opens or closes once, latched until the drag ends; a Shift-wheel gesture
ends 300ms after its last step (one notch pulls 40px), and a released pull
springs back. `enableGestures` turns both off, and `closeGesture` only the
push. The plain wheel keeps its volume and swipe actions, and the push lives
on the header, so it never takes a drag from a slider or list.

**Close guard.** `IslandSurface.beginBusy()` and `endBusy()` hold the island
open while a menu, picker or share action needs it: while `busyCount` is
above 0, the leave grace, a push or Shift-wheel close, a summon auto-close,
the player's own close requests and the host's toggle all leave it open.
Escape still closes it. The host's safety resets (the lock screen or a panel
disallow, leaving island mode, a screen change and fullscreen) go through
`resetForHost()`, which closes the island and drops every hold, so it never
shows over a lock screen or carries a busy state to another mode or screen.
Each hold lapses on its own after 2s, and when
the last one ends with the pointer already gone, the leave grace runs again.

**Keyboard / accessibility path.** Hover expansion never takes keyboard focus.
An explicit (host-summoned) expansion sets `explicitOpen`, which makes a
pointer leave a no-op: only Escape, a host toggle or a host hide can close it.
A summon may close itself again: a payload with `"autoClose": true` closes
the island after the `summonAutoClose` setting (3000ms by default, 0–10000,
0 never), unless the pointer arrives, a press lands on it, a key is pressed
or focus moves into a view first. The IPC verb is unchanged; the payload key
is additive (see [install](install.md#summon-with-auto-close)).
A summon focuses the surface root (`IslandSurface.focusKeys()`), where the
shortcut keys live (see [gestures and keys](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/interaction-reference.md#gestures-and-keys)), and Return steps into the
view (`IslandSurface.focusContent()`). Keys bubble from the focused control up
through the view to the root, whose Escape closes Home's settings or source
overlay first, then leaves Lyrics for Home, then collapses the island.
A collapse gives that focus back (`IslandSurface.releaseKeys()`), so every
summon starts on the root, where Tab and Shift+Tab switch views, and a hover
open never wears a focus ring left from an earlier summon. While the root holds
focus, a ring in the accent colour fits the tabs (or the back chevron in
Lyrics), sized from `NotchHeader.tabsRect`.

**Shape.** The island is a solid black notch
([NotchShape.qml](../components/NotchShape.qml)), after boring.notch's
`NotchShape`: a concave quad flare at each top corner that meets the screen's
top edge, straight sides, and quad-rounded bottom corners, drawn by a
`Shape` with `preferredRendererType: Shape.CurveRenderer`. Its width includes
both flares; the body the content lives in spans `[flare, width − flare]`,
and a 1px strip of the fill runs across the top of the body so no seam shows
at the screen edge. The fill is `notchColor` (`#000000`) whatever the theme
or the artwork. Closed, the notch is `liveWidth` (280) wide including the
flares and as tall as the bar, with flare `flareClosed` (6) and bottom radius
`bottomRadiusClosed` (14). Open, it is `openWidth × openHeight` (640×190)
with flare `flareOpen` (19) and bottom radius `bottomRadiusOpen` (24). Every
width is clamped to the island screen's width less `gap` on each side
(`IslandSurface.availableWidth`, from `Panel.qml`). The notch is centred
horizontally and sits at y=0.

`DesignTokens.gpuEffects` is on only when the island window's scene-graph
API is a hardware one (`OpenGL`, `OpenGLRhi`, `VulkanRhi`, `MetalRhi` or
`Direct3D11Rhi`); `Unknown`, which the offscreen platform reports, and
`Software` keep it off. Every GPU effect sits behind it, which
`tests/source-contract.py` pins. With `gpuEffects` on, the body's content is
masked by the shape itself while the notch is open, moving or peeking
(`MultiEffect` with `maskEnabled`, fed a `ShaderEffectSource` of the shape's
body, `autoPaddingEnabled: false`), and a `RectangularShadow` (black at 70%,
blur 6, spread 0, 2px down, square top and `bottomRadius` bottom corners)
sits under the body over the same span. The settled closed notch drops the
mask layer, so its live spectrum and hairline never re-render through an
offscreen texture. With `gpuEffects` off, as under the software renderer and
in the offscreen tests, and on the settled closed notch, the body clips its
content to a rectangle with per-corner radii and the flares carry no
content; without GPU effects the outline also draws the island's `stroke` as
a hairline edge in place of the shadow.

**Ink.** The notch is black in every theme, so everything drawn over it
(the closed row, the peek, the header, the player, Lyrics and the shelf)
reads its colours from `IslandSurface.ink`: a `DesignTokens` built from the
host's theme with `notchColor` as its surface and `light` off. Its text is
always `notchInk` (`#f6f7fb`), whatever the theme's text colour, so every view
on the notch, the calendar included, shares one white; the stroke derives from
it. A theme accent or error that already reads on black is kept (the error at
4.5:1, the accent at 3:1); one that does not falls back to the dark-surface
default. Sizes, the radius and the artwork tint carry over. The font is the
first installed of Inter, Roboto and Noto Sans (checked against
`Qt.fontFamilies()`), or fontconfig's `sans-serif` when none is, unless
`uiFont` is `theme`; none of them is a dependency. Times and the
clock use tabular figures (`numberFeatures`). All island text renders with
Qt's grayscale path (`textRenderType: Text.QtRendering` on the ink), never the
host window's native rendering, which follows fontconfig's LCD subpixel
antialiasing and fringes glyph edges with colour over the black notch; the
host's own windows keep native text. The ink sets
`neutralChrome`: the tab capsule is a 14% wash of the ink, filled controls are
ink with a black label, `tintText` is the ink and the card takes no wash, so
the artwork colour reaches only graphics (the spectrum, the sliders, the
hairline and the glow). For those, `tint` starts from the artwork colour at a
vibrance floor (`Tint.vibrant`: HSL saturation at least 0.45 and lightness
0.55–0.7, a near-grey kept as it is) and is guarded against black. The legacy
panel (`island:false`) keeps the host's own colours and tinted chrome.

**Morph.** `expansion` follows boring.notch's springs through
[Motion.js](../qml/Motion.js): open is `spring(response 0.42, damping 0.8)`,
which overshoots about 1.5% over the fixed `openDuration` (420ms);
close is `spring(0.45, 1.0)`, critically damped, over the fixed
`closeDuration` (450ms). One linear `NumberAnimation` runs a private
`morphT` from 0 to 1 over that duration, and each step maps it through the closed-form
spring, so the motion is exact and finite and the scene graph goes quiet when
it ends. A reversal mid-flight starts the other spring from the current
`expansion`, so the notch never jumps. Both settle at once under reduced
motion. The legacy panel keeps its own `expandDuration`/`collapseDuration`
(220/180ms), so `island:false` behaves as before.

Only the in-window notch (`islandCard`) morphs; the hosting window is mapped
once at its fixed size, `notchWindowWidth` × `notchWindowHeight`: the open
notch plus `shadowPad` (20px) on each side and below it, plus a 10px
`morphSlack` strip for the overshoot. The notch height uses the raw
`expansion` toward `restHeight` (`openHeight`), so the overshoot only drops
it a few pixels into the slack and settles. Its width, flare, bottom radius
and the content opacity use `clampedExpansion` (0..1), so nothing is clipped
at the window sides. The closed content is gone by expansion 0.4
(`pillFadeEnd`); the expanded column fades in over 0.35 to 1
(`contentFadeStart`) and scales from 0.8 (`openScaleFrom`) about its top
centre, and with `gpuEffects` on it also sharpens from a `MultiEffect` blur
(`entranceBlur`, 30px) to none over the same range. The blur layer exists
only while the blur shows.

**Input region.** `islandHitShape` masks the notch body: closed,
`liveWidth − 2·flareClosed` wide and bar high; open,
`openWidth − 2·flareOpen` wide and `openHeight` tall. It excludes flares,
slack and shadow room. `extendHoverArea` adds a separate 8 px strip below the
closed body for hover, without a tap, wheel or drag handler; the strip and the
body share one hover dwell, which keeps running as the pointer crosses from one
to the other. Wayland still
directs clicks there to the layer window. These regions jump on state changes
and never animate, so the mask does not resize per frame.

Home and the Lyrics view both fit the 190px open body; the Lyrics state
message lays out in one row (icon, text, Try again) on a stage that short.

**Artwork colour.** In island mode with `tint` on and `highContrast` off,
`Panel.qml` runs Quickshell's `ColorQuantizer` (depth 3, so 8 colours, at
48px) once per artwork change on the helper's sanitized artwork file, through
the same `SourceState.artworkUrl` rule the artwork itself is drawn with (the
helper publishes a `file://` URL). It is the only quantizer in the plugin, and
`tests/source-contract.py` pins both. It runs whenever the helper publishes a
path: a player's local cover file, or a web cover with `remoteArtwork:true`.
[Tint.js](../qml/Tint.js) picks the most vivid colour: it skips colours with
HSL lightness below 0.12 or above 0.92, or saturation below 0.18, and scores
the rest by saturation, favouring a lightness near 0.55. A greyscale cover
yields no colour. The pick becomes `DesignTokens.artColor`, which eases over
400ms (`tintDuration`, `OutCubic`), starting from the accent rather than from
transparent. `DesignTokens` derives these from it, each checked against the
live Omarchy palette, because the theme can change at runtime:

- `tint` colours the spectrum bars, the pill hairline, the progress and volume
  slider fills, the art glow, the pill's play-state glyph and HUD level, the
  source icon and the source picker's selection. It must reach 3:1 against
  `surface`, and against the card washed with the tint at its strongest alpha
  (below), since that card is what these graphics sit on (WCAG 1.4.11). If it
  falls short, its HSL lightness steps by 0.04 away from the surface, at most
  12 times, and falls back to `accent` if no step passes.
- `primaryFill` and `primaryLabel` fill the primary buttons (play/pause, Try
  again), the shelf count and a settings
  switch that is on. The label is the art colour's own hue at HSL lightness
  0.1 on a dark theme or 0.97 on a light one. The fill takes the same 0.04
  lightness steps until it reads as a graphic (as `tint` above) and the label
  reaches 4.5:1 on it (WCAG 1.4.3); if twelve steps are not enough, the pair
  is `accent` and `accentLabel`.
- `tintText` colours the source eyebrow: the art colour at 4.5:1 against the
  card, stepped the same way, or `accent`.
- Focus rings stay on the theme accent, so the keyboard focus looks the same
  on every cover.
- `cardSurface` mixes the tint into `surface` at alpha 0.10 on a dark theme or
  0.07 on a light one. It uses the first of those alphas, then 0.05, that keeps
  `text` at 4.5:1 and `secondary` at 3:1, and stays untinted otherwise. The
  legacy card uses it, and so do the island's overlays; the notch itself is
  always `notchColor`. `surfaceRaised` and `surfaceSunken` build on it, so
  raised rows and slider tracks carry the same wash.
- `glow` shows [ArtGlow.qml](../components/ArtGlow.qml) behind the cover
  without GPU effects: three concentric rounded rectangles (`glowRings`,
  offsets 3/6/9px at alpha 0.20/0.10/0.05), with no blur or shader. The Home
  player uses the blurred copy instead when GPU effects are on.

With no artwork, a greyscale cover, `tint:false`, `highContrast:true` or the
legacy panel, `artColor` is transparent. Then `tint` and `tintText` are
`accent`, the primary pair is `accent` on `accentLabel` (the theme's
`onAccent`), `cardSurface` is `surface` and there is no glow, which is
exactly the untinted look.

**Settings.** The [settings and configuration guide](settings.md) owns the schema,
defaults, storage, Settings window, and About behavior. It also documents
the `configure` route and every visible setting.

**Welcome.** When the island first becomes usable and the settings file has no
`onboardingDone`, the Service opens
[OnboardingWindow.qml](../components/OnboardingWindow.qml), a fixed 400×600
window (floating and centred, like the settings window) with seven steps
from the pure machine in [Onboarding.js](../qml/Onboarding.js):

- **Welcome**, with the idle face.
- **The idle notch**: a preview of Glance, Face, Horizon or the empty notch
  that follows the `idleStyle` choice, and Online artwork, which says a
  player's own cover always shows.
- **Media**: the source picker in its remembering mode (the choice becomes
  `preferredSource`; Auto forgets it), then Synced lyrics and Track peek. A
  choice that cannot be saved keeps the picker open and says why, from
  `configureError`, so nothing looks remembered that is not.
- **Calendar**: Calendar on Home and "Add a calendar", which opens the
  Calendar settings.
- **Camera mirror**: the camera test (a live preview that starts only after
  Test camera is pressed and stops on leaving the step) and Mirror on Home.
- **Keys and placement**: the summon line with Copy and the SUPER+M conflict
  check, and, while `islandOffCentre`, how to make the island the bar's
  centre anchor.
- **All set**: Customize in Settings and Finish.

A step's choices are the settings window's own rows
(`Onboarding.STEP_SETTINGS`, written through `configure`), so nothing changes
until the person picks and a skipped step keeps its defaults. The buttons are
the island's (`SettingsButton`), with Next and Finish filled. Next holds the
focus; Return presses the focused button or moves on, and Escape closes,
counting the steps not reached as skipped. Every step can be skipped, and
Skip all goes straight to Done; steps fade and slide for 600 ms (`InOutCubic`,
instant with reduced motion). Finishing or closing the window writes
`onboardingDone: true`, so it is offered once; About in the settings window
offers it again. If a lock interrupts an unfinished welcome, it opens again
when the island becomes usable.

The Service owns both windows. They open only while the panel is allowed, and
a lock, retirement or dispose closes them. Two IPC verbs open them and return
`ok`, or `unavailable` while locked:

```sh
omarchy-shell nookisle settings     # the settings window
omarchy-shell nookisle onboarding   # the welcome steps again
```

The island's header gear opens the window directly. Asked again while the
window is open (it may be on another workspace), the Service unmaps it and
maps it again on the current one, on the section asked for or the one it
showed. The legacy panel keeps
its inline settings view and its "All settings…" button.

**Idle face.** [IdleFace.qml](../components/IdleFace.qml) draws boring.notch's
face (eyes, nose and smile, 30×20, scaled to its size) and blinks every 3 to
7 s in four steps: half shut, shut (held 100 ms), half shut, open. A 4px eye
has only a few visible heights, so four redraws look the same as a tween
and cost a tenth of one. The blink re-arms a single-shot timer and runs only
while the face and its host window are visible, under no reduced motion and
in the neutral mood; the source contract pins that gate. The closed notch's
face also has moods: sleepy from 23:00 to 06:00 (low eyes, no blink, by an
hourly single-shot clock that runs only while it is shown), happy for 3s
after a charger banner and worried for 3s after a low or critical one; a
mood change is one step, never a tween. With no source, Home shows it at 80×70 in
the cover's place as the nothing-playing state. With `idleStyle: face`, the
closed notch shows it while nothing plays.

**Home glance.** Connected with no source to show,
[HomeGlance.qml](../components/HomeGlance.qml) takes the player title's place
beside the face: the time at 34px (the locale's short format, tabular
figures), the date ("Sunday, 27 September") and, with `showCalendar` on, the
event happening now or next today ("Now", "In 20 min" under an hour, or its
start time, then its title; `Calendar.nextEvent`). The status line and the
Sources button stay under it; there is no scrubber and no button row. The
time moves on with a one-shot timer armed to the next minute, and only while
the glance and its window are visible. A lost pinned source or a lost
connection keeps its explaining title instead. A paused or stopped player is
not idle: Auto keeps it selected, so Home shows the full player with the
paused cover, whose single tap resumes playback. That affordance is the
design, so the glance has no separate resume chip.

## Displays

`displayMode` (General) picks where the island shows: `follow`, the default,
keeps one island on the focused screen, moving it only while it is closed;
`fixed` keeps it on `preferredDisplay`, and follows focus while that screen is
not connected; `all` shows an island on every screen. In `all` the island on
`preferredDisplay` (or on the first screen) takes the keyboard summon, only
the visible island under the pointer draws the live spectrum (with the pointer
on none, the primary, or the first visible island while the primary is hidden,
so exactly one visible island does), and only the island opened last runs the
camera (`Displays.cameraOpenOrder`); closing it hands the camera back to the
island opened before it that is still open, so an open mirror never stays dark.
An island whose screen is unplugged while open is dropped from that order when
the screens change, so the screen's new island after a reconnect does not
take the camera until it is opened. The spectrum pauses only while that island itself is open, so another
open island does not freeze its bars. Each island hides over fullscreen on its
own screen, and a HUD bar held on one island latches only that island's
fullscreen state; the hold ends if that island goes with its screen. The
progress subscription and the spectrum stay on while any island is visible,
the shared level readout and peeks are suppressed only when no visible island
can show them, and each bar's centre peek is suppressed by the visible island
the pointer is on (else an open one). The settings window offers `preferredDisplay` as
Automatic plus the connected screens, and keeps a stored screen that is not
connected, marked "(not connected)". Every bar's spacer stays as it is. See
[architecture](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/architecture.md#host-and-session-constraints) for the windows
behind `all`.

## Gestures, keys and verification

See the [interaction reference](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/interaction-reference.md) for media-key readout ownership, pointer and keyboard gestures, and the verification suites.
