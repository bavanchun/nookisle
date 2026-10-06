import QtQuick
import "../qml/Battery.js" as Battery

// The header battery gauge: a 30x12 outline with a cap, filled to the level
// in the colour qml/Battery.js picks (amber power-saver, red when low on
// battery, green charging or plugged in, otherwise white), and an optional
// percentage beside it.
Row {
    id: root
    property var reading: ({ present: false, onBattery: false, level: 0, state: "Unknown", powerSaver: false })
    property bool showPercent: true
    property bool showStatusIcon: true
    property string fontFamily: "sans-serif"
    // The owner's text rendering: grayscale on the island (textRenderType).
    property int textRenderType: Text.NativeRendering
    property int fontSize: 11
    readonly property string fillKind: Battery.fillKind(reading)
    spacing: 4
    // Its width with and without the percentage, whichever shows, so a host
    // can plan its room without reading back the width it changes.
    readonly property real compactWidth: 30
    readonly property real fullWidth: compactWidth + spacing + percentText.implicitWidth
    Accessible.role: Accessible.Indicator
    Accessible.name: "Battery " + Battery.percent(reading.level) + " percent, " + Battery.stateLabel(reading)

    Item {
        width: 30
        height: 12
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            id: body
            width: 27
            height: 12
            radius: 3
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.5)
            border.width: 1
            Rectangle {
                objectName: "batteryFill"
                x: 2
                y: 2
                width: Math.round((body.width - 4) * Math.max(0, Math.min(1, root.reading.level)))
                height: body.height - 4
                radius: 1.5
                color: Battery.FILL_COLOURS[root.fillKind]
            }
            Text {
                objectName: "batteryStatusIcon"
                anchors.centerIn: parent
                visible: root.showStatusIcon && (root.fillKind === "charging" || root.fillKind === "low" || root.fillKind === "saver")
                text: root.fillKind === "charging" ? "⚡" : root.fillKind === "low" ? "!" : "S"
                textFormat: Text.PlainText
                color: "black"
                font.family: root.fontFamily
                renderType: root.textRenderType
                font.pixelSize: 9
                font.bold: true
            }
        }
        Rectangle {
            x: body.width + 1
            anchors.verticalCenter: body.verticalCenter
            width: 2
            height: 5
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }
    Text {
        id: percentText
        objectName: "batteryPercent"
        visible: root.showPercent
        anchors.verticalCenter: parent.verticalCenter
        text: Battery.percent(root.reading.level) + "%"
        textFormat: Text.PlainText
        color: "white"
        font.family: root.fontFamily
        renderType: root.textRenderType
        font.pixelSize: root.fontSize
    }
}
