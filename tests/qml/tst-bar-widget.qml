import QtQuick
import QtTest
import "../../qml/CatchZone.js" as CatchZone
import "../.."
import "../../components"

TestCase {
    id: test
    name: "MusicBarWidget"
    width: 400
    height: 60
    when: windowShown
    visible: true
    DesignTokens {
        id: design
    }
    FontMetrics {
        id: tooltipMetrics
        font.family: hostBar.fontFamily
        font.pixelSize: 12
    }
    QtObject {
        id: facade
        property bool panelAllowed: true
        property bool uiAllowed: true
        property bool autoShow: true
        property bool viewVisible: false
        property bool lightTheme: false
        property bool highContrast: false
        property bool reducedMotion: true
        property int bodyFontSize: 12
        property bool pinUnavailable: false
        property bool island: false
        property bool islandPointerActive: false
        property string islandScreenName: ""
        property var spanNotes: []
        function noteBarCentreSpan(screenName, span) {
            spanNotes = spanNotes.concat([{ screen: screenName, span: span }]);
        }
        property var placementNotes: []
        function noteBarPlacement(screenName, offCentre) {
            placementNotes = placementNotes.concat([offCentre]);
        }
        property string selectedLabel: "Chrome · browser source"
        property string pendingAction: ""
        property var selectedEndpoint: null
        property int dispatched: 0
        function captureIntent() { return {token: selectedEndpoint.token}; }
        function invoke(action, intent) {
            compare(action, "PlayPause");
            compare(intent.token.id, selectedEndpoint.token.id);
            dispatched++;
        }
    }
    QtObject {
        id: host
        property int opens: 0
        property int closes: 0
        property var lastPayload: null
        function serviceFor(id) { compare(id, "io.github.bavanchun.nookisle"); return facade; }
        function summon(id, payload) {
            compare(id, "io.github.bavanchun.nookisle");
            lastPayload = JSON.parse(payload);
            opens++;
        }
        function hide(id) { compare(id, "io.github.bavanchun.nookisle"); closes++; }
    }
    QtObject {
        id: hostBar
        property var shell: host
        property int barSize: 26
        property bool vertical: false
        property string position: "top"
        property color barForeground: "#d4be98"
        property string fontFamily: "monospace"
        property var clickTargets: []
        property var tooltipCalls: []
        property var tooltipTarget: null
        property string tooltipText: ""
        property var centerPeekCalls: []
        function registerClickTarget(target) { clickTargets = clickTargets.concat([target]); }
        function unregisterClickTarget(target) { clickTargets = clickTargets.filter(item => item !== target); }
        function setCenterHoverRevealSuppressed(value) { centerPeekCalls = centerPeekCalls.concat([value]); }
        function showTooltip(target, text) {
            verify(clickTargets.indexOf(target) >= 0);
            tooltipCalls = tooltipCalls.concat([{action: "show", target: target, text: text}]);
            tooltipTarget = target;
            tooltipText = text;
        }
        function hideTooltip(target) {
            tooltipCalls = tooltipCalls.concat([{action: "hide", target: target}]);
            if (tooltipTarget === target) {
                tooltipTarget = null;
                tooltipText = "";
            }
        }
    }
    Component {
        id: offsetContainerComponent
        Item { x: 31; y: 3; width: 340; height: 40 }
    }
    // The host bar's horizontal layout: a centre holder filling the bar with
    // the spacer centred in it, and left and right module rows at the edges.
    Component {
        id: barLayoutComponent
        Item {
            width: 1000
            height: 26
            property alias widget: spacer
            property alias leftRow: leftRow
            Item {
                anchors.fill: parent
                BarWidget {
                    id: spacer
                    bar: hostBar
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                }
            }
            Item { id: leftRow; x: 8; width: 300; height: 26 }
            Item { x: 792; width: 200; height: 26 }
        }
    }
    // The widget placed at the left of the bar, as the installer's default
    // placement leaves it until it is made the centre anchor.
    Component {
        id: offCentreLayoutComponent
        Item {
            width: 1000
            height: 26
            Item {
                anchors.fill: parent
                BarWidget { bar: hostBar; x: 330; width: implicitWidth; height: implicitHeight }
            }
            Item { x: 8; width: 300; height: 26 }
            Item { x: 792; width: 200; height: 26 }
        }
    }
    Component {
        id: widgetComponent
        BarWidget { bar: hostBar; width: implicitWidth; height: implicitHeight }
    }
    Component {
        id: overlayComponent
        MouseArea {
            property var target
            anchors.fill: parent
            onClicked: function(mouse) { target.triggerPress(mouse.button); }
        }
    }
    Component {
        id: barPreviewComponent
        Rectangle {
            color: "#282828"
            width: previewWidget.width + 16
            height: previewWidget.height + 16
            property alias widget: previewWidget
            BarWidget {
                id: previewWidget
                x: 8
                y: 8
                bar: hostBar
                width: implicitWidth
                height: implicitHeight
            }
        }
    }
    function init() {
        mouseMove(test, 399, 59);
        host.opens = 0;
        host.closes = 0;
        facade.viewVisible = false;
        facade.dispatched = 0;
        facade.panelAllowed = true;
        facade.uiAllowed = true;
        facade.autoShow = true;
        facade.pendingAction = "";
        facade.bodyFontSize = 12;
        facade.island = false;
        facade.islandPointerActive = false;
        facade.islandScreenName = "";
        tooltipMetrics.font.pixelSize = 12;
        facade.selectedLabel = "Chrome · browser source";
        hostBar.position = "top";
        hostBar.vertical = false;
        hostBar.tooltipCalls = [];
        hostBar.tooltipTarget = null;
        hostBar.tooltipText = "";
        hostBar.centerPeekCalls = [];
        facade.selectedEndpoint = {
            token: {id: "first"}, status: "Paused",
            presentation: {title: "A real endpoint presentation contract"},
            capabilities: {CanControl: true, CanPlay: true, CanPause: true}
        };
    }
    function test_inlineGeometryAndOpenWithoutPlayback() {
        var widget = createTemporaryObject(widgetComponent, test);
        verify(widget);
        compare(widget.height, 26);
        compare(widget.width, 280);
        compare(host.opens, 0);
        mouseClick(findChild(widget, "barDetailsButton"));
        compare(host.opens, 1);
        compare(host.lastPayload.expanded, true);
        compare(host.lastPayload.anchorCenterX, 140);
        compare(host.lastPayload.anchorLeftX, 0);
        compare(facade.dispatched, 0);
        facade.viewVisible = true;
        mouseClick(findChild(widget, "barDetailsButton"));
        compare(host.closes, 1);
        compare(host.opens, 1);
        compare(facade.dispatched, 0);
    }
    function test_shortTitleUsesCompactContinuousGroup() {
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint,
            {presentation: {title: "Home"}});
        var preview = createTemporaryObject(barPreviewComponent, test);
        var widget = preview.widget;
        var details = findChild(widget, "barDetailsButton");
        var play = findChild(widget, "barPlayButton");
        var surface = findChild(widget, "barGroupSurface");
        verify(widget.width >= 112);
        verify(widget.width < 200, "A short title must not reserve the long-title width");
        compare(details.x, 0);
        compare(play.x, details.x + details.width);
        compare(play.x + play.width, widget.width);
        compare(play.width, hostBar.barSize);
        compare(surface.x, 0);
        compare(surface.y, 0);
        compare(surface.width, widget.width);
        compare(surface.height, widget.height);
        compare(surface.opacity, 0);
        waitForRendering(preview);
        grabImage(preview).save(Qt.resolvedUrl("../../build/ui-preview/bar-short-normal.png").toString().slice(7));
        mouseMove(details, details.width / 2, 13);
        tryCompare(details, "hovered", true);
        compare(surface.opacity, 1);
        compare(details.background.color.a, 0);
        compare(play.background.color.a, 0);
        waitForRendering(preview);
        grabImage(preview).save(Qt.resolvedUrl("../../build/ui-preview/bar-short-title-hover.png").toString().slice(7));
        mouseMove(widget, play.x - 1, 13);
        compare(surface.opacity, 1);
        mouseMove(widget, play.x, 13);
        compare(surface.opacity, 1);
        mouseMove(play, play.width / 2, 13);
        tryCompare(play, "hovered", true);
        compare(surface.opacity, 1);
        compare(details.background.color.a, 0);
        compare(play.background.color.a, 0);
        waitForRendering(preview);
        grabImage(preview).save(Qt.resolvedUrl("../../build/ui-preview/bar-short-play-hover.png").toString().slice(7));
        mouseMove(test, 399, 59);
        compare(surface.opacity, 0);
        facade.viewVisible = true;
        compare(surface.opacity, 1);
        facade.viewVisible = false;
        compare(surface.opacity, 0);
        compare(host.opens, 0);
        compare(host.closes, 0);
        compare(facade.dispatched, 0);
        mousePress(play, play.width / 2, 13);
        compare(surface.opacity, 1);
        verify(play.capturedIntent !== null);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, {token: {id: "second"}});
        mouseRelease(play, play.width / 2, 13);
        compare(facade.dispatched, 0);
        mouseClick(play, play.width / 2, 13);
        compare(facade.dispatched, 1);
        mouseMove(test, 399, 59);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint,
            {presentation: {title: "A real endpoint presentation contract with a longer title"}});
        compare(widget.width, 280);
        waitForRendering(preview);
        grabImage(preview).save(Qt.resolvedUrl("../../build/ui-preview/bar-long-normal.png").toString().slice(7));
    }
    function test_playCaptureAndSourceReplacement() {
        var widget = createTemporaryObject(widgetComponent, test);
        var play = findChild(widget, "barPlayButton");
        mouseClick(play);
        compare(facade.dispatched, 1);
        mousePress(play);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, {token: {id: "second"}});
        mouseRelease(play);
        compare(facade.dispatched, 1);
    }
    function test_lockAndDisconnectedStates() {
        var widget = createTemporaryObject(widgetComponent, test);
        facade.uiAllowed = false;
        compare(widget.title, "Nookisle");
        verify(!findChild(widget, "barPlayButton").actionEnabled);
        facade.panelAllowed = false;
        verify(!widget.visible);
        widget.openDetails();
        compare(host.opens, 0);
        facade.panelAllowed = true;
        facade.autoShow = false;
        verify(!widget.visible);
    }
    function test_hostForwardedClickRetainsOriginalPress() {
        var widget = createTemporaryObject(widgetComponent, test);
        var play = findChild(widget, "barPlayButton");
        verify(hostBar.clickTargets.indexOf(play) >= 0);
        var overlay = createTemporaryObject(overlayComponent, widget, {target: play});
        mousePress(overlay, 267, 13);
        verify(play.capturedIntent !== null);
        mouseRelease(overlay, 267, 13);
        compare(facade.dispatched, 1);
        mousePress(overlay, 267, 13);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, {token: {id: "second"}});
        mouseRelease(overlay, 267, 13);
        compare(facade.dispatched, 1);
    }
    function test_nestedWidgetAnchorsUseWindowCoordinates() {
        var container = createTemporaryObject(offsetContainerComponent, test);
        var widget = createTemporaryObject(widgetComponent, container, {x: 17});
        var details = findChild(widget, "barDetailsButton");
        details.triggerPress(Qt.LeftButton);
        compare(host.opens, 1);
        compare(host.lastPayload.anchorLeftX, 48);
        compare(host.lastPayload.anchorCenterX, 188);
        compare(facade.dispatched, 0);
    }
    function test_nativeTooltipHoverLeaveAndPanelVisibility() {
        var widget = createTemporaryObject(widgetComponent, test);
        var details = findChild(widget, "barDetailsButton");
        var play = findChild(widget, "barPlayButton");
        verify(hostBar.clickTargets.indexOf(details) >= 0);
        verify(hostBar.clickTargets.indexOf(play) >= 0);
        mouseMove(details, 20, 13);
        tryCompare(details, "tooltipHovered", true);
        compare(hostBar.tooltipTarget, details);
        compare(hostBar.tooltipText, widget.title + "\n" + facade.selectedLabel);
        compare(details.tooltipsEnabled, false);
        compare(findChild(details, "buttonToolTip").visible, false);
        mouseMove(play, 13, 13);
        tryCompare(play, "tooltipHovered", true);
        compare(hostBar.tooltipTarget, play);
        compare(hostBar.tooltipText, play.accessibleLabel);
        compare(play.tooltipsEnabled, false);
        compare(findChild(play, "buttonToolTip").visible, false);
        mouseMove(test, 399, 59);
        tryCompare(play, "tooltipHovered", false);
        compare(hostBar.tooltipTarget, null);
        mouseMove(details, 20, 13);
        tryCompare(details, "tooltipHovered", true);
        facade.viewVisible = true;
        compare(details.tooltipHovered, false);
        compare(hostBar.tooltipTarget, null);
        mouseMove(play, 13, 13);
        compare(play.tooltipHovered, false);
        compare(hostBar.tooltipTarget, null);
        compare(facade.dispatched, 0);
    }
    function test_detailsAndForwardedPlayClickHideNativeTooltip() {
        var widget = createTemporaryObject(widgetComponent, test);
        var details = findChild(widget, "barDetailsButton");
        var play = findChild(widget, "barPlayButton");
        mouseMove(details, 20, 13);
        tryCompare(hostBar, "tooltipTarget", details);
        details.triggerPress(Qt.LeftButton);
        compare(hostBar.tooltipTarget, null);
        compare(host.opens, 1);
        compare(facade.dispatched, 0);
        mouseMove(play, 13, 13);
        tryCompare(hostBar, "tooltipTarget", play);
        var overlay = createTemporaryObject(overlayComponent, widget, {target: play});
        mouseClick(overlay, 267, 13);
        compare(hostBar.tooltipTarget, null);
        compare(facade.dispatched, 1);
    }
    function test_nativeTooltipBoundsAndMetadataRefresh_data() {
        return [{tag: "default-font", fontSize: 12}, {tag: "larger-host-font", fontSize: 20}];
    }
    function test_nativeTooltipBoundsAndMetadataRefresh(data) {
        facade.bodyFontSize = data.fontSize;
        var longTitle = "Một bản nhạc có tên rất dài cùng dàn nhạc giao hưởng ".repeat(12);
        var longSource = "Chrome · Nguồn trình duyệt có tên rất dài ".repeat(12);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint,
            {presentation: {title: longTitle}});
        facade.selectedLabel = longSource;
        var widget = createTemporaryObject(widgetComponent, test);
        var details = findChild(widget, "barDetailsButton");
        compare(details.tokens.bodySize, data.fontSize);
        tooltipMetrics.font.pixelSize = data.fontSize;
        mouseMove(details, 20, 13);
        tryCompare(hostBar, "tooltipTarget", details);
        verify(widget.tooltipTextWidth > 0 && widget.tooltipTextWidth <= 480);
        var lines = hostBar.tooltipText.split("\n");
        compare(lines.length, 2);
        verify(lines[0].length < longTitle.length);
        verify(lines[1].length < longSource.length);
        for (var line of lines)
            verify(tooltipMetrics.advanceWidth(line) <= widget.tooltipTextWidth + 0.5,
                "Native tooltip line width " + tooltipMetrics.advanceWidth(line) + " exceeds " + widget.tooltipTextWidth);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint,
            {presentation: {title: "Bài hát tiếp theo"}});
        facade.selectedLabel = "Spotify";
        compare(details.tooltipHovered, true);
        compare(hostBar.tooltipText, "Bài hát tiếp theo\nSpotify");
        compare(hostBar.tooltipCalls[hostBar.tooltipCalls.length - 1].action, "show");
        compare(facade.dispatched, 0);
    }
    function test_nativeTooltipReflowsWhenHostFontChangesDuringHover() {
        var longTitle = "Một bản nhạc có tên rất dài cùng dàn nhạc giao hưởng ".repeat(12);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint,
            {presentation: {title: longTitle}});
        facade.selectedLabel = "Chrome · Nguồn trình duyệt có tên rất dài ".repeat(12);
        var widget = createTemporaryObject(widgetComponent, test);
        var details = findChild(widget, "barDetailsButton");
        mouseMove(details, 20, 13);
        tryCompare(hostBar, "tooltipTarget", details);
        var initialText = hostBar.tooltipText;
        var callsBeforeResize = hostBar.tooltipCalls.length;
        facade.bodyFontSize = 20;
        tooltipMetrics.font.pixelSize = 20;
        compare(details.tokens.bodySize, 20);
        compare(details.tooltipHovered, true);
        verify(hostBar.tooltipCalls.length > callsBeforeResize);
        verify(hostBar.tooltipText !== initialText);
        var lines = hostBar.tooltipText.split("\n");
        compare(lines.length, 2);
        for (var line of lines)
            verify(tooltipMetrics.advanceWidth(line) <= widget.tooltipTextWidth + 0.5,
                "Updated host tooltip must fit at 20px");
        compare(facade.dispatched, 0);
    }
    function test_nativePlayTooltipRefreshesWithoutPointerMovement() {
        var widget = createTemporaryObject(widgetComponent, test);
        var play = findChild(widget, "barPlayButton");
        mouseMove(play, 13, 13);
        tryCompare(hostBar, "tooltipTarget", play);
        compare(hostBar.tooltipText, "Play");
        facade.pendingAction = "PlayPause";
        compare(hostBar.tooltipText, "Sending command");
        facade.pendingAction = "";
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, {status: "Playing"});
        compare(hostBar.tooltipText, "Pause");
        facade.uiAllowed = false;
        compare(hostBar.tooltipText, widget.boundedTooltip(play.disabledReason));
        verify(hostBar.tooltipText.indexOf("The source is not ready") === 0);
        compare(play.tooltipHovered, true);
        compare(facade.dispatched, 0);
    }
    // The spacer measures the empty bar centre between the module rows and
    // publishes it for the catch zone, again once the rows settle after a
    // change.
    function test_islandSpacerPublishesFreeCentre() {
        facade.island = true;
        facade.spanNotes = [];
        var layout = createTemporaryObject(barLayoutComponent, test);
        tryVerify(function () { return facade.spanNotes.length > 0; });
        compare(facade.spanNotes[facade.spanNotes.length - 1].span, 384);
        var before = facade.spanNotes.length;
        layout.leftRow.width = 400;
        compare(facade.spanNotes[facade.spanNotes.length - 1].span, -1,
            "a row change withdraws the span at once, before the row can reach the catch region");
        layout.leftRow.width = 420;
        layout.leftRow.width = 440;
        compare(facade.spanNotes.length, before + 1, "an animating row withdraws once, not per frame");
        tryVerify(function () { return facade.spanNotes[facade.spanNotes.length - 1].span === 104; });
        compare(facade.spanNotes.length, before + 2, "the settled span is republished once");
        facade.island = false;
        tryVerify(function () { return facade.spanNotes[facade.spanNotes.length - 1].span === -1; },
            1000, "leaving island mode withdraws the span");
    }
    // The spacer says whether it sits at the bar's middle, so the welcome can
    // point out an island that is not the centre anchor.
    function test_islandSpacerReportsItsPlacement() {
        compare(CatchZone.offCentre(500, 1000), false)
        compare(CatchZone.offCentre(502, 1000), false, "rounding is absorbed")
        compare(CatchZone.offCentre(420, 1000), true)
        facade.island = true;
        facade.placementNotes = [];
        facade.spanNotes = [];
        createTemporaryObject(barLayoutComponent, test);
        tryVerify(function () { return facade.spanNotes.length > 0; });
        compare(facade.placementNotes, [], "a centred island has nothing to report");
        createTemporaryObject(offCentreLayoutComponent, test);
        tryVerify(function () { return facade.placementNotes.length > 0; });
        compare(facade.placementNotes[facade.placementNotes.length - 1], true);
        facade.island = false;
        tryVerify(function () { return facade.placementNotes[facade.placementNotes.length - 1] === false; },
            1000, "leaving island mode withdraws the note");
    }
    function test_islandSpacerWithoutRowsPublishesUnknown() {
        facade.island = true;
        facade.spanNotes = [];
        createTemporaryObject(widgetComponent, test);
        tryVerify(function () { return facade.spanNotes.length > 0; });
        compare(facade.spanNotes[facade.spanNotes.length - 1].span, -1, "no recognisable rows: no catch region");
        facade.island = false;
    }
    function test_islandModeIsSpacer() {
        facade.island = true;
        var widget = createTemporaryObject(widgetComponent, test);
        verify(widget.islandMode);
        compare(widget.implicitWidth, design.liveWidth - 2 * design.flareClosed, "the closed notch body; the flares overhang it");
        compare(widget.implicitHeight, 26);
        verify(!findChild(widget, "barDetailsButton").visible);
        verify(!findChild(widget, "barPlayButton").visible);
        verify(!findChild(widget, "barGroupSurface").visible);
        compare(hostBar.clickTargets.length, 0);
        compare(widget.Accessible.name, "Nookisle");
    }
    function test_centerPeekSuppressedWhileIslandActive() {
        facade.island = true;
        var widget = createTemporaryObject(widgetComponent, test);
        verify(widget.islandMode);
        compare(hostBar.centerPeekCalls, []);
        facade.islandPointerActive = true;
        compare(hostBar.centerPeekCalls, [true]);
        facade.islandPointerActive = false;
        compare(hostBar.centerPeekCalls, [true, false]);
        facade.islandPointerActive = true;
        compare(hostBar.centerPeekCalls, [true, false, true]);
        widget.destroy();
        wait(0);
        compare(hostBar.centerPeekCalls, [true, false, true, false]);
    }
    // On multiple monitors, every bar shares the one Service-level
    // `islandPointerActive`; only the bar on the island's own screen may
    // suppress its centre peek (code review L7).
    function test_centerPeekSuppressionOnlyOnIslandScreen() {
        facade.island = true;
        var widget = createTemporaryObject(widgetComponent, test);
        verify(widget.islandMode);
        facade.islandScreenName = "definitely-not-this-widgets-screen";
        facade.islandPointerActive = true;
        compare(hostBar.centerPeekCalls, [], "a different screen's island must not suppress this bar's peek");
        facade.islandPointerActive = false;
        facade.islandScreenName = widget.ownScreenName;
        facade.islandPointerActive = true;
        compare(hostBar.centerPeekCalls, [true], "the island's own screen suppresses this bar's peek");
        facade.islandPointerActive = false;
        compare(hostBar.centerPeekCalls, [true, false]);
    }
    function test_noSuppressionCallInLegacyMode() {
        var widget = createTemporaryObject(widgetComponent, test);
        verify(!widget.islandMode);
        facade.islandPointerActive = true;
        compare(hostBar.centerPeekCalls, []);
        facade.islandPointerActive = false;
        compare(hostBar.centerPeekCalls, []);
    }
    function test_legacyModeUnchanged() {
        facade.island = false;
        var widget = createTemporaryObject(widgetComponent, test);
        verify(!widget.islandMode);
        compare(widget.height, 26);
        compare(widget.width, 280);
        verify(findChild(widget, "barDetailsButton").visible);
        verify(findChild(widget, "barPlayButton").visible);
        verify(findChild(widget, "barGroupSurface").visible);
        mouseClick(findChild(widget, "barDetailsButton"));
        compare(host.opens, 1);
    }
    function test_verticalBarStaysLegacy() {
        facade.island = true;
        hostBar.vertical = true;
        var widget = createTemporaryObject(widgetComponent, test);
        verify(!widget.islandMode);
        compare(widget.implicitWidth, hostBar.barSize);
        verify(findChild(widget, "barDetailsButton").visible);
        verify(findChild(widget, "barPlayButton").visible);
        compare(hostBar.clickTargets.indexOf(findChild(widget, "barPlayButton")) >= 0, true);
    }
}
