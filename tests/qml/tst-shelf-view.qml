import QtQuick
import QtTest
import "../../components"

// The shelf strip, tiles and menu against fakes: a coordinator that records
// actions, a tools/apps provider, and a busy guard that counts its pairs.
Item {
    id: host
    width: 700
    height: 200

    DesignTokens { id: realTokens; light: true }
    ShelfInk { id: mappedInk; tokens: realTokens }

    QtObject {
        id: facade
        property var shelfEntries: []
        property var fileSettings: ({ copyOnDrag: false, autoRemoveShelfItems: false })
        property var shelfMimes: ({})
        property var calls: []
        property var drops: []
        property var shares: []
        property int picks: 0
        property bool shareResult: true
        property int addResult: 1
        property string shelfNotice: ""
        property var previewCandidates: ({})
        property int pastes: 0
        function shelfPaste() { pastes++ }
        function shelfAction(name, ids, argument) {
            calls = calls.concat([{ name: name, ids: ids, argument: argument }])
            return true
        }
        function shelfAddDrop(urls, text) {
            drops = drops.concat([{ urls: urls, text: text }])
            shelfNotice = addResult > 0 ? "" : "shelf-full"
            return addResult
        }
        function shelfThumbnailCandidates(id) { return previewCandidates[id] || [] }
        function shelfIcons(id) { return [] }
        function requestShelfThumbnail(id) { return false }
        function shelfShareUris(uris) { shares = shares.concat([uris]); return shareResult }
        function shelfPickAndShare() { picks++; return true }
    }
    QtObject {
        id: fakeActions
        property var tools: ({ "zip": true, "magick": true })
        property var commands: []
        signal finished(string job, string status, int exitCode, string output)
        function fileSizeCommand(path) { return { argv: ["stat", "-c", "%s", "--", path] } }
        function execute(spec) { commands = commands.concat([spec]); return "size-job" }
        function openWithApps(mime) {
            return mime === "image/png" ? [{ id: "org.gnome.Loupe.desktop", dir: "/usr/share/applications" }] : []
        }
    }
    QtObject {
        id: guard
        property int begun: 0
        property int ended: 0
        readonly property int depth: begun - ended
        function beginBusy() { begun++ }
        function endBusy() { ended++ }
    }
    QtObject {
        id: tokens
        property color accent: "#a9c7ff"
        property bool reducedMotion: true
    }

    Component {
        id: viewComponent
        ShelfView {
            width: 700
            height: 120
            tokens: tokens
            coordinator: facade
            actions: fakeActions
            busyGuard: guard
        }
    }
    // The island's shape inside a taller window: the input region ends at
    // y = 150, while the window runs to 200.
    Item {
        id: islandBounds
        x: 40
        y: 0
        width: 620
        height: 150
    }
    Component {
        id: boundedViewComponent
        ShelfView {
            x: 40
            y: 30
            width: 620
            height: 110
            tokens: tokens
            coordinator: facade
            actions: fakeActions
            busyGuard: guard
            menuBounds: islandBounds
        }
    }
    SignalSpy { id: collapse; signalName: "collapseRequested" }

    TestCase {
        name: "ShelfView"
        when: windowShown
        property var view: null

        function test_ink_tracks_the_notch_palette() {
            compare(mappedInk.surface, realTokens.notchColor)
            compare(mappedInk.ink, realTokens.notchInk)
            compare(mappedInk.inkSecondary, realTokens.notchMutedInk)
            compare(mappedInk.inkFaint, realTokens.notchStroke)
            compare(mappedInk.accent, realTokens.notchAccent)
        }

        function items() {
            return [
                { id: "s1", kind: "file", uri: "file:///tmp/a.png", name: "a.png", addedAt: 1, temp: false },
                { id: "s2", kind: "file", uri: "file:///tmp/b.txt", name: "b.txt", addedAt: 1, temp: false },
                { id: "s3", kind: "link", url: "https://example.com/c", name: "example.com/c", addedAt: 1, temp: false },
                { id: "s4", kind: "text", text: "note d", name: "note d", addedAt: 1, temp: false }]
        }
        function init() {
            facade.shelfEntries = items()
            facade.shelfMimes = { s1: "image/png", s2: "text/plain" }
            facade.fileSettings = { copyOnDrag: false, autoRemoveShelfItems: false }
            facade.calls = []
            facade.drops = []
            facade.shares = []
            facade.picks = 0
            facade.shareResult = true
            facade.addResult = 1
            facade.shelfNotice = ""
            facade.previewCandidates = {}
            facade.pastes = 0
            fakeActions.commands = []
            fakeActions.tools = { "zip": true, "magick": true }
            guard.begun = 0
            guard.ended = 0
            view = createTemporaryObject(viewComponent, host)
            collapse.target = view
            collapse.clear()
            waitForRendering(view)
        }
        function tile(index) {
            var strip = findChild(view, "shelfStrip")
            strip.forceLayout()
            return strip.itemAtIndex(index)
        }
        function clickTile(index, modifiers) {
            mouseClick(tile(index), 52, 20, Qt.LeftButton, modifiers || Qt.NoModifier)
        }

        function test_empty_state_and_share_tile() {
            verify(!findChild(view, "shelfEmptyState").visible)
            verify(findChild(view, "shelfShareTile").width === findChild(view, "shelfShareTile").height, "the Share tile is square")
            facade.shelfEntries = []
            verify(findChild(view, "shelfEmptyState").visible)
            verify(!findChild(view, "shelfStrip").visible)
        }
        function test_keyboard_focus_enters_and_traverses_the_strip() {
            fakeActions.tools = { "zenity": true, "zip": true, "magick": true }
            verify(view.focusControls())
            var share = findChild(view, "shelfShareTile")
            verify(share.activeFocus)
            keyClick(Qt.Key_Return)
            compare(facade.picks, 1, "Return invokes Share from keyboard focus")
            keyClick(Qt.Key_Tab)
            verify(tile(0).activeFocus, "Tab moves to the first item")
            compare(view.selectedIds, ["s1"])
            keyClick(Qt.Key_Return)
            compare(facade.calls[0].name, "open")
            keyClick(Qt.Key_Tab)
            verify(tile(1).activeFocus, "Tab reaches the next tile")
            compare(view.selectedIds, ["s2"])
            fakeActions.tools = { "zip": true, "magick": true }
        }

        // In the island's body the Share tile and the drop zone fill the
        // band, the dashed frame shows at rest, and the tiles sit centred in
        // it; the notice keeps its line under the band.
        function test_drop_zone_fills_the_band_at_rest() {
            var tall = createTemporaryObject(viewComponent, host, { height: 154 })
            var band = tall.bandHeight
            verify(band > 105, "a taller body gives a taller band: " + band)
            compare(findChild(tall, "shelfShareTile").height, band)
            compare(findChild(tall, "shelfShareTile").width, band, "the Share tile stays square")
            var frame = findChild(tall, "shelfDropHighlight")
            verify(frame.visible, "the dashed frame shows with no drag")
            compare(frame.height, band)
            var strip = findChild(tall, "shelfStrip")
            fuzzyCompare(strip.y + strip.height / 2, band / 2, 0.5)
            verify(findChild(tall, "shelfStripNotice").y >= band, "the notice sits under the band")
            facade.shelfEntries = []
            verify(frame.visible, "and in the empty state")
            verify(findChild(tall, "shelfEmptyState").visible)
        }

        function test_tiles_are_105px_with_a_56px_thumbnail_and_two_line_names() {
            compare(tile(0).width, 105)
            var name = findChild(tile(0), "shelfTileName")
            compare(name.maximumLineCount, 2)
            compare(findChild(tile(0), "shelfThumbnail").width, 56)
        }

        function test_click_ctrl_shift_and_background_selection() {
            clickTile(1)
            compare(view.selectedIds, ["s2"])
            clickTile(3, Qt.ControlModifier)
            compare(view.selectedIds, ["s2", "s4"])
            clickTile(1, Qt.ControlModifier)
            compare(view.selectedIds, ["s4"], "Ctrl-click toggles one off")
            clickTile(0)
            clickTile(2, Qt.ShiftModifier)
            compare(view.selectedIds, ["s1", "s2", "s3"], "Shift-click selects the range from the anchor")
            verify(tile(1).selected)
            mouseClick(view, 690, 115)
            compare(view.selectedIds, [], "a background click clears")
            verify(!tile(1).selected)
        }

        function test_selection_follows_the_model() {
            clickTile(0)
            clickTile(1, Qt.ControlModifier)
            facade.shelfEntries = items().slice(1)
            compare(view.selectedIds, ["s2"], "removed items leave the selection")
        }

        function test_selected_tile_uses_accent_fill_and_stroke() {
            clickTile(0)
            var background = findChild(tile(0), "shelfTileBackground")
            compare(background.border.width, 2)
            verify(Qt.colorEqual(background.color, Qt.tint("#000000", Qt.rgba(0xa9 / 255, 0xc7 / 255, 1, 0.15))))
            verify(Qt.colorEqual(background.border.color, Qt.rgba(0xa9 / 255, 0xc7 / 255, 1, 0.8)))
            compare(findChild(tile(1), "shelfTileBackground").border.width, 0)
        }

        function test_keys() {
            clickTile(0)
            clickTile(1, Qt.ControlModifier)
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_C, Qt.ControlModifier)
            keyClick(Qt.Key_Delete)
            compare(facade.calls.map(function(call) { return call.name }), ["open", "copy", "remove"])
            compare(facade.calls[2].ids, ["s1", "s2"])
            keyClick(Qt.Key_Right)
            compare(view.selectedIds, ["s3"], "Right moves a single selection")
            keyClick(Qt.Key_Escape)
            compare(view.selectedIds, [])
            compare(collapse.count, 0, "the first Escape only clears")
            keyClick(Qt.Key_Escape)
            compare(collapse.count, 1, "Escape with nothing selected asks to collapse")
        }

        // Ctrl+V shelves the clipboard through the Service, with or without
        // a selection and on an empty shelf; a plain V does nothing.
        function test_ctrl_v_pastes_from_the_clipboard() {
            view.forceActiveFocus()
            keyClick(Qt.Key_V)
            compare(facade.pastes, 0)
            keyClick(Qt.Key_V, Qt.ControlModifier)
            compare(facade.pastes, 1)
            clickTile(0)
            keyClick(Qt.Key_V, Qt.ControlModifier)
            compare(facade.pastes, 2)
            compare(facade.calls, [], "and runs no item action")
            facade.shelfEntries = []
            view.forceActiveFocus()
            keyClick(Qt.Key_V, Qt.ControlModifier)
            compare(facade.pastes, 3, "the empty shelf takes a paste too")
        }

        function dropEvent(urls) {
            return {
                hasUrls: true, urls: urls, supportedActions: Qt.CopyAction | Qt.MoveAction,
                proposedAction: Qt.MoveAction, accepted: true, acceptedAction: Qt.IgnoreAction,
                accept: function(action) { this.accepted = true; this.acceptedAction = action }
            }
        }

        function test_share_drop_accepts_copy_only_after_share_starts() {
            var share = findChild(view, "shelfShareTile")
            var dropped = dropEvent(["file:///tmp/a.png"])
            verify(share.handleDrop(dropped))
            compare(facade.shares, [["file:///tmp/a.png"]])
            compare(dropped.acceptedAction, Qt.CopyAction, "a Move proposal must not be returned to the source")
            facade.shareResult = false
            var refused = dropEvent(["file:///tmp/b.txt"])
            verify(!share.handleDrop(refused))
            verify(!refused.accepted, "a failed share must not claim the source's data")
        }

        function test_strip_drop_rejects_failure_and_shows_notice() {
            facade.addResult = 0
            var refused = dropEvent(["file:///tmp/new.txt"])
            verify(!view.handleStripDrop(refused))
            verify(!refused.accepted)
            var notice = findChild(view, "shelfStripNotice")
            verify(notice.visible)
            verify(notice.text.indexOf("full") >= 0)
            facade.addResult = 1
            var accepted = dropEvent(["file:///tmp/new.txt"])
            verify(view.handleStripDrop(accepted))
            compare(accepted.acceptedAction, Qt.CopyAction)
            verify(!notice.visible)
        }

        function test_space_previews_in_strip_and_escape_closes_before_clearing() {
            clickTile(0)
            keyClick(Qt.Key_Space)
            var preview = findChild(view, "shelfPreview")
            verify(preview.visible)
            compare(preview.item.id, "s1")
            verify(findChild(preview, "shelfPreviewImage").width > 56)
            compare(facade.calls.length, 0, "preview never opens the default app")
            keyClick(Qt.Key_Space)
            verify(!preview.visible)
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_Escape)
            verify(!preview.visible)
            compare(view.selectedIds, ["s1"], "Escape closes preview before clearing selection")
            keyClick(Qt.Key_Return)
            compare(facade.calls.map(function(call) { return call.name }), ["open"])
        }

        function test_preview_text_link_and_file_details() {
            var examples = items()
            examples[3] = Object.assign({}, examples[3], { text: "one\ntwo\nthree\nfour\nfive" })
            facade.shelfEntries = examples
            clickTile(3)
            keyClick(Qt.Key_Space)
            var preview = findChild(view, "shelfPreview")
            var snippet = findChild(preview, "shelfPreviewText").text
            verify(snippet.indexOf("one\ntwo\nthree\nfour") >= 0)
            verify(snippet.indexOf("five") < 0, "the preview stops after the first lines")
            keyClick(Qt.Key_Space)
            clickTile(2)
            keyClick(Qt.Key_Space)
            compare(findChild(preview, "shelfPreviewHost").text, "example.com")
            compare(findChild(preview, "shelfPreviewUrl").text, "https://example.com/c")
            keyClick(Qt.Key_Space)
            facade.shelfMimes = { s1: "image/png", s2: "application/pdf" }
            clickTile(1)
            keyClick(Qt.Key_Space)
            compare(findChild(preview, "shelfPreviewFileName").text, "b.txt")
            compare(findChild(preview, "shelfPreviewFileType").text, "application/pdf")
            compare(fakeActions.commands[0].argv, ["stat", "-c", "%s", "--", "/tmp/b.txt"])
            fakeActions.finished("size-job", "ok", 0, "2048\n")
            compare(findChild(preview, "shelfPreviewFileSize").text, "2 KB")
        }

        function test_drag_out_mime_data_and_actions() {
            clickTile(0)
            clickTile(3, Qt.ControlModifier)
            compare(view.dragData("s1"), { "text/uri-list": "file:///tmp/a.png\r\n", "text/plain": "note d" },
                "a selected tile drags the whole selection")
            compare(view.dragData("s2"), { "text/uri-list": "file:///tmp/b.txt\r\n" }, "an unselected tile drags itself")
            compare(view.dragActions(), Qt.CopyAction | Qt.MoveAction)
            compare(tile(0).Drag.supportedActions, Qt.CopyAction | Qt.MoveAction)
            facade.fileSettings = { copyOnDrag: true, autoRemoveShelfItems: false }
            compare(tile(0).Drag.supportedActions, Qt.CopyAction, "copyOnDrag offers only Copy")
            view.finishDrag("s1", Qt.CopyAction)
            compare(facade.calls.length, 0, "without autoRemoveShelfItems nothing is removed")
            facade.fileSettings = { copyOnDrag: false, autoRemoveShelfItems: true }
            view.finishDrag("s1", Qt.IgnoreAction)
            compare(facade.calls.length, 0, "a refused drop removes nothing")
            view.finishDrag("s1", Qt.MoveAction)
            compare(facade.calls, [{ name: "remove", ids: ["s1", "s4"], argument: undefined }])
        }

        // Every entry of the longest menu sits inside the island's input
        // region (the menu scrolls to fit), opens from the keyboard, and its
        // last entry can be chosen by keyboard as well as by a click.
        function test_menu_fits_the_input_region_and_works_by_keyboard() {
            fakeActions.tools = { "zip": true, "magick": true, "rembg": true }
            var bounded = createTemporaryObject(boundedViewComponent, host)
            waitForRendering(bounded)
            var menu = findChild(bounded, "shelfMenu")
            var strip = findChild(bounded, "shelfStrip")
            strip.forceLayout()
            mouseClick(strip.itemAtIndex(0), 52, 20)
            compare(bounded.selectedIds, ["s1"])
            keyClick(Qt.Key_F10, Qt.ShiftModifier)
            tryVerify(function() { return menu.opened })
            verify(menu.count >= 12, "the image menu is the long one: " + menu.count)
            var frame = menu.background.mapToItem(null, 0, 0, menu.background.width, menu.background.height)
            var area = islandBounds.mapToItem(null, 0, 0, islandBounds.width, islandBounds.height)
            verify(frame.y >= area.y - 0.5 && frame.y + frame.height <= area.y + area.height + 0.5,
                "the menu stays inside the input region: " + JSON.stringify(frame))
            verify(frame.x >= area.x - 0.5 && frame.x + frame.width <= area.x + area.width + 0.5)
            verify(menu.contentItem.contentHeight > menu.contentItem.height, "a menu taller than the region scrolls")
            compare(menu.currentIndex, 0, "opened by keyboard, the first entry is current")
            var last = menu.itemAt(menu.count - 1)
            for (var step = 0; step < menu.count && !last.highlighted; ++step) keyClick(Qt.Key_Down)
            verify(last.highlighted, "Down reaches the last entry")
            var shown = last.mapToItem(null, 0, 0, last.width, last.height)
            tryVerify(function() {
                shown = last.mapToItem(null, 0, 0, last.width, last.height)
                return shown.y >= area.y - 0.5 && shown.y + shown.height <= area.y + area.height + 0.5
            }, 1000, "the highlighted last entry is scrolled into the input region")
            keyClick(Qt.Key_Return)
            tryVerify(function() { return !menu.visible })
            compare(facade.calls.map(function(call) { return call.name }), ["remove"], "the last entry, Remove, is chosen by keyboard")
            // The pointer reaches it too, inside the region.
            facade.calls = []
            facade.shelfEntries = items()
            strip.forceLayout()
            mouseClick(strip.itemAtIndex(0), 52, 20)
            keyClick(Qt.Key_Menu)
            tryVerify(function() { return menu.opened })
            menu.contentItem.positionViewAtEnd()
            last = menu.itemAt(menu.count - 1)
            waitForRendering(bounded)
            shown = last.mapToItem(null, 0, 0, last.width, last.height)
            verify(shown.y + shown.height <= area.y + area.height + 0.5, "scrolled to the end, Remove is inside the region")
            mouseClick(last, last.width / 2, last.height / 2)
            tryVerify(function() { return !menu.visible })
            compare(facade.calls.map(function(call) { return call.name }), ["remove"])
        }
        function test_menu_holds_the_busy_guard_while_open() {
            view.openMenu("s1", 20, 20)
            var menu = findChild(view, "shelfMenu")
            tryVerify(function() { return menu.opened })
            compare(guard.depth, 1)
            compare(view.selectedIds, ["s1"], "a menu on an unselected tile selects it")
            menu.close()
            tryVerify(function() { return !menu.visible })
            compare(guard.begun, 1)
            compare(guard.ended, 1)
            view.openMenu("s1", 20, 20)
            tryVerify(function() { return menu.opened })
            menu.close()
            tryVerify(function() { return !menu.visible })
            compare([guard.begun, guard.ended], [2, 2], "every open is paired with one close")
        }

        function test_menu_destroyed_while_open_releases_the_guard() {
            view.openMenu("s2", 20, 20)
            tryVerify(function() { return findChild(view, "shelfMenu").opened })
            compare(guard.depth, 1)
            view.destroy()
            view = null
            tryVerify(function() { return guard.depth === 0 })
        }

        function test_menu_items_per_item_type() {
            function actionsOf(id) {
                return view.menuEntriesFor([id]).filter(function(entry) { return !entry.separator })
                    .map(function(entry) { return entry.action })
            }
            compare(actionsOf("s1"), ["open", "openWith", "showInFiles", "copy", "copyPath", "compress", "rename",
                "convert", "pdf", "share", "remove"])
            compare(actionsOf("s2"), ["open", "showInFiles", "copy", "copyPath", "compress", "rename", "share", "remove"])
            compare(actionsOf("s3"), ["open", "copy", "remove"])
            compare(actionsOf("s4"), ["copy", "remove"])
            view.openMenu("s1", 20, 20)
            var menu = findChild(view, "shelfMenu")
            tryVerify(function() { return menu.opened })
            var convert = null
            for (var i = 0; i < menu.count; ++i) {
                var entry = menu.itemAt(i)
                if (entry && entry.subMenu && entry.subMenu.title === "Convert Image") convert = entry.subMenu
            }
            verify(convert !== null, "Convert Image is a submenu")
            compare(convert.count, 3)
            var compress = findChild(menu.contentItem, "shelfMenu_compress")
            verify(compress !== null)
            compress.triggered()
            compare(facade.calls[facade.calls.length - 1], { name: "compress", ids: ["s1"], argument: undefined })
            menu.close()
        }

        function test_rename_editor_holds_the_guard_and_commits() {
            clickTile(1)
            view.perform("rename")
            var editor = findChild(tile(1), "shelfRenameEditor")
            tryVerify(function() { return editor.visible && editor.activeFocus })
            compare(guard.depth, 1)
            compare(editor.selectedText, "b", "the name without its extension is preselected")
            keyClick(Qt.Key_Z)
            keyClick(Qt.Key_Return)
            compare(facade.calls, [{ name: "rename", ids: ["s2"], argument: "z.txt" }], "Return renames and does not also open")
            compare(guard.depth, 0)
            verify(!editor.visible)
            view.perform("rename")
            tryVerify(function() { return editor.activeFocus })
            keyClick(Qt.Key_Escape)
            compare(guard.depth, 0)
            compare(facade.calls.length, 1, "Escape cancels without renaming")
            compare(collapse.count, 0, "Escape in the editor does not collapse")
        }
    }
}
