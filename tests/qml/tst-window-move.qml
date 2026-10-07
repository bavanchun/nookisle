import QtQuick
import QtTest
import "../../components"

// Quickshell rebuilds a panel's window on a screen change by moving the
// whole content into a new QQuickWindow and
// deleting the old one. Any item left holding the old window then crashes
// the next scene-graph sync. Each test here builds the content Panel.qml puts
// in its PanelWindow, drives it into one state, and moves it from window to
// window several times, deleting each old window and rendering the new one.
// Qt warns "Cannot use same item on different windows" when an item keeps
// the old window; that warning, and any script error, fails the test.
TestCase {
    id: test
    name: "WindowMove"
    width: 100
    height: 100
    when: windowShown
    visible: true

    DesignTokens {
        id: design
        reducedMotion: true
    }
    // Long enough that a readout stays up through every move.
    HudModel {
        id: sharedHud
        tokens: design
        duration: 60000
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
        property bool hud: true
        property bool visualizer: true
        property bool lyrics: true
        property string spectrumState: "running"
        property var spectrumLevels: [0.2, 0.5, 0.9, 0.4, 0.7, 0.3, 0.6, 0.8, 0.1, 0.5, 0.4, 0.2]
        property bool islandPointerActive: false
        property var fileSettings: ({})
        property var shelfItems: []
        property var shelfEntries: []
        property var shelfMimes: ({})
        property string shelfNotice: ""
        property var shelfActions: null
        property var calendarSource: null
        property bool sleepArmable: true
        property bool sleepLockVerified: true
        property double sleepDeadline: 0
        property string sleepFailure: ""
        function shelfAddDrop(urls, text) { return urls.length }
        function shelfAdd(uris) { return uris.length }
        function shelfAction(name, ids, argument) { return true }
        function shelfThumbnailCandidates(id) { return [] }
        function shelfIcons(id) { return [] }
        function requestShelfThumbnail(id) { return false }
        function shelfShareUris(uris) { return true }
        function shelfPickAndShare() { return true }
        function shelfPaste() {}
        function openSettings(section) { return true }
        function armSleepTimer(minutes) { return "ok" }
        function cancelSleepTimer() {}
        function captureIntent() { return null }
        function invoke(action, intent, value) {}
        function selectSource(token) {}
        function selectAuto() {}
        function retryConnection() {}
        function configure(options) { return true }
    }
    QtObject {
        id: lyricsFixture
        property bool lyricsEnabled: true
        property string lyricsState: "ready"
        property string errorCode: ""
        property var lines: [{ time: 1, text: "First line" }, { time: 70, text: "Second line" }]
        property int currentIndex: 1
        property var meta: ({ title: "Test track" })
        readonly property string displayState: !lyricsEnabled ? "off"
            : lyricsState === "idle" ? (meta ? "loading" : "no-meta") : lyricsState
        function retry() {}
    }
    // Stands in for the camera device; tests never open it.
    Component {
        id: fakeCamera
        Item { property bool unavailable: false }
    }
    Component {
        id: bareWindow
        Window {
            width: 760
            height: 420
            visible: true
        }
    }
    // A stand-in for the PanelWindow's sole island surface.
    Component {
        id: panelContent
        Item {
            id: host
            readonly property alias surface: surface
            width: 760
            height: 420
            IslandSurface {
                id: surface
                anchors.fill: parent
                tokens: design
                coordinator: facade
                hostVisible: host.visible
                pillHeight: 26
                hudModel: sharedHud
                lyricsSource: lyricsFixture
                liveSpectrum: true
                cameraAllowed: true
            }
        }
    }

    property string artworkPath: ""
    Component {
        id: artworkFixture
        Rectangle {
            width: 64
            height: 64
            gradient: Gradient {
                GradientStop { position: 0; color: "#1f4fb8" }
                GradientStop { position: 1; color: "#f2a33a" }
            }
        }
    }
    function initTestCase() {
        var art = createTemporaryObject(artworkFixture, test);
        waitForRendering(art);
        var url = Qt.resolvedUrl("../../build/ui-preview/window-move-art.png").toString();
        grabImage(art).save(url.slice(7));
        artworkPath = url.slice(7);
    }
    function endpoint(status) {
        return {
            token: { owner: "fixture" },
            trackToken: { id: "track" },
            status: status,
            positionSeconds: 74,
            lengthSeconds: 245,
            volume: 0.6,
            shuffle: false,
            loopStatus: "None",
            artworkPath: test.artworkPath,
            presentation: { title: "Test track", artists: ["Test artist"], hostApp: "Spotify", controlScope: "application" },
            capabilities: {
                CanControl: true, CanPlay: true, CanPause: true, CanGoPrevious: true, CanGoNext: true,
                CanSeek: true, CanSetPosition: true, CanSetVolume: true, CanShuffle: true, CanLoop: true,
                CanFavorite: false, CanRaise: false
            }
        };
    }
    function calendarItems() {
        var now = new Date();
        function at(hours) {
            var d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, 0);
            return Qt.formatDateTime(d, "yyyy-MM-ddThh:mm:ss.zzz");
        }
        return [
            { sourceId: "s", uid: "a", start: at(9), end: at(10), title: "Standup", color: "#ff9f0a" },
            { sourceId: "s", uid: "b", start: at(20), end: at(21), title: "Review", location: "Room 2" },
            { sourceId: "s", uid: "c", todo: true, completed: false, due: at(18), start: "", end: "", title: "Pay rent" }
        ];
    }
    function init() {
        design.gpuEffects = false;
        design.artColor = "#1f4fb8";
        sharedHud.hudTimer.stop();
        sharedHud.active = false;
        facade.lyrics = true;
        facade.selectedEndpoint = endpoint("Playing");
        facade.endpoints = [facade.selectedEndpoint];
        facade.fileSettings = ({ showCalendar: true, showMirror: true, showIdleFace: true, pauseGrace: 0 });
        facade.calendarSource = ({ items: calendarItems() });
        facade.shelfEntries = [
            { id: "s1", kind: "file", uri: "file://" + test.artworkPath, name: "art.png", addedAt: 1, temp: false },
            { id: "s2", kind: "text", text: "a note", name: "a note", addedAt: 2, temp: false },
            { id: "s3", kind: "link", uri: "https://example.com/", name: "example.com", addedAt: 3, temp: false }
        ];
        facade.shelfMimes = ({ s1: "image/png", s2: "text/plain" });
    }

    // Moves the content through `rounds` new windows, deleting each old one
    // and rendering the new one, as Quickshell does when it rebuilds the
    // window. The first window is deleted too. `check` asserts the row's
    // state and its visible item before every transfer and after every
    // render, so a state lost in a move fails the row.
    function moveThroughWindows(host, first, rounds, check) {
        var current = first;
        for (var i = 0; i < rounds; ++i) {
            check("before move " + (i + 1));
            current = moveOnce(host, current);
            check("after move " + (i + 1));
        }
        host.destroy();
        current.destroy();
        wait(0);
    }
    function moveOnce(host, current) {
        var next = bareWindow.createObject(test);
        host.parent = next.contentItem;
        current.destroy();
        wait(0);
        waitForRendering(host);
        verify(host.Window.window === next, "the content renders in the new window");
        return next;
    }
    function watchForStaleWindows() {
        failOnWarning(/Cannot use same item on different windows/);
        failOnWarning(/TypeError/);
        failOnWarning(/ReferenceError/);
    }
    function build() {
        var first = bareWindow.createObject(test);
        // Owned by the test, shown in the window: the window only hosts the
        // content, as a Quickshell window hosts the panel's.
        var host = panelContent.createObject(test, { parent: first.contentItem });
        host.surface.cameraSource = fakeCamera;
        return { window: first, host: host };
    }
    function shown(root, name, where) {
        var item = findChild(root, name);
        verify(item && item.visible, name + " is visible " + where);
        return item;
    }
    function checkIslandSide(host, where) {
        verify(host.surface.visible, "the island surface shows " + where);
    }
    // The closed notch at rest: live while playing, idle (with its face)
    // once paused, since the fixture has no pause grace.
    function checkClosedRest(surface, status, where) {
        compare(surface.expanded, false, "collapsed " + where);
        if (status === "Playing") {
            compare(surface.closedModel.state, "live", "the live activity " + where);
            shown(surface, "progressHairline", where);
            verify(findChild(surface, "pillArtwork").visible || findChild(surface, "pillMusicGlyph").visible,
                "the art wing " + where);
        } else {
            compare(surface.closedModel.state, "idle", "idle " + where);
            shown(surface, "closedIdleFace", where);
        }
    }
    // The named island state and the item that shows it.
    function checkIslandState(host, data, where) {
        var surface = host.surface;
        checkIslandSide(host, where);
        switch (data.state) {
        case "home":
        case "batteryPopover":
        case "hudOpen":
            compare(surface.expanded, true, "open " + where);
            compare(surface.view, "home");
            shown(surface, "homeView", where);
            shown(surface, "calendarPanel", where);
            shown(surface, "cameraPanel", where);
            compare(!!findChild(surface, "pausedBlur"), data.gpu && data.status === "Paused",
                "the paused cover blur exists exactly when paused with GPU effects " + where);
            if (data.state === "batteryPopover") {
                var popover = findChild(surface, "batteryPopoverLoader").item;
                verify(popover && popover.visible, "the battery popover " + where);
            }
            if (data.state === "hudOpen") {
                verify(surface.hudActive, "the readout is active " + where);
                shown(surface, "headerHud", where);
            }
            break;
        case "shelf":
        case "lyrics":
            compare(surface.expanded, true, "open " + where);
            compare(surface.view, data.state);
            var view = findChild(surface, data.state + "ViewLoader").item;
            verify(view && view.visible, "the " + data.state + " view " + where);
            if (data.state === "shelf")
                compare(view.entries.length, 3, "with its items " + where);
            break;
        case "live":
            checkClosedRest(surface, data.status, where);
            break;
        case "idle":
            compare(surface.expanded, false);
            compare(surface.closedModel.state, "idle", "idle " + where);
            shown(surface, "closedIdleFace", where);
            break;
        case "peekTrack":
        case "peekPower":
            compare(surface.expanded, false);
            compare(surface.closedModel.state, "peek", "the peek " + where);
            compare(surface.peekKind, data.state === "peekTrack" ? "track" : "power");
            shown(surface, data.state === "peekTrack" ? "peekTrackRow" : "peekPowerRow", where);
            break;
        case "battery":
            compare(surface.expanded, false);
            compare(surface.closedModel.state, "battery", "the battery banner " + where);
            shown(surface, "batteryLabel", where);
            shown(surface, "batteryIcon", where);
            break;
        case "hudInline":
            compare(surface.expanded, false);
            compare(surface.hudStyle, "inline");
            compare(surface.closedModel.state, "hudInline", "the inline readout " + where);
            shown(shown(surface, "hudInline", where), "hudBar", where);
            break;
        case "hudBelow":
            compare(surface.hudStyle, "below");
            verify(surface.hudActive, "the readout is active " + where);
            shown(shown(surface, "hudBelow", where), "hudBar", where);
            checkClosedRest(surface, data.status, where);
            break;
        }
    }

    // Every island state, playing and paused, with and without GPU effects.
    function test_islandContentMovesBetweenWindows_data() {
        var states = ["home", "shelf", "lyrics", "batteryPopover", "hudOpen", "live", "idle",
            "peekTrack", "peekPower", "battery", "hudInline", "hudBelow"];
        var rows = [];
        for (var s = 0; s < states.length; ++s)
            for (var g = 0; g < 2; ++g)
                for (var p = 0; p < 2; ++p)
                    rows.push({ tag: states[s] + (g ? "-gpu" : "-software") + (p ? "-paused" : "-playing"),
                        state: states[s], gpu: g === 1, status: p ? "Paused" : "Playing" });
        return rows;
    }
    function test_islandContentMovesBetweenWindows(data) {
        design.gpuEffects = data.gpu;
        facade.selectedEndpoint = endpoint(data.status);
        facade.endpoints = [facade.selectedEndpoint];
        if (data.state === "idle") {
            facade.selectedEndpoint = null;
            facade.endpoints = [];
        }
        if (data.state === "hudBelow")
            facade.fileSettings = Object.assign({}, facade.fileSettings, { hudStyle: "below" });
        var built = build();
        var surface = built.host.surface;
        switch (data.state) {
        case "home":
        case "shelf":
        case "lyrics":
            surface.expandTo(data.state);
            break;
        case "batteryPopover":
            surface.batteryReading = { present: true, onBattery: true, level: 0.42, state: "Discharging" };
            surface.expandTo("home");
            surface.batteryPopoverOpen = true;
            break;
        case "hudOpen":
            surface.expandTo("home");
            sharedHud.show("volume", 0.5, false);
            break;
        case "peekTrack":
            surface.peekKind = "track";
            surface.peekActive = true;
            break;
        case "peekPower":
            surface.peekKind = "power";
            surface.powerKind = "plugged";
            surface.powerLevel = 0.8;
            surface.peekActive = true;
            break;
        case "battery":
            surface.batteryActive = true;
            surface.batteryLevel = 0.2;
            surface.batteryLabel = "On battery";
            break;
        case "hudInline":
        case "hudBelow":
            sharedHud.show("brightness", 0.7, false);
            break;
        }
        waitForRendering(built.host);
        watchForStaleWindows();
        moveThroughWindows(built.host, built.window, 4, function (where) {
            checkIslandState(built.host, data, where);
        });
    }

}
