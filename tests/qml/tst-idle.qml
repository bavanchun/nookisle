import QtQuick
import QtTest
import "../../components"
import "../../qml/Idle.js" as Idle
import "../../qml/Calendar.js" as Calendar

TestCase {
    id: test
    name: "Idle"
    width: 400
    height: 100
    when: windowShown
    visible: true
    DesignTokens {
        id: design
        reducedMotion: true
    }
    // Sunday 27 September 2026, 14:05 local.
    readonly property var now: new Date(2026, 8, 27, 14, 5, 0)
    function at(hours, minutes) {
        return new Date(2026, 8, 27, hours, minutes, 0).toISOString();
    }
    function event(fields) {
        return Object.assign({ sourceId: "work", uid: "u", title: "Standup", allDay: false, todo: false,
            start: at(14, 20), end: at(14, 35), color: "#34c759" }, fields || {});
    }

    function test_layoutHasModule() {
        var owner = { left: [{ id: "omarchy.menu" }], center: [{ id: "io.github.bavanchun.nookisle" }],
            right: [{ id: "omarchy.clock", format: "dddd h:mm AP" }] };
        verify(Idle.layoutHasModule(owner, "omarchy.clock"));
        verify(!Idle.layoutHasModule({ left: [], center: [{ id: "io.github.bavanchun.nookisle" }], right: [] }, "omarchy.clock"));
        verify(!Idle.layoutHasModule(null, "omarchy.clock"));
        verify(!Idle.layoutHasModule({ left: "x" }, "omarchy.clock"));
    }
    // Automatic shows only the date beside a bar that already shows the time.
    function test_clockMode() {
        compare(Idle.clockMode("auto", true), "date");
        compare(Idle.clockMode("auto", false), "time");
        compare(Idle.clockMode("time", true), "time");
        compare(Idle.clockMode("date", false), "date");
        compare(Idle.clockMode("off", false), "off");
        compare(Idle.clockMode("bogus", false), "off");
    }
    function test_clockLines() {
        compare(Idle.line(now, "time", null, false), { primary: "14:05", secondary: " · Sun 27 Sep", soon: false });
        compare(Idle.line(now, "date", null, false), { primary: "Sunday", secondary: " · 27 September", soon: false });
        compare(Idle.line(now, "off", null, false), { primary: "", secondary: "", soon: false });
    }
    // An event wins over the clock; its title shows only with titles on, and
    // the line turns to the accent in its last five minutes.
    function test_eventLines() {
        var coming = Calendar.nextUpcoming([event()], now, {});
        compare(Idle.line(now, "time", coming, false), { primary: "Event", secondary: " · in 15 min", soon: false });
        compare(Idle.line(now, "time", coming, true).primary, "Standup");
        var soon = Calendar.nextUpcoming([event({ start: at(14, 9) })], now, {});
        compare(Idle.line(now, "time", soon, true), { primary: "Standup", secondary: " · in 4 min", soon: true });
        var under = Calendar.nextUpcoming([event({ start: at(14, 0), end: at(14, 30) })], now, {});
        compare(Idle.line(now, "time", under, true), { primary: "Standup", secondary: " · now, until 14:30", soon: false });
        compare(Idle.accessibleName(Idle.line(now, "time", under, true)), "Standup · now, until 14:30");
        compare(Idle.accessibleName(Idle.line(now, "off", null, false)), "Nothing playing");
    }
    function test_nextUpcoming() {
        compare(Calendar.nextUpcoming([], now, {}), null);
        compare(Calendar.nextUpcoming([event({ start: at(15, 30), end: at(16, 0) })], now, {}), null, "beyond the hour");
        compare(Calendar.nextUpcoming([event({ start: at(13, 0), end: at(14, 0) })], now, {}), null, "already over");
        compare(Calendar.nextUpcoming([event({ allDay: true, start: "2026-09-27", end: "2026-09-28" })], now, {}), null, "all day");
        compare(Calendar.nextUpcoming([event({ todo: true, completed: true, due: at(14, 30) })], now, {}), null, "done");
        var reminder = Calendar.nextUpcoming([event({ todo: true, due: at(14, 30), title: "Call" })], now, {});
        compare(reminder.item.title, "Call", "an open reminder counts");
        var pick = Calendar.nextUpcoming([event({ title: "Later", start: at(14, 50) }), event({ title: "Sooner", start: at(14, 10) })], now, {});
        compare(pick.item.title, "Sooner");
        var ongoing = Calendar.nextUpcoming([event({ title: "Soon" }), event({ title: "Now", start: at(14, 0), end: at(15, 0) })], now, {});
        verify(ongoing.ongoing);
        compare(ongoing.item.title, "Now", "an event under way wins");
        compare(Calendar.nextUpcoming([event({ sourceId: "home" })], now, { calendarSelection: ["work"] }), null, "only selected calendars");
    }
    function test_pipVisible() {
        verify(!Idle.pipVisible({ present: false, state: "Charging" }));
        verify(Idle.pipVisible({ present: true, onBattery: false, level: 0.5, state: "Charging" }));
        verify(Idle.pipVisible({ present: true, onBattery: true, level: 0.2, state: "Discharging" }));
        verify(Idle.pipVisible({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: true }));
        verify(!Idle.pipVisible({ present: true, onBattery: true, level: 0.8, state: "Discharging" }), "the bar has the battery otherwise");
        verify(!Idle.pipVisible({ present: true, onBattery: false, level: 1, state: "FullyCharged" }));
    }
    function test_hairlineFraction() {
        compare(Idle.hairlineFraction(new Date(2026, 8, 27, 12, 0), null), 0.5, "the day's progress");
        var coming = Calendar.nextUpcoming([event({ start: at(14, 20) })], now, {});
        compare(Idle.hairlineFraction(now, coming), 0.75, "15 of the last 60 minutes left");
        var under = Calendar.nextUpcoming([event({ start: at(14, 0), end: at(14, 20) })], now, {});
        compare(Idle.hairlineFraction(now, under), 0.25, "5 of 20 minutes elapsed");
    }

    // A glance showing test.now: the clock reads the real time when it
    // starts, so the fixture's time is set after.
    function makeGlance(properties) {
        var glance = createTemporaryObject(glanceComponent, test, properties);
        glance.now = test.now;
        return glance;
    }
    Component {
        id: glanceComponent
        IdleGlance {
            tokens: design
            width: 268
            height: 26
        }
    }
    // The glance lays its row out like the live row: the dot and the pip at
    // the closed inset from each end, the line centred between them, above
    // the hairline band.
    function test_glanceLayout() {
        var glance = makeGlance({ clockSetting: "time" });
        var dot = findChild(glance, "glanceDot"), line = findChild(glance, "glanceLine");
        compare(dot.color, design.tint, "the lead dot takes the accent");
        compare(findChild(glance, "glancePrimary").text, "14:05");
        compare(findChild(glance, "glanceSecondary").text, " · Sun 27 Sep");
        verify(!findChild(glance, "glancePip").visible);
        // No pip: the dot hugs the line and the two centre as one group, so
        // the margins either side match.
        var lineWidth = findChild(glance, "glancePrimary").width + findChild(glance, "glanceSecondary").width;
        compare(line.x, dot.x + dot.width + design.gap);
        verify(Math.abs(dot.x - (glance.width - (line.x + lineWidth))) <= 1, "balanced: " + dot.x + " against "
            + (glance.width - (line.x + lineWidth)));
        glance.batteryReading = { present: true, onBattery: true, level: 0.15, state: "Discharging" };
        var pip = findChild(glance, "glancePip");
        verify(pip.visible, "low on battery shows the pip");
        compare(pip.x + pip.width, glance.width - design.closedInset);
        compare(dot.x, design.closedInset, "with the pip, the dot mirrors it at the left inset");
        verify(Math.abs(line.x - Math.round((glance.width - lineWidth) / 2)) <= 0.5, "and the line centres");
        compare(pip.fill, "#ff453a");
        var fill = findChild(glance, "glanceHairlineFill");
        var hairline = findChild(glance, "glanceHairline");
        compare(fill.width, Math.round(hairline.width * Idle.hairlineFraction(test.now, null)));
        glance.hairline = false;
        verify(!hairline.visible);
        compare(glance.Accessible.name, "14:05 · Sun 27 Sep");
    }
    function test_glanceKeepsRoomForTrailingActivity() {
        var glance = makeGlance({ clockSetting: "time", trailingReserve: 28 });
        var dot = findChild(glance, "glanceDot"), line = findChild(glance, "glanceLine");
        var lineWidth = findChild(glance, "glancePrimary").width + findChild(glance, "glanceSecondary").width;
        compare(dot.x, design.closedInset, "the trailing activity mirrors the dot");
        compare(line.x, Math.round((glance.width - glance.trailingReserve - lineWidth) / 2));
        verify(line.x + lineWidth < glance.width - glance.trailingReserve,
            "the text clears the trailing activity");
        glance.batteryReading = { present: true, onBattery: true, level: 0.15, state: "Discharging" };
        var pip = findChild(glance, "glancePip");
        compare(pip.x + pip.width, glance.width - design.closedInset - glance.trailingReserve,
            "the pip also clears the activity");
    }
    // The privacy dots at the trailing end never reflow the row: the dot
    // and the line keep their places as one centred group, and the line
    // only has less room.
    function test_privacyDotsDoNotReflowTheGlance() {
        var glance = makeGlance({ clockSetting: "time" });
        var dot = findChild(glance, "glanceDot"), line = findChild(glance, "glanceLine");
        var dotX = dot.x, lineX = line.x;
        [design.privacyInset, design.privacyMutedInset].forEach(function (reserve) {
            glance.privacyReserve = reserve;
            compare(dot.x, dotX, "the dot stays beside the line with " + reserve + " px of dots");
            compare(line.x, lineX, "and the line stays put");
            verify(line.x + findChild(glance, "glancePrimary").width + findChild(glance, "glanceSecondary").width
                <= glance.width - design.closedInset - reserve, "clear of the dots");
        });
        glance.batteryReading = { present: true, onBattery: true, level: 0.15, state: "Discharging" };
        var pip = findChild(glance, "glancePip");
        compare(pip.x + pip.width, glance.width - design.closedInset - glance.privacyReserve, "the pip clears the dots");
    }
    DesignTokens {
        id: movingDesign
        artColor: "#e2402e"
    }
    Component {
        id: movingGlanceComponent
        IdleGlance {
            tokens: movingDesign
            width: 268
            height: 26
        }
    }
    // The day's progress is a faint neutral fill, never the tint the track's
    // progress uses, and it fades in from nothing when the glance appears,
    // so the handover from the track's hairline never jumps.
    function test_dayHairlineIsNeutralAndFadesIn() {
        var glance = createTemporaryObject(movingGlanceComponent, test);
        var fill = findChild(glance, "glanceHairlineFill");
        verify(fill.opacity < 0.5, "it starts from nothing");
        tryCompare(fill, "opacity", 1, movingDesign.hairlineRevealDuration + 500);
        var muted = movingDesign.notchMutedInk;
        verify(Math.abs(fill.color.r - muted.r) < 0.01 && Math.abs(fill.color.g - muted.g) < 0.01
            && Math.abs(fill.color.b - muted.b) < 0.01, "neutral grey");
        verify(Math.abs(fill.color.a - movingDesign.dayHairlineOpacity) < 0.01, "and faint");
        verify(!Qt.colorEqual(fill.color, movingDesign.tint), "never the track's tint");
    }
    // Beside a bar that shows the time, the automatic clock shows the date.
    function test_glanceAutoClock() {
        var glance = makeGlance({ barHasClock: true });
        compare(findChild(glance, "glancePrimary").text, "Sunday");
        glance.barHasClock = false;
        compare(findChild(glance, "glancePrimary").text, "14:05");
    }
    // Given calendar items (the surface hands them over only with the opt-in
    // on), a coming event takes the line, the dot and the hairline in its
    // calendar's colour.
    function test_glanceNextEvent() {
        var glance = makeGlance({ calendarItems: [event()] });
        compare(findChild(glance, "glancePrimary").text, "Event", "no title without its own opt-in");
        compare(findChild(glance, "glanceSecondary").text, " · in 15 min");
        compare(findChild(glance, "glanceDot").color, "#34c759");
        compare(findChild(glance, "glanceHairlineFill").color, "#34c759");
        glance.eventTitles = true;
        compare(findChild(glance, "glancePrimary").text, "Standup");
    }
    // The clock steps once a minute through a single-shot timer re-armed to
    // the next minute, and only while the glance is shown.
    function test_glanceTicksOncePerMinuteWhileShown() {
        var glance = createTemporaryObject(glanceComponent, test);
        var minute = findChild(glance, "glanceMinute");
        verify(minute.running);
        verify(!minute.repeat, "never a repeating timer");
        verify(minute.interval <= 60050 && minute.interval >= 1000);
        glance.visible = false;
        verify(!minute.running, "hidden, it stops");
        glance.visible = true;
        verify(minute.running);
        verify(Math.abs(glance.now.getTime() - Date.now()) < 5000, "shown again, it reads the clock");
    }
}
