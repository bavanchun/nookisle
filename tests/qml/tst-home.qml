import QtQuick
import QtQuick.Window
import QtTest
import "../../components"
import "../../qml/Settings.js" as Settings
import "../../qml/Tint.js" as Tint

TestCase {
    id: test
    name: "Home"
    width: 700
    height: 240
    when: windowShown
    visible: true
    DesignTokens {
        id: design
        reducedMotion: true
        // The reveal waits 1 s in the app; the fixture does not.
        lyricRevealDelay: 50
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
        property bool remoteArtwork: false
        property bool lyrics: false
        property bool reducedMotion: true
        property bool highContrast: false
        property bool autoShow: true
        property bool island: true
        property bool hud: true
        property bool visualizer: true
        property bool sleepArmable: true
        property bool sleepLockVerified: true
        property double sleepDeadline: 0
        property string sleepFailure: ""
        property var sent: []
        property int retries: 0
        property bool delayVolume: false
        property var calendarSource: null
        property var settingsOpened: []
        function openSettings(section) { settingsOpened = settingsOpened.concat([section]); return true; }
        function captureIntent() {
            return selectedEndpoint ? { endpointToken: selectedEndpoint.token, trackToken: selectedEndpoint.trackToken } : null;
        }
        function invoke(action, intent, value) {
            sent = sent.concat([value === undefined ? action : action + ":" + JSON.stringify(value)]);
            if (delayVolume && action === "SetVolume")
                pendingAction = action;
        }
        function selectSource(token) {}
        function selectAuto() {}
        function retryConnection() { retries++; }
        function armSleepTimer(minutes) { return "ok"; }
        function cancelSleepTimer() {}
        function configure(options) { return true; }
    }
    QtObject {
        id: lyricsFixture
        property bool lyricsEnabled: true
        property string lyricsState: "ready"
        property string errorCode: ""
        property var lines: [{ time: 1, text: "First line" }, { time: 5, text: "Second line" }]
        property int currentIndex: 0
        property var meta: ({ title: "Afterglow" })
        readonly property string displayState: !lyricsEnabled ? "off"
            : lyricsState === "idle" ? (meta ? "loading" : "no-meta") : lyricsState
    }
    // The real source, to enumerate the states a view can be handed.
    LyricsSource {
        id: realSource
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
    Component {
        id: mirrorHomeComponent
        HomeView {
            width: 602
            height: 142
            tokens: design
            coordinator: facade
            settings: Object.assign(Settings.defaults("file"), { showMirror: true })
            lyricsSource: lyricsFixture
            cameraSource: fakeCamera
        }
    }
    Component {
        id: notchBackdrop
        Rectangle {
            color: design.notchColor
        }
    }
    Component {
        id: homeComponent
        HomeView {
            width: 602
            height: 142
            tokens: design
            coordinator: facade
            settings: Settings.defaults("file")
            lyricsSource: lyricsFixture
        }
    }
    Component {
        id: marqueeHost
        Item {
            property alias marquee: marquee
            width: 120
            height: 20
            Marquee {
                id: marquee
                width: parent.width
                tokens: design
            }
        }
    }
    Component {
        id: hiddenAnimationHost
        Window {
            width: 200
            height: 100
            visible: false
            property alias face: face
            property alias marquee: marquee
            IdleFace { id: face; visible: true; reducedMotion: false }
            Marquee {
                id: marquee
                width: 60
                visible: true
                tokens: design
                text: "A title long enough to overflow this narrow line"
            }
        }
    }
    function endpoint(overrides) {
        var e = {
            token: { busEpoch: 1, wellKnownName: "org.mpris.MediaPlayer2.fixture",
                uniqueOwner: ":1.10", endpointGeneration: 1 },
            trackToken: { id: "track" },
            status: "Playing",
            positionSeconds: 74,
            lengthSeconds: 245,
            volume: 0.6,
            shuffle: false,
            loopStatus: "None",
            artworkPath: "",
            presentation: { title: "Test track", artists: ["Test artist"], hostApp: "Spotify" },
            capabilities: {
                CanControl: true, CanPlay: true, CanPause: true, CanGoPrevious: true, CanGoNext: true,
                CanSeek: true, CanSetPosition: true, CanSetVolume: true, CanShuffle: true, CanLoop: true,
                CanFavorite: false, CanRaise: false
            }
        };
        for (var key in overrides)
            e[key] = overrides[key];
        return e;
    }
    function caps(extra) {
        var c = endpoint().capabilities;
        for (var key in extra)
            c[key] = extra[key];
        return c;
    }
    function init() {
        design.reducedMotion = true;
        design.gpuEffects = false;
        design.highContrast = false;
        design.artColor = "transparent";
        facade.selectedEndpoint = endpoint();
        facade.panelAllowed = true;
        facade.uiAllowed = true;
        facade.pinUnavailable = false;
        facade.endpoints = [facade.selectedEndpoint];
        facade.sent = [];
        facade.retries = 0;
        facade.pendingAction = "";
        facade.delayVolume = false;
        facade.calendarSource = null;
        facade.actionError = "";
        facade.statusText = "";
        facade.lyrics = false;
        lyricsFixture.lyricsEnabled = true;
        lyricsFixture.lyricsState = "ready";
        lyricsFixture.errorCode = "";
        lyricsFixture.meta = ({ title: "Afterglow" });
        lyricsFixture.currentIndex = 0;
        cameraCreations = 0;
        cameraDestructions = 0;
    }
    function slotsShown(home) {
        var names = [];
        var toolbar = findChild(home, "musicToolbar");
        var kinds = ["shuffle", "previous", "playPause", "next", "repeat", "volume", "favorite", "back15", "forward15", "none"];
        for (var i = 0; i < toolbar.shown.length; ++i) {
            var slot = findChild(toolbar, "toolbarSlot-" + toolbar.shown[i]);
            if (slot && slot.visible)
                names.push(toolbar.shown[i]);
        }
        return names;
    }

    // Art and glow.
    function test_artScalesAndDarkensWhenPaused() {
        var home = createTemporaryObject(homeComponent, test);
        var art = findChild(home, "heroArtwork");
        var veil = findChild(home, "pausedVeil");
        compare(art.scale, 1);
        compare(veil.opacity, 0);
        facade.selectedEndpoint = endpoint({ status: "Paused" });
        compare(art.scale, design.pausedArtScale, "paused, the cover shrinks");
        compare(veil.opacity, 0.5, "and a flat black veil covers it without GPU effects");
        compare(art.width, design.heroArt);
        compare(art.radius, design.heroArtRadius);
    }
    function test_pausedScaleSprings() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var art = findChild(home, "heroArtwork");
        facade.selectedEndpoint = endpoint({ status: "Paused" });
        verify(art.scale > design.pausedArtScale, "the cover springs down rather than jumping");
        tryCompare(art, "scale", design.pausedArtScale, 1000);
    }
    function test_glowRingsWithoutGpuAndBlurWithIt() {
        design.artColor = "#1f4fb8";
        var home = createTemporaryObject(homeComponent, test);
        var glow = findChild(home, "artGlow");
        verify(glow.visible);
        verify(findChild(glow, "artGlowRing0"), "the software fallback draws the rings");
        compare(findChild(glow, "artGlowBlurLoader").item, null);
        design.gpuEffects = true;
        verify(findChild(glow, "artGlowBlurLoader").item, "with GPU effects the blurred copy exists");
        var blur = findChild(glow, "artGlowBlurLoader").item;
        compare(blur.blurMax, 40);
        compare(blur.rotation, 92);
        compare(blur.opacity, 0.5, "at 0.5 while playing");
        verify(!findChild(glow, "artGlowRing0"), "and replaces the rings");
        facade.selectedEndpoint = endpoint({ status: "Paused" });
        tryCompare(blur, "opacity", 0, 1000, "and fades out while paused");
        design.gpuEffects = false;
    }
    // Quickshell rebuilds a panel's window (island mode on, a screen change)
    // by moving the content into a new window and deleting the old one. An
    // effect nested inside its own source holds the source on the old window
    // through that move, and the next scene-graph sync dereferences the
    // deleted window.
    Component {
        id: bareWindow
        Window {
            width: 700
            height: 240
            visible: true
        }
    }
    function test_pausedBlurFollowsTheHomeToANewWindow() {
        design.gpuEffects = true;
        facade.selectedEndpoint = endpoint({ status: "Paused" });
        var first = createTemporaryObject(bareWindow, test);
        var second = createTemporaryObject(bareWindow, test);
        var home = createTemporaryObject(homeComponent, test, { parent: first.contentItem });
        var art = findChild(home, "heroArtwork");
        var blur = findChild(home, "pausedBlur");
        verify(blur, "paused with GPU effects, the blurred copy exists");
        compare(blur.source, art);
        for (var p = blur.parent; p; p = p.parent)
            verify(p !== art, "the blur is not inside the cover it samples");
        waitForRendering(home);
        failOnWarning(/Cannot use same item on different windows/);
        home.parent = second.contentItem;
        first.destroy();
        wait(0);
        waitForRendering(home);
        verify(findChild(home, "pausedBlur"), "the blur survives the move");
        design.gpuEffects = false;
    }
    function test_lightingEffectOffHidesTheGlow() {
        design.artColor = "#1f4fb8";
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { lightingEffect: false });
        verify(!findChild(home, "artGlow").visible);
    }
    function test_gpuGlowNeedsArtworkTint() {
        design.gpuEffects = true;
        var home = createTemporaryObject(homeComponent, test);
        var glow = findChild(home, "artGlow");
        verify(!glow.visible, "untinted artwork has no GPU halo");
        compare(findChild(glow, "artGlowBlurLoader").item, null);
        design.artColor = "#1f4fb8";
        verify(glow.visible);
        verify(findChild(glow, "artGlowBlurLoader").item);
        design.highContrast = true;
        verify(!glow.visible, "high contrast hides the GPU halo");
        compare(findChild(glow, "artGlowBlurLoader").item, null);
    }
    function test_tapRaisesDoubleTapToggles() {
        facade.selectedEndpoint = endpoint({ capabilities: caps({ CanRaise: true }) });
        var home = createTemporaryObject(homeComponent, test);
        var art = findChild(home, "heroArtwork");
        waitForRendering(home);
        mouseClick(art, art.width / 2, art.height / 2);
        compare(facade.sent, [], "a single tap waits out the double-click interval");
        tryCompare(facade, "sent", ["Raise"], 1500, "then raises the source app");
        facade.sent = [];
        wait(600);
        mouseDoubleClickSequence(art, art.width / 2, art.height / 2);
        wait(Qt.styleHints.mouseDoubleClickInterval + 100);
        compare(facade.sent, ["PlayPause"], "a double tap toggles, and never raises");
    }
    // Paused, the cover shows a play glyph and one tap resumes at once; a
    // double tap does not pause it again.
    function test_tapOnAPausedCoverResumes() {
        facade.selectedEndpoint = endpoint({ status: "Paused", capabilities: caps({ CanRaise: true }) });
        var home = createTemporaryObject(homeComponent, test);
        var art = findChild(home, "heroArtwork");
        var glyph = findChild(home, "pausedPlayGlyph");
        verify(glyph.visible, "a paused cover wears a play glyph");
        waitForRendering(home);
        mouseClick(art, art.width / 2, art.height / 2);
        compare(facade.sent, ["PlayPause"], "one tap resumes, without waiting");
        wait(Qt.styleHints.mouseDoubleClickInterval + 100);
        compare(facade.sent, ["PlayPause"], "and never raises");
        facade.sent = [];
        mouseDoubleClickSequence(art, art.width / 2, art.height / 2);
        wait(Qt.styleHints.mouseDoubleClickInterval + 100);
        compare(facade.sent, ["PlayPause"], "a double tap resumes once");
        facade.selectedEndpoint = endpoint({ capabilities: caps({ CanRaise: true }) });
        verify(!glyph.visible, "playing, no glyph");
    }
    function test_tapWithoutRaiseDoesNothing() {
        var home = createTemporaryObject(homeComponent, test);
        var art = findChild(home, "heroArtwork");
        waitForRendering(home);
        mouseClick(art, art.width / 2, art.height / 2);
        wait(Qt.styleHints.mouseDoubleClickInterval + 100);
        compare(facade.sent, []);
    }
    function test_badgeHiddenUntilItsIconResolves() {
        var home = createTemporaryObject(homeComponent, test);
        var badge = findChild(home, "appBadge");
        verify(!badge.visible, "no icon, no badge");
        var path = Qt.resolvedUrl("../../build/ui-preview/home-badge-fixture.png").toString();
        var fixture = createTemporaryObject(badgeFixture, test);
        waitForRendering(fixture);
        grabImage(fixture).save(path.slice(7));
        home.appIcon = path;
        tryCompare(badge, "visible", true, 1000);
        compare(badge.width, 30);
        var art = findChild(home, "heroArtwork");
        compare(badge.x - (art.x + art.width - badge.width), 10, "offset 10 past the cover's right edge");
        compare(badge.y - (art.y + art.height - badge.height), 10, "and its bottom edge");
        mouseClick(badge);
        compare(home.pickerOpen, true, "the badge chooses the source");
        home.appIcon = "file:///nonexistent/icon.png";
        tryCompare(badge, "visible", false, 1000, "an icon that does not load hides it");
    }
    // Disconnected, Retry is the one filled control and Sources is tonal.
    function test_retryIsTheOnlyFilledActionWhileDisconnected() {
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        facade.uiAllowed = false;
        var home = createTemporaryObject(homeComponent, test);
        var retry = findChild(home, "homeRetryButton");
        verify(retry.visible);
        verify(retry.primary);
        verify(!retry.tonal);
        verify(findChild(home, "homeSourceButton").tonal);
        facade.uiAllowed = true;
    }
    function test_sourceChooserAndRetryInEmptyStates() {
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        var home = createTemporaryObject(homeComponent, test);
        var choose = findChild(home, "homeSourceButton");
        var retry = findChild(home, "homeRetryButton");
        verify(choose.visible);
        verify(choose.tonal, "Sources is a tonal action");
        verify(!choose.primary);
        verify(!retry.visible, "a healthy empty source list needs no reconnect warning");
        compare(findChild(home, "playerStatus").text, "Open Spotify, or play music in your browser.");
        verify(home.focusControls());
        compare(choose.activeFocus, true);
        keyClick(Qt.Key_Return);
        verify(home.pickerOpen);
        home.closeOverlay();
        facade.pinUnavailable = true;
        compare(findChild(home, "playerStatus").text, "Choose a source again, or switch to Auto.");
        choose.trigger();
        verify(home.pickerOpen);
        home.closeOverlay();
        facade.uiAllowed = false;
        facade.statusText = "bus-unavailable";
        verify(retry.visible);
        retry.trigger();
        compare(facade.retries, 1);
    }
    function test_sourceBadgeHasKeyboardAndIconFallback() {
        var home = createTemporaryObject(homeComponent, test);
        var fallback = findChild(home, "sourceBadgeFallback");
        verify(fallback.visible);
        verify(findChild(home, "sourceBadgeTile").visible, "on a raised tile, so it reads as a control");
        fallback.forceActiveFocus();
        keyClick(Qt.Key_Return);
        verify(home.pickerOpen);
        home.closeOverlay();
        var badge = findChild(home, "appBadge");
        var path = Qt.resolvedUrl("../../build/ui-preview/home-badge-fixture.png").toString();
        var fixture = createTemporaryObject(badgeFixture, test);
        grabImage(fixture).save(path.slice(7));
        home.appIcon = path;
        tryCompare(badge, "visible", true, 1000);
        badge.forceActiveFocus();
        keyClick(Qt.Key_Return);
        verify(home.pickerOpen);
    }
    function test_homeMarksTrimmedPresentation() {
        facade.selectedEndpoint = endpoint({ presentationTruncated: true });
        var home = createTemporaryObject(homeComponent, test);
        var marker = findChild(home, "homeTruncationMarker");
        verify(marker.visible);
        compare(marker.Accessible.name, "Some source details were trimmed");
        facade.selectedEndpoint = endpoint();
        verify(!marker.visible);
    }
    Component {
        id: badgeFixture
        Rectangle {
            width: 30
            height: 30
            color: "#1db954"
        }
    }

    // Title and artist.
    // The title and the artist stay neutral on the notch: the artwork colour
    // is for the graphics, never the text.
    function test_titleAndNeutralArtist() {
        var home = createTemporaryObject(homeComponent, test);
        var title = findChild(home, "trackTitle");
        var artist = findChild(home, "trackArtist");
        compare(title.text, "Test track");
        compare(title.weight, Font.Bold);
        compare(artist.text, "Test artist");
        compare(artist.color, design.secondary, "without a tint the artist is secondary");
        design.artColor = "#3a1010";
        verify(design.tintActive);
        compare(artist.color, design.secondary, "and with one it stays secondary");
        compare(title.color, design.text);
    }

    // Marquee.
    function test_marqueeLoopsOnlyWhenOverflowingAndVisible() {
        design.reducedMotion = false;
        var host = createTemporaryObject(marqueeHost, test);
        var marquee = host.marquee;
        marquee.text = "Short";
        verify(!marquee.overflowing);
        verify(!marquee.loopRunning, "a line that fits never scrolls");
        verify(!findChild(marquee, "marqueeCopy").visible);
        marquee.text = "A much longer title than the line can hold at all";
        verify(marquee.overflowing);
        verify(marquee.loopRunning, "an overflowing visible line scrolls");
        verify(findChild(marquee, "marqueeCopy").visible, "with its second copy");
        compare(findChild(marquee, "marqueeCopy").x - findChild(marquee, "marqueeText").x, marquee.textWidth + 20);
        compare(marquee.offset, 0, "after its pause");
        host.visible = false;
        verify(!marquee.loopRunning, "hidden, it stops");
        host.visible = true;
        verify(marquee.loopRunning);
        design.reducedMotion = true;
        verify(!marquee.loopRunning, "reduced motion never scrolls");
        compare(findChild(marquee, "marqueeText").elide, Text.ElideRight);
    }
    function test_hiddenWindowStopsIdleAnimations() {
        design.reducedMotion = false;
        var host = createTemporaryObject(hiddenAnimationHost, null);
        verify(host.marquee.overflowing);
        verify(!host.face.blinking, "the face pauses with its host window");
        verify(!host.marquee.loopRunning, "the title pauses with its host window");
        host.visible = true;
        tryCompare(host.face, "blinking", true);
        tryCompare(host.marquee, "loopRunning", true);
        host.visible = false;
        compare(host.face.blinking, false);
        compare(host.marquee.loopRunning, false);
        design.reducedMotion = true;
    }
    // A scrolling line fades out at its trailing edge, and at its leading
    // edge once it moves, in the colour it sits on; a line that fits or
    // elides has no fades.
    function test_marqueeFadesItsEdges() {
        design.reducedMotion = false;
        var host = createTemporaryObject(marqueeHost, test);
        var marquee = host.marquee;
        var trailing = findChild(marquee, "marqueeTrailingFade");
        var leading = findChild(marquee, "marqueeLeadingFade");
        marquee.text = "Short";
        verify(!trailing.visible && !leading.visible, "a line that fits has no fades");
        marquee.text = "A much longer title than the line can hold at all";
        verify(trailing.visible, "the trailing edge fades while the line waits");
        verify(!leading.visible, "the start is not cut before it moves");
        compare(trailing.x + trailing.width, marquee.width);
        compare(trailing.gradient.stops[1].color, Qt.rgba(design.cardSurface.r, design.cardSurface.g, design.cardSurface.b, 1));
        compare(trailing.gradient.stops[0].color.a, 0);
        marquee.offset = -30;
        verify(leading.visible, "moving, the leading edge fades too");
        compare(leading.x, 0);
        design.reducedMotion = true;
        verify(!trailing.visible, "an elided line has no fade");
    }
    Component {
        id: blackMarqueeHost
        Rectangle {
            property alias marquee: fadeMarquee
            width: 220
            height: 30
            color: "black"
            Marquee {
                id: fadeMarquee
                x: 10
                y: 4
                width: 200
                tokens: design
                pixelSize: design.titleSize + 2
                weight: Font.Bold
                fadeColor: "black"
                text: "OUT WEST (feat. Young Thug) - JACKBOYS, Travis Scott"
            }
        }
    }
    // The brightest pixel in a column range of a grab.
    function brightestIn(image, x0, x1, y0, y1) {
        var best = 0;
        for (var x = x0; x < x1; ++x)
            for (var y = y0; y < y1; ++y) {
                var p = image.pixel(x, y);
                best = Math.max(best, p.r, p.g, p.b);
            }
        return best;
    }
    // Rendered, a long title fades out at its trailing edge rather than
    // ending mid-glyph: its last pixels are far dimmer than its body.
    function test_longTitleFadesInTheRender() {
        design.reducedMotion = false;
        var host = createTemporaryObject(blackMarqueeHost, test);
        var marquee = host.marquee;
        verify(marquee.overflowing && marquee.scrolling);
        waitForRendering(host);
        var image = grabImage(host);
        var right = marquee.x + marquee.width;
        var body = brightestIn(image, marquee.x + 20, marquee.x + 120, 0, host.height);
        var edge = brightestIn(image, right - 2, right, 0, host.height);
        verify(body > 0.8, "the title's body is drawn bright: " + body);
        verify(edge < body * 0.3, "its trailing edge fades toward black: " + edge.toFixed(3));
        image.save(Qt.resolvedUrl("../../build/ui-preview/marquee-long-title-fade.png").toString().slice(7));
    }
    function test_marqueeScrollsAtItsSpeedAfterItsDelay() {
        design.reducedMotion = false;
        var host = createTemporaryObject(marqueeHost, test);
        host.marquee.text = "A much longer title than the line can hold at all";
        wait(design.marqueeDelay - 300);
        compare(host.marquee.offset, 0, "still for the delay");
        tryVerify(function () { return host.marquee.offset < -10; }, 1500, "then moving left");
    }

    // Inline lyric line.
    function test_inlineLyricShowsTheCurrentLineAndOpensLyrics() {
        var home = createTemporaryObject(homeComponent, test);
        var line = findChild(home, "inlineLyric");
        verify(!line.visible, "lyrics off, no line");
        facade.lyrics = true;
        verify(line.visible);
        compare(line.text, "First line");
        lyricsFixture.currentIndex = 1;
        compare(line.text, "Second line");
        lyricsFixture.currentIndex = -1;
        compare(line.text, "♪", "before the first line, a note");
        var opened = 0;
        home.lyricsRequested.connect(function () { opened++; });
        waitForRendering(home);
        mouseClick(line);
        compare(opened, 1, "a tap opens the Lyrics view");
        lyricsFixture.lyricsState = "none";
        verify(line.visible, "the line keeps its place without synced lines");
        compare(line.text, "No synced lyrics");
        lyricsFixture.lyricsState = "instrumental";
        compare(line.text, "Instrumental");
    }
    // Home on the notch's black, with the synced line in full ink.
    function test_homeLyricLinePreview() {
        facade.lyrics = true;
        lyricsFixture.currentIndex = 1;
        var host = createTemporaryObject(notchBackdrop, test, { width: 602, height: 142 });
        var home = createTemporaryObject(homeComponent, host);
        compare(findChild(home, "inlineLyric").text, "Second line");
        waitForRendering(host);
        grabImage(host).save(Qt.resolvedUrl("../../build/ui-preview/home-lyric-line.png").toString().slice(7));
    }
    function test_lyricStates_data() {
        return [
            { tag: "line", state: "ready", index: 1, text: "Second line", ink: "text", weight: Font.Medium },
            { tag: "before-first-line", state: "ready", index: -1, text: "♪", ink: "tint", weight: Font.Medium },
            { tag: "loading", state: "loading", text: "Looking up lyrics…", ink: "secondary", late: true },
            { tag: "idle-with-track", state: "idle", text: "Looking up lyrics…", ink: "secondary", late: true },
            { tag: "none", state: "none", text: "No synced lyrics", ink: "secondary" },
            { tag: "plain", state: "plain", text: "Unsynced lyrics only", ink: "secondary" },
            { tag: "instrumental", state: "instrumental", text: "Instrumental", ink: "secondary", glyph: true },
            { tag: "error", state: "error", code: "network", text: "Lyrics unavailable", ink: "secondary" },
            { tag: "error-timeout", state: "error", code: "timeout", text: "Lyrics unavailable", ink: "secondary" },
            { tag: "error-busy", state: "error", code: "busy", text: "Lyrics unavailable", ink: "secondary" },
            { tag: "error-rate-limited", state: "error", code: "rate-limited", text: "Lyrics unavailable", ink: "secondary" },
            { tag: "no-length", state: "no-length", text: "Lyrics need the track length", ink: "secondary" },
            { tag: "no-meta", state: "idle", meta: null, text: "Nothing to look up", ink: "secondary" },
            { tag: "off", state: "idle", off: true, hidden: true }
        ];
    }
    // Every state Home can be handed says what it means, in the words the
    // Lyrics view uses, and never claims "no lyrics" for a state it does not
    // know.
    function test_lyricStates(data) {
        facade.lyrics = true;
        lyricsFixture.lyricsEnabled = data.off !== true;
        lyricsFixture.errorCode = data.code || "";
        if (data.meta === null)
            lyricsFixture.meta = null;
        lyricsFixture.currentIndex = data.index === undefined ? 0 : data.index;
        lyricsFixture.lyricsState = data.state;
        var home = createTemporaryObject(homeComponent, test);
        var line = findChild(home, "inlineLyric");
        var row = findChild(home, "lyricRow");
        if (data.hidden) {
            verify(!row.visible && !line.visible, "lyrics off hides the row");
            return;
        }
        verify(row.visible);
        if (data.late) {
            compare(line.text, "", "no status text in the first moment of a lookup");
            tryCompare(line, "text", data.text, 1000);
        }
        compare(line.text, data.text);
        verify(Qt.colorEqual(line.color, design[data.ink]), data.ink + " ink: " + line.color);
        if (data.weight !== undefined)
            compare(line.weight, data.weight);
        compare(findChild(home, "lyricGlyph").visible, data.glyph === true);
        verify(line.Accessible.name.indexOf("Lyrics: ") === 0);
        verify(line.Accessible.name.indexOf(data.text) > 0, "the accessible name carries the state: " + line.Accessible.name);
    }
    function test_lyricStatusIsBlankStraightAfterATrackChange() {
        facade.lyrics = true;
        var home = createTemporaryObject(homeComponent, test);
        var line = findChild(home, "inlineLyric");
        compare(line.text, "First line");
        lyricsFixture.lyricsState = "loading";
        compare(line.text, "", "a new lookup shows nothing at first");
        tryCompare(line, "text", "Looking up lyrics…", 1000);
        lyricsFixture.lyricsState = "ready";
        compare(line.text, "First line");
        lyricsFixture.lyricsState = "loading";
        compare(line.text, "", "the reveal waits again for the next lookup");
        lyricsFixture.lyricsState = "none";
        compare(line.text, "No synced lyrics");
        wait(120);
        compare(line.text, "No synced lyrics", "a late reveal never replaces the answer");
    }
    // Hovering the line explains the state in the Lyrics view's own words.
    function test_lyricToolTipCarriesTheViewsDetail() {
        facade.lyrics = true;
        var home = createTemporaryObject(homeComponent, test);
        var tip = findChild(home, "lyricToolTip");
        compare(tip.text, "", "a line needs no explanation");
        lyricsFixture.lyricsState = "none";
        compare(tip.text, "LRCLIB has no timed lyrics for it");
        lyricsFixture.errorCode = "busy";
        lyricsFixture.lyricsState = "error";
        compare(tip.text, "LRCLIB is busy right now");
        lyricsFixture.errorCode = "network";
        compare(tip.text, "Check the connection and try again");
    }
    // A state message appears in place; only lines and notes drop in.
    function test_lyricStatusDoesNotDropIn() {
        design.reducedMotion = false;
        facade.lyrics = true;
        var home = createTemporaryObject(homeComponent, test);
        var line = findChild(home, "inlineLyric");
        lyricsFixture.currentIndex = 1;
        verify(line.enter < 1, "a line drops in");
        tryCompare(line, "enter", 1, 1000);
        lyricsFixture.lyricsState = "none";
        compare(line.enter, 1, "a state message does not drop");
        compare(line.y, 0);
    }
    // A state added to LyricsSource must get a case on Home.
    function test_everyLyricsDisplayStateHasACase() {
        facade.lyrics = true;
        var panel = findChild(createTemporaryObject(homeComponent, test), "playerPanel");
        var seen = {};
        var raw = ["idle", "loading", "ready", "plain", "none", "instrumental", "error", "no-length"];
        var metas = [null, { title: "Afterglow", artist: "A" }];
        for (var enabled = 0; enabled < 2; ++enabled)
            for (var i = 0; i < raw.length; ++i)
                for (var m = 0; m < metas.length; ++m) {
                    realSource.lyricsEnabled = enabled === 1;
                    realSource.lyricsState = raw[i];
                    realSource.endpoint = metas[m] ? { presentation: { title: "Afterglow", artists: ["A"] }, lengthSeconds: 200 } : null;
                    seen[realSource.displayState] = true;
                }
        // The mapping itself, on the real source.
        var track = { presentation: { title: "Afterglow", artists: ["A"] }, lengthSeconds: 200 };
        realSource.lyricsEnabled = true;
        realSource.endpoint = track;
        realSource.lyricsState = "idle";
        compare(realSource.displayState, "loading", "idle with a track is a lookup");
        realSource.endpoint = { presentation: { title: "Afterglow" }, lengthSeconds: 200 };
        compare(realSource.displayState, "no-meta", "idle with no artist has nothing to look up");
        realSource.lyricsState = "error";
        compare(realSource.displayState, "error");
        realSource.lyricsEnabled = false;
        compare(realSource.displayState, "off");
        var states = Object.keys(seen);
        verify(states.indexOf("off") >= 0 && states.indexOf("no-meta") >= 0 && states.indexOf("loading") >= 0);
        for (var j = 0; j < states.length; ++j)
            verify(panel.lyricStateCopy.hasOwnProperty(states[j]), "Home has an explicit case for " + states[j]);
        verify(panel.lyricStateCopy.hasOwnProperty("ready"));
        verify(!panel.lyricStateCopy.hasOwnProperty("idle"), "idle never reaches a view");
    }
    // The player block holds still as lyrics load and arrive: the line keeps
    // its row for every lookup state, and the row clips a line dropping in.
    // A track change hands the title and artist off together, on one wrapper.
    function test_metadataHandsOffOnATrackChange() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var wrapper = findChild(home, "trackMetadata");
        var title = findChild(home, "trackTitle"), artist = findChild(home, "trackArtist");
        verify(wrapper);
        compare(wrapper.opacity, 1);
        facade.selectedEndpoint = endpoint({ trackToken: { id: "next" },
            presentation: { title: "Next one", artists: ["Next artist"], hostApp: "Spotify" } });
        tryVerify(function () { return wrapper.opacity < 1; }, 500, "the old metadata starts to fade");
        compare(title.text, "Test track", "still the old title");
        compare(artist.text, "Test artist", "and the old artist");
        grabImage(home).save(Qt.resolvedUrl("../../build/ui-preview/home-metadata-handoff.png").toString().slice(7));
        tryCompare(title, "text", "Next one", 500);
        compare(artist.text, "Next artist", "they swap together");
        tryCompare(wrapper, "opacity", 1, design.closedFadeOut + design.closedFadeIn + 200);
    }
    function test_metadataRestartsOnARapidSkip() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var wrapper = findChild(home, "trackMetadata");
        var title = findChild(home, "trackTitle");
        function skip(id, name) {
            facade.selectedEndpoint = endpoint({ trackToken: { id: id },
                presentation: { title: name, artists: ["Artist"], hostApp: "Spotify" } });
        }
        skip("a", "Skipped title");
        tryVerify(function () { return wrapper.opacity < 0.9; }, 500);
        var seen = [title.text];
        var before = wrapper.opacity;
        skip("b", "Final title");
        verify(wrapper.opacity <= before + 0.001, "it restarts from the current opacity");
        for (var i = 0; i < 40; ++i) {
            wait(10);
            if (seen.indexOf(title.text) < 0)
                seen.push(title.text);
        }
        compare(seen, ["Test track", "Final title"], "never the skipped title");
        compare(wrapper.opacity, 1);
    }
    function test_metadataStaysPutWhenOnlyThePositionMoves() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var wrapper = findChild(home, "trackMetadata");
        facade.selectedEndpoint = endpoint({ positionSeconds: 150 });
        wait(120);
        compare(wrapper.opacity, 1);
        compare(findChild(home, "trackTitle").text, "Test track");
    }
    function test_metadataSwapsAtOnceUnderReducedMotion() {
        var home = createTemporaryObject(homeComponent, test);
        facade.selectedEndpoint = endpoint({ trackToken: { id: "next" },
            presentation: { title: "Next one", artists: ["Next artist"], hostApp: "Spotify" } });
        compare(findChild(home, "trackTitle").text, "Next one");
        compare(findChild(home, "trackArtist").text, "Next artist");
        compare(findChild(home, "trackMetadata").opacity, 1);
    }
    function test_playerBlockHoldsStillAsLyricsArrive() {
        facade.lyrics = true;
        lyricsFixture.lyricsState = "loading";
        var home = createTemporaryObject(homeComponent, test);
        var scrubber = findChild(home, "scrubberBlock");
        var toolbar = findChild(home, "musicToolbar");
        var title = findChild(home, "trackTitle");
        var before = [title.mapToItem(home, 0, 0).y, scrubber.mapToItem(home, 0, 0).y, toolbar.mapToItem(home, 0, 0).y];
        lyricsFixture.lyricsState = "ready";
        compare([title.mapToItem(home, 0, 0).y, scrubber.mapToItem(home, 0, 0).y, toolbar.mapToItem(home, 0, 0).y], before,
            "nothing moves when the lyric arrives");
        lyricsFixture.lyricsState = "none";
        compare(scrubber.mapToItem(home, 0, 0).y, before[1], "nor when there is none");
        verify(findChild(home, "lyricRow").clip);
        var bottom = toolbar.mapToItem(home, 0, toolbar.height).y;
        verify(bottom <= findChild(home, "playerPanel").height, "the block fits Home: " + bottom);
    }
    // The cover sits 5 px in, as boring.notch pads it, the text column
    // starts beside it, and the times sit under the scrubber in tabular
    // figures.
    function test_playerIsTopAlignedWithTimesUnderTheScrubber() {
        var home = createTemporaryObject(homeComponent, test);
        var art = findChild(home, "artBox");
        compare(art.x, 5);
        compare(art.y, 5);
        var details = findChild(home, "playerDetails");
        compare(details.x, 5 + design.heroArt + 5 + design.gap);
        var progress = findChild(home, "progressControl");
        var elapsed = findChild(home, "elapsedTime");
        var total = findChild(home, "totalTime");
        verify(elapsed.mapToItem(home, 0, 0).y >= progress.mapToItem(home, 0, progress.height).y, "the times sit under the track");
        compare(elapsed.mapToItem(home, 0, 0).x, progress.mapToItem(home, 0, 0).x);
        compare(total.mapToItem(home, total.width, 0).x, progress.mapToItem(home, progress.width, 0).x);
        compare(findChild(progress, "intentSliderTrack").width, progress.width, "the track spans the column");
        compare(elapsed.font.features["tnum"], 1);
    }
    // Connected with nothing to play, Home is a glance: the time, the date
    // and, with the calendar on, the event now or next. Its clock wakes once
    // a minute, only while it is on screen.
    function test_idleHomeIsAGlance() {
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        var home = createTemporaryObject(homeComponent, test);
        var glance = findChild(home, "homeGlance");
        verify(glance.visible);
        verify(!findChild(home, "trackTitle").visible, "the glance takes the title's place");
        verify(findChild(home, "homeSourceButton").visible, "the source choice stays");
        compare(findChild(glance, "glanceTime").text, Qt.formatTime(glance.now, Qt.locale().timeFormat(Locale.ShortFormat)));
        compare(findChild(glance, "glanceDate").text, Qt.formatDate(glance.now, "dddd, d MMMM"));
        compare(findChild(glance, "glanceTime").font.features["tnum"], 1);
        verify(!findChild(glance, "glanceEvent").visible, "no calendar, no event line");
        var minute = findChild(glance, "glanceMinute");
        verify(minute.running);
        verify(!minute.repeat, "a one-shot, re-armed each minute");
        verify(minute.interval <= 60050);
        home.visible = false;
        verify(!minute.running, "hidden, the clock sleeps");
        home.visible = true;
        verify(minute.running);
        var soon = new Date(Date.now() + 20 * 60000 + 30000);
        var later = new Date(soon.getTime() + 30 * 60000);
        facade.calendarSource = ({ items: [{ sourceId: "s", uid: "u", title: "Stand-up",
            start: Qt.formatDateTime(soon, "yyyy-MM-ddThh:mm:ss.zzz"), end: Qt.formatDateTime(later, "yyyy-MM-ddThh:mm:ss.zzz") }] });
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true });
        var event = findChild(glance, "glanceEvent");
        if (soon.getDate() === new Date().getDate()) {
            verify(event.visible, "with the calendar on, the next event shows");
            compare(event.text, "In 21 min · Stand-up");
        }
        facade.selectedEndpoint = endpoint();
        verify(!glance.visible, "a source brings the player back");
        verify(!minute.running);
    }
    // A paused player is not idle: Home keeps the full player, with the
    // paused cover's play glyph as the way to resume, not the glance.
    function test_pausedPlayerKeepsThePlayerNotTheGlance() {
        facade.selectedEndpoint = endpoint({ status: "Paused" });
        var home = createTemporaryObject(homeComponent, test);
        verify(!findChild(home, "homeGlance").visible);
        verify(findChild(home, "trackTitle").visible);
        verify(findChild(home, "pausedPlayGlyph").visible);
    }
    // A lost pinned source keeps its explaining title rather than a glance.
    function test_unavailableSourceKeepsItsTitle() {
        facade.selectedEndpoint = null;
        facade.pinUnavailable = true;
        var home = createTemporaryObject(homeComponent, test);
        verify(!findChild(home, "homeGlance").visible);
        verify(findChild(home, "trackTitle").visible);
    }
    Component {
        id: blackHomeComponent
        Rectangle {
            property alias home: blackHome
            width: 602
            height: 142
            color: "black"
            HomeView {
                id: blackHome
                anchors.fill: parent
                tokens: design
                coordinator: facade
                settings: Object.assign(Settings.defaults("file"), { showCalendar: true })
                lyricsSource: lyricsFixture
            }
        }
    }
    // The first row of lit pixels inside an item's box, in the grab's
    // coordinates: where its glyphs really start.
    function firstInkRow(image, host, item) {
        var box = item.mapToItem(host, 0, 0, item.width, item.height);
        for (var y = Math.max(0, Math.floor(box.y)); y < Math.min(host.height, box.y + box.height); ++y)
            for (var x = Math.max(0, Math.floor(box.x)); x < Math.min(host.width, box.x + box.width); ++x)
                if (Math.max(image.pixel(x, y).r, image.pixel(x, y).g, image.pixel(x, y).b) > 0.5)
                    return y;
        return -1;
    }
    // Home's columns share one top line: the cover's top edge, the title's
    // capitals and the calendar month's capitals, read from the rendered
    // pixels. The buttons sit at Home's foot, level with the calendar's
    // end, so the player column is not top-heavy.
    function test_homeColumnsShareATopLine() {
        facade.calendarSource = ({ items: [] });
        var host = createTemporaryObject(blackHomeComponent, test);
        var home = host.home;
        waitForRendering(host);
        var image = grabImage(host);
        var artTop = findChild(home, "artBox").mapToItem(host, 0, 0).y;
        compare(artTop, 5);
        var title = firstInkRow(image, host, findChild(home, "trackTitle"));
        var month = firstInkRow(image, host, findChild(home, "calendarMonth"));
        verify(Math.abs(title - artTop) <= 1, "the title's capitals start at the cover's top: " + title);
        verify(Math.abs(month - artTop) <= 1, "and so do the month's: " + month);
        var toolbar = findChild(home, "musicToolbar");
        compare(toolbar.mapToItem(host, 0, toolbar.height).y, host.height, "the buttons sit at Home's foot");
        var scrubber = findChild(home, "scrubberBlock");
        verify(toolbar.mapToItem(host, 0, 0).y >= scrubber.mapToItem(host, 0, scrubber.height).y, "clear of the scrubber");
        facade.selectedEndpoint = null;
        facade.endpoints = [];
        waitForRendering(host);
        image = grabImage(host);
        var time = firstInkRow(image, host, findChild(home, "glanceTime"));
        verify(Math.abs(time - artTop) <= 1, "the glance's time starts on the line too: " + time);
    }
    // With no source, Home shows no dead scrubber or empty button band.
    function test_noSourceHidesTheScrubberAndButtons() {
        facade.selectedEndpoint = null;
        var home = createTemporaryObject(homeComponent, test);
        verify(!findChild(home, "scrubberBlock").visible);
        verify(!findChild(home, "musicToolbar").visible);
    }
    function test_inlineLyricDropsIn() {
        design.reducedMotion = false;
        facade.lyrics = true;
        var home = createTemporaryObject(homeComponent, test);
        var line = findChild(home, "inlineLyric");
        lyricsFixture.currentIndex = 1;
        verify(line.enter < 1, "a new line starts above and faded");
        verify(line.y < 0);
        tryCompare(line, "enter", 1, 1000);
        compare(line.y, 0);
    }
    function test_inlineLyricFadesWhilePaused() {
        facade.lyrics = true;
        var home = createTemporaryObject(homeComponent, test);
        var line = findChild(home, "inlineLyric");
        compare(line.opacity, 1);
        facade.selectedEndpoint = endpoint({ status: "Paused" });
        compare(line.opacity, 0);
        facade.selectedEndpoint = endpoint({ status: "Playing" });
        compare(line.opacity, 1);
    }
    function test_statusLineReplacesTheLyric() {
        facade.lyrics = true;
        var home = createTemporaryObject(homeComponent, test);
        facade.actionError = "busy";
        verify(findChild(home, "playerStatus").visible);
        verify(!findChild(home, "inlineLyric").visible);
        facade.actionError = "";
        verify(!findChild(home, "playerStatus").visible);
    }

    // Scrubber.
    function test_scrubberThickensWhileDragged() {
        var home = createTemporaryObject(homeComponent, test);
        var progress = findChild(home, "progressControl");
        var track = findChild(progress, "intentSliderTrack");
        compare(track.height, design.scrubHeight);
        verify(progress.beginGesture());
        compare(track.height, design.scrubHeightActive, "9 px while dragged");
        progress.cancelGesture();
        compare(track.height, design.scrubHeight);
        compare(findChild(home, "elapsedTime").text, "1:14");
        compare(findChild(home, "totalTime").text, "4:05");
    }
    function test_scrubberHeightSprings() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var progress = findChild(home, "progressControl");
        var track = findChild(progress, "intentSliderTrack");
        progress.beginGesture();
        verify(track.height < design.scrubHeightActive, "it grows on the spring");
        tryCompare(track, "height", design.scrubHeightActive, 1000);
        progress.cancelGesture();
    }
    function test_sliderColorSetting() {
        design.artColor = "#e36954";
        var home = createTemporaryObject(homeComponent, test);
        var fill = findChild(findChild(home, "progressControl"), "intentSliderFill");
        compare(fill.color, design.tint, "the cover colour by default");
        compare(findChild(findChild(home, "progressControl"), "intentSliderHandle").color, fill.color,
            "the knob matches the fill");
        home.settings = Object.assign(Settings.defaults("file"), { sliderColor: "white" });
        compare(fill.color, Qt.color("#ffffff"));
        home.settings = Object.assign(Settings.defaults("file"), { sliderColor: "accent" });
        compare(fill.color, design.accent);
    }

    // Toolbar.
    function test_toolbarSlotsFromSettings() {
        var home = createTemporaryObject(homeComponent, test);
        compare(slotsShown(home), ["shuffle", "previous", "playPause", "next", "repeat"]);
        home.settings = Object.assign(Settings.defaults("file"), {
            musicControlSlots: ["back15", "playPause", "forward15", "volume", "favorite"] });
        compare(slotsShown(home), ["back15", "playPause", "forward15", "volume", "favorite"]);
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlotLimit: 3 });
        compare(slotsShown(home), ["shuffle", "previous", "playPause"], "the limit cuts the row");
    }
    function test_toolbarHidesWhatTheSourceCannotDo() {
        facade.selectedEndpoint = endpoint({ capabilities: caps({ CanShuffle: false, CanLoop: false }) });
        var home = createTemporaryObject(homeComponent, test);
        compare(slotsShown(home), ["previous", "playPause", "next"], "no shuffle or repeat without CanShuffle and CanLoop");
        facade.selectedEndpoint = endpoint({ shuffle: null, loopStatus: null });
        compare(slotsShown(home), ["previous", "playPause", "next"], "nor without their state");
        facade.selectedEndpoint = null;
        compare(slotsShown(home), [], "nothing without a source");
    }
    function test_favoriteDimsWhenUnsupported() {
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlots: ["favorite"] });
        var button = findChild(home, "toolbarButton-favorite");
        verify(button.visible, "favorite shows even without support");
        compare(button.opacity, 0.35);
        verify(!button.actionEnabled);
        facade.selectedEndpoint = endpoint({ liked: true, capabilities: caps({ CanFavorite: true }) });
        compare(button.opacity, 1);
        compare(button.iconName, "favorite-filled");
        button.trigger();
        compare(facade.sent, ["Favorite"]);
    }
    function test_crowdedHomeDropsTheEdgeSlots() {
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true, showMirror: true });
        compare(slotsShown(home), ["previous", "playPause", "next"]);
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true, showMirror: true, musicControlSlotLimit: 4 });
        compare(slotsShown(home), ["shuffle", "previous", "playPause", "next"], "only at a limit of 5");
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true });
        facade.calendarSource = ({ items: [] });
        compare(slotsShown(home).length, 5, "one side panel keeps all five");
    }
    function test_toggleStateAndActions() {
        var home = createTemporaryObject(homeComponent, test);
        var shuffle = findChild(home, "toolbarButton-shuffle");
        var repeat = findChild(home, "toolbarButton-repeat");
        design.artColor = "#e2402e";
        compare(shuffle.iconColor, design.secondary, "an off toggle is dimmed");
        verify(!findChild(home, "toolbarActiveDot-shuffle").visible);
        compare(findChild(home, "toolbarButton-next").iconColor, design.text, "a plain button is full ink");
        compare(repeat.iconName, "repeat");
        facade.selectedEndpoint = endpoint({ shuffle: true, loopStatus: "Track" });
        compare(shuffle.iconColor, design.text, "shuffle on is full ink, not the tint");
        verify(findChild(home, "toolbarActiveDot-shuffle").visible, "with a dot under it");
        compare(repeat.iconColor, design.text);
        verify(findChild(home, "toolbarActiveDot-repeat").visible);
        compare(repeat.iconName, "repeat-one");
        shuffle.trigger();
        repeat.trigger();
        compare(facade.sent, ["SetShuffle:false", "SetLoopStatus:\"None\""]);
        facade.sent = [];
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlots: ["back15", "forward15", "playPause"] });
        findChild(home, "toolbarButton-back15").trigger();
        findChild(home, "toolbarButton-forward15").trigger();
        findChild(home, "toolbarButton-playPause").trigger();
        compare(facade.sent, ["Seek:-15", "Seek:15", "PlayPause"]);
        facade.pendingAction = "Seek";
        verify(!findChild(home, "toolbarButton-playPause").actionEnabled, "nothing sends while a command is pending");
    }
    function test_buttonsBounce() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var button = findChild(home, "toolbarButton-next");
        verify(button.bounce);
        waitForRendering(home);
        mousePress(button);
        tryVerify(function () { return button.scale < 0.95; }, 500, "pressed, it dips toward 0.9");
        verify(button.scale >= 0.85);
        mouseRelease(button);
        tryCompare(button, "scale", 1, 1000);
    }

    // Volume popover.
    function test_volumePopover() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlots: ["playPause", "volume"] });
        var volumeSlot = findChild(home, "toolbarSlot-volume");
        var tray = findChild(volumeSlot, "volumeTray");
        var slider = findChild(volumeSlot, "volumeSlider");
        compare(tray.width, 0);
        verify(!slider.visible);
        findChild(home, "toolbarButton-volume").trigger();
        verify(slider.visible);
        compare(slider.width, 48);
        compare(slider.height, 24, "a hit area a pointer can take");
        compare(findChild(slider, "intentSliderTrack").width, 48, "the track spans the tray");
        tryCompare(tray, "width", 48 + design.small, 400, "it slides out over 120 ms");
        verify(slider.beginGesture());
        slider.updateGesture(0.3);
        compare(facade.sent, [], "throttled");
        tryCompare(facade, "sent", ["SetVolume:0.3"], 400, "then written while dragging");
        slider.updateGesture(0.35);
        slider.updateGesture(0.4);
        tryVerify(function () { return facade.sent.length === 2; }, 400);
        compare(facade.sent[1], "SetVolume:0.4", "one write per 100 ms, with the latest value");
        slider.cancelGesture();
        findChild(home, "toolbarButton-volume").trigger();
        tryCompare(tray, "width", 0, 500, "and slides back");
    }
    function test_volumeReleaseWaitsForPendingWrite() {
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlots: ["volume"] });
        facade.delayVolume = true;
        findChild(home, "toolbarButton-volume").trigger();
        var slider = findChild(home, "volumeSlider");
        verify(slider.beginGesture());
        slider.updateGesture(0.3);
        tryCompare(facade, "sent", ["SetVolume:0.3"], 400);
        compare(facade.pendingAction, "SetVolume");
        slider.updateGesture(0.8);
        slider.commitGesture();
        compare(facade.sent, ["SetVolume:0.3"], "the final write waits for the earlier reply");
        verify(slider.queuedWrite, "the final value remains queued");
        compare(slider.queuedWrite.value, 0.8);
        facade.pendingAction = "";
        compare(facade.sent, ["SetVolume:0.3", "SetVolume:0.8"], "the latest value is sent after the reply");
    }
    function test_volumeTrayClosesOnSourceAndCapabilityChanges() {
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlots: ["volume"] });
        var toolbar = findChild(home, "musicToolbar");
        var button = findChild(home, "toolbarButton-volume");
        button.trigger();
        verify(toolbar.volumeOpen);
        facade.selectedEndpoint = endpoint({ capabilities: caps({ CanSetVolume: false }) });
        verify(!toolbar.volumeOpen);
        facade.selectedEndpoint = endpoint();
        verify(!toolbar.volumeOpen);
        button.trigger();
        verify(toolbar.volumeOpen);
        facade.selectedEndpoint = endpoint({ volume: 0.65 });
        verify(toolbar.volumeOpen, "a same-source volume snapshot keeps the tray open");
        facade.selectedEndpoint = endpoint({ token: { busEpoch: 1,
            wellKnownName: "org.mpris.MediaPlayer2.anotherFixture", uniqueOwner: ":1.11", endpointGeneration: 1 } });
        verify(!toolbar.volumeOpen, "a different capable source closes the tray");
    }

    function within(item, ancestor) {
        for (var node = item; node; node = node.parent)
            if (node === ancestor)
                return true;
        return false;
    }
    // A tray that closes under its focused slider hands focus to the speaker
    // button: arrow keys must never write volume to a hidden slider.
    function test_closingTrayMovesFocusToTheSpeaker() {
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { musicControlSlots: ["volume"] });
        var toolbar = findChild(home, "musicToolbar");
        var button = findChild(home, "toolbarButton-volume");
        var slider = findChild(home, "volumeSlider");
        button.trigger();
        verify(toolbar.volumeOpen);
        slider.forceActiveFocus(Qt.TabFocusReason);
        var focused = home.Window.activeFocusItem;
        verify(focused && within(focused, slider), "the slider has the keyboard");
        facade.selectedEndpoint = endpoint({ capabilities: caps({ CanSetVolume: false }) });
        verify(!toolbar.volumeOpen);
        verify(button.activeFocus, "the speaker button takes the keyboard back");
        facade.sent = [];
        keyClick(Qt.Key_Right);
        compare(facade.sent.filter(function (entry) { return entry.indexOf("SetVolume") === 0; }), [],
            "no volume is written through the hidden slider");
        facade.selectedEndpoint = endpoint();
        button.trigger();
        slider.forceActiveFocus(Qt.TabFocusReason);
        facade.selectedEndpoint = endpoint({ token: { busEpoch: 1,
            wellKnownName: "org.mpris.MediaPlayer2.anotherFixture", uniqueOwner: ":1.11", endpointGeneration: 1 } });
        verify(!toolbar.volumeOpen);
        verify(findChild(home, "toolbarButton-volume").activeFocus, "a source change hands focus back too");
    }

    // Layout.
    function test_layoutWidths() {
        var home = createTemporaryObject(homeComponent, test);
        var player = findChild(home, "playerPanel");
        var row = findChild(home, "homeRow");
        verify(!findChild(home, "calendarPanel").visible);
        verify(!findChild(home, "cameraPanel").visible);
        compare(player.width, 602, "alone, the player takes the width");
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true });
        compare(row.spacing, 15);
        compare(home.calendarWidth, 215);
        compare(player.width, 602 - home.calendarWidth - 15);
        var calendar = findChild(home, "calendarPanel");
        verify(calendar.visible && findChild(calendar, "calendarWheel") && findChild(calendar, "calendarList"),
            "Home shows the real day wheel and event list");
        compare(calendar.source, facade.calendarSource, "Home uses the Service's calendar source");
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true, showMirror: true });
        compare(row.spacing, 10, "the gaps tighten with the mirror");
        compare(home.calendarWidth, 170);
        verify(calendar.compact, "the calendar uses its narrow list beside the mirror");
        compare(player.width, 602 - home.calendarWidth - home.mirrorWidth - 20);
        home.settings = Object.assign(Settings.defaults("file"), { showMirror: true });
        compare(player.width, 602 - home.mirrorWidth - 10);
        // No calendar yet: Add a calendar opens the Calendar settings.
        facade.settingsOpened = [];
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true });
        calendar.addCalendarRequested();
        compare(facade.settingsOpened, ["calendar"]);
    }
    // The panel keeps no clock of its own: Home refreshes it each time it is
    // shown, so an island opened after midnight, or after another day was
    // picked, starts on today with the wheel and list back on today.
    function test_calendarReturnsToTodayWhenShown() {
        var home = createTemporaryObject(homeComponent, test);
        home.settings = Object.assign(Settings.defaults("file"), { showCalendar: true });
        var calendar = findChild(home, "calendarPanel");
        var wheel = findChild(calendar, "calendarWheel");
        var stale = new Date();
        stale.setDate(stale.getDate() - 3);
        calendar.now = stale;
        calendar.selectDay(calendar.todayIndex + 2);
        verify(!calendar.showingToday);
        home.visible = false;
        home.visible = true;
        var today = new Date();
        compare(calendar.now.toDateString(), today.toDateString(), "shown again, the panel takes the current time");
        verify(calendar.showingToday, "and selects today");
        compare(wheel.currentIndex, calendar.todayIndex, "with the wheel back on today");
        home.settings = Settings.defaults("file");
        verify(!calendar.visible, "showCalendar off hides the panel");
    }
    // The mirror's camera runs only with the mirror on, the island open and
    // settled, Home shown and the tile visible; losing any of them destroys
    // the capture source.
    function test_mirrorCameraGates() {
        var home = createTemporaryObject(mirrorHomeComponent, test);
        var mirror = findChild(home, "cameraPanel");
        verify(mirror.visible);
        compare(mirror.captureAllowed, false, "a closed island never opens the camera");
        home.islandOpen = true;
        compare(mirror.captureAllowed, false, "nor does another view");
        home.onHome = true;
        compare(mirror.captureAllowed, true);
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        compare(cameraCreations, 1);
        home.pickerOpen = true;
        compare(mirror.captureAllowed, false, "an overlay over the tile stops it");
        tryCompare(test, "cameraDestructions", 1);
        home.closeOverlay();
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        home.mirrorHidden = true;
        verify(!mirror.visible, "the header toggle hides the tile for the session");
        compare(findChild(home, "playerPanel").width, 602, "and the player takes the room back");
        compare(mirror.captureAllowed, false);
        tryCompare(test, "cameraDestructions", 2);
        home.mirrorHidden = false;
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        home.islandOpen = false;
        tryCompare(test, "cameraDestructions", 3);
        home.islandOpen = true;
        tryVerify(function () { return mirror.sourceItem !== null; }, 1000);
        home.settings = Settings.defaults("file");
        verify(!mirror.visible);
        compare(mirror.captureAllowed, false, "showMirror off stops it");
        tryCompare(test, "cameraDestructions", 4);
        compare(cameraCreations, 4);
    }
    function test_mirrorShapeFollowsTheSetting() {
        var home = createTemporaryObject(mirrorHomeComponent, test);
        var mirror = findChild(home, "cameraPanel");
        compare(mirror.shape, "rectangle");
        compare(mirror.clipRadius, 13);
        home.settings = Object.assign(Settings.defaults("file"), { showMirror: true, mirrorShape: "circle" });
        compare(mirror.shape, "circle");
        compare(mirror.clipRadius, mirror.tileSize / 2);
    }
    // Nothing playing, Home shows the idle face at 80x70 in the cover's
    // place; its blink runs only while it is on screen.
    function test_emptyHomeShowsTheIdleFace() {
        design.reducedMotion = false;
        var home = createTemporaryObject(homeComponent, test);
        var face = findChild(home, "homeIdleFace");
        verify(!face.visible, "a source hides the face");
        verify(!face.blinking);
        facade.selectedEndpoint = null;
        verify(face.visible);
        compare(face.width, 80);
        compare(face.height, 70);
        verify(!findChild(home, "heroArtwork").visible);
        verify(face.blinking, "it blinks while shown");
        home.visible = false;
        verify(!face.blinking, "and stops once Home is hidden");
        home.visible = true;
        verify(face.blinking);
        design.reducedMotion = true;
        verify(!face.blinking, "reduced motion keeps it still");
    }
    // Closing the picker from the keyboard hands focus back to the control
    // that opened it, not to the empty overlay.
    function test_pickerReturnsFocusToItsOpener() {
        var home = createTemporaryObject(homeComponent, test);
        var fallback = findChild(home, "sourceBadgeFallback");
        verify(fallback.visible, "without an app icon the fallback button chooses the source");
        fallback.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        verify(home.pickerOpen);
        var overlay = findChild(home, "sourceOverlay");
        tryVerify(function () { return within(home.Window.activeFocusItem, overlay); }, 1000,
            "the picker takes the keyboard");
        // Escape reaches the picker through the surface's ladder, which
        // closes Home's overlay.
        verify(home.closeOverlay());
        verify(!home.pickerOpen);
        tryVerify(function () { return fallback.activeFocus; }, 1000, "Escape returns focus to the button that opened the picker");
        verify(fallback.visualFocus, "with its focus ring");
        keyClick(Qt.Key_Return);
        verify(home.pickerOpen);
        tryVerify(function () { return within(home.Window.activeFocusItem, overlay); }, 1000);
        // Choosing a row (Automatic here) closes the picker too.
        var auto = findChild(overlay.item, "autoSourceButton");
        auto.forceActiveFocus(Qt.TabFocusReason);
        auto.trigger();
        verify(!home.pickerOpen);
        tryVerify(function () { return fallback.activeFocus; }, 1000, "a choice returns focus to the opener too");
    }
    function test_sourceOverlay() {
        var home = createTemporaryObject(homeComponent, test);
        compare(findChild(home, "homeSettingsOverlay"), null, "the settings open in their own window");
        home.pickerOpen = true;
        verify(findChild(home, "sourceOverlay").item);
        verify(!findChild(home, "homeRow").visible);
        verify(home.closeOverlay());
        verify(findChild(home, "homeRow").visible);
        verify(!home.closeOverlay(), "nothing left to close");
    }
}
