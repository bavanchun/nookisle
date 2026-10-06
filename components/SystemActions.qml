import QtQuick
import Quickshell
import "../qml/Timers.js" as Timers

// The island's commands to Omarchy, each an argument array with a fixed
// program and never a shell line: start or cancel a reminder, and stop a
// screen recording. The Service validates what it passes; these check again.
QtObject {
    id: root
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    function startReminder(minutes, label) {
        if (!Timers.validMinutes(minutes))
            return false;
        var text = Timers.cleanLabel(label);
        Quickshell.execDetached(["omarchy-reminder", String(minutes)].concat(text ? [text] : []));
        return true;
    }
    function cancelReminder(unit) {
        if (!Timers.validUnit(unit))
            return false;
        Quickshell.execDetached(["systemctl", "--user", "stop", unit + ".timer"]);
        if (root.runtimeDir.charAt(0) === "/")
            Quickshell.execDetached(["rm", "-f", root.runtimeDir + "/omarchy-reminders/" + unit + ".message"]);
        Quickshell.execDetached(["omarchy-shell", "-q", "omarchy.indicators", "refresh"]);
        return true;
    }
    function stopRecording() {
        Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"]);
    }
}
