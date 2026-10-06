pragma ComponentBehavior: Bound

import QtQuick
import "../qml/HudGeometry.js" as HudGeometry
import "../qml/HudValues.js" as HudValues

// A separate pill under the closed notch. The shell places it using
// suggestedPosition and unions activeHitRect with its existing hitShape.
Item {
    id: root
    required property var tokens
    required property var model
    property bool showPercent: false
    property bool accent: false
    property bool gradientEnabled: false
    property bool glowEnabled: false
    property real notchWidth: tokens.liveWidth
    property real notchHeight: tokens.pillMinHeight
    property real notchGap: 4
    readonly property var suggestedPosition: HudGeometry.belowPosition(notchWidth, width, notchHeight, notchGap)
    readonly property bool active: !!model && model.active === true
    readonly property bool hasBar: !!model && model.hasBar === true
    readonly property var hudRect: HudGeometry.rect(x, y, width, height)
    readonly property var activeHitRect: HudGeometry.activeRect(active, hudRect)
    signal setLevel(string kind, real value)
    // A view that goes away mid-drag (its screen removed) ends its own hold.
    Component.onDestruction: if (root.model) root.model.hold(root, false)

    implicitWidth: 230
    implicitHeight: 36
    visible: active

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.tokens.notchColor
        border.width: 1
        border.color: root.tokens.notchStroke
    }
    IslandIcon {
        id: icon
        objectName: "hudIcon"
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        name: root.model ? root.model.icon : "volume"
        ink: root.tokens.notchInk
    }
    HudBar {
        objectName: "hudBar"
        x: icon.x + icon.width + 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.width - x - (percentage.visible ? 48 : 12))
        tokens: root.tokens
        active: root.active
        kind: root.model ? root.model.kind : "volume"
        level: root.model ? root.model.level : 0
        accent: root.accent
        gradientEnabled: root.gradientEnabled
        glowEnabled: root.glowEnabled
        visible: root.hasBar
        onSetLevel: (kind, value) => root.setLevel(kind, value)
        onInteracted: if (root.model) root.model.extend()
        onDraggingChanged: if (root.model) root.model.hold(root, dragging)
    }
    Text {
        id: percentage
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        horizontalAlignment: Text.AlignRight
        visible: root.hasBar && root.showPercent
        text: root.model ? HudValues.percent(root.model.level) + "%" : ""
        textFormat: Text.PlainText
        color: root.tokens.notchMutedInk
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
    }
    Text {
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.hasBar
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.model ? root.model.label : ""
        textFormat: Text.PlainText
        color: root.tokens.notchInk
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
    }
}
