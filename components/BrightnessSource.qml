pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Owns display and keyboard backlight discovery, sysfs reads and brightnessctl
// writes. Display change events arrive through onBacklightChanged() from the
// helper's udev monitor, which the Service keeps watching while this source
// is active. LED brightness changes emit no uevent,
// so the keyboard level is re-read only when keyboardChanged() is called (the
// Service's keyboardBacklightChanged IPC verb, run by the media-key bindings).
// The Service only forwards its samples and status.
Item {
    id: root
    property bool active: false
    property string sysRoot: "/sys"
    property string backlightOverride: ""
    property string brightnessctlBinary: "brightnessctl"
    property string backlightDevice: ""
    property string keyboardDevice: ""
    property real brightnessLevel: -1
    property real keyboardLevel: -1
    property var pendingWrite: null
    property string writingKind: ""
    property bool rediscover: false
    property bool componentReady: false
    property string discoveryRoot: ""
    property string discoveryOverride: ""
    signal sample(string kind, real level, bool muted)

    // The shell receives root and override as positional arguments, never as
    // interpolated code. Prefer the display devices Omarchy's brightness keys
    // target; exclude the Touch Bar from automatic fallback.
    readonly property string discoveryScript:
        'root=$1; wanted=$2\n' +
        'if [ -n "$wanted" ]; then\n' +
        '  set -- "$root"/class/backlight/"$wanted"\n' +
        'else\n' +
        '  set -- "$root"/class/backlight/gmux_backlight "$root"/class/backlight/amdgpu_bl* "$root"/class/backlight/intel_backlight "$root"/class/backlight/acpi_video* "$root"/class/backlight/*\n' +
        'fi\n' +
        'for path in "$@"; do\n' +
        '  [ -r "$path/max_brightness" ] || continue\n' +
        '  name=${path##*/}\n' +
        '  [ -n "$wanted" ] || [ "$name" != appletb_backlight ] || continue\n' +
        '  max=""; read -r max < "$path/max_brightness" || [ -n "$max" ] || continue\n' +
        '  case $max in ""|*[!0-9]*) continue;; esac\n' +
        '  [ "$max" -gt 0 ] || continue\n' +
        '  printf "B %s\\n" "$name"; break\n' +
        'done\n' +
        'for path in "$root"/class/leds/*kbd_backlight*; do\n' +
        '  [ -r "$path/max_brightness" ] || continue\n' +
        '  max=""; read -r max < "$path/max_brightness" || [ -n "$max" ] || continue\n' +
        '  case $max in ""|*[!0-9]*) continue;; esac\n' +
        '  [ "$max" -gt 0 ] || continue\n' +
        '  printf "K %s\\n" "${path##*/}"; break\n' +
        'done'

    function discover() {
        if (!root.active) return
        if (discovery.running) { root.rediscover = true; return }
        root.discoveryRoot = root.sysRoot
        root.discoveryOverride = root.backlightOverride
        // Shell globbing is needed to discover backlight and keyboard sysfs devices under variable paths.
        discovery.command = ["sh", "-c", root.discoveryScript, "sh", root.discoveryRoot, root.discoveryOverride]
        discovery.running = true
    }
    function applyDiscovery(text) {
        if (!root.active || root.discoveryRoot !== root.sysRoot
            || root.discoveryOverride !== root.backlightOverride) return
        var display = "", keyboard = ""
        var lines = String(text).trim().split("\n")
        for (var i = 0; i < lines.length; ++i) {
            if (lines[i].startsWith("B ")) display = lines[i].slice(2)
            if (lines[i].startsWith("K ")) keyboard = lines[i].slice(2)
        }
        root.backlightDevice = display
        root.keyboardDevice = keyboard
        if (display) root.readLevel("brightness", false)
        if (keyboard) root.readLevel("keyboard", false)
    }
    function ratio(valueView, maxView) {
        valueView.reload()
        maxView.reload()
        var value = String(valueView.text()).trim()
        var maximum = String(maxView.text()).trim()
        if (!/^\d+$/.test(value) || !/^\d+$/.test(maximum) || Number(maximum) <= 0) return -1
        return Math.max(0, Math.min(1, Number(value) / Number(maximum)))
    }
    function readLevel(kind, announce) {
        if (kind === "brightness" && root.backlightDevice) {
            var brightness = root.ratio(displayBrightness, displayMax)
            if (brightness < 0) return
            root.brightnessLevel = brightness
            if (announce) root.sample("brightness", brightness, false)
        } else if (kind === "keyboard" && root.keyboardDevice) {
            var keyboard = root.ratio(keyboardBrightness, keyboardMax)
            if (keyboard < 0) return
            root.keyboardLevel = keyboard
            if (announce) root.sample("keyboard", keyboard, false)
        }
    }
    function onBacklightChanged(device) {
        if (root.active && root.backlightDevice && String(device) === root.backlightDevice)
            root.readLevel("brightness", true)
    }
    function keyboardChanged() {
        if (!root.active || !root.keyboardDevice) return false
        root.readLevel("keyboard", true)
        return true
    }
    function setLevel(kind, level) {
        var device = kind === "brightness" ? root.backlightDevice
            : kind === "keyboard" ? root.keyboardDevice : ""
        if (!root.active || !device || !isFinite(level)) return false
        // A display at 0 % blanks many panels; the keyboard may turn off.
        var floor = kind === "brightness" ? 1 : 0
        root.pendingWrite = { kind: kind, device: device, percent: Math.max(floor, Math.round(Math.max(0, Math.min(1, level)) * 100)) }
        root.flushWrite()
        return true
    }
    function flushWrite() {
        if (!root.active || writeProcess.running || !root.pendingWrite) return
        var next = root.pendingWrite
        root.pendingWrite = null
        root.writingKind = next.kind
        writeProcess.command = [root.brightnessctlBinary, "-d", next.device, "set", next.percent + "%"]
        writeProcess.running = true
    }
    onActiveChanged: {
        if (root.active) {
            if (!root.componentReady) return
            root.discover()
        } else {
            discovery.running = false
            writeProcess.running = false
            root.pendingWrite = null
            root.backlightDevice = ""
            root.keyboardDevice = ""
        }
    }
    onSysRootChanged: {
        root.backlightDevice = ""
        root.keyboardDevice = ""
        root.discover()
    }
    onBacklightOverrideChanged: {
        root.backlightDevice = ""
        root.discover()
    }
    Component.onCompleted: {
        root.componentReady = true
        if (root.active) root.discover()
    }

    Process {
        id: discovery
        stdout: StdioCollector { onStreamFinished: root.applyDiscovery(text) }
        onExited: {
            if (root.rediscover && root.active) {
                root.rediscover = false
                Qt.callLater(root.discover)
            }
        }
    }
    Process {
        id: writeProcess
        // LED writes emit no uevent, so every completed write reports the
        // level the device actually applied.
        onExited: {
            var written = root.writingKind
            root.writingKind = ""
            if (root.active && written) root.readLevel(written, true)
            if (root.pendingWrite) Qt.callLater(root.flushWrite)
        }
    }
    FileView { id: displayBrightness; path: root.backlightDevice ? root.sysRoot + "/class/backlight/" + root.backlightDevice + "/brightness" : ""; blockAllReads: true; printErrors: false }
    FileView { id: displayMax; path: root.backlightDevice ? root.sysRoot + "/class/backlight/" + root.backlightDevice + "/max_brightness" : ""; blockAllReads: true; printErrors: false }
    FileView { id: keyboardBrightness; path: root.keyboardDevice ? root.sysRoot + "/class/leds/" + root.keyboardDevice + "/brightness" : ""; blockAllReads: true; printErrors: false }
    FileView { id: keyboardMax; path: root.keyboardDevice ? root.sysRoot + "/class/leds/" + root.keyboardDevice + "/max_brightness" : ""; blockAllReads: true; printErrors: false }
}
