import QtQuick

// The Share drop tile at the start of the strip, square. Files dropped here
// are shared without being shelved. A click with nothing dropped opens the
// file picker when one is installed; otherwise the tile only shows its drop
// hint.
Item {
    id: root
    property var coordinator: null
    property var actions: null
    property var ink: null
    readonly property bool canPick: !!(actions && actions.tools && actions.tools["zenity"])
    // Bound to the DropArea; not read-only only so an offscreen test, which
    // cannot start a drag carrying URLs, can stand in for an accepted drag.
    property bool dropActive: drop.containsDrag
    width: height
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: canPick ? "Share files" : "Drop files here to share them"
    Accessible.onPressAction: if (canPick && coordinator) coordinator.shelfPickAndShare()
    Keys.onReturnPressed: event => {
        event.accepted = true
        if (root.canPick && root.coordinator) root.coordinator.shelfPickAndShare()
    }
    Keys.onEnterPressed: event => {
        event.accepted = true
        if (root.canPick && root.coordinator) root.coordinator.shelfPickAndShare()
    }
    Keys.onSpacePressed: event => {
        event.accepted = true
        if (root.canPick && root.coordinator) root.coordinator.shelfPickAndShare()
    }

    function handleDrop(event) {
        if (!coordinator || !event.hasUrls || !(event.supportedActions & Qt.CopyAction)) {
            event.accepted = false
            return false
        }
        if (!coordinator.shelfShareUris(event.urls.map(String))) {
            event.accepted = false
            return false
        }
        event.accept(Qt.CopyAction)
        return true
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.ink.raised
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? root.ink.accent : root.ink.raisedStroke
    }
    ShelfDropHighlight {
        anchors.fill: parent
        ink: root.ink
        active: root.dropActive
    }
    Column {
        anchors.centerIn: parent
        spacing: 4
        IslandIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: 24
            name: "share"
            ink: root.dropActive ? root.ink.accent : root.ink.ink
        }
        Text {
            objectName: "shelfShareHint"
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.canPick ? "Share" : "Drop to share"
            color: root.ink.inkSecondary
            font.family: root.ink.fontFamily
            renderType: root.ink.textRenderType
            font.pixelSize: root.ink.captionSize
        }
    }
    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: drag => {
            if (root.coordinator && drag.hasUrls && (drag.supportedActions & Qt.CopyAction))
                drag.accept(Qt.CopyAction)
            else
                drag.accepted = false
        }
        onDropped: event => root.handleDrop(event)
    }
    // Exclusive, so the tap never also reaches the view's background, which
    // clears the selection; a DragHandler may still take the point over.
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: if (root.canPick && root.coordinator) root.coordinator.shelfPickAndShare()
    }
}
