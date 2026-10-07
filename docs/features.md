# Island features

The island's features beyond the notch itself: the level readout, peeks,
battery, privacy indicators, timers, screen recording, screenshots to the
shelf, lyrics, the shelf and the calendar. The notch shell, the header, Home,
gestures and keys are described in the [interaction reference](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/interaction-reference.md); defaults and
controls are in [settings and configuration](settings.md).

## Level readout

Volume, brightness, keyboard-backlight and microphone changes show a level
readout for `hudDuration` (1.5s by default), in the style `hudStyle` picks.
[VolumeSource.qml](../components/VolumeSource.qml)
feeds [HudModel.qml](../components/HudModel.qml), which keeps a silent first
sample for each sink. The panel requests the first ready volume sample after
its loader connects the source, so the next volume change displays a readout
even after reloading it. When the selected output is a DSP sink, the volume
source follows its output stream to the downstream sink that Omarchy's volume
keys change. Its readout, wheel steps and bar drags all use that resolved sink.
[BrightnessSource.qml](../components/BrightnessSource.qml)
owns discovery, sysfs reads and `brightnessctl` writes; display change events
come from the helper's udev watch while the HUD is on.
It selects `gmux_backlight`, then `amdgpu_bl*`, `intel_backlight`,
`acpi_video*`, then another valid display backlight, excluding the Touch Bar's
`appletb_backlight`, with a nonzero `max_brightness`. A valid `backlightDevice`
override takes precedence. It discovers the first keyboard
`*kbd_backlight*` LED. Display writes never go below 1%, so the panel cannot
be blanked; the keyboard level may reach 0 (off). LED brightness changes emit
no uevent, so no monitor watches the keyboard. Instead, the installed keyboard
bindings call the `keyboardBacklightChanged()` IPC verb after changing the
level, and the source re-reads the LED's sysfs level and emits one `keyboard`
event. The verb returns `ok`, or `unavailable` when the HUD is off or no
keyboard LED was found. Before acting, the bindings' helper asks
`hudReadout(kind, device)` whether the island will draw the key's readout. It
answers `ok` only with `hud` on, the island on screen, its
readout not suppressed (Panel publishes `HudModel.suppressed`, which covers
fullscreen and an open island with `showOpenNotchHud` off) and the plugin
admitted; for `keyboard` the source must have found an LED, and for
`brightness` its display monitor must be running on the same backlight the key
changes. Any other answer sends the key to Omarchy's own command and OSD.
Without the bindings block, Omarchy's own OSD handles the keyboard keys. The Service activates the source only with the HUD and
island admitted, forwards its `brightness` and `keyboard` events, and keeps the
`brightnessHud` status field as a thin monitor-running proxy.

