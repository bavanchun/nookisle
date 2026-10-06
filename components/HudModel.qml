pragma ComponentBehavior: Bound

import QtQuick

// Pure QtQuick HUD state for volume, display brightness, keyboard backlight
// and microphone events. No Quickshell import, so tests drive it offscreen.
QtObject {
    id: root
    // Optional: falls back to the plan's 1.5s constant so this stays usable
    // without a live DesignTokens instance (as the other pure components do).
    property var tokens: null
    property int duration: tokens ? tokens.hudDuration : 1500
    property bool active: false
    // True while a HUD bar is pressed: dismissal waits for the release.
    property bool held: false
    // The HUD view whose bar is held, when it said (hold()): with an island
    // on every screen, only that island treats the drag as its own.
    property var heldBy: null
    function hold(owner, pressed) {
        if (pressed) {
            heldBy = owner;
            held = true;
        } else if (heldBy === owner) {
            heldBy = null;
            held = false;
        }
    }
    property string kind: "volume"
    property real level: 0
    property bool muted: false
    property string label: "Volume"
    readonly property bool hasBar: kind !== "mic"
    readonly property string icon: kind === "mic" ? (muted ? "mic-muted" : "mic")
        : kind === "keyboard" ? "keyboard"
        : kind === "brightness" ? "brightness" : (muted ? "muted" : "volume")
    // True while the island is expanded, an explicit expansion is pending, or
    // the output is fullscreen (Panel.qml binds this). A suppressed model
    // still tracks the volume baseline, so the first sample after suppression
    // ends reflects the true level rather than a stale one.
    property bool suppressed: false
    // Panel supplies the media-key ownership gate. Pure model tests can use
    // the same callback without loading Quickshell's runtime files.
    property var readoutAllowed: null
    // Local controls produce an ordinary source sample too. Reserve one
    // resulting sample so a media-key fallback record does not hide it.
    property var localExpected: ({})
    function expectLocal(kind, count) {
        var next = Object.assign({}, root.localExpected)
        var prior = next[kind]
        var remaining = prior && prior.until >= Date.now() ? prior.remaining : 0
        // Brightness writes coalesce during a drag: many pointer moves can
        // produce one source sample. Never bank extra exemptions for a key.
        next[kind] = { remaining: kind === "volume" ? remaining + (count || 1) : 1,
            until: Date.now() + 1500 }
        root.localExpected = next
    }
    function cancelLocal(kind) {
        var next = Object.assign({}, root.localExpected)
        delete next[kind]
        root.localExpected = next
    }
    function takeLocal(kind) {
        var pending = root.localExpected[kind]
        if (!pending || pending.until < Date.now()) {
            root.cancelLocal(kind)
            return false
        }
        if (pending.remaining <= 1) root.cancelLocal(kind)
        else {
            var next = Object.assign({}, root.localExpected)
            next[kind] = { remaining: pending.remaining - 1, until: pending.until }
            root.localExpected = next
        }
        return true
    }
    // sinkId -> {volume, muted}. The first sample for a sinkId, including the
    // very first sample after the default sink changes, is stored here only.
    property var baselines: ({})

    // Clears every stored per-sink baseline. Panel.qml calls this whenever
    // the volume source is (re)loaded, so a sink that was already known
    // before the Loader was torn down (a `hud` toggle, a `barHidden` flip)
    // starts from a fresh baseline instead of comparing against a reading
    // that predates the reload and may no longer reflect reality (code
    // review M4).
    function resetBaselines() { root.baselines = ({}) }

    function noteVolume(sinkId, volume, muted) {
        var id = String(sinkId)
        var known = Object.prototype.hasOwnProperty.call(root.baselines, id)
        var previous = known ? root.baselines[id] : null
        var next = Object.assign({}, root.baselines)
        next[id] = { volume: volume, muted: muted === true }
        root.baselines = next
        if (!known) return
        if (Math.abs(volume - previous.volume) > 0.001 || muted !== previous.muted)
            root.show("volume", volume, muted === true)
    }

    function show(showKind, showLevel, showMuted, showLabel) {
        if (root.suppressed) return
        if (["volume", "brightness", "keyboard", "mic"].indexOf(showKind) < 0) return
        if (root.held && showKind !== root.kind) return
        if (!root.takeLocal(showKind) && root.readoutAllowed && !root.readoutAllowed(showKind)) return
        root.kind = showKind
        root.level = showLevel
        root.muted = showMuted === true
        root.label = showLabel || (showKind === "mic" ? (root.muted ? "Microphone muted" : "Microphone on")
            : showKind === "keyboard" ? "Keyboard backlight"
            : showKind === "brightness" ? "Brightness" : (root.muted ? "Muted" : "Volume"))
        root.active = true
        root.extend()
    }

    function extend() {
        if (root.active && !root.suppressed && !root.held) hudTimer.restart()
    }

    onHeldChanged: {
        if (root.held) hudTimer.stop()
        else root.extend()
    }

    onSuppressedChanged: if (root.suppressed) root.active = false

    property Timer hudTimer: Timer {
        interval: root.duration
        repeat: false
        onTriggered: if (!root.held) root.active = false
    }
}
