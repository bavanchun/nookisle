import QtQuick
import QtQuick.Controls.Basic as Controls

// A settings window button in the island tokens, never the platform palette:
// a checkable one (a choice) fills with the primary colour while checked,
// and every one draws a focus ring when reached by keyboard.
Controls.Button {
    id: control
    required property var tokens
    // The window's main action (the welcome's Next and Finish): filled with
    // the primary colour like a checked choice.
    property bool primary: false
    readonly property bool filled: checked || primary
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    leftPadding: tokens.medium
    rightPadding: tokens.medium
    implicitHeight: tokens.target
    Accessible.checkable: checkable
    Accessible.checked: checked
    background: Rectangle {
        objectName: "settingButtonFill"
        radius: control.tokens.rowRadius
        color: control.filled ? control.tokens.primaryFill
            : control.hovered || control.down ? control.tokens.hover : control.tokens.surfaceRaised
        border.width: control.visualFocus ? control.tokens.focusWidth : control.filled ? 0 : 1
        border.color: control.visualFocus ? (control.filled ? control.tokens.primaryLabel : control.tokens.accent)
            : control.tokens.stroke
        opacity: control.enabled ? 1 : 0.5
    }
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: control.filled ? control.tokens.primaryLabel : control.tokens.text
        font.family: control.tokens.fontFamily
        renderType: control.tokens.textRenderType
        font.pixelSize: control.tokens.bodySize
        font.weight: control.filled ? Font.DemiBold : Font.Normal
    }
}