[MicSource.qml](../components/MicSource.qml) watches the PipeWire default
input's mute bit and emits a `mic` event with a muted/unmuted label after a
silent baseline. `HudModel` recognizes `volume`, `brightness`, `keyboard` and
`mic`; its `icon`, `label` and `hasBar` fields let the visual layer omit the bar
for mic events. Panel loads MicSource under the same gate as VolumeSource and
shows each of its samples. The optional [media-key bindings](install.md#one-on-screen-display-for-media-keys)
give each key exactly one readout: the island's, or Omarchy's OSD when the
island will not draw one.

The styles all take Panel's one `HudModel`:

- **Inline** (`hudStyle` `inline`, the default): `ClosedModel` enters
  `hudInline`, the closed notch springs to `hudInlineWidth` (380px), and
  [HudInline.qml](../components/HudInline.qml) draws the icon and label in the
  left wing and the bar (with a percentage when `hudPercentClosed` is on) in
  the right.
- **Below** (`below`): the notch keeps its state, and
  [HudBelow.qml](../components/HudBelow.qml) shows a 230 × 36px pill 4px under
  it.
- **Open**: while the island is open and `showOpenNotchHud` is on (the
  default), [HudCapsule.qml](../components/HudCapsule.qml) replaces the
  header's right-hand slots for the readout's life, with a percentage when
  `hudPercentOpen` is on. The readout is then not suppressed by the open
  island; with the setting off it is, as before.

`hudAccent` (off by default) draws the level bar in the accent colour instead
of the text colour. `hudGradient` shades its fill; `hudGlow` adds a soft halo.
Both appearance switches start off and apply to the inline, below and open
header styles.

The HUD is suppressed over fullscreen (see below), and never while its bar is
held. Nothing that happens mid-drag takes the bar from under the pointer: an
open of the closed notch (a keyboard summon, a drop) waits for the release,
ordinary closes of the open island (the leave grace, a summon auto-close, the
host's toggle) wait for it too, while Escape and the host's resets still win,
and Panel keeps the fullscreen value the drag started with until the release.
An event of a different HUD kind cannot replace the held bar.

**Draggable bar.** The shared [HudBar.qml](../components/HudBar.qml) takes a
press or drag and asks for that level: `volume` goes to
`VolumeSource.setVolume`, which clamps to 0–100% and unmutes on a change, like
the media-keys helper, and `brightness` and `keyboard` go to
`Service.setBrightnessLevel(kind, value)`. The bar previews the level, renews
the dismissal while dragged, and holds the readout (`HudModel.held`) while
pressed. A display-brightness preview and request never go below 1%, and
after each completed `brightnessctl` write BrightnessSource re-reads the
level, so the bar settles on the value the device applied.

**HUD input.** While a closed readout with a bar shows, its rectangle
(`IslandSurface.hudHitShape`: the inline HUD's resting body, or the lower
pill) joins the notch body in the window's input region as its own nested
`Region` in `Panel.qml`'s mask. `tests/source-contract.py` names it alongside
the separate drag catch region. It takes the resting
geometry at once, never the springing notch, and comes and goes in one jump.
A mic readout, which has no bar, never grows it. Inside that rectangle the
pointer never starts the open dwell, and entering it stops a dwell already
running; a tap there never opens the island, and a wheel there is not a
volume step or a skip. Leaving it for the notch body starts the dwell as
usual. A move with a button held, on the HUD or not, stops the dwell and never
starts it.

`fullscreenBehavior` is stored as `always`, `nowPlayingOnly` (default), or
`never`. [FullscreenPolicy.js](../qml/FullscreenPolicy.js) returns whether a
fullscreen client should hide the island. The selected endpoint supplies its
MPRIS `DesktopEntry` or, for a Chrome document, the browser class. The pure
policy requires an exact class match after case normalization and removal of
the optional `.desktop` suffix. `Panel.qml` applies it to the
fullscreen client on the island's own monitor: it reads that client's class
from `lastIpcObject` of the active workspace's toplevels, asks Hyprland to
refresh them whenever the workspace or its fullscreen state changes, and
re-evaluates when the selected source changes. The result drives everything
that already read "fullscreen": the island's visibility, its interactivity and
the HUD and peek suppression, and an explicit open still overrides it.

## Idle notch

While nothing plays, `idleStyle` picks what the closed notch shows.
No idle style covers a bar module: each fits the 280px the spacer reserves.

- `glance` (the default, [IdleGlance.qml](../components/IdleGlance.qml),
  rules in [Idle.js](../qml/Idle.js)) fills the whole body with a 6px dot in the
  accent and one line, kept balanced: while the battery pip or a trailing
  activity shows, the dot sits at the left inset and the line centres in the
  space left for it; otherwise the dot hugs the line (8px before it) and the
  two centre as one group. The privacy dots never break that group: a line
  that fits keeps its place, and one too long for the narrower room left
  beside the dots is elided and the dot and line recentre together. The line shows
  the time and date (`14:05 · Sun 27 Sep`), or only the weekday and date when
  the host bar has an `omarchy.clock` module (`idleClock: auto`; `time`,
  `date` and `off` fix it). With `showCalendar` and `idleNextEvent` both on,
  the event under way or the next one within the hour takes the line
  (`Event · in 15 min`, `Event · now, until 14:30`) and the dot and hairline
  take its calendar's colour; the line turns to that colour in the last five
  minutes, and the event is named only with `idleEventTitles` on. A 12px
  battery pip ([BatteryPip.qml](../components/BatteryPip.qml)) shows at the
  right inset only while charging, in power saver or at 20 % or less on
  battery, filled in the gauge's colour; the bar shows the battery the rest
  of the time. The hairline (`idleHairline`, on by default) fills with the
  day's progress, the countdown over the last hour before an event, or the
  elapsed part of an event under way. The day's progress is a faint neutral
  grey (the muted notch ink at 35 %), so it never reads as the tinted track
  progress it takes over from, and it fades in over 400ms when the glance
  appears, so the handover never jumps; an event's hairline keeps its
  calendar's colour. The clock steps once a
  minute through a single-shot timer re-armed to the next minute, only while
  the glance is shown, so the idle notch redraws about once a minute and
  runs no loop; the glance loads only while shown.
- `face` centres the idle face in a 233px notch (boring.notch's face width
  at the 26px bar); with `hardwareNotch` on it takes the right wing, as in
  boring.notch.
- `horizon` shrinks the notch to 120px with one 40px accent line where the
  progress hairline sits, and the battery pip under the same rule. Nothing
  moves.
- `empty` is boring.notch's bare 185px base notch.

With `hardwareNotch` on, no idle style draws in the camera gap. The glance
keeps its 280px and splits into the wings: the line's first part (the time,
the weekday or the event) ends 6px short of the gap on the left, the dot and
the pip sit past it on the right, and the hairline, which would cross it, is
left out. Horizon, which would sit wholly inside the cutout, leaves the
empty 185px base notch.

The closed notch's accessible name says what it shows: the track and whether
it plays, a banner's label, the glance's line, or "Nothing playing".

## Peeks

A peek blooms the collapsed pill for a few seconds without taking focus or
input. [PeekModel.qml](../components/PeekModel.qml) is the pure QtQuick state
machine behind it (qmltestrunner drives it offscreen);
[IslandPeek.qml](../components/IslandPeek.qml) draws it inside the island
card, and `Panel.qml` feeds the model and passes its state to
`IslandSurface`.

- **Track peek** (`peek`, off by default). A new `trackToken` on the selected
  source, stable for 250ms so a player that sends title and artist in
  separate updates peeks once, blooms a 300x64 card for 3s
  (`trackPeekDuration`): the 44px art with its glow, the title and artists,
  24px live spectrum bars, and the progress hairline under the text. The
  track token changes only with the track id, title or artists, so artwork,
  position or volume updates never peek. The first track seen, an empty
  token and a switch to another source only set the baseline.
  `peekStyle: "standard"` uses this card; `"inline"` puts the title and
  artist in a pill-height row beside the closed notch. A paused player keeps
  its live row for `pauseGrace`, the one media timeout for the closed notch.
- **Power peek** (`power`, on by default). Plugging the charger in
  ("Charging", or "Fully charged" at 100%) or out ("On battery"), and
  discharging past 20% ("Battery low") or 10% ("Battery critical"), bloom a
  pill-high 300px row, with `powerStyle` `peek` (with the default `banner`
  they widen the closed notch instead; see the battery banner below), for 2.5s (`powerPeekDuration`): a bolt or a battery
  glyph filled to the level, the label, a 72x4 level bar and the percentage.
  Low and critical use the theme's error colour. "Charging" and "Fully
  charged" use `charging`, a green (`#5fd38d` on a dark theme, `#1a7f37` on a
  light one) stepped in lightness until it reaches 4.5:1 on the card, so the
  bar and the percentage both read; the text colour if it cannot. "On
  battery" uses the text colour. A plug-in pulses the bolt once: it swells to
  1.3x and a ring spreads to 1.5x and fades, 120ms after the bloom starts and
  over about 600ms, with no pulse under reduced motion.
  Each threshold fires once and re-arms only after the level climbs 2 points
  above it, or on a plug. The first sample, a level already below a
  threshold at that sample, and a machine without a laptop battery never
  peek. [PowerSource.qml](../components/PowerSource.qml), the only file that
  imports `Quickshell.Services.UPower`, reports the display device's
  `ready`, `isLaptopBattery`, `isPresent`, `percentage` (0..1) and
  `UPower.onBattery`; `Panel.qml` loads it only with `power`
  on, and resets the power baseline on every load.
