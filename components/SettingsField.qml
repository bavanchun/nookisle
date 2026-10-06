import QtQuick
import QtQuick.Controls.Basic as Controls

// A settings window text field in the island tokens: a hairline border that
// turns into the accent focus ring while it holds the keyboard.
Controls.TextField {
    id: control
    required property var tokens
    color: tokens.text
    placeholderTextColor: tokens.secondary
    selectionColor: tokens.primaryFill
    selectedTextColor: tokens.primaryLabel
    font.family: tokens.fontFamily
    renderType: tokens.textRenderType
    font.pixelSize: tokens.bodySize
    implicitHeight: tokens.target
    background: Rectangle {
        objectName: "settingFieldFrame"
        radius: control.tokens.rowRadius
        color: control.tokens.surfaceSunken
        border.width: control.activeFocus ? control.tokens.focusWidth : 1
        border.color: control.activeFocus ? control.tokens.accent : control.tokens.stroke
    }
}
