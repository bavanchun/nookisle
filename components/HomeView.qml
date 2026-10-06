pragma ComponentBehavior: Bound

import QtQuick

// Home, under the header: the player, then the calendar and the camera
// mirror when their settings are on, side by side. The gaps are 15 px, or
// 10 px with the mirror shown, and the player takes the width left over.
// The mirror's camera runs only while the mirror is on, the island is open
// and settled, Home is shown and the tile itself is visible (CameraPanel).
// The badge's source picker opens over it; the header gear opens the
// settings window instead.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    property var settings: ({})
    property var lyricsSource: null
    property string appIcon: ""
    property bool pickerOpen: false
    // True once the island is open and its open spring has settled.
    property bool islandOpen: false
    property bool onHome: false
    // The header's camera toggle hides the mirror for the session.
    property bool mirrorHidden: false
    property bool cameraCoveredByOverlay: false
    // Tests replace the capture source; null keeps the real camera.
    property Component cameraSource: null
    signal lyricsRequested
    readonly property bool calendarShown: settings.showCalendar === true
    readonly property bool mirrorShown: settings.showMirror === true && !mirrorHidden
    readonly property real gap: mirrorShown ? 10 : 15
    readonly property real calendarWidth: mirrorShown ? 170 : 215
    readonly property real mirrorWidth: 120
    readonly property bool overlayOpen: pickerOpen
    readonly property bool interacting: player.interacting
    readonly property alias player: player
    // Returns whether a control took the focus.
    function focusControls() {
        return !overlayOpen && player.focusControls();
    }
    // Escape closes an open overlay first; it reports whether it did.
    function closeOverlay() {
        if (!overlayOpen)
            return false;
        pickerOpen = false;
        return true;
    }
    onVisibleChanged: if (!visible)
        closeOverlay()
    // The control that opened the picker. When the picker closes with the
    // keyboard inside it (Escape, or a choice), focus goes back there, or to
    // the player's controls if that control is gone, never to the empty
    // overlay.
    property Item pickerOpener: null
    function openPicker() {
        var focused = Window.activeFocusItem;
        pickerOpener = focused && isInside(focused, player) ? focused : null;
        pickerOpen = true;
    }
    function isInside(item, ancestor) {
        for (var node = item; node; node = node.parent)
            if (node === ancestor)
                return true;
        return false;
    }
    onPickerOpenChanged: if (!pickerOpen) {
        var focused = Window.activeFocusItem;
        var opener = pickerOpener;
        pickerOpener = null;
        if (visible && (focused === null || isInside(focused, sourceOverlay)))
            Qt.callLater(restoreAfterPicker, opener);
    }
    // A tick later, once the player row shows again and the opener with it.
    function restoreAfterPicker(opener) {
        if (!visible || pickerOpen)
            return;
        if (opener && opener.visible && opener.enabled && isInside(opener, player))
            opener.forceActiveFocus(Qt.TabFocusReason);
        else
            player.focusControls();
    }
    Row {
        id: row
        objectName: "homeRow"
        anchors.fill: parent
        spacing: root.gap
        visible: !root.overlayOpen
        PlayerPanel {
            id: player
            objectName: "playerPanel"
            width: row.width - (root.calendarShown ? root.calendarWidth + row.spacing : 0)
                - (root.mirrorShown ? root.mirrorWidth + row.spacing : 0)
            height: row.height
            tokens: root.tokens
            coordinator: root.coordinator
            settings: root.settings
            lyricsSource: root.lyricsSource
            appIcon: root.appIcon
            crowded: root.calendarShown && root.mirrorShown
            calendarItems: root.calendarShown && root.coordinator && root.coordinator.calendarSource
                && Array.isArray(root.coordinator.calendarSource.items) ? root.coordinator.calendarSource.items : []
            calendarOptions: root.settings
            onLyricsRequested: root.lyricsRequested()
            onSourcesRequested: root.openPicker()
        }
        CalendarPanel {
            objectName: "calendarPanel"
            visible: root.calendarShown
            width: root.calendarWidth
            height: row.height
            tokens: root.tokens
            source: root.coordinator && "calendarSource" in root.coordinator ? root.coordinator.calendarSource : null
            sources: root.settings.calendarSources || []
            options: root.settings
            compact: root.mirrorShown
            capTop: player.capTop
            onAddCalendarRequested: if (root.coordinator && typeof root.coordinator.openSettings === "function")
                root.coordinator.openSettings("calendar")
            // Each reveal starts from the current time on today; the panel's
            // one-shot day timer handles a midnight while Home stays open.
            onVisibleChanged: if (visible) refresh(new Date())
        }
        CameraPanel {
            id: mirror
            objectName: "cameraPanel"
            visible: root.mirrorShown
            width: root.mirrorWidth
            height: Math.min(row.height, root.mirrorWidth)
            // Top-aligned with the cover, as boring.notch's row is.
            y: player.artPadding
            enabled: root.mirrorShown
            islandOpen: root.islandOpen
            onHome: root.onHome
            // Its effective visibility: false under an overlay, on another
            // view or while the island is closed.
            tileVisible: visible && !root.cameraCoveredByOverlay
            shape: root.settings.mirrorShape === "circle" ? "circle" : "rectangle"
            reducedMotion: root.tokens.reducedMotion === true
            textRenderType: root.tokens.textRenderType
            sourceComponent: root.cameraSource ? root.cameraSource : mirror.liveComponent
        }
    }
    Loader {
        id: sourceOverlay
        objectName: "sourceOverlay"
        anchors.fill: parent
        active: root.pickerOpen
        sourceComponent: SourcePicker {
            overlay: true
            tokens: root.tokens
            coordinator: root.coordinator
            onDismissed: root.pickerOpen = false
        }
    }
}