- **Device peek** (`deviceEvents`, `audio` by default). A Bluetooth device
  connecting blooms a pill-high 300px row for 2.5s (`devicePeekDuration`):
  its glyph, its name, "Connected", and a 48x4 battery bar with the
  percentage when BlueZ reports the device's battery (a headset does only if
  it sends it; without it the bar and the percentage are hidden). A device
  already connected at load, a disconnect, and a device reconnecting within a
  minute of its last peek (the storm after a resume) never peek. A connected
  device whose battery reaches 15 % warns once in the error colour, and again
  only after it climbs over 20 %. `audio` limits both to headsets,
  headphones and speakers, so a mouse or keyboard waking with the laptop stays
  quiet; `all` includes every device. [DeviceSource.qml](../components/DeviceSource.qml),
  the only file that imports `Quickshell.Bluetooth`, reports raw samples;
  [qml/DeviceEvents.js](../qml/DeviceEvents.js) holds the rules.
- **Output peek** (`outputPeek`, on by default). A switch of the resolved
  sound output (the device behind any DSP sink) shows its name and "Sound
  output" with a headset, display or speaker glyph. The first real output
  after a load is a baseline: while PipeWire is still resolving the sink,
  nothing is recorded, so its arrival never peeks. The level readout's source resolves the output, so the
  peek needs `hud` on. A connect and the output switch it causes, either way
  round within 1.5s and for the same device (a `bluez_output` sink carries
  its address), are one peek: "Connected · Now playing here".
- **Priority and suppression.** The level readout outranks every peek. Among
  peeks a finished timer outranks power, which outranks a device, then a
  capture, then a track: a peek replaces a showing one it outranks (the card
  eases to the row height and the rows fade one after the other), and never
  one that outranks it; the lower one is dropped, not queued. A peek is suppressed, and a
  showing one ends at once, while the island is hidden, expanded (hover or
  explicit), explicitly opened, over a fullscreen workspace, or showing the
  level readout. Both baselines still advance while suppressed, so nothing
  replays when the suppression ends. `peek:false` and `power:false` end a
  showing peek of that kind.
- **Motion.** `peekAmount` rides the same spring driver as the open notch:
  in on the open spring (0.42, 0.8) and out on the close spring (0.45, 1.0);
  both settle at once under reduced motion, while the 3s and 2.5s are intent
  timings that reduced motion keeps. A power peek replacing a track peek
  eases between the two shapes over 280ms (`peekInDuration`, `OutCubic`).
  The notch's width (`liveWidth` to `peekWidth`, both including the flares)
  and bottom radius (`bottomRadiusClosed` to `peekRadius` for a track peek;
  a power peek keeps the closed radius) follow the clamped amount, and its
  height the raw amount, so the small overshoot drops into the window slack.
  The peek content is laid out at its final body size and revealed by the
  growing notch, fading in over 0.4 to 1 and scaling from 0.96 about its top
  centre, after the closed content has faded out by 0.4. Expanding mid-peek
  grows the notch on from the peek shape, never back through the closed
  notch.
- **Input.** The input region (`islandHitShape`) stays the closed body during a
  peek. The peek body beyond the closed body, up to 10px each side and below
  the bar, is visual only: it never takes a click, and a peek appearing under a
  resting pointer never starts the hover dwell by default. With
  `extendHoverArea` enabled, the extra 8 px hover strip below the closed
  body can start it. Tap and hover on the pill area work as usual during a peek.

## Battery

[PowerSource.qml](../components/PowerSource.qml), still the only UPower
reader, exposes a `reading` for the battery UI: `present`, `onBattery`,
`level` (0..1), `state` (a UPower state name), `timeToEmpty` and `timeToFull`
(seconds), `health` (percent of design capacity from the first laptop battery
that reports it, or -1) and `powerSaver`. It also resolves `powerCommand`, the
first Omarchy power program on `PATH` (`omarchy-launch-power`, then
`omarchy-shell shell toggle omarchy.power`, the command behind Omarchy's own
SUPER+CTRL+P), and `openPowerSettings()` runs it.

