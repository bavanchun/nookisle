# Controller protocol

The helper owns discovery, transport and the session lease. The QML service
owns its stdin/stdout and does not share these streams with a browser host.
Every message has `protocolVersion: 1` and `connectionGeneration`. A helper
starts with `hello`; all later frames must carry that generation. Unsupported
versions fail closed. Producers encode non-ASCII characters as JSON Unicode
escapes so arbitrary Quickshell read boundaries preserve text.

## Bounds and publication

The executable constants are in [ipc-protocol.h](../helper/ipc-protocol.h):
64 KiB per frame, 128 KiB output queue, 64 endpoints, 8 KiB per snapshot entry,
512 KiB per transaction. While publishing snapshots and progress, the helper
reserves a whole frame (64 KiB) of output capacity for results and gate
acknowledgements, so a full calendar page always fits behind them. Input is
incremental and bounded to one incomplete frame; it does not buffer an entire
stdin read stream. At most 16 transport requests may be pending.

`snapshotBegin` declares `sequence`, `busEpoch`, and `count`; ordered
`snapshotEntry` frames carry `index` and `endpoint`; `snapshotCommit` repeats
the count. QML publishes only a complete, matching transaction. Duplicate
identities, wrong indices, old generations, and an incomplete 3-second
transaction cannot create a partial model. One staging and one committed
transaction are retained, up to 1 MiB serialized-equivalent, not a heap bound.

Presentation can be trimmed with `presentationTruncated`. Routing tokens are
never shortened. Unrepresentable mandatory identity drops only that endpoint.
Oversized/absent raw track IDs disable absolute `SetPosition`, while relative
`Seek` remains available when the player advertises `CanSeek`. Exact trimming and framing
behavior is tested by the [native](../tests/helper/ipc-protocol-test.cpp) and
[QML](../tests/qml/tst-protocol.qml) suites.

## Admission and commands

`controlGate {admissionEpoch, enabled}` receives an ordered
`controlGateAck {admissionEpoch, enabled}`. Startup admission is closed.
Commands require the current open epoch in both service and helper. Lock and
disable close local admission immediately; the helper barrier takes effect
when it receives the gate. Already dispatched remote actions can finish.
Unlock never replays an old request.

`command {requestId, admissionEpoch, endpointToken, action, trackToken?, value?}`
receives `result {requestId, status}`. Actions are `Play`, `Pause`, `PlayPause`,
`Next`, `Previous`, `SetPosition`, `Seek`, `SetVolume`, `SetShuffle`,
`SetLoopStatus`, `Favorite`, and `Raise`. Position and relative seek values are
seconds on this wire, converted to MPRIS microseconds at dispatch. Relative
seek is bounded to −3600..3600 seconds. Volume is in [0,1]; shuffle is a
boolean; loop status is `None`, `Playlist`, or `Track`. Absolute `SetPosition`
requires the exact current track token, positive known length, and capability.
The wire exposes `CanSetPosition` separately from MPRIS `CanSeek`, so a source
with unknown duration can still support relative seek without enabling the scrubber.
The native destination is the captured unique D-Bus owner, never
the reusable well-known name. There is no fallback or automatic toggle retry.

MPRIS `Shuffle` and `LoopStatus` are accepted only when present with valid
types and writable in the player's introspection data (`access="readwrite"`
on `org.mpris.MediaPlayer2.Player`), and writes use `Properties.Set`. An
absent or read-only property disables its button, as does an introspection
that has not answered or failed. Each player's one introspection shares the
helper's budget of 128 outstanding D-Bus reads with its property reads, so a
peer that keeps re-taking a name without answering cannot grow them.
`Favorite` is available only to extension documents whose site adapter
advertises an enabled, readable like control; desktop Spotify MPRIS never
advertises it. Browser sources without shuffle or loop controls report both
capabilities false. A successful command does not change the displayed state
until a new source state arrives.
Spotify desktop also reports shuffle and loop as unavailable despite exposing
the properties: its tested build acknowledges writes without changing them.
See the [support matrix](support-matrix.md) for the probe evidence.

