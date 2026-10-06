import QtQuick
import "../qml/Battery.js" as Battery

// Battery state for the header gauge, its popover and the banner, in the
// pattern of PeekModel: pure QtQuick, fed readings by PowerSource, so the
// tests drive it without UPower. The first reading after a load is a
// baseline. With powerStyle "banner", a charger plug or unplug after that,
// and a low (20 %) or critical (10 %) battery warning (warn(), from
// PeekModel's threshold crossing), show the banner for bannerDuration (3 s),
// restarted by a newer one; with "peek" the banner stays off and PeekModel's
// card shows them.
QtObject {
    id: root
    property string powerStyle: "banner"
    property bool enabled: true
    property int bannerDuration: Battery.BANNER_DURATION
    property var reading: ({ present: false, onBattery: false, level: 0, state: "Unknown",
        timeToEmpty: 0, timeToFull: 0, health: -1, powerSaver: false })
    property var baseline: null
    property bool bannerActive: false
    property string bannerKind: ""
    property real bannerLevel: 0
    readonly property bool bannerStyle: powerStyle === "banner"
    readonly property string bannerLabel: Battery.bannerLabel(bannerKind, reading)
    readonly property string fillKind: Battery.fillKind(reading)
    readonly property color fillColour: Battery.fillColour(reading)
    // Emitted once per banner, with "plugged", "unplugged", "low" or
    // "critical" and the level.
    signal bannerRequested(string kind, real level)

    function resetBaseline() {
        baseline = null;
        dismiss();
    }
    function note(next) {
        var kind = Battery.bannerFor(baseline, next);
        baseline = next;
        reading = next;
        if (kind && enabled && bannerStyle)
            show(kind, next.level);
    }
    // A battery warning crossing: a banner in banner style.
    function warn(kind, level) {
        if ((kind === "low" || kind === "critical") && enabled && bannerStyle)
            show(kind, level);
    }
    function show(kind, level) {
        bannerKind = kind;
        bannerLevel = level;
        bannerActive = true;
        bannerTimer.restart();
        bannerRequested(kind, level);
    }
    function dismiss() {
        bannerTimer.stop();
        bannerActive = false;
    }
    onEnabledChanged: if (!enabled) dismiss()
    onBannerStyleChanged: if (!bannerStyle) dismiss()

    property Timer bannerTimer: Timer {
        interval: root.bannerDuration
        onTriggered: root.bannerActive = false
    }
}
