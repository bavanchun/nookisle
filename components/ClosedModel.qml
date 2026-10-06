pragma ComponentBehavior: Bound

import QtQuick

// Pure QtQuick closed-notch state, after boring.notch's closed live
// activity: which of idle, live, activity, hudInline, battery or peek the
// closed notch shows, how wide it is and what its two wings hold. No
// Quickshell import, so qmltestrunner drives it offscreen. Priority is HUD >
// battery > peek > activity > live > idle, where an activity is a screen
// recording or a timer that ActivityModel put ahead of the music. A second
// activity shows as a minimal glyph at the trailing end (`minimalContent`). Music stays live for `pauseGrace` ms after a pause, so a
// short pause between tracks does not shrink the notch. Idle follows
// `idleStyle`: "glance" fills the body at the live width the bar spacer
// already reserves, "face" centres the face at boring.notch's face width,
// "horizon" shrinks to a small pill with one accent line, and "empty" (the
// model's own default) is boring.notch's bare base notch. With
// `hardwareNotch` on, no idle style puts anything in the centre.
QtObject {
    id: root
    // Optional: falls back to the plan's constants without a live
    // DesignTokens instance, as HudModel and PeekModel do.
    property var tokens: null
    property bool hasTrack: false
    property bool playing: false
    // A single snapshot avoids treating a source replacement as a pause when
    // the selected endpoint's identity and status change together.
    property var playback: null
    readonly property bool currentHasTrack: playback ? playback.hasTrack === true : hasTrack
    readonly property bool currentPlaying: playback ? playback.playing === true : playing
    readonly property string currentIdentity: playback && playback.identity ? String(playback.identity) : ""
    property string lastIdentity: ""
    property bool lastPlaying: false
    property bool liveActivity: true
    property int pauseGrace: 3000
    property bool hudActive: false
    // "inline" draws the HUD in the closed notch; the other styles draw it
    // elsewhere, so the notch keeps its state.
    property string hudStyle: "inline"
    property bool batteryActive: false
    property bool peekActive: false
    // ActivityModel's compact activity when it is not the music:
    // "recording", "timer" or "".
    property string activity: ""
    // ActivityModel's minimal activity: "recording", "music", "timer",
    // "sleepTimer" or "".
    property string minimalActivity: ""
    property string idleStyle: "empty"
    // False (no camera cutout behind the notch) puts content in the body's
    // centre too: the track title between the cover and the bars.
    property bool hardwareNotch: false
    // The screen less a gap on each side: every width is clamped to it, and
    // the battery banner falls back to the HUD width when it does not fit.
    property real availableWidth: Infinity

    // True from a pause until pauseGrace has passed, while nothing plays.
    property bool lingering: false
    property double pauseStartedAt: 0
    readonly property bool live: liveActivity && currentHasTrack && (currentPlaying || lingering)
    readonly property string state: hudActive && hudStyle === "inline" ? "hudInline"
        : batteryActive ? "battery" : peekActive ? "peek" : activity !== "" ? "activity" : live ? "live" : "idle"
    // The state the notch rests in under a peek: what it returns to.
    readonly property string restState: state === "peek" ? (activity !== "" ? "activity" : live ? "live" : "idle") : state
    readonly property real width: widthOf(state)
    readonly property real restWidth: widthOf(restState)
    readonly property string leftContent: contentOf(state).left
    readonly property string rightContent: contentOf(state).right
    readonly property string centreContent: contentOf(state).centre
    readonly property string minimalContent: minimalOf(state)

    function token(name, fallback) {
        return tokens && tokens[name] !== undefined ? tokens[name] : fallback
    }
    // Where a minimal glyph shows: beside live music, an activity or idle,
    // never over the HUD, the battery banner or a peek's own content.
    function minimalOf(name) {
        return minimalActivity !== "" && (name === "live" || name === "activity" || name === "idle")
            ? minimalActivity : "none"
    }
    // Over a camera cutout the wings are narrow, and the small idle styles
    // leave no room either: the notch widens for the minimal glyph there. The
    // live width is wide enough to take it as it is.
    function minimalGrowth(name) {
        if (minimalOf(name) === "none")
            return 0
        return hardwareNotch || (name === "idle" && idleStyle !== "glance") ? token("minimalGrowth", 22) : 0
    }
    function widthOf(name) {
        return Math.min(baseWidthOf(name) + minimalGrowth(name), availableWidth)
    }
    function baseWidthOf(name) {
        var width = token("idleWidth", 185)
        if (name === "live" || name === "activity" || (name === "idle" && idleStyle === "glance"))
            width = token("liveWidth", 280)
        else if (name === "idle" && idleStyle === "face")
            width = token("faceWidth", 233)
        else if (name === "idle" && idleStyle === "horizon" && !hardwareNotch)
            width = token("horizonWidth", 120)
        else if (name === "hudInline")
            width = token("hudInlineWidth", 380)
        else if (name === "battery") {
            width = token("batteryBannerWidth", 640)
            if (width > availableWidth)
                width = token("hudInlineWidth", 380)
        } else if (name === "peek")
            width = token("peekWidth", 300)
        return width
    }
    function contentOf(name) {
        switch (name) {
        case "live":
            return { left: "art", centre: hardwareNotch ? "none" : "title", right: "spectrum" }
        case "activity":
            // A recording or a timer: its glyph, its label in the centre
            // when no camera cutout is in the way, and its minutes.
            return { left: activity + "Glyph", centre: hardwareNotch ? "none" : activity + "Label", right: activity + "Value" }
        case "hudInline":
            return { left: "hudIcon", centre: "none", right: "hudLevel" }
        case "battery":
            return { left: "batteryLabel", centre: "none", right: "batteryIcon" }
        case "idle":
            // Over a camera cutout the face takes the right wing, as in
            // boring.notch; otherwise it sits in the centre.
            if (idleStyle === "face")
                return hardwareNotch ? { left: "none", centre: "none", right: "face" }
                    : { left: "none", centre: "face", right: "none" }
            // Over a camera cutout nothing enters the centre: the glance
            // splits into the wings, and Horizon, which would sit wholly
            // inside the cutout, leaves the empty base notch.
            if (idleStyle === "glance")
                return hardwareNotch ? { left: "glance", centre: "none", right: "glance" }
                    : { left: "none", centre: "glance", right: "none" }
            if (idleStyle === "horizon" && !hardwareNotch)
                return { left: "none", centre: "horizon", right: "none" }
        }
        return { left: "none", centre: "none", right: "none" }
    }
    function updatePlayback() {
        var nextIdentity = playback && playback.identity ? String(playback.identity) : "";
        var nextHasTrack = playback && playback.hasTrack === true;
        var nextPlaying = nextHasTrack && playback.playing === true;
        var sameTrack = nextIdentity !== "" && nextIdentity === lastIdentity;
        if (nextPlaying) {
            graceTimer.stop();
            lingering = false;
        } else if (lastPlaying && sameTrack && liveActivity && pauseGrace > 0) {
            lingering = true;
            pauseStartedAt = Date.now();
            graceTimer.interval = pauseGrace;
            graceTimer.restart();
        } else if (!sameTrack || !nextHasTrack) {
            graceTimer.stop();
            lingering = false;
        }
        lastIdentity = nextIdentity;
        lastPlaying = nextPlaying;
    }
    onPlaybackChanged: if (playback !== null)
        updatePlayback()
    onPlayingChanged: if (playback === null) {
        graceTimer.stop()
        if (playing) {
            lingering = false
        } else if (liveActivity && hasTrack && pauseGrace > 0) {
            lingering = true
            pauseStartedAt = Date.now()
            graceTimer.interval = pauseGrace
            graceTimer.start()
        }
    }
    onPauseGraceChanged: {
        if (!lingering)
            return;
        var remaining = pauseGrace - (Date.now() - pauseStartedAt);
        if (remaining <= 0) {
            graceTimer.stop();
            lingering = false;
        } else {
            graceTimer.interval = remaining;
            graceTimer.restart();
        }
    }
    onHasTrackChanged: if (playback === null && !hasTrack) {
        graceTimer.stop()
        lingering = false
    }
    property Timer graceTimer: Timer {
        repeat: false
        onTriggered: root.lingering = false
    }
}
