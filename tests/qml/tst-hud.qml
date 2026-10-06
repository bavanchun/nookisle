import QtQuick
import QtTest
import "../../components"
import "../../qml/ReadoutOwner.js" as ReadoutOwner
import "../../qml/VolumeSink.js" as VolumeSink

TestCase {
    id: test
    name: "HudModel"
    when: windowShown
    visible: true
    width: 10
    height: 10

    function test_virtualOutputResolvesToTheSinkUsedByKeys() {
        var dsp = { id: 1, name: "omarchy_speaker_tuning", isSink: true }
        var stream = { id: 2, name: "omarchy_speaker_tuning.output", isStream: true, properties: ({}) }
        var physical = { id: 3, name: "alsa_output.pci", isSink: true }
        compare(VolumeSink.resolve(dsp, [{ source: stream, target: physical }]), physical)
        compare(VolumeSink.resolve(physical, [{ source: stream, target: physical }]), physical)
        var effects = { id: 4, name: "easyeffects_sink", isSink: true }
        var effectsStream = { id: 5, name: "output", isStream: true,
            properties: ({ "application.name": "EasyEffects" }) }
        compare(VolumeSink.resolve(effects, [{ source: effectsStream, target: physical }]), physical)
        compare(VolumeSink.resolve(dsp, []), dsp, "an unlinked DSP uses its own level")
    }

    DesignTokens {
        id: design
    }

    Component {
        id: hudComponent
        HudModel {
            tokens: design
        }
    }

    function test_volumeShowsAndDismisses() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.2, false);
        compare(hud.active, false, "the first sample of a sink is a baseline only");
        hud.noteVolume("sink-a", 0.4, false);
        compare(hud.active, true);
        compare(hud.kind, "volume");
        compare(hud.level, 0.4);
        tryCompare(hud, "active", false, 2000);
    }

    function test_fallbackOwnedSampleNeverStartsIslandReadout() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.readoutAllowed = function (kind) { return false };
        hud.noteVolume("sink-a", 0.2, false);
        hud.noteVolume("sink-a", 0.4, false);
        compare(hud.active, false, "a fallback-owned key leaves the HUD silent");
        hud.readoutAllowed = function (kind) { return true };
        hud.noteVolume("sink-a", 0.6, false);
        compare(hud.active, true, "a prompt island-owned key still shows the HUD");
    }

    function test_readoutOwnerExpiresAndChecksKind() {
        var now = Date.now();
        var fallback = "volume 123-456 fallback " + (now + 2000);
        var island = "volume 123-457 island " + (now + 2000);
        compare(ReadoutOwner.allows(fallback, "volume", now), false);
        compare(ReadoutOwner.allows(island, "volume", now), true);
        compare(ReadoutOwner.allows(fallback, "mic", now), true);
        compare(ReadoutOwner.allows(fallback, "volume", now + 2001), true);
    }

    function test_localWheelAndBarChangesBypassFallbackRecordOnce() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.readoutAllowed = function (kind) { return false };
        hud.noteVolume("sink-a", 0.2, false);
        hud.expectLocal("volume");
        hud.noteVolume("sink-a", 0.4, false);
        compare(hud.active, true, "the island's wheel change shows despite a key fallback");
        hud.active = false;
        hud.noteVolume("sink-a", 0.6, false);
        compare(hud.active, false, "a later key sample still belongs to Omarchy");
        hud.expectLocal("brightness");
        hud.show("brightness", 0.7, false);
        compare(hud.active, true, "a HUD bar write also shows despite the fallback record");
        hud.active = false;
        hud.expectLocal("volume", 2);
        hud.noteVolume("sink-a", 0.6, true);
        hud.noteVolume("sink-a", 0.8, true);
        compare(hud.active, true, "unmute and level signals from one wheel step can both update the HUD");
        hud.active = false;
        hud.noteVolume("sink-a", 0.9, true);
        compare(hud.active, false, "the local exemption is consumed after both samples");
    }

    function test_dragThenSlowKeyDoesNotUseSpareLocalReservation() {
        for (var kind of ["brightness", "keyboard"]) {
            var hud = createTemporaryObject(hudComponent, test);
            var fallback = kind + " 123-456 fallback " + (Date.now() + 2000);
            hud.readoutAllowed = function (sampleKind) {
                return ReadoutOwner.allows(fallback, sampleKind, Date.now());
            };
            for (var move = 0; move < 6; ++move) hud.expectLocal(kind);
            hud.show(kind, 0.5, false);
            compare(hud.active, true, "the coalesced drag write shows locally");
            hud.active = false;
            hud.show(kind, 0.6, false);
            compare(hud.active, false, "a slow key's fallback sample must not use a spare drag reservation");
        }
    }

    function test_repeatedEventsExtend() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.2, false);
        hud.noteVolume("sink-a", 0.4, false);
        wait(design.hudDuration - 300);
        verify(hud.active, "still active before the first duration elapses");
        hud.noteVolume("sink-a", 0.6, false);
        wait(design.hudDuration - 300);
        verify(hud.active, "a repeated event must extend the duration rather than let it lapse");
        tryCompare(hud, "active", false, 2000);
    }

    function test_suppressedWhileExpanded() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.suppressed = true;
        hud.noteVolume("sink-a", 0.2, false);
        hud.noteVolume("sink-a", 0.4, false);
        compare(hud.active, false, "a suppressed model never shows");
        hud.suppressed = false;
    }

    function test_suppressedWhileFullscreen() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.2, false);
        hud.noteVolume("sink-a", 0.4, false);
        compare(hud.active, true);
        hud.suppressed = true;
        compare(hud.active, false, "suppression turns off an active readout immediately");
        hud.suppressed = false;
    }

    function test_firstSampleAndSinkChangeAreBaselineOnly() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.5, false);
        compare(hud.active, false);
        hud.noteVolume("sink-b", 0.9, false);
        compare(hud.active, false, "a new sink's first sample is baseline only");
        hud.noteVolume("sink-b", 0.1, false);
        compare(hud.active, true);
    }

    function test_baselineUpdatesWhileSuppressed() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.2, false);
        hud.suppressed = true;
        hud.noteVolume("sink-a", 0.9, false);
        hud.suppressed = false;
        hud.noteVolume("sink-a", 0.9, false);
        compare(hud.active, false, "the baseline moved to 0.9 while suppressed, so an unchanged repeat shows nothing");
        hud.noteVolume("sink-a", 0.5, false);
        compare(hud.active, true);
    }

    function test_mutedKind() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.5, false);
        hud.noteVolume("sink-a", 0.5, true);
        compare(hud.active, true);
        compare(hud.kind, "volume");
        compare(hud.muted, true);
        compare(hud.icon, "muted");
        compare(hud.label, "Muted");
    }

    function test_keyboardAndMicKinds() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.show("keyboard", 0.5, false);
        compare(hud.kind, "keyboard");
        compare(hud.icon, "keyboard");
        compare(hud.label, "Keyboard backlight");
        compare(hud.hasBar, true);
        hud.show("mic", 0, true, "Microphone muted");
        compare(hud.kind, "mic");
        compare(hud.icon, "mic-muted");
        compare(hud.label, "Microphone muted");
        compare(hud.hasBar, false);
        hud.show("mic", 0, false);
        compare(hud.icon, "mic");
        compare(hud.label, "Microphone on");
    }

    // Panel.qml calls this whenever the volume source Loader reloads (a
    // `hud` toggle, a `barHidden` flip), so a sink known from before the
    // reload does not compare a fresh baseline against a stale one (code
    // review M4).
    function test_resetBaselinesClearsPriorSinkState() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.noteVolume("sink-a", 0.2, false);
        hud.noteVolume("sink-a", 0.4, false);
        compare(hud.active, true, "an ordinary change shows as usual before any reset");
        hud.active = false;
        hud.resetBaselines();
        hud.noteVolume("sink-a", 0.9, false);
        compare(hud.active, false, "the first sample after a reset is a baseline only, even for a known sink");
        hud.noteVolume("sink-a", 0.1, false);
        compare(hud.active, true);
    }

    function test_levelAbove1() {
        var hud = createTemporaryObject(hudComponent, test);
        hud.show("brightness", 1.5, false);
        compare(hud.level, 1.5);
        compare(hud.kind, "brightness");
        compare(hud.active, true);
    }

    function test_otherKindWaitsForHeldBar() {
        var hud = createTemporaryObject(hudComponent, test);
        var owner = Qt.createQmlObject("import QtQuick; QtObject {}", test);
        hud.show("volume", 0.4, false);
        hud.hold(owner, true);
        hud.show("mic", 0, true);
        compare(hud.kind, "volume", "a different event cannot replace a held bar");
        compare(hud.level, 0.4);
        compare(hud.held, true);
        hud.show("volume", 0.6, false);
        compare(hud.level, 0.6, "the held kind may still update its level");
        hud.hold(owner, false);
        hud.show("mic", 0, true);
        compare(hud.kind, "mic", "a different event can show after release");
    }
}
