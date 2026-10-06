pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import "../qml/Strings.js" as Strings

Controls.AbstractButton {
    id: root
    required property var tokens
    property string iconName: ""
    property bool primary: false
    // A player button, after boring.notch's: it dips to 0.9 while pressed
    // and springs back (0.3, 0.3), on the raised surface when hovered.
    property bool bounce: false
    // The icon's colour; a toggle that is on takes the tint.
    property color iconColor: primary ? tokens.primaryLabel : tokens.text
    property real iconSize: 20
    property bool tooltipsEnabled: true
    property bool actionEnabled: true
    property string disabledReason: ""
    property bool pending: false
    property var coordinator: null
    property string actionName: ""
    property var capturedIntent: null
    readonly property string endpointIdentity: coordinator && coordinator.selectedEndpoint ? JSON.stringify(coordinator.selectedEndpoint.token) : ""
    signal activated
    implicitWidth: iconName && !text ? tokens.target : Math.max(tokens.target, label.implicitWidth + tokens.inset * 2)
    implicitHeight: primary ? tokens.primaryTarget : tokens.target
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    Accessible.name: accessibleLabel || text
    property string accessibleLabel: ""
    Accessible.description: pending ? Strings.sendingCommand : (!actionEnabled ? disabledReason : "")
    Accessible.role: Accessible.Button
    Accessible.onPressAction: trigger()
    function trigger() {
        if (!actionEnabled || pending)
            return;
        if (actionName && coordinator) {
            var intent = coordinator.captureIntent();
            if (intent)
                coordinator.invoke(actionName, intent);
        } else
            activated();
    }
    onPressed: capturedIntent = actionEnabled && !pending && coordinator && actionName ? coordinator.captureIntent() : null
    onCanceled: capturedIntent = null
    onClicked: {
        if (!actionEnabled || pending) {
            capturedIntent = null;
            return;
        }
        if (actionName && coordinator) {
            if (capturedIntent)
                coordinator.invoke(actionName, capturedIntent);
        } else
            activated();
        capturedIntent = null;
    }
    onActionEnabledChanged: if (!actionEnabled)
        capturedIntent = null
    // An ancestor turning enabled off fires neither onActionEnabledChanged nor
    // onVisibleChanged, so a captured press would otherwise outlive the context
    // it was captured in.
    onEnabledChanged: if (!enabled)
        capturedIntent = null
    onVisibleChanged: if (!visible)
        capturedIntent = null
    onEndpointIdentityChanged: capturedIntent = null
    readonly property bool bounceDown: bounce && down && actionEnabled && !pending
    scale: bounce ? bounceSpring.value : 1
    onBounceDownChanged: bounceSpring.moveTo(bounceDown ? 0.9 : 1, 0.3, 0.3, tokens.feedbackDuration <= 0)
    SpringDriver {
        id: bounceSpring
        value: 1
    }
    IslandToolTip {
        id: helpTip
        objectName: "buttonToolTip"
        parent: root
        tokens: root.tokens
        visible: root.tooltipsEnabled && (root.hovered || (root.activeFocus && (!root.actionEnabled || root.pending)))
        delay: root.hovered ? 600 : 800
        text: root.pending ? Strings.sendingCommand : !root.actionEnabled && root.disabledReason ? root.disabledReason : root.accessibleLabel || root.text
    }
    background: Rectangle {
        radius: height / 2
        readonly property bool raised: root.bounce && !root.primary && (root.hovered || root.down)
        color: root.primary && !root.actionEnabled ? root.tokens.track : root.primary ? (root.down && !root.pending ? Qt.darker(root.tokens.primaryFill, 1.12) : root.hovered ? Qt.lighter(root.tokens.primaryFill, 1.08) : root.tokens.primaryFill) : raised ? root.tokens.raisedSurface : (root.hovered || root.down ? root.tokens.hover : "transparent")
        border.width: root.visualFocus ? root.tokens.focusWidth : raised ? 1 : 0
        border.color: root.visualFocus ? (root.primary ? root.tokens.text : root.tokens.accent) : root.tokens.raisedStroke
        // A bouncing button scales as a whole instead.
        scale: !root.bounce && root.down && root.actionEnabled && !root.pending ? 0.96 : 1
        // Finite state feedback. Bounded by feedbackDuration, which the tokens
        // force to 0 under reduced motion, so it settles immediately.
        Behavior on color {
            enabled: root.tokens.feedbackDuration > 0
            ColorAnimation { duration: root.tokens.feedbackDuration }
        }
        Behavior on scale {
            enabled: root.tokens.feedbackDuration > 0
            NumberAnimation { duration: root.tokens.feedbackDuration }
        }
    }
    contentItem: Item {
        opacity: root.actionEnabled ? 1 : 0.6
        Behavior on opacity {
            enabled: root.tokens.feedbackDuration > 0
            NumberAnimation { duration: root.tokens.feedbackDuration }
        }
        IslandIcon {
            anchors.centerIn: parent
            visible: root.iconName !== ""
            width: root.iconSize
            height: root.iconSize
            name: root.iconName
            ink: root.iconColor
        }
        Text {
            id: label
            anchors.fill: parent
            anchors.leftMargin: root.tokens.gap
            anchors.rightMargin: root.tokens.gap
            text: root.text
            visible: root.iconName === ""
            color: root.primary ? root.tokens.primaryLabel : root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.bodySize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Rectangle {
            visible: root.pending
            width: root.tokens.gap
            height: root.tokens.small
            radius: height / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            color: root.primary ? root.tokens.primaryLabel : root.tokens.tint
        }
    }
}
