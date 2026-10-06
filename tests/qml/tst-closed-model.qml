import QtQuick
import QtTest
import "../../components"

TestCase {
    id: test
    name: "ClosedModel"
    DesignTokens {
        id: design
    }
    Component {
        id: modelComponent
        ClosedModel {
            tokens: design
        }
    }
    function test_idleWithoutMusic() {
        var model = createTemporaryObject(modelComponent, test);
        compare(model.state, "idle");
        compare(model.width, design.idleWidth);
        compare(model.leftContent, "none");
        compare(model.rightContent, "none");
    }
    // Each idle style has its width and content; each shows only while
    // nothing plays and yields to every other state.
    function test_idleStyles() {
        var model = createTemporaryObject(modelComponent, test);
        compare(model.idleStyle, "empty", "a bare model is boring.notch's base notch");
        model.idleStyle = "glance";
        compare(model.state, "idle");
        compare(model.centreContent, "glance");
        compare(model.width, design.liveWidth, "the glance fills the width the bar spacer reserves");
        model.idleStyle = "horizon";
        compare(model.centreContent, "horizon");
        compare(model.width, design.horizonWidth);
        model.idleStyle = "face";
        compare(model.centreContent, "face", "the face sits in the centre");
        compare(model.leftContent, "none");
        compare(model.width, design.faceWidth);
        model.hardwareNotch = true;
        compare(model.centreContent, "none");
        compare(model.rightContent, "face", "over a camera cutout it takes the right wing, as in boring.notch");
        model.hardwareNotch = false;
        model.hasTrack = true;
        model.playing = true;
        compare(model.state, "live");
        compare(model.leftContent, "art", "music replaces the idle style");
        model.playing = false;
        model.pauseGrace = 0;
        model.hasTrack = false;
        compare(model.centreContent, "face", "it returns once nothing plays");
        model.hudActive = true;
        compare(model.leftContent, "hudIcon", "the inline HUD wins over it");
        compare(model.centreContent, "none");
        model.hudActive = false;
        model.peekActive = true;
        compare(model.state, "peek");
        compare(model.contentOf(model.restState).centre, "face", "a peek rests on it");
        model.peekActive = false;
        model.idleStyle = "empty";
        compare(model.centreContent, "none");
        compare(model.width, design.idleWidth);
    }
    // Without a hardware notch the live notch's centre holds the title;
    // over a camera cutout it stays empty. No other state uses the centre.
    function test_centreHoldsTheTitleWithoutAHardwareNotch() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true });
        compare(model.centreContent, "title");
        model.hardwareNotch = true;
        compare(model.centreContent, "none");
        model.hardwareNotch = false;
        model.hudActive = true;
        compare(model.centreContent, "none", "the inline HUD draws its own row");
        model.hudActive = false;
        model.batteryActive = true;
        compare(model.centreContent, "none");
    }
    // Over a camera cutout no idle style enters the centre: the glance
    // splits into the wings at its width, and Horizon, which would sit
    // wholly inside the cutout, leaves the empty base notch.
    function test_hardwareNotchKeepsTheIdleCentreEmpty() {
        var model = createTemporaryObject(modelComponent, test, { hardwareNotch: true, idleStyle: "glance" });
        compare(model.centreContent, "none");
        compare(model.leftContent, "glance");
        compare(model.rightContent, "glance");
        compare(model.width, design.liveWidth);
        model.idleStyle = "horizon";
        compare(model.centreContent, "none");
        compare(model.leftContent, "none");
        compare(model.rightContent, "none");
        compare(model.width, design.idleWidth);
        ["glance", "face", "horizon", "empty"].forEach(function (style) {
            model.idleStyle = style;
            compare(model.centreContent, "none", style + " keeps the centre empty");
        });
    }
    function test_liveWhilePlaying() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true });
        compare(model.state, "live");
        compare(model.width, design.liveWidth);
        compare(model.leftContent, "art");
        compare(model.rightContent, "spectrum");
        model.liveActivity = false;
        compare(model.state, "idle", "musicLiveActivity off keeps the notch idle");
    }
    // Priority is HUD > battery > peek > live > idle.
    function test_priorities() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true });
        model.peekActive = true;
        compare(model.state, "peek");
        compare(model.width, design.peekWidth);
        compare(model.restState, "live", "a peek rests on the live notch");
        compare(model.restWidth, design.liveWidth);
        model.batteryActive = true;
        compare(model.state, "battery");
        compare(model.width, design.batteryBannerWidth);
        compare(model.leftContent, "batteryLabel");
        model.hudActive = true;
        compare(model.state, "hudInline");
        compare(model.width, design.hudInlineWidth);
        compare(model.leftContent, "hudIcon");
        compare(model.rightContent, "hudLevel");
        model.hudStyle = "under";
        compare(model.state, "battery", "a HUD drawn elsewhere leaves the notch alone");
        model.batteryActive = false;
        model.peekActive = false;
        compare(model.state, "live");
    }
    // Music stays live for pauseGrace after a pause, then goes idle; playing
    // again cancels the grace.
    function test_pauseGrace() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true, pauseGrace: 120 });
        model.playing = false;
        compare(model.state, "live", "live through the grace");
        wait(60);
        compare(model.state, "live");
        tryCompare(model, "state", "idle", 400);
        model.playing = true;
        compare(model.state, "live");
        model.playing = false;
        wait(60);
        model.playing = true;
        wait(120);
        compare(model.state, "live", "playing again cancels the grace");
    }
    function test_zeroGraceGoesIdleAtOnce() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true, pauseGrace: 0 });
        model.playing = false;
        compare(model.state, "idle");
    }
    function test_changingGraceUpdatesAnActivePause() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true, pauseGrace: 500 });
        model.playing = false;
        compare(model.state, "live");
        model.pauseGrace = 0;
        compare(model.state, "idle", "zero grace removes the live wing immediately");
        model.playing = true;
        model.pauseGrace = 300;
        model.playing = false;
        wait(80);
        model.pauseGrace = 120;
        compare(model.state, "live");
        tryCompare(model, "state", "idle", 200, "shortening grace counts from the original pause");
        model.playing = true;
        model.pauseGrace = 90;
        model.playing = false;
        wait(50);
        model.pauseGrace = 180;
        wait(60);
        compare(model.state, "live", "lengthening grace keeps the original pause time");
        tryCompare(model, "state", "idle", 200);
    }
    function test_losingTheTrackEndsTheGrace() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true, pauseGrace: 5000 });
        model.playing = false;
        compare(model.state, "live");
        model.hasTrack = false;
        compare(model.state, "idle");
    }
    // A track that was already paused when the model started is idle: the
    // grace follows a pause, not a paused track.
    function test_startsIdleWhenAlreadyPaused() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: false });
        compare(model.state, "idle");
    }
    function test_switchToAlreadyPausedTrackHasNoGrace() {
        var model = createTemporaryObject(modelComponent, test, {
            playback: { identity: "source-a/track-a", hasTrack: true, playing: true }, pauseGrace: 5000
        });
        compare(model.state, "live");
        model.playback = { identity: "source-b/track-b", hasTrack: true, playing: false };
        compare(model.state, "idle", "a different paused track did not just pause");
        model.playback = { identity: "source-b/track-b", hasTrack: true, playing: true };
        model.playback = { identity: "source-b/track-b", hasTrack: true, playing: false };
        compare(model.state, "live", "a real pause on the new track gets its own grace");
        model.playback = { identity: "source-b/track-c", hasTrack: true, playing: false };
        compare(model.state, "idle", "a different track from the same source gets no grace");
    }
    // Widths are clamped to the screen, and the battery banner falls back to
    // the HUD width when it does not fit.
    function test_widthsClampToTheScreen() {
        var model = createTemporaryObject(modelComponent, test, { batteryActive: true, availableWidth: 500 });
        compare(model.width, design.hudInlineWidth);
        model.availableWidth = 300;
        compare(model.width, 300);
        model.batteryActive = false;
        compare(model.width, design.idleWidth);
        model.availableWidth = 100;
        compare(model.width, 100);
    }
    // A recording or a timer ahead of the music takes the notch at the live
    // width, below the HUD, the battery banner and a peek.
    function test_activityState() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true });
        compare(model.state, "live");
        model.activity = "recording";
        compare(model.state, "activity");
        compare(model.width, design.liveWidth, "the width the bar spacer already reserves");
        compare(model.leftContent, "recordingGlyph");
        compare(model.centreContent, "recordingLabel");
        compare(model.rightContent, "recordingValue");
        model.hardwareNotch = true;
        compare(model.centreContent, "none", "no label over a camera cutout");
        model.hardwareNotch = false;
        model.peekActive = true;
        compare(model.state, "peek");
        compare(model.restState, "activity", "a peek returns to the activity");
        model.peekActive = false;
        model.batteryActive = true;
        compare(model.state, "battery");
        model.batteryActive = false;
        model.hudActive = true;
        compare(model.state, "hudInline");
        model.hudActive = false;
        model.activity = "timer";
        compare(model.leftContent, "timerGlyph");
        compare(model.rightContent, "timerValue");
        model.activity = "";
        compare(model.state, "live", "the music returns");
    }
    // The minimal glyph shows beside music, an activity or idle, and only
    // widens the notch where the wings are narrow.
    function test_minimalPlacement() {
        var model = createTemporaryObject(modelComponent, test, { hasTrack: true, playing: true });
        model.minimalActivity = "timer";
        compare(model.minimalContent, "timer");
        compare(model.width, design.liveWidth, "the live width takes the glyph as it is");
        model.hardwareNotch = true;
        compare(model.width, design.liveWidth + design.minimalGrowth, "narrow wings over a camera cutout widen");
        model.availableWidth = design.liveWidth + 5;
        compare(model.width, design.liveWidth + 5, "still clamped to the screen");
        model.availableWidth = Infinity;
        model.hudActive = true;
        compare(model.minimalContent, "none", "never over the HUD");
        compare(model.width, design.hudInlineWidth);
        model.hudActive = false;
        model.hardwareNotch = false;
        model.playing = false;
        model.lingering = false;
        compare(model.state, "idle");
        model.idleStyle = "glance";
        compare(model.minimalContent, "timer");
        compare(model.width, design.liveWidth, "the glance keeps room at its trailing end");
        model.idleStyle = "horizon";
        compare(model.width, design.horizonWidth + design.minimalGrowth, "a small idle notch widens for it");
        model.minimalActivity = "";
        compare(model.width, design.horizonWidth);
        compare(model.minimalContent, "none");
    }
}
