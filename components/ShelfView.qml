pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Shelf.js" as Shelf
import "../qml/Strings.js" as Strings

// The shelf strip: a square Share tile, then the shelved items as 105 px
// tiles in one horizontal row, or a tray with "Drop files here" when empty.
//
// It takes everything it acts on as properties so the tests drive it with
// fakes: `coordinator` holds the model and runs actions (Service.qml's
// shelfEntries, shelfAction and friends), `actions` reports the installed
// tools and Open With apps (ShelfActions.qml), and `busyGuard` is any object
// with beginBusy()/endBusy(), held while the menu or the rename editor is
// open. Placement, and the catch zone that opens the shelf on a drag, belong
// to the island surface.
//
// Selection: click selects one, Ctrl-click toggles, Shift-click selects the
// range from the last plain or Ctrl click, and a click on the background
// clears. Keys: Space toggles an in-strip preview, Return opens,
// Delete removes, Ctrl+C copies, Ctrl+V shelves the clipboard's files (the
// Service's wl-paste), Left/Right move a single selection, and Escape clears
// the selection, then asks to collapse.
FocusScope {
    id: root
    property var tokens: null
    property var coordinator: null
    property var actions: null
    property var busyGuard: null
    // The island's input region (its hit shape). The menu is placed inside
    // it: a click outside the input region goes to the window beneath, so an
    // entry there could not be chosen. A menu taller than the region scrolls.
    property Item menuBounds: null
    // Something the host draws over the strip (the battery popover) is open:
    // Escape is then the host's, to close that first.
    property bool hostOverlayOpen: false
    signal collapseRequested()
    // The strip plus the refusal notice under it, so a host gives it room.
    implicitHeight: stripNotice.y + stripNotice.implicitHeight
    // The band the Share tile and the drop zone fill: the height a host
    // gives, less a line for the notice and the notch's 12 px bottom inset,
    // and never under a tile's 105 px.
    readonly property real bandHeight: Math.max(105, height - (ink.captionSize + 4) - 12)

    readonly property var entries: coordinator && Array.isArray(coordinator.shelfEntries) ? coordinator.shelfEntries : []
    readonly property var order: entries.map(function(item) { return item.id })
    readonly property bool empty: entries.length === 0
    property var selection: Shelf.emptySelection()
    readonly property var selectedIds: selection.selected
    onOrderChanged: {
        selection = Shelf.pruneSelection(selection, order)
        if (previewId && order.indexOf(previewId) < 0) previewId = ""
    }
    readonly property var settings: coordinator && coordinator.fileSettings ? coordinator.fileSettings : ({})
    readonly property bool copyOnDrag: settings.copyOnDrag === true
    readonly property bool autoRemove: settings.autoRemoveShelfItems === true
    // The id of the tile mid drag-out, so the surface can defer a collapse.
    property string draggingId: ""
    readonly property bool dragActive: draggingId !== ""
    // A drag held over the strip or the Share tile.
    readonly property bool dropActive: stripDrop.containsDrag || shareTile.dropActive
    property string renamingId: ""
    property string previewId: ""
    readonly property var previewItem: Shelf.findItem(entries, previewId)

    ShelfInk { id: ink; tokens: root.tokens }
    ShelfBusyHold { guard: root.busyGuard; active: root.renamingId !== "" }

    function itemsFor(ids) {
        return entries.filter(function(item) { return ids.indexOf(item.id) >= 0 })
    }
    function click(id, modifiers) {
        selection = Shelf.selectClick(selection, order, id, modifiers)
        forceActiveFocus()
    }
    function focusTile(id) {
        selection = Shelf.selectClick(selection, order, id, {})
    }
    function focusControls() {
        var first = shareTile.canPick || empty ? shareTile : strip.itemAtIndex(0)
        if (!first) first = shareTile
        first.forceActiveFocus(Qt.TabFocusReason)
        return first.activeFocus
    }
    function clearSelection() {
        selection = Shelf.emptySelection()
        previewId = ""
    }
    // A drag or menu on an unselected tile acts on that tile alone.
    function targetIds(id) {
        if (selectedIds.indexOf(id) < 0) selection = Shelf.selectClick(selection, order, id, {})
        return selectedIds
    }
    function dragData(id) {
        return Shelf.dragMimeData(itemsFor(selectedIds.indexOf(id) >= 0 ? selectedIds : [id]))
    }
    function dragActions() {
        return copyOnDrag ? Qt.CopyAction : Qt.CopyAction | Qt.MoveAction
    }
    // After a drag out: with autoRemoveShelfItems, an accepted drop takes
    // the dragged items off the shelf.
    function finishDrag(id, dropAction) {
        var ids = selectedIds.indexOf(id) >= 0 ? selectedIds.slice() : [id]
        if (draggingId === id) draggingId = ""
        if (autoRemove && dropAction !== Qt.IgnoreAction && coordinator) coordinator.shelfAction("remove", ids)
    }
    function menuEntriesFor(ids) {
        var items = itemsFor(ids)
        var mimes = coordinator && coordinator.shelfMimes ? coordinator.shelfMimes : {}
        var apps = items.length === 1 && items[0].kind === "file" && actions && typeof actions.openWithApps === "function"
            ? actions.openWithApps(mimes[items[0].id]) : []
        return Shelf.menuEntries(items, { tools: actions && actions.tools ? actions.tools : {}, mimes: mimes, apps: apps })
    }
    function openMenu(id, x, y) {
        var ids = targetIds(id)
        menu.entries = menuEntriesFor(ids)
        if (!menu.entries.length) return
        fitMenu()
        menu.popup(root, x, y)
    }
    // Margins from the window's edges to the input region, set once per
    // opening: the input mask itself never changes for the menu.
    function fitMenu() {
        var window = root.Window.window
        if (!menuBounds || !window) return
        var area = menuBounds.mapToItem(null, 0, 0, menuBounds.width, menuBounds.height)
        menu.topMargin = Math.max(0, area.y)
        menu.leftMargin = Math.max(0, area.x)
        menu.rightMargin = Math.max(0, window.width - area.x - area.width)
        menu.bottomMargin = Math.max(0, window.height - area.y - area.height)
    }
    // The menu key or Shift+F10 opens the menu on the selection, at its
    // last tile; the menu then takes the arrows, Return and Escape.
    function openMenuFromKeyboard() {
        var id = previewTargetId()
        var index = order.indexOf(id)
        if (index < 0) return false
        strip.positionViewAtIndex(index, ListView.Contain)
        strip.forceLayout()
        var tile = strip.itemAtIndex(index)
        var point = tile ? tile.mapToItem(root, tile.width / 2, tile.height / 2) : Qt.point(0, 0)
        openMenu(id, point.x, point.y)
        // Opened by keyboard, the first entry is current, as in a desktop
        // context menu; the arrows move from there.
        if (menu.opened) menu.currentIndex = 0
        return true
    }
    function perform(action, argument) {
        if (!selectedIds.length || !coordinator) return
        if (action === "rename") {
            renamingId = selectedIds[0]
            return
        }
        coordinator.shelfAction(action, selectedIds.slice(), argument)
    }
    function commitRename(name) {
        var id = renamingId
        renamingId = ""
        if (coordinator && id && name !== Shelf.findItem(entries, id).name) coordinator.shelfAction("rename", [id], name)
        forceActiveFocus()
    }
    function cancelRename() {
        renamingId = ""
        forceActiveFocus()
    }
    function moveSelection(step) {
        if (!order.length) return
        var at = selectedIds.length ? order.indexOf(selectedIds[selectedIds.length - 1]) : (step > 0 ? -1 : order.length)
        var next = Math.max(0, Math.min(order.length - 1, at + step))
        selection = { selected: [order[next]], anchor: order[next] }
        if (previewId) previewId = order[next]
        strip.positionViewAtIndex(next, ListView.Contain)
    }
    function previewTargetId() {
        if (selectedIds.indexOf(selection.anchor) >= 0) return selection.anchor
        return selectedIds.length ? selectedIds[0] : ""
    }
    function handleStripDrop(event) {
        if (!coordinator || !(event.hasUrls || event.hasText) || !(event.supportedActions & Qt.CopyAction)) {
            event.accepted = false
            return false
        }
        var added = coordinator.shelfAddDrop(event.hasUrls ? event.urls.map(String) : [],
            event.hasText ? event.text : undefined)
        if (added <= 0) {
            event.accepted = false
            return false
        }
        event.accept(Qt.CopyAction)
        return true
    }

    Keys.onPressed: event => {
        if (renamingId) return
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (event.key === Qt.Key_Escape) {
            if (hostOverlayOpen) return
            if (previewId) previewId = ""
            else if (selectedIds.length) clearSelection()
            else root.collapseRequested()
        } else if (event.key === Qt.Key_Space) {
            previewId = previewId ? "" : previewTargetId()
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            perform("open")
        } else if (event.key === Qt.Key_Delete) {
            perform("remove")
        } else if (ctrl && event.key === Qt.Key_C) {
            perform("copy")
        } else if (ctrl && event.key === Qt.Key_V) {
            // The one route in without a drag: a keyboard user, or no file
            // manager open. Refusals show in the notice under the strip.
            if (coordinator && typeof coordinator.shelfPaste === "function") coordinator.shelfPaste()
        } else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            if (!openMenuFromKeyboard()) return
        } else if (event.key === Qt.Key_Left) {
            moveSelection(-1)
        } else if (event.key === Qt.Key_Right) {
            moveSelection(1)
        } else {
            return
        }
        event.accepted = true
    }

    // A click on the background, including the empty state, clears.
    TapHandler {
        onTapped: {
            root.clearSelection()
            root.forceActiveFocus()
        }
    }

    ShelfShareTile {
        id: shareTile
        objectName: "shelfShareTile"
        anchors.left: parent.left
        anchors.top: parent.top
        height: root.bandHeight
        coordinator: root.coordinator
        actions: root.actions
        ink: ink
    }

    Item {
        id: stripArea
        anchors.left: shareTile.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.bandHeight

        Column {
            objectName: "shelfEmptyState"
            anchors.centerIn: parent
            visible: root.empty
            spacing: 6
            IslandIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28
                height: 28
                name: "tray"
                ink: ink.inkSecondary
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Drop files here"
                textFormat: Text.PlainText
                color: ink.inkSecondary
                font.family: ink.fontFamily
                renderType: ink.textRenderType
                font.pixelSize: ink.bodySize
            }
        }

        ListView {
            id: strip
            objectName: "shelfStrip"
            // The 105 px tiles, centred in the drop zone.
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: (parent.height - 105) / 2
            anchors.bottomMargin: (parent.height - 105) / 2
            visible: !root.empty && !root.previewId
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width && !root.dragActive
            model: root.entries
            delegate: ShelfTile {
                id: tile
                required property var modelData
                item: modelData
                coordinator: root.coordinator
                ink: ink
                selected: root.selectedIds.indexOf(modelData.id) >= 0
                editing: root.renamingId === modelData.id
                onActiveFocusChanged: if (activeFocus && !editing) root.focusTile(modelData.id)
                onClicked: modifiers => root.click(modelData.id, modifiers)
                onMenuRequested: (x, y) => {
                    var point = tile.mapToItem(root, x, y)
                    root.openMenu(modelData.id, point.x, point.y)
                }
                onRenameCommitted: name => root.commitRename(name)
                onRenameCancelled: root.cancelRename()

                DragHandler {
                    id: dragHandler
                    target: null
                    dragThreshold: 8
                    enabled: !tile.editing
                    onActiveChanged: {
                        if (active) {
                            root.targetIds(tile.modelData.id)
                            root.draggingId = tile.modelData.id
                        } else if (root.draggingId === tile.modelData.id) {
                            root.draggingId = ""
                        }
                    }
                }
                // Drags carry every selected item when this tile is part of
                // the selection. copyOnDrag limits the target to copying;
                // autoRemoveShelfItems takes the items off once a drop is
                // accepted.
                Drag.active: dragHandler.active
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: root.dragActions()
                Drag.mimeData: root.dragData(modelData.id)
                Drag.hotSpot: Qt.point(width / 2, height / 2)
                Drag.onDragFinished: dropAction => root.finishDrag(tile.modelData.id, dropAction)
                Component.onDestruction: if (root.draggingId === modelData.id) root.draggingId = ""
            }
        }

        // The drop zone's dashed frame, always drawn, as boring.notch's:
        // white at 10 % at rest, the accent while a drag hovers.
        ShelfDropHighlight {
            objectName: "shelfDropHighlight"
            anchors.fill: parent
            ink: ink
            radius: 16
            resting: true
            active: root.dropActive
        }
        DropArea {
            id: stripDrop
            anchors.fill: parent
            // A drag that starts here is a drag out, not a drop back in.
            enabled: !root.dragActive && !root.previewId
            onEntered: drag => {
                if (root.coordinator && (drag.hasUrls || drag.hasText) && (drag.supportedActions & Qt.CopyAction))
                    drag.accept(Qt.CopyAction)
                else
                    drag.accepted = false
            }
            onDropped: event => root.handleStripDrop(event)
        }
        ShelfPreview {
            anchors.fill: parent
            visible: root.previewId !== "" && root.previewItem !== null
            item: root.previewItem
            coordinator: root.coordinator
            actions: root.actions
            ink: ink
        }
    }

    Text {
        id: stripNotice
        objectName: "shelfStripNotice"
        x: stripArea.x
        y: stripArea.height + 2
        width: stripArea.width
        visible: text !== ""
        text: root.coordinator ? Strings.shelfNoticeText(root.coordinator.shelfNotice) : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: ink.inkSecondary
        font.family: ink.fontFamily
        renderType: ink.textRenderType
        font.pixelSize: ink.captionSize
    }

    ShelfMenu {
        id: menu
        objectName: "shelfMenu"
        ink: ink
        busyGuard: root.busyGuard
        onActionTriggered: (action, argument) => root.perform(action, argument)
    }
}
