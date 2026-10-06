pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Motion.js" as Motion

// The Home mirror. The tile itself (a #141414 rounded square with a 4 %
// white hairline, a camera glyph and "Mirror") is always drawn while the
// panel shows, as boring.notch's is, so Home never has a hole in it while
// the island opens or the camera starts; only the feed reveals over it. A
// tap on the tile stops the camera and shows the tile, and another tap
// starts it again, for the session.
Item {
    id: root
    enabled: false
    property bool islandOpen: false
    property bool onHome: false
    property bool tileVisible: false
    property string shape: "rectangle"
    property bool reducedMotion: false
    property color matteColor: "#000000"
    // Grayscale text on the island; the welcome window keeps its default.
    property int textRenderType: Text.NativeRendering
    // Stopped from the tile itself; the header toggle hides the whole mirror.
    property bool stopped: false
    property Component sourceComponent: liveSource
    // The real camera source, for a host that swaps sourceComponent.
    readonly property Component liveComponent: liveSource
    readonly property bool captureAllowed: enabled && islandOpen && onHome && tileVisible && !stopped
    readonly property var sourceItem: sourceLoader.item
    readonly property bool unavailable: captureAllowed && (sourceLoader.status === Loader.Error
        || (sourceItem && sourceItem.unavailable === true))
    readonly property real tileSize: tile.width
    readonly property real clipRadius: shape === "circle" ? tile.width / 2 : 13
    readonly property real revealProgress: Motion.normalised(revealTime, 0.32, 0.76, 0.32)
    property real revealTime: 0
    // The capture source loads once the tile has finished revealing: opening
    // the device stalls the GUI thread for about 140 ms, which would
    // otherwise freeze the reveal (and the island's open spring before it).
    readonly property bool revealed: revealTime >= 0.32
    implicitWidth: 120
    implicitHeight: 120

    onCaptureAllowedChanged: {
        revealAnimation.stop()
        revealTime = 0
        if (captureAllowed) revealAnimation.start()
    }
    Component.onCompleted: if (captureAllowed) revealAnimation.start()

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "revealTime"
        from: 0
        to: 0.32
        duration: root.reducedMotion ? 0 : 320
    }

    Component {
        id: liveSource
        CameraSource {
            enabled: root.enabled
            islandOpen: root.islandOpen
            onHome: root.onHome
            tileVisible: root.tileVisible
        }
    }

    Item {
        id: tile
        width: Math.min(root.width, root.height)
        height: width
        anchors.centerIn: parent
        Accessible.role: Accessible.Button
        Accessible.name: root.stopped ? "Start the mirror" : "Stop the mirror"
        Accessible.onPressAction: root.stopped = !root.stopped

        Rectangle {
            objectName: "cameraTileBase"
            anchors.fill: parent
            color: "#141414"
            radius: root.clipRadius
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.04)
        }
        Column {
            objectName: "cameraPlaceholder"
            anchors.centerIn: parent
            spacing: 6
            visible: !root.unavailable
            IslandIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(tile.width / 3.5)
                height: width
                name: "camera"
                ink: "#8e8e93"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mirror"
                renderType: root.textRenderType
                color: "#8e8e93"
                font.pixelSize: 10
            }
        }

        // The feed grows and fades in over the tile.
        Item {
            id: feed
            objectName: "cameraFeed"
            anchors.fill: parent
            scale: 0.8 + 0.2 * root.revealProgress
            opacity: Math.max(0, Math.min(1, root.revealProgress))
            Loader {
                id: sourceLoader
                anchors.fill: parent
                active: root.captureAllowed && root.revealed
                sourceComponent: root.sourceComponent
            }
        }

        // A matte covers pixels outside the circle or rounded rectangle. It
        // works with the software renderer, without a GPU mask effect.
        Canvas {
            id: clipMatte
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: root
                function onShapeChanged() { clipMatte.requestPaint() }
                function onMatteColorChanged() { clipMatte.requestPaint() }
            }
            onPaint: {
                var context = getContext("2d")
                context.reset()
                context.fillStyle = root.matteColor
                context.fillRect(0, 0, width, height)
                context.globalCompositeOperation = "destination-out"
                context.beginPath()
                if (root.shape === "circle")
                    context.arc(width / 2, height / 2, width / 2, 0, Math.PI * 2)
                else
                    context.roundedRect(0, 0, width, height, 13, 13)
                context.fill()
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 6
            visible: root.unavailable

            Canvas {
                id: cautionIcon
                objectName: "cameraCautionIcon"
                width: 24
                height: 24
                anchors.horizontalCenter: parent.horizontalCenter
                onPaint: {
                    var context = getContext("2d")
                    context.reset()
                    context.strokeStyle = "#f6f7fb"
                    context.fillStyle = "#f6f7fb"
                    context.lineWidth = 1.8
                    context.lineJoin = "round"
                    context.beginPath()
                    context.moveTo(12, 3)
                    context.lineTo(22, 20)
                    context.lineTo(2, 20)
                    context.closePath()
                    context.stroke()
                    context.fillRect(11.1, 9, 1.8, 5.5)
                    context.beginPath()
                    context.arc(12, 17.3, 1, 0, Math.PI * 2)
                    context.fill()
                }
            }
            Text {
                objectName: "cameraUnavailableText"
                text: "Camera unavailable"
                renderType: root.textRenderType
                color: "#f6f7fb"
                font.pixelSize: 11
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
        TapHandler {
            objectName: "cameraTileTap"
            onTapped: root.stopped = !root.stopped
        }
    }
}
