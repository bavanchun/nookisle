pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls

Controls.ToolTip {
    id: root
    required property var tokens
    padding: tokens.gap
    width: Math.min(label.implicitWidth + padding * 2,
        parent && parent.Window.window ? Math.max(tokens.target, parent.Window.window.width - tokens.inset * 2) : tokens.expandedWidth - tokens.inset * 2)
    contentItem: Text {
        id: label
        text: root.text
        color: root.tokens.text
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }
    background: Rectangle {
        color: root.tokens.surface
        radius: Math.min(root.tokens.expandedRadius, root.tokens.gap)
        border.color: root.tokens.stroke
    }
}
