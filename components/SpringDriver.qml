pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Motion.js" as Motion

// One spring move: `from` to `to` along Motion.js's closed-form spring,
// driven by a single linear NumberAnimation on `morphT`, so the motion is
// exact and finite and the scene graph goes quiet when it ends. `stepped`
// carries each value to the property being moved; `value` holds the last
// one, for a caller that simply binds to it through moveTo().
QtObject {
    id: driver
    property real from: 0
    property real to: 0
    property real response: 0.42
    property real damping: 0.8
    property real morphT: 0
    readonly property real springDuration: Motion.springDuration(response, damping)
    property int durationOverrideMs: -1
    readonly property real durationSeconds: durationOverrideMs >= 0 ? durationOverrideMs / 1000 : springDuration
    readonly property bool running: animation.running
    property real value: 0
    signal stepped(real value)
    onMorphTChanged: {
        value = from + (to - from) * Motion.normalised(morphT * durationSeconds, response, damping, durationSeconds);
        stepped(value);
    }
    property NumberAnimation animation: NumberAnimation {
        target: driver
        property: "morphT"
        from: 0
        to: 1
        duration: Math.round(driver.durationSeconds * 1000)
    }
    function run(start, end, springResponse, springDamping, durationMs) {
        animation.stop();
        from = start;
        to = end;
        response = springResponse;
        damping = springDamping;
        durationOverrideMs = durationMs === undefined ? -1 : durationMs;
        morphT = 0;
        animation.start();
    }
    function stop() {
        animation.stop();
    }
    // Springs `value` from wherever it is to `target`; `instant` (reduced
    // motion) sets it at once.
    function moveTo(target, springResponse, springDamping, instant) {
        if (instant === true) {
            settle(target);
            return;
        }
        if (target !== value || running)
            run(value, target, springResponse, springDamping);
    }
    function settle(target) {
        animation.stop();
        value = target;
        stepped(value);
    }
}
