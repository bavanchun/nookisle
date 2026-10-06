import QtQuick
import QtTest
import "../../components"
import "../../qml/HeaderSlots.js" as HeaderSlots

TestCase {
    id: test
    name: "IslandSurface"
    // Wider than the surface itself, so a point exists that is outside the
    // surface's own bounds: the only way to leave the hit region while it
    // covers the full window (the expanded state).
    width: 760
    height: 420
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
        property bool lyrics: false
        property string spectrumState: "off"
        property var spectrumLevels: []
        property bool islandPointerActive: false
        property var fileSettings: ({})
        property var calendarSource: null
        property var shelfItems: []
        property var shelfEntries: []
        property string shelfNotice: ""
        property var shelfActions: null
        property var addedUris: []
        property int shelfAddResult: -1
        function shelfAddDrop(urls, text) {
            addedUris = addedUris.concat(urls);
            return urls.length;
        }
        function shelfAdd(uris) {
            addedUris = addedUris.concat(uris);
            return shelfAddResult < 0 ? uris.length : shelfAddResult;
        }
        property bool sleepArmable: true
        property bool sleepLockVerified: true
        property double sleepDeadline: 0
        property string sleepFailure: ""
        property var armedMinutes: []
        property bool timersEnabled: false
        property bool timersAvailable: true
        property var timerList: []
        property var startedTimers: []
        property var cancelledTimers: []
        property bool recordingShown: false
        property var recordingState: ({ active: false, startedAt: 0, path: "" })
        property int recordingStops: 0
        function stopRecording() {
            recordingStops++;
            return true;
        }
        function startTimer(minutes, label) {
            startedTimers = startedTimers.concat([{ minutes: minutes, label: label }]);
            return "ok";
        }
        function cancelTimer(unit) {
            cancelledTimers = cancelledTimers.concat([unit]);
            return "ok";
        }
        property var settingsSections: []
        function openSettings(section) {
            settingsSections = settingsSections.concat([section]);
            return true;
        }
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
    // Shaped like LyricsSource, as the Lyrics view reads it.
    QtObject {
        id: lyricsFixture
        property bool lyricsEnabled: true
        property string lyricsState: "idle"
        property string errorCode: ""
        property var lines: []
        property int currentIndex: -1
        property var meta: ({ title: "Afterglow" })
        property int retries: 0
        function retry() {
            retries++;
        }
    }
    Component {
        id: surfaceComponent
        IslandSurface {
            tokens: design
            coordinator: facade
            pillHeight: 56
            width: design.notchWindowWidth()
            height: design.notchWindowHeight()
        }
    }
    Component {
        id: livePillComponent
        IslandSurface {
            tokens: design
            coordinator: facade
            // The live bar size on this host: the fixture's default 56 px
            // would hide a spectrum that overflows the real pill.
            pillHeight: 26
            width: design.notchWindowWidth()
            height: design.notchWindowHeight()
        }
    }
    Component {
        id: artFixtureComponent
        Rectangle {
            width: 96
            height: 96
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#f0795a" }
                GradientStop { position: 0.55; color: "#c2417a" }
                GradientStop { position: 1; color: "#5a2d91" }
            }
            Rectangle {
                x: 30
                y: 22
                width: 42
                height: 42
                radius: 21
                color: "#ffd166"
                opacity: 0.85
            }
        }
    }
    // A slice of desktop for the peek previews: a wallpaper with a bar strip
    // along the top, the island centred over it as on the live bar.
    Component {
        id: peekStageComponent
        Rectangle {
            id: stage
            property alias surface: stageSurface
            width: 760
            height: 96
            gradient: Gradient {
                GradientStop { position: 0; color: "#3a4256" }
                GradientStop { position: 1; color: "#232838" }
            }
            Rectangle {
                width: parent.width
                height: 26
                color: "#101217"
            }
            IslandSurface {
                id: stageSurface
                x: Math.round((stage.width - width) / 2)
                tokens: design
                coordinator: facade
                pillHeight: 26
                width: design.notchWindowWidth()
                height: design.notchWindowHeight()
            }
        }
    }
    function ramp() {
        var levels = [];
        for (var i = 0; i < design.spectrumBands; ++i)
            levels.push(i * 6);
        return levels;
    }
    function bars(surface) {
        var list = [];
        for (var i = 0; i < design.spectrumBands; ++i)
            list.push(findChild(surface, "spectrumBar" + i));
        return list;
    }
    // The art fixture saved as a cover file, for an endpoint's artworkPath.
    function coverPath() {
        var art = createTemporaryObject(artFixtureComponent, test);
        waitForRendering(art);
        var path = Qt.resolvedUrl("../../build/ui-preview/pill-art-fixture.png").toString().slice(7);
        grabImage(art).save(path);
        art.destroy();
        return path;
    }
    function endpoint() {
        return {
            token: { owner: "fixture" },
            trackToken: { id: "track" },
            status: "Playing",
            positionSeconds: 74,
            lengthSeconds: 245,
            volume: 0.6,
            artworkPath: "",
            presentation: {
                title: "Test track",
                artists: ["Test artist"],
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
        mouseMove(test, 5, test.height - 5);
        design.artColor = "transparent";
        facade.panelAllowed = true;
        facade.uiAllowed = true;
        facade.selectedEndpoint = endpoint();
        facade.endpoints = [facade.selectedEndpoint];
        facade.actionError = "";
        facade.statusText = "";
        facade.pinUnavailable = false;
        facade.selectionMode = "auto";
        facade.selectedLabel = "Spotify";
        facade.shelfItems = [];
        facade.shelfAddResult = -1;
        facade.shelfEntries = [];
        facade.fileSettings = ({});
        facade.sleepDeadline = 0;
        facade.timersEnabled = false;
        facade.timersAvailable = true;
        facade.timerList = [];
        facade.startedTimers = [];
        facade.cancelledTimers = [];
        facade.recordingShown = false;
        facade.recordingState = { active: false, startedAt: 0, path: "" };
        facade.recordingStops = 0;
        facade.calendarSource = null;
        facade.settingsSections = [];
        facade.addedUris = [];
        facade.visualizer = true;
        facade.lyrics = false;
        lyricsFixture.lyricsEnabled = true;
        lyricsFixture.lyricsState = "idle";
        lyricsFixture.errorCode = "";
        lyricsFixture.lines = [];
        lyricsFixture.currentIndex = -1;
        lyricsFixture.meta = ({ title: "Afterglow" });
        lyricsFixture.retries = 0;
        facade.spectrumState = "off";
        facade.spectrumLevels = [];
        facade.remoteArtwork = false;
        facade.positionSeconds = 74;
        design.light = false;
        design.highContrast = false;
        design.theme = ({});
        design.reducedMotion = true;
    }
    function pillPoint(surface) {
        return { x: surface.width / 2, y: surface.pillHeight / 2 };
    }
    // Outside the pill but still inside the collapsed hit region's parent.
    function outsidePoint() {
        return { x: 4, y: 4 };
    }
    // Outside the surface entirely, so it also leaves the hit region while
    // expanded (the expanded hit region covers the whole surface).
    function farPoint() {
        return { x: test.width - 4, y: 4 };
    }
    function test_hoverDwellExpands() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        wait(surface.hoverDwell / 3);
        compare(surface.expanded, false);
        tryCompare(surface, "expanded", true, surface.hoverDwell + 200);
        mouseMove(test, outsidePoint().x, outsidePoint().y);
    }
    function test_hoverCanBeDisabledWithoutDisablingClick() {
        facade.fileSettings = ({ openOnHover: false, hoverDwell: 20 });
        var surface = createTemporaryObject(surfaceComponent, test);
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        wait(80);
        compare(surface.expanded, false);
        mouseClick(surface, p.x, p.y);
        compare(surface.expanded, true);
    }
    function test_closeChoosesShelfOnlyWhenPopulatedOrRemembered() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        verify(surface.collapse());
        compare(surface.view, "home", "empty Shelf returns to Home by default");
        facade.shelfEntries = [{ id: "item", kind: "text", text: "note", name: "note", addedAt: 1 }];
        surface.expandTo("home");
        verify(surface.collapse());
        compare(surface.view, "shelf", "populated Shelf takes the next open by default");
        facade.fileSettings = ({ openShelfByDefault: false });
        surface.expandTo("shelf");
        verify(surface.collapse());
        compare(surface.view, "home", "the Shelf preference is independent of its contents");
        facade.fileSettings = ({ openShelfByDefault: false, rememberLastTab: true });
        surface.expandTo("shelf");
        verify(surface.collapse());
        compare(surface.view, "shelf", "remembering the tab restores Shelf when opted in");
    }
    // A drag every route would take with the shelf on, so that only the
    // shelf setting can refuse it below.
    function validDrag() {
        return { hasUrls: true, hasText: false, urls: ["file:///tmp/shelf-off.txt"],
            supportedActions: Qt.CopyAction | Qt.MoveAction, proposedAction: Qt.CopyAction,
            accepted: false, accept: function (action) { this.accepted = true; this.acceptedAction = action; } };
    }
    // Escape on the Shelf tab closes an open battery popover first, as it
    // does on Home, before the shelf's own Escape ladder.
    function test_shelfEscapeClosesTheBatteryPopoverFirst() {
        facade.shelfEntries = [{ id: "s1", kind: "text", text: "note", name: "note", addedAt: 1, temp: false }];
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        var shelf = findChild(surface, "shelfView");
        tryVerify(function () { return shelf !== null; }, 1000);
        surface.batteryPopoverOpen = true;
        shelf.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(surface.batteryPopoverOpen, false, "the popover closes first");
        verify(surface.expanded, "and the island stays open");
        compare(surface.view, "shelf");
        shelf.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "the next Escape reaches the shelf, which collapses");
        facade.shelfEntries = [];
    }
    function test_disablingShelfRemovesTabViewAndDropRoute() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.barCentreSpan = 1200;
        var dropArea = findChild(surface, "islandDropArea");
        // With the shelf on, each route takes the drag.
        verify(surface.catchZone.width > 0, "the catch zone exists with the shelf on");
        verify(dropArea.enabled);
        verify(surface.handleCatchEnter(validDrag()));
        surface.collapse(true);
        verify(surface.handleBodyEnter(validDrag()));
        surface.collapse(true);
        verify(surface.handleDrop(validDrag()));
        compare(facade.addedUris.length, 1);
        surface.expandTo("shelf");
        verify(findChild(surface, "shelfView"));
        facade.fileSettings = ({ shelfEnabled: false });
        compare(surface.views, ["home"]);
        compare(surface.view, "home");
        compare(findChild(surface, "viewShelfButton"), null);
        tryVerify(function () { return findChild(surface, "shelfView") === null; }, 1000);
        surface.expandTo("shelf");
        compare(surface.view, "home");
        surface.collapse(true);
        // With it off, the same drags find no target and add nothing.
        compare(surface.catchZone.width, 0, "no catch zone, so a drag never grows the input region");
        verify(!dropArea.enabled, "the body drop area is off");
        var drag = validDrag();
        verify(!surface.handleCatchEnter(drag));
        verify(!drag.accepted);
        verify(!surface.handleBodyEnter(validDrag()));
        verify(!surface.handleDrop(validDrag()));
        compare(facade.addedUris.length, 1, "nothing was shelved");
        compare(surface.expanded, false, "no drag opened the island");
    }
    function test_quickPassDoesNotExpand() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        wait(40);
        mouseMove(test, outsidePoint().x, outsidePoint().y);
        wait(surface.hoverDwell + 100);
        compare(surface.expanded, false);
    }
    function test_leaveGraceCollapses() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        mouseMove(test, farPoint().x, farPoint().y);
        tryCompare(surface, "expanded", false, surface.leaveGrace + 250);
    }
    function test_reentryWithinGraceKeepsOpen() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        mouseMove(test, farPoint().x, farPoint().y);
        wait(surface.leaveGrace / 2);
        mouseMove(surface, p.x, p.y);
        wait(surface.leaveGrace + 100);
        compare(surface.expanded, true);
        mouseMove(test, farPoint().x, farPoint().y);
    }
    // A passing drag (a button held down while the pointer crosses the pill)
    // must not open the island. The offscreen QTest synthetic mouse-move
    // pipeline does not carry a pressed button through a passively observed
    // HoverHandler point (verified against a bare HoverHandler and against
    // QTest's own mouseDrag helper, both stuck at Qt.NoButton, while a
    // MouseArea in the same scene correctly observes the held button), so this
    // exercises the extracted predicate the handler calls directly.
    function test_pressedButtonBlocksHover() {
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.allowsHoverExpand(Qt.LeftButton), false,
            "a held button must block a hover-driven expand");
        compare(surface.allowsHoverExpand(Qt.NoButton), true);
    }
    function test_tapExpandsImmediately() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var p = pillPoint(surface);
        mouseClick(surface, p.x, p.y);
        tryCompare(surface, "expanded", true, 200);
        mouseMove(test, outsidePoint().x, outsidePoint().y);
    }
    function test_explicitOpenIgnoresLeave() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.explicitOpen = true;
        surface.expandTo("home");
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        mouseMove(test, farPoint().x, farPoint().y);
        wait(surface.leaveGrace + 200);
        compare(surface.expanded, true);
        surface.explicitOpen = false;
    }
    function test_interactingDefersCollapse() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        waitForRendering(surface);
        var progress = findChild(surface, "progressControl");
        verify(progress);
        progress.gesturing = true;
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        mouseMove(test, farPoint().x, farPoint().y);
        wait(surface.leaveGrace + 200);
        compare(surface.expanded, true, "an in-flight gesture must defer the collapse");
        progress.gesturing = false;
        tryCompare(surface, "expanded", false, surface.leaveGrace + 250);
    }
    function test_hitShapeJumpsNotAnimates() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        compare(surface.hitShape.height, surface.restHeight);
        var card = findChild(surface, "islandCard");
        verify(card.height < surface.restHeight, "the card must still be mid-morph while the mask already jumped");
        tryCompare(card, "height", surface.restHeight, 500);
        design.reducedMotion = true;
    }
    // Samples the notch every few ms for `duration` ms.
    function sampleCard(card, duration) {
        var samples = [];
        var elapsed = 0;
        while (elapsed < duration) {
            wait(8);
            elapsed += 8;
            samples.push({ width: card.width, height: card.height });
        }
        return samples;
    }
    // boring.notch's open spring (response 0.42, damping 0.8) overshoots by
    // about 1.5 % of its travel, into the slack below the rest height.
    function test_openSpringOvershootsUnderTwoPercent() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        surface.expandTo("home");
        var samples = sampleCard(card, design.openDuration + 100);
        var maxHeight = card.height;
        for (var i = 0; i < samples.length; ++i)
            maxHeight = Math.max(maxHeight, samples[i].height);
        var overshoot = (maxHeight - surface.restHeight) / (surface.restHeight - surface.pillHeight);
        verify(overshoot > 0, "the open spring overshoots past the rest height");
        verify(overshoot < 0.02, "by under 2 % of the travel, not " + overshoot);
        verify(maxHeight <= surface.restHeight + design.morphSlack, "the overshoot stays inside the slack");
        compare(card.height, surface.restHeight, "the notch settles back at the rest height");
        design.reducedMotion = true;
    }
    // The close spring is critically damped: it never dips below the closed
    // height, and it never turns back on its way there.
    function test_collapseHasNoOvershoot() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        tryCompare(surface, "expansion", 1, design.openDuration + 300);
        var card = findChild(surface, "islandCard");
        surface.collapse();
        var samples = sampleCard(card, design.closeDuration + 100);
        var previous = surface.restHeight;
        for (var i = 0; i < samples.length; ++i) {
            verify(samples[i].height >= surface.pillHeight, "collapse never dips below the closed height");
            verify(samples[i].height <= previous + 1e-6, "collapse never turns back");
            previous = samples[i].height;
        }
        compare(card.height, surface.pillHeight);
        compare(card.width, design.liveWidth);
        design.reducedMotion = true;
    }
    // A reversal mid-flight starts the close spring from where the open one
    // is, so the notch does not jump.
    function test_reversalMidFlightIsContinuous() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        surface.expandTo("home");
        tryVerify(function () { return surface.expansion > 0.4; }, design.openDuration, "the open spring is under way");
        var before = { width: card.width, height: card.height };
        surface.collapse();
        verify(Math.abs(card.height - before.height) <= 1, "the height carries on from where it was");
        verify(Math.abs(card.width - before.width) <= 1, "and so does the width");
        var samples = sampleCard(card, 48);
        var last = before.height;
        for (var i = 0; i < samples.length; ++i) {
            verify(Math.abs(samples[i].height - last) <= 16, "no frame leaps");
            last = samples[i].height;
        }
        tryCompare(card, "height", surface.pillHeight, design.closeDuration + 200);
        surface.expandTo("home");
        compare(card.height, surface.pillHeight, "a reopen starts from the closed notch too");
        tryCompare(card, "height", surface.restHeight, design.openDuration + 200);
        design.reducedMotion = true;
    }
    function test_cardWidthNeverExceedsWindow() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        surface.expandTo("home");
        var samples = sampleCard(card, design.openDuration + 100);
        for (var i = 0; i < samples.length; ++i)
            verify(samples[i].width <= design.openWidth, "the width never overshoots the open width");
        compare(card.width, design.openWidth);
        verify(card.x >= design.shadowPad - 1e-6 && card.x + card.width <= surface.width - design.shadowPad + 1e-6,
            "the open notch leaves the shadow room free on both sides");
        design.reducedMotion = true;
    }
    // Every width is clamped to the screen less a gap on each side.
    function test_widthsClampToTheScreen() {
        var surface = createTemporaryObject(surfaceComponent, test, { availableWidth: 400 });
        var card = findChild(surface, "islandCard");
        compare(card.width, design.liveWidth);
        surface.expandTo("home");
        compare(card.width, 400);
        compare(surface.hitShape.width, 400 - 2 * design.flareOpen);
        compare(design.notchWindowWidth(400), 400 + 2 * design.gap);
        compare(design.notchWindowWidth(2000), design.openWidth + 2 * design.shadowPad);
        surface.availableWidth = 200;
        surface.collapse();
        compare(card.width, 200, "the closed notch is clamped too");
    }
    function test_contentFadeAndScale() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var column = findChild(surface, "expandedColumn");
        surface.expansion = design.contentFadeStart;
        compare(column.opacity, 0);
        fuzzyCompare(column.scale, design.openScaleFrom + (1 - design.openScaleFrom) * design.contentFadeStart, 1e-9);
        compare(column.transformOrigin, Item.Top);
        surface.expansion = 0.01;
        verify(column.scale < 0.81, "the content grows from 80 %");
        surface.expansion = 1;
        compare(column.opacity, 1);
        compare(column.scale, 1);
        compare(column.entranceBlur, 0);
    }
    function test_slackIsNotHitShape() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        compare(surface.hitShape.height, surface.restHeight);
        verify(surface.restHeight < surface.height, "the window must keep a slack strip above restHeight");
    }
    // The notch outline in both states: the body is the notch colour right
    // up to the top edge, the flares curve out to meet it, and the bottom
    // corners are rounded.
    function test_notchOutlineFlaresAndRoundBottom() {
        facade.selectedEndpoint = null;
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        var shape = findChild(surface, "notchShape");
        function check(state, flare, radius) {
            waitForRendering(surface);
            compare(shape.flare, flare, state + " flare");
            compare(shape.radius, radius, state + " bottom radius");
            var image = grabImage(card);
            function isNotch(x, y) {
                return Qt.colorEqual(image.pixel(x, y), design.notchColor);
            }
            verify(isNotch(shape.bodyLeft + radius, 0), state + ": the body meets the top edge");
            verify(isNotch(shape.bodyLeft - 1, 1), state + ": the left flare fills the corner beside the body");
            verify(isNotch(shape.bodyRight, 1), state + ": and so does the right one");
            verify(!isNotch(1, flare - 2), state + ": the left flare curves out, clear beneath");
            verify(!isNotch(card.width - 2, flare - 2), state + ": the right flare too");
            verify(!isNotch(shape.bodyLeft, card.height - 1), state + ": bottom-left is rounded");
            verify(!isNotch(shape.bodyRight - 1, card.height - 1), state + ": bottom-right is rounded");
            verify(isNotch(card.width / 2, card.height - 2), state + ": the body is filled to its bottom edge");
        }
        check("closed", design.flareClosed, design.bottomRadiusClosed);
        surface.expandTo("home");
        check("open", design.flareOpen, design.bottomRadiusOpen);
    }
    // The fill is the notch colour, and without GPU effects the edge is the
    // theme hairline and no effect is ever created.
    function test_softwareFallbackDrawsHairline() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var shape = findChild(surface, "notchShape");
        compare(design.gpuEffects, false);
        compare(shape.fillColor, design.notchColor);
        compare(shape.edgeColor, design.stroke);
        compare(findChild(surface, "notchShadowLoader").item, null);
        compare(findChild(surface, "notchBody").clip, true, "the body clips its content");
        compare(findChild(surface, "notchBody").layer.enabled, false);
        surface.expandTo("home");
        compare(findChild(surface, "expandedColumn").layer.enabled, false);
    }
    // With GPU effects the shadow, the mask and the entrance blur exist and
    // follow the shape; they are not rendered offscreen.
    function test_gpuEffectsCreateTheEffects() {
        var surface = createTemporaryObject(surfaceComponent, test);
        design.gpuEffects = true;
        var shape = findChild(surface, "notchShape");
        var body = findChild(surface, "notchBody");
        var loader = findChild(surface, "notchShadowLoader");
        verify(loader.item, "the shadow is created");
        compare(loader.visible, false, "and hidden while closed");
        compare(shape.edgeColor, Qt.color("transparent"), "the shadow replaces the hairline");
        compare(body.layer.enabled, false, "the settled closed notch takes no mask layer");
        compare(body.clip, true, "it clips to the body rectangle instead");
        surface.peekActive = true;
        compare(body.layer.enabled, true, "a peek is masked by the shape");
        compare(body.clip, false);
        surface.peekActive = false;
        compare(body.layer.enabled, false);
        surface.expandTo("home");
        compare(body.layer.enabled, true, "the open body is masked by the shape");
        compare(body.clip, false);
        var shadow = loader.item;
        compare(loader.visible, true, "the shadow shows while open");
        compare(shadow.topLeftRadius, 0);
        compare(shadow.topRightRadius, 0);
        compare(shadow.bottomLeftRadius, shape.radius);
        compare(shadow.bottomRightRadius, shape.radius);
        compare(shadow.blur, design.shadowBlur);
        compare(shadow.spread, 0);
        compare(shadow.offset, Qt.vector2d(0, design.shadowOffset));
        verify(Qt.colorEqual(shadow.color, Qt.rgba(0, 0, 0, 0.7)));
        compare(loader.x, shape.bodyLeft, "under the body, not the flares");
        compare(loader.width, shape.bodyWidth);
        var column = findChild(surface, "expandedColumn");
        compare(column.layer.enabled, false, "a settled notch has no blur layer");
        surface.expansion = 0.6;
        verify(column.entranceBlur > 0);
        compare(column.layer.enabled, true, "the entrance blur shows mid-morph");
        surface.expansion = 1;
        surface.collapse();
        compare(body.layer.enabled, false, "the mask goes once the notch has closed");
        design.gpuEffects = false;
        compare(loader.item, null, "turning effects off drops them");
    }
    function test_pointerActiveFollowsHoverAndExpansion() {
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.pointerActive, false);
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        tryCompare(surface, "pointerActive", true, 200);
        mouseMove(test, outsidePoint().x, outsidePoint().y);
        tryCompare(surface, "pointerActive", false, surface.leaveGrace + 250);
        surface.expandTo("home");
        compare(surface.pointerActive, true);
        surface.collapse();
    }
    function test_reducedMotionSettlesImmediately() {
        design.reducedMotion = true;
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        compare(surface.expansion, 1);
        surface.collapse();
        compare(surface.expansion, 0);
    }
    // The inline HUD takes both wings of a wider closed notch: its icon on
    // the left, its level on the right.
    // The inline HUD takes a wider closed notch: HudInline draws its icon
    // and label in the left wing and its bar in the right, over the music.
    function test_hudRowReplacesMusicRow() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var art = findChild(surface, "pillArtwork").visible ? findChild(surface, "pillArtwork") : findChild(surface, "pillMusicGlyph");
        var inline = findChild(surface, "hudInline");
        verify(art.visible && !inline.visible);
        compare(surface.closedModel.state, "live");
        surface.hud.show("volume", 0.5, false);
        waitForRendering(surface);
        compare(surface.closedModel.state, "hudInline");
        compare(findChild(surface, "islandCard").width, design.hudInlineWidth);
        verify(!art.visible && inline.visible);
        verify(findChild(inline, "hudIcon").visible && findChild(inline, "hudBar").visible);
        compare(surface.hitShape.width, design.liveWidth - 2 * design.flareClosed, "the notch body's input region stays put");
        surface.hud.active = false;
        compare(findChild(surface, "islandCard").width, design.liveWidth);
    }
    function test_hudLevelOver100Percent() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.hud.show("volume", 1.5, false);
        waitForRendering(surface);
        var bar = findChild(findChild(surface, "hudInline"), "hudBar");
        compare(bar.displayLevel, 1, "an over-amplified level fills the bar, never past it");
        surface.hud.active = false;
    }
    function test_escapeCollapses() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        surface.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false);
    }
    // A keyboard summon (Panel.qml's open()) expands the player view and
    // must focus its content so Escape collapses it immediately, exactly as
    // a host toggle or hide would.
    function test_escapeCollapsesPlayerViewAfterSummon() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.explicitOpen = true;
        surface.expandTo("home");
        surface.focusContent();
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "Escape must collapse a keyboard-summoned island in the Now playing view");
        surface.explicitOpen = false;
    }
    // Even when focus lands on the surface root itself rather than on the
    // loaded content, Escape must still collapse the island: the surface's
    // own handler is a fallback net for whichever view did not accept the
    // key.
    function test_escapeCollapsesWhenSurfaceItselfHasFocus() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.explicitOpen = true;
        surface.expandTo("home");
        surface.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false);
        surface.explicitOpen = false;
    }
    // The drop wiring itself, not just the facade's shelfAdd: this calls
    // IslandSurface's real handleDrop(), the function its DropArea's
    // onDropped actually invokes, rather than calling facade.shelfAdd from
    // the test the way tst-shelf.qml's test_dropAddsUrls does. A synthetic
    // JS object cannot be sent through the real `dropped` signal itself: it
    // is strongly typed to QQuickDragEvent*, which QtTest cannot construct.
    function test_dropDelegatesToRealSurfaceHandler() {
        var surface = createTemporaryObject(surfaceComponent, test);
        verify(findChild(surface, "islandDropArea"));
        var uris = ["file:///tmp/real-drop.txt"];
        var fakeEvent = {
            hasUrls: true,
            urls: uris,
            supportedActions: Qt.CopyAction | Qt.MoveAction,
            proposedAction: Qt.MoveAction,
            accepted: false,
            acceptedAction: Qt.IgnoreAction,
            accept: function (action) { this.accepted = true; this.acceptedAction = action; }
        };
        verify(surface.handleDrop(fakeEvent));
        compare(facade.addedUris, uris, "IslandSurface's own handleDrop() must reach the coordinator");
        verify(fakeEvent.accepted);
        compare(fakeEvent.acceptedAction, Qt.CopyAction, "a proposed Move is acknowledged as Copy");
        facade.shelfAddResult = 0;
        fakeEvent.accepted = true;
        verify(!surface.handleDrop(fakeEvent));
        verify(!fakeEvent.accepted, "a duplicate or full shelf does not claim the drop");
        facade.shelfAddResult = -1;
        fakeEvent.supportedActions = Qt.MoveAction;
        verify(!surface.handleDrop(fakeEvent));
        verify(!fakeEvent.accepted, "a Move-only drag is refused");
    }
    // The Shelf tab hosts the shelf strip, with room under it for its
    // refusal notice inside the open body.
    function test_shelfTabHostsShelfView() {
        facade.shelfNotice = "shelf-full";
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        var view = findChild(surface, "shelfView");
        verify(view, "the Shelf tab loads ShelfView");
        verify(findChild(surface, "shelfStrip"));
        verify(view.implicitHeight > 105, "the view asks for the strip plus its notice");
        verify(view.height >= view.implicitHeight, "the view gets the height it asks for");
        var notice = findChild(surface, "shelfStripNotice");
        verify(notice.visible);
        var bottom = notice.mapToItem(surface, 0, notice.height).y;
        verify(bottom <= surface.restHeight, "the notice sits inside the open body");
        verify(!findChild(surface, "islandDropArea").enabled, "drops on the Shelf tab go to the strip");
        surface.expandTo("home");
        verify(findChild(surface, "islandDropArea").enabled);
        facade.shelfNotice = "";
    }
    // ShelfView holds the real surface busy guard: a rename in progress
    // keeps the island open, and ending it releases the hold.
    function test_shelfBusyGuardIsTheSurface() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        var view = findChild(surface, "shelfView");
        compare(view.busyGuard, surface);
        compare(view.actions, facade.shelfActions);
        view.renamingId = "item-1";
        compare(surface.busyCount, 1);
        compare(surface.collapse(), false, "a held shelf keeps the island open");
        view.renamingId = "";
        compare(surface.busyCount, 0);
        verify(surface.collapse());
    }
    // A file held over the Share tile is shelf drag activity too: the leave
    // grace must not close the island under it. An offscreen test cannot
    // start a drag that carries URLs (an internal Drag reports no URLs, so
    // the tile rightly refuses it), so this stands in for the tile's
    // accepted-drag state, which is bound to its DropArea's containsDrag.
    function test_shareTileDropKeepsIslandOpen() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        var tile = findChild(surface, "shelfShareTile");
        verify(tile);
        compare(tile.dropActive, false);
        tile.dropActive = true;
        verify(surface.shelfDragActive, "a drag over the Share tile counts as shelf drag activity");
        verify(surface.interacting, "the leave grace defers while it is held");
        tile.dropActive = false;
        verify(!surface.interacting);
    }
    function test_shelfCollapseRequestAndDragActivity() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        var view = findChild(surface, "shelfView");
        view.draggingId = "item-1";
        verify(surface.interacting, "a drag out keeps the island open");
        view.draggingId = "";
        verify(!surface.interacting);
        view.collapseRequested();
        compare(surface.expanded, false);
    }
    // The catch zone: while collapsed, a bar-high drop region wider than
    // the closed body, centred on it. It is part of the input region only
    // then, and a drag entering it opens the Shelf tab.
    function test_catchZoneStates() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var zone = surface.catchZone;
        var body = surface.hitShape;
        compare(zone.width, 0, "no catch region until the bar's empty centre is measured");
        surface.barCentreSpan = 1200;
        compare(zone.width, Math.min(480, surface.openWidth - 2 * surface.flareOpen));
        verify(zone.width > body.width);
        compare(zone.height, surface.pillHeight);
        compare(zone.y, 0);
        compare(zone.x + zone.width / 2, body.x + body.width / 2);
        surface.expandTo("home");
        compare(zone.width, 0, "no catch region while open");
        surface.collapse();
        surface.barCentreShared = true;
        compare(zone.width, 0, "a shared bar centre gets no catch region");
        surface.barCentreShared = false;
        facade.fileSettings = { expandedDragDetection: false };
        compare(zone.width, 0, "the setting turns it off");
        facade.fileSettings = { dragCatchWidth: 300 };
        compare(zone.width, 300);
        facade.fileSettings = ({});
        surface.barCentreSpan = 360;
        compare(zone.width, 360, "a crowded bar limits the region to its empty centre");
        surface.barCentreSpan = 100;
        compare(zone.width, body.width, "a centre narrower than the body adds nothing beyond it");
        surface.barCentreSpan = 1200;
        surface.interactive = false;
        compare(zone.width, 0);
        surface.interactive = true;
    }
    function test_catchZoneDragOpensShelf() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.barCentreSpan = 1200;
        var drag = { hasUrls: true, hasText: false, supportedActions: Qt.CopyAction | Qt.MoveAction,
            accepted: false, acceptedAction: Qt.IgnoreAction,
            accept: function (action) { this.accepted = true; this.acceptedAction = action; } };
        verify(!surface.handleCatchEnter({ hasUrls: false, hasText: false, supportedActions: Qt.CopyAction }),
            "an empty drag is ignored");
        compare(surface.expanded, false);
        var catchWidth = surface.catchZone.width;
        verify(surface.handleCatchEnter(drag));
        compare(surface.expanded, true);
        compare(surface.view, "shelf");
        compare(surface.catchZone.width, catchWidth, "an active drag retains the catch target through expansion");
        verify(surface.catchZone.z > surface.hitShape.z, "the retained catch target stays above the opened body");
        compare(drag.acceptedAction, Qt.CopyAction);
        var dropped = { hasUrls: true, urls: ["file:///tmp/quick.txt"], supportedActions: Qt.CopyAction | Qt.MoveAction,
            accepted: false, accept: function (action) { this.accepted = true; this.acceptedAction = action; } };
        verify(surface.handleDrop(dropped), "a quick release reaches the original target");
        compare(dropped.acceptedAction, Qt.CopyAction);
        compare(surface.catchZone.width, 0, "the catch region leaves after the drop");
    }
    // A drag that only passes through the catch zone, or is cancelled there,
    // must not leave the island open: its exit restarts the leave grace.
    function test_catchZoneDragPassingThroughCloses() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.barCentreSpan = 1200;
        var drag = { hasUrls: true, hasText: false, supportedActions: Qt.CopyAction,
            accepted: false, accept: function (action) { this.accepted = true; this.acceptedAction = action; } };
        verify(surface.handleCatchEnter(drag));
        verify(surface.expanded && surface.view === "shelf");
        surface.handleCatchExit();
        compare(surface.catchDropHandoff, false, "the hand-off ends with the drag");
        tryCompare(surface, "expanded", false, surface.leaveGrace + 1000, "the leave grace closes the island");
    }
    function test_bodyDropTargetSurvivesShelfHandoff() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var dropArea = findChild(surface, "islandDropArea");
        var drag = { hasUrls: true, supportedActions: Qt.CopyAction, accepted: false,
            accept: function (action) { this.accepted = true; this.acceptedAction = action; } };
        verify(surface.handleBodyEnter(drag));
        verify(surface.expanded && surface.view === "shelf");
        verify(dropArea.enabled, "the original body target persists until release");
        var dropped = { hasUrls: true, urls: ["file:///tmp/quick.txt"], supportedActions: Qt.CopyAction,
            accepted: false, accept: function (action) { this.accepted = true; this.acceptedAction = action; } };
        verify(surface.handleDrop(dropped));
        compare(dropped.acceptedAction, Qt.CopyAction);
        verify(!dropArea.enabled, "the strip takes later drags");
    }
    // Only a drag uses the zone: hovering the empty bar beside the body
    // does not start the open dwell.
    function test_catchZoneIgnoresHover() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.barCentreSpan = 1200;
        var zone = surface.catchZone;
        var body = surface.hitShape;
        waitForRendering(surface);
        mouseMove(surface, zone.x + 4, zone.height / 2);
        verify(zone.x + 4 < body.x, "the point is outside the closed body");
        wait(surface.hoverDwell + 150);
        compare(surface.expanded, false);
    }
    function test_islandHeightIsPureFunctionOfWidth() {
        [384, 320, 256].forEach(function (width) {
            compare(design.islandHeight(width), design.bandSwitcher + design.panelHeight(width));
        });
    }
    function test_playStateGlyphStatic() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        var e = endpoint();
        e.status = "Paused";
        facade.selectedEndpoint = e;
        waitForRendering(surface);
        wait(200);
        var glyph = findChild(surface, "pauseGlyph");
        var before = glyph.children.map(function (bar) { return bar.height; });
        wait(200);
        var after = glyph.children.map(function (bar) { return bar.height; });
        compare(after, before, "the paused glyph must settle rather than animate perpetually");
        design.reducedMotion = true;
    }
    function test_pillShowsSpectrumWhenLive() {
        // Live bars need motion; init() reduces it for every other test.
        design.reducedMotion = false;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(surfaceComponent, test);
        waitForRendering(surface);
        var spectrum = findChild(surface, "spectrumBars");
        tryVerify(function () { return spectrum.visible; }, 1000, "the spectrum takes the trailing slot while live");
        verify(!findChild(surface, "playStateGlyph").visible, "the static glyph gives way to the bars");
        var list = bars(surface);
        verify(list[list.length - 1].height > list[0].height, "a rising ramp draws rising bars");
        compare(list[0].height, design.spectrumMinBar);
        verify(Qt.colorEqual(list[list.length - 1].color, surface.ink.tint), "live bars use the tint");
    }
    function test_spectrumFitsLivePillHeight() {
        facade.spectrumState = "running";
        var loud = [];
        for (var i = 0; i < design.spectrumBands; ++i)
            loud.push(99);
        facade.spectrumLevels = loud;
        var surface = createTemporaryObject(livePillComponent, test);
        waitForRendering(surface);
        var card = findChild(surface, "islandCard");
        var hairline = findChild(surface, "progressHairline");
        var hairlineTop = hairline.mapToItem(card, 0, 0).y;
        bars(surface).forEach(function (bar, index) {
            var box = bar.mapToItem(card, 0, 0, bar.width, bar.height);
            verify(box.height > design.spectrumMinBar, "bar " + index + " is lit");
            verify(box.x >= 0 && box.x + box.width <= card.width, "bar " + index + " stays inside the card horizontally");
            verify(box.y >= 0, "bar " + index + " stays below the card top");
            verify(box.y + box.height < hairlineTop, "bar " + index + " ends above the hairline");
        });
    }
    function test_spectrumSpanFollowsHairlineAndPillHeight() {
        facade.spectrumState = "running";
        var surface = createTemporaryObject(livePillComponent, test);
        waitForRendering(surface);
        var spectrum = findChild(surface, "spectrumBars");
        compare(surface.spectrumBarSpan, 14, "a 26 px pill with a hairline leaves 14 px of active bar travel");
        compare(surface.spectrumBarSpan, spectrum.maxHeight - design.spectrumMinBar);
        var e = endpoint();
        e.lengthSeconds = 0;
        facade.selectedEndpoint = e;
        compare(surface.spectrumBarSpan, 18, "without a hairline the same pill has 18 px of active travel");
        compare(surface.spectrumBarSpan, spectrum.maxHeight - design.spectrumMinBar);
        surface.pillHeight = 22;
        compare(surface.spectrumBarSpan, 16, "the reported span follows a shorter host bar too");
        compare(surface.spectrumBarSpan, spectrum.maxHeight - design.spectrumMinBar);
    }
    // Paused within the pause grace, the notch stays live with flat bars;
    // a track that was already paused leaves the notch idle.
    // Reduced motion shows the still play glyph where the bars would be.
    function test_reducedMotionShowsTheStillGlyph() {
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        design.reducedMotion = true;
        var surface = createTemporaryObject(surfaceComponent, test);
        waitForRendering(surface);
        verify(!findChild(surface, "spectrumBars").visible, "no live bars with reduced motion");
        verify(findChild(surface, "playStateGlyph").visible, "the still glyph takes their place");
        design.reducedMotion = false;
        verify(findChild(surface, "spectrumBars").visible, "motion allowed, the bars return");
    }
    function test_pillStaticWhenPaused() {
        // Live bars need motion; init() reduces it for every other test.
        design.reducedMotion = false;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(surfaceComponent, test);
        var e = endpoint();
        e.status = "Paused";
        facade.selectedEndpoint = e;
        waitForRendering(surface);
        compare(surface.closedModel.state, "live", "live through the pause grace");
        tryVerify(function () { return findChild(surface, "spectrumBars").visible; }, 1000);
        bars(surface).forEach(function (bar) {
            compare(bar.height, design.spectrumMinBar);
        });
        verify(!Qt.colorEqual(bars(surface)[0].color, surface.ink.tint), "paused bars are muted, not tinted");
    }
    // Bars step with each incoming line and hold still between lines: no
    // animation of their own, so nothing repaints faster than lines arrive.
    function test_barsStepWithEachLineAndHold() {
        design.reducedMotion = false;
        facade.spectrumState = "running";
        facade.spectrumLevels = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        var surface = createTemporaryObject(livePillComponent, test);
        waitForRendering(surface);
        var spectrum = findChild(surface, "spectrumBars");
        var bar = bars(surface)[8];
        compare(bar.height, design.spectrumMinBar);
        var peak = [];
        for (var i = 0; i < design.spectrumBands; ++i)
            peak.push(99);
        facade.spectrumLevels = peak;
        compare(bar.height, spectrum.maxHeight, "a new line sets the bar at once, with motion on");
        wait(150);
        compare(bar.height, spectrum.maxHeight, "without a new line the bar holds still");
        design.reducedMotion = true;
    }
    function test_pillFallsBackToGlyphWhenUnavailable() {
        facade.spectrumState = "unavailable";
        var surface = createTemporaryObject(surfaceComponent, test);
        waitForRendering(surface);
        verify(!findChild(surface, "spectrumBars").visible);
        verify(findChild(surface, "playStateGlyph").visible);
        facade.spectrumState = "off";
        facade.visualizer = false;
        verify(!findChild(surface, "spectrumBars").visible, "visualizer:false also restores the glyph");
        verify(findChild(surface, "playStateGlyph").visible);
    }
    function test_hairlineTracksPosition() {
        var e = endpoint();
        e.lengthSeconds = 120;
        facade.selectedEndpoint = e;
        facade.positionSeconds = 30;
        var surface = createTemporaryObject(livePillComponent, test);
        waitForRendering(surface);
        var hairline = findChild(surface, "progressHairline");
        var fill = findChild(surface, "progressHairlineFill");
        verify(hairline.visible);
        verify(Math.abs(fill.width - hairline.width / 4) <= 1, "30 of 120 s fills a quarter of the track");
        facade.positionSeconds = 500;
        compare(fill.width, hairline.width, "the fill is clamped to the track");
        var card = findChild(surface, "islandCard");
        var box = hairline.mapToItem(card, 0, 0, hairline.width, hairline.height);
        verify(box.x >= card.bottomRadius - 1 && box.x + box.width <= card.width - card.bottomRadius + 1,
            "the hairline is inset by the bottom radius");
        verify(box.y + box.height <= card.height - 2, "the hairline sits clear of the bottom edge");
    }
    function test_hairlineHiddenWithoutLength() {
        var e = endpoint();
        e.lengthSeconds = 0;
        facade.selectedEndpoint = e;
        var surface = createTemporaryObject(surfaceComponent, test);
        verify(!findChild(surface, "progressHairline").visible);
        facade.selectedEndpoint = null;
        verify(!findChild(surface, "progressHairline").visible);
    }
    function test_hairlineHiddenDuringHud() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var hairline = findChild(surface, "progressHairline");
        verify(hairline.visible);
        surface.hud.show("volume", 0.5, false);
        verify(!hairline.visible, "the HUD owns the closed notch while it shows");
        surface.hud.active = false;
        verify(hairline.visible);
    }
    // The closed notch's body: the flares are not part of it.
    function pillRect(surface) {
        var body = design.liveWidth - 2 * design.flareClosed;
        return { x: (surface.width - body) / 2, y: 0, width: body, height: surface.pillHeight };
    }
    // Inside the peek's body but outside the closed notch's body.
    function peekOnlyPoint(surface) {
        var closedBody = design.liveWidth - 2 * design.flareClosed;
        var peekBody = design.peekWidth - 2 * design.flareClosed;
        return { x: surface.width / 2 - (closedBody + peekBody) / 4, y: 10 };
    }
    function test_peekGrowsCardNotHitShape() {
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        surface.peekKind = "track";
        surface.peekActive = true;
        compare(card.width, design.peekWidth);
        compare(card.height, design.peekHeight);
        compare(card.bottomRadius, design.peekRadius);
        var pill = pillRect(surface);
        compare(surface.hitShape.x, pill.x);
        compare(surface.hitShape.y, pill.y);
        compare(surface.hitShape.width, pill.width);
        compare(surface.hitShape.height, pill.height, "the input region stays the pill during a peek");
        var p = peekOnlyPoint(surface);
        mouseClick(surface, p.x, p.y);
        wait(50);
        compare(surface.expanded, false, "a click on the peek body beyond the pill passes through");
        mouseClick(surface, p.x, surface.pillHeight + 20);
        wait(50);
        compare(surface.expanded, false, "so does a click on the peek below the bar");
    }
    function test_peekUnderRestingPointerDoesNotExpand() {
        var surface = createTemporaryObject(livePillComponent, test);
        var p = peekOnlyPoint(surface);
        mouseMove(surface, p.x, surface.pillHeight + 20);
        surface.peekKind = "track";
        surface.peekActive = true;
        wait(surface.hoverDwell + 100);
        compare(surface.expanded, false, "a peek appearing under a resting pointer never starts the dwell");
        compare(surface.pointerActive, false);
    }
    function test_peekKeepsPillTapAndHover() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekActive = true;
        var p = pillPoint(surface);
        mouseClick(surface, p.x, p.y);
        tryCompare(surface, "expanded", true, 200);
        mouseMove(test, outsidePoint().x, outsidePoint().y);
    }
    function test_powerPeekKeepsPillHeight() {
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        surface.peekKind = "power";
        surface.powerKind = "low";
        surface.powerLevel = 0.18;
        surface.peekActive = true;
        compare(card.width, design.peekWidth);
        compare(card.height, surface.pillHeight, "a power peek is a single closed-high row");
        compare(card.bottomRadius, design.bottomRadiusClosed);
        var peek = findChild(surface, "islandPeek");
        verify(peek.visible);
        verify(findChild(peek, "peekPowerRow").visible);
        verify(!findChild(peek, "peekTrackRow").visible);
        compare(findChild(peek, "peekPowerLabel").text, "Battery low");
        compare(findChild(peek, "peekPowerPercent").text, "18%");
        verify(Qt.colorEqual(findChild(peek, "peekPowerFill").color, design.error), "low battery uses the error colour");
        surface.powerKind = "plugged";
        compare(findChild(peek, "peekPowerLabel").text, "Charging");
        verify(Qt.colorEqual(findChild(peek, "peekPowerFill").color, design.charging), "charging reads green");
        verify(Qt.colorEqual(findChild(peek, "peekPowerPercent").color, design.charging));
        compare(findChild(peek, "peekPowerIcon").name, "bolt");
        compare(peek.Accessible.name, "Charging, 18 percent");
        compare(findChild(surface, "islandPill").opacity, 0, "the closed content gives way to the peek");
    }
    function test_powerPeekInkFollowsTheState() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekKind = "power";
        surface.powerLevel = 1;
        surface.powerKind = "plugged";
        surface.peekActive = true;
        var peek = findChild(surface, "islandPeek");
        compare(findChild(peek, "peekPowerLabel").text, "Fully charged");
        verify(Qt.colorEqual(findChild(peek, "peekPowerFill").color, design.charging), "full charge stays green");
        surface.powerKind = "unplugged";
        verify(Qt.colorEqual(findChild(peek, "peekPowerFill").color, design.text), "on battery is neutral");
        surface.powerKind = "critical";
        verify(Qt.colorEqual(findChild(peek, "peekPowerFill").color, design.error));
    }
    function test_plugInPulsesTheBoltOnce() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekKind = "power";
        surface.powerKind = "plugged";
        surface.powerLevel = 0.5;
        surface.peekActive = true;
        var peek = findChild(surface, "islandPeek");
        var pulse = findChild(peek, "peekBoltPulse");
        var icon = findChild(peek, "peekPowerIcon");
        var ring = findChild(peek, "peekBoltRing");
        tryVerify(function () { return pulse.running; }, 500, "a plug-in starts the pulse");
        tryVerify(function () { return icon.scale > 1.1; }, 500, "the bolt swells");
        tryCompare(pulse, "running", false, 1500, "the pulse is finite");
        compare(icon.scale, 1);
        compare(ring.opacity, 0);
        surface.powerKind = "low";
        verify(!pulse.running, "a battery warning never pulses");
    }
    function test_boltPulseSkippedUnderReducedMotion() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekKind = "power";
        surface.powerKind = "plugged";
        surface.powerLevel = 0.5;
        surface.peekActive = true;
        var peek = findChild(surface, "islandPeek");
        verify(peek.visible);
        verify(!findChild(peek, "peekBoltPulse").running);
        compare(findChild(peek, "peekPowerIcon").scale, 1);
    }
    function test_trackPeekShowsTheTrack() {
        // Live bars need motion; init() reduces it for every other test.
        design.reducedMotion = false;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekActive = true;
        var peek = findChild(surface, "islandPeek");
        tryVerify(function () { return peek.visible; }, 1000, "the peek blooms in");
        compare(findChild(peek, "peekTitle").text, "Test track");
        compare(findChild(peek, "peekArtists").text, "Test artist");
        compare(peek.Accessible.name, "Now playing: Test track by Test artist");
        var bars = findChild(peek, "peekSpectrum");
        tryVerify(function () { return bars.visible && bars.active; }, 1000, "the peek carries the live bars");
        surface.peekActive = false;
        tryVerify(function () { return !peek.visible; }, 1000, "the peek fades out");
        compare(bars.levels.length, 0, "a hidden peek stops following the spectrum");
    }
    function test_inlinePeekUsesTheClosedHeightAndSideLabels() {
        facade.fileSettings = ({ peekStyle: "inline" });
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekKind = "track";
        surface.peekActive = true;
        compare(surface.peekTargetHeight, surface.pillHeight);
        compare(surface.peekWidth, design.hudInlineWidth);
        var peek = findChild(surface, "islandPeek");
        verify(findChild(peek, "peekInlineTrack").visible);
        verify(!findChild(peek, "peekTrackRow").visible);
        compare(findChild(peek, "peekInlineTitle").text, "Test track");
        surface.peekKind = "power";
        compare(surface.peekWidth, design.peekWidth);
        verify(findChild(peek, "peekPowerRow").visible);
    }
    function test_hudAppearanceSettingsReachEveryStyle() {
        facade.fileSettings = ({ hudGradient: true, hudGlow: true, showPowerStatusIcons: false });
        var surface = createTemporaryObject(livePillComponent, test);
        var inline = findChild(surface, "hudInline");
        var below = findChild(surface, "hudBelow");
        var header = findChild(surface, "notchHeader");
        verify(inline.gradientEnabled && inline.glowEnabled);
        verify(below.gradientEnabled && below.glowEnabled);
        verify(!header.batteryStatusIcons);
        var capsule = findChild(header, "headerHud");
        verify(capsule.gradientEnabled && capsule.glowEnabled);
        facade.fileSettings = ({ hudGradient: false, hudGlow: false, showPowerStatusIcons: true });
        verify(!inline.gradientEnabled && !below.glowEnabled && !capsule.gradientEnabled);
        verify(header.batteryStatusIcons);
    }
    function test_settingsGearAndCustomAccent() {
        facade.fileSettings = ({ showSettingsIcon: false });
        var surface = createTemporaryObject(livePillComponent, test);
        surface.expanded = true;
        var header = findChild(surface, "notchHeader");
        verify(!header.settingsVisible);
        verify(!findChild(header, "headerSettingsButton").visible);
        facade.fileSettings = ({ showSettingsIcon: true });
        verify(header.settingsVisible);
        verify(findChild(header, "headerSettingsButton").visible);
        design.customAccent = "#f09258";
        compare(surface.ink.accent, Qt.color("#f09258"));
        design.customAccent = "";
        var shadow = findChild(surface, "notchShadowLoader");
        verify(shadow.visible);
        facade.fileSettings = ({ windowShadow: false });
        verify(!shadow.visible);
    }
    function test_hoverExtensionAddsOnlyTheChosenStrip() {
        facade.fileSettings = ({ extendHoverArea: true, hoverDwell: 20 });
        var surface = createTemporaryObject(livePillComponent, test);
        var strip = surface.hoverExtension;
        compare(strip.height, 8);
        compare(strip.y, surface.pillHeight);
        compare(strip.width, surface.hitShape.width);
        mouseMove(test, strip.x + strip.width / 2, strip.y + 4);
        tryCompare(surface, "expanded", true, 300);
        compare(strip.height, 0, "the extra region disappears while open");
        mouseMove(test, 5, test.height - 5);
        facade.fileSettings = ({ extendHoverArea: true, hoverDwell: 20, openOnHover: false });
        surface.collapse();
        compare(strip.height, 8);
        mouseMove(test, strip.x + strip.width / 2, strip.y + 4);
        wait(80);
        compare(surface.expanded, false, "disabled hover keeps the island closed after the strip dwell");
        mouseMove(test, 5, test.height - 5);
        facade.fileSettings = ({ extendHoverArea: false });
        compare(strip.height, 0);
    }
    // Crossing from the strip into the pill keeps the dwell running: Qt
    // delivers the pill's enter before the strip's leave, and that leave
    // must not stop the dwell the pill has just restarted.
    function test_stripToPillKeepsTheDwell() {
        facade.fileSettings = ({ extendHoverArea: true, hoverDwell: 150 });
        var surface = createTemporaryObject(livePillComponent, test);
        var strip = surface.hoverExtension;
        mouseMove(test, strip.x + strip.width / 2, strip.y + 4);
        wait(40);
        mouseMove(test, strip.x + strip.width / 2, surface.pillHeight / 2);
        compare(surface.expanded, false);
        tryCompare(surface, "expanded", true, 600, "the dwell runs on into the pill and opens the island");
        mouseMove(test, 5, test.height - 5);
        surface.collapse();
        // And back: from the pill down into the strip.
        mouseMove(test, strip.x + strip.width / 2, surface.pillHeight / 2);
        wait(40);
        mouseMove(test, strip.x + strip.width / 2, strip.y + 4);
        tryCompare(surface, "expanded", true, 600, "the dwell runs on into the strip");
        mouseMove(test, 5, test.height - 5);
    }
    function test_mediaInactivityControlsClosedRowAndIdleFace() {
        facade.fileSettings = ({ pauseGrace: 40, showIdleFace: true });
        var surface = createTemporaryObject(livePillComponent, test);
        compare(surface.closedModel.state, "live");
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        compare(surface.closedModel.state, "live", "the one timeout retains the closed player");
        tryCompare(surface.closedModel, "state", "idle", 200);
        compare(surface.closedModel.centreContent, "face", "idle face follows the same timeout");
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Playing" });
        compare(surface.closedModel.state, "live");
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        compare(surface.closedModel.state, "live");
        facade.fileSettings = ({ pauseGrace: 0, showIdleFace: true });
        compare(surface.closedModel.state, "idle");
        compare(surface.closedModel.centreContent, "face");
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Playing" });
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        compare(surface.closedModel.state, "idle", "zero ends the live state immediately");
    }
    function test_peekBloomOvershootsInsideWindowAndSettles() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        surface.peekActive = true;
        var maxHeight = card.height, maxWidth = card.width;
        var elapsed = 0;
        while (elapsed < design.openDuration + 100) {
            wait(8);
            elapsed += 8;
            maxHeight = Math.max(maxHeight, card.height);
            maxWidth = Math.max(maxWidth, card.width);
        }
        verify(maxHeight > design.peekHeight, "the bloom overshoots a little");
        verify(maxHeight <= surface.height, "inside the window");
        compare(maxWidth, design.peekWidth, "the width never overshoots");
        compare(card.height, design.peekHeight, "and settles at the peek height");
        surface.peekActive = false;
        tryCompare(card, "height", surface.pillHeight, design.closeDuration + 200);
        compare(card.width, design.liveWidth);
        design.reducedMotion = true;
    }
    function test_expandFromPeekIsContinuous() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        surface.peekActive = true;
        tryCompare(surface, "peekAmount", 1, design.openDuration + 300);
        // As Panel.qml does: expanding suppresses, and so ends, the peek.
        surface.expandTo("home");
        surface.peekActive = false;
        var minHeight = card.height, minWidth = card.width;
        var elapsed = 0;
        while (elapsed < design.openDuration + 100) {
            wait(16);
            elapsed += 16;
            minHeight = Math.min(minHeight, card.height);
            minWidth = Math.min(minWidth, card.width);
        }
        verify(minHeight >= design.peekHeight - 1, "the card grows on from the peek, never back through the pill");
        verify(minWidth >= design.peekWidth - 1);
        compare(card.height, surface.restHeight);
        design.reducedMotion = true;
    }
    function test_peekHiddenWhenExpanded() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekActive = true;
        var peek = findChild(surface, "islandPeek");
        verify(peek.visible);
        surface.expandTo("home");
        verify(!peek.visible, "the expanded card replaces the peek");
        compare(surface.peekAmount, 0);
        compare(findChild(surface, "islandCard").height, surface.restHeight);
        compare(surface.hitShape.height, surface.restHeight);
    }
    function test_powerReplacingTrackEasesTheShape() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        surface.peekActive = true;
        tryCompare(surface, "peekAmount", 1, design.openDuration + 300);
        surface.peekKind = "power";
        wait(16);
        verify(card.height > surface.pillHeight + 4, "the track card eases down, it does not snap");
        tryCompare(card, "height", surface.pillHeight, design.peekInDuration + 300);
        design.reducedMotion = true;
    }
    // Offscreen previews of the three peeks over a bar strip. The track peek
    // uses the art fixture with a tint picked from it.
    function peekStage(kind, powerKind, level) {
        var stage = createTemporaryObject(peekStageComponent, test);
        stage.surface.peekKind = kind;
        stage.surface.powerKind = powerKind;
        stage.surface.powerLevel = level;
        stage.surface.peekActive = true;
        return stage;
    }
    function test_peekScreenshots() {
        var art = createTemporaryObject(artFixtureComponent, test);
        waitForRendering(art);
        var artPath = Qt.resolvedUrl("../../build/ui-preview/pill-art-fixture.png").toString().slice(7);
        grabImage(art).save(artPath);
        art.destroy();
        var e = endpoint();
        e.artworkPath = artPath;
        e.presentation.title = "Midnight City";
        e.presentation.artists = ["M83"];
        facade.selectedEndpoint = e;
        facade.positionSeconds = 92;
        facade.remoteArtwork = true;
        facade.spectrumState = "running";
        facade.spectrumLevels = [38, 72, 91, 80, 64, 70, 55, 47, 58, 41, 33, 39];
        design.artColor = "#e0607e";
        var stage = peekStage("track", "plugged", 0);
        var raster = findChild(findChild(stage, "peekArtwork"), "artworkRaster");
        tryCompare(raster, "ready", true);
        wait(250);
        grabImage(stage).save(Qt.resolvedUrl("../../build/ui-preview/island-peek-track.png").toString().slice(7));
        stage.destroy();
        design.artColor = "transparent";
        stage = peekStage("power", "plugged", 0.64);
        wait(50);
        grabImage(stage).save(Qt.resolvedUrl("../../build/ui-preview/island-peek-power-charging.png").toString().slice(7));
        stage.destroy();
        // A frame from the plug-in pulse: the bolt swollen, the ring spreading.
        design.reducedMotion = false;
        stage = peekStage("power", "plugged", 0.64);
        wait(design.peekInDuration + 40);
        grabImage(stage).save(Qt.resolvedUrl("../../build/ui-preview/island-peek-power-plugin.png").toString().slice(7));
        stage.destroy();
        design.reducedMotion = true;
        stage = peekStage("power", "low", 0.18);
        wait(50);
        var image = grabImage(stage);
        image.save(Qt.resolvedUrl("../../build/ui-preview/island-peek-power-low.png").toString().slice(7));
        var fill = findChild(stage, "peekPowerFill");
        var centre = fill.mapToItem(stage, fill.width / 2, fill.height / 2);
        verify(Qt.colorEqual(image.pixel(Math.floor(centre.x), Math.floor(centre.y)), design.error),
            "the low-battery preview draws its level in the error colour");
    }
    function test_livePillScreenshot() {
        var art = createTemporaryObject(artFixtureComponent, test);
        waitForRendering(art);
        var artPath = Qt.resolvedUrl("../../build/ui-preview/pill-art-fixture.png").toString().slice(7);
        grabImage(art).save(artPath);
        art.destroy();
        var e = endpoint();
        e.artworkPath = artPath;
        e.lengthSeconds = 245;
        facade.selectedEndpoint = e;
        facade.positionSeconds = 92;
        facade.remoteArtwork = true;
        facade.spectrumState = "running";
        facade.spectrumLevels = [38, 72, 91, 80, 64, 70, 55, 47, 58, 41, 33, 39];
        var surface = createTemporaryObject(livePillComponent, test);
        var image = findChild(surface, "artworkImage");
        tryCompare(image, "status", Image.Ready);
        tryCompare(findChild(surface, "artworkRaster"), "ready", true);
        wait(50);
        waitForRendering(surface);
        grabImage(findChild(surface, "islandCard")).save(Qt.resolvedUrl("../../build/ui-preview/island-pill-live.png").toString().slice(7));
    }
    function test_screenshots() {
        var surface = createTemporaryObject(surfaceComponent, test);
        waitForRendering(surface);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-pill.png").toString().slice(7));
        surface.expandTo("home");
        waitForRendering(surface);
        wait(design.openDuration + 50);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-expanded.png").toString().slice(7));
        facade.shelfItems = ["file:///home/user/Documents/report%20final.pdf", "file:///home/user/Pictures/cover.png",
            "file:///home/user/notes.txt"];
        facade.shelfEntries = facade.shelfItems.map(function (uri, index) {
            return { id: "s" + index, kind: "file", uri: uri, name: decodeURIComponent(uri.split("/").pop()), addedAt: index, temp: false };
        });
        surface.expandTo("shelf");
        wait(80);
        waitForRendering(surface);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-shelf.png").toString().slice(7));
        facade.shelfItems = [];
        facade.shelfEntries = [];
        surface.expandTo("home");
        surface.collapse();
        waitForRendering(surface);
        surface.hud.show("volume", 0.62, false);
        waitForRendering(surface);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-hud.png").toString().slice(7));
        surface.hud.active = false;
    }
    // Invented lines: no real song's lyrics live in the repository.
    function fixtureLines() {
        return [
            { t: 10, text: "Neon rivers under the overpass" },
            { t: 14, text: "We keep the engine running while the signal fades" },
            { t: 19, text: "Every window holds a different song" },
            { t: 23, text: "♪" },
            { t: 30, text: "And the whole city hums along" },
            { t: 34, text: "Hold the light a little longer" },
            { t: 38, text: "Before the morning finds us" }
        ];
    }
    function lyricsSurface(component) {
        facade.lyrics = true;
        var surface = createTemporaryObject(component || surfaceComponent, test);
        surface.lyricsSource = lyricsFixture;
        return surface;
    }
    function lyricsView(surface) {
        surface.expandTo("lyrics");
        var loader = findChild(surface, "lyricsViewLoader");
        tryVerify(function () { return loader.item !== null; }, 1000, "the Lyrics view loads");
        return loader.item;
    }
    // Lyrics is a sub-view of Home, not a tab: the tabs stay Home and
    // Shelf, and while Lyrics shows a back chevron takes their place.
    function test_lyricsIsASubViewOfHome() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("lyrics");
        compare(surface.view, "home", "no Lyrics while lyrics is off");
        compare(surface.views, ["home", "shelf"]);
        facade.lyrics = true;
        compare(surface.views, ["home", "shelf"], "turning lyrics on adds no tab");
        surface.lyricsSource = lyricsFixture;
        surface.expandTo("lyrics");
        compare(surface.view, "lyrics");
        waitForRendering(surface);
        verify(findChild(surface, "lyricsViewLoader").item, "the view loads on demand");
        var header = findChild(surface, "notchHeader");
        compare(header.selectedTab, "home", "Home stays the selected tab");
        verify(!findChild(surface, "viewHomeButton").visible, "the tabs give way to");
        var back = findChild(surface, "lyricsBackButton");
        verify(back.visible, "a back chevron");
        mouseClick(back);
        compare(surface.view, "home", "which returns to Home");
        verify(findChild(surface, "viewHomeButton").visible);
        compare(surface.expanded, true);
    }
    function test_lyricsOffFallsBackToHome() {
        var surface = lyricsSurface();
        lyricsView(surface);
        facade.lyrics = false;
        compare(surface.view, "home");
        compare(findChild(surface, "lyricsViewLoader").item, null);
        facade.lyrics = true;
        compare(surface.view, "home", "turning lyrics back on does not jump views");
    }
    function test_lyricsViewUnloadsWhenCollapsed() {
        var surface = lyricsSurface();
        lyricsView(surface);
        surface.collapse();
        compare(findChild(surface, "lyricsViewLoader").item, null);
        compare(findChild(surface, "lyricsViewLoader").active, false);
    }
    function test_tabCyclesTabsFromLyrics() {
        var surface = lyricsSurface();
        surface.explicitOpen = true;
        surface.expandTo("home");
        surface.focusKeys();
        waitForRendering(surface);
        keyClick(Qt.Key_Tab);
        compare(surface.view, "shelf");
        keyClick(Qt.Key_Tab);
        compare(surface.view, "home");
        surface.view = "lyrics";
        keyClick(Qt.Key_Tab);
        compare(surface.view, "shelf", "Lyrics steps as its Home tab does");
        keyClick(Qt.Key_Backtab);
        compare(surface.view, "home");
        surface.explicitOpen = false;
    }
    // Escape leaves the Lyrics sub-view first, then closes the island.
    function test_escapeLeavesLyricsThenCloses() {
        var surface = lyricsSurface();
        surface.explicitOpen = true;
        surface.expandTo("lyrics");
        surface.focusKeys();
        waitForRendering(surface);
        keyClick(Qt.Key_Escape);
        compare(surface.view, "home");
        compare(surface.expanded, true);
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false);
        surface.explicitOpen = false;
    }
    function test_returnIntoLyricsReachesTryAgain() {
        lyricsFixture.lyricsState = "error";
        lyricsFixture.errorCode = "network";
        var surface = lyricsSurface();
        surface.explicitOpen = true;
        surface.expandTo("lyrics");
        surface.focusKeys();
        waitForRendering(surface);
        keyClick(Qt.Key_Return);
        var retry = findChild(surface, "lyricsRetry");
        verify(retry.activeFocus, "Return lands on Try again");
        keyClick(Qt.Key_Space);
        compare(lyricsFixture.retries, 1, "Space activates the focused button");
        keyClick(Qt.Key_Escape);
        compare(surface.view, "home", "Escape leaves Lyrics from inside the view");
        compare(surface.expanded, true);
        surface.explicitOpen = false;
    }
    function test_returnIntoSyncedLyricsKeepsShortcuts() {
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        var surface = lyricsSurface();
        surface.explicitOpen = true;
        surface.expandTo("lyrics");
        surface.focusKeys();
        waitForRendering(surface);
        keyClick(Qt.Key_Return);
        verify(!surface.keysFocused, "Return steps into the view");
        verify(findChild(surface, "lyricsViewLoader").item.activeFocus);
        keyClick(Qt.Key_Escape);
        compare(surface.view, "home");
        compare(surface.expanded, true);
        surface.explicitOpen = false;
    }
    function test_lyricsLinesFollowCurrentIndex() {
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        lyricsFixture.currentIndex = -1;
        var view = lyricsView(lyricsSurface());
        var current = findChild(view, "lyricsCurrentLine");
        compare(current.text, "♪", "before the first line the current slot holds a note");
        compare(findChild(view, "lyricsNextLine").text, "Neon rivers under the overpass");
        verify(!findChild(view, "lyricsPreviousLine").visible);
        lyricsFixture.currentIndex = 1;
        compare(current.text, "We keep the engine running while the signal fades");
        compare(findChild(view, "lyricsPreviousLine").text, "Neon rivers under the overpass");
        compare(findChild(view, "lyricsNextLine").text, "Every window holds a different song");
        compare(findChild(view, "lyricsLaterLine").text, "♪");
        verify(current.font.pixelSize > findChild(view, "lyricsNextLine").font.pixelSize, "the current line is the largest");
        verify(findChild(view, "lyricsPreviousLine").font.pixelSize <= findChild(view, "lyricsNextLine").font.pixelSize);
        verify(Qt.colorEqual(current.color, design.text), "the current line is in the text colour");
        compare(current.opacity, 1);
        compare(current.lineCount <= 2, true);
        lyricsFixture.currentIndex = 3;
        verify(Qt.colorEqual(current.color, design.tint), "a break is drawn in the tint");
        lyricsFixture.currentIndex = 6;
        compare(current.text, "Before the morning finds us");
        verify(!findChild(view, "lyricsNextLine").visible, "nothing after the last line");
    }
    function test_lyricsGlideIsFinite() {
        design.reducedMotion = false;
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        lyricsFixture.currentIndex = 0;
        var surface = lyricsSurface();
        var view = lyricsView(surface);
        tryCompare(surface, "expansion", 1, design.openDuration + 500);
        tryCompare(view, "glide", 1, 1000);
        var current = findChild(view, "lyricsCurrentLine");
        var next = findChild(view, "lyricsNextLine");
        // Where the upcoming line sits now is where the new current line
        // starts its glide from.
        var nextOffset = next.y - current.y;
        lyricsFixture.currentIndex = 1;
        verify(view.glide < 1, "a step forward glides");
        verify(view.glideForward);
        compare(view.glideShift, nextOffset, "the new current line starts where the upcoming line was");
        verify(current.scale < 1 && current.opacity < 1, "the new line grows from the upcoming line's style");
        tryCompare(view, "glide", 1, design.lyricLineDuration * 2 + 300);
        compare(current.scale, 1);
        compare(current.opacity, 1);
        lyricsFixture.currentIndex = 5;
        verify(!view.glideForward, "a jump is a seek, not a step");
        compare(view.glideShift, 6);
        tryCompare(view, "glide", 1, design.lyricLineDuration * 2 + 300);
    }
    function test_lyricsGlideSkippedUnderReducedMotion() {
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        lyricsFixture.currentIndex = 0;
        var view = lyricsView(lyricsSurface());
        compare(findChild(view, "lyricsCurrentLine").text, "Neon rivers under the overpass",
            "a view opened mid-song starts on the line being sung");
        lyricsFixture.currentIndex = 1;
        compare(view.glide, 1);
        compare(findChild(view, "lyricsCurrentLine").scale, 1);
    }
    function test_lyricsStates_data() {
        return [
            { tag: "loading", state: "loading", title: "Looking up lyrics…" },
            { tag: "none", state: "none", title: "No synced lyrics for this track" },
            { tag: "plain", state: "plain", title: "Only unsynced lyrics" },
            { tag: "instrumental", state: "instrumental", title: "Instrumental" },
            { tag: "no-length", state: "no-length", title: "Lyrics need the track length",
                detail: "This source does not report the track length, which lyrics need" },
            { tag: "error-timeout", state: "error", code: "timeout", title: "Lyrics could not be loaded",
                detail: "LRCLIB did not answer in time", retry: true },
            { tag: "error-network", state: "error", code: "network", title: "Lyrics could not be loaded",
                detail: "Check the connection and try again", retry: true },
            { tag: "idle-no-meta", state: "idle", meta: null, title: "Nothing to look up" },
            { tag: "off", state: "idle", off: true, title: "Lyrics are off" },
            { tag: "nothing-playing", state: "idle", noEndpoint: true, title: "Nothing is playing" }
        ];
    }
    function test_lyricsStates(data) {
        lyricsFixture.lyricsState = data.state;
        lyricsFixture.errorCode = data.code || "";
        if (data.meta === null)
            lyricsFixture.meta = null;
        lyricsFixture.lyricsEnabled = data.off !== true;
        if (data.noEndpoint)
            facade.selectedEndpoint = null;
        var view = lyricsView(lyricsSurface());
        compare(findChild(view, "lyricsMessageTitle").text, data.title);
        if (data.detail)
            compare(findChild(view, "lyricsMessageDetail").text, data.detail);
        verify(findChild(view, "lyricsMessage").visible);
        verify(!findChild(view, "lyricsLines").visible, "a state replaces the lines");
        compare(findChild(view, "lyricsRetry").visible, data.retry === true);
        compare(findChild(view, "lyricsHeader").visible, !data.noEndpoint);
        verify(findChild(view, "lyricsAttribution").visible, "the attribution always shows");
        if (data.retry) {
            mouseClick(findChild(view, "lyricsRetry"));
            compare(lyricsFixture.retries, 1);
        }
    }
    function test_lyricsViewFitsTheCard() {
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        lyricsFixture.currentIndex = 1;
        var surface = lyricsSurface();
        var view = lyricsView(surface);
        compare(view.height, design.openHeight - design.bandSwitcher, "the view fills the open body under the switcher");
        var stage = findChild(view, "lyricsStage");
        var footer = findChild(view, "lyricsAttribution");
        verify(stage.y + stage.height <= footer.y, "the lines never run into the attribution");
        verify(footer.y + footer.height <= view.height);
        var header = findChild(view, "lyricsHeader");
        verify(header.y + header.height <= stage.y);
    }
    function test_calendarFitsTheFixedOpenHeight() {
        facade.fileSettings = ({ showCalendar: true });
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.restHeight, 190);
        compare(design.notchWindowHeight(), 220);
        surface.expandTo("home");
        var calendar = findChild(surface, "calendarPanel");
        var list = findChild(calendar, "calendarList");
        verify(list.height > 0 && list.height < 120);
        verify(list.y + list.height <= calendar.height);
        compare(findChild(surface, "islandCard").height, 190);
    }
    function lyricsArt() {
        var art = createTemporaryObject(artFixtureComponent, test);
        waitForRendering(art);
        var artPath = Qt.resolvedUrl("../../build/ui-preview/pill-art-fixture.png").toString().slice(7);
        grabImage(art).save(artPath);
        art.destroy();
        var e = endpoint();
        e.artworkPath = artPath;
        e.presentation.title = "Afterglow";
        e.presentation.artists = ["The Test Pressing"];
        e.presentation.album = "Fixtures, Vol. 2";
        facade.selectedEndpoint = e;
        facade.remoteArtwork = true;
        facade.positionSeconds = 92;
    }
    // A short wait, not waitForRendering(): with nothing left to render that
    // waits out its whole timeout.
    function savePreview(surface, name) {
        wait(40);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/" + name + ".png").toString().slice(7));
    }
    function test_lyricsScreenshots() {
        lyricsArt();
        design.artColor = "#e0607e";
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        lyricsFixture.currentIndex = 1;
        var surface = lyricsSurface();
        var view = lyricsView(surface);
        tryCompare(findChild(view, "artworkRaster"), "ready", true);
        wait(250);
        savePreview(surface, "island-lyrics");
        lyricsFixture.currentIndex = 3;
        wait(50);
        savePreview(surface, "island-lyrics-break");
        // One frame part-way through a step forward.
        design.reducedMotion = false;
        lyricsFixture.currentIndex = 4;
        view.glide = 0.45;
        savePreview(surface, "island-lyrics-glide");
        design.reducedMotion = true;
        view.glide = 1;
        var states = [["loading", ""], ["none", ""], ["plain", ""], ["instrumental", ""],
            ["no-length", ""], ["error", "timeout"]];
        for (var i = 0; i < states.length; ++i) {
            lyricsFixture.lyricsState = states[i][0];
            lyricsFixture.errorCode = states[i][1];
            wait(30);
            savePreview(surface, "island-lyrics-" + states[i][0]);
        }
        design.artColor = "transparent";
        design.light = true;
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.currentIndex = 1;
        wait(50);
        savePreview(surface, "island-lyrics-light");
        design.light = false;
    }
    // The header: Home and Shelf tabs on the left under a sliding capsule,
    // the closed notch's body left empty in the centre, and the settings
    // gear on the right; the camera slot shows only with the mirror on, and
    // the battery slot waits for its feature.
    function test_headerTabsAndCapsule() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        tryCompare(surface, "expansion", 1, design.openDuration + 300);
        waitForRendering(surface);
        var header = findChild(surface, "notchHeader");
        var capsule = findChild(surface, "tabCapsule");
        var home = findChild(surface, "viewHomeButton");
        var shelf = findChild(surface, "viewShelfButton");
        compare(home.text, "Home");
        compare(shelf.text, "Shelf");
        compare(findChild(home, "tabIcon").name, "home", "the tabs are icons, as boring.notch's");
        compare(findChild(shelf, "tabIcon").name, "tray");
        verify(!findChild(shelf, "tabBadge").visible, "an empty shelf shows no zero count");
        compare(capsule.height, 26);
        compare(capsule.color.a < 0.3, true, "a faint neutral capsule");
        verify(home.x < shelf.x, "Home, then Shelf");
        compare(capsule.x, home.x + home.parent.x);
        compare(capsule.width, home.width);
        mouseClick(shelf);
        compare(surface.view, "shelf");
        verify(capsule.x < shelf.x + shelf.parent.x, "the capsule slides rather than jumping");
        tryCompare(capsule, "x", shelf.x + shelf.parent.x, design.tabDuration + 200);
        compare(capsule.width, shelf.width);
        var centre = findChild(surface, "headerCentre");
        compare(centre.width, design.liveWidth - 2 * design.flareClosed, "the centre span is the closed body");
        fuzzyCompare(header.mapToItem(surface, centre.x + centre.width / 2, 0).x, surface.width / 2, 0.5);
        verify(shelf.parent.x + shelf.x + shelf.width <= centre.x, "no tab reaches the centre span");
        verify(findChild(surface, "headerSettingsButton").visible);
        verify(!findChild(surface, "headerCameraSlot").visible);
        verify(!findChild(surface, "headerBatterySlot").visible);
        design.reducedMotion = true;
    }
    // A stand-in for the camera: tests never open the real device.
    property int cameraCreations: 0
    property int cameraDestructions: 0
    Component {
        id: fakeCamera
        Item {
            property bool unavailable: false
            Component.onCompleted: test.cameraCreations++
            Component.onDestruction: test.cameraDestructions++
        }
    }
    // The mirror's camera waits for the open spring to settle, stops on
    // another tab, and the header toggle hides the mirror for the session,
    // across a close and reopen.
    function test_mirrorWaitsForTheSettledOpenAndTheHeaderToggle() {
        design.reducedMotion = false;
        cameraCreations = 0;
        facade.fileSettings = ({ showMirror: true });
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.cameraSource = fakeCamera;
        var toggle = findChild(surface, "headerCameraButton");
        surface.expandTo("home");
        verify(surface.expanded);
        var mirror = findChild(surface, "cameraPanel");
        compare(surface.openSettled, false, "the spring is still running");
        compare(mirror.captureAllowed, false, "so the camera waits");
        tryCompare(surface, "openSettled", true, design.openDuration + 300);
        verify(findChild(surface, "headerCameraSlot").visible, "the mirror setting shows the camera toggle");
        verify(mirror.captureAllowed);
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        surface.view = "shelf";
        compare(mirror.captureAllowed, false, "another tab stops the camera");
        compare(mirror.sourceItem, null);
        surface.view = "home";
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        mouseClick(toggle);
        verify(surface.mirrorHidden);
        verify(!mirror.visible, "the toggle hides the mirror");
        compare(mirror.sourceItem, null, "and stops its camera");
        verify(findChild(surface, "headerCameraSlot").visible, "the toggle stays to bring it back");
        surface.collapse();
        tryCompare(surface, "expansion", 0, design.openDuration + 300);
        surface.expandTo("home");
        tryCompare(surface, "openSettled", true, design.openDuration + 300);
        verify(!mirror.visible, "hidden for the session, not just until the close");
        mouseClick(toggle);
        verify(mirror.visible);
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        surface.collapse();
        compare(mirror.captureAllowed, false, "closing stops the camera at once");
        compare(mirror.sourceItem, null);
        design.reducedMotion = true;
    }
    // The host can hide its window while the island stays expanded on Home
    // (autoShow turned off, for one): the camera must stop with the window,
    // not wait for a collapse that never comes.
    function test_hiddenHostWindowStopsTheMirror() {
        cameraCreations = 0;
        cameraDestructions = 0;
        facade.fileSettings = ({ showMirror: true });
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.cameraSource = fakeCamera;
        surface.expandTo("home");
        var mirror = findChild(surface, "cameraPanel");
        tryCompare(surface, "openSettled", true, design.openDuration + 300);
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        surface.hostVisible = false;
        verify(surface.expanded, "the host hid the window without collapsing");
        compare(surface.openSettled, false);
        compare(mirror.captureAllowed, false, "a hidden window stops the camera");
        compare(mirror.sourceItem, null, "and unloads its source");
        tryCompare(test, "cameraDestructions", 1);
        surface.hostVisible = true;
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        compare(cameraCreations, 2, "showing the window again starts it afresh");
    }
    // Home is built on the first approach (hover or open), not before, and
    // stays built after the island closes.
    function test_homeBuildsOnFirstApproachAndStays() {
        // Latching Home loaded must not feed back into its own Loader.
        failOnWarning(/Binding loop/);
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(findChild(surface, "homeView"), null, "a never-approached island holds no Home");
        mouseMove(surface, surface.width / 2, pillPoint(surface).y);
        tryVerify(function () { return findChild(surface, "homeView") !== null; }, 1000, "hovering builds Home");
        var home = findChild(surface, "homeView");
        surface.expandTo("home");
        compare(findChild(surface, "homeView"), home);
        surface.collapse();
        mouseMove(test, 5, test.height - 5);
        tryCompare(surface, "expansion", 0, 2000);
        compare(findChild(surface, "homeView"), home, "and keeps it once built");
        var summoned = createTemporaryObject(surfaceComponent, test);
        summoned.expandTo("home");
        verify(findChild(summoned, "homeView") !== null, "a summon builds it too");
    }
    // With showCalendar on, the open island's Home holds the calendar, and
    // opening the island refreshes it to the current day; other tabs and a
    // closed island hide it.
    function test_calendarOnHomeRefreshesWhenTheIslandOpens() {
        facade.fileSettings = ({ showCalendar: true });
        var surface = createTemporaryObject(surfaceComponent, test);
        // The mirror joins later in this test; never the real camera.
        surface.cameraSource = fakeCamera;
        compare(findChild(surface, "calendarPanel"), null, "closed and never opened, Home is not even built");
        surface.expandTo("home");
        var calendar = findChild(surface, "calendarPanel");
        tryVerify(function () { return calendar.visible; }, 1000);
        surface.collapse();
        tryVerify(function () { return !calendar.visible; }, 1000);
        var stale = new Date();
        stale.setDate(stale.getDate() - 2);
        calendar.now = stale;
        surface.expandTo("home");
        tryVerify(function () { return calendar.visible; }, 1000);
        compare(calendar.now.toDateString(), new Date().toDateString(), "opening refreshes it");
        verify(calendar.showingToday);
        compare(calendar.width, 215);
        surface.view = "shelf";
        verify(!calendar.visible, "another tab hides it");
        facade.fileSettings = ({ showCalendar: true, showMirror: true });
        surface.view = "home";
        compare(calendar.width, 170, "beside the mirror it narrows");
        verify(calendar.compact);
        facade.fileSettings = ({});
        verify(!calendar.visible, "showCalendar off removes it");
    }
    // With the face style and nothing playing, the closed notch shows the
    // face centred in its body at boring.notch's face width, and music
    // replaces it. An old file's showIdleFace still means the face.
    function test_closedIdleFace() {
        facade.selectedEndpoint = null;
        var surface = createTemporaryObject(livePillComponent, test);
        var face = findChild(surface, "closedIdleFace");
        verify(!face.visible, "off by default");
        facade.fileSettings = ({ showIdleFace: true });
        verify(face.visible);
        compare(surface.closedModel.width, design.faceWidth);
        var body = findChild(surface, "notchBody");
        var box = face.mapToItem(body, 0, 0, face.width, face.height);
        compare(box.x + box.width / 2, body.width / 2, "centred in the body");
        facade.fileSettings = ({ idleStyle: "face", hardwareNotch: true });
        var right = findChild(surface, "rightWing");
        box = face.mapToItem(right, 0, 0, face.width, face.height);
        compare(box.x + box.width / 2, right.width / 2, "over a camera cutout, centred in the right wing");
        facade.selectedEndpoint = endpoint();
        verify(!face.visible, "music replaces the face");
    }
    // A host safety reset that leaves the window shown (a move to another
    // screen) ends a hold this island's readout took, like one that hides
    // it; a hold another island's readout took is not this island's to end.
    Component {
        id: foreignOwner
        Item {}
    }
    function test_hostResetEndsAHeldHudBar() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("volume", 0.4, false);
        waitForRendering(surface);
        var bar = findChild(findChild(surface, "hudInline"), "hudBar");
        mouseMove(bar, bar.width * 0.75, bar.height / 2);
        mousePress(bar, bar.width * 0.75, bar.height / 2);
        verify(surface.hud.held);
        surface.resetForHost();
        verify(!surface.hud.held, "the reset ends the hold");
        compare(bar.dragging, false);
        compare(surface.hud.active, false, "and the readout goes");
        surface.expandTo("home");
        verify(surface.expanded, "so the island opens again");
        mouseRelease(bar, bar.width * 0.75, bar.height / 2);
        surface.collapse(true);
        var other = createTemporaryObject(foreignOwner, test);
        surface.hud.show("volume", 0.4, false);
        surface.hud.hold(other, true);
        surface.resetForHost();
        verify(surface.hud.held, "another island's hold is left to its owner");
        surface.hud.hold(other, false);
    }
    // Every part of the closed inline readout's bar is the bar's: the
    // notch body's own handlers sit above it, and a press over the body
    // must still set the level and hold the readout.
    function test_inlineHudBarTakesPressesAcrossItsWidth_data() {
        return [{ tag: "left", fraction: 0.25 }, { tag: "middle", fraction: 0.5 }, { tag: "right", fraction: 0.75 }];
    }
    function test_inlineHudBarTakesPressesAcrossItsWidth(data) {
        var surface = createTemporaryObject(livePillComponent, test);
        var requests = [];
        surface.hudLevelRequested.connect(function (kind, value) { requests.push([kind, Math.round(value * 100)]); });
        surface.hud.show("volume", 0.4, false);
        waitForRendering(surface);
        var bar = findChild(findChild(surface, "hudInline"), "hudBar");
        // A real pointer reaches the point before it presses there.
        mouseMove(bar, bar.width * data.fraction, bar.height / 2);
        mousePress(bar, bar.width * data.fraction, bar.height / 2);
        verify(surface.hud.held, "the press holds the readout");
        verify(requests.length >= 1, "and sets the level");
        verify(Math.abs(requests[0][1] - Math.round(data.fraction * 100)) <= 3, "at the press point: " + requests[0][1]);
        mouseRelease(bar, bar.width * data.fraction, bar.height / 2);
        verify(!surface.hud.held, "the release ends the hold");
        compare(surface.expanded, false, "a press on the bar never opens the notch");
    }
    // A summon that asks to close itself again, arriving while a HUD bar is
    // held, waits with the open for the release and still closes by itself.
    function test_autoCloseWaitsWithAPendingOpen() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("volume", 0.4, false);
        waitForRendering(surface);
        var bar = findChild(findChild(surface, "hudInline"), "hudBar");
        mouseMove(bar, bar.width * 0.75, bar.height / 2);
        mousePress(bar, bar.width * 0.75, bar.height / 2);
        verify(surface.hud.held);
        surface.expandTo("home");
        surface.scheduleAutoClose(300);
        verify(!surface.expanded, "the open waits for the release");
        mouseRelease(bar, bar.width * 0.75, bar.height / 2);
        verify(surface.expanded, "the release applies the open");
        verify(surface.autoClosePending, "with the summon's auto-close");
        tryCompare(surface, "expanded", false, 1000, "which then closes the island");
        mousePress(bar, bar.width * 0.75, bar.height / 2);
        surface.expandTo("home");
        surface.scheduleAutoClose(300);
        surface.cancelAutoClose();
        mouseRelease(bar, bar.width * 0.75, bar.height / 2);
        verify(surface.expanded);
        verify(!surface.autoClosePending, "a cancelled auto-close stays cancelled");
    }
    // A HUD bar held when its window hides never sees the release, which
    // lands outside the unmapped window. The hold must end with the window,
    // or the readout never dismisses and every open waits for a release that
    // cannot come.
    Component {
        id: windowedSurface
        Window {
            property alias surface: hosted
            width: design.notchWindowWidth()
            height: design.notchWindowHeight()
            visible: true
            IslandSurface {
                id: hosted
                anchors.fill: parent
                tokens: design
                coordinator: facade
                // The live bar size, where the readout's bar takes presses.
                pillHeight: 26
            }
        }
    }
    function test_hiddenWindowEndsAHeldHudBar() {
        var win = createTemporaryObject(windowedSurface, test);
        tryCompare(win, "visible", true);
        waitForRendering(win.contentItem);
        var surface = win.surface;
        surface.hud.show("volume", 0.4, false);
        var bar = findChild(findChild(surface, "hudInline"), "hudBar");
        tryVerify(function () { return bar.visible; }, 1000);
        // A real pointer reaches the point before it presses there.
        mouseMove(bar, bar.width * 0.75, bar.height / 2);
        mousePress(bar, bar.width * 0.75, bar.height / 2);
        verify(surface.hud.held, "a press on the bar holds the readout");
        win.visible = false;
        verify(!surface.hud.held, "hiding the window ends the hold");
        compare(bar.dragging, false);
        win.visible = true;
        tryCompare(surface.hud, "active", false, design.hudDuration + 1000, "the readout dismisses again");
        surface.expandTo("home");
        verify(surface.expanded, "and the island opens again");
    }
    // The capsule finds its tab on the first open of a fresh surface, not
    // only after a later change re-runs its binding. The surface is built
    // the way the shell builds it on the first open, incubated
    // asynchronously, where the tab buttons arrive after the capsule's
    // bindings have run.
    Component {
        id: asyncSurfaceLoader
        Loader {
            asynchronous: true
            sourceComponent: surfaceComponent
        }
    }
    function test_capsuleFindsItsTabFromTheStart() {
        var loader = createTemporaryObject(asyncSurfaceLoader, test);
        tryCompare(loader, "status", Loader.Ready);
        var surface = loader.item;
        waitForRendering(surface);
        var capsule = findChild(surface, "tabCapsule");
        var home = findChild(surface, "viewHomeButton");
        verify(capsule.width > 0, "the capsule has its tab's size from creation");
        compare(capsule.width, home.width);
        compare(capsule.x, home.x + home.parent.x);
        surface.expandTo("home");
        verify(capsule.visible);
    }
    function test_tabsFollowAlwaysShowTabsOrAShelf() {
        facade.fileSettings = ({ alwaysShowTabs: false });
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        verify(!findChild(surface, "viewHomeButton").visible, "no tabs for an empty shelf");
        verify(!findChild(surface, "tabCapsule").visible);
        facade.shelfItems = ["file:///tmp/a.png"];
        facade.shelfEntries = [{ id: "s1", kind: "file", uri: "file:///tmp/a.png", name: "a.png", addedAt: 1, temp: false },
            { id: "s2", kind: "text", text: "note", name: "note", addedAt: 2, temp: false }];
        verify(findChild(surface, "viewHomeButton").visible, "a shelf with items brings them back");
        var shelfTab = findChild(surface, "viewShelfButton");
        compare(findChild(shelfTab, "tabBadge").text, "2", "the count includes links and text, not only files");
        verify(findChild(shelfTab, "tabBadge").visible);
        compare(shelfTab.Accessible.name, "Shelf, 2 items");
        facade.shelfItems = [];
        facade.shelfEntries = [];
        facade.fileSettings = ({ alwaysShowTabs: true });
        verify(findChild(surface, "viewHomeButton").visible, "alwaysShowTabs keeps them");
    }
    // The header gear opens the settings window in one click, from any tab;
    // the inline settings view stays with the legacy panel.
    function test_settingsGearOpensTheSettingsWindow() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("shelf");
        waitForRendering(surface);
        mouseClick(findChild(surface, "headerSettingsButton"));
        compare(facade.settingsSections, [""], "one click opens the window");
        compare(findChild(surface, "homeSettingsOverlay"), null, "nothing opens over Home");
        compare(findChild(surface, "settingsScroller"), null, "the inline settings view is not loaded");
        compare(surface.view, "shelf", "the island stays on its tab");
        verify(surface.expanded);
    }
    // "player", the name Home had before, still opens Home.
    function test_playerViewMigratesToHome() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("player");
        compare(surface.view, "home");
        surface.view = "player";
        compare(surface.view, "home");
        surface.view = "nowhere";
        compare(surface.view, "home");
        surface.view = "shelf";
        compare(surface.view, "shelf");
    }
    // The pull accumulator: progress is travel / gestureTravel * 20, the
    // stretch never drops under 60 %, the dimming tops out at 30 %.
    function test_pullArithmetic() {
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.gestureTravel, 200);
        compare(surface.pullProgress(100, 200), 10);
        compare(surface.pullProgress(-200, 200), -20);
        fuzzyCompare(surface.pullScale(10), 1.1, 1e-9);
        fuzzyCompare(surface.pullScale(-20), 0.8, 1e-9);
        compare(surface.pullScale(-100), 0.6, "the stretch has a floor");
        fuzzyCompare(surface.pullDim(2), 0.2, 1e-9);
        compare(surface.pullDim(-20), 0.3, "the dimming has a ceiling");
    }
    Component {
        id: sharedHudComponent
        HudModel { tokens: design }
    }
    Component {
        id: hudBelowComponent
        HudBelow { tokens: design }
    }
    // A screen removed mid-drag destroys its island and the held bar with
    // it: the hold goes too, rather than staying ownerless and latching
    // every surviving island.
    function test_heldBarReleasedWhenItsViewGoes() {
        var hud = createTemporaryObject(sharedHudComponent, test);
        var first = createTemporaryObject(surfaceComponent, test, { hudModel: hud });
        var second = createTemporaryObject(surfaceComponent, test, { hudModel: hud });
        var view = hudBelowComponent.createObject(first, { model: hud });
        hud.show("volume", 0.5, false);
        findChild(view, "hudBar").dragging = true;
        verify(hud.held);
        compare(hud.heldBy, view);
        verify(first.hudHeldHere && !second.hudHeldHere);
        view.destroy();
        wait(0);
        verify(!hud.held, "the hold ends with its view");
        compare(hud.heldBy, null);
        verify(!first.hudHeldHere && !second.hudHeldHere, "no surviving island stays latched");
    }
    // A view going away without a hold leaves an ownerless hold alone.
    function test_viewWithoutHoldKeepsLegacyHold() {
        var hud = createTemporaryObject(sharedHudComponent, test);
        var view = hudBelowComponent.createObject(test, { model: hud });
        hud.held = true;
        view.destroy();
        wait(0);
        verify(hud.held);
        hud.held = false;
    }
    // With an island on every screen, the windows share one readout model.
    // A bar held on one island is that island's: only it latches and defers,
    // while a hold with no known owner still applies everywhere.
    function test_heldBarBelongsToItsOwnIsland() {
        var hud = createTemporaryObject(sharedHudComponent, test);
        var first = createTemporaryObject(surfaceComponent, test, { hudModel: hud });
        var second = createTemporaryObject(surfaceComponent, test, { hudModel: hud });
        hud.hold(findChild(first, "islandHitShape"), true);
        verify(hud.held);
        verify(first.hudHeldHere, "the island whose bar is held");
        verify(!second.hudHeldHere, "another island is not held");
        hud.hold(findChild(first, "islandHitShape"), false);
        verify(!hud.held);
        verify(!first.hudHeldHere);
        hud.held = true;
        verify(first.hudHeldHere && second.hudHeldHere, "a hold without an owner applies to every island");
        hud.held = false;
    }
    function test_pullDownOpensOnceAtTheThreshold() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        surface.updatePull(surface.pullDeadZone - 1);
        compare(surface.gestureProgress, 0, "a tap-sized move never moves the notch");
        surface.updatePull(100);
        compare(surface.gestureProgress, 10);
        compare(card.transform[0].yScale, surface.pullScale(10), "the notch stretches about its top");
        compare(card.transform[0].origin.y, 0);
        compare(surface.expanded, false);
        surface.updatePull(-40);
        compare(surface.gestureProgress, 0, "back past the start, nothing is pulled");
        surface.updatePull(200);
        compare(surface.expanded, true, "it opens at gestureTravel");
        compare(surface.gestureProgress, 0);
        verify(surface.pullLatched);
        surface.updatePull(260);
        compare(surface.expanded, true);
        surface.updatePull(-400);
        compare(surface.expanded, true, "latched until the gesture ends");
        surface.endPull();
        verify(!surface.pullLatched);
    }
    function test_pushUpClosesAndDims() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var column = findChild(surface, "expandedColumn");
        surface.updatePull(40);
        compare(surface.gestureProgress, 0, "a push only runs upward");
        surface.updatePull(-40);
        compare(surface.gestureProgress, -4);
        fuzzyCompare(column.opacity, 1 - 0.3, 1e-9);
        surface.updatePull(-200);
        compare(surface.expanded, false, "it closes at gestureTravel");
        surface.endPull();
        facade.fileSettings = ({ closeGesture: false });
        surface.expandTo("home");
        surface.updatePull(-300);
        compare(surface.expanded, true, "closeGesture off keeps pushes inert");
        surface.endPull();
        surface.collapse();
        facade.fileSettings = ({ enableGestures: false });
        surface.updatePull(300);
        compare(surface.expanded, false, "enableGestures off keeps pulls inert");
    }
    function test_gestureTravelComesFromSettings() {
        facade.fileSettings = ({ gestureTravel: 100 });
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.updatePull(100);
        compare(surface.expanded, true);
        facade.fileSettings = ({ gestureTravel: 999 });
        compare(surface.gestureTravel, 200, "an out-of-range value reads as the default");
    }
    // Shift turns the wheel into the pull; a plain wheel keeps volume.
    function test_shiftWheelPullsPlainWheelKeepsVolume() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var steps = [];
        surface.volumeStepRequested.connect(function (delta) { steps.push(delta); });
        surface.handleWheel(0, -120, false, Qt.NoModifier);
        compare(steps.length, 1, "a plain wheel still steps the volume");
        compare(surface.gestureProgress, 0);
        surface.handleWheel(0, -120, false, Qt.ShiftModifier);
        compare(steps.length, 1, "a Shift-wheel never steps the volume");
        compare(surface.pullTravel, surface.wheelPullStep);
        surface.handleWheel(-120 * 4, 0, false, Qt.ShiftModifier);
        compare(surface.expanded, true, "five notches down open it");
        surface.endPull();
        surface.handleWheel(0, 120 * 5, false, Qt.ShiftModifier);
        compare(surface.expanded, false, "five up close it");
        surface.endPull();
        surface.handleWheel(0, -120, false, Qt.ShiftModifier);
        tryCompare(surface, "pullTravel", 0, 1000, "the wheel pull ends by itself");
    }
    function test_hoverTimingsComeFromSettings() {
        facade.fileSettings = ({ hoverDwell: 40, leaveGrace: 30 });
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.hoverDwell, 40);
        compare(surface.leaveGrace, 30);
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        tryCompare(surface, "expanded", true, 200);
        mouseMove(test, farPoint().x, farPoint().y);
        tryCompare(surface, "expanded", false, 200);
        facade.fileSettings = ({});
        compare(surface.hoverDwell, 300);
        compare(surface.leaveGrace, 100);
    }
    // A summon may close itself; any interaction cancels that, and 0 never
    // closes.
    function test_summonAutoClose() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        surface.scheduleAutoClose(60);
        verify(surface.autoClosePending);
        tryCompare(surface, "expanded", false, 500);
        surface.expandTo("home");
        surface.scheduleAutoClose(60);
        mouseMove(surface, surface.width / 2, 20);
        verify(!surface.autoClosePending, "the pointer arriving cancels it");
        wait(120);
        compare(surface.expanded, true);
        mouseMove(test, farPoint().x, farPoint().y);
        tryCompare(surface, "expanded", false, surface.leaveGrace + 250);
        surface.explicitOpen = true;
        surface.expandTo("home");
        surface.focusKeys();
        surface.scheduleAutoClose(60);
        verify(surface.autoClosePending, "the summon's own focus is not an interaction");
        keyClick(Qt.Key_Tab);
        verify(!surface.autoClosePending, "a key cancels it");
        surface.scheduleAutoClose(0);
        verify(!surface.autoClosePending, "0 never closes");
        surface.explicitOpen = false;
    }
    // The busy guard holds every collapse path but Escape, for at most its
    // timeout per hold.
    function test_busyGuardBlocksCollapseButEscape() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.busyTimeout = 150;
        surface.expandTo("home");
        surface.beginBusy();
        compare(surface.busyCount, 1);
        compare(surface.collapse(), false, "a plain collapse is refused");
        surface.updatePull(-400);
        compare(surface.expanded, true, "so is a push");
        surface.endPull();
        surface.scheduleAutoClose(20);
        wait(60);
        compare(surface.expanded, true, "and the summon auto-close");
        surface.endBusy();
        compare(surface.busyCount, 0);
        compare(surface.collapse(), true);
        surface.expandTo("home");
        surface.beginBusy();
        surface.beginBusy();
        compare(surface.busyCount, 2);
        tryCompare(surface, "busyCount", 0, 600, "each hold lapses after busyTimeout");
        surface.beginBusy();
        surface.focusKeys();
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "Escape closes whatever holds it");
        surface.endBusy();
    }
    // The host's safety resets close a busy island and drop every hold, so
    // nothing stale survives into the next open.
    function test_hostResetClosesABusyIslandAndDropsItsHolds() {
        var surface = createTemporaryObject(surfaceComponent, test);
        var closed = { count: 0 };
        surface.collapseRequested.connect(function () { closed.count++; });
        surface.expandTo("home");
        surface.beginBusy();
        surface.beginBusy();
        compare(surface.collapse(), false);
        compare(surface.resetForHost(), true);
        compare(surface.expanded, false);
        compare(surface.busyCount, 0, "the reset drops every hold");
        compare(closed.count, 1);
        surface.endBusy();
        compare(surface.busyCount, 0, "a late endBusy() from the old menu is harmless");
        surface.expandTo("home");
        compare(surface.collapse(), true, "the next open closes normally");
    }
    function test_busyEndRestartsTheLeaveGrace() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        surface.beginBusy();
        var p = pillPoint(surface);
        mouseMove(surface, p.x, p.y);
        mouseMove(test, farPoint().x, farPoint().y);
        wait(surface.leaveGrace + 100);
        compare(surface.expanded, true, "busy holds it open past the grace");
        surface.endBusy();
        tryCompare(surface, "expanded", false, surface.leaveGrace + 250, "then the grace runs again");
    }
    // Live music puts the cover in the left wing and the spectrum in the
    // right, with the centre of the notch body left empty.
    function test_closedWingsWhilePlaying() {
        // Live bars need motion; init() reduces it for every other test.
        design.reducedMotion = false;
        facade.remoteArtwork = true;
        var track = endpoint();
        track.artworkPath = coverPath();
        facade.selectedEndpoint = track;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        compare(surface.closedModel.state, "live");
        compare(card.width, design.liveWidth);
        var left = findChild(surface, "leftWing"), right = findChild(surface, "rightWing");
        var art = findChild(surface, "pillArtwork"), bars = findChild(surface, "spectrumBars");
        tryVerify(function () { return art.visible && bars.visible; }, 1000);
        var body = findChild(surface, "notchBody");
        var centreLeft = (body.width - (design.idleWidth - 2 * design.flareClosed)) / 2;
        var artBox = art.mapToItem(body, 0, 0, art.width, art.height);
        var barsBox = bars.mapToItem(body, 0, 0, bars.width, bars.height);
        verify(artBox.x + artBox.width <= centreLeft + 0.5, "the cover stays in the left wing");
        verify(barsBox.x >= body.width - centreLeft - 0.5, "the bars stay in the right wing");
        compare(art.width, Math.min(design.wingArt, surface.pillHeight - design.hairlineHeight - 4 - 4));
        compare(art.radius, design.wingArtRadius);
        verify(!findChild(surface, "hudInline").visible);
    }
    // The wings mirror each other: the cover's left edge and the spectrum's
    // right edge sit the same inset from their ends of the body, and the
    // spectrum fits its wing instead of running into the rounded corner.
    function test_closedWingsMirror() {
        design.reducedMotion = false;
        facade.remoteArtwork = true;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        var body = findChild(surface, "notchBody");
        var art = findChild(surface, "pillMusicGlyph"), bars = findChild(surface, "spectrumBars");
        var right = findChild(surface, "rightWing");
        tryVerify(function () { return art.visible && bars.visible; }, 1000);
        var artBox = art.mapToItem(body, 0, 0, art.width, art.height);
        var barsBox = bars.mapToItem(body, 0, 0, bars.width, bars.height);
        compare(artBox.x, design.closedInset);
        compare(body.width - (barsBox.x + barsBox.width), design.closedInset);
        compare(bars.width, design.closedSpectrumWidth);
        verify(bars.width + design.closedInset <= right.width, "the spectrum fits its wing");
        var last = findChild(bars, "spectrumBar" + (design.spectrumBands - 1));
        compare(last.x + last.width, bars.width, "bars packed a pixel apart fill the spectrum's width");
    }
    DesignTokens {
        id: movingDesign
    }
    Component {
        id: barsComponent
        SpectrumBars {
            tokens: movingDesign
            live: true
            playing: true
            maxHeight: 16
        }
    }
    // A pause lets the last line fall flat over the decay instead of
    // snapping; under reduced motion it snaps.
    function test_spectrumDecaysOnPause() {
        var bars = createTemporaryObject(barsComponent, test);
        bars.levels = [99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99];
        var bar = findChild(bars, "spectrumBar0");
        compare(bar.height, 16);
        bars.playing = false;
        verify(bar.height > movingDesign.spectrumMinBar, "the bar is still falling right after the pause");
        wait(movingDesign.spectrumDecayDuration / 3);
        verify(bar.height > movingDesign.spectrumMinBar && bar.height < 16, "part-way down");
        tryCompare(bar, "height", movingDesign.spectrumMinBar, movingDesign.spectrumDecayDuration + 200);
        bars.playing = true;
        compare(bar.height, 16);
        movingDesign.reducedMotion = true;
        bars.playing = false;
        compare(bar.height, movingDesign.spectrumMinBar, "reduced motion drops at once");
        movingDesign.reducedMotion = false;
    }
    Component {
        id: movingPillComponent
        IslandSurface {
            tokens: movingDesign
            coordinator: facade
            pillHeight: 26
            width: movingDesign.notchWindowWidth()
            height: movingDesign.notchWindowHeight()
        }
    }
    // The shape moves first: music starting grows the notch before the
    // wing content shows, and only over the last part of the growth.
    function test_closedContentWaitsForTheShape() {
        facade.selectedEndpoint = null;
        facade.fileSettings = ({ idleStyle: "empty" });
        var surface = createTemporaryObject(movingPillComponent, test);
        var pill = findChild(surface, "islandPill"), card = findChild(surface, "islandCard");
        tryCompare(card, "width", movingDesign.idleWidth, 1000);
        var from = card.width, target = movingDesign.liveWidth;
        var early = [];
        var watch = function () {
            if (pill.opacity > 0 && surface.closedWidth < from + 0.7 * (target - from) - 0.5)
                early.push(surface.closedWidth);
        };
        pill.opacityChanged.connect(watch);
        facade.selectedEndpoint = endpoint();
        compare(surface.closedModel.state, "live");
        compare(pill.opacity, 0, "nothing shows while the notch is still idle-wide");
        tryCompare(pill, "opacity", 1, 2000);
        pill.opacityChanged.disconnect(watch);
        compare(early.length, 0, "no content before the notch had room for it");
    }
    // Content leaves as the notch shrinks, not a frame before it: the old
    // wings stay drawn, fading, while the width is already moving.
    function test_closedContentFadesWithTheShrink() {
        facade.fileSettings = ({ idleStyle: "empty" });
        var surface = createTemporaryObject(movingPillComponent, test);
        var pill = findChild(surface, "islandPill"), card = findChild(surface, "islandCard");
        tryCompare(pill, "opacity", 1, 2000);
        facade.selectedEndpoint = null;
        compare(surface.closedModel.state, "idle");
        compare(pill.leftContent, "art", "the cover is still drawn as the shrink starts");
        tryVerify(function () { return card.width < movingDesign.liveWidth - 1; }, 1000, "the width moves");
        tryCompare(pill, "leftContent", "none", 1000);
        verify(card.width > movingDesign.idleWidth + 1 || pill.opacity === 0, "the content is gone by the time the shrink ends");
    }
    // Art that is about to load never flashes the music glyph first; the
    // glyph stands in only once the art is late or missing.
    function test_localWingArtWorksWithOnlineArtworkOff() {
        facade.remoteArtwork = false;
        var track = endpoint();
        track.artworkPath = coverPath();
        facade.selectedEndpoint = track;
        var surface = createTemporaryObject(livePillComponent, test);
        var art = findChild(surface, "pillArtwork"), glyph = findChild(surface, "pillMusicGlyph");
        verify(art.visible, "a local cover is admitted without network artwork consent");
        tryCompare(art, "ready", true);
        verify(!glyph.visible, "the loaded local cover takes the glyph's place");
    }
    function test_noPlaceholderGlyphWhileArtLoads() {
        facade.remoteArtwork = true;
        var track = endpoint();
        track.artworkPath = "/nonexistent/nookisle-cover.png";
        facade.selectedEndpoint = track;
        var surface = createTemporaryObject(livePillComponent, test);
        var glyph = findChild(surface, "pillMusicGlyph"), art = findChild(surface, "pillArtwork");
        verify(art.visible && !glyph.visible, "the empty cover box waits for the art");
        compare(art.color, Qt.rgba(0, 0, 0, 0), "no tinted placeholder square");
        tryVerify(function () { return glyph.visible; }, 1000, "art that never arrives falls back to the glyph");
        track = endpoint();
        facade.selectedEndpoint = track;
        verify(glyph.visible && !art.visible, "a track without art shows the glyph at once");
    }
    // With no hardware notch (the default) the title sits in the body's
    // centre, between the cover and the bars; the setting empties it.
    function test_closedTitleInTheCentre() {
        design.reducedMotion = false;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        var body = findChild(surface, "notchBody");
        var title = findChild(surface, "closedTitle"), art = findChild(surface, "pillMusicGlyph");
        var bars = findChild(surface, "spectrumBars");
        tryVerify(function () { return title.visible; }, 1000, "the title appears after the closed shape is ready");
        compare(title.text, "Test track");
        var titleBox = title.mapToItem(body, 0, 0, title.width, title.height);
        var artBox = art.mapToItem(body, 0, 0, art.width, art.height);
        var barsBox = bars.mapToItem(body, 0, 0, bars.width, bars.height);
        compare(titleBox.x, artBox.x + artBox.width + design.gap);
        compare(titleBox.x + titleBox.width, barsBox.x - design.gap);
        facade.fileSettings = ({ hardwareNotch: true });
        tryVerify(function () { return !findChild(surface, "centreSlot").visible; }, 1000,
            "a camera cutout keeps the centre empty after the content fades");
    }
    // The closed title keeps its place and width when the bars give way to
    // the narrower pause glyph: the right wing's slot is as wide in both.
    function test_closedTitleHoldsItsPlaceOnPause() {
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        var body = findChild(surface, "notchBody");
        var title = findChild(surface, "closedTitle");
        tryVerify(function () { return title.visible; }, 1000);
        var playing = title.mapToItem(body, 0, 0, title.width, title.height);
        var paused = endpoint();
        paused.status = "Paused";
        facade.selectedEndpoint = paused;
        facade.endpoints = [paused];
        var glyph = findChild(surface, "pauseGlyph");
        tryVerify(function () { return glyph.visible; }, 2000, "the pause glyph replaces the bars");
        verify(title.visible, "within the grace the title stays");
        var rest = title.mapToItem(body, 0, 0, title.width, title.height);
        compare(rest.x, playing.x, "the title does not move");
        compare(rest.width, playing.width, "nor change its room");
        var glyphBox = glyph.mapToItem(body, 0, 0, glyph.width, glyph.height);
        verify(rest.x + rest.width <= glyphBox.x - design.gap, "and stays clear of the glyph");
    }
    // The privacy dots never reflow the idle glance: its dot stays beside
    // its line and the pair keeps its centre.
    function test_privacyDotsKeepTheIdleGlanceInPlace() {
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        var surface = createTemporaryObject(livePillComponent, test);
        var body = findChild(surface, "notchBody");
        var glance = findChild(surface, "idleGlance");
        verify(glance && glance.visible);
        var dot = findChild(glance, "glanceDot"), line = findChild(glance, "glanceLine");
        var dotBefore = dot.mapToItem(body, 0, 0).x, lineBefore = line.mapToItem(body, 0, 0).x;
        compare(line.x, dot.x + dot.width + design.gap, "the dot hugs the line");
        surface.privacy = { mic: ["Zoom"], camera: [], screen: [], micMuted: false, any: true };
        tryVerify(function () { return findChild(surface, "privacyIndicators").visible; }, 1000);
        compare(dot.mapToItem(body, 0, 0).x, dotBefore, "the dot does not jump to the inset");
        compare(line.mapToItem(body, 0, 0).x, lineBefore, "the line does not move");
        surface.privacy = { mic: ["Zoom"], camera: [], screen: [], micMuted: true, any: true };
        compare(dot.mapToItem(body, 0, 0).x, dotBefore, "nor with the wider muted glyph");
        surface.privacy = null;
        compare(dot.mapToItem(body, 0, 0).x, dotBefore);
    }
    // Privacy dots sit in a column at the trailing end; the right wing's
    // content moves in beside them, and a muted captured mic is a glyph.
    function test_privacyIndicators() {
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        var body = findChild(surface, "notchBody");
        var column = findChild(surface, "privacyIndicators");
        var bars = findChild(surface, "spectrumBars");
        var pill = findChild(surface, "islandPill");
        verify(!column.visible, "nothing captures, nothing shows");
        var before = bars.mapToItem(body, 0, 0, bars.width, bars.height);
        surface.privacy = { mic: ["Zoom"], camera: ["Chromium"], screen: [], micMuted: false, any: true };
        tryVerify(function () { return column.visible && column.opacity === 1; }, 1000);
        verify(findChild(surface, "privacyMic").visible);
        verify(findChild(surface, "privacyCamera").visible);
        verify(!findChild(surface, "privacyScreen").visible);
        verify(!findChild(surface, "privacyMicMuted").visible);
        compare(column.Accessible.name, "Mic: Zoom · Camera: Chromium");
        var pillBox = pill.mapToItem(body, 0, 0, pill.width, pill.height);
        var columnBox = column.mapToItem(body, 0, 0, column.width, column.height);
        compare(columnBox.x + columnBox.width, pillBox.x + pillBox.width - design.privacyEdge);
        var after = bars.mapToItem(body, 0, 0, bars.width, bars.height);
        compare(after.x, before.x - design.privacyInset, "the bars move in; the notch keeps its width");
        compare(pill.width, pillBox.width);
        surface.privacy = { mic: ["Zoom"], camera: [], screen: [], micMuted: true, any: true };
        verify(findChild(surface, "privacyMicMuted").visible, "muted in the call");
        verify(!findChild(surface, "privacyMic").visible);
        after = bars.mapToItem(body, 0, 0, bars.width, bars.height);
        compare(after.x, before.x - design.privacyMutedInset);
        surface.privacy = null;
        tryVerify(function () { return !column.visible; }, 1000);
    }
    // The dots stay above the peek and the inline HUD while the capture
    // goes on, and leave only when the island opens (the chip names the apps).
    function test_privacyDotsStayOverPeekAndHud() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.privacy = { mic: ["Zoom"], camera: ["Chromium"], screen: [], micMuted: false, any: true };
        var dots = findChild(surface, "privacyIndicators");
        var pill = findChild(surface, "islandPill");
        tryVerify(function () { return dots.visible && dots.opacity === 1; }, 1000);
        surface.peekKind = "timerDone";
        surface.peekEvent = { icon: "ring", title: "Tea", detail: "Timer done", level: -1, alert: false };
        surface.peekActive = true;
        var peek = findChild(surface, "islandPeek");
        tryVerify(function () { return peek.opacity === 1 && !pill.visible; }, 3000, "the peek settles over the closed row");
        verify(dots.visible && dots.opacity === 1, "the dots stay over a settled peek");
        verify(findChild(surface, "privacyMic").visible && findChild(surface, "privacyCamera").visible);
        verify(dots.parent === peek.parent && dots.z >= peek.z, "drawn in the same layer as the peek, above it");
        var siblings = dots.parent.children, dotsIndex = -1, peekIndex = -1;
        for (var i = 0; i < siblings.length; ++i) {
            if (siblings[i] === dots) dotsIndex = i;
            if (siblings[i] === peek) peekIndex = i;
        }
        verify(dotsIndex > peekIndex, "declared after the peek, so painted on top");
        var dotsBox = dots.mapToItem(dots.parent, 0, 0, dots.width, dots.height);
        compare(dotsBox.x + dotsBox.width, dots.parent.width - design.privacyEdge, "at the peek body's trailing end");
        surface.peekActive = false;
        tryVerify(function () { return peek.opacity === 0; }, 3000);
        surface.hud.show("volume", 0.5, false);
        var hud = findChild(surface, "hudInline");
        tryVerify(function () { return hud.visible; }, 2000);
        verify(dots.visible && dots.opacity === 1, "and over the inline readout");
        surface.expanded = true;
        tryVerify(function () { return dots.opacity === 0 || !dots.visible; }, 3000, "open, the header's chip takes over");
    }
    function test_privacyChipInTheOpenHeader() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.privacy = { mic: ["Zoom"], camera: [], screen: ["OBS"], micMuted: false, any: true };
        surface.expanded = true;
        var chip = null;
        tryVerify(function () { chip = findChild(surface, "privacyChip"); return !!chip && chip.visible; }, 2000);
        compare(findChild(surface, "privacyChipText").text, "Mic: Zoom · Screen: OBS");
        facade.fileSettings = ({ hardwareNotch: true });
        tryVerify(function () { return !findChild(surface, "privacyChip"); }, 2000, "nothing over a camera cutout");
    }
    // A device peek is a pill-high event row: glyph, name, detail, and a
    // battery bar only when the device reports its battery.
    function test_devicePeekRow() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekKind = "device";
        surface.peekEvent = { icon: "headset", title: "JBL LIVE PRO 2", detail: "Connected · Now playing here", level: 0.8, alert: false };
        surface.peekActive = true;
        var row = findChild(surface, "peekEventRow");
        tryVerify(function () { return row.visible; }, 2000);
        compare(findChild(surface, "peekEventTitle").text, "JBL LIVE PRO 2");
        compare(findChild(surface, "peekEventDetail").text, "Connected · Now playing here");
        verify(findChild(surface, "peekEventTrack").visible);
        compare(findChild(surface, "peekEventPercent").text, "80%");
        compare(findChild(surface, "islandPeek").Accessible.name, "JBL LIVE PRO 2, Connected · Now playing here, 80 percent");
        compare(surface.peekTargetHeight, surface.pillHeight, "an event peek keeps the pill's height");
        surface.peekEvent = { icon: "speaker", title: "Speaker", detail: "Sound output", level: -1, alert: false };
        verify(!findChild(surface, "peekEventTrack").visible, "no battery, no bar");
        verify(!findChild(surface, "peekEventPercent").visible);
        surface.peekActive = false;
    }
    // A running timer beside the music is a minimal ring; alone it fills the
    // notch with its ring, label and minutes.
    function test_timerActivity() {
        facade.timersEnabled = true;
        var at = Date.now() + 12 * 60000 + 30000;
        facade.timerList = [{ unit: "omarchy-reminder-15m-1", label: "Tea", minutes: 15, at: at }];
        var surface = createTemporaryObject(livePillComponent, test);
        var minimal = findChild(surface, "minimalActivity");
        tryVerify(function () { return minimal.visible; }, 2000);
        verify(findChild(surface, "minimalTimer").visible, "the music keeps the notch; the timer is a ring");
        var track = endpoint();
        track.status = "Paused";
        facade.selectedEndpoint = track;
        surface.closedModel.lingering = false;
        var ring = findChild(surface, "timerGlyph");
        tryVerify(function () { return ring.visible; }, 2000, "alone, the timer fills the notch");
        compare(findChild(surface, "activityValue").text, "13m");
        compare(findChild(surface, "activityLabel").text, "Tea");
        compare(findChild(surface, "islandPill").Accessible.name, "Tea, 13m left");
    }
    // The header's Timers entry reads as timers: a stopwatch, named for
    // assistive tech, with the running timer's time left beside it, and a
    // wash while the view is open.
    function test_headerTimersEntryIsLabelled() {
        facade.timersEnabled = true;
        facade.timerList = [];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.expanded = true;
        var button = findChild(surface, "headerTimersButton");
        tryVerify(function () { return button.visible; }, 2000);
        compare(findChild(button, "headerTimersIcon").name, "timer", "a stopwatch, not a bare ring");
        compare(button.Accessible.name, "Timers");
        var label = findChild(button, "headerTimersLabel");
        verify(!label.visible, "no timer, no time");
        verify(!findChild(button, "headerTimersOpen").visible);
        var idleWidth = button.width;
        facade.timerList = [{ unit: "omarchy-reminder-15m-1", label: "Tea", minutes: 15, at: Date.now() + 13 * 60000 + 30000 }];
        tryVerify(function () { return label.visible; }, 2000, "a running timer shows its time left");
        verify(/^1[34]m$/.test(label.text), "the time left: " + label.text);
        tryVerify(function () { return button.width >= findChild(button, "headerTimersIcon").width + label.width + 2 * design.gap; },
            1000, "the entry grows to hold it");
        verify(button.width > idleWidth);
        compare(button.Accessible.name, "Timers, Tea, " + label.text + " left");
        var slots = findChild(surface, "headerSlots"), centre = findChild(surface, "headerCentre");
        verify(slots.x >= centre.x + centre.width, "the slots stay clear of the centre span");
        button.activated();
        compare(surface.view, "timers");
        verify(findChild(button, "headerTimersOpen").visible, "open, the entry is washed like a selected tab");
        compare(button.Accessible.name, "Close timers");
    }
    // The time left never pushes the header's right-hand row into the
    // reserved centre (a camera cutout with hardwareNotch on): in a full
    // row (battery, gear, Timers) the label steps aside when it does not
    // fit, and the stopwatch still names the time. With room, it shows.
    function test_timerLabelKeepsTheHeaderRowClearOfTheCentre_data() {
        return [{ tag: "13m", minutes: 13 }, { tag: "1h 05m", minutes: 65 }];
    }
    function test_timerLabelKeepsTheHeaderRowClearOfTheCentre(data) {
        facade.timersEnabled = true;
        facade.fileSettings = ({ hardwareNotch: true });
        facade.timerList = [{ unit: "omarchy-reminder-1", label: "Tea", minutes: data.minutes,
            at: Date.now() + data.minutes * 60000 - 30000 }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: false });
        surface.expandTo("home");
        var header = findChild(surface, "notchHeader");
        var slots = findChild(surface, "headerSlots"), centre = findChild(surface, "headerCentre");
        var button = findChild(surface, "headerTimersButton");
        tryVerify(function () { return button.visible && findChild(surface, "headerBatterySlot").visible; }, 2000);
        verify(findChild(surface, "headerSettingsButton").visible, "the gear is in the row");
        waitForRendering(surface);
        verify(slots.x >= centre.x + centre.width, "the populated row ends clear of the centre: "
            + slots.x + " against " + (centre.x + centre.width));
        var label = findChild(button, "headerTimersLabel");
        compare(label.text, data.tag);
        verify(/left$/.test(button.Accessible.name) && button.Accessible.name.indexOf(data.tag) > 0,
            "the name keeps the time: " + button.Accessible.name);
        // Without the battery the row has room for the label.
        surface.batteryReading = ({ present: false });
        tryVerify(function () { return label.visible; }, 1000, "with room, the time shows");
        waitForRendering(surface);
        verify(slots.x >= centre.x + centre.width, "and the row still ends clear of the centre");
    }
    function test_timersView() {
        facade.timersEnabled = true;
        facade.fileSettings = ({ timerPresets: [5, 25] });
        facade.timerList = [{ unit: "omarchy-reminder-15m-1", label: "Tea", minutes: 15, at: Date.now() + 10 * 60000 }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.expanded = true;
        var button = findChild(surface, "headerTimersButton");
        tryVerify(function () { return button.visible; }, 2000);
        button.activated();
        compare(surface.view, "timers");
        var view = null;
        tryVerify(function () { view = findChild(surface, "timersViewLoader").item; return !!view; }, 2000);
        findChild(view, "timerPreset25").clicked();
        compare(facade.startedTimers.length, 1);
        compare(facade.startedTimers[0].minutes, 25);
        var minutes = findChild(view, "timerMinutes");
        minutes.text = "2000";
        verify(!findChild(view, "timerStart").enabled, "more than a day is refused before it is sent");
        minutes.text = "7";
        findChild(view, "timerLabel").text = "Pasta";
        findChild(view, "timerStart").clicked();
        compare(facade.startedTimers[1].minutes, 7);
        compare(facade.startedTimers[1].label, "Pasta");
        findChild(view, "timerCancel").clicked();
        compare(facade.cancelledTimers, ["omarchy-reminder-15m-1"]);
        surface.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(surface.view, "home", "Escape leaves the sub-view first");
        facade.timersEnabled = false;
        surface.view = "timers";
        compare(surface.view, "home", "no Timers view while timers are off");
        verify(!button.visible);
    }
    // A recording outranks the music: it fills the notch in red, and the
    // music shrinks to a glyph at the trailing end. Open, its chip stops it.
    function test_recordingActivity() {
        facade.recordingState = { active: true, startedAt: Date.now() - 12 * 60000 - 5000, path: "/v/a.mp4" };
        facade.recordingShown = true;
        var surface = createTemporaryObject(livePillComponent, test);
        var glyph = findChild(surface, "recordingGlyph");
        tryVerify(function () { return glyph.visible; }, 2000);
        compare(findChild(surface, "activityValue").text, "12m");
        compare(findChild(surface, "activityValue").color, design.recordingInk);
        compare(findChild(surface, "activityLabel").text, "Screen recording");
        verify(findChild(surface, "minimalActivity").visible, "the music waits as a glyph");
        compare(findChild(surface, "islandPill").Accessible.name, "Screen recording, 12m");
        verify(!findChild(surface, "spectrumBars").visible, "no bars while the recording holds the notch");
        surface.expanded = true;
        var chip = null;
        tryVerify(function () { chip = findChild(surface, "recordingChip"); return !!chip && chip.visible; }, 2000);
        compare(findChild(surface, "recordingChipText").text, "REC 12m");
        mouseClick(findChild(surface, "recordingStop"));
        compare(facade.recordingStops, 1);
        verify(!findChild(surface, "headerRecordingStop").visible, "the chip offers Stop; no second button");
        facade.fileSettings = ({ hardwareNotch: true });
        tryVerify(function () { return !findChild(surface, "recordingChip"); }, 2000, "no chip over a camera cutout");
        var stop = findChild(surface, "headerRecordingStop");
        verify(stop.visible, "Stop stays reachable in the right-hand slots");
        stop.activated();
        compare(facade.recordingStops, 2);
        surface.expanded = false;
        facade.recordingShown = false;
        tryVerify(function () { return !glyph.visible; }, 2000, "the music comes back when it stops");
        verify(!stop.visible);
    }
    function test_timerChipOpensTheView() {
        facade.timersEnabled = true;
        facade.timerList = [{ unit: "omarchy-reminder-5m-1", label: "Tea", minutes: 5, at: Date.now() + 4 * 60000 }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.expanded = true;
        var chip = null;
        tryVerify(function () { chip = findChild(surface, "timerChip"); return !!chip && chip.visible; }, 2000);
        compare(findChild(surface, "timerChipText").text, "4m");
        mouseClick(chip);
        compare(surface.view, "timers");
    }
    function test_capturePeekShowsTheThumbnail() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.peekKind = "capture";
        surface.peekEvent = { icon: "image", title: "Screenshot", detail: "Added to shelf", level: -1, alert: false,
            thumbnail: "/tmp/screenshot-1.png" };
        surface.peekActive = true;
        var thumb = findChild(surface, "peekEventThumbnail");
        tryVerify(function () { return findChild(surface, "peekEventRow").visible; }, 2000);
        verify(thumb.visible && !findChild(surface, "peekEventIcon").visible, "the picture stands in for the glyph");
        compare(String(thumb.source), "file:///tmp/screenshot-1.png");
        compare(thumb.sourceSize.width, 48, "decoded once at thumbnail size");
        verify(!thumb.cache);
        surface.peekEvent = { icon: "record", title: "Screen recording", detail: "Added to shelf", level: -1, alert: false, thumbnail: "" };
        verify(!thumb.visible && findChild(surface, "peekEventIcon").visible);
        surface.peekActive = false;
    }
    // An armed sleep timer shrinks to a moon and its time. Without a camera
    // cutout it closes the centre region, just before the bars, which stay
    // put, and the title makes room; over a cutout it takes the outer end
    // and the bars move in beside it.
    function test_sleepTimerShowsAsMinimalGlyph() {
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        var body = findChild(surface, "notchBody");
        var pill = findChild(surface, "islandPill");
        // The right wing's content: the bars, or the play-state glyph when
        // the bars have no slot.
        var bars = pill.spectrumSlot ? findChild(pill, "spectrumBars") : findChild(pill, "playStateGlyph");
        function box(item) { return item.mapToItem(body, 0, 0, item.width, item.height); }
        var barsBefore = box(bars);
        facade.sleepDeadline = new Date(2026, 8, 27, 23, 10).getTime();
        var minimal = findChild(surface, "minimalActivity");
        tryVerify(function () { return minimal.visible; }, 2000);
        verify(findChild(surface, "minimalSleep").visible);
        var minimalBox = box(minimal), barsBox = box(bars), pillBox = box(pill);
        compare(barsBox.x, barsBefore.x, "the bars stay at their inset");
        compare(barsBox.x + barsBox.width, pillBox.x + pillBox.width - design.closedInset);
        compare(minimalBox.x + minimalBox.width, barsBox.x - design.gap, "the glyph ends the centre region");
        var title = findChild(surface, "closedTitle");
        var titleBox = box(title);
        compare(titleBox.x + titleBox.width, minimalBox.x - design.gap, "the title makes room");
        facade.fileSettings = ({ hardwareNotch: true });
        tryVerify(function () {
            minimalBox = box(minimal); pillBox = box(pill);
            return Math.abs(minimalBox.x + minimalBox.width - (pillBox.x + pillBox.width - design.closedInset)) < 0.5;
        }, 2000, "over a camera cutout the glyph takes the outer end");
        barsBox = box(bars);
        compare(barsBox.x + barsBox.width, minimalBox.x - design.small, "and the bars move in beside it");
        facade.sleepDeadline = 0;
        tryVerify(function () { return !minimal.visible; }, 2000, "cancelling the timer removes the glyph");
    }
    // A title too long for the centre scrolls through one pass after a track
    // change while playing, then rests elided; a paused track never scrolls.
    function test_closedTitleScrollsOncePerTrack() {
        var surface = createTemporaryObject(movingPillComponent, test);
        var pill = findChild(surface, "islandPill");
        tryCompare(pill, "opacity", 1, 2000);
        var track = endpoint();
        track.trackToken = { id: "long" };
        track.presentation.title = "A title far too long to fit between the cover and the bars of the closed notch";
        facade.selectedEndpoint = track;
        var marquee = findChild(surface, "closedTitleMarquee"), rest = findChild(surface, "closedTitle");
        tryVerify(function () { return pill.titlePassing; }, 1000, "the new track's title scrolls");
        verify(marquee.visible && !rest.visible);
        verify(marquee.overflowing);
        var timer = findChild(surface, "titlePass");
        compare(timer.interval, movingDesign.marqueeDelay
            + Math.ceil((marquee.textWidth + marquee.gap) / movingDesign.marqueeSpeed * 1000) + 100, "exactly one pass");
        timer.triggered();
        verify(!pill.titlePassing && rest.visible && !marquee.visible, "then it rests elided");
        track = endpoint();
        track.status = "Paused";
        track.trackToken = { id: "paused" };
        track.presentation.title = "Another title far too long to fit between the cover and the bars";
        facade.selectedEndpoint = track;
        wait(50);
        verify(!pill.titlePassing, "a paused track does not scroll");
    }
    // Without a hardware notch the inline HUD is one centred row: its two
    // halves meet across a 12 px gap instead of a camera-wide one.
    function test_inlineHudCentresWithoutAHardwareNotch() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("volume", 0.5, false);
        var inline = findChild(surface, "hudInline");
        compare(inline.centerGap, design.medium);
        compare(inline.wingWidth, (inline.width - design.medium) / 2 - inline.sideInset);
        facade.fileSettings = ({ hardwareNotch: true });
        compare(inline.centerGap, design.idleWidth - 2 * design.flareClosed);
    }
    // With nothing playing the default idle style is the glance: it fills
    // the live width the bar spacer already reserves, and the body's input
    // region is that width's body.
    function test_idleGlanceByDefault() {
        facade.selectedEndpoint = null;
        var surface = createTemporaryObject(livePillComponent, test);
        compare(surface.closedModel.state, "idle");
        compare(findChild(surface, "islandCard").width, design.liveWidth);
        var glance = findChild(surface, "idleGlance");
        verify(glance && glance.visible);
        compare(glance.width, findChild(surface, "notchBody").width);
        compare(surface.hitShape.width, design.liveWidth - 2 * design.flareClosed);
        verify(findChild(glance, "glancePrimary").text.length > 0, "the clock shows");
        surface.barHasClock = true;
        compare(glance.barHasClock, true, "the bar's clock reaches the glance");
        facade.selectedEndpoint = endpoint();
        tryVerify(function () { return !findChild(surface, "idleGlance"); }, 1000, "music unloads the glance");
    }
    // The next event reaches the closed notch only with the calendar and
    // the idle opt-in both on, and its title only with its own opt-in.
    function test_idleGlanceEventNeedsBothOptIns() {
        facade.selectedEndpoint = null;
        var start = new Date(Date.now() + 20 * 60000), end = new Date(Date.now() + 50 * 60000);
        facade.calendarSource = { items: [{ sourceId: "work", uid: "u", title: "Standup", allDay: false, todo: false,
            start: start.toISOString(), end: end.toISOString() }] };
        facade.fileSettings = ({ showCalendar: true });
        var surface = createTemporaryObject(livePillComponent, test);
        var glance = findChild(surface, "idleGlance");
        compare(glance.calendarItems.length, 0, "the calendar alone keeps events out of the closed notch");
        verify(findChild(glance, "glancePrimary").text !== "Event");
        facade.fileSettings = ({ idleNextEvent: true });
        compare(glance.calendarItems.length, 0, "the opt-in needs the calendar on");
        facade.fileSettings = ({ showCalendar: true, idleNextEvent: true });
        compare(glance.calendarItems.length, 1);
        compare(findChild(glance, "glancePrimary").text, "Event", "no title without its own opt-in");
        facade.fileSettings = ({ showCalendar: true, idleNextEvent: true, idleEventTitles: true });
        compare(findChild(glance, "glancePrimary").text, "Standup");
    }
    // Over a camera cutout the glance draws nothing in the gap: its line
    // ends short of it, its dot and pip sit past it, and the hairline that
    // would cross it is left out. Horizon falls back to the empty notch.
    function test_idleGlanceClearsTheCameraGap() {
        facade.selectedEndpoint = null;
        facade.fileSettings = ({ hardwareNotch: true });
        var surface = createTemporaryObject(livePillComponent, test);
        surface.batteryReading = { present: true, onBattery: false, level: 0.5, state: "Charging" };
        var body = findChild(surface, "notchBody");
        var glance = findChild(surface, "idleGlance");
        verify(glance && glance.visible);
        var gap = design.idleWidth - 2 * design.flareClosed;
        var gapLeft = (body.width - gap) / 2, gapRight = (body.width + gap) / 2;
        ["glancePrimary", "glanceDot", "glancePip"].forEach(function (name) {
            var item = findChild(glance, name);
            verify(item.visible, name + " shows");
            var box = item.mapToItem(body, 0, 0, item.width, item.height);
            verify(box.x + box.width <= gapLeft + 0.5 || box.x >= gapRight - 0.5, name + " stays out of the camera gap");
        });
        verify(!findChild(glance, "glanceSecondary").visible);
        verify(!findChild(glance, "glanceHairline").visible);
        facade.fileSettings = ({ hardwareNotch: true, idleStyle: "horizon" });
        verify(!findChild(surface, "idleHorizon").visible);
        compare(findChild(surface, "islandCard").width, design.idleWidth);
    }
    // Horizon: a small pill with one accent line, and the base notch's
    // input region so it stays as easy to hover.
    function test_idleHorizon() {
        facade.selectedEndpoint = null;
        facade.fileSettings = ({ idleStyle: "horizon" });
        var surface = createTemporaryObject(livePillComponent, test);
        compare(findChild(surface, "islandCard").width, design.horizonWidth);
        verify(findChild(surface, "idleHorizon").visible);
        var line = findChild(surface, "horizonLine");
        compare(line.width, design.horizonLine);
        compare(line.color, surface.ink.tint);
        verify(!findChild(surface, "horizonPip").visible);
        surface.batteryReading = { present: true, onBattery: false, level: 0.5, state: "Charging" };
        verify(findChild(surface, "horizonPip").visible, "charging shows the pip");
        compare(surface.hitShape.width, design.idleWidth - 2 * design.flareClosed);
    }
    // After a charger banner the idle face is happy for a while, after a
    // low-battery banner worried; then it returns to its own mood.
    function test_idleFaceMoodAfterABanner() {
        facade.selectedEndpoint = null;
        facade.fileSettings = ({ idleStyle: "face" });
        var surface = createTemporaryObject(livePillComponent, test);
        var face = findChild(surface, "closedIdleFace");
        surface.batteryKind = "plugged";
        surface.batteryActive = true;
        compare(surface.closedModel.state, "battery");
        surface.batteryActive = false;
        compare(face.moodOverride, "happy");
        surface.batteryKind = "low";
        surface.batteryActive = true;
        surface.batteryActive = false;
        compare(face.moodOverride, "worried");
        tryCompare(face, "moodOverride", "", design.faceMoodDuration + 500);
        surface.batteryKind = "unplugged";
        surface.batteryActive = true;
        surface.batteryActive = false;
        compare(face.moodOverride, "", "unplugging has no mood");
    }
    // The closed notch's accessible name says what it shows: the track and
    // its state, the banner's label, the glance's line, or that nothing
    // plays; never "Paused" with nothing there.
    function test_closedAccessibleName() {
        var surface = createTemporaryObject(livePillComponent, test);
        var pill = findChild(surface, "islandPill");
        compare(pill.Accessible.name, "Test track. Playing");
        facade.selectedEndpoint = null;
        var glance = findChild(surface, "idleGlance");
        compare(pill.Accessible.name, glance.Accessible.name);
        verify(pill.Accessible.name.length > 0 && pill.Accessible.name.indexOf("Paused") < 0);
        facade.fileSettings = ({ idleStyle: "empty" });
        compare(pill.Accessible.name, "Nothing playing");
        surface.batteryLabel = "Charging";
        surface.batteryActive = true;
        compare(pill.Accessible.name, "Charging");
    }
    // Paused within the grace, the closed cover dims; playing again it
    // returns to full strength.
    function test_pausedWingArtDims() {
        facade.fileSettings = ({ pauseGrace: 5000 });
        var surface = createTemporaryObject(livePillComponent, test);
        var wing = findChild(surface, "leftWing");
        compare(wing.opacity, 1);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        compare(surface.closedModel.state, "live", "still live through the grace");
        compare(wing.opacity, design.pausedWingOpacity);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Playing" });
        compare(wing.opacity, 1);
    }
    // Paused within the grace, the right wing says so with two short bars,
    // not a row of flat dots or dimmed bars: the pause glyph takes the
    // play-state glyph's place (reduced motion shows no live bars), at the
    // same inset, and playing brings it back.
    function test_pausedRestShowsAPauseGlyph() {
        facade.fileSettings = ({ pauseGrace: 5000 });
        var surface = createTemporaryObject(livePillComponent, test);
        var still = findChild(surface, "playStateGlyph"), pause = findChild(surface, "pauseGlyph");
        verify(still.visible && !pause.visible);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        compare(surface.closedModel.state, "live", "still live through the grace");
        verify(pause.visible && pause.opacity === 1, "the pause glyph shows");
        verify(!still.visible);
        var body = findChild(surface, "notchBody");
        var box = pause.mapToItem(body, 0, 0, pause.width, pause.height);
        compare(body.width - (box.x + box.width), design.closedInset);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Playing" });
        verify(!pause.visible && still.visible);
    }
    function test_pausedGlyphKeepsRoomForMinimalActivityAndPrivacy() {
        facade.fileSettings = ({ pauseGrace: 5000 });
        var surface = createTemporaryObject(livePillComponent, test);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        facade.sleepDeadline = Date.now() + 10 * 60000;
        surface.privacy = { mic: ["Zoom"], camera: [], screen: [], micMuted: false, any: true };
        var body = findChild(surface, "notchBody"), pill = findChild(surface, "islandPill");
        var pause = findChild(surface, "pauseGlyph"), minimal = findChild(surface, "minimalActivity");
        var dots = findChild(surface, "privacyIndicators");
        tryVerify(function () { return pause.visible && minimal.visible && dots.visible; }, 1000);
        function box(item) { return item.mapToItem(body, 0, 0, item.width, item.height); }
        var pauseBox = box(pause), minimalBox = box(minimal), dotsBox = box(dots);
        compare(pauseBox.x + pauseBox.width, body.width - pill.rightInset,
            "the pause glyph uses the privacy inset");
        verify(pill.rightContentWidth >= pause.width, "the music slot holds the pause glyph");
        compare(minimalBox.x + minimalBox.width, body.width - pill.rightInset - pill.rightContentWidth - design.gap,
            "the minimal glyph ends the centre region beside the music slot, where it sits while playing too");
        verify(minimalBox.x + minimalBox.width <= pauseBox.x - design.gap, "clear of the visible pause glyph");
        verify(pauseBox.x + pauseBox.width < dotsBox.x, "the pause glyph clears the privacy dots");
        var title = findChild(surface, "closedTitle"), titleBox = box(title);
        compare(titleBox.x + titleBox.width, minimalBox.x - design.gap,
            "the title ends before the minimal glyph");
    }
    // With motion, the bars fall first and the pause glyph follows.
    function test_pauseGlyphWaitsForTheBarsToFall() {
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        facade.fileSettings = ({ pauseGrace: 5000 });
        var surface = createTemporaryObject(movingPillComponent, test);
        var bars = findChild(surface, "spectrumBars"), pause = findChild(surface, "pauseGlyph");
        tryCompare(findChild(surface, "islandPill"), "opacity", 1, 2000);
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        verify(bars.visible, "live bars with motion");
        verify(bars.falling && bars.opacity === 1 && !pause.visible, "the bars fall first");
        tryCompare(pause, "opacity", 1, movingDesign.spectrumDecayDuration + 500);
        tryCompare(bars, "opacity", 0, 500, "then the flat dots give way to the glyph");
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Playing" });
        tryCompare(bars, "opacity", 1, 500);
        tryVerify(function () { return !pause.visible; }, 500);
    }
    function test_idleWhenNothingPlays() {
        facade.selectedEndpoint = null;
        facade.fileSettings = ({ idleStyle: "empty" });
        var surface = createTemporaryObject(livePillComponent, test);
        compare(surface.closedModel.state, "idle");
        compare(findChild(surface, "islandCard").width, design.idleWidth);
        verify(!findChild(surface, "pillArtwork").visible && !findChild(surface, "pillMusicGlyph").visible);
        verify(!findChild(surface, "spectrumBars").visible && !findChild(surface, "playStateGlyph").visible);
        compare(surface.hitShape.width, design.idleWidth - 2 * design.flareClosed, "the input region is the idle body");
    }
    function test_liveActivityAndSpectrumColourSettings() {
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        design.artColor = "#e2402e";
        var surface = createTemporaryObject(livePillComponent, test);
        compare(findChild(surface, "spectrumBar2").color, surface.ink.tint);
        facade.fileSettings = ({ coloredSpectrogram: false });
        compare(findChild(surface, "spectrumBar2").color, surface.ink.text, "plain ink when colouring is off");
        facade.fileSettings = ({ musicLiveActivity: false });
        compare(surface.closedModel.state, "idle", "the live activity off keeps the notch idle while playing");
    }
    // A state change springs the closed width rather than jumping.
    function test_closedWidthSprings() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(livePillComponent, test);
        var card = findChild(surface, "islandCard");
        compare(card.width, design.liveWidth);
        surface.hud.show("volume", 0.5, false);
        verify(card.width < design.hudInlineWidth, "it grows on the spring");
        compare(surface.hitShape.width, design.liveWidth - 2 * design.flareClosed, "while the input region stays put");
        tryCompare(card, "width", design.hudInlineWidth, 1000);
        surface.hud.active = false;
        tryCompare(card, "width", design.liveWidth, 1000);
    }
    // Home's inline lyric line opens the Lyrics sub-view.
    function test_inlineLyricOpensLyrics() {
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = fixtureLines();
        lyricsFixture.currentIndex = 1;
        var surface = lyricsSurface();
        surface.expandTo("home");
        waitForRendering(surface);
        var line = findChild(surface, "inlineLyric");
        verify(line.visible);
        mouseClick(line);
        compare(surface.view, "lyrics");
        verify(findChild(surface, "lyricsBackButton").visible);
    }
    function hudBarPoint(surface, barName, fraction) {
        var bar = findChild(surface, barName);
        return { bar: bar, x: bar.width * fraction, y: bar.height / 2 };
    }
    // Below style: a pill under the closed notch; the notch keeps its state.
    function test_hudBelowStyle() {
        facade.fileSettings = ({ hudStyle: "below" });
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("brightness", 0.4, false);
        waitForRendering(surface);
        compare(surface.closedModel.state, "live", "the notch keeps the music");
        var below = findChild(surface, "hudBelow");
        verify(below.visible);
        verify(!findChild(surface, "hudInline").visible);
        compare(below.y, surface.pillHeight + below.notchGap);
        fuzzyCompare(below.x + below.width / 2, surface.width / 2, 0.5);
        var hit = surface.hudHitShape;
        verify(hit.present);
        compare(hit.x, below.x);
        compare(hit.y, below.y);
        compare(hit.width, below.width);
        compare(hit.height, below.height);
        compare(surface.hitShape.height, surface.pillHeight, "the notch's own region is unchanged");
    }
    // The HUD's input rectangle exists only while a readout with a bar shows,
    // takes the resting geometry at once while the notch still springs, and
    // goes in one step.
    function test_hudInputGrowsOnlyWhileActiveInOneStep() {
        design.reducedMotion = false;
        var surface = createTemporaryObject(livePillComponent, test);
        var hit = surface.hudHitShape;
        verify(!hit.present);
        compare(hit.width, 0);
        surface.hud.show("volume", 0.5, false);
        verify(findChild(surface, "islandCard").width < design.hudInlineWidth, "the notch is still springing");
        verify(hit.present);
        compare(hit.width, design.hudInlineWidth - 2 * design.flareClosed, "the input rectangle is already at rest");
        compare(hit.height, surface.pillHeight);
        compare(hit.x, Math.round((surface.width - hit.width) / 2));
        surface.hud.active = false;
        verify(!hit.present, "and leaves in one step");
        compare(hit.width, 0);
        surface.hud.show("mic", 0, true);
        verify(!hit.present, "a readout without a bar takes no input");
        surface.hud.active = false;
        surface.hud.show("volume", 0.5, false);
        surface.expandTo("home");
        verify(!hit.present, "nor while the notch is open");
        design.reducedMotion = true;
    }
    // Hovering the HUD never starts the open dwell, and entering it stops a
    // dwell already running.
    function test_hudHoverNeverExpands() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("volume", 0.5, false);
        waitForRendering(surface);
        var p = hudBarPoint(surface, "hudBar", 0.5);
        var at = p.bar.mapToItem(surface, p.x, p.y);
        mouseMove(surface, at.x, at.y);
        wait(surface.hoverDwell + 150);
        compare(surface.expanded, false, "resting on the HUD never opens the island");
        mouseMove(test, farPoint().x, farPoint().y);
        surface.hud.active = false;
        var pill = pillPoint(surface);
        mouseMove(surface, pill.x, pill.y);
        wait(surface.hoverDwell / 3);
        surface.hud.show("volume", 0.5, false);
        wait(surface.hoverDwell + 150);
        compare(surface.expanded, false, "a readout arriving under the pointer stops the running dwell");
        mouseMove(test, farPoint().x, farPoint().y);
    }
    // Leaving the below pill for the notch body starts the dwell as usual.
    function test_leavingTheHudForTheNotchStartsTheDwell() {
        facade.fileSettings = ({ hudStyle: "below" });
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("volume", 0.5, false);
        waitForRendering(surface);
        var below = findChild(surface, "hudBelow");
        mouseMove(surface, below.x + below.width / 2, below.y + below.height / 2);
        wait(surface.hoverDwell + 150);
        compare(surface.expanded, false);
        var pill = pillPoint(surface);
        mouseMove(surface, pill.x, pill.y);
        tryCompare(surface, "expanded", true, surface.hoverDwell + 300);
        mouseMove(test, farPoint().x, farPoint().y);
    }
    // A press on the HUD bar sets the level and never taps the notch open.
    function test_hudPressSetsTheLevelNotTheNotch() {
        var surface = createTemporaryObject(livePillComponent, test);
        var requests = [];
        surface.hudLevelRequested.connect(function (kind, value) { requests.push([kind, Math.round(value * 100)]); });
        surface.hud.show("brightness", 0.2, false);
        waitForRendering(surface);
        var p = hudBarPoint(surface, "hudBar", 0.75);
        mouseMove(p.bar, p.x, p.y);
        mouseClick(p.bar, p.x, p.y);
        wait(50);
        compare(surface.expanded, false, "the press never reaches the tap that opens");
        verify(requests.length >= 1);
        compare(requests[0][0], "brightness");
        verify(Math.abs(requests[0][1] - 75) <= 2, "the level at the press point: " + requests[0][1]);
        var centre = pillPoint(surface);
        mouseClick(surface, centre.x, centre.y);
        wait(50);
        compare(surface.expanded, false, "nor does a tap anywhere else on the readout, the notch's centre included");
        var steps = [];
        surface.volumeStepRequested.connect(function (delta) { steps.push(delta); });
        var at = p.bar.mapToItem(surface, p.x, p.y);
        mouseWheel(surface, at.x, at.y, 0, 120);
        mouseWheel(surface, centre.x, centre.y, 0, 120);
        compare(steps.length, 0, "a wheel on the HUD is not a volume step");
    }
    // Open, the readout shows in the header in place of its slots, and a
    // drag there routes the same way.
    function test_openHeaderCapsule() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var capsule = findChild(surface, "headerHud");
        var slots = findChild(surface, "headerSlots");
        verify(!capsule.visible && slots.visible);
        surface.hud.show("volume", 0.3, false);
        verify(capsule.visible, "the open header shows the readout");
        verify(!slots.visible, "in place of the right-hand slots");
        var requests = [];
        surface.hudLevelRequested.connect(function (kind, value) { requests.push(kind); });
        waitForRendering(surface);
        var bar = findChild(capsule, "hudBar");
        mouseClick(bar, bar.width / 2, bar.height / 2);
        compare(requests, ["volume"]);
        compare(surface.expanded, true);
        surface.hud.active = false;
        verify(slots.visible);
        facade.fileSettings = ({ showOpenNotchHud: false });
        surface.hud.show("volume", 0.3, false);
        verify(!capsule.visible, "showOpenNotchHud off keeps the header as it is");
    }
    // The battery: a gauge in the header, its popover on a tap, and the
    // closed banner.
    function test_batteryGaugeAndPopover() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var slot = findChild(surface, "headerBatterySlot");
        verify(!slot.visible, "no battery, no gauge");
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.15, state: "Discharging",
            timeToEmpty: 3600, timeToFull: 0, health: 91, powerSaver: false });
        verify(slot.visible);
        compare(findChild(slot, "batteryGauge").fillKind, "low", "red at 15 % on battery");
        facade.fileSettings = ({ showBatteryIndicator: false });
        verify(!slot.visible, "showBatteryIndicator off hides it");
        facade.fileSettings = ({});
        waitForRendering(surface);
        mouseClick(slot);
        var loader = findChild(surface, "batteryPopoverLoader");
        verify(loader.item, "a tap opens the popover");
        compare(findChild(loader.item, "popoverPercent").text, "15%");
        verify(!findChild(loader.item, "popoverPowerSettings").visible, "no power command, no button");
        surface.batteryPowerAvailable = true;
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.15, state: "Discharging",
            timeToEmpty: 3600, timeToFull: 0, health: 91, powerSaver: true });
        var header = findChild(surface, "notchHeader");
        verify(loader.y >= header.y + header.height, "the popover never covers the header gauge");
        verify(loader.y + loader.item.height <= surface.restHeight,
            "the full detail menu stays inside the 190 px input body");
        var body = findChild(loader.item, "popoverBody");
        body.contentY = Math.max(0, body.contentHeight - body.height);
        var powerButton = findChild(loader.item, "popoverPowerSettings");
        var powerTop = powerButton.mapToItem(body, 0, 0).y;
        verify(powerTop >= 0 && powerTop + powerButton.height <= body.height,
            "scrolling reveals the entire Power settings button");
        var powerBottom = powerButton.mapToItem(surface, 0, powerButton.height).y;
        verify(powerBottom <= surface.restHeight, "Power settings remains clickable");
        var asked = 0;
        surface.batteryPowerRequested.connect(function () { asked++; });
        powerButton.clicked();
        compare(asked, 1);
        surface.focusKeys();
        keyClick(Qt.Key_Escape);
        compare(loader.item, null, "Escape closes the popover first");
        compare(surface.expanded, true);
        mouseClick(slot);
        verify(loader.item);
        surface.collapse();
        verify(!surface.batteryPopoverOpen, "closing the island closes it");
    }
    function test_batteryPopoverStopsCoveredCamera() {
        cameraCreations = 0;
        cameraDestructions = 0;
        facade.fileSettings = ({ showMirror: true });
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.cameraSource = fakeCamera;
        surface.expandTo("home");
        var mirror = findChild(surface, "cameraPanel");
        tryCompare(surface, "openSettled", true, design.openDuration + 300);
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        surface.batteryPopoverOpen = true;
        verify(surface.batteryPopoverOpen);
        compare(mirror.sourceItem, null, "the covered camera unloads");
        surface.focusKeys();
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
    }
    function test_batteryBanner() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.batteryLevel = 0.64;
        surface.batteryLabel = "Charging";
        surface.batteryActive = true;
        compare(surface.closedModel.state, "battery");
        compare(findChild(surface, "islandCard").width, design.batteryBannerWidth);
        compare(findChild(surface, "batteryLabel").text, "Charging");
        verify(findChild(surface, "batteryIcon").visible);
        compare(surface.hitShape.width, design.liveWidth - 2 * design.flareClosed, "the banner never grows the input region");
        verify(!surface.hudHitShape.present);
        surface.batteryActive = false;
        compare(surface.closedModel.state, "live");
    }
    // The banner's battery is the header's gauge, in its colours with its
    // mark and percentage, and both halves hug the middle (or the camera
    // gap, over a hardware notch).
    function test_batteryBannerMatchesTheGauge() {
        var surface = createTemporaryObject(livePillComponent, test);
        surface.batteryReading = { present: true, onBattery: false, level: 0.64, state: "Charging", powerSaver: false };
        surface.batteryLabel = "Charging";
        surface.batteryActive = true;
        var body = findChild(surface, "notchBody");
        var gauge = findChild(surface, "batteryIcon"), label = findChild(surface, "batteryLabel");
        verify(gauge.visible);
        compare(findChild(gauge, "batteryFill").color, "#30d158", "green while charging");
        verify(findChild(gauge, "batteryStatusIcon").visible, "with the charging mark");
        compare(findChild(gauge, "batteryPercent").text, "64%");
        var labelBox = label.mapToItem(body, 0, 0, label.width, label.height);
        var gaugeBox = gauge.mapToItem(body, 0, 0, gauge.width, gauge.height);
        compare(labelBox.x + labelBox.width, body.width / 2 - design.medium);
        compare(gaugeBox.x, body.width / 2 + design.medium);
        facade.fileSettings = ({ hardwareNotch: true, showBatteryPercent: false });
        gaugeBox = gauge.mapToItem(body, 0, 0, gauge.width, gauge.height);
        labelBox = label.mapToItem(body, 0, 0, label.width, label.height);
        var gap = design.idleWidth - 2 * design.flareClosed;
        compare(labelBox.x + labelBox.width, (body.width - gap) / 2 - design.medium);
        compare(gaugeBox.x, (body.width + gap) / 2 + design.medium);
        verify(!findChild(gauge, "batteryPercent").visible, "the percentage follows its setting");
    }
    // A pointer that moves over the notch with a button held never starts
    // or keeps the open dwell. The offscreen pipeline cannot carry a held
    // button through the hover handler (see test_pressedButtonBlocksHover),
    // so this drives the step every hover move takes, with the buttons the
    // handler passes (tests/source-contract.py pins that it passes them).
    function test_pressedMoveNeverRestartsTheDwell() {
        var surface = createTemporaryObject(livePillComponent, test);
        var p = pillPoint(surface);
        var local = surface.mapToItem(surface.hitShape, p.x, p.y);
        compare(surface.dwellStep(local, Qt.LeftButton, true), "stop", "a pressed move stops a running dwell");
        compare(surface.dwellStep(local, Qt.LeftButton, false), "stop", "and never starts one");
        compare(surface.dwellStep(local, Qt.RightButton, false), "stop");
        compare(surface.dwellStep(local, Qt.NoButton, false), "start", "a released move starts it");
        compare(surface.dwellStep(local, Qt.NoButton, true), "keep");
        surface.hud.show("volume", 0.5, false);
        compare(surface.dwellStep(local, Qt.NoButton, true), "stop", "and on the readout it stops");
    }
    // While a HUD bar is held, nothing removes it: an open (a keyboard
    // summon, a drop) waits for the release, and the readout keeps its
    // pill and its input rectangle meanwhile.
    function test_openWaitsForAHeldBar() {
        facade.fileSettings = ({ hudStyle: "below" });
        var surface = createTemporaryObject(livePillComponent, test);
        surface.hud.show("volume", 0.5, false);
        surface.hud.held = true;
        surface.explicitOpen = true;
        surface.expandTo("home");
        compare(surface.expanded, false, "the open waits");
        verify(findChild(surface, "hudBelow").visible, "the pill stays");
        verify(surface.hudHitShape.present, "and so does its input");
        surface.hud.held = false;
        compare(surface.expanded, true, "the release opens the island");
        compare(surface.view, "home");
        surface.explicitOpen = false;
    }
    // Open, a held capsule keeps the island open: the ordinary closes wait
    // for the release, and a forced one (Escape, a host reset) still wins.
    function test_heldCapsuleKeepsTheIslandOpen() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        surface.hud.show("volume", 0.5, false);
        surface.hud.held = true;
        compare(surface.collapse(), false, "an ordinary close waits");
        compare(surface.expanded, true);
        surface.hud.held = false;
        tryCompare(surface, "expanded", false, surface.leaveGrace + 300, "and the grace runs after the release");
        surface.expandTo("home");
        surface.hud.show("volume", 0.5, false);
        surface.hud.held = true;
        compare(surface.collapse(true), true, "a forced close still wins");
        surface.hud.held = false;
    }
    // With an island on every screen, only the one under the pointer draws
    // the live bars; the others show the still glyph.
    function test_liveSpectrumOnlyWhereAllowed() {
        // Live bars need motion; init() reduces it for every other test.
        design.reducedMotion = false;
        facade.spectrumState = "running";
        facade.spectrumLevels = ramp();
        var surface = createTemporaryObject(livePillComponent, test);
        tryVerify(function () { return findChild(surface, "spectrumBars").visible; }, 1000);
        surface.liveSpectrum = false;
        verify(!findChild(surface, "spectrumBars").visible, "no live bars here");
        verify(findChild(surface, "playStateGlyph").visible, "the still glyph instead");
        surface.peekKind = "track";
        surface.peekActive = true;
        verify(!findChild(surface, "peekSpectrum").visible, "nor in the peek");
        surface.liveSpectrum = true;
        tryVerify(function () { return findChild(surface, "peekSpectrum").visible; }, 1000);
    }
    // One camera: an island that may not run it keeps Home's mirror shut
    // even open and settled.
    function test_cameraOnlyWhereAllowed() {
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var home = findChild(surface, "homeView");
        verify(surface.openSettled);
        verify(home.islandOpen, "an island that may run the camera passes it on");
        surface.cameraAllowed = false;
        verify(!home.islandOpen, "one that may not keeps it shut");
    }
    // Every text element under an item: anything with a renderType and a
    // text, which is Text, TextInput and TextEdit.
    function textItems(item, found) {
        found = found || [];
        if (item.renderType !== undefined && item.text !== undefined)
            found.push(item);
        for (var i = 0; i < item.children.length; ++i)
            textItems(item.children[i], found);
        return found;
    }
    function verifyGrayscaleText(root, where) {
        var texts = textItems(root);
        verify(texts.length > 0, where + " has text");
        for (var i = 0; i < texts.length; ++i)
            compare(texts[i].renderType, Text.NativeRendering,
                where + ": " + (texts[i].objectName || texts[i].text) + " uses grayscale rendering");
    }
    // A named text element exists under `root` and renders in grayscale.
    function verifyGrayscaleNamed(root, name, where) {
        var item = findChild(root, name);
        verify(item !== null, where + ": " + name + " exists");
        compare(item.renderType, Text.NativeRendering, where + ": " + name + " uses grayscale rendering");
    }
    // Island text sets native rendering explicitly: on the live compositor
    // it draws grayscale glyphs, while Qt's distance-field rendering (what a
    // Text gets when it sets nothing) draws subpixel glyphs that fringe with
    // colour on the black notch. Each path is exercised with its text
    // present: the closed idle glance, activity rows, the closed HUD, track
    // and device peeks, the header (tabs, badge, battery and activity
    // chips), Home (player, calendar rows, mirror and timers), the open
    // glance, shelf and Lyrics. The offscreen renderer shows no subpixel
    // layout either way, so the fringes themselves are checked on the live
    // compositor, not here.
    function test_islandTextIsGrayscale() {
        compare(design.textRenderType, Text.NativeRendering, "the tokens render text natively");
        // A text that skips the token reads the runner's default, so the
        // checks below fail for any island text left unbound.
        var unbound = createTemporaryQmlObject("import QtQuick; Text { text: \"x\" }", test);
        verify(unbound.renderType !== Text.NativeRendering, "an unbound text does not render natively by default");
        // The calendar is refreshed to a fixed noon below, so its event row
        // exists whatever the time the test runs.
        var noon = new Date(2026, 8, 26, 12, 0);
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        facade.fileSettings = ({ showCalendar: true, showMirror: true, hudPercentClosed: true });
        facade.calendarSource = ({ items: [{ sourceId: "s", uid: "u", title: "Stand-up",
            start: "2026-09-26T15:00:00.000", end: "2026-09-26T15:30:00.000" }] });
        facade.shelfEntries = [{ id: "s1", kind: "file", uri: "file:///tmp/a.png", name: "a.png", addedAt: 1, temp: false }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.cameraAllowed = false;
        compare(surface.ink.textRenderType, Text.NativeRendering);
        // Closed and idle: the glance's line.
        var glance = findChild(surface, "idleGlance");
        verify(glance && glance.visible, "the closed idle glance is loaded");
        verifyGrayscaleNamed(glance, "glancePrimary", "the closed glance");
        verifyGrayscaleText(glance, "the closed glance");
        // The closed HUD, with its percentage.
        surface.hud.show("volume", 0.5, false);
        verifyGrayscaleText(findChild(surface, "hudInline"), "the closed HUD");
        surface.hud.active = false;
        // The recording, timer and sleep text are separate closed-notch paths.
        facade.recordingState = { active: true, startedAt: Date.now() - 12 * 60000, path: "/v/a.mp4" };
        facade.recordingShown = true;
        tryVerify(function () { return findChild(surface, "recordingGlyph").visible; }, 2000);
        verifyGrayscaleNamed(surface, "recordingGlyphText", "the recording glyph");
        verifyGrayscaleNamed(surface, "activityValue", "the recording time");
        verifyGrayscaleNamed(surface, "activityLabel", "the recording label");
        facade.recordingShown = false;
        facade.timersEnabled = true;
        facade.timerList = [{ unit: "omarchy-reminder-15m-1", label: "Tea", minutes: 15,
            at: Date.now() + 12 * 60000 }];
        var paused = endpoint();
        paused.status = "Paused";
        facade.selectedEndpoint = paused;
        facade.endpoints = [paused];
        surface.closedModel.lingering = false;
        tryVerify(function () { return findChild(surface, "timerGlyph").visible; }, 2000);
        verifyGrayscaleNamed(surface, "activityValue", "the timer time");
        verifyGrayscaleNamed(surface, "activityLabel", "the timer label");
        facade.timerList = [];
        facade.selectedEndpoint = endpoint();
        facade.endpoints = [facade.selectedEndpoint];
        facade.sleepDeadline = Date.now() + 10 * 60000;
        tryVerify(function () { return findChild(surface, "minimalSleep").visible; }, 2000);
        verifyGrayscaleNamed(surface, "minimalSleepText", "the sleep timer");
        facade.sleepDeadline = 0;
        // The track peek.
        surface.peekKind = "track";
        surface.peekActive = true;
        verifyGrayscaleNamed(findChild(surface, "islandPeek"), "peekTitle", "the peek");
        verifyGrayscaleNamed(findChild(surface, "islandPeek"), "peekArtists", "the peek");
        surface.peekActive = false;
        surface.peekKind = "device";
        surface.peekEvent = { icon: "headset", title: "Headphones", detail: "Connected",
            level: 0.8, alert: false };
        surface.peekActive = true;
        tryVerify(function () { return findChild(surface, "peekEventRow").visible; }, 2000);
        verifyGrayscaleNamed(surface, "peekEventTitle", "the device peek");
        verifyGrayscaleNamed(surface, "peekEventDetail", "the device peek");
        verifyGrayscaleNamed(surface, "peekEventPercent", "the device peek");
        surface.peekActive = false;
        // Open: the header with its shelf badge and battery percentage.
        facade.recordingShown = true;
        facade.timerList = [{ unit: "omarchy-reminder-15m-1", label: "Tea", minutes: 15,
            at: Date.now() + 12 * 60000 }];
        facade.sleepDeadline = Date.now() + 10 * 60000;
        surface.privacy = { mic: ["Zoom"], camera: [], screen: [], micMuted: false, any: true };
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: false });
        surface.expandTo("home");
        var header = findChild(surface, "notchHeader");
        verifyGrayscaleNamed(header, "tabBadge", "the header");
        verifyGrayscaleNamed(header, "batteryPercent", "the header");
        for (var chipName of ["recordingChipText", "recordingStop", "timerChipText", "privacyChipText"])
            verifyGrayscaleNamed(header, chipName, "the activity chips");
        // Home: the player, a calendar event row and the mirror's label.
        var home = findChild(surface, "homeView");
        verifyGrayscaleNamed(findChild(home, "trackTitle"), "marqueeText", "the player title");
        verifyGrayscaleNamed(home, "elapsedTime", "the player");
        verifyGrayscaleNamed(home, "calendarMonth", "the calendar");
        var calendar = findChild(home, "calendarPanel");
        calendar.refresh(noon);
        tryVerify(function () { return findChild(home, "calendarTitle") !== null; }, 1000, "the event row is laid out");
        compare(findChild(home, "calendarTitle").text, "Stand-up");
        verifyGrayscaleNamed(home, "calendarTitle", "a calendar row");
        verifyGrayscaleNamed(home, "calendarTime", "a calendar row");
        verifyGrayscaleText(findChild(home, "cameraPanel"), "the mirror");
        verifyGrayscaleText(home, "Home");
        // Home with nothing to play: the open glance.
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        verifyGrayscaleNamed(home, "glanceTime", "the open glance");
        // The Timers view has running, sleep, unavailable and empty labels,
        // plus controls whose text uses the same token rendering mode.
        surface.view = "timers";
        tryVerify(function () { return findChild(surface, "timersViewLoader").item !== null; }, 1000);
        var timers = findChild(surface, "timersViewLoader").item;
        for (var timerName of ["timerRowText", "timersSleep", "timersUnavailable", "timersEmpty",
                              "timerMinutes", "timerLabel"])
            verifyGrayscaleNamed(timers, timerName, "Timers");
        compare(findChild(timers, "timerStart").contentItem.renderType, Text.NativeRendering,
                "Timers buttons use grayscale rendering");
        verifyGrayscaleText(timers, "Timers");
        // The shelf.
        surface.view = "shelf";
        tryVerify(function () { return findChild(surface, "shelfViewLoader").item !== null; }, 1000);
        verifyGrayscaleNamed(findChild(surface, "shelfViewLoader").item, "shelfTileName", "the shelf");
        verifyGrayscaleText(findChild(surface, "shelfViewLoader").item, "the shelf");
        // Lyrics, with a current line.
        facade.selectedEndpoint = endpoint();
        facade.endpoints = [facade.selectedEndpoint];
        facade.lyrics = true;
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.lines = [{ time: 0, text: "First line" }, { time: 5, text: "Second line" }];
        lyricsFixture.currentIndex = 0;
        surface.lyricsSource = lyricsFixture;
        surface.view = "lyrics";
        tryVerify(function () { return findChild(surface, "lyricsViewLoader").item !== null; }, 1000);
        var lyrics = findChild(surface, "lyricsViewLoader").item;
        verifyGrayscaleNamed(lyrics, "lyricsCurrentLine", "Lyrics");
        verifyGrayscaleNamed(lyrics, "lyricsTitle", "Lyrics");
        verifyGrayscaleText(lyrics, "Lyrics");
    }
    // The header's row plan: full width when it fits, then compact forms
    // from the least important entry up, then an overflow button with the
    // least important entries folded, never skipping priority.
    function test_headerSlotPlan() {
        var slots = [{ key: "recording", width: 32 }, { key: "battery", width: 70, compact: 38 },
            { key: "timers", width: 70, compact: 34 }, { key: "camera", width: 32 }, { key: "settings", width: 32 }];
        var all = HeaderSlots.plan(slots, 400, 4, 32);
        compare(all.inline, ["recording", "battery", "timers", "camera", "settings"]);
        verify(!all.overflow && !all.compact.timers && !all.compact.battery);
        var timersCompact = HeaderSlots.plan(slots, 240, 4, 32);
        verify(timersCompact.compact.timers && !timersCompact.compact.battery, "Timers gives up its time first");
        verify(!timersCompact.overflow);
        var bothCompact = HeaderSlots.plan(slots, 190, 4, 32);
        verify(bothCompact.compact.timers && bothCompact.compact.battery, "then the battery its percentage");
        verify(!bothCompact.overflow);
        var folded = HeaderSlots.plan(slots, 155, 4, 32);
        verify(folded.overflow);
        compare(folded.inline, ["recording", "battery", "timers"]);
        compare(folded.folded, ["camera", "settings"], "the least important fold");
        verify(folded.width <= 155);
        var tight = HeaderSlots.plan(slots, 60, 4, 32);
        compare(tight.inline, [], "with no room at all, everything is in the menu");
        compare(tight.folded.length, 5);
        verify(tight.width <= 60);
    }
    // Header widths from the full open notch down to the narrowest the
    // tabs still fit, with the heaviest slot combinations.
    function test_populatedHeaderStaysClearOfTheCentre_data() {
        var rows = [];
        [578, 540, 500].forEach(function (width) {
            rows.push({ tag: width + " all", header: width, recording: true, battery: true, timers: true, camera: true, gear: true });
            rows.push({ tag: width + " battery timers gear", header: width, recording: false, battery: true, timers: true, camera: false, gear: true });
            rows.push({ tag: width + " camera gear", header: width, recording: false, battery: false, timers: false, camera: true, gear: true });
        });
        return rows;
    }
    function test_populatedHeaderStaysClearOfTheCentre(data) {
        facade.fileSettings = ({ hardwareNotch: true, showMirror: data.camera, showSettingsIcon: data.gear });
        facade.timersEnabled = data.timers;
        facade.timerList = data.timers ? [{ unit: "omarchy-reminder-1", label: "Tea", minutes: 65,
            at: Date.now() + 65 * 60000 - 30000 }] : [];
        facade.recordingState = { active: data.recording, startedAt: Date.now() - 60000, path: "/v/a.mp4" };
        facade.recordingShown = data.recording;
        facade.shelfEntries = [{ id: "s1", kind: "file", uri: "file:///tmp/a.png", name: "a.png", addedAt: 1, temp: false }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.cameraAllowed = false;
        surface.availableWidth = data.header + 2 * design.flareOpen + 2 * design.medium;
        surface.batteryReading = data.battery ? ({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: false })
            : ({ present: false });
        surface.expandTo("home");
        var header = findChild(surface, "notchHeader");
        compare(header.width, data.header, "the header at its width");
        waitForRendering(surface);
        var centre = findChild(surface, "headerCentre");
        var slots = findChild(surface, "headerSlots");
        verify(slots.x >= centre.x + centre.width, "the right-hand row ends clear of the centre: "
            + slots.x + " against " + (centre.x + centre.width));
        // Every shown entry is reachable, in the row or in the overflow menu,
        // under its name.
        var entries = { recording: ["headerRecordingStop", data.recording], battery: ["headerBatterySlot", data.battery],
            timers: ["headerTimersButton", data.timers], camera: ["headerCameraSlot", data.camera],
            settings: ["headerSettingsButton", data.gear] };
        var overflow = findChild(surface, "headerOverflowButton");
        for (var key in entries) {
            var shown = entries[key][1], item = findChild(header, entries[key][0]);
            var folded = header.slotPlan.folded.indexOf(key) >= 0;
            if (!shown) {
                verify(!item.visible && !folded, key + " is off");
                continue;
            }
            verify(item.visible !== folded, key + " is in exactly one place");
            if (folded)
                verify(overflow.visible && overflow.Accessible.name.indexOf(header.slotLabel(key)) >= 0,
                    key + " is named by the overflow button");
        }
        // The menu opens inside the open notch, where the island takes input.
        if (header.slotPlan.overflow) {
            var menu = header.overflowMenu;
            overflow.activated();
            tryVerify(function () { return menu.opened; }, 1000);
            var card = findChild(surface, "islandCard");
            var box = menu.background.mapToItem(card, 0, 0, menu.background.width, menu.background.height);
            verify(box.x >= 0 && box.x + box.width <= card.width, "the menu stays within the notch's width");
            verify(box.y + box.height <= surface.restHeight, "and above its bottom: " + (box.y + box.height));
            menu.close();
            tryVerify(function () { return !menu.opened; }, 1000);
        }
        // The tabs on the left end clear of the centre too.
        var tabs = findChild(surface, "viewShelfButton");
        verify(tabs.mapToItem(header, tabs.width, 0).x <= centre.x, "the tabs end clear of the centre");
        // The open-notch HUD takes the row's place, and fits the same room.
        surface.hud.show("volume", 0.5, false);
        var hud = findChild(surface, "headerHud");
        tryVerify(function () { return hud.visible; }, 1000);
        verify(hud.x >= centre.x + centre.width, "the header readout ends clear of the centre: " + hud.x);
        verify(findChild(hud, "hudBar").width > 0);
    }
    // The overflow menu works from the keyboard: it opens with its first
    // entry focused, Return runs it, and it closes back to its button.
    function test_headerOverflowMenuIsKeyboardReachable() {
        facade.fileSettings = ({ hardwareNotch: true, showMirror: true });
        facade.timersEnabled = true;
        facade.recordingState = { active: true, startedAt: Date.now() - 60000, path: "/v/a.mp4" };
        facade.recordingShown = true;
        var surface = createTemporaryObject(livePillComponent, test);
        surface.cameraAllowed = false;
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: false });
        surface.expandTo("home");
        var header = findChild(surface, "notchHeader");
        var overflow = findChild(surface, "headerOverflowButton");
        tryVerify(function () { return overflow.visible; }, 1000, "a full row folds entries at the full width");
        compare(header.slotPlan.folded[header.slotPlan.folded.length - 1], "settings", "the gear folds first");
        overflow.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        var menu = header.overflowMenu;
        tryVerify(function () { return menu.opened; }, 1000);
        var entries = menu.contentItem.children.filter(function (child) { return child.objectName.indexOf("headerOverflow-") === 0; });
        compare(entries.length, header.slotPlan.folded.length);
        var gear = entries.filter(function (child) { return child.objectName === "headerOverflow-settings"; })[0];
        compare(gear.text, "Nookisle settings");
        compare(gear.Accessible.name, "Nookisle settings");
        tryVerify(function () { return entries[0].activeFocus; }, 1000, "the first entry takes the keyboard");
        gear.forceActiveFocus(Qt.TabFocusReason);
        var before = facade.settingsSections.length;
        keyClick(Qt.Key_Return);
        tryVerify(function () { return !menu.opened; }, 1000, "choosing closes the menu");
        compare(facade.settingsSections.length, before + 1, "and runs the entry");
    }
    // A full row at the full header width, with the overflow menu shown.
    function fullHeaderSurface() {
        facade.fileSettings = ({ hardwareNotch: true, showMirror: true });
        facade.timersEnabled = true;
        facade.recordingState = { active: true, startedAt: Date.now() - 60000, path: "/v/a.mp4" };
        facade.recordingShown = true;
        facade.shelfEntries = [{ id: "s1", kind: "file", uri: "file:///tmp/a.png", name: "a.png", addedAt: 1, temp: false }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.cameraAllowed = false;
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: false });
        surface.expandTo("home");
        tryVerify(function () { return findChild(surface, "headerOverflowButton").visible; }, 1000);
        return surface;
    }
    // The pointer can use the menu: moving from its button into an entry
    // keeps the island open past the leave grace, and leaving the menu for
    // outside the island closes both after the grace.
    function test_overflowMenuHoldsTheIslandUnderThePointer() {
        var surface = fullHeaderSurface();
        var header = findChild(surface, "notchHeader"), menu = header.overflowMenu;
        var button = findChild(surface, "headerOverflowButton");
        waitForRendering(surface);
        mouseMove(button, button.width / 2, button.height / 2);
        tryVerify(function () { return surface.pointerInside; }, 1000);
        mouseClick(button);
        tryVerify(function () { return menu.opened; }, 1000);
        var entry = menu.contentItem.children.filter(function (child) { return child.objectName.indexOf("headerOverflow-") === 0; })[0];
        mouseMove(entry, entry.width / 2, entry.height / 2);
        tryVerify(function () { return header.overflowHovered; }, 1000, "the menu sees the pointer");
        verify(surface.pointerInside, "the island counts the menu as inside");
        wait(surface.leaveGrace + 200);
        verify(surface.expanded, "the island stays open while the pointer is on the menu");
        verify(menu.opened);
        mouseMove(test, test.width - 2, test.height - 2);
        tryVerify(function () { return !header.overflowHovered; }, 1000);
        tryVerify(function () { return !surface.expanded; }, surface.leaveGrace + 1000, "leaving both closes the island");
        verify(!menu.opened && !menu.visible, "and its menu");
    }
    // The menu never outlives its view or the open island: a tab change,
    // a collapse and a host reset each close it.
    function test_overflowMenuClosesOnTabChangeAndCollapse() {
        var surface = fullHeaderSurface();
        var header = findChild(surface, "notchHeader"), menu = header.overflowMenu;
        var button = findChild(surface, "headerOverflowButton");
        button.activated();
        tryVerify(function () { return menu.opened; }, 1000);
        findChild(surface, "viewShelfButton").clicked();
        compare(surface.view, "shelf");
        tryVerify(function () { return !menu.opened; }, 1000, "a tab change closes it");
        surface.view = "home";
        button.activated();
        tryVerify(function () { return menu.opened; }, 1000);
        surface.collapse(true);
        tryVerify(function () { return !menu.opened && !menu.visible; }, 1000, "a collapse closes it");
        surface.expandTo("home");
        tryVerify(function () { return button.visible; }, 1000);
        button.activated();
        tryVerify(function () { return menu.opened; }, 1000);
        surface.resetForHost();
        tryVerify(function () { return !menu.opened; }, 1000, "a host reset closes it");
        surface.expandTo("home");
        button.activated();
        tryVerify(function () { return menu.opened; }, 1000);
        surface.hud.show("volume", 0.5, false);
        tryVerify(function () { return !menu.opened; }, 1000, "the readout taking the row's place closes it");
    }
    // From the keyboard the menu opens on Return, Escape closes it back to
    // its button, and a collapse with the keyboard in it closes it too.
    function test_overflowMenuKeyboardEscape() {
        var surface = fullHeaderSurface();
        var header = findChild(surface, "notchHeader"), menu = header.overflowMenu;
        var button = findChild(surface, "headerOverflowButton");
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        tryVerify(function () { return menu.opened; }, 1000);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !menu.opened; }, 1000);
        tryVerify(function () { return button.activeFocus; }, 1000, "focus returns to the button");
    }
    // The inline battery is a keyboard button: Tab reaches it from the tabs,
    // and Return or Space opens the battery popover.
    function test_inlineBatteryIsAKeyboardButton() {
        facade.shelfEntries = [{ id: "s1", kind: "file", uri: "file:///tmp/a.png", name: "a.png", addedAt: 1, temp: false }];
        var surface = createTemporaryObject(livePillComponent, test);
        surface.batteryReading = ({ present: true, onBattery: true, level: 0.8, state: "Discharging", powerSaver: false });
        surface.expandTo("home");
        var battery = findChild(surface, "headerBatterySlot");
        tryVerify(function () { return battery.visible; }, 1000);
        verify(battery.activeFocusOnTab);
        findChild(surface, "viewHomeButton").forceActiveFocus(Qt.TabFocusReason);
        for (var i = 0; i < 30 && !battery.activeFocus; ++i)
            keyClick(Qt.Key_Tab);
        verify(battery.activeFocus, "Tab reaches the battery");
        verify(findChild(battery, "headerBatteryFocus").visible, "with a focus ring");
        keyClick(Qt.Key_Return);
        tryVerify(function () { return surface.batteryPopoverOpen; }, 1000, "Return opens the popover");
        surface.batteryPopoverOpen = false;
        battery.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        tryVerify(function () { return surface.batteryPopoverOpen; }, 1000, "and so does Space");
    }
}
