# Performance measurement

Passing correctness tests is a prerequisite, not performance evidence. Measure
the final packaged revision in a controlled desktop workload, and keep raw
runs, artifact hashes, environment details and conclusions with the work plan's
stateful reports. This guide defines interpretation, not a claim that a budget
has passed.

## Compare equivalent workloads

Use at least three alternating baseline/island pairs. Each run needs 30 seconds
of warmup followed by 120 seconds of sampling. Preserve playback state, selected
track and artwork, background applications, wallpaper, bar activity, power mode
and output configuration. Keep failures and noisy runs with their explanation;
report the median and range across pairs, not a selected favorable run.

Begin with the native shell baseline and island-plus-helper with blur off.
Glass needs a separately approved compositor configuration. If it changes global
blur, measure both the original baseline and a blur-enabled baseline without the
island: report total desktop cost as well as the matched-baseline delta. Compare
extension off/on with the same browser profile and supported-page workload; the
browser's entire baseline footprint is not extension overhead.

Do not start a second desktop shell for measurement. Identify the existing
shell and compositor, and every owned helper/native-host process, before each
run. Re-resolve ownership after a restart. The sampler neither discovers child
processes nor starts or stops its targets.

## Collect and interpret process samples

[benchmark-resources.py](../scripts/benchmark-resources.py) owns the command-line
options, sampling implementation and output schema. For example, after resolving
the actual process identities and choosing a report destination:

```sh
python3 scripts/benchmark-resources.py \
  --pid shell:"$shell_pid" --pid helper:"$helper_pid" --pid compositor:"$compositor_pid" \
  --warmup 30 --seconds 120 --cohort native-island-blur-off > "$report_path"
```

Label the compositor `compositor:PID`: the analyzer leaves it out of the
owned total and reports its delta beside it (an unlabelled run falls back to
the lowest PID, which is not guaranteed to be the compositor).

Add the native-host PID and relevant browser-process cohort when the extension
is enabled. Record how browser overhead is attributed. The command is only a
sampling example; it does not select processes or establish a matched baseline.

Use whole-run, interval-weighted `cpuPercentMean` for CPU budgets. The median
one-second CPU bucket can be zero while periodic work remains expensive. Here
100% is one logical core; subtracting two CPU percentages produces percentage
points, not relative percent. Aggregate owned-process CPU with the matched
shell delta, and disclose compositor and browser deltas separately rather than
omitting them from the total.

For memory, add process samples at corresponding times before deriving cohort
statistics and baseline deltas.
[analyze-resources.py](../scripts/analyze-resources.py) owns that arithmetic
and the memory verdict. It reads `<cohort>-island-false-<n>.json` and
`<cohort>-island-true-<n>.json` pairs and judges each memory budget against
the cohort's own noise, the spread of the baseline's owned footprint across its
pairs. A cohort passes only when the median delta clears the budget by more
than that spread, and fails only when it exceeds the budget by more than that
spread. Anything between, or fewer than three pairs, is `inconclusive` and
needs more pairs, not a conclusion. The final parity acceptance shows why: the
island:false shell alone moved by 18 to 22 MiB PSS between pairs of the same
cohort, so its hover-cycle median of 31.3 MiB (pair range 10.6 to 34.8) could
not tell a fixed cost from noise, while camera-open (37.8 MiB with ±1 MiB of
noise) is a clear failure. The sampler also records USS (private pages) and
anonymous PSS, which do not move when other processes map the same
libraries; the analyzer reports their deltas to attribute where memory goes.
Within each island run, owned PSS must not rise more than 5 MiB from the first
fifth of the samples to the last. Summing individual process medians or peaks
does not describe the median or peak simultaneous footprint. PSS apportions
shared pages; RSS can double-count shared libraries, so retain both measures
and state the accounting basis.

The sampler's memory peaks are maxima of periodic observations, not continuous
high-water marks. Short-lived decoder children can start and exit between
samples, and their CPU is not included in the parent's own CPU ticks. The
same holds for the artwork fetch child (`nookisle-artwork-fetch`), which
carries the TLS stack for each remote artwork download and exits with it, so
the helper's settled memory no longer includes TLS state. Measure
those jobs separately and include their contribution to artwork/transition
workloads. [The decoder resource probe](../tests/helper/artwork-loader-test.cpp)
and [decoder limits](../helper/artwork-decoder.cpp) are the executable owners for
transient artwork evidence. A transient decode peak is distinct from settled
memory; neither substitutes for the other.

