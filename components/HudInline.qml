pragma ComponentBehavior: Bound

import QtQuick
import "../qml/HudGeometry.js" as HudGeometry
import "../qml/HudValues.js" as HudValues

// Content for the closed notch's expanded HUD width. The centre remains clear
// for the notch body; the shell supplies the black shape behind both wings.
Item {
    id: root
    required property var tokens
    required property var model
    property bool showPercent: false
    property bool accent: false
    property bool gradientEnabled: false
    property bool glowEnabled: false
    property real centerGap: 76
    property real sideInset: 12
    readonly property bool active: !!model && model.active === true
    readonly property bool hasBar: !!model && model.hasBar === true
    readonly property real wingWidth: HudGeometry.inlineWingWidth(width, centerGap, sideInset)
    readonly property var hudRect: HudGeometry.rect(x, y, width, height)
    readonly property var activeHitRect: HudGeometry.activeRect(active, hudRect)
    signal setLevel(string kind, real value)
    // A view that goes away mid-drag (its screen removed) ends its own hold.
    Component.onDestruction: if (root.model) root.model.hold(root, false)

    implicitWidth: tokens.hudInlineWidth
    implicitHeight: Math.max(28, tokens.pillMinHeight)
    visible: active

    Item {
        x: root.sideInset
        width: root.wingWidth
        height: parent.height
        IslandIcon {
            id: icon
            objectName: "hudIcon"
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            name: root.model ? root.model.icon : "volume"
            ink: root.tokens.notchInk
        }
        Text {
            anchors.left: icon.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.model ? root.model.label : ""
            textFormat: Text.PlainText
            color: root.tokens.notchInk
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }
    Item {
        x: root.width - root.sideInset - root.wingWidth
        width: root.wingWidth
        height: parent.height
        HudBar {
            objectName: "hudBar"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - (percentage.visible ? 42 : 0))
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
            anchors.fill: parent
            visible: !root.hasBar
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.model && root.model.muted ? "Muted" : "On"
            textFormat: Text.PlainText
            color: root.tokens.notchMutedInk
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
    }
}
