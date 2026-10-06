pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls

Item {
    id: root
    required property var tokens
    property var coordinator: null
    property string action: "SetPosition"
    property string label: "Playback position"
    property string disabledReason: "This source does not support seeking"
    property bool actionEnabled: true
    property bool showValue: action === "SetVolume"
    property real sample: 0
    property real maximum: 1
    property real step: 1
    property var capturedIntent: null
    property bool gesturing: false
    property real preview: sample
    readonly property real displayValue: gesturing ? preview : sample
    // The scrubber's track, after boring.notch's: scrubHeight at rest and
    // scrubHeightActive while dragged, springing (0.35, 0.7) between them.
    // Off, the track keeps its plain small height.
    property bool thickens: false
    // Above 0, a drag also sends its value every liveInterval ms while it
    // runs, not only on release (the volume popover writes as it moves).
    property int liveInterval: 0
    // One latest write survives an outstanding command. A release marks it
    // committed; a canceled gesture discards only its uncommitted preview.
    property var queuedWrite: null
    onPreviewChanged: if (gesturing && liveInterval > 0) {
        if (queuedWrite && !queuedWrite.committed)
            queuedWrite = Object.assign({}, queuedWrite, { value: preview });
        if (!liveTimer.running)
            liveTimer.start();
    }
    Timer {
        id: liveTimer
        interval: Math.max(1, root.liveInterval)
        repeat: false
        onTriggered: if (root.gesturing && root.capturedIntent && root.coordinator && root.coordinator.uiAllowed)
            root.submitOrQueue(root.capturedIntent, root.preview, false)
    }
    property color fillColor: tokens.tint
    // Space left and right of the track, inside the control. The track is
    // centred vertically in the control's whole height.
    property real trackPadding: 6
    readonly property real restTrack: thickens ? tokens.scrubHeight : tokens.small
    readonly property real trackTarget: thickens && gesturing ? tokens.scrubHeightActive : restTrack
    readonly property real trackHeight: thickens ? trackSpring.value : tokens.small
    onTrackTargetChanged: trackSpring.moveTo(trackTarget, 0.35, 0.7, tokens.reducedMotion)
    SpringDriver {
        id: trackSpring
        Component.onCompleted: settle(root.restTrack)
    }
    readonly property string identity: coordinator && coordinator.selectedEndpoint ? JSON.stringify([coordinator.selectedEndpoint.token, coordinator.selectedEndpoint.trackToken]) : ""
    implicitHeight: tokens.target
    implicitWidth: 120
    function beginGesture() {
        if (!actionEnabled || !coordinator || !coordinator.uiAllowed || gesturing)
            return false;
        capturedIntent = coordinator.captureIntent();
        if (!capturedIntent)
            return false;
        gesturing = true;
        preview = Math.max(0, Math.min(maximum, sample));
        return true;
    }
    function updateGesture(value) {
        if (gesturing)
            preview = Math.max(0, Math.min(maximum, value));
    }
    function submitOrQueue(intent, value, committed) {
        if (liveInterval > 0 && coordinator.pendingAction) {
            queuedWrite = { intent: intent, value: value, identity: identity, committed: committed };
            return;
        }
        queuedWrite = null;
        coordinator.invoke(action, intent, value);
    }
    function flushQueued() {
        var write = queuedWrite;
        if (!write || !coordinator || coordinator.pendingAction || (gesturing && liveTimer.running))
            return;
        queuedWrite = null;
        if (enabled && visible && actionEnabled && coordinator.uiAllowed && write.identity === identity)
            coordinator.invoke(action, write.intent, gesturing ? preview : write.value);
    }
    function commitGesture() {
        // Belt and braces against binding-order: two independent bindings change
        // when the overlay opens and Qt does not guarantee which lands first.
        if (!enabled || !actionEnabled) {
            cancelGesture();
            return;
        }
        var intent = capturedIntent, value = preview;
        cancelGesture();
        if (intent && actionEnabled && coordinator && coordinator.uiAllowed)
            submitOrQueue(intent, value, true);
    }
    function cancelGesture() {
        liveTimer.stop();
        capturedIntent = null;
        gesturing = false;
        if (queuedWrite && !queuedWrite.committed)
            queuedWrite = null;
    }
    onIdentityChanged: { cancelGesture(); queuedWrite = null; }
    onActionEnabledChanged: if (!actionEnabled) {
        cancelGesture(); queuedWrite = null;
    }
    onVisibleChanged: if (!visible) {
        cancelGesture(); queuedWrite = null;
    }
    // Effective-enabled propagates from an ancestor and fires neither of the two
    // handlers above. Without this, covering the stage would ungrab the mouse,
    // drop `pressed`, and let onPressedChanged commit the gesture the user never
    // released.
    onEnabledChanged: if (!enabled) {
        cancelGesture(); queuedWrite = null;
    }
    Connections {
        target: root.coordinator
        function onPendingActionChanged() {
            root.flushQueued();
        }
        function onUiAllowedChanged() {
            if (!root.coordinator.uiAllowed) {
                root.cancelGesture();
                root.queuedWrite = null;
            }
        }
    }
    Controls.Slider {
        id: slider
        objectName: "intentSlider"
        anchors.fill: parent
        leftPadding: root.trackPadding
        rightPadding: root.trackPadding
        topPadding: 0
        bottomPadding: 0
        from: 0
        to: Math.max(1, root.maximum)
        stepSize: root.step
        live: true
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        onActiveFocusChanged: if (!activeFocus) root.cancelGesture()
        Accessible.name: root.label
        Accessible.description: root.actionEnabled ? "" : root.disabledReason
        Accessible.onIncreaseAction: root.keyboardStep(root.step)
        Accessible.onDecreaseAction: root.keyboardStep(-root.step)
        onPressedChanged: {
            if (pressed)
                root.beginGesture();
            else if (root.gesturing)
                root.commitGesture();
        }
        onMoved: if (pressed)
            root.updateGesture(value)
        Keys.onPressed: event => {
            // Escape is the slider's only while a drag or a key step is
            // running, to cancel it. Otherwise it bubbles on to the view's
            // Escape ladder, so a focused slider never traps the key.
            if (event.key === Qt.Key_Escape) {
                event.accepted = root.gesturing;
                root.cancelGesture();
                return;
            }
            if ([Qt.Key_Left, Qt.Key_Down, Qt.Key_Right, Qt.Key_Up, Qt.Key_Home, Qt.Key_End].indexOf(event.key) < 0)
                return;
            if (!root.gesturing)
                root.beginGesture();
            if (root.gesturing) {
                if (event.key === Qt.Key_Home)
                    root.updateGesture(0);
                else if (event.key === Qt.Key_End)
                    root.updateGesture(root.maximum);
                else
                    root.updateGesture(root.preview + (event.key === Qt.Key_Left || event.key === Qt.Key_Down ? -root.step : root.step));
            }
            event.accepted = true;
        }
        Keys.onReleased: event => {
            if ([Qt.Key_Left, Qt.Key_Down, Qt.Key_Right, Qt.Key_Up, Qt.Key_Home, Qt.Key_End].indexOf(event.key) < 0)
                return;
            if (!event.isAutoRepeat)
                root.commitGesture();
            event.accepted = true;
        }
        Binding {
            target: slider
            property: "value"
            value: root.displayValue
            when: !slider.pressed
        }
        background: Rectangle {
            objectName: "intentSliderTrack"
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: root.trackHeight
            radius: height / 2
            color: root.tokens.surfaceSunken
            Rectangle {
                objectName: "intentSliderFill"
                width: parent.width * Math.max(0, Math.min(1, root.displayValue / Math.max(1, root.maximum)))
                height: parent.height
                radius: parent.radius
                color: root.actionEnabled ? root.fillColor : root.tokens.secondary
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -root.tokens.small
                radius: root.tokens.gap
                color: "transparent"
                border.width: slider.visualFocus ? root.tokens.focusWidth : 0
                border.color: root.tokens.accent
            }
        }
        handle: Rectangle {
            objectName: "intentSliderHandle"
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: root.tokens.medium
            height: width
            radius: width / 2
            color: root.actionEnabled ? root.fillColor : root.tokens.secondary
            visible: slider.hovered || slider.activeFocus || root.gesturing
        }
        IslandToolTip {
            parent: slider
            tokens: root.tokens
            visible: (slider.hovered || slider.activeFocus || root.gesturing) && (!root.actionEnabled || root.showValue)
            delay: root.gesturing || slider.activeFocus ? 0 : 500
            text: !root.actionEnabled ? root.disabledReason : Math.round(root.displayValue * 100) + "%"
        }
    }
    function keyboardStep(delta) {
        if (beginGesture()) {
            updateGesture(preview + delta);
            commitGesture();
        }
    }
}
