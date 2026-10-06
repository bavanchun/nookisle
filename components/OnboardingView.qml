pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as Controls
import "../qml/Onboarding.js" as Onboarding
import "../qml/Settings.js" as Settings
import "../qml/Strings.js" as Strings

// The first-run steps, driven by the pure machine in qml/Onboarding.js. Each
// step between Welcome and Done offers real choices as the settings window's
// own rows, written through the coordinator's configure(); nothing changes
// until the person picks, so a skipped step keeps its defaults. Moving
// between steps fades and slides the content for 600 ms. Return moves on,
// Escape closes. OnboardingWindow hosts it; the tests load it directly.
Rectangle {
    id: root
    required property var tokens
    property var coordinator: null
    property var flow: Onboarding.start()
    readonly property var step: Onboarding.step(flow)
    signal finished(var skipped)
    color: tokens.surface

    // The camera test opens the camera only after an explicit press on this
    // step, and only while the window shows and the shell allows windows (a
    // lock unloads it). Any step change withdraws the press, so leaving,
    // skipping or coming back never opens the camera by itself.
    // hostVisible is the window's visible property, the strongest signal
    // QML has: Qt exposes no exposure state to QML (QWindow::isExposed is
    // C++ only, and Quickshell's backingWindowVisible mirrors the same
    // mapped state), and on Wayland a window on a background workspace stays
    // mapped and exposed, so no property would tell it apart. The test is
    // opt-in per press and ends with the step, the window or a lock.
    property bool hostVisible: true
    readonly property bool cameraHostAllowed: hostVisible
        && (!coordinator || coordinator.windowsAllowed !== false)
    property bool cameraTestRequested: false
    onStepChanged: cameraTestRequested = false
    onCameraHostAllowedChanged: if (!cameraHostAllowed) cameraTestRequested = false
    // Tests swap in a fake capture source; null uses the real camera.
    property Component cameraSourceComponent: null

    function go(next) {
        if (next === flow)
            return;
        flow = next;
        if (flow.finished) {
            finished(flow.skipped);
            return;
        }
        slide.restart();
        nextButton.forceActiveFocus(Qt.OtherFocusReason);
    }
    // The schema keys a step offers that this build has.
    function settingsOf(id) {
        return (Onboarding.STEP_SETTINGS[id] || []).filter(key => {
            var spec = Settings.entry(key);
            return !!spec && !spec.internal;
        });
    }
    function valueOf(key) {
        return Settings.storedValue(coordinator, key);
    }
    Component.onCompleted: nextButton.forceActiveFocus(Qt.OtherFocusReason)
    // Return or Enter presses the focused button (Back, Skip, a step's
    // own), and anywhere else moves on; Escape closes, counting what is
    // left as skipped.
    function activate() {
        var item = Window.activeFocusItem;
        // A button: anything with click() and a clicked signal.
        if (item && item !== nextButton && item.enabled && typeof item.click === "function"
                && typeof item.clicked === "function") {
            item.click();
            return;
        }
        go(Onboarding.next(flow));
    }
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onEscapePressed: go(Onboarding.close(flow))

    ParallelAnimation {
        id: slide
        NumberAnimation {
            target: stage; property: "offset"; from: root.flow.direction * 40; to: 0
            duration: root.tokens.reducedMotion ? 0 : 600; easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: stage; property: "opacity"; from: 0; to: 1
            duration: root.tokens.reducedMotion ? 0 : 600; easing.type: Easing.InOutCubic
        }
    }

    Row {
        objectName: "onboardingProgress"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.tokens.inset
        spacing: root.tokens.small
        Accessible.role: Accessible.ProgressBar
        Accessible.name: "Step " + (root.flow.index + 1) + " of " + Onboarding.STEPS.length
        Repeater {
            model: Onboarding.STEPS.length
            Rectangle {
                required property int index
                width: index === root.flow.index ? 18 : 6
                height: 6
                radius: 3
                color: index === root.flow.index ? root.tokens.accent : root.tokens.track
            }
        }
    }
    Item {
        id: stage
        objectName: "onboardingStage"
        property real offset: 0
        x: root.tokens.inset + offset
        y: root.tokens.inset * 2 + 6
        width: parent.width - root.tokens.inset * 2
        height: parent.height - y - buttons.height - root.tokens.inset * 2
        Text {
            id: title
            objectName: "onboardingTitle"
            width: parent.width
            text: root.step.title
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            color: root.tokens.text
            font.family: root.tokens.fontFamily
            font.pixelSize: root.tokens.titleSize + 4
            font.weight: Font.DemiBold
            Accessible.role: Accessible.Heading
        }
        Flickable {
            objectName: "onboardingStepPage"
            y: title.height + root.tokens.medium
            width: parent.width
            height: parent.height - y
            contentHeight: stepLoader.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: stepLoader
                objectName: "onboardingStep-" + root.step.id
                width: parent.width
                sourceComponent: {
                    switch (root.step.id) {
                    case "welcome": return welcomeStep;
                    case "look": return lookStep;
                    case "media": return mediaStep;
                    case "calendar": return calendarStep;
                    case "camera": return cameraStep;
                    case "shortcuts": return shortcutsStep;
                    }
                    return doneStep;
                }
            }
        }
    }
    Row {
        id: buttons
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.tokens.inset
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.tokens.small
        SettingsButton {
            objectName: "onboardingBack"
            tokens: root.tokens
            text: "Back"
            enabled: root.flow.index > 0
            onClicked: root.go(Onboarding.back(root.flow))
        }
        SettingsButton {
            objectName: "onboardingSkip"
            tokens: root.tokens
            visible: !Onboarding.isLast(root.flow)
            text: "Skip"
            Accessible.description: "Keep this step's defaults"
            onClicked: root.go(Onboarding.skip(root.flow))
        }
        SettingsButton {
            objectName: "onboardingSkipAll"
            tokens: root.tokens
            visible: !Onboarding.isLast(root.flow)
            text: "Skip all"
            onClicked: root.go(Onboarding.skipAll(root.flow))
        }
        SettingsButton {
            id: nextButton
            objectName: "onboardingNext"
            tokens: root.tokens
            primary: true
            text: Onboarding.isLast(root.flow) ? "Finish" : "Next"
            onClicked: root.go(Onboarding.next(root.flow))
        }
    }

    component Body: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: root.tokens.secondary
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.bodySize
    }
    // A step's settings, as the settings window draws them.
    component StepSettings: Column {
        id: rows
        required property string stepId
        width: parent ? parent.width : 0
        spacing: root.tokens.medium
        Repeater {
            model: root.settingsOf(rows.stepId)
            SettingsControls {
                required property string modelData
                width: rows.width
                tokens: root.tokens
                coordinator: root.coordinator
                spec: Settings.entry(modelData)
                value: root.valueOf(modelData)
                requirement: Settings.requirementText(modelData, root.valueOf)
            }
        }
    }
    Component {
        id: welcomeStep
        Column {
            spacing: root.tokens.medium
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 90
                radius: 24
                color: root.tokens.notchColor
                IdleFace {
                    objectName: "onboardingFace"
                    anchors.centerIn: parent
                    width: 80
                    height: 70
                    reducedMotion: root.tokens.reducedMotion
                }
            }
            Body { text: "Nookisle turns the middle of your bar into a live notch for what is playing. The next steps let you choose what it shows; every one can be skipped, and nothing changes until you pick." }
        }
    }
    // The idle notch, previewed as it will look, and whether covers from the
    // web may be fetched.
    Component {
        id: lookStep
        Column {
            id: look
            spacing: root.tokens.medium
            readonly property string idleStyle: String(root.valueOf("idleStyle") || "glance")
            DesignTokens {
                id: previewInk
                theme: ({ surface: root.tokens.notchColor, text: root.tokens.notchInk,
                    accent: root.tokens.accent, fontFamily: root.tokens.fontFamily })
                light: false
                highContrast: root.tokens.highContrast
                reducedMotion: root.tokens.reducedMotion
                tintEnabled: root.tokens.tintEnabled
                artColor: root.tokens.artColor
                neutralChrome: true
            }
            Rectangle {
                id: preview
                objectName: "onboardingIdlePreview"
                anchors.horizontalCenter: parent.horizontalCenter
                width: look.idleStyle === "glance" ? root.tokens.liveWidth
                    : look.idleStyle === "face" ? root.tokens.faceWidth
                    : look.idleStyle === "horizon" ? root.tokens.horizonWidth : root.tokens.idleWidth
                height: 26
                radius: 14
                color: root.tokens.notchColor
                Accessible.role: Accessible.Graphic
                Accessible.name: "Idle notch preview: " + look.idleStyle
                IdleGlance {
                    objectName: "onboardingIdleGlance"
                    anchors.fill: parent
                    visible: look.idleStyle === "glance"
                    tokens: previewInk
                    clockSetting: String(root.valueOf("idleClock") || "auto")
                    hairline: root.valueOf("idleHairline") !== false
                }
                IdleFace {
                    objectName: "onboardingIdleFace"
                    visible: look.idleStyle === "face"
                    anchors.centerIn: parent
                    width: 30
                    height: 22
                    reducedMotion: root.tokens.reducedMotion
                }
                Rectangle {
                    objectName: "onboardingIdleHorizon"
                    visible: look.idleStyle === "horizon"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - height - 2
                    width: root.tokens.horizonLine
                    height: root.tokens.hairlineHeight
                    radius: height / 2
                    color: previewInk.tint
                }
            }
            Body { text: "This is the notch while nothing plays. A player's own cover always shows; covers from the web need Online artwork." }
            StepSettings { stepId: "look" }
        }
    }
    Component {
        id: mediaStep
        Column {
            spacing: root.tokens.gap
            Body { text: "Choose the player to follow whenever it is open. It is remembered after a restart; Auto follows whatever plays." }
            SourcePicker {
                width: parent.width
                height: 200
                overlay: true
                remember: true
                tokens: root.tokens
                coordinator: root.coordinator
            }
            StepSettings { stepId: "media" }
        }
    }
    Component {
        id: calendarStep
        Column {
            spacing: root.tokens.medium
            Body { text: "Show today's events and reminders beside the player, from local files, iCal links or CalDAV." }
            StepSettings { stepId: "calendar" }
            SettingsButton {
                objectName: "onboardingCalendarSettings"
                anchors.horizontalCenter: parent.horizontalCenter
                tokens: root.tokens
                text: "Add a calendar"
                enabled: !!root.coordinator
                onClicked: root.coordinator.openSettings("calendar")
            }
        }
    }
    Component {
        id: cameraStep
        Column {
            spacing: root.tokens.medium
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160
                height: 160
                CameraPanel {
                    id: cameraTest
                    objectName: "onboardingCameraPanel"
                    anchors.fill: parent
                    enabled: root.cameraTestRequested
                    islandOpen: root.cameraHostAllowed
                    onHome: root.step.id === "camera"
                    tileVisible: visible
                    reducedMotion: root.tokens.reducedMotion
                    matteColor: root.tokens.surface
                    sourceComponent: root.cameraSourceComponent ? root.cameraSourceComponent : cameraTest.liveComponent
                }
                Text {
                    objectName: "onboardingCameraHint"
                    anchors.centerIn: parent
                    width: parent.width - root.tokens.medium * 2
                    visible: !root.cameraTestRequested
                    text: "The camera stays off until you press Test camera."
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
            }
            SettingsButton {
                objectName: "onboardingCameraTest"
                anchors.horizontalCenter: parent.horizontalCenter
                tokens: root.tokens
                text: root.cameraTestRequested ? "Stop test" : "Test camera"
                enabled: root.cameraHostAllowed
                onClicked: root.cameraTestRequested = !root.cameraTestRequested
            }
            Body { text: "The mirror shows your camera on Home, and runs only while it shows." }
            StepSettings { stepId: "camera" }
        }
    }
    // The summon line with Copy and a conflict check, and, when the island
    // is not the bar's centre anchor, how to make it one.
    Component {
        id: shortcutsStep
        Column {
            spacing: root.tokens.gap
            Component.onCompleted: if (root.coordinator && typeof root.coordinator.checkSummonBinding === "function")
                root.coordinator.checkSummonBinding()
            Body { text: "Open the island from a key by adding this line to ~/.config/hypr/bindings.lua:" }
            Controls.TextArea {
                id: snippet
                objectName: "onboardingSummonSnippet"
                width: parent.width
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                text: Strings.summonBinding
                color: root.tokens.text
                selectionColor: root.tokens.primaryFill
                selectedTextColor: root.tokens.primaryLabel
                font.family: "monospace"
                font.pixelSize: root.tokens.captionSize
                background: Rectangle { color: root.tokens.surfaceSunken; radius: root.tokens.small }
            }
            SummonSnippetActions {
                width: parent.width
                tokens: root.tokens
                snippet: snippet
                conflict: root.coordinator ? String(root.coordinator.summonConflict || "") : ""
            }
            Column {
                objectName: "onboardingPlacement"
                visible: !!root.coordinator && root.coordinator.islandOffCentre === true
                width: parent.width
                spacing: root.tokens.small
                topPadding: root.tokens.medium
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "The island is not at the middle of your bar, so the notch covers the wrong place. Move it and make it the bar's centre anchor:"
                    textFormat: Text.PlainText
                    color: root.tokens.error
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
                Controls.TextArea {
                    objectName: "onboardingPlacementCommand"
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAnywhere
                    text: Strings.centrePlacement
                    color: root.tokens.text
                    font.family: "monospace"
                    font.pixelSize: root.tokens.captionSize
                    background: Rectangle { color: root.tokens.surfaceSunken; radius: root.tokens.small }
                }
            }
        }
    }
    Component {
        id: doneStep
        Column {
            spacing: root.tokens.medium
            Body { text: "All set. Everything here, and more, is in the settings window; the welcome can be shown again from its About section." }
            SettingsButton {
                objectName: "onboardingOpenSettings"
                anchors.horizontalCenter: parent.horizontalCenter
                tokens: root.tokens
                text: "Customize in Settings"
                enabled: !!root.coordinator
                onClicked: root.coordinator.openSettings("")
            }
        }
    }
}
