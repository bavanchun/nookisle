pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Tint.js" as Tint

QtObject {
    property var theme: ({})
    property bool light: false
    property bool highContrast: false
    property bool reducedMotion: false
    property string customAccent: ""
    readonly property color baseSurface: theme.surface || (light ? "#f6f7fb" : "#15171c")
    readonly property color surface: highContrast ? Qt.rgba(baseSurface.r, baseSurface.g, baseSurface.b, 1) : baseSurface
    readonly property color text: theme.text || (light ? "#171a22" : "#f6f7fb")
    readonly property color secondary: highContrast ? text : Qt.tint(surface, Qt.rgba(text.r, text.g, text.b, 0.72))
    readonly property color accent: customAccent !== "" ? customAccent : theme.accent || (light ? "#2456ac" : "#a9c7ff")
    // The label on an accent fill. Not named onAccent: QML reads a property
    // whose name starts with "on" and a capital as a signal handler, so that
    // name never took its binding and every primary label drew black.
    readonly property color accentLabel: customAccent !== ""
        ? (Tint.contrast(rgb(accent), { r: 0, g: 0, b: 0 }) >= 4.5 ? "#000000" : "#ffffff")
        : theme.onAccent || (light ? "#f6f7fb" : "#172337")
    readonly property color stroke: highContrast ? text : theme.stroke || Qt.rgba(text.r, text.g, text.b, 0.16)
    readonly property color hover: Qt.rgba(text.r, text.g, text.b, 0.10)
    // Elevation scale. Depth here is tint delta plus a hairline, which every
    // renderer draws. Shadows and blur are allowed only behind gpuEffects
    // (below), with this scale as their software fallback.
    // High contrast forces every one of these opaque. Built on the card
    // colour, so raised rows and slider tracks carry the artwork tint with
    // the card instead of reading as grey patches on it; without a tint the
    // card colour is the surface itself.
    readonly property color surfaceRaised: highContrast
        ? Qt.tint(surface, Qt.rgba(text.r, text.g, text.b, 0.14))
        : Qt.tint(cardSurface, Qt.rgba(text.r, text.g, text.b, 0.07))
    readonly property color surfaceSunken: highContrast
        ? Qt.tint(surface, Qt.rgba(text.r, text.g, text.b, 0.22))
        : Qt.tint(cardSurface, Qt.rgba(text.r, text.g, text.b, 0.12))
    readonly property color hairline: highContrast ? stroke : Qt.rgba(text.r, text.g, text.b, 0.12)
    readonly property int rowRadius: Math.min(expandedRadius, gap)
    readonly property color track: Qt.rgba(text.r, text.g, text.b, 0.24)
    readonly property color error: theme.error || (light ? "#9b2438" : "#ffb6bd")
    readonly property string fontFamily: theme.fontFamily || "monospace"
    // How text is rasterised, set explicitly on every island text. Native
    // rendering draws grayscale glyphs on the live compositor. Qt's own
    // distance-field rendering, which Quickshell uses when a Text sets
    // nothing, draws subpixel glyphs whose blue and orange fringes show on
    // the black notch.
    property int textRenderType: Text.NativeRendering
    // OpenType features for running numbers (times, the clock): tabular
    // figures, so a ticking time keeps its width in a proportional face.
    readonly property var numberFeatures: ({ "tnum": 1 })
    readonly property int compactWidth: 280
    readonly property int compactHeight: 40
    readonly property int expandedWidth: 384
    readonly property int expandedHeight: 320
    readonly property int compactRadius: 20
    readonly property int expandedRadius: theme.radius !== undefined ? theme.radius : 12
    readonly property int small: 4
    readonly property int gap: 8
    readonly property int medium: 12
    readonly property int inset: 16
    readonly property int target: 32
    readonly property int primaryTarget: 40
    readonly property int artSize: 48
    readonly property int heroArtSize: 64
    readonly property int rowHeight: 48
    // Band heights for the expanded player. Each band is a fixed-height wrapper
    // so the window height stays a pure function of width: no text metric and no
    // visible/invisible child may reach the layout's implicit height.
    readonly property int bandHeader: heroArtSize + inset + gap
    readonly property int bandProgress: artSize
    // Two lines at the largest shell body font. Sizing this from the live font
    // would make the window height depend on the theme; sizing it for the worst
    // case keeps panelHeight() a pure function of width.
    readonly property int bandStatus: 40
    readonly property int bandFooter: target
    readonly property int bandSpacing: small
    function bandTransport(isNarrow) {
        return primaryTarget + inset + gap * 2 + (isNarrow ? rowHeight : 0)
    }
    // The single height authority. Panel.qml binds its window to this instead of
    // recomputing the narrow threshold, so the two arithmetics cannot drift.
    function panelHeight(w) {
        return inset * 2 + bandHeader + bandProgress + bandTransport(w < 320)
            + bandStatus + bandFooter + bandSpacing * 4
    }
    readonly property int titleSize: theme.titleSize || 14
    readonly property int bodySize: theme.bodySize || 12
    readonly property int captionSize: theme.captionSize || 11
    readonly property int focusWidth: 2
    // The legacy panel's own morph. The island reads island*Duration instead
    // (below), so island:false keeps this timing exactly as it was.
    readonly property int expandDuration: reducedMotion ? 0 : 220
    readonly property int collapseDuration: reducedMotion ? 0 : 180
    readonly property int feedbackDuration: reducedMotion ? 0 : 100
    // The collapsed pill: a fixed-width notch that never depends on title
    // length, so the window it lives in never resizes on metadata change.
    readonly property int pillWidth: 240
    readonly property int pillMinHeight: 24
    // The switcher row between the pill and the expanded content.
    readonly property int bandSwitcher: target + small
    // The single window-height authority for island mode, mirroring
    // panelHeight() for the legacy compact/expanded window.
    function islandHeight(w) {
        return bandSwitcher + panelHeight(w);
    }
    // Spare window height below the open notch, so the open spring's
    // overshoot never gets clipped by the layer-shell window it is drawn into.
    readonly property int morphSlack: 10
    function islandWindowHeight(w) { return islandHeight(w) + morphSlack; }
    // Island-only morph: boring.notch's open and close springs as SwiftUI
    // (response s, damping fraction) pairs, played through qml/Motion.js.
    // The peek bloom uses the same pair. Only IslandSurface reads these,
    // never the legacy panel.
    readonly property real openResponse: 0.42
    readonly property real openDamping: 0.8
    readonly property real closeResponse: 0.45
    readonly property real closeDamping: 1.0
    readonly property int openDuration: reducedMotion ? 0 : 420
    readonly property int closeDuration: reducedMotion ? 0 : 450
    // Pill layout: art on the left, a fixed-width spectrum slot on the right.
    readonly property int pillArtSize: 18
    readonly property int pillArtRadius: 5
    readonly property int spectrumBands: 12
    readonly property int spectrumBarWidth: 2
    readonly property int spectrumBarGap: 2
    readonly property int spectrumWidth: spectrumBands * spectrumBarWidth + (spectrumBands - 1) * spectrumBarGap
    readonly property int spectrumMinBar: 2
    readonly property int hairlineHeight: 2
    // How long the spectrum takes to fall flat after a pause.
    readonly property int spectrumDecayDuration: reducedMotion ? 0 : 300
    // Track and power peeks, bloomed from the pill.
    readonly property int peekWidth: 300
    readonly property int peekHeight: 64
    readonly property int peekRadius: 22
    readonly property int peekArtSize: 44
    readonly property int peekArtRadius: 10
    // The ease between a track peek and a power peek; the bloom itself
    // rides the open and close springs above.
    readonly property int peekInDuration: reducedMotion ? 0 : 280
    // Intent timings: the peek is meant to be seen, so reduced motion does not
    // shorten it, the same rule as the hover dwell and leave grace settings.
    readonly property int trackPeekDuration: 3000
    readonly property int powerPeekDuration: 2500
    readonly property int devicePeekDuration: 2500
    readonly property int timerDonePeekDuration: 6000
    readonly property int capturePeekDuration: 4000
    // Concentric rings around the hero/pill art, drawn as plain rounded
    // rectangles at falling alpha, so the software renderer draws them.
    readonly property var glowRings: [
        { offset: 3, alpha: 0.20 },
        { offset: 6, alpha: 0.10 },
        { offset: 9, alpha: 0.05 }
    ]
    // Expanded content cross-fade and scale, driven by the card's clamped
    // expansion fraction.
    readonly property real contentFadeStart: 0.35
    readonly property real contentScaleFrom: 0.96
    // The open notch's content grows from 80 % about its top, and with GPU
    // effects it also sharpens from this blur radius, as boring.notch does.
    readonly property real openScaleFrom: 0.8
    readonly property int entranceBlur: 30
    readonly property real pillFadeEnd: 0.4
    readonly property int tintDuration: reducedMotion ? 0 : 400
    // The header's tab capsule slides to the selected tab.
    readonly property int tabDuration: reducedMotion ? 0 : 350
    readonly property int lyricLineDuration: reducedMotion ? 0 : 180
    readonly property int lyricCurrentSize: titleSize + 2
    // How long Home waits before it says a lyrics lookup is running, so a
    // quick answer never flashes status text. An intent timing like
    // hoverDwell: reduced motion does not shorten it. Writable so the tests
    // can shorten it.
    property int lyricRevealDelay: 1000
    // Artwork tint. Panel.qml writes artColor from the artwork's most vivid
    // colour; transparent means no artwork, and then every derived colour is
    // exactly the plain theme. The guards run against the live palette,
    // because an Omarchy theme can change underneath at any time.
    property color artColor: "transparent"
    property bool tintEnabled: true
    // The notch's rule: text, tabs and filled controls stay neutral, and the
    // artwork colour reaches only graphics (the spectrum, the slider, the
    // hairline and the glow), lifted to a vibrance floor so a muddy cover
    // still lights them up. The legacy panel keeps its tinted chrome.
    property bool neutralChrome: false
    readonly property bool tintActive: tintEnabled && !highContrast && artColor.a >= 1
    // Bars, the hairline, slider fills and the glow: 3:1 against the surface
    // and against the card washed with the tint, which is what they are drawn
    // on, or the accent when the art colour cannot get there.
    readonly property color tint: {
        if (!tintActive)
            return accent;
        var base = neutralChrome ? Tint.vibrant(rgb(artColor)) : rgb(artColor);
        var guarded = Tint.guardGraphic(base, rgb(surface), neutralChrome ? 0 : Tint.cardWash(light));
        return guarded ? Qt.rgba(guarded.r, guarded.g, guarded.b, 1) : accent;
    }
    // Filled controls (primary buttons, the selected view, the shelf count,
    // a switch that is on) take the artwork colour too, so nothing on a
    // tinted card stays in the theme accent but the focus rings. The fill
    // reads as a graphic on the card and its label, a deep or pale shade of
    // the same hue, reads at 4.5:1 on it; otherwise the accent pair stays.
    readonly property var fillPair: tintActive && !neutralChrome ? Tint.guardFill(rgb(artColor), rgb(surface), Tint.cardWash(light)) : null
    readonly property color primaryFill: neutralChrome ? text
        : fillPair ? Qt.rgba(fillPair.fill.r, fillPair.fill.g, fillPair.fill.b, 1) : accent
    readonly property color primaryLabel: neutralChrome ? surface
        : fillPair ? Qt.rgba(fillPair.label.r, fillPair.label.g, fillPair.label.b, 1) : accentLabel
    // Accent-coloured text on the card (the source eyebrow): the artwork
    // colour at 4.5:1 on the card it sits on, or the accent.
    readonly property color tintText: {
        if (neutralChrome)
            return text;
        if (!tintActive)
            return accent;
        var guarded = Tint.guardText(rgb(artColor), rgb(cardSurface));
        return guarded ? Qt.rgba(guarded.r, guarded.g, guarded.b, 1) : accent;
    }
    // Plugged in, charging or full: a green that reads at 4.5:1 on the card,
    // so the power peek's level bar and its percentage both read; the
    // theme's text colour when no lightness step gets there.
    readonly property color chargingBase: light ? "#1a7f37" : "#5fd38d"
    readonly property color charging: {
        var guarded = Tint.guardText(rgb(chargingBase), rgb(cardSurface));
        return guarded ? Qt.rgba(guarded.r, guarded.g, guarded.b, 1) : text;
    }
    // A faint wash of the tint into the card, never at the cost of text.
    readonly property real cardTintAlpha: tintActive && !neutralChrome ? Tint.cardAlpha(rgb(tint), rgb(surface), rgb(text), rgb(secondary), light) : 0
    readonly property color cardSurface: cardTintAlpha > 0 ? Qt.tint(surface, Qt.rgba(tint.r, tint.g, tint.b, cardTintAlpha)) : surface
    readonly property bool glow: tintActive
    function rgb(c) { return { r: c.r, g: c.g, b: c.b }; }
    // The HUD intent timing. A deliberate pause, not decorative motion, so
    // reduced motion must not shorten it. The hover dwell and leave grace
    // are settings (hoverDwell, leaveGrace in qml/Settings.js).
    readonly property int hudDuration: 1500
    // Whether GPU effects (MultiEffect, RectangularShadow) may draw. The host
    // sets it from the window's scene-graph API; it stays false under the
    // software renderer and offscreen, where the island keeps hairline edges
    // and the ring glow.
    property bool gpuEffects: false
    // The notch: a solid black shape with concave top flares over the bar,
    // opening into a wide panel. Sizes in px.
    readonly property color notchColor: "#000000"
    // Ink stays light on the owner's black notch even under a light host theme.
    readonly property color notchInk: "#f6f7fb"
    readonly property color notchMutedInk: "#a4a7ad"
    readonly property color notchTrack: "#484848"
    readonly property color notchStroke: Qt.rgba(1, 1, 1, 0.10)
    readonly property color notchAccent: {
        var guarded = Tint.guardGraphic(rgb(tint), rgb(notchColor), 0);
        return guarded ? Qt.rgba(guarded.r, guarded.g, guarded.b, 1) : notchInk;
    }
    readonly property int openWidth: 640
    readonly property int openHeight: 190
    // Room around the open notch for its shadow.
    readonly property int shadowPad: 20
    // Concave top flare radius, closed and open.
    readonly property int flareClosed: 6
    readonly property int flareOpen: 19
    readonly property int bottomRadiusClosed: 14
    readonly property int bottomRadiusOpen: 24
    // The GPU shadow under the notch body: black at 70 %, a 6 px blur,
    // dropped 2 px. Without GPU effects the hairline edge stands in.
    readonly property color shadowColor: Qt.rgba(0, 0, 0, 0.7)
    readonly property int shadowBlur: 6
    readonly property int shadowOffset: 2
    // The island's fixed layer window: the open notch plus room for its
    // shadow on both sides and below, and the spring's overshoot. Never
    // wider than the screen (availableWidth is the screen less a gap on
    // each side). The window never resizes; the notch morphs inside it.
    function notchWindowWidth(availableWidth) {
        var full = openWidth + 2 * shadowPad;
        return availableWidth === undefined ? full : Math.min(full, availableWidth + 2 * gap);
    }
    function notchWindowHeight() {
        return openHeight + morphSlack + shadowPad;
    }
    // The bar spacer's reserved width while music plays: the base notch plus
    // the art and spectrum wings.
    readonly property int liveWidth: 280
    // The closed notch with nothing to show: boring.notch's base width.
    readonly property int idleWidth: 185
    // The idle face's notch: boring.notch's base width plus a wing of
    // (bar height − 12) + 10 on each side, at the 26 px bar.
    readonly property int faceWidth: 233
    // The Horizon idle style: a small pill with a centred accent line.
    readonly property int horizonWidth: 120
    readonly property int horizonLine: 40
    // The glance's day-progress fill: neutral and faint, unlike the track's
    // tinted progress, and faded in when the glance appears.
    readonly property real dayHairlineOpacity: 0.35
    readonly property int hairlineRevealDuration: reducedMotion ? 0 : 400
    // How long the idle face keeps a battery mood after its banner.
    readonly property int faceMoodDuration: 3000
    readonly property int hudInlineWidth: 380
    readonly property int batteryBannerWidth: 640
    readonly property int heroArt: 90
    readonly property int heroArtRadius: 13
    readonly property int wingArt: 20
    readonly property int wingArtRadius: 4
    // The closed notch's outer inset: the wing art sits this far in from the
    // body's left end and the spectrum as far in from its right end, so the
    // two wings mirror each other and stay clear of the rounded corners.
    readonly property int closedInset: 10
    // The closed spectrum: the same bands a pixel apart, narrow enough to
    // fit its wing at that inset.
    readonly property int closedSpectrumGap: 1
    // The closed content's swap: the old content fades out while the width
    // springs, then the new fades in.
    readonly property int closedFadeOut: reducedMotion ? 0 : 90
    readonly property int closedFadeIn: reducedMotion ? 0 : 130
    readonly property int closedSpectrumWidth: spectrumBands * spectrumBarWidth + (spectrumBands - 1) * closedSpectrumGap
    // Closed-notch activities: the minimal glyph a second activity shrinks
    // to, how much the notch widens for it where the wings are narrow, and
    // the recording's dot and red (fixed, never album-tinted).
    readonly property int minimalGlyph: 14
    readonly property int minimalGrowth: 22
    readonly property int recordingDot: 7
    readonly property color recordingInk: "#ff453a"
    // Privacy indicators: 4 px dots in a column at the closed notch's
    // trailing end, the right wing's content moved in beside them, and the
    // platform's colours (fixed, never album-tinted).
    readonly property int privacyDot: 4
    readonly property int privacyEdge: 4
    readonly property int privacyInset: 6
    readonly property int privacyMutedGlyph: 9
    readonly property int privacyMutedInset: 11
    readonly property color privacyMic: "#ff9f0a"
    readonly property color privacyCamera: "#30d158"
    readonly property color privacyScreen: "#0a84ff"
    readonly property int buttonSize: 30
    readonly property int playSize: 40
    readonly property int toolbarGap: 6
    readonly property color raisedSurface: "#141414"
    readonly property color raisedStroke: Qt.rgba(1, 1, 1, 0.04)
    readonly property real pausedArtScale: 0.85
    // The closed notch's cover while paused.
    readonly property real pausedWingOpacity: 0.6
    readonly property int scrubHeight: 5
    readonly property int scrubHeightActive: 9
    // Marquee scroll speed in px/s, and its pause before each pass in ms.
    readonly property int marqueeSpeed: 30
    readonly property int marqueeDelay: 3000
}
