pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import "../qml/Battery.js" as Battery

// The popover under the header gauge: level, state, the time estimate,
// health (energy when full against design capacity), power-saver, and a
// button to Omarchy's power controls shown only when PowerSource found one
// on PATH.
Rectangle {
    id: root
    required property var tokens
    property var reading: ({ present: false, onBattery: false, level: 0, state: "Unknown",
        timeToEmpty: 0, timeToFull: 0, health: -1, powerSaver: false })
    property bool powerAvailable: false
    property real maximumHeight: implicitHeight
    signal powerSettingsRequested
    width: 280
    implicitHeight: content.implicitHeight + tokens.inset * 2
    height: Math.min(implicitHeight, maximumHeight)
    radius: tokens.heroArtRadius
    color: tokens.raisedSurface
    border.color: tokens.raisedStroke

    component Line: Text {
        width: content.width
        color: Qt.rgba(1, 1, 1, 0.75)
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.bodySize
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        visible: text.length > 0
    }
    Flickable {
        id: body
        objectName: "popoverBody"
        x: root.tokens.inset
        y: root.tokens.inset
        width: root.width - root.tokens.inset * 2
        height: Math.max(0, root.height - root.tokens.inset * 2)
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {
            objectName: "popoverScrollIndicator"
            visible: body.contentHeight > body.height
            active: visible
            contentItem: Rectangle {
                implicitWidth: 3
                radius: width / 2
                color: root.tokens.secondary
            }
        }
        Column {
            id: content
            width: body.width
            spacing: root.tokens.small
            Row {
                width: parent.width
                Text {
                    width: parent.width - percentText.width
                    text: "Battery"
                    color: "white"
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.titleSize
                    font.weight: Font.DemiBold
                }
                Text {
                    id: percentText
                    objectName: "popoverPercent"
                    text: Battery.percent(root.reading.level) + "%"
                    textFormat: Text.PlainText
                    color: "white"
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.titleSize
                    font.weight: Font.DemiBold
                }
            }
            Line { objectName: "popoverState"; text: Battery.stateLabel(root.reading) }
            Line { objectName: "popoverTime"; text: Battery.timeLabel(root.reading) }
            Line { objectName: "popoverHealth"; text: Battery.healthLabel(root.reading) }
            Line { objectName: "popoverSaver"; text: root.reading.powerSaver ? "Power saver is on" : "" }
            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.12)
                visible: powerButton.visible
            }
            Controls.Button {
                id: powerButton
                objectName: "popoverPowerSettings"
                visible: root.powerAvailable
                text: "Power settings"
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
                // A Text of its own, so the label renders like the rest of
                // the island's text (the style's label has no renderType).
                contentItem: Text {
                    text: powerButton.text
                    textFormat: Text.PlainText
                    font: powerButton.font
                    renderType: root.tokens.textRenderType
                    color: powerButton.palette.buttonText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                onActiveFocusChanged: if (activeFocus) body.contentY = Math.max(0, body.contentHeight - body.height)
                onClicked: root.powerSettingsRequested()
            }
        }
    }
}
