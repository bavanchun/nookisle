import QtQuick
import QtTest
import QtQuick.Controls.Basic
import "../../components"

TestCase {
    id: test
    name: "IslandState"
    width: 384
    height: design.expandedHeight + design.rowHeight
    when: windowShown
    visible: true
    DesignTokens {
        id: design
        reducedMotion: true
    }
    QtObject {
        id: facade
        property bool panelAllowed: true
        property bool uiAllowed: true
        property var selectedEndpoint: null
        property var endpoints: []
        property string selectedLabel: "Spotify"
        property string selectionMode: "auto"
        property bool pinUnavailable: false
        property real positionSeconds: 74
        property string pendingAction: ""
        property string actionError: ""
        property string statusText: ""
        property bool reducedMotion: true
        property bool highContrast: false
        property bool remoteArtwork: false
        property bool autoShow: true
        property int retries: 0
        property bool island: true
        property bool hud: true
        property bool visualizer: true
        property bool peek: true
        property bool tint: true
        property bool power: true
        property bool lyrics: false
        property bool islandPointerActive: false
        property var shelfItems: []
        property bool sleepArmable: true
        property bool sleepLockVerified: true
        property double sleepDeadline: 0
        property string sleepFailure: ""
        property var armedMinutes: []
        function armSleepTimer(minutes) {
            armedMinutes = armedMinutes.concat([minutes]);
            sleepDeadline = new Date(2026, 8, 23, 23, 5).getTime();
            return "ok";
        }
        function cancelSleepTimer() {
            sleepDeadline = 0;
            sleepFailure = "";
        }
        function captureIntent() {
            return null;
        }
        function invoke(action, intent, value) {
            fail("State fixture must not dispatch");
        }
        function selectSource(token) {
            selectionMode = "pinned";
        }
        function selectAuto() {
            selectionMode = "auto";
        }
        function retryConnection() {
            retries++;
        }
        function configure(options) {
            for (var key in options)
                facade[key] = options[key];
        }
    }
    Component {
        id: islandComponent
        Rectangle {
            color: design.surface
            width: island.expanded ? design.expandedWidth : design.compactWidth
            height: island.expanded ? design.panelHeight(width) : design.compactHeight
            radius: island.expanded ? design.expandedRadius : design.compactRadius
            property alias content: island
            IslandContent {
                id: island
                anchors.fill: parent
                tokens: design
                coordinator: facade
                onToggleRequested: expanded = !expanded
            }
        }
    }
    Component {
        id: artworkComponent
        Artwork {
            tokens: design
            width: 48
            height: 48
        }
    }
    Component {
        id: artworkFixture
        Rectangle {
            width: 48
            height: 48
            color: "#ed704f"
        }
    }
    Component {
        id: pickerComponent
        SourcePicker {
            tokens: design
            coordinator: facade
            width: 384
            height: design.expandedHeight
        }
    }
    function test_sourceScopeAndPlatformLabels() {
        var picker = createTemporaryObject(pickerComponent, test);
        compare(picker.sourceName({
            presentation: {
                hostApp: "Chrome",
                platform: "YouTube",
                controlScope: "document"
            }
        }), "YouTube · Chrome · Chrome tab");
        compare(picker.sourceName({
            presentation: {
                hostApp: "Chrome",
                platform: "Spotify",
                controlScope: "document"
            }
        }), "Spotify · Chrome · Chrome tab");
        compare(picker.sourceName({
            presentation: {
                hostApp: "Chrome",
                controlScope: "browser"
            }
        }), "Chrome · browser source");
    }
    // The helper publishes a path only for a local cover or, with remote
    // artwork on, a fetched one, and withdraws it when consent ends; the
    // view shows whatever the selected endpoint carries.
    function test_artworkFollowsThePublishedPath() {
        var view = createTemporaryObject(islandComponent, test)
        view.visible = false
        var e = endpoint()
        e.artworkPath = "/private/runtime/cached-art.png"
        facade.selectedEndpoint = e
        facade.remoteArtwork = false
        compare(view.content.displayArtworkPath, e.artworkPath)
        var withdrawn = endpoint()
        facade.selectedEndpoint = withdrawn
        compare(view.content.displayArtworkPath, "")
    }
    function test_artworkMaskAndMotionCancellation() {
        var fixture = createTemporaryObject(artworkFixture, test);
        var path = Qt.resolvedUrl("../../build/ui-preview/art-fixture.png").toString().slice(7);
        grabImage(fixture).save(path);
        fixture.destroy();
        design.reducedMotion = false;
        var art = createTemporaryObject(artworkComponent, test, {
            artworkPath: path
        });
        var image = findChild(art, "artworkImage");
        tryCompare(image, "status", Image.Ready);
        design.reducedMotion = true;
        compare(art.fadeRunning, false);
        compare(findChild(art, "artworkRaster").opacity, 1);
        wait(50);
        var capture = grabImage(art);
        capture.save(Qt.resolvedUrl("../../build/ui-preview/art-rounded.png").toString().slice(7));
        verify(capture.pixel(0, 0) !== capture.pixel(24, 24));
        verify(capture.red(24, 24) > 200);
        art.visible = false;
        compare(art.fadeRunning, false);
        compare(image.source.toString(), "");
        art.artworkPath = "https://invalid.example/art.png";
        art.visible = true;
        compare(image.source.toString(), "");
    }
    function endpoint() {
        return {
            token: {
                owner: "fixture"
            },
            trackToken: {
                id: "track"
            },
            status: "Playing",
            positionSeconds: 74,
            lengthSeconds: 245,
            volume: 0.6,
            artworkPath: "",
            presentation: {
                title: "Một ngày mới trên những con đường đầy nắng",
                artists: ["Nghệ sĩ thử nghiệm"],
                hostApp: "Spotify",
                controlScope: "application"
            },
            capabilities: {
                CanControl: true,
                CanPlay: true,
                CanPause: true,
                CanGoPrevious: true,
                CanGoNext: true,
                CanSeek: true,
                CanSetPosition: true,
                CanSetVolume: true
            }
        };
    }
    function init() {
        facade.sleepArmable = true;
        facade.sleepLockVerified = true;
        facade.sleepDeadline = 0;
        facade.sleepFailure = "";
        facade.armedMinutes = [];
        facade.panelAllowed = true;
        facade.uiAllowed = true;
        facade.selectedEndpoint = endpoint();
        facade.endpoints = [facade.selectedEndpoint];
        facade.actionError = "";
        facade.statusText = "";
        facade.pinUnavailable = false;
        facade.selectionMode = "auto";
        facade.selectedLabel = "Spotify";
        design.light = false;
        design.highContrast = false;
        design.theme = ({});
        design.reducedMotion = true;
    }
    function test_secondaryViewKeyboardFocus_data() {
        return [
            { tag: "sources", opener: "openSourcePicker", initial: "autoSourceButton", state: "pickerOpen" },
            { tag: "settings", opener: "openSettingsButton", initial: "settingsBackButton", state: "settingsOpen" }
        ];
    }
    function test_secondaryViewKeyboardFocus(data) {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        var opener = findChild(view, data.opener);
        verify(opener);
        opener.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        tryCompare(view.content, data.state, true);
        var initial = findChild(view, data.initial);
        verify(initial);
        tryCompare(initial, "activeFocus", true);
        verify(initial.visualFocus);
        keyClick(Qt.Key_Escape);
        compare(view.content[data.state], false);
        tryCompare(opener, "activeFocus", true);
        verify(view.content.expanded);
        keyClick(Qt.Key_Space);
        tryCompare(view.content, data.state, true);
        initial = findChild(view, data.initial);
        tryCompare(initial, "activeFocus", true);
        keyClick(Qt.Key_Space);
        compare(view.content[data.state], false);
        tryCompare(opener, "activeFocus", true);
    }
    function test_errorTextGeometry_data() {
        var rows = [];
        var codes = ["target-gone", "stale-track", "unsupported", "busy", "disconnected", "timeout", "error", "locked", "unknown"];
        [384, 320, 256].forEach(function (width) {
            codes.forEach(function (code) {
                rows.push({tag: width + "-" + code, panelWidth: width, code: code});
            });
        });
        return rows;
    }
    function test_errorTextGeometry(data) {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        view.width = data.panelWidth;
        facade.actionError = data.code;
        var message = findChild(view, "actionErrorMessage");
        var footer = findChild(view, "openSourcePicker");
        var volume = findChild(view, "volumeControl");
        waitForRendering(view);
        verify(message.visible);
        compare(message.text, view.content.errorText);
        verify(!message.truncated, "The complete error must remain readable");
        verify(message.height >= message.contentHeight);
        verify(message.mapToItem(view, 0, 0).y >= volume.mapToItem(view, 0, volume.height).y);
        verify(message.mapToItem(view, 0, message.height).y
                <= footer.mapToItem(view, 0, 0).y - design.bandSpacing,
            "The error must not cross the footer separator");
        verify(message.mapToItem(view, message.width, 0).x <= view.width - design.inset);
    }
    function test_longMetadataWithLargerFont() {
        design.theme = {titleSize: 16, bodySize: 14, captionSize: 12};
        var e = endpoint();
        e.presentation.title = "Một ngày mới trên những con đường đầy nắng — bản thu trực tiếp cùng dàn nhạc và những người bạn";
        e.presentation.artists = ["Nghệ sĩ có tên rất dài", "Dàn nhạc giao hưởng thành phố"];
        facade.selectedEndpoint = e;
        facade.selectedLabel = "Spotify · Trình phát có tên rất dài";
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        var title = findChild(view, "trackTitle");
        var progress = findChild(view, "progressControl");
        wait(80);
        compare(title.text, e.presentation.title);
        compare(title.font.pixelSize, 16);
        verify(title.truncated);
        verify(title.lineCount <= 2);
        verify(title.parent.mapToItem(view, 0, title.parent.height).y <= progress.mapToItem(view, 0, 0).y,
            "Metadata must finish before the progress control");
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/large-font-long-metadata.png").toString().slice(7));
    }
    function test_narrow256Layout() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        view.width = 256;
        var progress = findChild(view, "progressControl");
        var play = findChild(view, "expandedPlayButton");
        var next = findChild(view, "nextTrackButton");
        var volume = findChild(view, "volumeControl");
        var volumeIcon = findChild(view, "volumeIcon");
        var footer = findChild(view, "openSourcePicker");
        wait(80);
        verify(progress.mapToItem(view, 0, progress.height).y <= play.mapToItem(view, 0, 0).y);
        verify(play.mapToItem(view, 0, play.height).y <= volume.mapToItem(view, 0, 0).y);
        verify(next.mapToItem(view, 0, next.height).y <= volumeIcon.mapToItem(view, 0, 0).y);
        verify(volume.mapToItem(view, volume.width, 0).x <= view.width - design.inset);
        verify(volume.mapToItem(view, 0, volume.height).y
            < footer.mapToItem(view, 0, 0).y - design.bandSpacing);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/narrow-256.png").toString().slice(7));
    }
    function test_sourceKeyboardScrollAndSelection_data() {
        return [{tag: "tab", forward: Qt.Key_Tab, backward: Qt.Key_Backtab},
            {tag: "arrows", forward: Qt.Key_Down, backward: Qt.Key_Up}];
    }
    function test_sourceKeyboardScrollAndSelection(data) {
        var endpoints = [];
        for (var i = 0; i < 6; ++i) {
            var e = endpoint();
            e.token = {owner: "source-" + i};
            endpoints.push(e);
        }
        facade.endpoints = endpoints;
        facade.selectedEndpoint = endpoints[5];
        facade.selectionMode = "pinned";
        var picker = createTemporaryObject(islandComponent, test);
        picker.content.expanded = true;
        picker.content.pickerOpen = true;
        var sources = findChild(picker, "sourceList");
        verify(sources);
        tryCompare(sources, "count", 6);
        var auto = findChild(picker, "autoSourceButton");
        tryCompare(auto, "activeFocus", true);
        wait(0);
        for (var index = 0; index < 6; ++index) {
            keyClick(data.forward);
            tryVerify(function () {
                var row = sources.itemAtIndex(index);
                return row && row.activeFocus;
            }, 1000, "Source " + index + " should receive focus");
            var row = sources.itemAtIndex(index);
            tryCompare(row, "visualFocus", true);
            compare(row.background.border.width, design.focusWidth);
            compare(row.selected, index === 5);
            verify(row.y >= sources.contentY);
            verify(row.y + row.height <= sources.contentY + sources.height);
            waitForRendering(picker);
        }
        verify(sources.contentY > 0, "Keyboard focus must scroll the last source into view");
        grabImage(picker).save(Qt.resolvedUrl("../../build/ui-preview/sources-scrolled.png").toString().slice(7));
        for (var previous = 4; previous >= 0; --previous) {
            keyClick(data.backward);
            tryVerify(function () {
                var row = sources.itemAtIndex(previous);
                return row && row.activeFocus;
            });
            tryCompare(sources.itemAtIndex(previous), "visualFocus", true);
            waitForRendering(picker);
        }
        keyClick(data.backward);
        tryCompare(auto, "activeFocus", true);
    }
    function test_loaderLifetimeAndPicker() {
        var view = createTemporaryObject(islandComponent, test);
        var loader = findChild(view, "expandedContentLoader");
        verify(!loader.active);
        view.content.expanded = true;
        tryCompare(loader, "status", Loader.Ready);
        view.content.pickerOpen = true;
        view.content.expanded = false;
        verify(!view.content.pickerOpen);
        verify(!loader.active);
        view.content.expanded = true;
        facade.panelAllowed = false;
        verify(!loader.active);
    }
    function test_emptyUnavailableDisconnected() {
        var view = createTemporaryObject(islandComponent, test);
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        compare(view.content.title, "No music source yet");
        facade.pinUnavailable = true;
        compare(view.content.title, "Spotify");
        facade.pinUnavailable = false;
        facade.uiAllowed = false;
        compare(view.content.title, "Connect Nookisle");
        verify(!view.content.playEnabled);
        compare(view.content.endpoint, null);
    }
    function test_errorCapabilitiesAndTime() {
        var view = createTemporaryObject(islandComponent, test);
        verify(view.content.playEnabled);
        var e = endpoint();
        e.capabilities.CanPause = false;
        facade.selectedEndpoint = e;
        verify(!view.content.playEnabled);
        facade.actionError = "stale-track";
        verify(view.content.errorText.indexOf("The track changed") >= 0);
        compare(view.content.timeText(3665), "1:01:05");
        compare(view.content.timeText(-3), "0:00");
    }
    function test_screenshots() {
        var view = createTemporaryObject(islandComponent, test);
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/compact.png").toString().slice(7));
        view.content.expanded = true;
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/expanded.png").toString().slice(7));
        view.content.pickerOpen = true;
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/sources.png").toString().slice(7));
        view.content.pickerOpen = false;
        // The fixture endpoint advertises no CanRaise, so Show player renders
        // disabled; the armed sleep timer shares the status band.
        verify(!findChild(view, "raiseButton").actionEnabled);
        facade.sleepDeadline = new Date(2026, 8, 23, 23, 5).getTime();
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/sleep-armed-raise-disabled.png").toString().slice(7));
        facade.sleepDeadline = 0;
        view.content.settingsOpen = true;
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/settings.png").toString().slice(7));
        view.content.settingsOpen = false;
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/empty.png").toString().slice(7));
        facade.uiAllowed = false;
        facade.statusText = "retry-exhausted";
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/error.png").toString().slice(7));
        facade.uiAllowed = true;
        facade.selectedEndpoint = endpoint();
        design.light = true;
        design.highContrast = true;
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/light-contrast.png").toString().slice(7));
    }
    function test_shellThemeAndNarrowLayout() {
        // Real installed theme roles supplied at the presentation boundary.
        design.theme = {surface: "#282828", text: "#d4be98", accent: "#7daea3",
            onAccent: "#282828", stroke: "#7daea3", fontFamily: "monospace", radius: 0};
        design.highContrast = false;
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        compare(design.surface, "#282828");
        compare(design.text, "#d4be98");
        compare(design.expandedRadius, 0);
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/native-theme.png").toString().slice(7));
        view.width = 320;
        var progress = findChild(view, "progressControl");
        var play = findChild(view, "expandedPlayButton");
        var volume = findChild(view, "volumeControl");
        verify(progress.mapToItem(view, 0, progress.height).y <= play.mapToItem(view, 0, 0).y);
        verify(play.mapToItem(view, play.width, 0).x < volume.mapToItem(view, 0, 0).x);
        verify(volume.mapToItem(view, volume.width, 0).x <= view.width - design.inset);
        wait(80);
        grabImage(view).save(Qt.resolvedUrl("../../build/ui-preview/native-narrow.png").toString().slice(7));
        design.theme = {surface: "#f6f7fb", text: "#171a22", accent: "#2456ac",
            fontFamily: "monospace", radius: 8};
        compare(design.surface, "#f6f7fb");
        compare(design.expandedRadius, 8);
        design.theme = ({});
    }

    // panelHeight() is the single height authority. If it ever depends on
    // content, the window would resize after first show and the fade would no
    // longer happen at final dimensions.
    function test_panelHeightIsAPureFunctionOfWidth() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        [384, 320, 256].forEach(function (width) {
            view.width = width;
            var baseline = design.panelHeight(width);
            var e = facade.endpoints[0];
            var originalTitle = e.presentation.title;
            ["", "target-gone", "stale-track", "unsupported", "busy", "disconnected",
             "closed", "invalid-value", "timeout", "error", "locked"].forEach(function (code) {
                facade.actionError = code;
                waitForRendering(view);
                compare(design.panelHeight(width), baseline, "error code " + code + " changed the height");
            });
            facade.actionError = "";
            e.presentation.title = "A single short title";
            facade.endpointsChanged();
            waitForRendering(view);
            compare(design.panelHeight(width), baseline, "a one-line title changed the height");
            e.presentation.title = "A considerably longer title that has to wrap onto a second line and then elide";
            facade.endpointsChanged();
            waitForRendering(view);
            compare(design.panelHeight(width), baseline, "a wrapped title changed the height");
            e.presentation.title = originalTitle;
            facade.endpointsChanged();
            facade.selectedEndpoint = null;
            waitForRendering(view);
            compare(design.panelHeight(width), baseline, "an absent endpoint changed the height");
            facade.selectedEndpoint = e;
            waitForRendering(view);
        });
    }
    // The window arithmetic and the band arithmetic must not drift. card.clip
    // would hide the overflow if they did.
    function test_panelHeightEqualsTheSumOfItsBands() {
        [384, 320, 256].forEach(function (width) {
            var narrow = width < 320;
            var sum = design.inset * 2
                + design.bandHeader + design.bandProgress + design.bandTransport(narrow)
                + design.bandStatus + design.bandFooter + design.bandSpacing * 4;
            compare(design.panelHeight(width), sum, "band sum drifted at width " + width);
        });
    }
    // Relational, not pixel-equal: ordering and containment are what protect the
    // layout, and a pixel rewrite would pass while covering nothing.
    function test_bandOrderHoldsAcrossWidthsAndFonts() {
        [{titleSize: 14, bodySize: 12, captionSize: 11},
         {titleSize: 16, bodySize: 14, captionSize: 12}].forEach(function (theme) {
            design.theme = theme;
            [384, 320, 256].forEach(function (width) {
                var view = createTemporaryObject(islandComponent, test);
                view.content.expanded = true;
                view.width = width;
                facade.actionError = "error";
                waitForRendering(view);
                var title = findChild(view, "trackTitle");
                var progress = findChild(view, "progressControl");
                var play = findChild(view, "expandedPlayButton");
                var message = findChild(view, "actionErrorMessage");
                var footer = findChild(view, "openSourcePicker");
                var tag = " at " + width + "/" + theme.bodySize;
                function top(item) { return item.mapToItem(view, 0, 0).y; }
                function bottom(item) { return item.mapToItem(view, 0, item.height).y; }
                verify(bottom(title) <= top(progress) + 1, "header overlaps progress" + tag);
                verify(bottom(progress) <= top(play) + 1, "progress overlaps transport" + tag);
                verify(bottom(play) <= top(message) + 1, "transport overlaps status" + tag);
                verify(bottom(message) <= top(footer) + 1, "status overlaps footer" + tag);
                verify(bottom(footer) <= view.height - design.inset + 1, "footer leaves the card" + tag);
                [title, progress, play, message, footer].forEach(function (item) {
                    verify(item.mapToItem(view, 0, 0).x >= design.inset - 1, "left inset" + tag);
                    verify(item.mapToItem(view, item.width, 0).x <= view.width - design.inset + 1,
                        "right inset" + tag);
                });
                view.destroy();
            });
        });
        design.theme = ({});
        facade.actionError = "";
    }

    // A property comparison only proves arithmetic returns what it was told. If a
    // low-alpha tint renders indistinguishable from its background under the
    // software renderer, the whole depth approach fails silently - so compare
    // actual rendered pixels.
    function test_raisedSurfaceIsVisiblyDistinctWhenRendered() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        view.width = 384;
        waitForRendering(view);
        var surface = findChild(view, "transportSurface");
        verify(surface && surface.visible);
        var image = grabImage(view);
        var inside = surface.mapToItem(view, surface.width / 2, surface.height / 2);
        var outside = findChild(view, "trackTitle").mapToItem(view, 0, -design.small);
        var raised = image.pixel(Math.round(inside.x), Math.round(inside.y));
        var card = image.pixel(Math.round(outside.x), Math.round(outside.y));
        verify(raised !== card,
            "the raised transport surface renders identically to the card surface");
    }
    function test_highContrastMakesElevationOpaque() {
        facade.highContrast = true;
        design.highContrast = true;
        compare(design.surfaceRaised.a, 1, "raised surface is translucent in high contrast");
        compare(design.surfaceSunken.a, 1, "sunken surface is translucent in high contrast");
        compare(design.hairline.a, design.stroke.a, "hairline ignores high contrast");
        design.highContrast = false;
        facade.highContrast = false;
    }
    // timeText clamps its argument to zero, so a negated argument would render
    // 0:00 for the whole track rather than a countdown.
    function test_scrubberCountsDownRatherThanShowingTotal() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        var e = endpoint();
        e.lengthSeconds = 200;
        facade.selectedEndpoint = e;
        facade.positionSeconds = 20;
        waitForRendering(view);
        function labels() {
            var found = [];
            function walk(item) {
                for (var i = 0; i < item.children.length; ++i) {
                    var child = item.children[i];
                    if (child.text !== undefined && String(child.text).indexOf(":") >= 0)
                        found.push(String(child.text));
                    walk(child);
                }
            }
            walk(view);
            return found;
        }
        var shown = labels();
        verify(shown.indexOf("-3:00") >= 0, "expected a remaining time of -3:00, got " + shown.join(", "));
        var unknown = endpoint();
        unknown.lengthSeconds = 0;
        facade.selectedEndpoint = unknown;
        waitForRendering(view);
        shown = labels();
        verify(shown.indexOf("--:--") >= 0, "unknown length must stay --:--, got " + shown.join(", "));
        facade.selectedEndpoint = endpoint();
        facade.positionSeconds = 74;
    }

    // The helper states a reason for one case only and the bridge never states
    // one, so a disabled control must never end up with an empty explanation.
    function test_seekDisabledReasonIsNeverEmpty() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        var progress = findChild(view, "progressControl");
        var oversized = endpoint();
        oversized.seekUnavailableReason = "track-id-oversized";
        oversized.lengthSeconds = 200;
        facade.selectedEndpoint = oversized;
        waitForRendering(view);
        verify(progress.disabledReason.indexOf("ID is too long") >= 0, progress.disabledReason);
        var unknownLength = endpoint();
        unknownLength.seekUnavailableReason = "";
        unknownLength.lengthSeconds = 0;
        facade.selectedEndpoint = unknownLength;
        waitForRendering(view);
        verify(progress.disabledReason.length > 0, "an ordinary source lost its reason");
        verify(progress.disabledReason.indexOf("Duration unknown") >= 0, progress.disabledReason);
        facade.selectedEndpoint = endpoint();
    }

    function test_albumAndTruncationMarkerArePresenceGated() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        var baseline = design.panelHeight(view.width);
        var album = findChild(view, "albumLine");
        var marker = findChild(view, "truncationMarker");
        var bare = endpoint();
        bare.presentation.album = "";
        bare.presentationTruncated = false;
        facade.selectedEndpoint = bare;
        waitForRendering(view);
        verify(!album.visible, "an absent album must not render");
        verify(!marker.visible, "the truncation marker must not render when nothing was trimmed");
        compare(design.panelHeight(view.width), baseline);
        var rich = endpoint();
        rich.presentation.album = "An Album Name";
        rich.presentationTruncated = true;
        facade.selectedEndpoint = rich;
        waitForRendering(view);
        verify(album.visible && album.text === "An Album Name", album.text);
        verify(marker.visible, "trimmed metadata must be marked rather than shown as complete");
        compare(design.panelHeight(view.width), baseline, "the album line changed the window height");
        facade.selectedEndpoint = endpoint();
    }

    // Reduced motion zeroes every duration token, which disables the Behaviors
    // outright, so state changes settle in the same frame.
    function test_reducedMotionDisablesStateTransitions() {
        design.reducedMotion = true;
        compare(design.feedbackDuration, 0);
        compare(design.expandDuration, 0);
        compare(design.collapseDuration, 0);
        compare(design.openDuration, 0);
        compare(design.closeDuration, 0);
        compare(design.peekInDuration, 0);
        compare(design.tintDuration, 0);
        compare(design.lyricLineDuration, 0);
        verify(design.trackPeekDuration > 0, "the track peek is an intent timing, not shortened by reduced motion");
        verify(design.powerPeekDuration > 0, "the power peek is an intent timing, not shortened by reduced motion");
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        facade.actionError = "error";
        waitForRendering(view);
        var message = findChild(view, "actionErrorMessage");
        compare(message.opacity, 1, "the error line did not settle immediately");
        facade.actionError = "";
        design.reducedMotion = false;
    }

    // The whole point of the overlay: switching source no longer blanks the
    // player, and the controls underneath go inert rather than staying live.
    function test_sourceOverlayKeepsTheHeaderAndInertsTheStage() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        waitForRendering(view);
        var title = findChild(view, "trackTitle");
        var play = findChild(view, "expandedPlayButton");
        var progress = findChild(view, "progressControl");
        verify(title.visible && play.enabled);
        view.content.pickerOpen = true;
        waitForRendering(view);
        var overlay = findChild(view, "sourceOverlay");
        verify(overlay, "the source overlay did not load");
        verify(title.visible, "the header disappeared behind the overlay");
        verify(!play.enabled, "a transport control stayed live under the overlay");
        verify(!progress.actionEnabled, "the scrubber stayed live under the overlay");
        verify(overlay.mapToItem(view, 0, 0).y > title.mapToItem(view, 0, 0).y,
            "the overlay covered the header");
        verify(overlay.mapToItem(view, 0, overlay.height).y <= view.height + 1,
            "the overlay ran past the card");
        view.content.pickerOpen = false;
        waitForRendering(view);
        verify(play.enabled, "the stage stayed inert after the overlay closed");
    }

    function openSettings() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        view.content.settingsOpen = true;
        waitForRendering(view);
        return view;
    }
    function test_sleepTimerArmsAndCancelsThroughTheCoordinator() {
        var view = openSettings();
        var fifteen = findChild(view, "sleepOption15");
        verify(fifteen);
        verify(fifteen.enabled);
        // Settings scroll; focusing the option reveals it before the click.
        fifteen.forceActiveFocus(Qt.TabFocusReason);
        waitForRendering(view);
        mouseClick(fifteen);
        compare(facade.armedMinutes, [15]);
        var status = findChild(view, "sleepStatus");
        compare(status.text, "Pauses at 23:05. Locking the screen cancels it.");
        var off = findChild(view, "sleepOption0");
        off.forceActiveFocus(Qt.TabFocusReason);
        waitForRendering(view);
        mouseClick(off);
        compare(facade.sleepDeadline, 0);
        compare(status.text, "Playback keeps going until you stop it.");
    }
    function test_sleepTimerSaysWhenTheLockCannotBeSeen() {
        facade.sleepLockVerified = false;
        facade.sleepDeadline = new Date(2026, 8, 23, 7, 30).getTime();
        var view = openSettings();
        compare(findChild(view, "sleepStatus").text,
            "Pauses at 7:30. The screen lock cannot be seen here, so it keeps running if you lock.");
    }
    function test_sleepTimerIsDisabledWithAReason() {
        facade.sleepArmable = false;
        var view = openSettings();
        var thirty = findChild(view, "sleepOption30");
        verify(!thirty.actionEnabled);
        compare(thirty.disabledReason, "This source cannot be paused");
        verify(findChild(view, "sleepOption0").actionEnabled, "Off stays reachable");
        mouseClick(thirty);
        compare(facade.armedMinutes, []);
        facade.selectedEndpoint = null;
        compare(thirty.disabledReason, "Choose a source first");
    }
    function test_settingsScrollsAndRevealsFocus_data() {
        return [{tag: "384-12", panelWidth: 384, body: 12}, {tag: "256-16", panelWidth: 256, body: 16}];
    }
    function test_settingsScrollsAndRevealsFocus(data) {
        design.theme = ({bodySize: data.body, titleSize: data.body + 2, captionSize: data.body - 1});
        var view = createTemporaryObject(islandComponent, test, {width: data.panelWidth});
        view.content.expanded = true;
        view.content.settingsOpen = true;
        waitForRendering(view);
        var scroller = findChild(view, "settingsScroller");
        var column = findChild(view, "settingsColumn");
        verify(scroller.y + scroller.height <= view.height, "the scroller stays on the card");
        verify(column.implicitHeight > scroller.height, "this layout needs scrolling at this size");
        compare(scroller.ScrollBar.vertical.policy, ScrollBar.AlwaysOn);
        var flick = scroller.contentItem;
        flick.contentY = column.implicitHeight - flick.height;
        waitForRendering(view);
        var first = findChild(view, "setting-remoteArtwork");
        verify(first.mapToItem(scroller, 0, 0).y < 0, "the first switch starts scrolled out of view");
        first.forceActiveFocus(Qt.TabFocusReason);
        waitForRendering(view);
        var top = first.mapToItem(scroller, 0, 0).y;
        verify(top >= 0 && top + first.height <= scroller.height,
            "focused switch is inside the viewport: " + top + " of " + scroller.height);
    }
    function test_settingsRowsIncludeNewSwitches() {
        var view = openSettings();
        function switches() {
            var found = [];
            function walk(item) {
                for (var i = 0; i < item.children.length; ++i) {
                    var child = item.children[i];
                    if (child.objectName && String(child.objectName).indexOf("setting-") === 0)
                        found.push(child);
                    walk(child);
                }
            }
            walk(view);
            return found;
        }
        compare(switches().length, 11, "every settings boolean must have its own switch");
        var lyrics = findChild(view, "setting-lyrics");
        verify(lyrics, "the lyrics switch must exist");
        compare(lyrics.checked, false, "lyrics stays off with the default facade");
        // Settings scroll; focusing the last row reveals it before the click.
        lyrics.forceActiveFocus(Qt.TabFocusReason);
        waitForRendering(view);
        mouseClick(lyrics);
        compare(facade.lyrics, true, "toggling the switch must call configure({lyrics:true})");
        facade.lyrics = false;
    }
    function test_settingDescriptionsAreNeverCut_data() {
        return [{tag: "384-12", panelWidth: 384, body: 12}, {tag: "256-16", panelWidth: 256, body: 16}];
    }
    function test_settingDescriptionsAreNeverCut(data) {
        design.theme = ({bodySize: data.body, titleSize: data.body + 2, captionSize: data.body - 1});
        var view = createTemporaryObject(islandComponent, test, {width: data.panelWidth});
        view.content.expanded = true;
        view.content.settingsOpen = true;
        waitForRendering(view);
        var keys = ["remoteArtwork", "autoShow", "reducedMotion", "highContrast", "island", "hud",
            "visualizer", "peek", "power", "tint", "lyrics"];
        for (var i = 0; i < keys.length; ++i) {
            var row = findChild(view, "setting-" + keys[i]);
            var description = findChild(view, "settingDescription-" + keys[i]);
            verify(row && description, keys[i]);
            verify(!description.truncated, keys[i] + " description is cut");
            var box = description.mapToItem(row, 0, 0, description.width, description.height);
            verify(box.y + box.height <= row.height, keys[i] + " description overflows its row");
        }
        verify(findChild(view, "settingDescription-lyrics").lineCount > 1,
            "the lyrics disclosure wraps rather than hiding the fields it lists");
    }
    function test_playerShowsTheSleepDeadlineAndYieldsToErrors() {
        var view = createTemporaryObject(islandComponent, test);
        view.content.expanded = true;
        waitForRendering(view);
        var indicator = findChild(view, "sleepIndicator");
        verify(indicator);
        verify(!indicator.visible, "nothing is shown while disarmed");
        facade.sleepDeadline = new Date(2026, 8, 23, 23, 5).getTime();
        verify(indicator.visible);
        compare(indicator.text, "Pauses at 23:05");
        facade.actionError = "busy";
        verify(!indicator.visible, "the error line takes the band");
        facade.actionError = "";
        facade.sleepFailure = "source-changed";
        compare(indicator.text, "The sleep timer could not pause: that source is gone.");
    }
}
