pragma ComponentBehavior: Bound

import QtQuick
import "../qml/HudValues.js" as HudValues

// A direct level request, with a local drag preview until the source reports
// its new value. The parent owns the actual sink/backlight write.
Item {
    id: root
    required property var tokens
    property bool active: false
    property string kind: "volume"
    property real level: 0
    property bool accent: false
    property bool gradientEnabled: false
    property bool glowEnabled: false
    property bool dragging: false
    property real preview: 0
    readonly property real displayLevel: dragging ? preview : HudValues.clamp(level)
    readonly property bool adjustable: HudValues.adjustable(kind)
    signal setLevel(string kind, real value)
    signal interacted()

    implicitWidth: 100
    implicitHeight: 24

    function requestAt(x) {
        var next = HudValues.fromPosition(x, width)
        if (next === null || !root.active || !root.adjustable) return
        next = HudValues.floorFor(root.kind, next)
        root.preview = next
        root.interacted()
        root.setLevel(root.kind, next)
    }
    onActiveChanged: if (!active) dragging = false
    onKindChanged: dragging = false
    // A window hidden mid-drag (the lock, autoShow off, a screen change)
    // never delivers the release, and Qt keeps the press: the drag, and so
    // the view's hold on the readout, ends with the window.
    Connections {
        target: root.Window.window
        function onVisibleChanged() {
            if (root.Window.window && !root.Window.window.visible)
                root.dragging = false
        }
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.dragging ? 9 : 6
        radius: height / 2
        color: root.tokens.notchTrack
        Rectangle {
            objectName: "hudGlow"
            x: -3
            y: -3
            width: Math.min(track.width + 6, fill.width + 6)
            height: track.height + 6
            radius: height / 2
            color: root.accent ? root.tokens.notchAccent : root.tokens.notchInk
            opacity: 0.24
            visible: root.glowEnabled && root.displayLevel > 0
        }
        Rectangle {
            id: fill
            objectName: "hudFill"
            width: parent.width * root.displayLevel
            height: parent.height
            radius: parent.radius
            color: root.accent ? root.tokens.notchAccent : root.tokens.notchInk
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { objectName: "hudGradientStart"; position: 0; color: root.accent ? root.tokens.notchAccent : root.tokens.notchInk }
                GradientStop { objectName: "hudGradientEnd"; position: 1; color: root.gradientEnabled
                    ? Qt.darker(root.accent ? root.tokens.notchAccent : root.tokens.notchInk, 1.55)
                    : root.accent ? root.tokens.notchAccent : root.tokens.notchInk }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.active && root.adjustable
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: mouse => {
            root.dragging = true
            root.requestAt(mouse.x)
        }
        onPositionChanged: mouse => { if (pressed && root.dragging) root.requestAt(mouse.x) }
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
    }
}
