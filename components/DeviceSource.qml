pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth

// Bluetooth devices, as raw samples for qml/DeviceEvents.js: one per device
// when it appears and on every change of its connection or battery. The
// only file that imports Quickshell.Bluetooth; Panel.qml loads it only in
// the island with device peeks on. Battery levels come from BlueZ's
// Battery1, which a headset reports only if it sends them; batteryAvailable
// says whether it does.
Item {
    id: root
    signal deviceSample(var sample)
    // Touching the list at load starts the module; a first read later would
    // find it empty.
    readonly property var devices: Bluetooth.devices.values
    Instantiator {
        model: root.devices
        delegate: QtObject {
            required property var modelData
            readonly property var sample: ({
                address: String(modelData.address || ""),
                name: String(modelData.name || modelData.deviceName || "Bluetooth device"),
                icon: String(modelData.icon || ""),
                connected: modelData.connected === true,
                batteryAvailable: modelData.batteryAvailable === true,
                battery: Number(modelData.battery) || 0
            })
            onSampleChanged: root.deviceSample(sample)
            Component.onCompleted: root.deviceSample(sample)
        }
    }
}
