import QtQuick
import QtTest
import "../../components"
import "../../qml/Activities.js" as Activities

TestCase {
    id: test
    name: "ActivityModel"
    Component {
        id: modelComponent
        ActivityModel {}
    }
    readonly property double minute: 60000

    function test_priorityTable() {
        compare(Activities.arbitrate({}).key, "|", "nothing present shows nothing");
        var music = Activities.arbitrate({ musicLive: true });
        compare(music.primary, "music");
        compare(music.minimal, "");
        var musicTimer = Activities.arbitrate({ musicLive: true, timer: {} });
        compare(musicTimer.primary, "music", "music stays compact beside a timer");
        compare(musicTimer.minimal, "timer");
        var recordingMusic = Activities.arbitrate({ musicLive: true, recording: {} });
        compare(recordingMusic.primary, "recording", "a recording outranks the music");
        compare(recordingMusic.minimal, "music");
        var timerOnly = Activities.arbitrate({ timer: {} });
        compare(timerOnly.primary, "timer", "a timer fills an otherwise idle notch");
    }
    function test_sleepTimerIsOnlyMinimal() {
        var alone = Activities.arbitrate({ sleepTimer: {} });
        compare(alone.primary, "", "a sleep timer alone leaves the notch idle");
        compare(alone.minimal, "sleepTimer");
        var withTimer = Activities.arbitrate({ timer: {}, sleepTimer: {} });
        compare(withTimer.primary, "timer");
        compare(withTimer.minimal, "sleepTimer");
    }
    function test_onlyOneMinimal() {
        var all = Activities.arbitrate({ musicLive: true, recording: {}, timer: {}, sleepTimer: {} });
        compare(all.primary, "recording");
        compare(all.minimal, "music", "the next one down; the rest wait");
        compare(all.key, "recording|music");
    }
    function test_labels() {
        compare(Activities.remainingLabel(30 * 1000), "<1m");
        compare(Activities.remainingLabel(59 * minute), "59m");
        compare(Activities.remainingLabel(58 * minute + 1), "59m", "a countdown rounds up");
        compare(Activities.remainingLabel(65 * minute), "1h 05m");
        compare(Activities.remainingLabel(0), "0m");
        compare(Activities.elapsedLabel(59 * 1000), "<1m");
        compare(Activities.elapsedLabel(12 * minute + 59 * 1000), "12m", "elapsed time rounds down");
        compare(Activities.elapsedLabel(125 * minute), "2h 05m");
        compare(Activities.clockLabel(new Date(2026, 8, 27, 23, 5).getTime()), "23:05");
    }
    function test_fractionStepsWithTheLabel() {
        var now = 1000000;
        compare(Activities.fraction(now + 10 * minute, 20 * minute, now), 0.5);
        compare(Activities.fraction(now + 9 * minute + 1, 20 * minute, now), 0.5, "the ring steps to the minute");
        compare(Activities.fraction(now - 1, 20 * minute, now), 0);
        compare(Activities.fraction(now + minute, 0, now), 0, "an unknown total draws an empty ring");
    }
    function test_nextTickAligned() {
        var anchor = 10 * minute;
        compare(Activities.nextTickMs(anchor - 90 * 1000, anchor), 30 * 1000, "to the next whole minute of the anchor");
        compare(Activities.nextTickMs(anchor - 60 * 1000, anchor), 60 * 1000);
        compare(Activities.nextTickMs(anchor + 500, anchor), 59500, "counting up from a start works the same");
        verify(Activities.nextTickMs(anchor - 60 * 1000 - 200, anchor) >= 1000, "never faster than a second");
    }
    function test_keyStableAcrossTime() {
        var model = createTemporaryObject(modelComponent, test, { musicLive: true });
        model.timer = { label: "Tea", endsAt: Date.now() + 5 * minute, totalMs: 5 * minute };
        compare(model.key, "music|timer");
        var keyChanges = 0;
        model.keyChanged.connect(function () { keyChanges++; });
        model.timer = { label: "Tea", endsAt: Date.now() + 4 * minute, totalMs: 5 * minute };
        model.now = Date.now() + minute;
        compare(keyChanges, 0, "time and a moved deadline never change the shown set");
        compare(model.timerLabel, "Tea");
    }
    function test_tickRunsOnlyWhileTicking() {
        var model = createTemporaryObject(modelComponent, test);
        model.timer = { label: "Timer", endsAt: Date.now() + 3 * minute, totalMs: 5 * minute };
        verify(!model.minuteTick.running, "no tick while the island is not on screen");
        model.ticking = true;
        verify(model.minuteTick.running);
        verify(!model.minuteTick.repeat, "a single shot, re-armed each minute");
        verify(model.minuteTick.interval <= minute && model.minuteTick.interval >= 1000);
        model.ticking = false;
        verify(!model.minuteTick.running);
        model.ticking = true;
        model.timer = null;
        verify(!model.minuteTick.running, "nothing left to count");
        model.sleepTimer = { endsAt: Date.now() + 30 * minute };
        verify(!model.minuteTick.running, "the sleep timer shows a fixed time and never ticks");
    }
    function test_recordingAnchorsTheTick() {
        var model = createTemporaryObject(modelComponent, test, { ticking: true });
        var start = Date.now() - 90 * 1000;
        model.recording = { startedAt: start, path: "/tmp/a.mp4" };
        compare(model.primary, "recording");
        compare(model.recordingElapsed, "1m");
        compare(model.anchor, start);
        verify(Math.abs(model.minuteTick.interval - 30 * 1000) < 1500, "the label steps on the recording's own minutes");
    }
}
