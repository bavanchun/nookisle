pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import "../qml/HeaderSlots.js" as HeaderSlots

// The open notch's header, after boring.notch's BoringHeader: icon tabs in
// a neutral 26 px capsule on the left (the shelf's count as a small badge
// once it holds something), a span as wide as the closed notch's body in the
// centre (empty over a camera cutout, else the activity chips), and the
// camera, recording Stop, Timers, settings and battery slots on the right. The capsule slides to the
// selected tab by animating its x and width.
Item {
    id: root
    required property var tokens
    // The tabs in order, and the one shown. `view` may name a sub-view of
    // home ("lyrics"); home stays the selected tab, and a back chevron
    // replaces the tabs until the sub-view closes.
    property var views: ["home", "shelf"]
    property string view: "home"
    property int shelfCount: 0
    property bool alwaysShowTabs: true
    property real centreWidth: 0
    // What the centre span shows, when nothing sits under it (no camera
    // cutout): the activity chips. Null keeps it empty.
    property Component centreComponent: null
    // The right-hand slots, each hidden while its feature is off. The
    // camera toggle shows or hides the mirror for the session; the battery
    // slot shows a gauge while a battery is present.
    property bool cameraVisible: false
    property bool cameraOn: true
    property bool settingsVisible: true
    // The Timers sub-view's button, while timers are on: a stopwatch, with
    // the running timer's time left beside it, and a wash while the Timers
    // view is open.
    property bool timersVisible: false
    // The running timer's name and time left ("13m"), or "" with none.
    property string timerName: ""
    property string timerRemaining: ""
    readonly property bool timersOpen: view === "timers"
    readonly property int timersIconSize: 18
    // The right-hand row never crosses into the centre span. Its entries,
    // most important first, go through HeaderSlots.plan: at full width if
    // they fit; else in compact form (Timers without its time left, then
    // the battery without its percentage); else with the least important
    // folded into the overflow menu at the row's inner end. Every entry
    // stays reachable by pointer and keyboard, under the same name.
    readonly property var slotEntries: {
        var list = [];
        if (recordingStopVisible)
            list.push({ key: "recording", width: tokens.target });
        if (batteryVisible)
            list.push({ key: "battery", width: (batteryPercent ? gauge.fullWidth : gauge.compactWidth) + tokens.small * 2,
                compact: gauge.compactWidth + tokens.small * 2 });
        if (timersVisible) {
            var bare = Math.max(tokens.target, timersIconSize + 2 * tokens.gap);
            list.push({ key: "timers", compact: bare, width: timerRemaining === "" ? bare
                : Math.max(tokens.target, timersIconSize + tokens.small + Math.ceil(timersLabelMetrics.advanceWidth) + 2 * tokens.gap) });
        }
        if (cameraVisible)
            list.push({ key: "camera", width: tokens.target });
        if (settingsVisible)
            list.push({ key: "settings", width: tokens.target });
        return list;
    }
    readonly property var slotPlan: HeaderSlots.plan(slotEntries, sideWidth, tokens.small, tokens.target)
    function inRow(key) {
        return slotPlan.inline.indexOf(key) >= 0;
    }
    function compactSlot(key) {
        return slotPlan.compact[key] === true;
    }
    // An entry's name, the same in the row and in the overflow menu.
    function slotLabel(key) {
        switch (key) {
        case "recording":
            return "Stop the screen recording";
        case "battery":
            return gauge.Accessible.name;
        case "timers":
            return timersButton.accessibleLabel;
        case "camera":
            return cameraOn ? "Hide the mirror" : "Show the mirror";
        case "settings":
            return "Nookisle settings";
        }
        return "";
    }
    function activateSlot(key) {
        switch (key) {
        case "recording":
            stopRecordingRequested();
            break;
        case "battery":
            batteryRequested();
            break;
        case "timers":
            timersRequested();
            break;
        case "camera":
            cameraToggled();
            break;
        case "settings":
            settingsRequested();
            break;
        }
    }
    readonly property alias overflowMenu: overflowMenu
    // The pointer is over the open overflow menu. The menu is a popup, drawn
    // above the island rather than inside it, so the island's own hover does
    // not see it; the island counts this as the pointer being inside.
    // The entries take hover before the frame under them, so both watch.
    readonly property bool overflowHovered: overflowMenu.opened && (menuHover.hovered || entriesHover.hovered)
    // The menu belongs to the view it opened over: a tab change closes it.
    onViewChanged: overflowMenu.close()
    // The menu's entries share the widest one's width, measured from the
    // font as IslandButton lays its label out.
    FontMetrics {
        id: menuFont
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.bodySize
    }
    readonly property real overflowEntryWidth: {
        var widest = tokens.target;
        for (var i = 0; i < slotPlan.folded.length; ++i)
            widest = Math.max(widest, Math.ceil(menuFont.advanceWidth(slotLabel(slotPlan.folded[i]))) + tokens.inset * 2);
        return widest;
    }
    // Stop for a running screen recording, when no activity chip in the
    // centre can offer it (a camera cutout keeps the centre empty).
    property bool recordingStopVisible: false
    property bool batteryVisible: false
    readonly property alias cameraSlot: cameraSlot
    readonly property alias batterySlot: batterySlot
    // The battery gauge in its slot, and whether it shows the percentage.
    property var batteryReading: ({ present: false, onBattery: false, level: 0, state: "Unknown", powerSaver: false })
    property bool batteryPercent: true
    property bool batteryStatusIcons: true
    // The open-notch HUD: while `hudVisible`, a capsule with the level
    // takes the right-hand slots' place for the readout's short life.
    property var hudModel: null
    property bool hudVisible: false
    property bool hudPercent: true
    property bool hudAccent: false
    property bool hudGradient: false
    property bool hudGlow: false
    signal batteryRequested
    signal hudLevelRequested(string kind, real value)
    readonly property bool subView: views.indexOf(view) < 0
    readonly property string selectedTab: subView ? views[0] : view
    readonly property bool tabsVisible: views.length > 1 && !subView && (alwaysShowTabs || shelfCount > 0)
    readonly property real sideWidth: Math.max(0, (width - centreWidth) / 2)
    signal tabRequested(string view)
    signal backRequested
    signal settingsRequested
    signal timersRequested
    signal stopRecordingRequested
    signal cameraToggled
    readonly property alias capsule: capsule
    // The tab's name, which is also its accessible name.
    function tabText(name) {
        return name === "shelf" ? "Shelf" : "Home";
    }
    function badgeText(name) {
        return name === "shelf" && shelfCount > 0 ? String(shelfCount) : "";
    }
    readonly property int tabIconSize: 16
    readonly property int tabPadding: 15
    readonly property int capsuleHeight: 26
    // Tab geometry straight from the icon size and the font, so the capsule
    // is right from the first frame rather than waiting for the Repeater's
    // items.
    function tabWidth(name) {
        var badge = badgeText(name);
        return tabIconSize + 2 * tabPadding + (badge ? Math.ceil(tabFont.advanceWidth(badge)) + tokens.small : 0);
    }
    function tabX(name) {
        var x = 0;
        for (var i = 0; i < views.length && views[i] !== name; ++i)
            x += tabWidth(views[i]) + tokens.small;
        return x;
    }
    // The keyboard-focus target in header coordinates: both tab capsules, or
    // the back chevron in a sub-view. The surface sizes its ring from it.
    readonly property rect tabsRect: {
        if (subView)
            return Qt.rect(left.x + backButton.x, left.y + backButton.y, backButton.width, backButton.height);
        var last = views.length > 0 ? views[views.length - 1] : "";
        return Qt.rect(left.x + tabRow.x, left.y + tabRow.y, last ? tabX(last) + tabWidth(last) : 0, tabRow.height);
    }
    FontMetrics {
        id: tabFont
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
        font.weight: Font.DemiBold
    }
    Item {
        id: left
        objectName: "headerTabs"
        width: root.sideWidth
        height: parent.height
        clip: true
        Rectangle {
            id: capsule
            objectName: "tabCapsule"
            visible: root.tabsVisible
            x: tabRow.x + root.tabX(root.selectedTab)
            y: tabRow.y
            width: root.tabWidth(root.selectedTab)
            height: tabRow.height
            radius: height / 2
            // A neutral wash of the ink, as boring.notch's system fill: the
            // artwork colour stays off the header.
            color: Qt.rgba(root.tokens.text.r, root.tokens.text.g, root.tokens.text.b, 0.14)
            Behavior on x {
                enabled: root.tokens.tabDuration > 0
                NumberAnimation { duration: root.tokens.tabDuration; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                enabled: root.tokens.tabDuration > 0
                NumberAnimation { duration: root.tokens.tabDuration; easing.type: Easing.OutCubic }
            }
        }
        Row {
            id: tabRow
            visible: root.tabsVisible
            y: Math.round((parent.height - height) / 2)
            height: root.capsuleHeight
            spacing: root.tokens.small
            Repeater {
                id: tabRepeater
                model: root.views
                Controls.AbstractButton {
                    id: tab
                    required property string modelData
                    readonly property string name: modelData
                    readonly property bool selected: root.selectedTab === name
                    objectName: name === "home" ? "viewHomeButton" : "viewShelfButton"
                    text: root.tabText(name)
                    width: root.tabWidth(name)
                    height: tabRow.height
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    Accessible.role: Accessible.PageTab
                    Accessible.name: tab.badge ? text + ", " + tab.badge + (tab.badge === "1" ? " item" : " items") : text
                    readonly property string badge: root.badgeText(name)
                    Accessible.checked: selected
                    onClicked: root.tabRequested(name)
                    background: Rectangle {
                        radius: height / 2
                        color: !tab.selected && (tab.hovered || tab.down) ? root.tokens.hover : "transparent"
                        border.width: tab.visualFocus ? root.tokens.focusWidth : 0
                        border.color: tab.selected ? root.tokens.text : root.tokens.accent
                    }
                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: root.tokens.small
                            IslandIcon {
                                objectName: "tabIcon"
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.tabIconSize
                                height: root.tabIconSize
                                name: tab.name === "shelf" ? "tray" : "home"
                                ink: tab.selected ? root.tokens.text : root.tokens.secondary
                            }
                            Text {
                                objectName: "tabBadge"
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tab.badge !== ""
                                text: tab.badge
                                color: tab.selected ? root.tokens.text : root.tokens.secondary
                                font: tabFont.font
                                renderType: root.tokens.textRenderType
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }
            }
        }
        IslandButton {
            id: backButton
            objectName: "lyricsBackButton"
            visible: root.subView
            tokens: root.tokens
            iconName: "back"
            accessibleLabel: "Back"
            height: parent.height
            onActivated: root.backRequested()
        }
    }
    // Nothing sits over a camera cutout; otherwise the centre holds what
    // centreComponent draws.
    Item {
        objectName: "headerCentre"
        x: root.sideWidth
        width: root.centreWidth
        height: parent.height
        Loader {
            anchors.fill: parent
            active: !!root.centreComponent && !root.subView
            sourceComponent: root.centreComponent
        }
    }
    TextMetrics {
        id: timersLabelMetrics
        text: root.timerRemaining
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
        font.weight: Font.Medium
    }
    Row {
        id: headerSlots
        objectName: "headerSlots"
        x: root.width - width
        height: parent.height
        visible: !root.hudVisible
        layoutDirection: Qt.RightToLeft
        spacing: root.tokens.small
        Item {
            id: batterySlot
            objectName: "headerBatterySlot"
            visible: root.batteryVisible && root.inRow("battery")
            width: gauge.implicitWidth + root.tokens.small * 2
            height: parent.height
            BatteryGauge {
                id: gauge
                objectName: "batteryGauge"
                anchors.centerIn: parent
                reading: root.batteryReading
                showPercent: root.batteryPercent && !root.compactSlot("battery")
                showStatusIcon: root.batteryStatusIcons
                fontFamily: root.tokens.fontFamily
                fontSize: root.tokens.captionSize
                textRenderType: root.tokens.textRenderType
            }
            // A tap opens the battery popover.
            TapHandler {
                onTapped: root.batteryRequested()
            }
            // A button to the keyboard as well: Tab reaches it, and Return,
            // Enter or Space opens the battery popover.
            activeFocusOnTab: true
            Keys.onReturnPressed: event => { event.accepted = true; root.batteryRequested(); }
            Keys.onEnterPressed: event => { event.accepted = true; root.batteryRequested(); }
            Keys.onSpacePressed: event => { event.accepted = true; root.batteryRequested(); }
            Rectangle {
                objectName: "headerBatteryFocus"
                anchors.fill: parent
                anchors.topMargin: 3
                anchors.bottomMargin: 3
                radius: height / 2
                color: "transparent"
                visible: batterySlot.activeFocus
                border.width: root.tokens.focusWidth
                border.color: root.tokens.accent
            }
            Accessible.role: Accessible.Button
            Accessible.name: gauge.Accessible.name
            Accessible.onPressAction: root.batteryRequested()
        }
        IslandButton {
            objectName: "headerRecordingStop"
            visible: root.recordingStopVisible && root.inRow("recording")
            tokens: root.tokens
            iconName: "record"
            iconColor: root.tokens.recordingInk
            accessibleLabel: "Stop the screen recording"
            height: parent.height
            onActivated: root.stopRecordingRequested()
        }
        IslandButton {
            id: timersButton
            objectName: "headerTimersButton"
            visible: root.timersVisible && root.inRow("timers")
            tokens: root.tokens
            accessibleLabel: root.timersOpen ? "Close timers"
                : root.timerRemaining !== "" ? "Timers, " + root.timerName + ", " + root.timerRemaining + " left" : "Timers"
            height: parent.height
            width: Math.max(root.tokens.target, timersRow.implicitWidth + 2 * root.tokens.gap)
            onActivated: root.timersRequested()
            contentItem: Item {
                Rectangle {
                    objectName: "headerTimersOpen"
                    anchors.fill: parent
                    visible: root.timersOpen
                    radius: height / 2
                    color: Qt.rgba(root.tokens.text.r, root.tokens.text.g, root.tokens.text.b, 0.14)
                }
                Row {
                    id: timersRow
                    anchors.centerIn: parent
                    spacing: root.tokens.small
                    IslandIcon {
                        objectName: "headerTimersIcon"
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.timersIconSize
                        height: root.timersIconSize
                        name: "timer"
                        ink: root.tokens.text
                    }
                    Text {
                        objectName: "headerTimersLabel"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== "" && !root.compactSlot("timers")
                        text: root.timerRemaining
                        color: root.tokens.text
                        font.family: root.tokens.fontFamily
                        renderType: root.tokens.textRenderType
                        font.pixelSize: root.tokens.captionSize
                        font.weight: Font.Medium
                        font.features: root.tokens.numberFeatures
                        textFormat: Text.PlainText
                    }
                }
            }
        }
        IslandButton {
            objectName: "headerSettingsButton"
            visible: root.settingsVisible && root.inRow("settings")
            tokens: root.tokens
            iconName: "settings"
            accessibleLabel: "Nookisle settings"
            height: parent.height
            onActivated: root.settingsRequested()
        }
        Item {
            id: cameraSlot
            objectName: "headerCameraSlot"
            visible: root.cameraVisible && root.inRow("camera")
            width: root.tokens.target
            height: parent.height
            IslandButton {
                objectName: "headerCameraButton"
                anchors.fill: parent
                tokens: root.tokens
                iconName: root.cameraOn ? "camera" : "camera-off"
                iconColor: root.cameraOn ? root.tokens.text : root.tokens.secondary
                accessibleLabel: root.cameraOn ? "Hide the mirror" : "Show the mirror"
                onActivated: root.cameraToggled()
            }
        }
        // The overflow: at the row's inner end, a menu of the entries the
        // row has no room for, each under its own name. Keyboard: Return
        // opens it with the first entry focused, Tab moves, Escape closes.
        IslandButton {
            id: overflowButton
            objectName: "headerOverflowButton"
            visible: root.slotPlan.overflow
            tokens: root.tokens
            iconName: "more"
            accessibleLabel: "More: " + root.slotPlan.folded.map(root.slotLabel).join(", ")
            height: parent.height
            onActivated: overflowMenu.opened ? overflowMenu.close() : overflowMenu.open()
            // Gone from the row (the plan changed, or the readout took the
            // row's place), it takes its menu with it.
            onVisibleChanged: if (!visible) overflowMenu.close()
            Keys.onReturnPressed: event => { event.accepted = true; activated(); }
            Keys.onEnterPressed: event => { event.accepted = true; activated(); }
            Controls.Popup {
                id: overflowMenu
                objectName: "headerOverflowMenu"
                x: overflowButton.width - width
                y: overflowButton.height + root.tokens.small
                padding: root.tokens.small
                focus: true
                closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
                onOpened: {
                    var first = overflowColumn.children[0];
                    if (first)
                        first.forceActiveFocus(Qt.TabFocusReason);
                }
                onClosed: if (overflowButton.visible) overflowButton.forceActiveFocus(Qt.TabFocusReason)
                background: Rectangle {
                    color: root.tokens.notchColor
                    radius: root.tokens.gap
                    border.width: 1
                    border.color: root.tokens.notchStroke
                    HoverHandler {
                        id: menuHover
                        objectName: "headerOverflowHover"
                    }
                }
                contentItem: Column {
                    id: overflowColumn
                    spacing: 2
                    HoverHandler {
                        id: entriesHover
                    }
                    Repeater {
                        model: root.slotPlan.folded
                        IslandButton {
                            required property string modelData
                            objectName: "headerOverflow-" + modelData
                            tokens: root.tokens
                            text: root.slotLabel(modelData)
                            accessibleLabel: text
                            width: root.overflowEntryWidth
                            onActivated: {
                                overflowMenu.close();
                                root.activateSlot(modelData);
                            }
                            Keys.onReturnPressed: event => { event.accepted = true; activated(); }
                            Keys.onEnterPressed: event => { event.accepted = true; activated(); }
                        }
                    }
                }
            }
        }
    }
    HudCapsule {
        objectName: "headerHud"
        x: root.width - width
        maximumWidth: root.sideWidth
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hudVisible && active
        tokens: root.tokens
        model: root.hudModel
        showPercent: root.hudPercent
        accent: root.hudAccent
        gradientEnabled: root.hudGradient
        glowEnabled: root.hudGlow
        onSetLevel: (kind, value) => root.hudLevelRequested(kind, value)
    }
}
