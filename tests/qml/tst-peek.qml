import QtQuick
import QtTest
import "../../components"

TestCase {
    id: test
    name: "PeekModel"
    when: windowShown
    visible: true
    width: 10
    height: 10

    DesignTokens {
        id: design
    }

    Component {
        id: peekComponent
        PeekModel {
            tokens: design
        }
    }

    // Shaped like PowerSource: raw samples only, sent from emitSample().
    Component {
        id: powerStubComponent
        Item {
            id: stub
            property bool onBattery: true
            property real level: 0.8
            signal sample(bool present, bool onBattery, real level)
            function emitSample() { stub.sample(true, stub.onBattery, stub.level) }
            onOnBatteryChanged: emitSample()
            // As PowerSource: no sample from Component.onCompleted.
        }
    }

    // Drives the stub exactly as Panel.qml drives PowerSource.
    Component {
        id: powerHostComponent
        Item {
            id: host
            property alias model: model
            property alias loader: loader
            PeekModel {
                id: model
                tokens: design
            }
            Loader {
                id: loader
                active: false
                sourceComponent: powerStubComponent
                onLoaded: {
                    model.resetPowerBaseline();
                    loader.item.emitSample();
                }
            }
            Connections {
                target: loader.item
                function onSample(present, onBattery, level) { model.notePower(present, onBattery, level) }
            }
        }
    }

    function test_firstTrackIsBaseline() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        wait(400);
        compare(peek.active, false, "the first track of a source is a baseline only");
    }

    function test_trackChangePeeksAfterSettle() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        wait(150);
        compare(peek.active, false, "the peek waits out the settle window");
        tryCompare(peek, "active", true, 400);
        compare(peek.kind, "track");
    }

    function test_metadataBurstPeeksOnce() {
        var peek = createTemporaryObject(peekComponent, test);
        var shows = 0;
        peek.activeChanged.connect(function () { if (peek.active) shows++; });
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        wait(40);
        peek.noteTrack("spotify", "track-c");
        wait(40);
        peek.noteTrack("spotify", "track-d");
        tryCompare(peek, "active", true, 500);
        wait(300);
        compare(shows, 1, "a burst of metadata updates peeks once");
        compare(peek.trackKey, "track-d", "with the last key");
    }

    function test_sourceSwitchDoesNotPeek() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("firefox", "track-z");
        wait(400);
        compare(peek.active, false, "a new source is a new baseline, not a track change");
        peek.noteTrack("firefox", "");
        peek.noteTrack("firefox", "track-y");
        wait(400);
        compare(peek.active, false, "an empty key also resets the baseline");
    }

    function test_trackPeekDismissesAfterDuration() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        tryCompare(peek, "active", true, 500);
        wait(design.trackPeekDuration - 400);
        verify(peek.active, "still showing before the duration elapses");
        tryCompare(peek, "active", false, 1000);
    }

    function test_suppressedWhileExpanded() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        peek.suppressed = true;
        peek.noteTrack("spotify", "track-b");
        wait(400);
        compare(peek.active, false, "a suppressed model never peeks");
        peek.suppressed = false;
        wait(400);
        compare(peek.active, false, "ending the suppression does not replay the change");
        peek.noteTrack("spotify", "track-c");
        tryCompare(peek, "active", true, 500);
        peek.suppressed = true;
        compare(peek.active, false, "suppression ends a showing peek at once");
    }

    function test_suppressionCancelsPendingSettle() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        wait(100);
        peek.suppressed = true;
        peek.suppressed = false;
        wait(400);
        compare(peek.active, false, "an expansion inside the settle window cancels the peek");
    }

    function test_peekOffDisablesTrack() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.trackEnabled = false;
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        wait(400);
        compare(peek.active, false);
        peek.trackEnabled = true;
        peek.noteTrack("spotify", "track-c");
        tryCompare(peek, "active", true, 500);
        peek.trackEnabled = false;
        compare(peek.active, false, "turning peek off ends a showing track peek");
    }

    function test_plugAndUnplug() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.notePower(true, true, 0.6);
        compare(peek.active, false, "the first sample is a baseline only");
        peek.notePower(true, false, 0.6);
        compare(peek.active, true);
        compare(peek.kind, "power");
        compare(peek.powerKind, "plugged");
        compare(peek.powerLevel, 0.6);
        peek.notePower(true, false, 0.61);
        compare(peek.powerLevel, 0.61, "a showing power peek follows the level");
        peek.dismiss();
        peek.notePower(true, true, 0.61);
        compare(peek.active, true);
        compare(peek.powerKind, "unplugged");
        tryCompare(peek, "active", false, design.powerPeekDuration + 500);
    }

    function test_lowAndCriticalCrossOnce() {
        var peek = createTemporaryObject(peekComponent, test);
        var shown = [];
        peek.activeChanged.connect(function () { if (peek.active) shown.push(peek.powerKind); });
        peek.notePower(true, true, 0.21);
        peek.notePower(true, true, 0.20);
        peek.notePower(true, true, 0.19);
        compare(shown, ["low"], "crossing 20% peeks once");
        peek.dismiss();
        peek.notePower(true, true, 0.11);
        peek.notePower(true, true, 0.10);
        peek.dismiss();
        peek.notePower(true, true, 0.09);
        compare(shown, ["low", "critical"], "crossing 10% peeks once more");
    }

    // The warning is reported at the crossing whatever the style: with
    // power peeks off (the default banner style) it shows no peek, and the
    // host banners it instead; with peeks on it also peeks.
    function test_batteryWarningFiresInEitherStyle() {
        var peek = createTemporaryObject(peekComponent, test);
        var warnings = [];
        peek.batteryWarning.connect(function (kind, level) { warnings.push(kind + "@" + level.toFixed(2)); });
        peek.powerEnabled = false;
        peek.notePower(true, true, 0.25);
        peek.notePower(true, true, 0.20);
        compare(warnings, ["low@0.20"], "20% warns with power peeks off");
        compare(peek.active, false, "and shows no peek");
        peek.notePower(true, true, 0.10);
        compare(warnings, ["low@0.20", "critical@0.10"], "10% warns once more");
        peek.notePower(true, false, 0.30);
        peek.powerEnabled = true;
        peek.dismiss();
        peek.notePower(true, true, 0.25);
        peek.notePower(true, true, 0.19);
        compare(warnings.length, 3, "with peeks on the warning is reported too");
        compare(peek.active, true);
        compare(peek.powerKind, "low", "and peeks");
    }
    function test_thresholdRearmsAfterHysteresis() {
        var peek = createTemporaryObject(peekComponent, test);
        var shows = 0;
        peek.activeChanged.connect(function () { if (peek.active) shows++; });
        peek.notePower(true, true, 0.25);
        peek.notePower(true, true, 0.20);
        compare(shows, 1);
        peek.dismiss();
        peek.notePower(true, true, 0.22);
        peek.notePower(true, true, 0.20);
        compare(shows, 1, "a level that wobbles on the line does not re-arm it");
        peek.notePower(true, true, 0.23);
        peek.notePower(true, true, 0.20);
        compare(shows, 2, "rising past threshold + 2 points re-arms it");
        peek.dismiss();
        peek.notePower(true, false, 0.20);
        peek.dismiss();
        peek.notePower(true, true, 0.21);
        peek.dismiss();
        peek.notePower(true, true, 0.20);
        compare(peek.active, true, "plugging in re-arms it too");
        compare(peek.powerKind, "low");
    }

    function test_firstSampleBelowThresholdDoesNotPeek() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.notePower(true, true, 0.15);
        peek.notePower(true, true, 0.14);
        compare(peek.active, false, "a crossing before the plugin watched is not announced");
        peek.notePower(true, true, 0.10);
        compare(peek.powerKind, "critical");
        compare(peek.active, true);
    }

    function test_noBatteryNeverPeeks() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.notePower(false, true, 0);
        peek.notePower(false, false, 0);
        peek.notePower(false, true, 0.05);
        compare(peek.active, false);
        compare(peek.powerBaseline, null);
        peek.notePower(true, true, 0.5);
        compare(peek.active, false, "the first present sample is a baseline only");
    }

    function test_powerReplacesTrackButNotReverse() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        tryCompare(peek, "active", true, 500);
        compare(peek.kind, "track");
        peek.notePower(true, true, 0.5);
        peek.notePower(true, false, 0.5);
        compare(peek.kind, "power", "a power peek replaces a track peek");
        peek.noteTrack("spotify", "track-c");
        wait(400);
        compare(peek.kind, "power", "a track peek never replaces a power peek");
        compare(peek.powerKind, "plugged");
    }

    // timerDone > power > device > capture > track: a peek replaces one it
    // outranks and never one that outranks it.
    function test_eventPriorityOrder() {
        var peek = createTemporaryObject(peekComponent, test);
        var device = { icon: "headset", title: "JBL", detail: "Connected", level: -1, alert: false };
        verify(peek.showEvent("capture", { icon: "image", title: "Screenshot", detail: "Added to shelf", level: -1 }, 4000));
        compare(peek.kind, "capture");
        verify(peek.showEvent("device", device, 2500), "a device replaces a capture");
        compare(peek.kind, "device");
        compare(peek.event.title, "JBL");
        compare(peek.dismissTimer.interval, 2500);
        verify(!peek.showEvent("capture", { title: "Screenshot" }, 4000), "a capture waits behind a device");
        compare(peek.kind, "device");
        peek.noteTrack("spotify", "track-a");
        peek.noteTrack("spotify", "track-b");
        wait(400);
        compare(peek.kind, "device", "a track never covers a device");
        peek.notePower(true, true, 0.5);
        peek.notePower(true, false, 0.5);
        compare(peek.kind, "power", "power outranks a device");
        verify(!peek.showEvent("device", device, 2500));
        verify(peek.showEvent("timerDone", { icon: "ring", title: "Tea", detail: "Timer done", level: -1 }, 6000));
        compare(peek.kind, "timerDone");
        peek.notePower(true, true, 0.5);
        compare(peek.kind, "timerDone", "nothing covers a finished timer");
        verify(!peek.showEvent("unknown", {}, 1000), "an unknown kind never shows");
    }
    function test_eventUpdateKeepsTime() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.showEvent("device", { title: "JBL", detail: "Connected", level: 0.8 }, 2500);
        peek.dismissTimer.stop();
        peek.updateEvent("device", { title: "JBL", detail: "Connected · Now playing here", level: 0.8 });
        compare(peek.event.detail, "Connected · Now playing here");
        verify(!peek.dismissTimer.running, "an update does not restart the peek's time");
        peek.updateEvent("capture", { title: "other" });
        compare(peek.event.title, "JBL", "only the kind on screen updates");
    }
    function test_eventsAreDroppedWhileSuppressed() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.suppressed = true;
        verify(!peek.showEvent("device", { title: "JBL" }, 2500));
        verify(!peek.active);
        peek.suppressed = false;
        verify(!peek.active, "nothing replays when the suppression ends");
    }

    function test_baselineUpdatesWhileSuppressed() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.notePower(true, true, 0.5);
        peek.suppressed = true;
        peek.notePower(true, false, 0.5);
        compare(peek.active, false);
        peek.suppressed = false;
        peek.notePower(true, false, 0.52);
        compare(peek.active, false, "the plug seen while suppressed is not replayed");
        peek.notePower(true, true, 0.52);
        compare(peek.active, true);
        compare(peek.powerKind, "unplugged");
    }

    function test_powerOffDisablesPower() {
        var peek = createTemporaryObject(peekComponent, test);
        peek.powerEnabled = false;
        peek.notePower(true, true, 0.5);
        peek.notePower(true, false, 0.5);
        compare(peek.active, false);
        peek.powerEnabled = true;
        peek.notePower(true, true, 0.5);
        compare(peek.active, true);
        peek.powerEnabled = false;
        compare(peek.active, false, "turning power off ends a showing power peek");
    }

    function test_firstPlugAfterLoadPeeks() {
        var host = createTemporaryObject(powerHostComponent, test);
        // A stale baseline from before the reload must not be compared.
        host.model.notePower(true, false, 0.3);
        host.loader.active = true;
        verify(host.loader.item);
        compare(host.model.active, false, "the load's own sample is a baseline");
        compare(host.model.powerBaseline.onBattery, true);
        host.loader.item.onBattery = false;
        compare(host.model.active, true, "the first plug after a load peeks");
        compare(host.model.powerKind, "plugged");
    }
}
