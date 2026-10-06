pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../qml/Battery.js" as Battery

// The only file in this plugin that imports Quickshell.Services.UPower.
// Panel.qml loads this through a Loader, only in island mode with power on,
// so the Service-side lifecycle harness never depends on the power stack
// (tests/source-contract.py's check_service_imports and check_upower_owner).
//
// This component holds no baseline logic: it only reports raw samples of the
// display device. The baseline and threshold rules live in PeekModel and
// BatteryModel (qml/Battery.js), where they can be unit tested without UPower.
// Nothing here is stored or logged.
Item {
    id: root
    readonly property var device: UPower.displayDevice
    signal sample(bool present, bool onBattery, real level)

    // UPower documents `percentage` as 0..1. No "> 1 means 0..100" guess: it
    // cannot tell 1% on one scale from 100% on the other. If a live host
    // reports 0..100, this one function is where the scale changes.
    function normalizedLevel(p) { return Math.max(0, Math.min(1, Number(p) || 0)) }

    // Not called from Component.onCompleted: a Loader completes its item
    // before it assigns `item`, so a sample sent from here would reach no
    // Connections on the loader's item and the first plug would be lost.
    // Panel.qml calls this from the loader's onLoaded instead.
    function emitSample() {
        var d = root.device
        var present = !!d && d.ready === true && d.isLaptopBattery === true && d.isPresent === true
        root.sample(present, UPower.onBattery === true, present ? root.normalizedLevel(d.percentage) : 0)
    }

    function stateName(state) {
        switch (state) {
        case UPowerDeviceState.Charging: return "Charging";
        case UPowerDeviceState.Discharging: return "Discharging";
        case UPowerDeviceState.Empty: return "Empty";
        case UPowerDeviceState.FullyCharged: return "FullyCharged";
        case UPowerDeviceState.PendingCharge: return "PendingCharge";
        case UPowerDeviceState.PendingDischarge: return "PendingDischarge";
        }
        return "Unknown";
    }
    // Energy when full against the design capacity, from the first laptop
    // battery that reports it; the aggregate display device does not. -1 when
    // no battery does.
    readonly property real health: {
        var batteries = UPower.devices ? UPower.devices.values : [];
        for (var i = 0; i < batteries.length; ++i) {
            var battery = batteries[i];
            if (battery && battery.isLaptopBattery && battery.healthSupported && battery.healthPercentage > 0)
                return battery.healthPercentage;
        }
        return -1;
    }
    // The full reading for the header gauge and its popover, in the shape
    // qml/Battery.js takes. Power-saver comes from power-profiles-daemon
    // when it runs.
    readonly property var reading: {
        var d = root.device;
        var present = !!d && d.ready === true && d.isLaptopBattery === true && d.isPresent === true;
        return {
            present: present,
            onBattery: UPower.onBattery === true,
            level: present ? root.normalizedLevel(d.percentage) : 0,
            state: present ? root.stateName(d.state) : "Unknown",
            timeToEmpty: present ? Number(d.timeToEmpty) || 0 : 0,
            timeToFull: present ? Number(d.timeToFull) || 0 : 0,
            health: root.health,
            powerSaver: PowerProfiles.profile === PowerProfile.PowerSaver
        };
    }

    // The command behind the popover's power button, [] when no Omarchy power
    // program is on PATH. Probed once per load.
    property var powerCommand: []
    function openPowerSettings() {
        if (root.powerCommand.length > 0)
            Quickshell.execDetached(root.powerCommand);
    }
    Process {
        running: true
        command: ["sh", "-c", 'for program; do command -v "$program" >/dev/null 2>&1 && { printf %s "$program"; exit 0; }; done; exit 1',
            "sh"].concat(Battery.powerPrograms())
        stdout: StdioCollector {
            onStreamFinished: root.powerCommand = Battery.powerCommandFor(text.trim())
        }
    }

    Connections {
        target: UPower
        // The property is `onBattery`, so its change handler takes a second
        // "on": a handler named onBatteryChanged would never connect.
        function onOnBatteryChanged() { root.emitSample() }
    }
    Connections {
        target: root.device
        function onPercentageChanged() { root.emitSample() }
        function onStateChanged() { root.emitSample() }
        function onReadyChanged() { root.emitSample() }
        function onIsPresentChanged() { root.emitSample() }
    }
}
