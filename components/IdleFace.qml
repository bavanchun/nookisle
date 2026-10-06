import QtQuick
import QtQuick.Shapes
import QtQuick.Window

// The idle face: two eyes, a nose and a smile, drawn at 30x20 and scaled to
// fill its size (80x70 as the empty Home state). The eyes blink every 3 to
// 7 s in four steps: half shut, shut (held 100 ms), half shut, open. A 4 px
// eye has only a few visible heights, so four redraws per blink look the
// same as a tween and cost a tenth of one. The blink is one of the loops
// allowed in components/, and it runs only while the face is visible.
//
// Moods: "neutral" blinks; "sleepy" (23:00 to 06:00 by the face's own hour
// clock, only with `sleepsAtNight`, which the closed notch sets) keeps the
// eyes low and does not blink; "happy" squints and smiles
// wide and "worried" drops the smile to an "o", each while `moodOverride`
// asks for it (the island sets it for 3 s after a charger or low-battery
// banner). A mood change is one step: no tween.
Item {
    id: root
    property color color: "white"
    property bool reducedMotion: false
    // "happy" or "worried" from the host, or "" for the face's own mood.
    property string moodOverride: ""
    property bool sleepsAtNight: false
    property var now: new Date()
    readonly property bool night: sleepsAtNight && (now.getHours() >= 23 || now.getHours() < 6)
    readonly property string mood: moodOverride === "happy" || moodOverride === "worried" ? moodOverride
        : night ? "sleepy" : "neutral"
    // 0 open, 1 shut.
    property real blink: 0
    // The blink loop's gate: the face is shown, its window is, motion is
    // allowed and the mood blinks.
    readonly property bool blinking: visible && hostVisible && !reducedMotion && mood === "neutral"
    onBlinkingChanged: restartBlink()
    readonly property bool hostVisible: !root.Window.window || root.Window.window.visible
    // The blink's steps after the wait, and the ms each step is held.
    readonly property var blinkSteps: [2 / 3, 1, 2 / 3, 0]
    readonly property var blinkHolds: [70, 100, 70]
    property int blinkStep: -1
    implicitWidth: 30
    implicitHeight: 20

    function nextWait() {
        return 3000 + Math.floor(Math.random() * 4000);
    }
    // The hour clock: a single-shot timer re-armed to the next hour, only
    // while the face is shown.
    function armHour() {
        hour.stop();
        if (!root.sleepsAtNight || !root.visible || !root.hostVisible)
            return;
        var current = new Date();
        hour.interval = Math.max(1000, (60 - current.getMinutes()) * 60000 - current.getSeconds() * 1000 + 50);
        hour.start();
    }
    function resumeClock() {
        if (sleepsAtNight && visible && hostVisible)
            now = new Date();
        armHour();
    }
    onVisibleChanged: resumeClock()
    onHostVisibleChanged: resumeClock()
    onSleepsAtNightChanged: resumeClock()
    Component.onCompleted: {
        armHour();
        restartBlink();
    }
    function restartBlink() {
        blinkLoop.stop();
        blinkStep = -1;
        blink = 0;
        if (blinking) {
            blinkLoop.interval = nextWait();
            blinkLoop.start();
        }
    }
    Timer {
        id: hour
        repeat: false
        onTriggered: {
            root.now = new Date();
            root.armHour();
        }
    }

    Item {
        id: face
        width: 30
        height: 20
        anchors.centerIn: parent
        scale: Math.min(root.width / width, root.height / height)
        Row {
            x: (face.width - width) / 2
            y: 2
            spacing: 4
            Repeater {
                model: 2
                Item {
                    required property int index
                    objectName: "idleEye" + index
                    width: 4
                    height: 4
                    Rectangle {
                        objectName: "idleEyeLid"
                        visible: root.mood !== "happy"
                        width: 4
                        height: root.mood === "sleepy" ? 1 : Math.max(1, Math.round(4 - 3 * root.blink))
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Math.min(width, height) / 2
                        color: root.color
                    }
                    // Happy: the eye squints into an upturned arc.
                    Shape {
                        objectName: "idleEyeSquint"
                        visible: root.mood === "happy"
                        anchors.fill: parent
                        ShapePath {
                            strokeColor: root.color
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            startX: 0.5
                            startY: 3.5
                            PathQuad { x: 3.5; y: 3.5; controlX: 2; controlY: 0 }
                        }
                    }
                }
            }
        }
        Rectangle {
            x: (face.width - width) / 2
            y: 8
            width: 3
            height: 4
            radius: 1
            color: root.color
        }
        Shape {
            objectName: "idleSmile"
            visible: root.mood !== "worried"
            x: (face.width - 14) / 2
            y: 12
            width: 14
            height: 8
            ShapePath {
                strokeColor: root.color
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 1
                startY: 2
                PathQuad { x: 13; y: 2; controlX: 7; controlY: root.mood === "happy" ? 12 : 9 }
            }
        }
        // Worried: a small "o".
        Rectangle {
            objectName: "idleMouthO"
            visible: root.mood === "worried"
            x: (face.width - width) / 2
            y: 13
            width: 5
            height: 5
            radius: 2.5
            color: "transparent"
            border.color: root.color
            border.width: 1.5
        }
    }

    // A single-shot timer re-armed for each step and each wait.
    Timer {
        id: blinkLoop
        objectName: "idleBlink"
        repeat: false
        onTriggered: {
            root.blinkStep = root.blinkStep + 1;
            root.blink = root.blinkSteps[root.blinkStep];
            if (root.blinkStep < root.blinkHolds.length) {
                interval = root.blinkHolds[root.blinkStep];
            } else {
                root.blinkStep = -1;
                interval = root.nextWait();
            }
            if (root.blinking)
                start();
        }
    }
}
