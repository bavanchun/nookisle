pragma ComponentBehavior: Bound

import QtQuick
import "qml/Strings.js" as Strings
import "qml/CatchZone.js" as CatchZone
import "components"

Item {
    id: root
    property var bar: null
    property string moduleName: "io.github.bavanchun.nookisle"
    property var settings: ({})
    readonly property var host: bar ? bar.shell : null
    readonly property var coordinator: host ? host.serviceFor(moduleName) : null
    readonly property var endpoint: coordinator && coordinator.uiAllowed ? coordinator.selectedEndpoint : null
    readonly property bool vertical: bar && bar.vertical === true
    readonly property real barSize: bar ? bar.barSize : design.target
    readonly property bool playing: endpoint && endpoint.status === "Playing"
    readonly property var capabilities: endpoint ? endpoint.capabilities || ({}) : ({})
    readonly property string title: endpoint ? String(endpoint.presentation.title || endpoint.presentation.hostApp || Strings.player)
        : coordinator && coordinator.pinUnavailable ? "Source lost" : "Nookisle"
    // In island mode the live bar centre holds only this widget, so it becomes
    // an invisible spacer that reserves the closed notch body's width and
    // publishes no geometry (plan Decisions, "Bar widget fate"); the notch's
    // top flares overhang it on each side. A non-top or vertical bar
    // keeps the inline widget unchanged, because there is no notch to reserve
    // space for there.
    readonly property bool islandMode: coordinator && coordinator.island === true
        && bar && bar.position === "top" && !vertical
    visible: coordinator && coordinator.panelAllowed === true && coordinator.autoShow !== false
    implicitWidth: vertical ? barSize : islandMode ? design.liveWidth - 2 * design.flareClosed : Math.min(design.compactWidth,
        Math.max(design.target * 3 + design.inset, Math.ceil(titleMetrics.advanceWidth) + design.gap * 3 + 20 + barSize))
    implicitHeight: vertical ? barSize * 2 : barSize
    readonly property bool interactionActive: !islandMode
        && (details.hovered || play.hovered || details.down || play.down || (coordinator && coordinator.viewVisible))
    Accessible.name: islandMode ? "Nookisle" : ""
    // Written only on this widget's own transitions, the same contract the
    // first-party clock and weather panels follow for the shared flag
    // (host centre-hover peek contract).
    // On multiple monitors, every bar shares the one Service-level
    // `islandPointerActive`, so without a screen check every bar would
    // suppress its own centre peek whenever the island is hovered on any
    // screen. An unset `islandScreenName` (the coordinator has not resolved
    // one yet) stays permissive rather than never suppressing.
    readonly property string ownScreenName: root.Window.window && root.Window.window.screen ? root.Window.window.screen.name : ""
    readonly property bool suppressCenterPeek: islandMode && visible
        && coordinator && coordinator.islandPointerActive === true
        && (!coordinator.islandScreenName || coordinator.islandScreenName === ownScreenName)
    property bool centerPeekSuppressionSent: false
    onSuppressCenterPeekChanged: {
        if (bar && typeof bar.setCenterHoverRevealSuppressed === "function") {
            bar.setCenterHoverRevealSuppressed(suppressCenterPeek);
            centerPeekSuppressionSent = suppressCenterPeek;
        }
    }
    // The empty bar centre around this spacer, for the island's drag catch
    // zone. The host lays out a centre holder filling the bar and one module
    // row at each edge; this finds them among its ancestors, measures the
    // gap, and publishes it once the rows settle. A row or bar that moves or
    // resizes withdraws the span at once (catch zone off, so the zone never
    // overlaps a row that grew), and the new span is published only after the
    // debounce, so an animating row changes the input region twice at most.
    // Without that layout, or outside island mode, it publishes -1 and the
    // catch zone stays off.
    property var barRows: null
    // The last span sent, so a repeated value (an animation's many width
    // changes, all withdrawing) is sent once.
    property real publishedSpan: NaN
    function sendSpan(span) {
        if (!coordinator || typeof coordinator.noteBarCentreSpan !== "function" || span === publishedSpan) return;
        publishedSpan = span;
        coordinator.noteBarCentreSpan(ownScreenName, span);
    }
    property var rowHolder: null
    function locateRows() {
        for (var holder = root.parent; holder && holder.parent; holder = holder.parent) {
            var bar = holder.parent;
            var siblings = [];
            for (var i = 0; i < bar.children.length; ++i)
                if (bar.children[i] !== holder && bar.children[i].visible)
                    siblings.push(bar.children[i]);
            var rows = CatchZone.classifyRows(bar.width, holder.width, siblings);
            if (rows) {
                rowHolder = holder;
                barRows = rows;
                return;
            }
        }
        rowHolder = null;
        barRows = null;
    }
    // Whether this island is away from the bar's middle, sent on change, so
    // the welcome can say how to make it the centre anchor.
    property bool publishedOffCentre: false
    function sendPlacement(offCentre) {
        if (!coordinator || typeof coordinator.noteBarPlacement !== "function" || offCentre === publishedOffCentre) return;
        publishedOffCentre = offCentre;
        coordinator.noteBarPlacement(ownScreenName, offCentre);
    }
    function publishSpan() {
        if (!islandMode || !barRows || !rowHolder) {
            sendSpan(-1);
            sendPlacement(false);
            return;
        }
        var bar = rowHolder.parent;
        var centre = root.mapToItem(bar, root.width / 2, 0).x;
        sendPlacement(CatchZone.offCentre(centre, bar.width));
        sendSpan(CatchZone.freeSpan(centre, {
            left: { x: barRows.left.x, width: barRows.left.width },
            right: { x: barRows.right.x, width: barRows.right.width } }));
    }
    function measureSoon() { spanSettle.restart(); }
    function rowsChanged() {
        sendSpan(-1);
        measureSoon();
    }
    Timer {
        id: spanSettle
        interval: 250
        onTriggered: {
            root.locateRows();
            root.publishSpan();
        }
    }
    Connections {
        target: root.barRows ? root.barRows.left : null
        function onWidthChanged() { root.rowsChanged(); }
        function onXChanged() { root.rowsChanged(); }
        function onVisibleChanged() { root.rowsChanged(); }
    }
    Connections {
        target: root.barRows ? root.barRows.right : null
        function onWidthChanged() { root.rowsChanged(); }
        function onXChanged() { root.rowsChanged(); }
        function onVisibleChanged() { root.rowsChanged(); }
    }
    Connections {
        target: root.rowHolder ? root.rowHolder.parent : null
        function onWidthChanged() { root.rowsChanged(); }
    }
    // A new coordinator or screen has none of what was sent before.
    onCoordinatorChanged: {
        publishedSpan = NaN;
        measureSoon();
    }
    onOwnScreenNameChanged: {
        publishedSpan = NaN;
        measureSoon();
    }
    onParentChanged: measureSoon()
    TextMetrics {
        id: titleMetrics
        font.family: design.fontFamily
        font.pixelSize: design.bodySize
        text: root.title
    }
    Rectangle {
        id: groupSurface
        objectName: "barGroupSurface"
        anchors.fill: parent
        visible: !root.islandMode
        radius: root.vertical ? root.barSize / 2 : height / 2
        color: design.hover
        opacity: root.interactionActive ? 1 : 0
        Behavior on opacity {
            enabled: root.visible && !design.reducedMotion
            NumberAnimation { id: hoverFade; duration: design.feedbackDuration; easing.type: Easing.OutCubic }
        }
    }
    Connections {
        target: design
        function onReducedMotionChanged() { if (design.reducedMotion) hoverFade.complete(); }
    }
    property var registeredBar: null
    function registerButtons() {
        if (registeredBar && registeredBar.unregisterClickTarget) {
            registeredBar.unregisterClickTarget(details);
            registeredBar.unregisterClickTarget(play);
        }
        registeredBar = bar;
        if (!islandMode && registeredBar && registeredBar.registerClickTarget) {
            registeredBar.registerClickTarget(details);
            registeredBar.registerClickTarget(play);
        }
    }
    onBarChanged: registerButtons()
    onIslandModeChanged: {
        registerButtons();
        measureSoon();
    }
    Component.onCompleted: {
        registerButtons();
        measureSoon();
    }
    Component.onDestruction: {
        if (coordinator && typeof coordinator.noteBarCentreSpan === "function")
            coordinator.noteBarCentreSpan(ownScreenName, -1);
        hideTooltips();
        if (registeredBar && registeredBar.unregisterClickTarget) {
            registeredBar.unregisterClickTarget(details);
            registeredBar.unregisterClickTarget(play);
        }
        if (centerPeekSuppressionSent && bar && typeof bar.setCenterHoverRevealSuppressed === "function")
            bar.setCenterHoverRevealSuppressed(false);
    }

    DesignTokens {
        id: design
        theme: ({text: root.bar && root.bar.barForeground !== undefined ? root.bar.barForeground : "",
            accent: root.bar && root.bar.barForeground !== undefined ? root.bar.barForeground : "",
            fontFamily: root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace",
            bodySize: root.coordinator && root.coordinator.bodyFontSize ? root.coordinator.bodyFontSize : 12})
        light: root.coordinator ? root.coordinator.lightTheme === true : false
        highContrast: root.coordinator ? root.coordinator.highContrast === true : false
        reducedMotion: root.coordinator ? root.coordinator.reducedMotion === true : false
    }
    FontMetrics {
        id: tooltipMetrics
        font.family: design.fontFamily
        font.pixelSize: design.bodySize
    }
    readonly property real tooltipTextWidth: Math.min(480, root.Window.window && root.Window.window.screen
        ? Math.max(design.target, root.Window.window.screen.width - design.inset * 2) : 352)
    function boundedTooltip(text) {
        // Metric methods do not make font changes a binding dependency.
        if (tooltipMetrics.font.pixelSize <= 0) return "";
        return tooltipMetrics.elidedText(String(text || ""), Qt.ElideRight, tooltipTextWidth);
    }
    function updateTooltip(button, text) {
        if (!bar) return;
        if (button.tooltipHovered && typeof bar.showTooltip === "function")
            bar.showTooltip(button, text);
        else if (typeof bar.hideTooltip === "function")
            bar.hideTooltip(button);
    }
    function hideTooltips() {
        if (bar && typeof bar.hideTooltip === "function") {
            bar.hideTooltip(details);
            bar.hideTooltip(play);
        }
    }
    onVisibleChanged: if (!visible) {
        hideTooltips();
        hoverFade.complete();
    }
    Connections {
        target: root.coordinator
        function onViewVisibleChanged() { if (root.coordinator.viewVisible) root.hideTooltips(); }
    }
    function openDetails() {
        hideTooltips();
        if (!host || !coordinator || !coordinator.panelAllowed) return;
        if (coordinator.viewVisible && typeof host.hide === "function") {
            host.hide(moduleName);
            return;
        }
        var screen = root.Window.window ? root.Window.window.screen : null;
        host.summon(moduleName, JSON.stringify({expanded: true, screenName: screen ? screen.name : "",
            anchorLeftX: root.mapToItem(null, 0, 0).x,
            anchorCenterX: root.mapToItem(null, root.width / 2, 0).x}));
    }
    IslandButton {
        id: details
        objectName: "barDetailsButton"
        tokens: design
        tooltipsEnabled: !root.bar
        visible: !root.islandMode
        readonly property bool tooltipHovered: !root.islandMode && hovered && root.visible && !(root.coordinator && root.coordinator.viewVisible)
        readonly property string nativeTooltipText: root.boundedTooltip(root.title) + "\n" + root.boundedTooltip(root.coordinator ? root.coordinator.selectedLabel : "Nookisle")
        onTooltipHoveredChanged: root.updateTooltip(details, nativeTooltipText)
        onNativeTooltipTextChanged: if (tooltipHovered) root.updateTooltip(details, nativeTooltipText)
        width: root.vertical ? root.width : root.width - root.barSize
        height: root.barSize
        accessibleLabel: root.title + (root.coordinator ? ". " + root.coordinator.selectedLabel : "") + ". Open music controls"
        background: Rectangle {
            color: "transparent"
            radius: height / 2
            border.width: details.visualFocus ? design.focusWidth : 0
            border.color: design.text
        }
        onActivated: root.openDetails()
        function triggerPress(button) { if (button === Qt.LeftButton) trigger(); }
        contentItem: Item {
            IslandIcon {
                id: musicIcon
                anchors.left: parent.left
                anchors.leftMargin: design.gap
                anchors.verticalCenter: parent.verticalCenter
                name: "music"
                ink: design.text
            }
            Text {
                anchors.left: musicIcon.right
                anchors.leftMargin: design.gap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.vertical
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: design.text
                font.family: design.fontFamily
                font.pixelSize: design.bodySize
            }
        }
    }
    IslandButton {
        id: play
        tooltipsEnabled: !root.bar
        visible: !root.islandMode
        readonly property bool tooltipHovered: !root.islandMode && hovered && root.visible && !(root.coordinator && root.coordinator.viewVisible)
        readonly property string nativeTooltipText: root.boundedTooltip(pending ? Strings.sendingCommand : !actionEnabled ? disabledReason : accessibleLabel)
        onTooltipHoveredChanged: root.updateTooltip(play, nativeTooltipText)
        onNativeTooltipTextChanged: if (tooltipHovered) root.updateTooltip(play, nativeTooltipText)
        objectName: "barPlayButton"
        tokens: design
        x: root.vertical ? 0 : details.width
        y: root.vertical ? root.barSize : 0
        width: root.barSize
        height: root.barSize
        coordinator: root.coordinator
        background: Rectangle {
            anchors.fill: parent
            anchors.margins: design.small / 2
            radius: height / 2
            color: play.down && play.actionEnabled && !play.pending ? design.hover : "transparent"
            border.width: play.visualFocus ? design.focusWidth : 0
            border.color: design.text
        }
        actionName: "PlayPause"
        actionEnabled: root.endpoint !== null && root.capabilities.CanControl === true
            && (root.playing ? root.capabilities.CanPause === true : root.capabilities.CanPlay === true)
        pending: root.coordinator && root.coordinator.pendingAction === "PlayPause"
        iconName: root.playing ? "pause" : "play"
        accessibleLabel: root.playing ? Strings.pause : Strings.play
        disabledReason: "The source is not ready or does not support play/pause"
        // The host's reorder layer forwards clicks, not presses. Observe the
        // original press passively so the forwarded click keeps its source.
        function triggerPress(button) { root.hideTooltips(); if (button === Qt.LeftButton) clicked(); }
    }
    Item {
        parent: root.Window.window ? root.Window.window.contentItem : root
        anchors.fill: parent
        z: 1
        PointHandler {
            enabled: !root.islandMode
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) {
                var position = play.mapFromItem(parent, point.position.x, point.position.y);
                play.capturedIntent = root.visible && play.actionEnabled && !play.pending && root.coordinator
                    && position.x >= 0 && position.x < play.width && position.y >= 0 && position.y < play.height
                    ? root.coordinator.captureIntent() : null;
            }
        }
    }
}
