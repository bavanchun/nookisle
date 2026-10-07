# Settings and configuration

**Settings.** [qml/Settings.js](../qml/Settings.js) is the one settings
schema: each key's type (`bool`, `int`, `real`, `enum`, `string`, `list` or `sources`),
default, bounds or allowed values, section, label and help text. Besides
`autoShow`, `reducedMotion`, `highContrast`, `remoteArtwork`, `island` and
`hud`, `configure` accepts five more booleans, each with a row in the
settings window and the legacy panel's
[IslandSettings.qml](../components/IslandSettings.qml), and a field in
`status()`. No setting has its own IPC verb; every setting travels through
`configure`.

| Key | Default | Governs |
|---|---|---|
| `hud` | off | level readout in the island for volume and brightness changes |
| `visualizer` | on | live spectrum bars in the closed notch and the track peek (for its CPU cost while playing, see [performance](https://github.com/bavanchun/nookisle/blob/v1.0.3/docs/performance.md#island-workloads)) |
| `peek` | off | the short track peek when the playing track changes |
| `power` | on | "Battery and charger": reading the battery through UPower at all. It gates charger changes and low (20 %) or critical (10 %) battery warnings, as a banner or a peek (`powerStyle`), and the header gauge; off, every other Battery row is dimmed |
| `tint` | on | tinting the bars, sliders, hairline and glow with the artwork's colour (the legacy card and its controls too) |
| `lyrics` | off | synced lyrics from lrclib.net (sends title, artist, album and length) |

Lyrics and the level readout (`hud`) are opt-in: lyrics sends track metadata off the machine, and HUD defaults to off so Omarchy's OSD keeps the media keys without duplicate readouts.

`configure` takes a JSON object of schema keys and validates every value
against the schema before writing anything: an unknown key, a wrong type, an
out-of-range number or an unlisted enum word rejects the whole batch
(`invalid-settings`), and neither store changes. The eleven booleans above
keep living in the host's `shell.json` bar entry, written exactly as before.
Every other key is typed and lives in the plugin's own file,
`$XDG_CONFIG_HOME/nookisle/settings.json` (or
`~/.config/nookisle/settings.json`), as `{"version": 1, "values": {...}}`.
The Service creates the directory with mode 0700 when it starts and creates
the file atomically with mode 0600. A typed write is saved before the shell
config is touched: if the directory does not exist yet or the save fails, the
whole batch is rejected and neither store changes. The Service reloads the
file when it changes on disk; unknown keys are dropped, and an invalid value,
a missing file or an unreadable one reads as the defaults. `status()` reports the resolved typed
values as one `settings` object, next to the top-level booleans, while omitting
calendar source definitions and the internal keys (pending password clear
identifiers, and the retired `showIdleFace` switch).

| Key | Type | Default | Range |
|---|---|---|---|
| `hoverDwell` | int (ms) | 300 | 0–1000 |
| `openOnHover` | bool | true | When false, hover dwell does not open the island; click and pull still work |
| `rememberLastTab` | bool | false | Retain the last Home/Shelf tab unless a populated Shelf is set to open by default; turning it on also enables `alwaysShowTabs` |
| `displayMode` | enum | `follow` | `follow`, `all`, `fixed` |
| `preferredDisplay` | screen | "" | a connected screen's name, or "" for automatic |
| `leaveGrace` | int (ms) | 100 | 0–1000 |
| `onboardingDone` | bool | false | Set when the welcome is finished or closed; not a row in the window, where About offers Show welcome again |
| `alwaysShowTabs` | bool | true | Show the Home and Shelf tabs even while the shelf is empty |
| `followDesktopMotion` | bool | true | Reduce motion while Hyprland's animations are off (`hyprctl getoption animations:enabled`, read at start and after each config reload), as well as with the `reducedMotion` switch |
| `showSettingsIcon` | bool | true | Show the settings gear in the open header |
| `uiFont` | enum | `sans` | `sans` (the first installed of Inter, Roboto and Noto Sans, else fontconfig's `sans-serif`; tabular figures for times), `theme` (the Omarchy theme font) |
| `openShelfByDefault` | bool | true | On close, choose Shelf for the next open when it contains items |
| `showPowerNotifications` | bool | true | Show charger and low or critical battery banners (default `powerStyle`) or peeks; the gauge remains available |
| `showPowerStatusIcons` | bool | true | Show the charging, low-battery and saver marks within the gauge |
| `enableGestures` | bool | true | Pull the closed island down, or Shift and scroll, to open it |
| `closeGesture` | bool | true | Push the open island up, or Shift and scroll, to close it |
| `gestureTravel` | int (px) | 200 | 100–300 |
| `summonAutoClose` | int (ms) | 3000 | 0–10000, 0 never |
| `lightingEffect` | bool | true | Light the player with a soft glow of the cover while music plays |
| `sliderColor` | enum | `albumArt` | `white`, `albumArt`, `accent`; the default reaches only installs that never saved a setting, so an existing install keeps its stored `white` until it is changed in Settings (Home, Progress colour) |
| `peekStyle` | enum | `standard` | `standard` (art and spectrum card), `inline` (title and artist beside the closed notch) |
| `musicControlSlots` | list | `shuffle`, `previous`, `playPause`, `next`, `repeat` | up to 5 of the button kinds, or `none`; the editor can reset this list to its defaults |
| `musicControlSlotLimit` | int | 5 | 3–5 |
| `pauseGrace` | int (ms) | 3000 | 0–10000; shown as Media inactivity timeout, and 0 ends the live state immediately |
| `musicLiveActivity` | bool | true | Show the cover and the spectrum beside the closed island while music plays |
| `coloredSpectrogram` | bool | true | |
| `showCalendar` | bool | false | Show the calendar beside the player; the calendar rows need it |
| `showMirror` | bool | false | Show the camera mirror beside the player; the camera runs only while it shows |
| `hudGradient` | bool | false | Shade the filled level bar from one end to the other |
| `hudGlow` | bool | false | Draw a soft halo around the filled level bar |
| `shelfLimit` | int (items) | 64 | 1–256 |
| `shelfEnabled` | bool | true | Hides the Shelf tab and view, and stops drop-to-Shelf when false; stored items remain |
| `shelfPersist` | bool | false | Saves the shelf to `$XDG_STATE_HOME/nookisle/shelf.json` |
| `shareProvider` | enum | `auto` | `auto`, `localsend`, `kdeconnect`, `portal` |
| `screenshotsToShelf` | bool | false | Add each new Omarchy screenshot to the shelf ([screenshots](features.md#screenshots-to-the-shelf)) |
| `screenshotDir` | string | empty | An absolute folder where screenshots are saved; empty follows Omarchy (`$OMARCHY_SCREENSHOT_DIR`, else the Pictures folder) |
| `recordingsToShelf` | bool | false | Add each saved Omarchy screen recording to the shelf; needs `recordingActivity`, which runs the recording watch |
| `copyOnDrag` | bool | false | Drags out offer only Copy |
| `autoRemoveShelfItems` | bool | false | Items leave the shelf once a drag out is dropped |
| `preferredSource` | string | "" | The remembered player's app identity (`org.mpris.MediaPlayer2.spotify`, the MPRIS name without its `.instance…` suffix, or `extension:` and a platform). While selection is Auto, a present endpoint of that app wins over every other, across restarts; set in the welcome's Media step, shown in Media with Forget |
| `mirrorShape` | enum | `rectangle` | `rectangle`, `circle` |
| `deviceEvents` | enum | `audio` | `off`, `audio` (headsets, headphones, speakers), `all`: peek when a Bluetooth device connects or its battery runs low ([peeks](features.md#peeks)) |
| `outputPeek` | bool | true | Peek when the sound output changes; needs the level readout (`hud`), whose source resolves the output |
| `timers` | bool | true | Start Omarchy reminders from the island's Timers view and count the soonest down in the closed notch ([timers](features.md#timers)) |
| `timerPresets` | list of int (minutes) | 5, 10, 25, 60 | up to 6 whole minutes, each 1–1440, offered in the Timers view; typed as "5, 10, 25" in the settings window, where an invalid list is put back and explained |
| `recordingActivity` | bool | true | Show a running Omarchy screen recording in the closed island, with Stop in the open one ([screen recording](features.md#screen-recording)) |
| `privacyIndicators` | bool | true | Dots in the closed island while an app uses the microphone, a camera or the screen; local only ([privacy](privacy.md#privacy-indicators)) |
| `hardwareNotch` | bool | false | Keep the closed notch's centre empty, as over a camera cutout; off, the centre holds the track title and the inline HUD centres |
| `idleStyle` | enum | `glance` | `glance`, `face`, `horizon`, `empty`: what the closed island shows while nothing plays ([idle notch](features.md#idle-notch)) |
| `idleClock` | enum | `auto` | `auto`, `time`, `date`, `off`: the glance's clock; `auto` shows only the date when the host bar has an `omarchy.clock` module |
| `idleHairline` | bool | true | The glance's hairline: the day's progress, or the countdown to a coming event |
| `idleNextEvent` | bool | false | The next event within the hour in the glance; needs `showCalendar` |
| `idleEventTitles` | bool | false | Name that event instead of saying "Event" |
| `useCustomAccentColor` | bool | false | Use the chosen accent rather than the Omarchy theme accent |
| `customAccentColor` | string | `#a9c7ff` | `#RRGGBB`; used when `useCustomAccentColor` is on |
| `windowShadow` | bool | true | Draw the open island's GPU shadow; software fallback remains the hairline edge |
| `extendHoverArea` | bool | false | Add an 8 px hover strip beneath the closed island; it has no tap or drag action, though Wayland intercepts clicks in its input mask |
| `expandedDragDetection` | bool | true | A drag over the empty bar centre beside the closed notch opens the shelf (see the catch zone in [features](features.md#shelf)) |
| `dragCatchWidth` | int (px) | 480 | 120–1600; the catch zone's width, limited to the free bar centre |
| `backlightDevice` | string | "" | Leave empty to use the first available display backlight |
| `fullscreenBehavior` | enum | `nowPlayingOnly` | `always`, `nowPlayingOnly`, `never`; Always, only for the selected player's app, or never |
| `showBatteryIndicator` | bool | true | Show the battery level in the open island's header |
| `showBatteryPercent` | bool | true | Show the percentage beside the battery gauge |
| `hudStyle` | enum | `inline` | `inline`, `below`; Show it in the notch wings or below the notch |
| `showOpenNotchHud` | bool | true | Show a level capsule in the open header |
| `hudPercentClosed` | bool | false | Show a percentage beside the closed readout bar |
| `hudPercentOpen` | bool | true | Show a percentage beside the open header bar |
| `hudDuration` | int (ms) | 1500 | 250–5000; Milliseconds before the level readout closes |
| `hudAccent` | bool | false | Use the accent colour for the readout bar |
| `hideCompletedReminders` | bool | true | Leave finished reminders out of the day's list |
| `hideAllDayEvents` | bool | false | Show only events with a time |
| `autoScrollToNextEvent` | bool | true | Open today's list at the current or next event |
| `showFullEventTitles` | bool | false | Wrap long titles instead of shortening them |

`showIdleFace` is no longer shown in the settings window. A settings file
that has it on and names no `idleStyle` reads as `idleStyle: "face"`, and
`configure` still takes it as an alias: `true` selects the face style, and
`false` returns the face to the glance and leaves any other style alone. A
batch that also names `idleStyle` keeps that style.

[qml/Settings.js](../qml/Settings.js) is the one list of these keys, with
their labels and help text.

```sh
omarchy-shell nookisle configure '{"hoverDwell":450}'
omarchy-shell nookisle configure '{"musicControlSlots":["back15","previous","playPause","next","forward15"]}'
omarchy-shell nookisle configure '{"hoverDwell":"x"}'   # invalid-settings
```

**Settings window.** [SettingsWindow.qml](../components/SettingsWindow.qml) is
a fixed 700×600 Quickshell `FloatingWindow` in the dark tokens; its minimum
and maximum sizes match, so Hyprland floats and centres it as a dialog instead
of tiling it, and no window rule is installed. A 200 px
sidebar lists `Settings.sections()` (General, Appearance, Media, Calendar, HUD,
Battery, Shelf, Shortcuts, Advanced, About), and
[SettingsPane.qml](../components/SettingsPane.qml) generates each section's
rows from the schema through
[SettingsControls.qml](../components/SettingsControls.qml): a switch for
`bool`, a slider with a number field and its `unit` for `int` and `real`, a segmented
control for `enum` that names each value by `Settings.VALUE_LABELS`, a text
field for `string`, and for `list` the
[SlotEditor.qml](../components/SlotEditor.qml), where slots are dragged to
reorder, palette words are dragged in, and a slot dropped on the trash is
removed. Its chips are Tab stops too: Ctrl+Left and Ctrl+Right move a slot,
Delete removes it, and Return or Space adds a palette word at the end (in place
of the last slot when the list is full). A move beyond either end leaves the
list and keyboard focus unchanged. The sidebar, switches and choices draw
with the island tokens, never the platform palette: the selected section and
a checked choice take the primary fill and label, and a switch fills its track
when on. The sidebar is
the window's first Tab stop: Up, Down, Home and End change the section, and
every control that takes the keyboard (sidebar, switch, slider, choice, button,
field, check box and slot chip) draws an accent focus ring. The page follows
the keyboard: a control that takes the focus outside the visible part scrolls
into view. A setting's choices form one radio group, so Tab reaches only the
chosen one and the arrow keys choose and focus its neighbour. Each control
carries its row's help text as its accessible description. Every edit goes
through `configure`; a refused edit snaps the control
back and says why it was not saved, from the Service's `configureError`: a
value the schema refuses says what is allowed (a `#RRGGBB` colour, a
backlight device name, a number's range), and a folder still being created,
an unwritable `settings.json` or an unwritable shell config each say so. A
refused text field keeps what was typed so it can be corrected. The IPC verb
still answers `invalid-settings` for any refusal. Shortcuts shows the one summon line for
`bindings.lua` (`Strings.summonBinding`: SUPER+M with auto-close, the line the
welcome and [install](install.md#summon-with-auto-close) show) with a Copy
button. Each time it shows it reads `hyprctl binds -j`, read-only, and names
a binding that already holds SUPER+M. About shows the plugin version, installed build description,
manifest schema and repository link from [manifest.json](../manifest.json).
The build description ends in `-dirty` when tracked source changes are
uncommitted; it is `source` when Git or the source tree's `.git` is unavailable
during installation. Calendar sources get their own editor with the calendar
backend.

**Numbers.** A drag saves once on release. Arrow keys, Page Up and Page Down
(a tenth of the range) and Home and End move the slider at once and save once
the keys rest for 400 ms, or as soon as the slider loses the keyboard, so a
held key writes `settings.json` once rather than once per step. The number
field beside it takes an exact value: Return or leaving it saves what was
typed, and a number out of range stays in the field while the row names the
range. Until something is typed, the field follows the value.

**Search, reset and About.** The search field above the sections (Ctrl+F
focuses it, Escape clears it) lists every row whose label, help, section or
group heading holds each word typed, under its section's name, as working
rows; it is the window's last Tab stop. Each section ends in "Reset …to
defaults", which asks once and then writes the section's defaults as one
`configure` batch (`Settings.resetValues`); calendar sources are data and a
reset keeps them. About adds Show welcome again, which opens the welcome
steps, and Open settings file.

**Groups and dependent rows.** General and Media read in named groups
(`Settings.GROUPS`: Bar, Opening, Gestures and Displays; Player, Closed
island, Track peek, Lyrics and Mirror); a key a group list does not name
follows them without a heading. A row whose setting only matters while
another allows it is dimmed, its control disabled, and it says which setting
to turn on (`Settings.REQUIRES`): Open delay needs Open on hover, Screen needs
One screen or Every screen, Gesture distance needs either gesture, the HUD
rows need Level readout, the calendar display rules need Calendar on Home,
and the Shelf rows need Enable shelf. The stored value is kept while dimmed.
The Calendar section owns `showCalendar`, `calendarRefresh`, `calendarSources`,
the display rules and `calendarSelection`. Its "Calendars shown" row offers
All calendars and one toggle per configured source; choosing a source starts a
subset, and an empty selection shows all. Remote URLs appear as hosts, without
their private link paths. Sources resolving to local or private network destinations
(including CGNAT and Tailscale 100.64.0.0/10 addresses, benchmark ranges, and loopback)
require `"allowLocalNetwork": true` on that source. Its internal pending-clear key has no row. The
reference's “Hide title bar” changes the macOS menu-bar chin height. Omarchy
has no equivalent inset, so there is no title-bar switch.
