import QtQuick
import Quickshell
import "package" as Plugin
import "package/qml/Settings.js" as Settings

// Loads the complete installed Panel.qml the way the host does, with the
// fewest host stubs that let every mode build: first bare (no host), then as
// the island over a top bar with a coordinator. The package is imported, not
// loaded by URL, so Quickshell's scanner reaches every file Panel.qml
// imports; a Panel that does not compile fails the whole configuration. run-panel-load.sh fails on
// any QML error or warning in the log, so an unloadable or noisy panel can
// never ship. The coordinator stub carries only values, never behaviour.
ShellRoot {
    id: test
    property int failures: 0
    function check(condition, message) {
        if (!condition) {
            failures++
            console.error("PANEL_LOAD_FAIL " + message)
        }
    }
    QtObject {
        id: coordinator
        property bool panelAllowed: true
        property bool uiAllowed: true
        property bool island: true
        property bool autoShow: true
        property bool hud: true
        property bool peek: false
        property bool power: false
        property bool tint: true
        property bool lyrics: false
        property bool visualizer: true
        property bool reducedMotion: true
        property bool highContrast: false
        property bool lightTheme: false
        property bool remoteArtwork: false
        property bool viewVisible: false
        property bool viewExpanded: false
        property bool islandShowing: false
        property bool islandPointerActive: false
        property bool settingsWindowOpen: false
        property bool onboardingWindowOpen: false
        property bool pinUnavailable: false
        property bool timersEnabled: true
        property bool timersAvailable: true
        // A recording already runs when the island is built, with the
        // privacy indicators off: the first report must still name it.
        property bool recordingShown: true
        property var recordingState: ({ active: true, startedAt: Date.now() - 60000, path: "/tmp/perf.mp4" })
        property var timerList: []
        property var cameraHolders: []
        property var selectedEndpoint: null
        property var endpoints: []
        property var shelfEntries: []
        property var shelfItems: []
        property var shelfActions: null
        property var calendarSource: null
        property var barCentreSpans: ({})
        property var spectrumLevels: []
        property string spectrumState: "off"
        property string selectedLabel: ""
        property string selectionMode: "auto"
        property string pendingAction: ""
        property string actionError: ""
        property string statusText: ""
        property string shelfNotice: ""
        property string sleepFailure: ""
        property double sleepDeadline: 0
        property real positionSeconds: 0
        property var fileSettings: Settings.resolve({ privacyIndicators: false })
        property var settings: ({})
        // Written by the Panel's Bindings, as on the Service.
        property real bodyFontSize: 0
        property string islandScreenName: ""
        property real spectrumBarSpan: 0
        property bool hudSuppressed: false
        property string hudHeldKind: ""
        property bool spectrumPaused: false
        signal hudEvent(string kind, real level, bool muted)
        signal timerFinished(string label)
        signal captureShelved(string kind, string path)
        // What status() would report, as the Service stores it.
        property string reportedActivity: "unset"
        property var reportedPrivacy: null
        function reportActivity(key, privacy) {
            reportedActivity = String(key || "")
            reportedPrivacy = privacy
        }
        function retainArtwork(paths) {}
        function setBrightnessLevel(value) {}
        function captureIntent() { return null }
    }
    QtObject {
        id: hostShell
        property var bar: QtObject {
            property string position: "top"
            property bool barHidden: false
            property int barSize: 26
            property var layoutConfig: ({ left: [], center: [{ id: "io.github.bavanchun.nookisle" }], right: [] })
        }
        property var barConfig: ({ layout: { left: [], center: [{ id: "io.github.bavanchun.nookisle" }], right: [] } })
        function serviceFor(id) { return id === "io.github.bavanchun.nookisle" ? coordinator : null }
    }
    Component {
        id: panelComponent
        Plugin.Panel {}
    }
    property var bare: null
    property var island: null
    Timer {
        interval: 50
        running: true
        onTriggered: {
            var component = panelComponent
            test.check(component.status === Component.Ready, "Panel.qml compiles: " + component.errorString())
            if (component.status !== Component.Ready) { test.finish(); return }
            test.bare = component.createObject(null, {})
            test.check(!!test.bare, "Panel builds without a host: " + component.status + " " + component.errorString())
            test.island = component.createObject(null, { shell: hostShell })
            test.check(!!test.island, "Panel builds as the island")
            test.check(test.island && test.island.islandMode === true, "the island mode is on over a top bar")
            settle.start()
        }
    }
    // Long enough for Loaders, deferred calls and the first frames. Then
    // the mode switches: status() follows the mode the panel shows.
    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            test.check(coordinator.reportedActivity === "recording|",
                "the island built with a recording reports it: " + coordinator.reportedActivity)
            test.check(coordinator.reportedPrivacy === null, "no privacy state with the indicators off")
            hostShell.bar.position = "bottom"
            legacy.start()
        }
    }
    Timer {
        id: legacy
        interval: 500
        onTriggered: {
            test.check(test.island.islandMode === false, "a bottom bar leaves island mode")
            test.check(coordinator.reportedActivity === "", "legacy mode shows no activity: " + coordinator.reportedActivity)
            hostShell.bar.position = "top"
            back.start()
        }
    }
    Timer {
        id: back
        interval: 500
        onTriggered: {
            test.check(test.island.islandMode === true, "a top bar brings the island back")
            test.check(coordinator.reportedActivity === "recording|", "and its activity again: " + coordinator.reportedActivity)
            test.finish()
        }
    }
    function finish() {
        if (test.island) test.island.destroy()
        if (test.bare) test.bare.destroy()
        console.log("PANEL_LOAD_RESULT failures=" + test.failures)
        Qt.callLater(Qt.quit)
    }
}
