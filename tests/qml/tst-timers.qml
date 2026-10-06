import QtQuick
import QtTest
import "../../qml/Timers.js" as Timers

TestCase {
    name: "Timers"
    // `omarchy-reminder show --json`, as it prints.
    function json(reminders) {
        return JSON.stringify({ count: reminders.length, active: reminders.length > 0, tooltip: "", reminders: reminders })
    }
    function reminder(fields) {
        return Object.assign({ unit: "omarchy-reminder-5m-1790500000", timer: "omarchy-reminder-5m-1790500000.timer",
            minutes: 5, message: "", label: "5-min reminder", remaining: "5m", remainingSeconds: 300,
            at: 1790500300, atTime: "16:05" }, fields || {})
    }

    function test_parse() {
        var list = Timers.parse(json([reminder({ message: "Tea" }),
            reminder({ unit: "omarchy-reminder-1m-1790500100", minutes: 1, at: 1790500160 })]))
        compare(list.length, 2)
        compare(list[0].unit, "omarchy-reminder-1m-1790500100", "soonest first")
        compare(list[0].label, "1-min timer", "no message: the minutes name it")
        compare(list[0].at, 1790500160 * 1000, "seconds become ms")
        compare(list[1].label, "Tea")
    }
    function test_parseRejectsWhatItCannotTrust() {
        compare(Timers.parse("not json"), [])
        compare(Timers.parse(""), [])
        compare(Timers.parse(JSON.stringify({ reminders: "none" })), [])
        compare(Timers.parse(json([reminder({ unit: "rm -rf" })])), [], "a unit that is not a reminder is dropped")
        compare(Timers.parse(json([reminder({ at: "soon" })])), [])
        compare(Timers.parse(json([reminder({ message: "a\nb\tc" })]))[0].label, "a b c", "control characters are gone")
        compare(Timers.parse(JSON.stringify({ count: 5, reminders: [reminder()] })).length, 1, "the list, not the count")
    }
    function test_minutesAndLabels() {
        verify(Timers.validMinutes(1))
        verify(Timers.validMinutes(1440))
        verify(!Timers.validMinutes(0))
        verify(!Timers.validMinutes(1441))
        verify(!Timers.validMinutes(2.5))
        verify(!Timers.validMinutes("5"))
        compare(Timers.cleanLabel("  Pasta  "), "Pasta")
        compare(Timers.cleanLabel("x".repeat(100)).length, 80)
        compare(Timers.cleanLabel(undefined), "")
    }
    function test_units() {
        verify(Timers.validUnit("omarchy-reminder-5m-1790500000"))
        verify(!Timers.validUnit("omarchy-reminder-x"))
        verify(!Timers.validUnit("omarchy-reminder-5m-1790500000.timer"))
        verify(!Timers.validUnit("sshd"))
        var list = Timers.parse(json([reminder()]))
        verify(Timers.known(list, "omarchy-reminder-5m-1790500000"))
        verify(!Timers.known(list, "omarchy-reminder-9m-1790500000"), "a well-formed unit not in the list is unknown")
    }
    function test_soonest() {
        var list = Timers.parse(json([reminder(), reminder({ unit: "omarchy-reminder-60m-1790500000", minutes: 60, at: 1790503600 })]))
        var first = Timers.soonest(list, 1790500000 * 1000)
        compare(first.endsAt, 1790500300 * 1000)
        compare(first.totalMs, 5 * 60000)
        compare(Timers.soonest(list, 1790500400 * 1000).endsAt, 1790503600 * 1000, "one already due is skipped")
        compare(Timers.soonest([], 0), null)
    }
    // A unit that leaves the list at its time finished; one that leaves
    // earlier was cancelled.
    function test_finishedOrCancelled() {
        var before = Timers.parse(json([reminder(), reminder({ unit: "omarchy-reminder-60m-1790500000", minutes: 60, at: 1790503600 })]))
        var after = [before[1]]
        compare(Timers.finished(before, after, 1790500300 * 1000 - 1000).length, 1, "within two seconds of its time")
        compare(Timers.finished(before, after, 1790500200 * 1000).length, 0, "a minute early: cancelled")
        compare(Timers.finished(before, before, 1790509999 * 1000).length, 0, "still listed")
    }
}