A missing/unreadable process or changed PID lifetime invalidates the run. Keep
the failure, resolve the new process set and restart the paired measurement;
do not splice lifetimes or silently drop a process. Review output and cohort
labels before sharing; do not put titles, URLs, tokens or personal paths in
labels or public reports.

## Island workloads

The dynamic island adds three cohorts, each a matched `island:false` baseline
against `island:true` on the same shell: collapsed with playback paused,
expanded with a silent local track playing, and a hover cycle that moves the
pointer onto and off the pill every second. The brightness HUD's backlight
events come from the helper's own udev socket, so no separate monitor process
joins the owned set; the compositor is reported beside it. The budgets below apply
unchanged; the hover cycle is held to the transition limit.

The island experience adds a fourth cohort, collapsed with music playing, held
to the expanded-playing limit of 2 percentage points. In both playing cohorts
the owned set also includes the `nookisle-spectrum` capture process,
re-resolved before every run (match it with a pattern that allows arguments,
such as `io\.github\.bavanchun\.nookisle/libexec/nookisle-spectrum( |$)`). An
`island:true` playing run without a live spectrum process is invalid and is
repeated. A silent track no longer represents playback, because the capture
prints nothing while the signal is silent: the playing cohorts play a
pink-noise fixture. Keep the default sink muted when its monitor still carries
signal while muted (check that the capture prints non-zero lines), and
otherwise play at 10% volume, and record which rule applied. If a playing
cohort exceeds its CPU budget, the fallbacks are, in order and each
remeasured: `--fps 20` for the capture, then 12 bands, then `visualizer` off
by default. All three were needed on the reference machine: at 30 lines a
second the live pill cost 2.87 points, at 20 lines 2.20, and with 12 bands
2.13, almost all of it the shell repainting the pill once per line.

A per-thread profile of the live shell then showed that each line costs about
1 ms of shell CPU, split between the render thread, the GUI thread and the
Wayland event thread, and that this is fixed per-frame overhead: receiving and
parsing lines without drawing them costs little, bars written in one pass
instead of per-bar bindings cost the same, and a window cut to the pill's
height cost the same. The line rate is the only lever, so the capture runs at
15 lines a second with 12 bands. At that rate the earlier island measured 1.78
points (range 1.78 to 1.80, compositor 0.87 reported beside it), inside the
budget, and the live bars are on by default (from benchmark runs).

The Home player and the closed live activity then measured 2.25 points
(range 1.87 to 2.44) on the same cohort. To bring it back inside the budget,
the shell now draws a spectrum line only when some band would move a bar at
least one pixel from the line on screen, using the actual bar span above its
minimum height (14 px with a progress hairline on this host, 18 px without
one), and a quiet line whenever it differs ([Spectrum.js](../qml/Spectrum.js));
a dropped line moves no bar by a whole pixel. An earlier fixed rule of 7
levels skipped about 28 % of lines on the pink-noise fixture, and with it
three alternating pairs measured 1.51 points (range 1.50 to 1.59), the same
evening as the 2.25 and with other work loading the machine (1-minute load 1.0
to 5.9) (from benchmark runs).
That 1.51 was measured with the fixed rule. The current span-aware rule has
not been measured live: it draws 54 of 90 recorded fixture lines at a 14 px
span, against 63 for the fixed rule, and 79 of 90 at an 18 px span (a track
with no known length), so a similar or lower cost is expected at 14 px but not
established. The collapsed-playing figure for the current build is
re-measured in acceptance. The closed title adds one marquee pass per track
change, and only for a title too long to fit: about a 3s pause and then
(title width + 20 px) / 30 px/s of scrolling at the display rate, so about
6s of extra frames every 3 to 4 minutes of typical music, and nothing at
rest.

The idle styles are drawn to stay far inside the collapsed-paused budget. At
about 1ms of shell CPU per redraw, the glance redraws once a minute (about
0.002 points), Horizon never, and the face about 0.8 times a second (four
redraws per blink, every 5s on average: about 0.08 points). The face's
earlier tweened blink redrew about 24 frames every 3s, an estimated 0.8
points. These are estimates from the per-redraw cost, not measurements; the
`collapsed-idle-glance` and `collapsed-idle-face` cohorts measure them. Each
is collapsed with nothing playing (the players paused past the pause grace)
and the style set explicitly, held to the collapsed-paused limit of 0.5
points, against the same `island:false` baseline. The face cohort runs in
daytime: from 23:00 to 06:00 the face sleeps and never blinks. Since the
glance is the default idle style, `collapsed-paused` now measures it too.
The acceptance harness (benchmark runner and analyzer) includes both cohorts.