The rules live in [Battery.js](../qml/Battery.js) and the state in
[BatteryModel.qml](../components/BatteryModel.qml), pure like `PeekModel`:

- The fill colour, most urgent first: amber in power-saver mode, red at 20 %
  or below on battery, green while charging, plugged in or full, otherwise
  white.
- `note(reading)` takes each reading; the first after a load or
  `resetBaseline()` is a baseline. A charger plug or unplug on a present
  battery then emits `bannerRequested(kind, level)` once (`plugged` or
  `unplugged`) and holds `bannerActive` for `bannerDuration` (3 s), restarted
  by a newer change. With `powerStyle` `peek` there is no banner, and the
  existing power peek shows the change instead.

[BatteryGauge.qml](../components/BatteryGauge.qml) is the 30×12 gauge with an
optional percentage, and [BatteryPopover.qml](../components/BatteryPopover.qml)
shows the percentage, state, time estimate, health and power-saver, with a
"Power settings" button only when `powerCommand` is set.

`Panel.qml` feeds each PowerSource sample to `BatteryModel`
(and to `PeekModel`). The open header shows the gauge in its battery slot
while a battery is present, `power` is on (it loads the reader) and
`showBatteryIndicator` is on; a tap opens the
popover under it, over Home, and Escape, another tap or closing the island
closes it. The popover stays below the header and scrolls its details when
they exceed the open body's height, showing a vertical scroll indicator when
there is more to see. With `powerStyle` `banner` (the default), a charger plug
or unplug, and discharging past 20 % or 10 %, widen the closed notch to the
`battery` state (`batteryBannerWidth`, 640px, or the HUD width where that does
not fit) for 3s. The label sits on the left and the header's battery gauge
on the right, each 12px from the middle of the body (or from the camera gap
with `hardwareNotch` on), as boring.notch hugs its notch. The gauge keeps
its colours (green charging, red low, amber power saver), its status mark
(`showPowerStatusIcons`) and its percentage (`showBatteryPercent`). A plug-in
says what UPower reports: "Charging", "Fully charged", or "Plugged in" when
the battery is not charging (a charge limit); an unplug says "On battery",
and the warnings "Battery low" or "Battery critical". The banner never
grows the input region. With `peek`, `PeekModel` shows its power card instead,
and only then: its power peeks, warnings included, are off in banner style.
Both styles take the warning from the same threshold crossing, so each warning
shows once, and `showPowerNotifications` turns both off.

| Key | Type | Default | Purpose |
|---|---|---|---|
| `showBatteryIndicator` | bool | true | the gauge in the open header |
| `showBatteryPercent` | bool | true | the percentage beside it |
| `showPowerNotifications` | bool | true | charger and low or critical battery banners (with `banner`) or peeks (with `peek`); the gauge remains available when off |
| `showPowerStatusIcons` | bool | true | charging, low and saver marks within the gauge |
| `powerStyle` | `banner` or `peek` | `banner` | how a charger change or a battery warning shows |

## Privacy indicators

With `privacyIndicators` on (the default), the closed island shows who is
capturing, as iOS and macOS do: a column of 4px dots at its trailing end,
orange for the microphone, green for a camera and blue for the screen, top to
bottom. The right wing's content moves in 6px beside them; the notch keeps its
width. A microphone that is captured while it is muted shows a slashed mic
instead of its dot ("you are muted in the call"), and the content moves in
11px; a muted microphone that nothing uses shows nothing. The dots fade in and
out over 150ms and never move. [PrivacyDots.qml](../components/PrivacyDots.qml)
draws them above the closed row, the peek and the inline HUD, at the body's
trailing end, so they show in every closed state: beside music, an activity,
idle, the battery banner, a peek and the level readout. They leave only as
the island opens. Open,
without a camera cutout, the header's centre names the apps in a chip, such as
"Mic: Firefox · Camera: Chromium", which is also the dots' accessible name.

