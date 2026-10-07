pragma ComponentBehavior: Bound

import QtQuick
import "qml/CatchZone.js" as CatchZone
import "components"

Item {
    id: root
    property var bar: null
    property string moduleName: "io.github.bavanchun.nookisle"
    property var settings: ({})
    readonly property var host: bar ? bar.shell : null
    readonly property var coordinator: host ? host.serviceFor(moduleName) : null
    readonly property bool vertical: bar && bar.vertical === true
    readonly property real barSize: bar ? bar.barSize : design.target
    // The host still loads this entrypoint, but it only reserves notch space.
    // Other bar layouts have no widget; the island stays at the screen top.
    readonly property bool spacerAllowed: !!bar && bar.position === "top" && !vertical
    visible: spacerAllowed && coordinator && coordinator.panelAllowed === true && coordinator.autoShow !== false
    implicitWidth: spacerAllowed ? design.liveWidth - 2 * design.flareClosed : 0
    implicitHeight: spacerAllowed ? barSize : 0
    Accessible.name: "Nookisle"
    // Written only on this widget's own transitions, the same contract the
    // first-party clock and weather panels follow for the shared flag
    // (host centre-hover peek contract).
    // On multiple monitors, every bar shares the one Service-level
    // `islandPointerActive`, so without a screen check every bar would
    // suppress its own centre peek whenever the island is hovered on any
    // screen. An unset `islandScreenName` (the coordinator has not resolved
    // one yet) stays permissive rather than never suppressing.
    readonly property string ownScreenName: root.Window.window && root.Window.window.screen ? root.Window.window.screen.name : ""
    readonly property bool suppressCenterPeek: spacerAllowed && visible
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
    // Without that layout, or without a top horizontal bar, it publishes -1 and the
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
        if (!spacerAllowed || !barRows || !rowHolder) {
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
    onSpacerAllowedChanged: measureSoon()
    Component.onCompleted: measureSoon()
    Component.onDestruction: {
        if (coordinator && typeof coordinator.noteBarCentreSpan === "function")
            coordinator.noteBarCentreSpan(ownScreenName, -1);
        if (centerPeekSuppressionSent && bar && typeof bar.setCenterHoverRevealSuppressed === "function")
            bar.setCenterHoverRevealSuppressed(false);
    }

    DesignTokens { id: design }
}
