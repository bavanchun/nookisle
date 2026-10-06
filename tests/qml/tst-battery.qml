import QtQuick
import QtTest
import "../../components"
import "../../qml/Battery.js" as Battery

TestCase {
    id: test
    name: "Battery"
    width: 320
    height: 400
    when: windowShown
    visible: true

    DesignTokens {
        id: design
        reducedMotion: true
    }
    Component {
        id: modelComponent
        BatteryModel {
            property var requests: []
            onBannerRequested: (kind, level) => requests = requests.concat([{ kind: kind, level: level }])
        }
    }
    Component {
        id: gaugeComponent
        BatteryGauge {}
    }
    Component {
        id: popoverComponent
        BatteryPopover {
            tokens: design
            property int powerRequests: 0
            onPowerSettingsRequested: powerRequests++
        }
    }

    function reading(fields) {
        return Object.assign({ present: true, onBattery: true, level: 0.5, state: "Discharging",
            timeToEmpty: 0, timeToFull: 0, health: -1, powerSaver: false }, fields || {})
    }

    function test_fill_kind_data() {
        return [
            { tag: "normal on battery", fields: {}, kind: "normal" },
            { tag: "21 percent", fields: { level: 0.21 }, kind: "normal" },
            { tag: "20 percent is low", fields: { level: 0.20 }, kind: "low" },
            { tag: "5 percent", fields: { level: 0.05 }, kind: "low" },
            { tag: "low but charging", fields: { level: 0.1, onBattery: false, state: "Charging" }, kind: "charging" },
            { tag: "low but plugged in", fields: { level: 0.1, onBattery: false, state: "PendingCharge" }, kind: "charging" },
            { tag: "charging", fields: { level: 0.6, onBattery: false, state: "Charging" }, kind: "charging" },
            { tag: "full", fields: { level: 1, onBattery: false, state: "FullyCharged" }, kind: "charging" },
            { tag: "saver outranks low", fields: { level: 0.1, powerSaver: true }, kind: "saver" },
            { tag: "saver outranks charging", fields: { onBattery: false, state: "Charging", powerSaver: true }, kind: "saver" }
        ]
    }
    function test_fill_kind(data) {
        compare(Battery.fillKind(reading(data.fields)), data.kind)
        compare(Battery.fillColour(reading(data.fields)), Battery.FILL_COLOURS[data.kind])
    }

    function test_labels() {
        compare(Battery.percent(0.784), 78)
        compare(Battery.percent(2), 100)
        compare(Battery.percent(-1), 0)
        compare(Battery.duration(0), "")
        compare(Battery.duration(59), "1 min")
        compare(Battery.duration(12 * 60), "12 min")
        compare(Battery.duration(65 * 60), "1 h 05 min")
        compare(Battery.duration(135 * 60), "2 h 15 min")
        compare(Battery.stateLabel(reading({ state: "Charging" })), "Charging")
        compare(Battery.stateLabel(reading({ state: "FullyCharged", onBattery: false })), "Fully charged")
        compare(Battery.stateLabel(reading({ state: "Unknown", onBattery: false })), "Plugged in")
        compare(Battery.timeLabel(reading({ timeToEmpty: 90 * 60 })), "1 h 30 min left")
        compare(Battery.timeLabel(reading({ state: "Charging", onBattery: false, timeToFull: 30 * 60 })), "30 min to full")
        compare(Battery.timeLabel(reading({ state: "PendingCharge", onBattery: false, timeToFull: 600 })), "")
        compare(Battery.timeLabel(reading()), "", "no estimate, no label")
        compare(Battery.healthLabel(reading({ health: 90.15 })), "90 % of design capacity")
        compare(Battery.healthLabel(reading({ health: 104 })), "100 % of design capacity")
        compare(Battery.healthLabel(reading({ health: -1 })), "")
    }

    function test_banner_trigger() {
        compare(Battery.bannerFor(null, reading()), "", "the first reading is a baseline")
        compare(Battery.bannerFor(reading(), reading({ level: 0.4 })), "", "a level change alone is no banner")
        compare(Battery.bannerFor(reading(), reading({ onBattery: false, state: "Charging" })), "plugged")
        compare(Battery.bannerFor(reading({ onBattery: false }), reading()), "unplugged")
        compare(Battery.bannerFor(reading({ present: false }), reading({ onBattery: false })), "",
            "no banner without a battery before")
        compare(Battery.bannerFor(reading(), reading({ present: false, onBattery: false })), "",
            "no banner without a battery now")
    }

    function test_power_command() {
        compare(Battery.powerPrograms(), ["omarchy-launch-power", "omarchy-shell"])
        compare(Battery.powerCommandFor("omarchy-shell"), ["omarchy-shell", "shell", "toggle", "omarchy.power"])
        compare(Battery.powerCommandFor("omarchy-launch-power"), ["omarchy-launch-power"])
        compare(Battery.powerCommandFor(""), [])
        compare(Battery.powerCommandFor("rm"), [])
    }

    function test_banner_lasts_three_seconds() {
        var model = createTemporaryObject(modelComponent, test)
        compare(model.bannerDuration, 3000)
        model.note(reading())
        verify(!model.bannerActive, "baseline")
        model.note(reading({ onBattery: false, state: "Charging", level: 0.51 }))
        verify(model.bannerActive)
        compare(model.bannerKind, "plugged")
        compare(model.bannerLevel, 0.51)
        compare(model.requests, [{ kind: "plugged", level: 0.51 }])
        wait(2700)
        verify(model.bannerActive, "still showing before 3 s")
        tryVerify(function () { return !model.bannerActive }, 800, "gone after 3 s")
    }

    function test_newer_change_restarts_the_banner() {
        var model = createTemporaryObject(modelComponent, test, { bannerDuration: 300 })
        model.note(reading())
        model.note(reading({ onBattery: false }))
        wait(200)
        model.note(reading())
        compare(model.bannerKind, "unplugged")
        compare(model.requests.length, 2)
        wait(200)
        verify(model.bannerActive, "the second change restarted the timer")
        tryVerify(function () { return !model.bannerActive }, 400)
    }

    function test_peek_style_and_disabled_show_no_banner() {
        var model = createTemporaryObject(modelComponent, test, { powerStyle: "peek" })
        model.note(reading())
        model.note(reading({ onBattery: false }))
        verify(!model.bannerActive)
        compare(model.requests.length, 0)
        compare(model.reading.onBattery, false, "readings still update for the gauge")
        model.powerStyle = "banner"
        model.enabled = false
        model.note(reading())
        verify(!model.bannerActive)
        model.enabled = true
        model.note(reading({ onBattery: false }))
        verify(model.bannerActive)
        model.powerStyle = "peek"
        verify(!model.bannerActive, "switching to peek dismisses a showing banner")
    }

    // Low and critical warnings banner in the default banner style, with
    // their own labels; peek style and a disabled model leave it to the peek.
    function test_warnings_banner_in_banner_style() {
        var model = createTemporaryObject(modelComponent, test)
        compare(model.powerStyle, "banner", "banner is the default style")
        model.warn("low", 0.2)
        verify(model.bannerActive, "a low warning banners")
        compare(model.bannerLabel, "Battery low")
        compare(model.bannerLevel, 0.2)
        model.warn("critical", 0.1)
        compare(model.bannerLabel, "Battery critical")
        compare(model.requests.map(function (r) { return r.kind }), ["low", "critical"])
        model.warn("plugged", 1)
        compare(model.requests.length, 2, "warn() takes only warnings")
        model.dismiss()
        model.powerStyle = "peek"
        model.warn("low", 0.2)
        verify(!model.bannerActive, "peek style leaves the warning to the peek")
        model.powerStyle = "banner"
        model.enabled = false
        model.warn("critical", 0.1)
        verify(!model.bannerActive, "notifications off shows nothing")
        model.enabled = true
        model.note(reading())
        model.note(reading({ onBattery: false, state: "Charging" }))
        compare(model.bannerLabel, "Charging")
        model.note(reading())
        compare(model.bannerLabel, "On battery")
    }

    // A plug-in says what UPower says: charging, full, or plugged in and not
    // charging (a charge limit); warnings and unplugging keep their words.
    function test_banner_label_follows_the_reading() {
        compare(Battery.bannerLabel("plugged", reading({ onBattery: false, state: "Charging" })), "Charging")
        compare(Battery.bannerLabel("plugged", reading({ onBattery: false, state: "FullyCharged", level: 1 })), "Fully charged")
        compare(Battery.bannerLabel("plugged", reading({ onBattery: false, state: "PendingCharge", level: 0.8 })), "Plugged in")
        compare(Battery.bannerLabel("unplugged", reading()), "On battery")
        compare(Battery.bannerLabel("low", reading()), "Battery low")
        compare(Battery.bannerLabel("critical", reading()), "Battery critical")
        var model = createTemporaryObject(modelComponent, test)
        model.note(reading())
        model.note(reading({ onBattery: false, state: "FullyCharged", level: 1 }))
        compare(model.bannerLabel, "Fully charged", "the model's banner reads its reading")
    }
    function test_reset_baseline() {
        var model = createTemporaryObject(modelComponent, test)
        model.note(reading())
        model.note(reading({ onBattery: false }))
        verify(model.bannerActive)
        model.resetBaseline()
        verify(!model.bannerActive)
        model.note(reading())
        verify(!model.bannerActive, "the first reading after a reset is a baseline again")
        compare(model.fillKind, "normal")
    }

    function test_gauge() {
        var gauge = createTemporaryObject(gaugeComponent, test, { reading: reading({ level: 0.5 }) })
        compare(gauge.children[0].width, 30)
        compare(gauge.children[0].height, 12)
        var fill = findChild(gauge, "batteryFill")
        compare(fill.width, Math.round(23 * 0.5))
        compare(fill.color, Qt.color(Battery.FILL_COLOURS.normal))
        compare(findChild(gauge, "batteryPercent").text, "50%")
        verify(findChild(gauge, "batteryPercent").visible)
        gauge.reading = reading({ level: 0.15 })
        compare(fill.color, Qt.color(Battery.FILL_COLOURS.low))
        var status = findChild(gauge, "batteryStatusIcon")
        verify(status.visible)
        compare(status.text, "!")
        gauge.showStatusIcon = false
        verify(!status.visible)
        gauge.showStatusIcon = true
        gauge.reading = reading({ level: 0.15, powerSaver: true })
        compare(fill.color, Qt.color(Battery.FILL_COLOURS.saver))
        gauge.reading = reading({ level: 1, onBattery: false, state: "FullyCharged" })
        compare(fill.width, 23)
        compare(fill.color, Qt.color(Battery.FILL_COLOURS.charging))
        compare(status.text, "⚡")
        gauge.showPercent = false
        verify(!findChild(gauge, "batteryPercent").visible)
    }

    function test_popover() {
        var popover = createTemporaryObject(popoverComponent, test, {
            reading: reading({ level: 0.78, state: "Charging", onBattery: false, timeToFull: 40 * 60, health: 90.1 }) })
        compare(findChild(popover, "popoverPercent").text, "78%")
        compare(findChild(popover, "popoverState").text, "Charging")
        compare(findChild(popover, "popoverTime").text, "40 min to full")
        compare(findChild(popover, "popoverHealth").text, "90 % of design capacity")
        verify(!findChild(popover, "popoverSaver").visible)
        var button = findChild(popover, "popoverPowerSettings")
        verify(!button.visible, "no Omarchy power program, no button")
        popover.powerAvailable = true
        verify(button.visible)
        verify(!findChild(popover, "popoverScrollIndicator").visible,
            "an uncapped popover has no scroll cue")
        waitForRendering(popover)
        mouseClick(button)
        compare(popover.powerRequests, 1)
        popover.reading = reading({ health: -1, powerSaver: true })
        verify(!findChild(popover, "popoverHealth").visible, "no health line without a design capacity")
        verify(!findChild(popover, "popoverTime").visible)
        verify(findChild(popover, "popoverSaver").visible)
    }

    function test_cappedPopoverScrollsToPowerSettings() {
        var popover = createTemporaryObject(popoverComponent, test, {
            maximumHeight: 85, powerAvailable: true,
            reading: reading({ level: 0.15, timeToEmpty: 3600, health: 91, powerSaver: true }) })
        compare(popover.height, 85)
        var body = findChild(popover, "popoverBody")
        verify(body.contentHeight > body.height, "the details overflow the capped body")
        var cue = findChild(popover, "popoverScrollIndicator")
        verify(cue.visible && cue.active && cue.size < 1,
            "the capped body shows where more details can be found")
        body.contentY = body.contentHeight - body.height
        var button = findChild(popover, "popoverPowerSettings")
        var top = button.mapToItem(body, 0, 0).y
        verify(top >= 0 && top + button.height <= body.height,
            "scrolling brings the Power settings button fully into view")
        mouseClick(button)
        compare(popover.powerRequests, 1)
    }
}
