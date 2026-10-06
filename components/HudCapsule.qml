pragma ComponentBehavior: Bound

import QtQuick
import "../qml/HudGeometry.js" as HudGeometry
import "../qml/HudValues.js" as HudValues

// Open-notch header readout. With a percentage, the bar is 65 px; without
// one it is 108 px, keeping the capsule's overall width stable.
Item {
    id: root
    required property var tokens
    required property var model
    property bool showPercent: true
    property bool accent: false
    property bool gradientEnabled: false
    property bool glowEnabled: false
    readonly property bool active: !!model && model.active === true
    readonly property bool hasBar: !!model && model.hasBar === true
    // The room a host can give; the bar gives up what the capsule lacks.
    property real maximumWidth: Infinity
    readonly property real barWidth: HudGeometry.capsuleBarWidth(showPercent) - Math.max(0, implicitWidth - width)
    readonly property var hudRect: HudGeometry.rect(x, y, width, height)
    readonly property var activeHitRect: HudGeometry.activeRect(active, hudRect)
    signal setLevel(string kind, real value)
    // A view that goes away mid-drag (its screen removed) ends its own hold.
    Component.onDestruction: if (root.model) root.model.hold(root, false)

    implicitWidth: 156
    width: Math.min(implicitWidth, maximumWidth)
    implicitHeight: 30
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
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        name: root.model ? root.model.icon : "volume"
        ink: root.tokens.notchInk
    }
    HudBar {
        id: bar
        objectName: "hudBar"
        x: icon.x + icon.width + 8
        anchors.verticalCenter: parent.verticalCenter
        width: root.barWidth
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
        anchors.left: bar.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 35
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
        objectName: "hudText"
        x: bar.x
        width: 108 - Math.max(0, root.implicitWidth - root.width)
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
