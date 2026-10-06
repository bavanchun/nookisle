import QtQuick

// Holds a busy guard while `active` is true: beginBusy() once when it turns
// on, endBusy() once when it turns off or this object goes away, so a menu or
// editor that is destroyed while open never leaks a busy count.
QtObject {
    property var guard: null
    property bool active: false
    property var held: null
    function sync() {
        if (active && !held && guard) {
            held = guard
            held.beginBusy()
        } else if (!active && held) {
            var previous = held
            held = null
            previous.endBusy()
        }
    }
    onActiveChanged: sync()
    onGuardChanged: if (!active) sync()
    Component.onCompleted: sync()
    Component.onDestruction: {
        if (held) {
            var previous = held
            held = null
            previous.endBusy()
        }
    }
}
