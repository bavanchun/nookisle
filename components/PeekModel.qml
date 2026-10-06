pragma ComponentBehavior: Bound

import QtQuick

// Pure QtQuick peek state: turns track changes and power samples into a short
// bloom of the pill. No Quickshell import, so qmltestrunner drives it
// offscreen. Panel.qml is the only thing that feeds it: noteTrack() from the
// selected endpoint's track token, notePower() from PowerSource's sample
// signal, and showEvent() for a device, a finished timer or a capture.
// Priority is HUD > timerDone > power > device > capture > track; the HUD
// side lives in Panel.qml, which suppresses this model while the HUD shows.
QtObject {
    id: root
    // Optional: falls back to the plan's constants so this stays usable
    // without a live DesignTokens instance (as HudModel does).
    property var tokens: null
    property bool active: false
    // "track", "power", "device", "timerDone" or "capture".
    property string kind: "track"
    // An event peek's content: { icon, title, detail, level (-1 hides the
    // bar), alert }.
    property var event: null
    readonly property var priority: ({ track: 1, capture: 2, device: 3, power: 4, timerDone: 5 })
    // A showing peek that outranks `next`, which must then wait its turn
    // (it does not queue: the moment is gone).
    function outranks(next) {
        return root.active && root.priority[root.kind] > root.priority[next]
    }
    // "plugged", "unplugged", "low" or "critical".
    property string powerKind: "plugged"
    property real powerLevel: 0
    // True while the island is hidden, expanded, explicitly open, fullscreen
    // or showing the HUD (Panel.qml binds this). A suppressed model still
    // tracks both baselines, so ending the suppression never replays a
    // change the user already saw in the expanded card.
    property bool suppressed: false
    property bool trackEnabled: true
    property bool powerEnabled: true
    readonly property real lowThreshold: 0.20
    readonly property real criticalThreshold: 0.10
    // A threshold re-arms only once the level climbs this far above it, so a
    // level wobbling on the line cannot peek twice.
    readonly property real rearmMargin: 0.02

    property string trackEndpoint: ""
    property string trackKey: ""
    // {onBattery, level} of the last present sample, or null: the next
    // present sample is then a baseline only.
    property var powerBaseline: null
    property bool lowArmed: true
    property bool criticalArmed: true

    function resetTrackBaseline() {
        root.trackEndpoint = ""
        root.trackKey = ""
        settle.stop()
    }
    function resetPowerBaseline() { root.powerBaseline = null }

    // The first key, an empty key and a source switch only move the baseline.
    // A new track on the same source waits out a short settle window, so a
    // player that publishes title and artist in separate updates peeks once,
    // with the final metadata.
    function noteTrack(endpointKey, nextTrackKey) {
        var endpoint = String(endpointKey || "")
        var track = String(nextTrackKey || "")
        if (!endpoint || !track || !root.trackKey || endpoint !== root.trackEndpoint) {
            root.trackEndpoint = endpoint
            root.trackKey = track
            settle.stop()
            return
        }
        if (track === root.trackKey)
            return
        root.trackKey = track
        if (root.suppressed)
            settle.stop()
        else
            settle.restart()
    }

    // A low or critical threshold crossing, whatever the peek style: the
    // host shows it as a banner when power peeks are off.
    signal batteryWarning(string kind, real level)

    function notePower(present, onBattery, level) {
        var value = Math.max(0, Math.min(1, Number(level) || 0))
        var battery = onBattery === true
        // A machine without a battery, or a battery that is not ready yet,
        // never peeks; its next present sample starts from a fresh baseline.
        if (present !== true) {
            root.powerBaseline = null
            return
        }
        var previous = root.powerBaseline
        root.powerBaseline = { onBattery: battery, level: value }
        if (value > root.lowThreshold + root.rearmMargin || !battery)
            root.lowArmed = true
        if (value > root.criticalThreshold + root.rearmMargin || !battery)
            root.criticalArmed = true
        if (!previous) {
            // Already below a threshold at the first sample: do not announce
            // a crossing that happened before the plugin was watching.
            if (battery && value <= root.lowThreshold) root.lowArmed = false
            if (battery && value <= root.criticalThreshold) root.criticalArmed = false
            return
        }
        // Keep a showing power peek's level live (a charger topping up).
        if (root.active && root.kind === "power")
            root.powerLevel = value
        if (battery !== previous.onBattery) {
            root.showPower(battery ? "unplugged" : "plugged", value)
            return
        }
        if (!battery)
            return
        if (root.criticalArmed && previous.level > root.criticalThreshold && value <= root.criticalThreshold) {
            root.criticalArmed = false
            root.lowArmed = false
            root.batteryWarning("critical", value)
            root.showPower("critical", value)
        } else if (root.lowArmed && previous.level > root.lowThreshold && value <= root.lowThreshold) {
            root.lowArmed = false
            root.batteryWarning("low", value)
            root.showPower("low", value)
        }
    }

    function show(showKind) {
        if (showKind !== "track") return
        if (root.suppressed || !root.trackEnabled) return
        // A track change never covers any other peek still on screen.
        if (root.outranks("track")) return
        root.kind = "track"
        root.active = true
        dismissTimer.interval = root.tokens ? root.tokens.trackPeekDuration : 3000
        dismissTimer.restart()
    }

    function showPower(showKind, level) {
        if (root.suppressed || !root.powerEnabled || root.outranks("power")) return
        root.powerKind = showKind
        root.powerLevel = Math.max(0, Math.min(1, Number(level) || 0))
        root.kind = "power"
        root.active = true
        dismissTimer.interval = root.tokens ? root.tokens.powerPeekDuration : 2500
        dismissTimer.restart()
    }

    // A device, timerDone or capture peek for `duration` ms. False when it
    // was suppressed or outranked.
    function showEvent(showKind, payload, duration) {
        if (root.suppressed || root.priority[showKind] === undefined || root.outranks(showKind)) return false
        root.event = payload
        root.kind = showKind
        root.active = true
        dismissTimer.interval = Math.max(1, Number(duration) || 2500)
        dismissTimer.restart()
        return true
    }
    // New content for the event peek on screen (a connect that also became
    // the sound output), keeping its time.
    function updateEvent(showKind, payload) {
        if (root.active && root.kind === showKind) root.event = payload
    }
    function dismiss() {
        dismissTimer.stop()
        root.active = false
    }

    onSuppressedChanged: if (root.suppressed) {
        settle.stop()
        root.dismiss()
    }
    onTrackEnabledChanged: if (!root.trackEnabled) {
        settle.stop()
        if (root.active && root.kind === "track") root.dismiss()
    }
    onPowerEnabledChanged: if (!root.powerEnabled && root.active && root.kind === "power") root.dismiss()

    property Timer settle: Timer {
        interval: 250
        repeat: false
        onTriggered: root.show("track")
    }
    property Timer dismissTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: root.active = false
    }
}
