import QtQuick
import QtQuick.Controls.Basic as Controls

// A settings window check box in the island tokens: the box fills with the
// primary colour and shows a tick while checked, and wears a focus ring when
// reached by keyboard.
Controls.CheckBox {
    id: control
    required property var tokens
    focusPolicy: Qt.StrongFocus
    spacing: tokens.gap
    indicator: Rectangle {
        objectName: "settingCheckBox"
        implicitWidth: 18
        implicitHeight: 18
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: 4
        color: control.checked ? control.tokens.primaryFill : "transparent"
        border.width: control.visualFocus ? control.tokens.focusWidth : 1
        border.color: control.visualFocus ? control.tokens.accent : control.checked ? control.tokens.primaryFill : control.tokens.stroke
        Text {
            anchors.centerIn: parent
            visible: control.checked
            text: "✓"
            color: control.tokens.primaryLabel
            font.pixelSize: 13
            font.weight: Font.Bold
        }
    }
    contentItem: Text {
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: control.text
        textFormat: Text.PlainText
        color: control.tokens.text
        font.family: control.tokens.fontFamily
        font.pixelSize: control.tokens.bodySize
    }
}
