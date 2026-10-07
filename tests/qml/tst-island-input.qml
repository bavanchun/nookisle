import QtQuick
import QtTest
import "../../components"
import "../../qml/IslandKeys.js" as IslandKeys

TestCase {
    id: test
    name: "IslandInput"
    width: 760
    height: 420
    when: windowShown
    visible: true
    DesignTokens {
        id: design
        reducedMotion: true
    }
    // A recording coordinator: every command lands in `sent`, and an intent
    // is always available, so each test reads exactly what was dispatched.
    QtObject {
        id: facade
        property bool panelAllowed: true
        property bool uiAllowed: true
        property var selectedEndpoint: null
        property var endpoints: []
        property string selectedLabel: "Spotify"
        property string selectionMode: "auto"
        property bool pinUnavailable: false
        property real positionSeconds: 50
        property string pendingAction: ""
        property string actionError: ""
        property string statusText: ""
        property bool reducedMotion: true
        property bool highContrast: false
        property bool remoteArtwork: false
        property bool autoShow: true
        property bool hud: true
        property bool visualizer: true
        property string spectrumState: "off"
        property var spectrumLevels: []
        property bool islandPointerActive: false
        property bool lyrics: false
        property var shelfItems: []
        property bool sleepArmable: true
        property bool sleepLockVerified: true
        property double sleepDeadline: 0
        property string sleepFailure: ""
        property var sent: []
        property var settingsSections: []
        function openSettings(section) {
            settingsSections = settingsSections.concat([section]);
            return true;
        }
        function shelfAdd(uris) { return uris.length; }
        function armSleepTimer(minutes) { return "ok"; }
        function cancelSleepTimer() {}
        function captureIntent() {
            return { ok: true };
        }
        function invoke(action, intent, value) {
            sent = sent.concat([{ action: action, value: value }]);
            return "sent";
        }
        function selectSource(token) {}
        function selectAuto() {}
        function retryConnection() {}
        function configure(options) {}
    }
    Component {
        id: surfaceComponent
        IslandSurface {
            tokens: design
            coordinator: facade
            pillHeight: 26
            width: design.notchWindowWidth()
            height: design.notchWindowHeight()
        }
    }
    SignalSpy {
        id: volumeSpy
        signalName: "volumeStepRequested"
    }
    readonly property var codes: ({
        space: Qt.Key_Space, left: Qt.Key_Left, right: Qt.Key_Right, up: Qt.Key_Up, down: Qt.Key_Down,
        n: Qt.Key_N, p: Qt.Key_P, tab: Qt.Key_Tab, backtab: Qt.Key_Backtab,
        returnKey: Qt.Key_Return, enter: Qt.Key_Enter,
        shift: Qt.ShiftModifier, blocked: Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier
    })
    QtObject {
        id: lyricsFixture
        property bool lyricsEnabled: true
        property string lyricsState: "idle"
        property string errorCode: ""
        property var lines: []
        property int currentIndex: -1
        property var meta: ({ title: "Afterglow" })
        readonly property string displayState: !lyricsEnabled ? "off"
            : lyricsState === "idle" ? (meta ? "loading" : "no-meta") : lyricsState
        function retry() {}
    }
    function capabilities() {
        return {
            CanControl: true,
            CanPlay: true,
            CanPause: true,
            CanGoPrevious: true,
            CanGoNext: true,
            CanSeek: true,
            CanSetPosition: true,
            CanSetVolume: true
        };
    }
    function endpoint(token) {
        return {
            token: { owner: token || "fixture" },
            trackToken: { id: "track" },
            status: "Playing",
            positionSeconds: 50,
            lengthSeconds: 200,
            volume: 0.5,
            artworkPath: "",
            presentation: {
                title: "Test track",
                artists: ["Test artist"],
                hostApp: "Spotify",
                controlScope: "application"
            },
            capabilities: capabilities()
        };
    }
    function init() {
        mouseMove(test, test.width - 4, test.height - 4);
        design.reducedMotion = true;
        facade.panelAllowed = true;
        facade.uiAllowed = true;
        facade.selectedEndpoint = endpoint();
        facade.endpoints = [facade.selectedEndpoint];
        facade.positionSeconds = 50;
        facade.pendingAction = "";
        facade.sent = [];
        facade.settingsSections = [];
        volumeSpy.clear();
    }
    function actions() {
        return facade.sent.map(function (entry) { return entry.action; });
    }
    function makeSurface() {
        var surface = createTemporaryObject(surfaceComponent, test);
        volumeSpy.target = surface;
        return surface;
    }
    // A keyboard summon as Panel.qml's open() performs it.
    function summon() {
        var surface = makeSurface();
        surface.explicitOpen = true;
        surface.expandTo("home");
        surface.focusKeys();
        waitForRendering(surface);
        return surface;
    }
    function isInside(item, ancestor) {
        for (var node = item; node; node = node.parent)
            if (node === ancestor)
                return true;
        return false;
    }

    function test_keyboardFocusIsExclusiveOnlyForASummon() {
        compare(IslandKeys.keyboardFocus(true, true, true, false), "exclusive");
        compare(IslandKeys.keyboardFocus(true, false, true, false), "none", "hover open never takes the keyboard");
        compare(IslandKeys.keyboardFocus(true, true, false, false), "none", "collapsed releases it");
        compare(IslandKeys.keyboardFocus(false, true, true, false), "none", "hidden releases it");
        compare(IslandKeys.keyboardFocus(true, true, true, true), "none", "an island window borrows the keyboard");
    }
    function test_relative_seek_does_not_enable_absolute_key_step() {
        var state = { capabilities: { CanControl: true, CanSeek: true, CanSetPosition: false }, lengthSeconds: 200 }
        verify(!IslandKeys.canInvoke("SetPosition", state))
        state.capabilities.CanSetPosition = true
        verify(IslandKeys.canInvoke("SetPosition", state))
    }
    function test_wheelUpEmitsVolumeStep() {
        var surface = makeSurface();
        surface.handleWheel(0, 120);
        compare(volumeSpy.count, 1);
        fuzzyCompare(volumeSpy.signalArguments[0][0], 0.02, 1e-9);
        surface.handleWheel(0, 60);
        compare(volumeSpy.count, 1, "half a notch carries over");
        surface.handleWheel(0, 60);
        compare(volumeSpy.count, 2, "the second half completes the step");
        surface.handleWheel(0, -240);
        compare(volumeSpy.count, 4);
        fuzzyCompare(volumeSpy.signalArguments[3][0], -0.02, 1e-9);
        compare(actions(), [], "the wheel never sends a player command");
    }
    // Natural scrolling reports the deltas flipped, with the event's
    // `inverted` flag set; the finger direction still decides.
    function test_naturalScrollingKeepsTheDirection() {
        var surface = makeSurface();
        surface.handleWheel(0, -120, true);
        compare(volumeSpy.count, 1);
        fuzzyCompare(volumeSpy.signalArguments[0][0], 0.02, 1e-9, "the same finger motion still raises the volume");
        surface.handleWheel(0, 120, true);
        fuzzyCompare(volumeSpy.signalArguments[1][0], -0.02, 1e-9);
        surface.handleWheel(240, 0, true);
        compare(actions(), ["Next"], "and still picks the same skip");
    }
    function test_realWheelEventReachesHandler() {
        var surface = makeSurface();
        waitForRendering(surface);
        mouseWheel(surface, surface.width / 2, 10, 0, 120);
        compare(volumeSpy.count, 1);
        compare(surface.expanded, false, "the wheel neither expands nor collapses");
    }
    function test_realHorizontalWheelSwipes() {
        var surface = makeSurface();
        waitForRendering(surface);
        mouseWheel(surface, surface.width / 2, 10, -120, 0);
        mouseWheel(surface, surface.width / 2, 10, -120, 0);
        compare(actions(), ["Next"]);
        compare(volumeSpy.count, 0);
    }
    function test_diagonalWheelCountsOnce() {
        var surface = makeSurface();
        waitForRendering(surface);
        mouseWheel(surface, surface.width / 2, 10, -100, 120);
        compare(volumeSpy.count, 1, "a mostly vertical event is one volume step");
        mouseWheel(surface, surface.width / 2, 10, -250, 100);
        compare(volumeSpy.count, 1);
        compare(actions(), ["Next"], "a mostly horizontal event is one swipe");
    }
    function test_wheelDoesNotStartHoverDwell() {
        var surface = makeSurface();
        waitForRendering(surface);
        mouseMove(surface, surface.width / 2, 10);
        for (var i = 0; i < 6; ++i) {
            mouseWheel(surface, surface.width / 2, 10, 0, 120);
            wait(30);
        }
        wait(surface.hoverDwell + 100);
        compare(surface.expanded, false, "scrolling on the pill must not open the card under it");
        compare(volumeSpy.count, 6);
    }
    function test_wheelIgnoredWhenExpanded() {
        var surface = makeSurface();
        surface.expandTo("home");
        surface.handleWheel(0, 120);
        surface.handleWheel(-480, 0);
        compare(volumeSpy.count, 0);
        compare(actions(), []);
        waitForRendering(surface);
        mouseWheel(surface, surface.width / 2, 10, 0, 120);
        compare(volumeSpy.count, 0);
    }
    function test_wheelIgnoredWhenNotInteractive() {
        var surface = makeSurface();
        surface.interactive = false;
        surface.handleWheel(0, 120);
        surface.handleWheel(-480, 0);
        compare(volumeSpy.count, 0);
        compare(actions(), []);
    }
    function test_swipeLeftNextOncePerGesture() {
        var surface = makeSurface();
        for (var i = 0; i < 4; ++i)
            surface.handleWheel(-120, 0);
        compare(actions(), ["Next"], "one skip per gesture, however long the swipe");
        wait(350);
        surface.handleWheel(-120, 0);
        surface.handleWheel(-120, 0);
        compare(actions(), ["Next", "Next"], "a new gesture skips again");
    }
    function test_swipeRightPrevious() {
        var surface = makeSurface();
        surface.handleWheel(120, 0);
        compare(actions(), [], "below the threshold nothing fires");
        surface.handleWheel(120, 0);
        compare(actions(), ["Previous"]);
    }
    function test_swipeGestureEndsAfterSilence() {
        var surface = makeSurface();
        surface.handleWheel(-120, 0);
        wait(350);
        surface.handleWheel(-120, 0);
        compare(actions(), [], "a pause longer than the gesture window starts over");
    }
    function test_swipeNeedsCapability() {
        var e = endpoint();
        e.capabilities.CanGoNext = false;
        facade.selectedEndpoint = e;
        var surface = makeSurface();
        surface.handleWheel(-240, 0);
        compare(actions(), []);
    }
    function test_swipeWaitsForPendingCommand() {
        facade.pendingAction = "PlayPause";
        var surface = makeSurface();
        surface.handleWheel(-240, 0);
        compare(actions(), [], "a skip during a pending command would only be refused as busy");
    }
    function test_swipeNudgesAndSpringsBack() {
        design.reducedMotion = false;
        var surface = makeSurface();
        var pill = findChild(surface, "islandPill");
        verify(pill, "the pill must be findable");
        surface.handleWheel(-240, 0);
        compare(actions(), ["Next"]);
        var furthest = 0;
        for (var elapsed = 0; elapsed < 500; elapsed += 16) {
            furthest = Math.min(furthest, surface.swipeNudge);
            compare(pill.transform[0].x, surface.swipeNudge, "the pill rides the nudge");
            wait(16);
        }
        verify(furthest < -surface.nudgeDistance / 2, "a forward skip nudges the pill left, got " + furthest);
        compare(surface.swipeNudge, 0, "the nudge springs back and stops");
        wait(350);
        surface.handleWheel(240, 0);
        compare(actions(), ["Next", "Previous"]);
        var rightmost = 0;
        for (elapsed = 0; elapsed < 500; elapsed += 16) {
            rightmost = Math.max(rightmost, surface.swipeNudge);
            wait(16);
        }
        verify(rightmost > surface.nudgeDistance / 2, "a backward skip nudges the pill right");
        compare(surface.swipeNudge, 0);
    }
    function test_swipeNudgeSkippedUnderReducedMotion() {
        var surface = makeSurface();
        surface.handleWheel(-240, 0);
        compare(actions(), ["Next"]);
        compare(surface.swipeNudge, 0);
        wait(50);
        compare(surface.swipeNudge, 0);
    }
    function test_summonedSpacePlayPause() {
        var surface = summon();
        verify(surface.keysFocused, "a summon focuses the surface root");
        keyClick(Qt.Key_Space);
        compare(actions(), ["PlayPause"]);
    }
    function test_summonShowsFocusRing() {
        var surface = summon();
        var ring = findChild(surface, "keyFocusRing");
        verify(ring);
        verify(ring.visible, "the summoned root shows where the keyboard is");
        wait(50);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-keys-summoned.png").toString().slice(7));
        keyClick(Qt.Key_Return);
        verify(!ring.visible, "the ring moves to the focused control inside the view");
        wait(50);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-keys-controls.png").toString().slice(7));
    }
    // The ring hugs the tabs like a selection outline: the two tab capsules
    // plus a pixel of air inside the border, not the header's whole side.
    function test_focusRingHugsTheTabs() {
        var surface = summon();
        var ring = findChild(surface, "keyFocusRing");
        var header = findChild(surface, "notchHeader");
        var gap = design.focusWidth + 1;
        verify(ring.visible);
        var tabs = header.tabsRect;
        verify(tabs.width > 0 && tabs.height > 0, "the tabs have a rectangle");
        verify(ring.width <= tabs.width + 2 * gap + 1, "no wider than the tabs: " + ring.width + " vs " + tabs.width);
        compare(ring.height, header.capsuleHeight + 2 * gap, "capsule height plus the air");
        compare(ring.radius, ring.height / 2);
        compare(ring.border.width, design.focusWidth);
        var home = ring.mapFromItem(findChild(surface, "viewHomeButton"), 0, 0);
        var shelf = ring.mapFromItem(findChild(surface, "viewShelfButton"), 0, 0);
        var shelfButton = findChild(surface, "viewShelfButton");
        verify(home.x >= 0 && home.y >= 0, "the ring contains the first tab");
        verify(shelf.x + shelfButton.width <= ring.width && shelf.y + shelfButton.height <= ring.height,
            "and the last one");
    }
    function test_focusRingContainsTheBackChevronInLyrics() {
        var surface = summon();
        facade.lyrics = true;
        surface.lyricsSource = lyricsFixture;
        surface.expandTo("lyrics");
        waitForRendering(surface);
        compare(surface.view, "lyrics");
        surface.focusKeys();
        var ring = findChild(surface, "keyFocusRing");
        var back = findChild(surface, "lyricsBackButton");
        verify(ring.visible && back.visible);
        var at = ring.mapFromItem(back, 0, 0);
        verify(at.x >= 0 && at.y >= 0 && at.x + back.width <= ring.width && at.y + back.height <= ring.height,
            "the ring contains the chevron");
        verify(ring.width <= back.width + 2 * (design.focusWidth + 1) + 1, "and hugs it");
    }
    function test_arrowsSeekAndVolume() {
        summon();
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Down);
        compare(actions(), ["SetPosition", "SetPosition", "SetVolume", "SetVolume"]);
        fuzzyCompare(facade.sent[0].value, 45, 1e-9);
        fuzzyCompare(facade.sent[1].value, 55, 1e-9);
        fuzzyCompare(facade.sent[2].value, 0.55, 1e-9);
        fuzzyCompare(facade.sent[3].value, 0.45, 1e-9);
    }
    function test_seekClampsAtEdges() {
        var state = { capabilities: capabilities(), playing: true, positionSeconds: 2, lengthSeconds: 200,
            volume: 0.98, views: ["home", "shelf"], view: "home" };
        compare(IslandKeys.resolve(Qt.Key_Left, 0, true, state, codes).value, 0);
        state.positionSeconds = 197;
        compare(IslandKeys.resolve(Qt.Key_Right, 0, true, state, codes).value, 199, "never seek onto the very end");
        compare(IslandKeys.resolve(Qt.Key_Up, 0, true, state, codes).value, 1);
        state.volume = 0.02;
        compare(IslandKeys.resolve(Qt.Key_Down, 0, true, state, codes).value, 0);
        state.lengthSeconds = 0;
        compare(IslandKeys.resolve(Qt.Key_Right, 0, true, state, codes), null, "no length, no seek");
    }
    function test_wheelUpKeepsOverAmplifiedLevel() {
        compare(IslandKeys.nextVolume(1.5, 0.02), 1.5);
        compare(IslandKeys.nextVolume(0.99, 0.02), 1);
        compare(IslandKeys.nextVolume(0.01, -0.02), 0);
        // The HUD bar's absolute level: clamped to 0..100 %, never above.
        compare(IslandKeys.absoluteVolume(0.4), 0.4);
        compare(IslandKeys.absoluteVolume(1.3), 1);
        compare(IslandKeys.absoluteVolume(-0.2), 0);
        compare(IslandKeys.absoluteVolume("x"), 0);
        fuzzyCompare(IslandKeys.nextVolume(1.5, -0.02), 1.48, 1e-9);
        fuzzyCompare(IslandKeys.nextVolume(0.5, 0.02), 0.52, 1e-9);
    }
    function test_nAndPSkip() {
        summon();
        keyClick(Qt.Key_N);
        keyClick(Qt.Key_P);
        keyClick(Qt.Key_N, Qt.ShiftModifier);
        compare(actions(), ["Next", "Previous", "Next"]);
    }
    function test_ctrlNIgnored() {
        summon();
        keyClick(Qt.Key_N, Qt.ControlModifier);
        keyClick(Qt.Key_Space, Qt.AltModifier);
        keyClick(Qt.Key_Left, Qt.MetaModifier);
        compare(actions(), []);
    }
    function test_heldKeysRepeatOnlyForSteps() {
        // QtTest cannot mark a key event as auto-repeated, so this feeds the
        // handler Keys.onPressed calls with the events a held key produces.
        var surface = summon();
        verify(surface.handleKey({ key: Qt.Key_Space, modifiers: Qt.NoModifier, isAutoRepeat: false }));
        verify(surface.handleKey({ key: Qt.Key_Space, modifiers: Qt.NoModifier, isAutoRepeat: true }),
            "an auto-repeated Space is still the island's key");
        verify(surface.handleKey({ key: Qt.Key_Right, modifiers: Qt.NoModifier, isAutoRepeat: true }));
        compare(actions(), ["PlayPause", "SetPosition"], "a held Space toggles once; a held arrow keeps stepping");
    }
    function test_tabSwitchesViewsAtRoot() {
        var surface = summon();
        keyClick(Qt.Key_Tab);
        compare(surface.view, "shelf");
        verify(surface.keysFocused, "switching views keeps focus on the root");
        keyClick(Qt.Key_Tab);
        compare(surface.view, "home");
        keyClick(Qt.Key_Backtab);
        compare(surface.view, "shelf");
        keyClick(Qt.Key_Tab, Qt.ShiftModifier);
        compare(surface.view, "home");
        compare(actions(), []);
    }
    // Focus from one opening never carries into the next: a collapse drops
    // it, a hover open shows no ring, and every summon puts the keys back on
    // the root, where Tab switches views again.
    function test_everySummonStartsAtTheRoot() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        verify(!surface.keysFocused, "Return stepped into the view");
        surface.collapse(true);
        surface.explicitOpen = false;
        var focused = surface.Window.activeFocusItem;
        verify(!focused || !isInside(focused, surface), "a collapse gives the focus back");
        surface.expandTo("home");
        waitForRendering(surface);
        verify(!surface.keysFocused);
        verify(!findChild(surface, "keyFocusRing").visible, "a hover open wears no stale ring");
        surface.collapse(true);
        surface.explicitOpen = true;
        surface.expandTo("home");
        surface.focusKeys();
        verify(surface.keysFocused, "the next summon focuses the root");
        keyClick(Qt.Key_Tab);
        compare(surface.view, "shelf");
        keyClick(Qt.Key_Backtab);
        compare(surface.view, "home");
    }
    function test_tabTraversesInsideContent() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        verify(!surface.keysFocused, "Return steps into the view");
        keyClick(Qt.Key_Tab);
        compare(surface.view, "home", "Tab inside the view traverses, never switches views");
        var focused = surface.Window.activeFocusItem;
        verify(focused && focused !== surface, "Tab moved focus to a control");
        verify(isInside(focused, findChild(surface, "homeView")), "focus stays inside the view");
        keyClick(Qt.Key_Tab);
        compare(surface.view, "home");
    }
    function test_returnFocusesPlayButton() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        var button = findChild(surface, "toolbarButton-playPause");
        verify(button.activeFocus, "Return lands on the play button");
        verify(button.visualFocus, "with its focus ring showing");
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "Escape from the play button still collapses");
    }
    // With no source, Return reaches the source chooser so a pinned source
    // can be changed back to Auto from the keyboard.
    function test_returnWithoutSourceFocusesTheChooser() {
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        var surface = summon();
        keyClick(Qt.Key_Return);
        verify(findChild(surface, "homeSourceButton").activeFocus);
        keyClick(Qt.Key_Return);
        verify(findChild(surface, "sourceOverlay").item);
    }
    function test_returnStepsIntoShelf() {
        var surface = summon();
        keyClick(Qt.Key_Tab);
        compare(surface.view, "shelf");
        keyClick(Qt.Key_Return);
        verify(!surface.keysFocused);
        verify(findChild(surface, "shelfShareTile").activeFocus);
        verify(isInside(surface.Window.activeFocusItem, findChild(surface, "shelfViewLoader")));
    }
    function test_keysPropagateFromControlsInsideView() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_N);
        compare(actions(), ["Next"], "a control that does not take N lets the island have it");
    }
    function test_focusedButtonKeepsSpace() {
        var surface = summon();
        var button = findChild(surface, "toolbarButton-playPause");
        verify(button);
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(actions(), ["PlayPause"], "exactly one PlayPause, from the button");
    }
    function test_focusedSliderKeepsArrows() {
        var surface = summon();
        var slider = findChild(surface, "progressControl");
        verify(slider);
        var inner = findChild(slider, "intentSlider");
        verify(inner, "the slider's own focusable control");
        inner.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Right);
        compare(actions(), ["SetPosition"], "the slider commits its own step, the root adds none");
        fuzzyCompare(facade.sent[0].value, 55, 1e-9);
    }
    function test_escapeFromIdleSliderCollapses() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        var inner = findChild(findChild(surface, "progressControl"), "intentSlider");
        verify(inner);
        inner.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "a slider with no gesture running lets Escape reach the ladder");
        compare(actions(), []);
    }
    function test_escapeCancelsSliderStepBeforeCollapsing() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        var control = findChild(surface, "progressControl");
        var inner = findChild(control, "intentSlider");
        inner.forceActiveFocus(Qt.TabFocusReason);
        keyPress(Qt.Key_Right);
        verify(control.gesturing);
        keyClick(Qt.Key_Escape);
        verify(!control.gesturing, "the first Escape cancels the running step");
        compare(surface.expanded, true, "and is the slider's alone");
        keyRelease(Qt.Key_Right);
        compare(actions(), [], "the cancelled step sends nothing");
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "the next Escape collapses the island");
    }
    function test_missingCapabilityDoesNothing() {
        var e = endpoint();
        e.capabilities.CanGoNext = false;
        facade.selectedEndpoint = e;
        summon();
        keyClick(Qt.Key_N);
        compare(actions(), []);
    }
    function test_noKeysWithoutControl() {
        facade.uiAllowed = false;
        summon();
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_N);
        compare(actions(), []);
    }
    function test_pendingCommandSendsNothing() {
        facade.pendingAction = "Next";
        summon();
        keyClick(Qt.Key_Space);
        compare(actions(), []);
    }
    function test_keysInertWhileCollapsed() {
        var surface = makeSurface();
        surface.forceActiveFocus();
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Tab);
        compare(actions(), []);
        compare(surface.view, "home");
    }
    function test_escapeStillCollapses() {
        var surface = summon();
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false);
    }
    function test_doubleClickArtPlayPause() {
        var surface = makeSurface();
        surface.expandTo("home");
        waitForRendering(surface);
        var art = findChild(surface, "heroArtwork");
        verify(art && art.visible);
        mouseClick(art, art.width / 2, art.height / 2);
        wait(surface.hoverDwell);
        compare(actions(), [], "a single click on the art does nothing");
        wait(600);
        mouseDoubleClickSequence(art, art.width / 2, art.height / 2);
        compare(actions(), ["PlayPause"]);
        compare(surface.expanded, true);
    }
    function test_doubleClickArtPulses() {
        design.reducedMotion = false;
        var surface = makeSurface();
        surface.expandTo("home");
        tryCompare(surface, "expansion", 1, design.openDuration + 300);
        waitForRendering(surface);
        var art = findChild(surface, "heroArtwork");
        var glow = findChild(surface, "artGlow");
        mouseDoubleClickSequence(art, art.width / 2, art.height / 2);
        compare(actions(), ["PlayPause"]);
        var smallest = 1;
        for (var elapsed = 0; elapsed < 500; elapsed += 16) {
            smallest = Math.min(smallest, art.scale);
            compare(glow.scale, art.scale, "the glow follows the art");
            wait(16);
        }
        verify(smallest < 0.97, "the art dips to acknowledge the toggle, got " + smallest);
        compare(art.scale, 1, "and springs back and stops");
    }
    function test_doubleClickArtRespectsPlayCapability() {
        var e = endpoint();
        e.capabilities.CanPause = false;
        facade.selectedEndpoint = e;
        var surface = makeSurface();
        surface.expandTo("home");
        waitForRendering(surface);
        var art = findChild(surface, "heroArtwork");
        mouseDoubleClickSequence(art, art.width / 2, art.height / 2);
        compare(actions(), []);
        compare(art.scale, 1, "no pulse without a command");
    }
    function test_sourcePickerKeepsTabInsideSurface() {
        facade.endpoints = [endpoint("one"), endpoint("two")];
        facade.selectedEndpoint = facade.endpoints[0];
        var surface = summon();
        keyClick(Qt.Key_Return);
        var content = findChild(surface, "homeView");
        content.pickerOpen = true;
        var list = null;
        tryVerify(function () {
            list = findChild(surface, "sourceList");
            var auto = findChild(surface, "autoSourceButton");
            return list && auto && auto.activeFocus;
        }, 1000, "the picker takes focus on its Auto row");
        // The rows exist before a person could press Tab.
        tryVerify(function () { return list.count === 2 && !!list.itemAtIndex(0) && !!list.itemAtIndex(1); }, 1000);
        keyClick(Qt.Key_Tab);
        tryVerify(function () { return isInside(surface.Window.activeFocusItem, list); }, 1000,
            "Tab moves onto a source row");
        keyClick(Qt.Key_Tab);
        tryVerify(function () {
            var item = list.itemAtIndex(1);
            return item && item.activeFocus;
        }, 1000, "Tab moves to the next source row");
        keyClick(Qt.Key_Backtab);
        tryVerify(function () {
            var item = list.itemAtIndex(0);
            return item && item.activeFocus;
        }, 1000, "Backtab moves back a row");
        compare(surface.view, "home", "the picker keeps Tab; the view never switches");
        compare(content.pickerOpen, true);
        compare(actions(), []);
    }
    function test_islandSettingsEntryOpensWindowInOneClick() {
        var surface = summon();
        keyClick(Qt.Key_Return);
        var settingsButton = findChild(surface, "headerSettingsButton");
        verify(settingsButton);
        settingsButton.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(facade.settingsSections, [""], "the header gear opens the window directly");
        compare(findChild(surface, "homeSettingsOverlay"), null, "the island does not load the legacy settings view");
        compare(surface.view, "home");
        keyClick(Qt.Key_Escape);
        compare(surface.expanded, false, "Escape still collapses the island");
    }
}
