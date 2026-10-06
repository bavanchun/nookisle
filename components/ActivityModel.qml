pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Activities.js" as Activities

// Pure QtQuick activity arbiter for the closed notch: of a screen
// recording, live music, a running timer and an armed sleep timer, one fills
// the notch (the compact presentation) and the next shrinks to a glyph at
// its trailing end (the minimal one). No Quickshell import, so qmltestrunner
// drives it offscreen. `now` steps once a minute while `ticking`, from a
// single-shot timer re-armed to the next whole minute of the shown
// activity: nothing here loops.
QtObject {
    id: root
    property bool musicLive: false
    // null or { startedAt, path }.
    property var recording: null
    // null or { label, endsAt, totalMs }: the soonest running timer.
    property var timer: null
    // null or { endsAt }: the armed sleep timer.
    property var sleepTimer: null
    // True while the closed notch is on screen and shows an activity that
    // counts minutes.
    property bool ticking: false
    property double now: Date.now()

    readonly property var arbitration: Activities.arbitrate({ musicLive: musicLive, recording: recording,
        timer: timer, sleepTimer: sleepTimer })
    // "", "recording", "music" or "timer".
    readonly property string primary: arbitration.primary
    // "", "recording", "music", "timer" or "sleepTimer".
    readonly property string minimal: arbitration.minimal
    // Changes only when the set of shown activities does, never with time.
    readonly property string key: arbitration.key

    readonly property string timerLabel: timer ? String(timer.label || "Timer") : ""
    readonly property string timerRemaining: timer ? Activities.remainingLabel(Number(timer.endsAt) - now) : ""
    readonly property real timerFraction: timer ? Activities.fraction(timer.endsAt, timer.totalMs, now) : 0
    readonly property string recordingElapsed: recording ? Activities.elapsedLabel(now - Number(recording.startedAt)) : ""
    readonly property string sleepLabel: sleepTimer ? Activities.clockLabel(sleepTimer.endsAt) : ""

    // The minute boundary that matters: the recording's start when it is
    // shown, else the timer's end.
    readonly property double anchor: (primary === "recording" || minimal === "recording") && recording
        ? Number(recording.startedAt) : timer ? Number(timer.endsAt) : 0
    readonly property bool counting: ticking && anchor > 0
    function tick() {
        now = Date.now();
        arm();
    }
    function arm() {
        minuteTick.stop();
        if (!counting)
            return;
        minuteTick.interval = Activities.nextTickMs(Date.now(), anchor);
        minuteTick.start();
    }
    onCountingChanged: if (counting) tick(); else minuteTick.stop()
    onAnchorChanged: if (counting) tick()
    property Timer minuteTick: Timer {
        repeat: false
        onTriggered: root.tick()
    }
}
