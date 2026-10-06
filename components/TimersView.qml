pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import "../qml/Activities.js" as Activities
import "../qml/Timers.js" as Timers

// The Timers sub-view of Home: start an Omarchy reminder from a preset or a
// number of minutes, with an optional label, and see or cancel the running
// ones. The armed sleep timer shows here too, read-only. Remaining times are
// in whole minutes, from ActivityModel's minute step.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    // Minutes, from the timerPresets setting.
    property var presets: []
    // ActivityModel.now: the minute the labels read from.
    property double now: Date.now()
    readonly property var timers: coordinator && Array.isArray(coordinator.timerList) ? coordinator.timerList : []
    readonly property bool available: !!coordinator && coordinator.timersAvailable !== false
    readonly property double sleepDeadline: coordinator ? Number(coordinator.sleepDeadline) || 0 : 0
    function start(minutes) {
        if (!coordinator)
            return;
        coordinator.startTimer(minutes, labelField.text);
        labelField.text = "";
    }
    function focusControls() {
        if (presetRow.children.length > 0 && presetRow.children[0].visible)
            presetRow.children[0].forceActiveFocus(Qt.TabFocusReason);
        else
            minutesField.forceActiveFocus(Qt.TabFocusReason);
    }
    Column {
        x: root.tokens.medium
        y: root.tokens.small
        width: root.width - 2 * root.tokens.medium
        spacing: root.tokens.small
        Row {
            spacing: root.tokens.small
            Flow {
                id: presetRow
                objectName: "timerPresets"
                spacing: root.tokens.small
                Repeater {
                    model: root.presets
                    SettingsButton {
                        required property var modelData
                        objectName: "timerPreset" + modelData
                        tokens: root.tokens
                        enabled: root.available
                        text: Activities.minutesLabel(Number(modelData))
                        Accessible.name: "Start a " + modelData + " minute timer"
                        onClicked: root.start(Number(modelData))
                    }
                }
            }
            SettingsField {
                id: minutesField
                objectName: "timerMinutes"
                tokens: root.tokens
                width: 64
                placeholderText: "min"
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 1440 }
                Accessible.name: "Minutes"
                onAccepted: startButton.clicked()
            }
            SettingsField {
                id: labelField
                objectName: "timerLabel"
                tokens: root.tokens
                width: 150
                maximumLength: 80
                placeholderText: "Label"
                Accessible.name: "Timer label"
                onAccepted: startButton.clicked()
            }
            SettingsButton {
                id: startButton
                objectName: "timerStart"
                tokens: root.tokens
                text: "Start"
                enabled: root.available && minutesField.acceptableInput
                onClicked: root.start(parseInt(minutesField.text, 10))
            }
        }
        Text {
            objectName: "timersUnavailable"
            visible: !root.available
            text: "Timers need Omarchy's reminders (omarchy-reminder), which were not found."
            textFormat: Text.PlainText
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
        Repeater {
            model: root.timers
            Item {
                id: timerRow
                required property var modelData
                objectName: "timerRow"
                width: parent ? parent.width : 0
                height: root.tokens.target
                Text {
                    objectName: "timerRowText"
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - cancel.width - root.tokens.gap
                    elide: Text.ElideRight
                    text: timerRow.modelData.label + "  ·  " + Activities.remainingLabel(timerRow.modelData.at - root.now)
                        + " left, at " + Activities.clockLabel(timerRow.modelData.at)
                    textFormat: Text.PlainText
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.bodySize
                    font.features: { "tnum": 1 }
                }
                SettingsButton {
                    id: cancel
                    objectName: "timerCancel"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    tokens: root.tokens
                    text: "Cancel"
                    Accessible.name: "Cancel " + timerRow.modelData.label
                    onClicked: if (root.coordinator) root.coordinator.cancelTimer(timerRow.modelData.unit)
                }
            }
        }
        Text {
            objectName: "timersSleep"
            visible: root.sleepDeadline > 0
            text: "Sleep timer  ·  pauses at " + Activities.clockLabel(root.sleepDeadline) + " (in Settings)"
            textFormat: Text.PlainText
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
        Text {
            objectName: "timersEmpty"
            visible: root.available && root.timers.length === 0 && root.sleepDeadline <= 0
            text: "No timers running."
            textFormat: Text.PlainText
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
    }
}