`Raise` dispatches on the MPRIS root interface rather than the player interface
and is gated on `capabilities.CanRaise`. It is deliberately exempt from the
`CanControl` gate every transport action passes, because MPRIS defines `CanRaise`
as a root property independent of playback control. The helper derives the
capability from root-property presence and never fabricates it; an absent
property is `false`. The bridge instead **authors** `CanRaise` for
extension-transport endpoints, because raising is a property of that transport —
the extension worker activates the tab and the document can neither know nor
perform it. A successful reply proves the method returned, not that the
compositor activated anything: window activation is the application's to request
and the compositor's to grant, so the UI claims nothing on success.

Results include `success`, `target-gone`, `stale-track`, `unsupported`, `busy`,
`disconnected`, `closed`, `invalid-value`, `timeout`, and `error`. A successful method reply is not proof
that audio is audible. The source snapshot remains playback-state authority.
Transport timeout is 3 seconds; the service's 4-second safety deadline detects
a missing result and closes an unresponsive connection rather than leaking
pending credits indefinitely. That deadline, and the 3-second snapshot
deadline, count on a clock the service advances with a 250 ms tick only while
a request or snapshot is pending: the tick pauses across suspend, so a command
sent just before sleep does not expire on resume. A missed command deadline or
gate acknowledgement restarts the helper after 1, 2 and then 4 s; a fourth stall
within a minute stops it until the user retries.

## Shelf thumbnails

`thumbnail {requestId, uri, name}` asks for a freedesktop thumbnail of one
shelved local file. `name` is the cache file name, the MD5 of `uri` plus
`.png`, computed in QML. The helper answers `requestAck` at once and later
`thumbnailResult {requestId, status, path}`, where `status` is `ready`,
`unsupported` (not a regular PNG or JPEG file, or over 32 MiB), `failed`,
`busy` (more than 64 waiting) or `invalid`, and `path` is set only when it is
`ready`. An existing normal or large cache entry (a PNG of at most 1 MiB, 256
px a side) may have been written by another application, so the helper never
parses it: the decoder child checks and re-encodes it (`--cached-thumbnail`),
keeping only `Thumb::URI` and `Thumb::MTime`, and succeeds only when both keys
match the current file, which the helper passes as arguments; the helper then
stores the child's PNG as below, so `path` always names the helper's own normal
entry. Without the
child no cache entry is accepted. Otherwise, or when the child rejects the
entry, the file is decoded in the sandboxed decoder child with the
thumbnail limits (at most 8192 px a side and 16 megapixels, a 128 px result),
stamped by the child with `Thumb::URI` and `Thumb::MTime`, and written by the
helper to `$XDG_CACHE_HOME/thumbnails/normal/` through a private temporary
file and a rename. See
[thumbnail-cache.cpp](../helper/thumbnail-cache.cpp). The helper opens and
checks a shelved file but never reads it: the open descriptor becomes the
child's standard input, so a large photo streams from disk to the child without
passing through the helper's memory or blocking its event loop.

## Backlight events

