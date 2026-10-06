pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import "../qml/Strings.js" as Strings
import "../qml/SourceState.js" as SourceState

Item {
    id: root
    required property var tokens
    property var coordinator: null
    // In overlay mode the player header is visible behind this surface, so the
    // picker's own title and back row would duplicate it.
    property bool overlay: false
    // In the welcome, a choice is remembered across restarts (the
    // coordinator's rememberSource) instead of pinned for the session, and
    // Auto forgets the remembered player.
    property bool remember: false
    readonly property bool remembering: remember && !!coordinator && typeof coordinator.rememberSource === "function"
    signal dismissed
    // Why the last remembered choice was not saved; "" when it was. A
    // refusal keeps the picker open with this sentence, since the choice
    // would otherwise look remembered when it is not.
    property string rememberError: ""
    function remembered(token) {
        var saved = coordinator.rememberSource(token) === true;
        rememberError = saved ? "" : Strings.settingErrorText(String(coordinator.configureError || ""), null);
        return saved;
    }
    // Whether the picker may close: a session pin always does, a
    // remembered choice only once it is saved.
    function choose(token) {
        if (!coordinator || !token)
            return true;
        if (remembering)
            return remembered(token);
        coordinator.selectSource(token);
        return true;
    }
    function chooseAuto() {
        if (!coordinator)
            return true;
        if (remembering)
            return remembered(null);
        coordinator.selectAuto();
        return true;
    }
    function isChosen(endpoint) {
        if (!coordinator || !endpoint)
            return false;
        if (remembering)
            return !!coordinator.preferredSource && coordinator.preferredSource === SourceState.appIdentity(endpoint);
        return coordinator.selectionMode === "pinned" && !!coordinator.selectedEndpoint
            && JSON.stringify(coordinator.selectedEndpoint.token) === JSON.stringify(endpoint.token);
    }
    Component.onCompleted: autoButton.forceActiveFocus(Qt.TabFocusReason)
    function focusSource(index) {
        if (index < 0) {
            autoButton.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        if (index >= sources.count)
            return;
        sources.positionViewAtIndex(index, ListView.Contain);
        Qt.callLater(function () {
            var item = sources.itemAtIndex(index);
            if (item) item.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    function sourceName(endpoint) {
        return Strings.sourceName(endpoint.presentation);
    }
    Text {
        visible: !root.overlay
        x: root.tokens.inset
        y: root.tokens.inset
        width: parent.width - root.tokens.inset * 3 - root.tokens.target
        height: root.tokens.target
        elide: Text.ElideRight
        text: "Sources"
        color: root.tokens.text
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.titleSize
        font.weight: Font.DemiBold
        verticalAlignment: Text.AlignVCenter
    }
    IslandButton {
        visible: !root.overlay
        x: parent.width - width - root.tokens.inset
        y: root.tokens.inset
        tokens: root.tokens
        iconName: "back"
        accessibleLabel: Strings.backToPlayer
        onActivated: root.dismissed()
    }
    IslandButton {
        id: autoButton
        objectName: "autoSourceButton"
        x: root.tokens.inset
        y: root.overlay ? root.tokens.inset : root.tokens.heroArtSize
        width: parent.width - root.tokens.inset * 2
        tokens: root.tokens
        text: root.remembering
            ? (root.coordinator.preferredSource ? "Follow whatever plays" : "Auto · Selected")
            : root.coordinator && root.coordinator.selectionMode === "auto" ? "Auto · Selected" : "Choose source automatically"
        Keys.onDownPressed: root.focusSource(0)
        Keys.onTabPressed: event => {
            if (sources.count) root.focusSource(0);
            else event.accepted = false;
        }
        onActivated: {
            if (root.chooseAuto())
                root.dismissed();
        }
    }
    Text {
        id: rememberNotice
        objectName: "sourceRememberError"
        visible: root.rememberError !== ""
        x: root.tokens.inset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.tokens.small
        width: parent.width - root.tokens.inset * 2
        wrapMode: Text.WordWrap
        text: root.rememberError
        textFormat: Text.PlainText
        color: root.tokens.error
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }
    Controls.ScrollView {
        x: root.tokens.inset
        y: (root.overlay ? root.tokens.inset : root.tokens.heroArtSize) + root.tokens.target + root.tokens.gap
        width: parent.width - root.tokens.inset * 2
        height: parent.height - y - root.tokens.inset - (rememberNotice.visible ? rememberNotice.height + root.tokens.small : 0)
        clip: true
        contentWidth: availableWidth
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        ListView {
            id: sources
            objectName: "sourceList"
            model: root.coordinator ? root.coordinator.endpoints : []
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            spacing: root.tokens.small
            delegate: Controls.AbstractButton {
                id: row
                required property var modelData
                width: sources.width
                height: root.tokens.rowHeight + root.tokens.gap
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                readonly property bool selected: root.isChosen(modelData)
                property var capturedToken: null
                onActiveFocusChanged: if (activeFocus) sources.positionViewAtIndex(index, ListView.Contain)
                required property int index
                Accessible.name: root.sourceName(modelData) + ", " + (modelData.status === "Playing" ? "Playing" : "Paused") + (selected ? ", selected" : "")
                Accessible.role: Accessible.Button
                Accessible.onPressAction: {
                    if (root.choose(modelData.token))
                        root.dismissed();
                }
                Keys.onDownPressed: root.focusSource(index + 1)
                Keys.onUpPressed: root.focusSource(index - 1)
                Keys.onTabPressed: event => {
                    if (index + 1 < sources.count) root.focusSource(index + 1);
                    else event.accepted = false;
                }
                Keys.onBacktabPressed: root.focusSource(index - 1)
                onPressed: capturedToken = JSON.parse(JSON.stringify(modelData.token))
                onCanceled: capturedToken = null
                onClicked: {
                    var closes = capturedToken ? root.choose(capturedToken) : true;
                    capturedToken = null;
                    if (closes)
                        root.dismissed();
                }
                background: Rectangle {
                    radius: root.tokens.rowRadius
                    color: row.hovered ? root.tokens.hover : row.selected ? root.tokens.surfaceRaised : "transparent"
                    border.color: row.visualFocus ? root.tokens.accent : row.selected ? root.tokens.tint : root.tokens.hairline
                    border.width: row.visualFocus ? root.tokens.focusWidth : 1
                    Behavior on color {
                        enabled: root.tokens.feedbackDuration > 0
                        ColorAnimation { duration: root.tokens.feedbackDuration }
                    }
                }
                contentItem: Item {
                    Text {
                        x: root.tokens.gap
                        y: root.tokens.gap
                        width: parent.width - root.tokens.target - root.tokens.inset
                        text: root.sourceName(row.modelData)
                        color: root.tokens.text
                        font.family: root.tokens.fontFamily
                        renderType: root.tokens.textRenderType
                        font.pixelSize: root.tokens.bodySize
                        font.weight: Font.Medium
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    Text {
                        x: root.tokens.gap
                        y: root.tokens.inset + root.tokens.gap + root.tokens.small
                        width: parent.width - root.tokens.target - root.tokens.inset
                        text: (row.modelData.status === "Playing" ? "Playing" : "Paused") + (row.modelData.presentation && row.modelData.presentation.title ? " · " + row.modelData.presentation.title : "")
                        color: root.tokens.secondary
                        font.family: root.tokens.fontFamily
                        renderType: root.tokens.textRenderType
                        font.pixelSize: root.tokens.captionSize
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    IslandIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: root.tokens.gap
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        ink: root.tokens.tint
                        visible: row.selected
                    }
                }
            }
        }
    }
    Text {
        visible: !root.coordinator || root.coordinator.endpoints.length === 0
        x: root.tokens.inset
        y: (root.overlay ? root.tokens.inset : root.tokens.heroArtSize) + root.tokens.rowHeight + root.tokens.inset
        width: parent.width - root.tokens.inset * 2
        text: "Open Spotify, or play music in your browser, to choose a source."
        color: root.tokens.secondary
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.bodySize
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
    }
}
