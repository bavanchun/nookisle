pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import "../qml/CaptureFormat.js" as CaptureFormat

// Camera lifetime follows the Loader, not just Camera.active: Qt keeps the
// device open while an inactive Camera object still exists.
Item {
    id: root
    enabled: false
    property bool islandOpen: false
    property bool onHome: false
    property bool tileVisible: false
    readonly property bool captureAllowed: enabled && islandOpen && onHome && tileVisible
    readonly property bool hasCamera: mediaDevices.videoInputs.length > 0
    readonly property var captureItem: cameraLoader.item
    readonly property bool unavailable: !hasCamera || cameraLoader.status === Loader.Error
        || (captureItem && captureItem.cameraError)

    MediaDevices { id: mediaDevices }

    Loader {
        id: cameraLoader
        anchors.fill: parent
        active: root.captureAllowed && root.hasCamera
        sourceComponent: Component {
            Item {
                id: capture
                readonly property bool cameraError: camera.error !== Camera.NoError

                CaptureSession {
                    camera: Camera {
                        id: camera
                        cameraDevice: mediaDevices.defaultVideoInput
                        // The smallest format at least twice the tile, set
                        // before the camera starts so the device opens once,
                        // in that format; a later tile resize switches it.
                        readonly property var chosenFormat: CaptureFormat.pick(cameraDevice.videoFormats,
                            root.width, root.height)
                        property bool formatApplied: false
                        onChosenFormatChanged: if (formatApplied && chosenFormat) cameraFormat = chosenFormat
                        Component.onCompleted: {
                            if (chosenFormat)
                                cameraFormat = chosenFormat;
                            formatApplied = true;
                        }
                        active: root.captureAllowed && formatApplied
                    }
                    videoOutput: preview
                }

                VideoOutput {
                    id: preview
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    transform: Scale {
                        origin.x: preview.width / 2
                        origin.y: preview.height / 2
                        xScale: -1
                    }
                }
            }
        }
    }
}
