pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Privacy.js" as Privacy

// The open header's centre, when no camera cutout sits there: what is going
// on right now, as small chips. The privacy chip names the apps using the
// microphone, a camera or the screen; the timer chip counts the soonest
// timer down and opens the Timers view; the recording chip counts a screen
// recording's minutes and stops it.
Item {
    id: root
    required property var tokens
    // PrivacySource's state, or null.
    property var privacy: null
    readonly property bool privacyShown: !!privacy && privacy.any === true
    readonly property string privacyText: privacyShown ? Privacy.summary(privacy) : ""
    // ActivityModel, for the timer's label and minutes.
    property var activities: null
    readonly property bool timerShown: !!activities && !!activities.timer
    signal timersRequested
    readonly property bool recordingShown: !!activities && !!activities.recording
    signal stopRecordingRequested
    implicitHeight: tokens.target
    Row {
        id: chips
        objectName: "activityChips"
        anchors.centerIn: parent
        spacing: root.tokens.small
        Rectangle {
            id: recordingChip
            objectName: "recordingChip"
            visible: root.recordingShown
            width: recordingRow.implicitWidth + 2 * root.tokens.gap
            height: root.tokens.captionSize + 2 * root.tokens.small + 2
            radius: height / 2
            color: root.tokens.raisedSurface
            Row {
                id: recordingRow
                x: root.tokens.gap
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.tokens.small
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.tokens.recordingDot
                    height: width
                    radius: width / 2
                    color: root.tokens.recordingInk
                }
                Text {
                    objectName: "recordingChipText"
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.recordingShown ? "REC " + root.activities.recordingElapsed : ""
                    textFormat: Text.PlainText
                    color: root.tokens.recordingInk
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    Accessible.ignored: true
                }
                Text {
                    id: stopLabel
                    objectName: "recordingStop"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Stop"
                    textFormat: Text.PlainText
                    color: stopTap.pressed ? root.tokens.secondary : root.tokens.text
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Button
                    Accessible.name: "Stop the screen recording"
                    Accessible.onPressAction: root.stopRecordingRequested()
                    TapHandler {
                        id: stopTap
                        margin: root.tokens.small
                        onTapped: root.stopRecordingRequested()
                    }
                }
            }
        }
        Rectangle {
            id: timerChip
            objectName: "timerChip"
            visible: root.timerShown
            width: timerRow.implicitWidth + 2 * root.tokens.gap
            height: root.tokens.captionSize + 2 * root.tokens.small + 2
            radius: height / 2
            color: timerTap.pressed ? root.tokens.hover : root.tokens.raisedSurface
            Accessible.role: Accessible.Button
            Accessible.name: root.timerShown ? root.activities.timerLabel + ", " + root.activities.timerRemaining + " left" : ""
            Accessible.onPressAction: root.timersRequested()
            Row {
                id: timerRow
                x: root.tokens.gap
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.tokens.small
                IslandIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.tokens.captionSize
                    height: width
                    name: "ring"
                    level: root.timerShown ? root.activities.timerFraction : 0
                    ink: root.tokens.accent
                }
                Text {
                    objectName: "timerChipText"
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.timerShown ? root.activities.timerRemaining : ""
                    textFormat: Text.PlainText
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    font.features: { "tnum": 1 }
                    Accessible.ignored: true
                }
            }
            TapHandler {
                id: timerTap
                onTapped: root.timersRequested()
            }
        }
        Rectangle {
            id: privacyChip
            objectName: "privacyChip"
            visible: root.privacyShown
            readonly property real room: root.width - (timerChip.visible ? timerChip.width + root.tokens.small : 0)
                - (recordingChip.visible ? recordingChip.width + root.tokens.small : 0)
            width: Math.min(privacyRow.implicitWidth + 2 * root.tokens.gap, room)
            height: root.tokens.captionSize + 2 * root.tokens.small + 2
            radius: height / 2
            color: root.tokens.raisedSurface
            Accessible.role: Accessible.StaticText
            Accessible.name: root.privacyText
            Row {
                id: privacyRow
                x: root.tokens.gap
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.tokens.small
                Repeater {
                    model: [
                        { shown: root.privacyShown && root.privacy.mic.length > 0, ink: root.tokens.privacyMic },
                        { shown: root.privacyShown && root.privacy.camera.length > 0, ink: root.tokens.privacyCamera },
                        { shown: root.privacyShown && root.privacy.screen.length > 0, ink: root.tokens.privacyScreen }
                    ]
                    Rectangle {
                        required property var modelData
                        visible: modelData.shown
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        width: root.tokens.privacyDot + 2
                        height: width
                        radius: width / 2
                        color: modelData.ink
                    }
                }
                Text {
                    objectName: "privacyChipText"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, privacyChip.room - 2 * root.tokens.gap - 3 * (root.tokens.privacyDot + 2 + root.tokens.small)))
                    elide: Text.ElideRight
                    text: root.privacyText
                    textFormat: Text.PlainText
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    Accessible.ignored: true
                }
            }
        }
    }
}
