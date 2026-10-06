pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Shelf.js" as Shelf

// One shelf item: a 56 px thumbnail (or its theme icon, or a glyph) over a
// two-line, middle-elided name, in a 105 px tile. The thumbnail tries each
// freedesktop cache candidate in turn and asks the coordinator to generate
// one when they all miss. Selection and the inline rename editor are driven
// by the view; this tile only reports clicks, menu requests and edits.
Item {
    id: tile
    required property var item
    property var coordinator: null
    property var ink: null
    property bool selected: false
    property bool editing: false
    signal clicked(var modifiers)
    signal menuRequested(real x, real y)
    signal renameCommitted(string name)
    signal renameCancelled()
    width: 105
    height: 105
    activeFocusOnTab: !editing
    Accessible.role: Accessible.ListItem
    Accessible.name: item.name
    Accessible.selected: selected

    readonly property color fill: selected ? ink.selectedFill : ink.surface
    Rectangle {
        objectName: "shelfTileBackground"
        anchors.fill: parent
        radius: 12
        color: tile.fill
        border.width: tile.activeFocus || tile.selected ? 2 : 0
        border.color: tile.activeFocus ? tile.ink.accent : tile.ink.selectedStroke
    }

    // Thumbnail candidates: the generated entry first, then the cache.
    readonly property var candidates: coordinator && item.kind === "file" && typeof coordinator.shelfThumbnailCandidates === "function"
        ? coordinator.shelfThumbnailCandidates(item.id) : []
    readonly property var icons: coordinator && typeof coordinator.shelfIcons === "function" ? coordinator.shelfIcons(item.id) : []
    property int attempt: 0
    property int iconAttempt: 0
    onCandidatesChanged: attempt = 0
    onIconsChanged: iconAttempt = 0
    readonly property bool exhausted: attempt >= candidates.length
    onExhaustedChanged: requestThumbnail()
    readonly property string mime: coordinator && coordinator.shelfMimes ? coordinator.shelfMimes[item.id] || "" : ""
    onMimeChanged: requestThumbnail()
    function requestThumbnail() {
        if (exhausted && item.kind === "file" && coordinator && typeof coordinator.requestShelfThumbnail === "function")
            coordinator.requestShelfThumbnail(item.id)
    }

    Item {
        id: thumbBox
        width: 56
        height: 56
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        Image {
            id: thumbnail
            objectName: "shelfThumbnail"
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(112, 112)
            source: tile.attempt < tile.candidates.length ? Shelf.fileUrl(tile.candidates[tile.attempt]) : ""
            onStatusChanged: if (status === Image.Error) tile.attempt++
        }
        Image {
            id: themeIcon
            objectName: "shelfThemeIcon"
            anchors.centerIn: parent
            width: 40
            height: 40
            sourceSize: Qt.size(80, 80)
            visible: thumbnail.status !== Image.Ready && status === Image.Ready
            source: thumbnail.status !== Image.Ready && tile.iconAttempt < tile.icons.length
                ? "image://icon/" + tile.icons[tile.iconAttempt] : ""
            onStatusChanged: if (status === Image.Error) tile.iconAttempt++
        }
        IslandIcon {
            objectName: "shelfGlyph"
            anchors.centerIn: parent
            width: 32
            height: 32
            visible: thumbnail.status !== Image.Ready && themeIcon.status !== Image.Ready
            name: tile.item.kind === "link" ? "link" : tile.item.kind === "text" ? "note" : "file"
            ink: tile.ink.inkSecondary
        }
        // Rounds the thumbnail's corners to 12 px without an effect: a ring in
        // the tile's own colour covers everything outside the rounded rect.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -12
            radius: 24
            color: "transparent"
            border.width: 12
            border.color: tile.fill
            visible: thumbnail.status === Image.Ready
        }
    }

    FontMetrics {
        id: metrics
        font.family: tile.ink.fontFamily
        font.pixelSize: tile.ink.captionSize
    }
    Text {
        id: label
        objectName: "shelfTileName"
        visible: !tile.editing
        anchors.top: thumbBox.bottom
        anchors.topMargin: 6
        x: 6
        width: parent.width - 12
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        textFormat: Text.PlainText
        text: Shelf.middleElide(tile.item.name, 2 * width / Math.max(1, metrics.averageCharacterWidth) - 2)
        color: tile.ink.ink
        font.family: tile.ink.fontFamily
        renderType: tile.ink.textRenderType
        font.pixelSize: tile.ink.captionSize
    }
    Rectangle {
        visible: tile.editing
        anchors.fill: editor
        anchors.margins: -3
        radius: 4
        color: tile.ink.raised
        border.width: 1
        border.color: tile.ink.selectedStroke
    }
    TextInput {
        id: editor
        objectName: "shelfRenameEditor"
        visible: tile.editing
        anchors.top: thumbBox.bottom
        anchors.topMargin: 6
        x: 6
        width: parent.width - 12
        clip: true
        color: tile.ink.ink
        selectionColor: tile.ink.selectedStroke
        font.family: tile.ink.fontFamily
        renderType: tile.ink.textRenderType
        font.pixelSize: tile.ink.captionSize
        selectByMouse: true
        // Accepted here: TextInput lets Return propagate after finishing, and
        // the view would then also open the file.
        Keys.onReturnPressed: event => { event.accepted = true; tile.renameCommitted(text) }
        Keys.onEnterPressed: event => { event.accepted = true; tile.renameCommitted(text) }
        Keys.onEscapePressed: event => { event.accepted = true; tile.renameCancelled() }
        onActiveFocusChanged: if (!activeFocus && tile.editing) tile.renameCancelled()
    }
    onEditingChanged: {
        if (!editing) return
        editor.text = item.name
        var dot = item.name.lastIndexOf(".")
        editor.select(0, dot > 0 ? dot : item.name.length)
        editor.forceActiveFocus()
    }

    // Exclusive, so the tap never also reaches the view's background, which
    // clears the selection; a DragHandler may still take the point over.
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.RightButton) {
                tile.menuRequested(eventPoint.position.x, eventPoint.position.y)
                return
            }
            var modifiers = point.modifiers
            tile.clicked({ ctrl: (modifiers & Qt.ControlModifier) !== 0, shift: (modifiers & Qt.ShiftModifier) !== 0 })
        }
    }
}
