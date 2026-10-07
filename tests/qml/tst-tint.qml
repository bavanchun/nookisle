import QtQuick
import QtTest
import "../../components"
import "../../qml/Tint.js" as Tint

TestCase {
    id: test
    name: "Tint"
    width: 760
    height: 460
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
        property real positionSeconds: 92
        property string pendingAction: ""
        property string actionError: ""
        property string statusText: ""
        property bool reducedMotion: true
        property bool highContrast: false
        property bool remoteArtwork: false
        property bool autoShow: true
        property bool island: true
        property bool hud: true
        property bool visualizer: true
        property bool tint: true
        property bool lyrics: false
        property string spectrumState: "off"
        property var spectrumLevels: []
        property bool islandPointerActive: false
        property var fileSettings: ({})
        property var shelfItems: []
        property bool sleepArmable: true
        property bool sleepLockVerified: true
        property double sleepDeadline: 0
        property string sleepFailure: ""
        function shelfAdd(uris) { return 0; }
        function armSleepTimer(minutes) { return "ok"; }
        function cancelSleepTimer() {}
        function captureIntent() { return null; }
        function invoke(action, intent, value) { fail("Tint fixture must not dispatch"); }
        function selectSource(token) {}
        function selectAuto() {}
        function retryConnection() {}
        function configure(options) {}
    }
    // Shaped like LyricsSource, in an error state so the view shows its
    // message, Try again and the attribution.
    QtObject {
        id: lyricsFixture
        property bool lyricsEnabled: true
        property string lyricsState: "error"
        property string errorCode: "network"
        property var lines: []
        property int currentIndex: -1
        property var meta: ({ title: "Afterglow" })
        readonly property string displayState: !lyricsEnabled ? "off"
            : lyricsState === "idle" ? (meta ? "loading" : "no-meta") : lyricsState
        function retry() {}
    }
    Component {
        id: legacyContentComponent
        IslandContent {
            tokens: design
            coordinator: facade
            width: design.expandedWidth
            height: design.panelHeight(design.expandedWidth)
            expanded: true
        }
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
    Component {
        id: primaryComponent
        IslandButton {
            tokens: design
            primary: true
            text: "Try again"
        }
    }
    // Artwork fixtures with a known dominant colour, painted from `palette`.
    Component {
        id: coverComponent
        Rectangle {
            id: cover
            property var palette: []
            width: 128
            height: 128
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: cover.palette[0] }
                GradientStop { position: 0.6; color: cover.palette[1] }
                GradientStop { position: 1; color: cover.palette[2] }
            }
            Rectangle {
                x: 24
                y: 30
                width: 64
                height: 64
                radius: 32
                color: cover.palette[3]
            }
            Rectangle {
                x: 60
                y: 70
                width: 52
                height: 40
                radius: 8
                color: cover.palette[4]
                opacity: 0.9
            }
        }
    }
    readonly property var covers: ({
        red: ["#e2402e", "#a3111f", "#2c0609", "#f7c9a6", "#5c0b14"],
        blue: ["#1f4fb8", "#0e225e", "#060b1f", "#5d8df0", "#132f7c"],
        grey: ["#8b8d91", "#5c5e62", "#26272a", "#c8c9cb", "#707379"]
    })
    // What Quickshell's quantizer (depth 3, rescaleSize 48, as in
    // Panel.qml) returned for each saved cover, captured once offscreen:
    // qmltestrunner cannot load the Quickshell module that owns it.
    readonly property var quantized: ({
        red: ["#3f080c", "#5d0b13", "#7f0e19", "#a22025", "#c42a27", "#d3342a", "#e36954", "#f7c9a6"],
        blue: ["#070e29", "#0a1842", "#10286a", "#13307b", "#183b90", "#1c45a3", "#3260c3", "#5d8df0"],
        grey: ["#2e2f33", "#444649", "#636569", "#6d6f75", "#77797e", "#808286", "#9c9da1", "#c8c9cb"]
    })
    function rgb(hex) {
        var c = Qt.color(hex);
        return { r: c.r, g: c.g, b: c.b };
    }
    function hexList(list) {
        return list.map(rgb);
    }
    function near(a, b, tolerance) {
        return Math.abs(a - b) <= tolerance;
    }
    function compareColor(actual, expected, tolerance, message) {
        verify(near(actual.r, expected.r, tolerance) && near(actual.g, expected.g, tolerance)
            && near(actual.b, expected.b, tolerance),
            message + ": " + actual + " vs " + expected);
    }
    function endpoint(artworkPath) {
        return {
            token: { owner: "fixture" },
            trackToken: { id: "track" },
            status: "Playing",
            positionSeconds: 92,
            lengthSeconds: 245,
            volume: 0.64,
            artworkPath: artworkPath || "",
            presentation: {
                title: "Afterglow",
                artists: ["The Test Pressing"],
                album: "Fixtures, Vol. 2",
                hostApp: "Spotify",
                controlScope: "application"
            },
            capabilities: {
                CanControl: true, CanPlay: true, CanPause: true, CanGoPrevious: true,
                CanGoNext: true, CanSeek: true, CanSetPosition: true, CanSetVolume: true
            }
        };
    }
    function init() {
        facade.fileSettings = ({});
        design.theme = ({});
        design.light = false;
        design.highContrast = false;
        design.reducedMotion = true;
        design.tintEnabled = true;
        design.artColor = "transparent";
        facade.selectedEndpoint = endpoint("");
        facade.endpoints = [facade.selectedEndpoint];
        facade.remoteArtwork = false;
        facade.spectrumState = "off";
        facade.spectrumLevels = [];
        facade.positionSeconds = 92;
        facade.lyrics = false;
    }

    function test_luminanceAndContrastMatchWcag() {
        compare(Tint.luminance(rgb("#000000")), 0);
        compare(Tint.luminance(rgb("#ffffff")), 1);
        verify(near(Tint.contrast(rgb("#000000"), rgb("#ffffff")), 21, 1e-9));
        verify(near(Tint.contrast(rgb("#777777"), rgb("#ffffff")), 4.48, 0.01));
        compare(Tint.contrast(rgb("#1db954"), rgb("#15171c")), Tint.contrast(rgb("#15171c"), rgb("#1db954")));
    }
    // The artist tint is lifted to a Rec. 709 luma of at least 0.6 by
    // blending toward white, which keeps its hue; a light colour is kept.
    function test_atLeastLuma() {
        var dark = { r: 0.5, g: 0.1, b: 0.1 };
        var lifted = Tint.atLeastLuma(dark, 0.6);
        verify(Math.abs(Tint.luma709(lifted) - 0.6) < 1e-9);
        compare(Tint.hsl(lifted).h, Tint.hsl(dark).h);
        var light = { r: 0.9, g: 0.9, b: 0.8 };
        compare(Tint.atLeastLuma(light, 0.6), light);
        compare(Tint.atLeastLuma({ r: 0, g: 0, b: 0 }, 0.6), { r: 0.6, g: 0.6, b: 0.6 });
    }
    // Graphics on the notch lift the artwork colour to a vibrance floor: a
    // muddy olive becomes a clear gold with the same hue, a vivid colour in
    // range is kept, and a near-grey stays grey.
    function test_vibrantFloor() {
        var olive = rgb("#8a7a1a");
        var lifted = Tint.hsl(Tint.vibrant(olive));
        verify(near(lifted.h, Tint.hsl(olive).h, 1e-9), "the hue is kept");
        verify(lifted.s >= Tint.VIBRANT_SATURATION - 1e-9, "saturation reaches the floor: " + lifted.s);
        verify(lifted.l >= 0.55 - 1e-9 && lifted.l <= 0.7 + 1e-9, "lightness is in range: " + lifted.l);
        var dark = Tint.hsl(Tint.vibrant(rgb("#301818")));
        verify(near(dark.l, 0.55, 1e-9), "a dark brown is lifted to the lightness floor");
        var pale = Tint.hsl(Tint.vibrant(rgb("#f0e68c")));
        verify(near(pale.l, 0.7, 1e-9), "a pale colour is brought down to the ceiling");
        var vivid = rgb("#e05a44");
        var kept = Tint.vibrant(vivid);
        compareColor(kept, vivid, 1e-9, "an in-range vivid colour is unchanged");
        compare(Tint.vibrant(rgb("#777777")), rgb("#777777"), "grey stays grey");
    }
    // The closed notch's tinted graphics (the play-state glyph and live
    // bars, the progress hairline, the pause glyph) take the notch ink's
    // tint, which a muddy cover lifts to the vibrance floor: an olive cover
    // lights them gold, not brown.
    function test_closedGraphicsTakeTheLiftedTint() {
        design.artColor = "#8a7a1a";
        var surface = createTemporaryObject(surfaceComponent, test);
        var tint = surface.ink.tint;
        var lifted = Tint.hsl({ r: tint.r, g: tint.g, b: tint.b });
        verify(lifted.s >= Tint.VIBRANT_SATURATION - 0.02, "lifted saturation: " + lifted.s);
        verify(lifted.l >= 0.55 - 0.02 && lifted.l <= 0.7 + 0.02, "lifted lightness: " + lifted.l);
        verify(!Qt.colorEqual(tint, design.artColor), "not the raw cover colour");
        var still = findChild(surface, "playStateGlyph");
        verify(still.visible);
        verify(Qt.colorEqual(still.children[0].color, tint), "the play-state glyph");
        verify(Qt.colorEqual(findChild(surface, "progressHairlineFill").color, tint), "the progress hairline");
        facade.selectedEndpoint = Object.assign({}, facade.selectedEndpoint, { status: "Paused" });
        var pause = findChild(surface, "pauseGlyph");
        verify(pause.visible && Qt.colorEqual(pause.children[0].color, tint), "the pause glyph");
    }
    function test_hslRoundTrip() {
        var samples = ["#1db954", "#a3111f", "#1f4fb8", "#f0e68c", "#777777", "#301818"];
        for (var i = 0; i < samples.length; ++i) {
            var c = rgb(samples[i]);
            var v = Tint.hsl(c);
            compareColor(Tint.fromHsl(v.h, v.s, v.l), c, 1e-9, samples[i]);
        }
        verify(near(Tint.hsl(rgb("#301818")).l, 0.141, 0.001));
    }
    function test_pickPrefersVivid() {
        var picked = Tint.pick(hexList(["#000000", "#ffffff", "#808080", "#1db954", "#3a2a2a"]));
        compareColor(picked, rgb("#1db954"), 1e-9, "the vivid green wins");
    }
    function test_pickNullForGreyscale() {
        compare(Tint.pick(hexList(["#000000", "#ffffff", "#808080", "#303030", "#d0d0d0"])), null);
        compare(Tint.pick([]), null);
        compare(Tint.pick(null), null);
    }
    function test_pickFixtureCovers() {
        var red = Tint.pick(hexList(quantized.red));
        var blue = Tint.pick(hexList(quantized.blue));
        verify(red !== null && red.r > red.g && red.r > red.b, "red cover gives a red tint");
        verify(blue !== null && blue.b > blue.r && blue.b > blue.g, "blue cover gives a blue tint");
        compare(Tint.pick(hexList(quantized.grey)), null, "a near-grey cover gives no tint");
    }
    function test_guardKeepsPassingColour() {
        var green = rgb("#1db954");
        verify(Tint.contrast(green, rgb("#15171c")) >= 3);
        compareColor(Tint.guardGraphic(green, rgb("#15171c")), green, 1e-9, "a passing colour is kept");
    }
    function test_guardRaisesDarkTintOnDarkSurface() {
        var source = rgb("#202040");
        var guarded = Tint.guardGraphic(source, rgb("#15171c"));
        verify(guarded !== null);
        verify(Tint.contrast(guarded, rgb("#15171c")) >= 3);
        verify(Tint.hsl(guarded).l > Tint.hsl(source).l, "lightened away from a dark surface");
        verify(near(Tint.hsl(guarded).h, Tint.hsl(source).h, 0.01), "the hue is kept");
    }
    function test_guardLowersLightTintOnLightSurface() {
        var source = rgb("#f0e68c");
        var guarded = Tint.guardGraphic(source, rgb("#f6f7fb"));
        verify(guarded !== null);
        verify(Tint.contrast(guarded, rgb("#f6f7fb")) >= 3);
        verify(Tint.hsl(guarded).l < Tint.hsl(source).l, "darkened away from a light surface");
    }
    function test_guardFallsBackToAccent() {
        // A dark red at about 2.8:1 on mid-grey: the walk runs away from the
        // surface (up, since the surface is darker than 0.4) and tops out
        // near 1.9:1, so no step passes.
        verify(Tint.contrast(rgb("#502828"), rgb("#777777")) < 3);
        compare(Tint.guardGraphic(rgb("#502828"), rgb("#777777")), null);
        design.theme = ({ surface: "#777777", text: "#f6f7fb", accent: "#a9c7ff" });
        design.artColor = "#502828";
        verify(design.tintActive);
        compare(design.tint, design.accent);
    }
    function test_guardTextReachesBodyContrast() {
        var card = rgb("#2a1f22");
        var guarded = Tint.guardText(rgb("#a3111f"), card);
        verify(guarded !== null);
        verify(Tint.contrast(guarded, card) >= 4.5);
        verify(Tint.hsl(guarded).l > Tint.hsl(rgb("#a3111f")).l, "lightened away from a dark card");
        compareColor(Tint.guardText(rgb("#f7c9a6"), card), rgb("#f7c9a6"), 1e-9, "a passing colour is kept");
        compare(Tint.guardText(rgb("#502828"), rgb("#777777")), null);
    }
    // Every art colour a cover can give, on both default themes: the fill
    // reads on the surface and on the tinted card, its label reads at 4.5:1
    // on it, and both keep the art's hue.
    function test_guardFillKeepsFillAndLabelReadable_data() {
        return [
            { tag: "dark", light: false },
            { tag: "light", light: true }
        ];
    }
    function test_guardFillKeepsFillAndLabelReadable(data) {
        design.light = data.light;
        var surface = rgb(design.surface);
        var wash = Tint.cardWash(data.light);
        var arts = ["#e36954", "#5d8df0", "#1db954", "#e2402e", "#1f4fb8", "#f0e68c", "#9b30ff", "#ffcc00", "#b03060", "#2080ff"];
        for (var i = 0; i < arts.length; ++i) {
            var art = rgb(arts[i]);
            var pair = Tint.guardFill(art, surface, wash);
            verify(pair !== null, arts[i] + " gets a fill on " + data.tag);
            verify(Tint.graphicReads(pair.fill, surface, wash), arts[i] + " fill reads on the card on " + data.tag);
            verify(Tint.contrast(pair.label, pair.fill) >= 4.5, arts[i] + " label reads on its fill on " + data.tag);
            verify(near(Tint.hsl(pair.fill).h, Tint.hsl(art).h, 0.01), arts[i] + " fill keeps the hue");
            verify(near(Tint.hsl(pair.label).h, Tint.hsl(art).h, 0.01), arts[i] + " label keeps the hue");
            verify(data.light ? Tint.luminance(pair.label) > Tint.luminance(pair.fill)
                : Tint.luminance(pair.label) < Tint.luminance(pair.fill),
                arts[i] + " label sits on the surface's side on " + data.tag);
        }
        compare(Tint.guardFill(rgb("#502828"), rgb("#777777"), 0.10), null);
    }
    function test_primaryPairFollowsTint() {
        design.artColor = "#e36954";
        verify(!Qt.colorEqual(design.primaryFill, design.accent));
        var fill = rgb(design.primaryFill), label = rgb(design.primaryLabel);
        verify(Tint.contrast(label, fill) >= 4.5);
        verify(Tint.contrast(fill, rgb(design.cardSurface)) >= 3);
        verify(fill.r > fill.g && fill.r > fill.b, "a red cover gives a red fill");
        var text = rgb(design.tintText);
        verify(Tint.contrast(text, rgb(design.cardSurface)) >= 4.5);
        verify(text.r > text.g && text.r > text.b, "a red cover gives red eyebrow text");
    }
    function test_primaryPairIsAccentWithoutTint_data() {
        return [
            { tag: "no artwork", art: "transparent", highContrast: false, tintEnabled: true },
            { tag: "high contrast", art: "#e36954", highContrast: true, tintEnabled: true },
            { tag: "tint off", art: "#e36954", highContrast: false, tintEnabled: false }
        ];
    }
    function test_primaryPairIsAccentWithoutTint(data) {
        design.artColor = data.art;
        design.highContrast = data.highContrast;
        design.tintEnabled = data.tintEnabled;
        compare(design.primaryFill, design.accent);
        compare(design.primaryLabel, design.accentLabel);
        compare(design.tintText, design.accent);
    }
    function test_primaryPairFallsBackToAccent() {
        design.theme = ({ surface: "#777777", text: "#f6f7fb", accent: "#a9c7ff", onAccent: "#172337" });
        design.artColor = "#502828";
        verify(design.tintActive);
        compare(design.primaryFill, design.accent);
        compare(design.primaryLabel, Qt.color("#172337"));
    }
    function test_chargingIsGreenAndReadsOnTheCard_data() {
        return [
            { tag: "dark", light: false, art: "transparent", highContrast: false },
            { tag: "light", light: true, art: "transparent", highContrast: false },
            { tag: "dark tinted", light: false, art: "#e36954", highContrast: false },
            { tag: "light tinted", light: true, art: "#1db954", highContrast: false },
            { tag: "high contrast", light: false, art: "#e36954", highContrast: true }
        ];
    }
    function test_chargingIsGreenAndReadsOnTheCard(data) {
        design.light = data.light;
        design.highContrast = data.highContrast;
        design.artColor = data.art;
        var green = rgb(design.charging);
        verify(Tint.contrast(green, rgb(design.cardSurface)) >= 4.5, "reads on the card");
        verify(green.g > green.r && green.g > green.b, "stays green");
    }
    function test_chargingFallsBackToText() {
        design.theme = ({ surface: "#3a8a4a", text: "#ffffff" });
        compare(Tint.guardText(rgb(design.chargingBase), rgb(design.cardSurface)), null);
        compare(design.charging, design.text);
    }
    // A button's label: its text, or a header tab's icon.
    function buttonLabel(button) {
        for (var i = 0; i < button.contentItem.children.length; ++i)
            if (button.contentItem.children[i].text === button.text)
                return button.contentItem.children[i];
        return findChild(button, "tabIcon");
    }
    function labelColor(label) {
        return label.ink !== undefined ? label.ink : label.color;
    }
    // The play button, the selected view and the switch share the pair;
    // the focus ring around the switcher stays on the accent.
    // On the notch the artwork colour reaches only graphics: the tabs, the
    // title, the artist, the filled controls and the card stay neutral,
    // while the legacy panel keeps its tinted chrome.
    function test_notchChromeStaysNeutral() {
        design.artColor = "#e36954";
        verify(design.fillPair !== null, "the legacy tokens tint their fills");
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var ink = surface.ink;
        var capsule = findChild(surface, "tabCapsule").color;
        verify(Qt.colorEqual(Qt.rgba(capsule.r, capsule.g, capsule.b, 1), ink.text) && capsule.a < 0.3,
            "the selected tab's capsule is a faint wash of the ink");
        compare(labelColor(buttonLabel(findChild(surface, "viewHomeButton"))), ink.text, "the selected tab's icon is ink");
        compareColor(labelColor(buttonLabel(findChild(surface, "viewShelfButton"))), ink.secondary, 1 / 255, "the other tab is muted");
        compare(findChild(surface, "trackTitle").color, ink.text);
        compareColor(findChild(surface, "trackArtist").color, ink.secondary, 1 / 255, "the artist is secondary ink");
        compare(ink.primaryFill, ink.text, "filled controls are ink");
        compare(ink.primaryLabel, design.notchColor);
        compare(ink.cardSurface, design.notchColor, "no wash into the black");
        compare(ink.tintText, ink.text);
        compareColor(findChild(surface, "intentSliderFill").color, Qt.color("#ffffff"), 1 / 255,
            "the scrubber starts white");
        compare(findChild(surface, "keyFocusRing").border.color, design.accent);
        verify(ink.tint !== ink.accent, "graphics still take the tint");
    }
    // The graphics' tint is the artwork colour at its vibrance floor, still
    // guarded to read on black.
    function test_notchTintIsVibrant() {
        design.artColor = "#8a7a1a";
        var surface = createTemporaryObject(surfaceComponent, test);
        var lifted = Tint.hsl(surface.ink.rgb(surface.ink.tint));
        verify(lifted.s >= Tint.VIBRANT_SATURATION - 0.01, "the olive tint is saturated: " + lifted.s);
        verify(lifted.l >= 0.55 - 0.01, "and lifted out of the mud: " + lifted.l);
        verify(Tint.contrast(surface.ink.rgb(surface.ink.tint), { r: 0, g: 0, b: 0 }) >= 3, "and reads on black");
    }
    function test_cardAlphaKeepsTextContrast_data() {
        return [
            { tag: "dark", light: false, theme: {} },
            { tag: "light", light: true, theme: {} },
            { tag: "mid-grey", light: false, theme: { surface: "#777777", text: "#f6f7fb", accent: "#a9c7ff" } }
        ];
    }
    function test_cardAlphaKeepsTextContrast(data) {
        design.light = data.light;
        design.theme = data.theme;
        var arts = ["#1db954", "#e2402e", "#1f4fb8", "#f0e68c", "#9b30ff", "#ffcc00"];
        for (var i = 0; i < arts.length; ++i) {
            design.artColor = arts[i];
            var card = rgb(design.cardSurface), surface = rgb(design.surface);
            var text = rgb(design.text), secondary = rgb(design.secondary);
            verify(Tint.contrast(text, card) >= Math.min(4.5, Tint.contrast(text, surface)),
                arts[i] + " keeps text readable on " + data.tag);
            verify(Tint.contrast(secondary, card) >= Math.min(3, Tint.contrast(secondary, surface)),
                arts[i] + " keeps secondary text readable on " + data.tag);
            verify(Tint.contrast(rgb(design.tint), surface) >= 3 || design.tint === design.accent,
                arts[i] + " graphic tint reaches 3:1 or falls back on " + data.tag);
        }
    }
    // The bars, hairline and fills are drawn on the tinted card, not on the
    // plain surface. #1f4fb8 on the dark theme and #ffcc00 and #f0e68c on the
    // light one reach 3:1 against the surface but not against the card they
    // tint, so they pin the wash into the guard.
    function test_graphicTintReadsOnTheTintedCard_data() {
        return [
            { tag: "dark", light: false },
            { tag: "light", light: true }
        ];
    }
    function test_graphicTintReadsOnTheTintedCard(data) {
        design.light = data.light;
        design.theme = ({});
        var arts = ["#1f4fb8", "#ffcc00", "#f0e68c", "#1db954", "#e2402e", "#9b30ff", "#b03060", "#3060b0", "#2080ff"];
        for (var i = 0; i < arts.length; ++i) {
            design.artColor = arts[i];
            verify(design.tintActive);
            if (Qt.colorEqual(design.tint, design.accent))
                continue;
            var tint = rgb(design.tint);
            verify(Tint.contrast(tint, rgb(design.surface)) >= 3, arts[i] + " reads on the surface on " + data.tag);
            verify(Tint.contrast(tint, rgb(design.cardSurface)) >= 3, arts[i] + " reads on the tinted card on " + data.tag);
        }
    }
    function test_cardIsTintedOnDefaultThemes() {
        design.artColor = "#e2402e";
        compare(design.cardTintAlpha, 0.10);
        verify(design.cardSurface !== design.surface);
        design.light = true;
        compare(design.cardTintAlpha, 0.07);
    }
    function test_highContrastDisablesTint() {
        design.artColor = "#1db954";
        design.highContrast = true;
        verify(!design.tintActive);
        compare(design.tint, design.accent);
        compare(design.cardSurface, design.surface);
        verify(!design.glow);
    }
    function test_tintOffDisablesTint() {
        design.artColor = "#1db954";
        design.tintEnabled = false;
        compare(design.tint, design.accent);
        compare(design.cardSurface, design.surface);
        verify(!design.glow);
    }
    function test_noArtworkIsAccent() {
        compare(design.artColor.a, 0);
        compare(design.tint, design.accent);
        compare(design.cardSurface, design.surface);
        verify(!design.glow);
    }
    // A property named onAccent parses as a signal handler and never takes
    // its binding, which left every primary label black.
    function test_primaryLabelTakesItsThemeColour() {
        design.light = true;
        compare(design.accentLabel, Qt.color("#f6f7fb"));
        design.light = false;
        compare(design.accentLabel, Qt.color("#172337"));
        design.theme = ({ accent: "#7daea3", onAccent: "#282828" });
        compare(design.accentLabel, Qt.color("#282828"));
        var button = createTemporaryObject(primaryComponent, test);
        var label = buttonLabel(button);
        verify(label);
        compare(label.color, Qt.color("#282828"));
    }
    // The notch is solid black whatever the artwork: the tint reaches only
    // text, sliders, bars and the glow.
    function test_islandNotchIgnoresTheTint() {
        design.artColor = "#1db954";
        verify(design.cardSurface !== design.notchColor, "the tint is active");
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        var shape = findChild(surface, "notchShape");
        waitForRendering(card);
        compare(shape.fillColor, design.notchColor);
        var pixel = grabImage(card).pixel(card.width / 2 - 70, 4);
        compareColor(pixel, design.notchColor, 2 / 255, "the closed notch is the notch colour");
        surface.expandTo("home");
        waitForRendering(card);
        pixel = grabImage(card).pixel(shape.bodyRight - 12, card.height - 6);
        compareColor(pixel, design.notchColor, 2 / 255, "and so is the open notch");
    }
    // The lightest rendered pixel inside an item, read from a grab of the
    // whole notch: a glyph's core, which the renderer draws at the text's
    // own colour.
    function brightest(card, item) {
        var image = grabImage(card);
        var box = item.mapToItem(card, 0, 0, item.width, item.height);
        var best = { r: 0, g: 0, b: 0 };
        for (var x = Math.max(0, Math.floor(box.x)); x < Math.min(card.width, box.x + box.width); ++x)
            for (var y = Math.max(0, Math.floor(box.y)); y < Math.min(card.height, box.y + box.height); ++y) {
                var px = image.pixel(x, y);
                if (Tint.luminance(px) > Tint.luminance(best))
                    best = { r: px.r, g: px.g, b: px.b };
            }
        return best;
    }
    function verifyReadsOnNotch(card, item, minimum, what) {
        verify(item && item.visible, what + " shows");
        var ink = brightest(card, item);
        var ratio = Tint.contrast(ink, { r: 0, g: 0, b: 0 });
        verify(ratio >= minimum, what + " reads on the black notch: " + ratio.toFixed(2) + ":1");
    }
    // A filled button's label against its own fill.
    function verifyLabelOnFill(button, what, fill) {
        var ratio = Tint.contrast(design.rgb(labelColor(buttonLabel(button))), design.rgb(fill || button.background.color));
        verify(ratio >= 4.5, what + " reads on its fill: " + ratio.toFixed(2) + ":1");
    }
    // A light theme's own text and accent are dark, and the notch is black
    // in every theme: everything drawn over it is rendered with the island's
    // notch-based ink, while the legacy panel keeps the theme colours.
    function test_lightThemeReadsOnTheNotch_data() {
        return [
            { tag: "default-light", theme: ({}) },
            { tag: "host-light", theme: ({ surface: "#fafafa", text: "#202124", accent: "#1a4fd0", onAccent: "#ffffff",
                stroke: "#d0d0d0", error: "#b3261e" }) }
        ];
    }
    function test_lightThemeReadsOnTheNotch(data) {
        design.light = true;
        design.theme = data.theme;
        verify(Tint.contrast(design.rgb(design.text), { r: 0, g: 0, b: 0 }) < 4.5, "the theme's text is dark");
        var surface = createTemporaryObject(surfaceComponent, test);
        var card = findChild(surface, "islandCard");
        waitForRendering(surface);
        surface.hud.show("volume", 0.5, false);
        waitForRendering(surface);
        verifyReadsOnNotch(card, findChild(findChild(surface, "hudInline"), "hudIcon"), 3, "the closed HUD icon");
        surface.hud.active = false;
        surface.peekKind = "track";
        surface.peekActive = true;
        waitForRendering(surface);
        verifyReadsOnNotch(card, findChild(surface, "peekTitle"), 4.5, "the peek title");
        surface.peekActive = false;
        surface.expandTo("home");
        waitForRendering(surface);
        verifyReadsOnNotch(card, findChild(surface, "trackTitle"), 4.5, "the player title");
        verifyReadsOnNotch(card, buttonLabel(findChild(surface, "viewShelfButton")), 4.5, "the switcher label");
        var wash = findChild(surface, "tabCapsule").color;
        verifyLabelOnFill(findChild(surface, "viewHomeButton"), "the selected tab label",
            Qt.rgba(wash.r * wash.a, wash.g * wash.a, wash.b * wash.a, 1));
        compare(findChild(surface, "keyFocusRing").border.color, surface.ink.accent);
        verify(Tint.contrast(surface.ink.rgb(surface.ink.accent), { r: 0, g: 0, b: 0 }) >= 3, "the focus ring reads");
        facade.lyrics = true;
        surface.lyricsSource = lyricsFixture;
        surface.view = "lyrics";
        var loader = findChild(surface, "lyricsViewLoader");
        tryVerify(function () { return loader.item !== null; }, 1000, "the Lyrics view loads");
        waitForRendering(surface);
        verifyReadsOnNotch(card, findChild(loader.item, "lyricsMessageTitle"), 4.5, "the lyrics message");
        verifyReadsOnNotch(card, findChild(loader.item, "lyricsAttribution"), 3, "the lyrics attribution");
        verifyLabelOnFill(findChild(loader.item, "lyricsRetry"), "the Try again label");
        verify(Tint.contrast(surface.ink.rgb(findChild(loader.item, "lyricsRetry").background.color), { r: 0, g: 0, b: 0 }) >= 3,
            "the Try again fill reads on the notch");
        surface.view = "shelf";
        tryVerify(function () { return findChild(surface, "shelfViewLoader").item !== null; }, 1000);
        waitForRendering(surface);
        verifyReadsOnNotch(card, findChild(surface, "shelfEmptyState"), 3, "the empty shelf hint");
        // The legacy panel is untouched: it keeps the theme's own colours.
        var legacy = createTemporaryObject(legacyContentComponent, test);
        compare(findChild(legacy, "trackTitle").color, design.text);
    }
    // A dark theme whose colours already read on black keeps them.
    // The island's text takes the first installed of Inter, Roboto and Noto
    // Sans, or fontconfig's sans-serif, with tabular figures for times;
    // uiFont "theme" keeps the theme's font.
    function test_islandFontFollowsTheSetting() {
        design.theme = ({ fontFamily: "JetBrainsMono Nerd Font" });
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.uiFontFamilies, ["Inter", "Roboto", "Noto Sans"]);
        compare(surface.preferredSans(["DejaVu Sans", "Noto Sans", "Roboto"]), "Roboto", "in preference order");
        compare(surface.preferredSans(["Inter", "Roboto"]), "Inter");
        compare(surface.preferredSans(["Noto Sans"]), "Noto Sans");
        compare(surface.preferredSans(["DejaVu Sans"]), "sans-serif", "none installed, fontconfig's default");
        var expected = surface.preferredSans(Qt.fontFamilies());
        if (Qt.fontFamilies().indexOf("Roboto") >= 0 && Qt.fontFamilies().indexOf("Inter") < 0)
            compare(expected, "Roboto", "this machine has Roboto but no Inter");
        compare(surface.ink.fontFamily, expected);
        surface.expandTo("home");
        var elapsed = findChild(surface, "elapsedTime");
        compare(elapsed.font.family, expected);
        compare(elapsed.font.features["tnum"], 1, "times use tabular figures");
        surface.view = "shelf";
        tryVerify(function () { return findChild(surface, "shelfViewLoader").item !== null; }, 1000);
        var empty = findChild(surface, "shelfEmptyState");
        compare(empty.children[1].font.family, expected, "the shelf takes the island font too");
        surface.view = "home";
        facade.fileSettings = ({ uiFont: "theme" });
        compare(surface.ink.fontFamily, "JetBrainsMono Nerd Font");
        compare(elapsed.font.family, "JetBrainsMono Nerd Font");
        facade.fileSettings = ({});
        design.theme = ({});
    }
    // Text is always the neutral notch ink; an accent that reads on black
    // is kept.
    function test_darkThemeKeepsItsAccent() {
        design.theme = ({ text: "#e8e8ff", accent: "#ffb86c" });
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(surface.ink.text, design.notchInk);
        compare(surface.ink.accent, design.accent);
        compare(surface.ink.surface, design.notchColor);
    }
    function test_tintedControlsFollowTint() {
        design.artColor = "#e2402e";
        facade.spectrumState = "running";
        facade.spectrumLevels = [38, 72, 91, 80, 64, 70, 55, 47, 58, 41, 33, 39];
        var surface = createTemporaryObject(surfaceComponent, test);
        compare(findChild(surface, "progressHairlineFill").color, surface.ink.tint);
        compare(findChild(surface, "spectrumBar2").color, surface.ink.tint);
        design.artColor = "transparent";
        compare(findChild(surface, "progressHairlineFill").color, design.accent);
    }
    function test_glowRingsConcentricAndGated() {
        var e = endpoint("");
        facade.selectedEndpoint = e;
        var surface = createTemporaryObject(surfaceComponent, test);
        surface.expandTo("home");
        var glow = findChild(surface, "artGlow");
        verify(glow);
        verify(!glow.visible, "no glow without artwork");
        design.artColor = "#1f4fb8";
        verify(glow.visible);
        var rings = design.glowRings;
        for (var i = 0; i < rings.length; ++i) {
            var ring = findChild(glow, "artGlowRing" + i);
            compare(ring.x, -rings[i].offset);
            compare(ring.y, -rings[i].offset);
            compare(ring.width, glow.width + 2 * rings[i].offset);
            compare(ring.height, glow.height + 2 * rings[i].offset);
            compare(ring.radius, glow.radius + rings[i].offset);
            verify(near(ring.color.a, rings[i].alpha, 1 / 255));
        }
        design.highContrast = true;
        verify(!glow.visible, "high contrast drops the glow");
    }
    function test_heroArtShowsWhenPillHoldsSameImage() {
        // The pill already holds the cover when the card first expands, so
        // the hero's Canvas finds it cached and gets no imageLoaded signal.
        facade.remoteArtwork = true;
        facade.selectedEndpoint = endpoint(saveCover("blue"));
        var surface = createTemporaryObject(surfaceComponent, test);
        tryCompare(findChild(findChild(surface, "leftWing"), "artworkRaster"), "ready", true);
        surface.expandTo("home");
        tryCompare(findChild(findChild(surface, "heroArtwork"), "artworkRaster"), "ready", true, 1000);
    }

    Component {
        id: artworkComponent
        Artwork {
            width: 90
            height: 90
            tokens: design
        }
    }
    // A new cover fades in over the old one, which stays drawn until the
    // fade ends: a track change never flashes the placeholder. Clearing
    // the artwork drops the old cover at once.
    function test_coverCrossFades() {
        var red = saveCover("red");
        var blue = saveCover("blue");
        design.reducedMotion = false;
        var art = createTemporaryObject(artworkComponent, test);
        var raster = findChild(art, "artworkRaster");
        var previous = findChild(art, "artworkPrevious");
        var placeholder = findChild(art, "artworkPlaceholder");
        art.artworkPath = red;
        tryCompare(raster, "ready", true, 2000);
        tryCompare(art, "fadeRunning", false, 1000);
        verify(!previous.shown);
        art.artworkPath = blue;
        verify(previous.shown, "the old cover holds while the new one loads");
        compare(previous.path, "file://" + red);
        verify(!placeholder.visible, "no placeholder between covers");
        tryCompare(raster, "ready", true, 2000);
        tryCompare(previous, "shown", false, 1000, "released once the new cover has faded in");
        art.artworkPath = "";
        verify(!previous.shown);
        verify(placeholder.visible, "no artwork, the placeholder");
    }
    // Skipping again while the next cover is still loading keeps the last
    // cover that was on screen until a successor is paintable.
    function test_rapidSkipsKeepTheLastShownCover() {
        var red = saveCover("red");
        var blue = saveCover("blue");
        var grey = saveCover("grey");
        design.reducedMotion = false;
        var art = createTemporaryObject(artworkComponent, test);
        var raster = findChild(art, "artworkRaster");
        var previous = findChild(art, "artworkPrevious");
        var placeholder = findChild(art, "artworkPlaceholder");
        art.artworkPath = red;
        tryCompare(raster, "ready", true, 2000);
        tryCompare(art, "fadeRunning", false, 1000);
        art.artworkPath = blue;
        verify(!raster.ready, "the second cover has not loaded yet");
        art.artworkPath = grey;
        verify(previous.shown, "the first cover still holds");
        compare(previous.path, "file://" + red, "it is the last one displayed");
        verify(!placeholder.visible, "no placeholder flash");
        tryCompare(raster, "ready", true, 2000);
        compare(raster.loadedPath, "file://" + grey, "the latest cover wins");
        tryCompare(previous, "shown", false, 1000);
    }
    // Offscreen previews: the expanded card and the live pill for each cover,
    // plus the light theme with the red cover.
    function saveCover(name) {
        var cover = createTemporaryObject(coverComponent, test, { palette: covers[name] });
        waitForRendering(cover);
        var path = Qt.resolvedUrl("../../build/ui-preview/tint-cover-" + name + ".png").toString().slice(7);
        grabImage(cover).save(path);
        cover.destroy();
        return path;
    }
    function preview(name, light, suffix) {
        var path = saveCover(name);
        design.light = light;
        var picked = Tint.pick(hexList(quantized[name]));
        design.artColor = picked ? Qt.rgba(picked.r, picked.g, picked.b, 1) : "transparent";
        facade.remoteArtwork = true;
        facade.selectedEndpoint = endpoint(path);
        facade.endpoints = [facade.selectedEndpoint];
        facade.spectrumState = "running";
        facade.spectrumLevels = [38, 72, 91, 80, 64, 70, 55, 47, 58, 41, 33, 39];
        var surface = createTemporaryObject(surfaceComponent, test);
        tryCompare(findChild(surface, "artworkRaster"), "ready", true);
        wait(50);
        var pill = findChild(surface, "islandCard");
        grabImage(pill).save(Qt.resolvedUrl("../../build/ui-preview/island-pill-tinted" + suffix + ".png").toString().slice(7));
        surface.expandTo("home");
        tryCompare(findChild(findChild(surface, "heroArtwork"), "artworkRaster"), "ready", true);
        wait(250);
        wait(50);
        grabImage(surface).save(Qt.resolvedUrl("../../build/ui-preview/island-tinted" + suffix + ".png").toString().slice(7));
    }
    function test_previewRed() { preview("red", false, ""); }
    function test_previewBlue() { preview("blue", false, "-blue"); }
    function test_previewGrey() { preview("grey", false, "-grey"); }
    function test_previewLight() { preview("red", true, "-light"); }
}