The privacy indicators add `collapsed-idle-privacy`: collapsed with nothing
playing while a throwaway `pw-record /dev/null` captures the microphone in
both modes, so the island shows the mic dot, held to the collapsed-paused
limit of 0.5 points against the same `island:false` baseline. The dots are
static; the cost is the PipeWire graph bindings, one tracked stream and the
helper's idle camera watch. It runs in the same harness.

Timers add `collapsed-idle-timer` (a 60-minute Omarchy reminder running with
nothing playing, so the timer fills the notch; 0.5 points) and
`collapsed-playing-timer` (the same reminder beside playing music, as the
minimal ring; 2 points, the collapsed-playing limit). The reminder runs in
both modes, and the harness stops exactly that unit afterwards. The labels
and the ring step once a minute; reading the list costs one short
`omarchy-reminder` run per change, not per minute.

`collapsed-recording` writes Omarchy's recording marker by hand with nothing
playing, so the recording fills the notch without anything being recorded,
and removes it afterwards; it refuses to run while a real recording runs.
It is held to 0.5 points. The helper's `/tmp` watch wakes on every file
closed or deleted in `/tmp`, and only the island side runs it, so the cohort
also measures that. An offscreen estimate, before any live run: a benchmark
of `SystemWatch` alone took 9.7 to 10.7 µs of CPU per event over three runs
of 40,000 events (next to nothing with the watch off), and `/tmp` on the
reference laptop saw 710 such events in 120 s (5.9 a second, mostly
container runtime files). That is about 60 µs of CPU a second, roughly 0.006
points, and still about 0.1 points at 100 events a second. The watch runs
only while `recordingActivity` is on.

`collapsed-idle-screenshots` turns `screenshotsToShelf` on with nothing
playing and takes no screenshot: it measures the helper's idle watch on the
screenshot folder, which should cost nothing until a file is written, against
the 0.5-point limit.

The notch shell's hover cycle measured 4.16 points in one paused pair, under
the 5-point transition limit (from benchmark runs),
and the Home player's expanded-playing cohort 0.78 points in one pair
(from benchmark runs).
One pair is a first reading, not the three-pair acceptance measurement. The
camera mirror and the calendar have no measured cohort.

The island is drawn as a `Shape` with `preferredRendererType:
Shape.CurveRenderer` (the notch outline), whose flare and corner radii change
on every frame of the open and close springs, so the renderer re-tessellates
the outline while the notch morphs and not while it rests. The hover cycle
catches that cost. If it rises above the transition limit, the fallbacks, in
order and each remeasured, are: two small fixed-radius flare `Shape`s scaled
around a `Rectangle` body, then the `Rectangle` with a static flare image.
Under the software renderer the `Shape` falls back to its painter path.

## Acceptance boundaries

Retain the accepted targets without quietly loosening them:

- Whole-owned-workload CPU delta: settled hidden/locked at most 0.2 percentage
  points, compact/expanded paused 0.5, expanded playing 2, finite transitions 5.
  Settled hidden/locked also requires no recurring plugin UI timer/render work.
- Steady memory delta: PSS at most 25 MiB and RSS at most 40 MiB. After at least
  100 transitions and 100 artwork changes, settled PSS must stay within 5 MiB
  of the warm matched state without monotonic growth.
- GUI/render work: p95 at most 8 ms. Presentation: 60 Hz target with fewer than
  1% of intervals exceeding 33.3 ms. No reproduced plugin-attributable stall
  over 50 ms. Calculated texture use at most 16 MiB.
- GPU busy delta: at most 1 percentage point settled and 5 during transitions,
  only when a reliable counter is available.

GUI/render work, presentation intervals and end-to-end command latency are
different measurements. Capture each with suitable instrumentation in a
separate run; an animation timer or CPU sample is not presentation evidence.
Screen recording can perturb the workload and belongs in a separate visual
check. Missing GPU counters, frame tooling or real-site coverage remain
explicitly unverified, never inferred as a pass from proxy data.

Use [installation and recovery](install.md) for package ownership and rollback,
[architecture](architecture.md) for lifecycle boundaries, and the
[support matrix](support-matrix.md) for evidence limits. A failed budget calls
for diagnosis and remeasurement, or an explicit decision about the trade-off;
it does not justify removing safety guarantees or excluding a costly process.