`backlightWatch {requestId, enabled}` starts or stops the helper's watch on
udev's netlink socket for display backlight changes; the service sends it
whenever the brightness source becomes active or inactive (HUD and island on,
panel admitted), and again after each new connection. The helper answers
`requestAck {requestId, status}`, where `status` is `ok`, or `unavailable` when
this process cannot open the udev monitor (the brightness readout then stays
with Omarchy's own OSD). While watching, it sends
`backlightChanged {device}` for each backlight `change` uevent, where `device`
is the kernel name (at most 64 characters of `A-Za-z0-9_.:-`); the service
re-reads that device's level only when it is the backlight the HUD shows. LED
(keyboard) changes emit no uevent and are not watched. See
[backlight-monitor.cpp](../helper/backlight-monitor.cpp).

## Calendar

Calendar messages use the same version and connection generation as media
messages. `calendarConfigure {requestId, enabled, sources, refreshMinutes}`
activates the configured sources while the calendar preference, island mode
and UI admission hold; hiding the island keeps them configured, so remote
sources refresh on their configured interval rather than on every reveal.
`calendarWindow {requestId, offset}` returns
`calendarWindowResult {requestId, items, errors, nextOffset}` for the local
day window `[today−7d, today+14d]`; a new local day requests a fresh window,
including when Home has stayed open across midnight. `nextOffset:-1` ends
pagination. Each
item has `sourceId`, `uid`, `instanceStart`, `start`, `end`, `allDay`, `title`,
`location`, `color`, `todo`, `completed`, and `due`. `allDay` follows a
date-only `DTSTART`, or, for a reminder without `DTSTART`, a date-only `DUE`
(`DUE;VALUE=DATE`, as task apps write it). Unsupported ICS properties
are reported in an optional `unsupported` array. Source errors have a code
and source ID, without a URL or path; `recurrence-limit` means a source's
recurring series needed more than the per-source expansion budget, so some
series were cut short. The budget is 1,000,000 steps per source per window.
Each period of a series is charged its checks before it is expanded (every
`BYMONTHDAY` against every `BYDAY` in each month it covers); a period that is
never expanded, such as one of a series starting after the window, costs
nothing. Repeated values in a rule's lists count once, so a rule whose
distinct values multiply ends the budget instead of stalling the helper.
One window keeps at most 5000 items and 4 MiB of encoded
items across all sources together; `window-limit` marks the source whose
items crossed that bound and every source after it (in source-ID order), whose
items were left out.
Home displays those source error codes and failed reminder completion results
as compact messages above the event list, using the calendar's user-facing
error text.

The recurrence subset: `FREQ` DAILY, WEEKLY, MONTHLY or YEARLY with
`INTERVAL`, `COUNT`, `UNTIL`, `BYDAY` (an ordinal only with MONTHLY, or with
YEARLY limited by `BYMONTH`), `BYMONTHDAY`, `BYMONTH` (one or more months) and
`WKST`. Weeks start on Monday unless `WKST` names another day; it decides which
weeks an `INTERVAL` above 1 counts. YEARLY covers the `BYMONTH` months, or the
month of `DTSTART` without `BYMONTH`, and applies `BYDAY` or `BYMONTHDAY`
within each; `BYMONTH` limits the other frequencies to those months. `EXDATE` and `RECURRENCE-ID`
match instances by instant, whatever zone they are written in. Cancelled
instances are omitted, and an override moved into the window from outside
it is included. Any other rule shows only its first instance, with `RRULE`
in `unsupported`. Home marks a visible row carrying that value as a repeating
event whose pattern is not fully supported; it does not imply later instances
were expanded. The first instance is returned even when it falls before the
window, so the series never disappears from the result. `TZID` accepts IANA,
Windows and prefixed IDs; an unknown zone, or an ID longer than 256
characters, is read as floating time and reported as `TZID` in `unsupported`.
An entry keeps at most 4096 `EXDATE` values; the rest are dropped and reported
as `EXDATE` in `unsupported`.
Sub-components such as `VALARM` are skipped.

`calendarSetCompleted {requestId, sourceId, uid, completed}` returns a
`calendarResult` status. File and ICS URL sources return `read-only`; vdir
uses an atomic file replacement and returns `conflict` when the file changed
after the window read it, while CalDAV PUT uses `If-Match` and returns
`conflict` on a changed ETag. A write still pending when the sources are
reconfigured returns `cancelled`. `calendarCredential {requestId, action, url,
user, password?}` stores or clears a CalDAV password through `secret-tool`;
store sends the password to that process on standard input. The result never
echoes it. Reconfiguring sources never clears a password; only this
request's `clear` action does. `calendarTest {requestId, sourceId}` loads that one source afresh, bypassing
the cached window, and answers `calendarResult {requestId, ok, error}` (with
`status` as for other calendar results) only when that load completes; a
test during a load waits for that load, and an unknown source is
`not-found`. After a successful `store`, the helper reloads every configured
CalDAV source with that URL and user, and sends `calendarChanged` once they
have all finished. `calendarChanged` announces a watcher or refresh update so the
QML source can request the window again. These are helper stdio messages;
the public `nookisle` IPC target does not expose calendar data or secrets.

## Desktop signals

`watch {requestId, cameraDevices, recording, reminders, screenshots,
screenshotDir}` turns the helper's local watches on and off; an absent field
is off. It is sent on connect and whenever the wanted set changes, and only
while the island is allowed on screen with the matching feature on. The
reply is `requestAck {requestId, status}`, with `status` `invalid` for a
malformed request or a `screenshotDir` override that is not an existing
absolute folder of at most 4096 bytes; an invalid request changes nothing.

[system-watch.cpp](../helper/system-watch.cpp) holds one inotify descriptor
in the helper, so no watcher process runs beside it, and nothing is polled:

- **Camera.** Opens and closes on `/dev/videoN`, and hotplug in `/dev`, start
  one scan of `/proc/*/fd` 300ms after the last event. It names this user's
  processes holding a camera, except the shell hosting the island (the
  helper's parent), the helper, `pipewire` and `wireplumber`, and sends
  `systemEvent {kind: "camera", holders}` when the set changes: at most 16
  names of at most 64 bytes, sorted.
- **Recording.** Omarchy writes `/tmp/omarchy-screenrecord-filename` once a
  recording produces output and deletes it after saving.
  `systemEvent {kind: "recording", active, startedAt, path}` carries the
  marker's mtime (ms) and the video path it names; the stop carries the
  saved path. At start a marker counts only while `gpu-screen-recorder`
  runs, so a stale one left by a crash is ignored.
- **Screenshots.** Omarchy's `screenshot-*.png`, closed after writing or
  moved in, in `$OMARCHY_SCREENSHOT_DIR`, else the Pictures folder, or the
  override: `systemEvent {kind: "screenshot", path}`, at most 20 a second.
- **Reminders.** `omarchy-reminder-*m-*.timer` units appearing or going in
  `$XDG_RUNTIME_DIR/systemd/transient` send `systemEvent {kind: "reminders"}`
  100ms after the last change; `unavailable: true` when that folder is
  missing.

The Service checks each field (`Protocol.systemEvent`) and drops anything
else. Events are replaceable under output backpressure, like progress.

## Progress and credits

`subscribe {requestId, admissionEpoch, endpointToken, visible, cadenceMs}`
selects one view subscription. `refresh {requestId}` requests a new snapshot.
Both receive `requestAck {requestId}` for bounded write-credit accounting;
these acknowledgements are not playback results. Commands, control gates and
ordinary requests have distinct credit namespaces.

`progress {endpointToken, trackToken, positionSeconds, sequence}` is a
replaceable sample computed from the helper's monotonic clock. The service
subscribes only while the selected source is playing and the view is visible
and admitted: at 250ms while the view is expanded, and at 1000ms while the
collapsed island shows, for its progress hairline. The collapsed legacy panel,
hidden, paused and locked views have no recurring progress subscription. QML displays samples without a second extrapolation clock.
A seek (an MPRIS `Seeked` signal, or a browser state marked `positionEvent`)
publishes a new endpoint snapshot at once, so a seek while paused, with no
progress subscription, shows its position immediately.

The native source and progress owner is
[mpris-registry.cpp](../helper/mpris-registry.cpp). The service parser and
request lifecycle are [Protocol.js](../qml/Protocol.js) and
[Service.qml](../Service.qml). Privacy-sensitive metadata, URLs and complete
tokens are not diagnostic log fields.