[PrivacySource.qml](../components/PrivacySource.qml) reads the local
PipeWire graph: a microphone capture is an input stream linked from an audio
source, so a capture of a sink monitor (the island's own spectrum, cava, a
desktop-audio recorder) never counts; a camera is a stream linked from a
`v4l2_` or `libcamera` video source, and a screen cast one linked from any
other video source, such as xdg-desktop-portal-hyprland's. Node types and links
need no tracking; only the capture streams in use are tracked, for their
application names ([qml/Privacy.js](../qml/Privacy.js)). Apps that open a
camera without PipeWire, as browsers usually do, are found by the helper's
camera watch (see the [protocol](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/protocol.md#desktop-signals)), which the
Service runs only while the indicators are on and the island is allowed on
screen. `Panel.qml` loads the source only with the setting on.

## Timers

With `timers` on (the default), the island's timers are Omarchy's reminders:
systemd user timers made by `omarchy-reminder <minutes> [label]`. They outlive
a shell restart, Omarchy notifies when one runs out even with the island hidden,
and the bar's Reminder indicator shows the same ones. The Service reads them
with `omarchy-reminder show --json` ([qml/Timers.js](../qml/Timers.js)) when it
starts, after each change the island makes, when the helper sees a reminder
unit come or go (so reminders set from the bar or a terminal appear at once;
see the [protocol](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/protocol.md#desktop-signals)), and once when the soonest
is due. Nothing polls.

- **Closed.** The soonest timer is an activity (see the
  [interface](interface.md#island-interaction)): beside music it is a
  draining ring at the trailing end; alone it fills the notch with the ring,
  its label and the minutes left ("12m", "1h 05m", "<1m"). It steps once a
  minute and never shows seconds.
- **Open.** A stopwatch button in the header (with the soonest timer's
  minutes left beside it while one runs and the header row has room clear of
  the centre), and the timer chip in the header's
  centre, open the Timers view: preset buttons (`timerPresets`), a minutes
  field (1–1440) with an optional label (at most 80 characters) and Start,
  each running timer with its minutes left, its time and Cancel, and the
  armed sleep timer, read-only. Escape or the back button returns to Home.
- **Done.** A timer that leaves the list at its time (within two seconds)
  finished: the notch blooms a pill-high "Timer done" peek with its label for
  6s, which no other peek covers. One that leaves earlier was cancelled.
- **IPC.** `timer(minutes, label)` starts one and answers `ok`, `invalid`
  (minutes outside 1–1440) or `unavailable` (timers off, or no
  `omarchy-reminder`); `timerCancel(unit)` answers `ok`, `invalid` (not a
  reminder unit), `unknown` (not in the list) or `unavailable`. Cancelling
  stops the unit's `.timer` with `systemctl --user` and removes its message
  file. Every command is an argv array, never a shell line. `status()` lists
  the timers' units, labels and times, and also reports `activity`, the
  closed island's shown activities as `"<compact>|<minimal>"` (for example
  `"recording|music"`, or `"|"` for none), and `privacy`, how many apps
  capture the microphone, a camera and the screen (`{mic, camera, screen}`),
  as counts only.

## Screen recording

With `recordingActivity` on (the default), a running Omarchy screen recording
(`omarchy screenrecord`) is the closed notch's first activity, ahead of the
music: a red dot and "REC" on the left, "Screen recording" in the centre when
`hardwareNotch` is off, and its minutes on the right in red ("<1m", "12m"),
stepping once a minute. Music playing at the same time shrinks to its cover at
the trailing end. Open, without a camera cutout, the header's centre shows a
red "REC 12m" chip with Stop, which runs
`omarchy-capture-screenrecording --stop-recording`, the command Omarchy's own
indicator runs. With `hardwareNotch` on the centre stays empty, so a red
record button beside the Timers button in the header's right-hand slots
offers Stop instead. A tap on the closed notch opens the island as usual.

The helper learns of a recording from Omarchy's own marker file (see the
[protocol](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/protocol.md#desktop-signals)): it appears once the recorder
produces output and goes when the video is saved, with the video's path.
Its modification time is the start. At start, a marker left behind by a crash
counts only while `gpu-screen-recorder` runs.

`recordingsToShelf` (off by default, because the shelf may persist) adds each
saved recording to the shelf and blooms a 4s "Screen recording · Added to
shelf" peek (`capturePeekDuration`), ready to drag into a chat. It needs the
shelf and `recordingActivity` on: the helper's recording watch wakes on every
file closed or deleted in `/tmp`, so only the activity runs it.

## Screenshots to the shelf

`screenshotsToShelf` (off by default, because the shelf may persist) adds
each new Omarchy screenshot to the shelf, macOS's floating-thumbnail moment:
the notch blooms a 4s peek with a small thumbnail, "Screenshot" and "Added to
shelf" (`capturePeekDuration`), and the file is ready to drag into a chat or
share. Peeks take no input, which is why it is automatic rather than a tap.
The helper watches the screenshot folder for `screenshot-*.png` files closed
after writing or moved in (see the [protocol](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/protocol.md#desktop-signals)):
`$OMARCHY_SCREENSHOT_DIR`, else the Pictures folder, or `screenshotDir` when
set. A folder that does not exist is refused and nothing is watched. The
thumbnail is decoded once at 48x32; the watch runs only while the option is
on and the island is allowed on screen, and it needs the shelf on.

## Lyrics

With `lyrics:true`, **Lyrics** is a sub-view of Home rather than a tab: the
header keeps Home and Shelf, shows a back chevron while Lyrics is open, and
Escape or the chevron returns to Home. Turning lyrics off while the view
shows falls back to Home. A tap on Home's lyric line opens it.
[IslandLyrics.qml](../components/IslandLyrics.qml) draws the view from
[LyricsSource.qml](../components/LyricsSource.qml), which asks LRCLIB only
while Home or the Lyrics view is open (see [privacy](privacy.md#lyrics)).

**Synced lines.** The view follows the song across its whole card, with a
tinted progress hairline and a footer under the lines: the 20px cover, "Title
· Artists" and, on the right, "Lyrics from LRCLIB" (with nothing playing, only
the attribution):

- the current line, large (`lyricCurrentSize` + 4) and semi-bold in the
  card's text colour, wrapping to two lines;
- the line before it smaller and dimmed, with the one before that fainter;
- the next line in the title size, slightly dimmed, then the one after it
  fainter still.

The current line rests at 40 % of the stage, so the previous line, the
current line and the next line are all fully visible (a long current line
wraps to two lines), and the card's own colour fades the lines out at the
stage's top and bottom edges. In high contrast every neighbouring line is at
least 0.66 opaque.
When the song moves on by a line, the whole group glides up one step while the
next line grows into the current one (scale and brightness), over 360 ms
`OutCubic` (twice `lyricLineDuration`); a seek or a first line fades in with a
6px rise instead. Reduced motion shows every change at once. A line lands 0.15
s before its timestamp, so it shows with the vocal. An instrumental break (an
empty timed line), and the time before the first line, show a single note in
the tint colour.

**States.** Anything that is not a synced song replaces the lines with a short
centred message under a tinted note (an error uses the retry glyph in the
error colour):

| State | Message |
|---|---|
| Looking up | Looking up lyrics… |
| Not found | No synced lyrics for this track |
| Untimed only | Only unsynced lyrics (LRCLIB has the words, but not their timing) |
| Instrumental | Instrumental |
| No length | Lyrics need the track length |
| No title or artist | Nothing to look up |
| Nothing playing | Nothing is playing |
| Lyrics off | Lyrics are off |
| Error | Lyrics could not be loaded, with the reason (LRCLIB busy or limiting requests, timeout, too large, connection) and a **Try again** button |

A busy LRCLIB is asked once more after 2 s before the error shows, and after a
"not found" the lookup tries the track without its album and without a remaster
mark or "(feat. …)" before it gives up. Try again appears for errors only: a
"not found" is kept for the session, and turning lyrics off and on clears it.
The footer always carries "Lyrics from LRCLIB".

On Home the lyric line reads the same state in shorter words ("No synced
lyrics", "Unsynced lyrics only", "Lyrics unavailable" for an error), stays
blank for the first second of a lookup, and offers the view's detail on hover.

## Shelf

The shelf model is [`Service.shelfEntries`](../Service.qml): files, web links
and dropped text (up to 64 KiB), deduplicated by identity key, kept in
insertion order and capped at `shelfLimit` by [Shelf.js](../qml/Shelf.js).
`shelfAdd(uris)` and `shelfAddDrop(urls, text)` add to it; `shelfRemoveItem(id)`,
`shelfClear()` and `shelfAction(name, ids, argument)` change it, where `name`
is one of `open`, `openWith`, `showInFiles`, `copy`, `copyPath`, `compress`,
`rename`, `convert` (`png`, `jpeg` or `webp`), `pdf`, `removeBackground`,
`share` or `remove`. `shelfShareUris(uris)` shares dropped files without
shelving them, and `shelfPickAndShare()` opens `zenity`'s file picker when it
is installed. For tiles, `shelfThumbnailCandidates(id)`, `requestShelfThumbnail(id)`
and `shelfIcons(id)` give validated thumbnail paths and the icon fallback.
The helper checks the cache before generating a missing or stale thumbnail.
A request still pending when its item is renamed or removed is dropped, so the
item asks again and a late answer is ignored. When the helper stops or exits,
expectedly or not, its pending requests are dropped too, and the items it still
owed are asked again as soon as a replacement helper connects. A busy
answer is retried after a short pause, at most three times; then the item keeps
its icon.
Open handles files with `xdg-open`, web links in the default browser, and text
by copying it. Rename runs `mv -T --update=none-fail`: a name already taken, by
a file or a folder, refuses the rename, so the item is never moved into a
folder or over another file. Convert and Create PDF read each image's first
frame only, so an animated GIF or a multi-page file yields exactly the one
output that is shelved, with no numbered frame files left behind.

[ShelfView.qml](../components/ShelfView.qml) is the strip that uses them. It
takes `coordinator` (the Service), `actions` (ShelfActions, for the installed
tools and the Open With apps) and `busyGuard` (any object with
`beginBusy()`/`endBusy()`) as properties. The island's Shelf tab loads it
under the header with the Service's `shelfActions`, the surface itself as the
busy guard (so a menu or rename holds the island open under the close guard),
and its Escape collapse request wired to the surface's Escape close. The
view's implicit height covers the strip and the refusal notice under it, and
the open body gives it that room. While the Shelf tab shows, the island's own
drop area steps aside so drops reach the strip and its notice; on Home and
while closed, a file drop still lands on the shelf through the island. A drag
held over the strip or the Share tile keeps the island open like a drag out. The strip holds:

- a square Share drop tile ([ShelfShareTile.qml](../components/ShelfShareTile.qml)).
  Files dropped on it are shared without being shelved. It accepts only Copy
  after a share starts, so a file manager is never told its file was moved.
  A click opens the
  `zenity` picker when one is installed, and otherwise the tile shows only
  its drop hint;
- the items as 105 px tiles ([ShelfTile.qml](../components/ShelfTile.qml)): a
  56 px thumbnail with 12 px corners (the freedesktop cache, then a
  helper-generated entry, then the theme icon, then a glyph) over a two-line,
  middle-elided name;
- a tray with "Drop files here" when the shelf is empty.

The Share tile and the strip fill the open body's band (the height less a
line for the notice and a 12 px bottom inset, never under 105 px), and the
tiles sit centred in it. The strip is a drop zone with a 3 px dashed outline
with 16 px corners, drawn at rest in white at 10 % and fading to the accent
at 90 % while a drag hovers. Selection follows [Shelf.js](../qml/Shelf.js):
click selects one item, Ctrl-click toggles, Shift-click selects the range
from the anchor, and a background click clears. Selected tiles have an
accent fill at 15 % and a 2 px stroke at 80 %. Space previews the selected
item in an in-strip [panel](../components/ShelfPreview.qml): a larger cached or
helper-generated thumbnail for images, the first lines of a text item, the
host and URL of a link, or the name, MIME type and file size of another file.
File size comes from a bounded `stat` command; the preview does not open the
file in another app. Space or Escape closes the preview, then Escape clears
the selection before it asks to collapse; an open battery popover takes the
first Escape, as on Home. Return opens, Delete removes,
Ctrl+C copies, Ctrl+V pastes (below), and Left and Right move a single
selection.

A drag out carries every selected item: `text/uri-list` with the files and
links, and `text/plain` with any text (or the links). `copyOnDrag` limits the
drop to Copy; otherwise the target may copy or move. `autoRemoveShelfItems`
removes the items once a drop is accepted. A right click opens
[ShelfMenu.qml](../components/ShelfMenu.qml), which is built from
`Shelf.menuEntries` and offers only what fits the whole selection and the
installed tools. The menu key or Shift+F10 opens it on the selection, with
the first entry current. It opens inside the island's input region (the hit
shape, so the input mask never changes for it) and scrolls when it is taller,
so every entry can be reached and clicked; its submenus stay inside the same
region. It holds the busy guard while it is open, and so does the
inline rename editor (Return renames, Escape cancels).

**Catch zone.** While the island is closed and `expandedDragDetection` is on,
a bar-high region centred on the notch, `dragCatchWidth` wide (at least the
closed body, at most the empty bar centre and the open body), catches file or
text drags: a drag entering it opens the Shelf tab. A drag that only passes
through, or is cancelled there, hands the island back to the leave grace, so it
closes as after a pointer leaves. The empty bar centre is
measured by the spacer [BarWidget.qml](../BarWidget.qml): among its ancestors
it finds the host's centre holder and the module rows anchored at each edge,
and publishes twice the nearer gap from the notch centre to a row
(`Service.barCentreSpans`, per screen). When a row or the bar moves or
resizes, it withdraws the span at once (-1, so the catch zone never overlaps a
row that grew) and publishes the new span 250 ms after the rows settle; an
animating row changes the input region once when it starts and once when it
settles, never per frame. When that layout cannot be found, or without a top horizontal bar, it
publishes -1 and the catch zone stays off; the closed body keeps its own input
region either way. The region is part of the layer
input region only while closed, so it jumps once as the island opens or closes
and is never resized per frame. It holds only a drop target, so moving,
clicking or scrolling over the empty bar beside the notch does nothing to the
island, but the bar cannot take clicks there either. On Omarchy's bar that
means its centre gestures do not work inside the zone while the island is
closed: dragging the empty centre to move the bar, double-clicking it to
toggle the bar's transparency, and the bar's own centre hover. They still work
on the empty bar outside the zone. Turn `expandedDragDetection` off, or narrow
`dragCatchWidth`, to give that space back to the bar. A Wayland input region
decides pointer and drag-and-drop focus together, so the zone cannot catch
drags and pass clicks through. It exists only while the
bar's centre section holds nothing but the island's spacer
([CatchZone.js](../qml/CatchZone.js), read by Panel from the bar layout), so it
never covers another centre module. The source contract pins that it holds
only a drop target and that Panel unions it into the mask.

These components use
no GPU effect: the thumbnail corners are drawn with a ring in the tile's own
colour, and the outline is a path, so they look the same under the software
renderer.

The strip shows the existing shelf notice when a drop is refused. It reports
an accepted Copy only when an item was added.

Ctrl+V is the one way in without a drag, for a keyboard user or when no file
manager is open. The clipboard is read only on that press.
[`Service.shelfPaste()`](../Service.qml) runs a one-shot `wl-paste --type
text/uri-list` and shelves each local file and http(s) link on the list, as a
dropped URL would be. Only when the clipboard offers no `text/uri-list` does it
run a second one-shot `wl-paste --type text`, and shelve that text as a drop's
text is shelved: a single web URL becomes a link, a local file URI a file,
and other text a text item. Each read is capped at 131,072 JavaScript string
code units and killed after 5 seconds, and a text item holds at
most 64 KiB of UTF-8; longer text is refused. A press while a read is running
reports the clipboard as busy. A missing `wl-paste`, or a clipboard with
nothing the shelf can keep (only an image, for instance), states the reason in
the notice under the strip. Pasted items are kept like any other shelf item:
in memory, and in `shelf.json` only while `shelfPersist` is on.

Nobody has yet dragged a file into or out of the island in a live session
(see the [support matrix](support-matrix.md#dynamic-island)). Both paths ship
enabled (`Panel.qml`'s `shelfDropInSupported` and `shelfDragOutSupported`,
both `true`): an untriggered drop area costs nothing and cannot misreport
state, and Paste and Copy are the proven route in and out either way.

## Calendar

[CalendarPanel.qml](../components/CalendarPanel.qml) fills Home's calendar
slot. It reads `items` from its `source` (a
[CalendarSource](../components/CalendarSource.qml), or a fake in the tests),
the source definitions from `sources`, the settings from `options`, and the
clock from `now`. Each time Home shows it
(the island opens on Home, the Home tab returns, or `showCalendar` turns on),
Home calls `refresh()`, which takes the current time and returns the
selection, the wheel and the list to today. A one-shot timer moves it to the
next local day at midnight and requests a fresh helper window; a reveal after
midnight does the same. Beside the mirror it uses its
170 px list (`compact`), otherwise 215 px.

- The month in semibold and the year in light weight, above a horizontal,
  snapping day wheel from 7 days back to 14 ahead: 20 px day circles, today
  in the accent colour, the selected day filled.
- The selected day's list, 120 px tall and 215 px wide (170 with `compact`,
  when the camera shares Home): a 3 px bar in the source's colour, the title
  and the time (`All day`, `Due 18:00`, or `09:00 – 09:30`) with the location.
  All-day rows come first, then by start.
- A reminder sits at its due time (an all-day one on its due date), or at
  its start when it has none.
- A row whose recurrence rule is outside the supported subset shows a small
  repeating-pattern warning. Only its first instance is known to the helper.
- A reminder has a 14 px check circle, filled with an 8 px dot when
  completed; clicking it calls `source.setCompleted(sourceId, uid, !completed)`.
- Source errors and failed reminder changes appear as a short message above
  the event list, using the calendar error text. The list remains usable.
- Showing today, the list opens at the event happening now, else the next
  one still ahead (`autoScrollToNextEvent`).
- An empty day says "Nothing on today" (or "on this day"). With no calendar
  configured at all it says "No calendars yet" with a tonal Add calendar button,
  which opens the settings window on Calendar.
- The dimmed shades of its white text (the year, weekdays, times, completed
  reminders) turn fully white in high contrast.
- Clicking a row opens a local source's file or folder with
  `Qt.openUrlExternally` (xdg-open). Remote sources open nothing, so a Google
  secret address never reaches a browser history.

The rules are pure, in [Calendar.js](../qml/Calendar.js), including the
helper's source id (the first 16 hex digits of the SHA-256 of kind, path, url
and user), so the panel and the editor can match items and errors to their
source definitions.

| Key | Default | |
|---|---|---|
| `hideCompletedReminders` | true | leave finished reminders out |
| `hideAllDayEvents` | false | show only timed events |
| `autoScrollToNextEvent` | true | open today's list at the current or next event |
| `showFullEventTitles` | false | wrap long titles instead of eliding them |
| `calendarSelection` | `[]` | source ids to show; empty shows all |

[CalendarSourceEditor.qml](../components/CalendarSourceEditor.qml) edits
`calendarSources` for the settings window. It lists each source without
printing a secret (a path, `host (link hidden)` for an iCal link, `user @
host` for CalDAV), adds one of the four kinds, removes one, and tests one.
Both remote opt-ins, "allow this server" and "local network", start off for
every new source. A link with a user name or password before its host is
refused with a hint to use the user and password fields
(`Settings.hasUserinfo`, applied by `Calendar.makeSource` and
`Settings.checkSource`).

- **Test** calls `CalendarSource.testSource(id)`, the helper's `calendarTest`
  verb, which loads that one source afresh; the row shows "Testing…" until
  that answer arrives, then "Connected" or the error. A source already being
  tested is not asked again.
- **Password.** A CalDAV password goes only to
  `CalendarSource.storeCredential`, and the field is cleared at once. The
  editor reports whether the store succeeded; after a successful store the
  helper refetches every source with that account.
- **Removal.** The Service's `removeCalendarSource(definition)` does it, so
  it completes whether or not the settings window stays open or the island
  shows, and across a restart. One settings save writes the list without that
  source and, if no remaining source uses the same CalDAV url and user, that
  account's identifiers in the internal `calendarPendingClears` key (never a
  password); `configure()` returns only once it is on disk, so a failed save
  removes nothing and clears nothing. The Service sends a clear for each saved
  account whenever the helper connects, forgets it when the helper answers
  (`calendarClearFinished(url, user, ok, error)`, which the editor reports
  while open), and drops an unsent one when the account is added again. A
  clear already with the helper cannot be recalled: a password store for that
  account waits in the Service until the clear is answered, and the editor
  asks for the password again when such an account is re-added. This clear is
  the one `calendarCredential` message the Service composes; `CalendarSource`
  owns every other calendar verb.

[CalendarSource.qml](../components/CalendarSource.qml) sends one request at
a time. User actions (completion, credentials, tests) wait in its queue while
it is busy and go out in order; `credentialFinished(requestId, action, ok,
error)` and `testFinished(requestId, sourceId, ok, error)` report their
answers. Testing and passwords need the calendar source, so they wait until
the calendar is enabled with UI admission. Hiding the island keeps the source
configured; remote sources refresh on `calendarRefresh`, not every reveal.

## Calendar sources

[CalendarSource.qml](../components/CalendarSource.qml) is the only QML sender
of the helper's calendar requests; the Service passes them through
`calendarSend` only while the calendar is enabled with UI admission. Besides
configuring sources, paging the day window and completing reminders, it can
store or clear a CalDAV password. The helper also accepts a test of one
source, which the source editor sends through CalendarSource. A test reloads that
source afresh and answers `ok` or an error code (`auth-error`,
`network-error`, `private-address`, `timeout`, `too-large`, `not-found`,
`secret-service-locked`, `secret-service-unavailable` and the parser's codes)
once the load finishes. `secret-tool` may take up to 60 s, so the user can
answer a keyring unlock prompt; a prompt left unanswered reports
`secret-service-locked`, not a refused password. Storing a password reloads every
source of that account and then announces the change, so the window refreshes
without a second request. Clearing a password is always explicit; the editor
clears only when no remaining source uses the same URL and user. See
[protocol](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/protocol.md#calendar) for the message shapes.
