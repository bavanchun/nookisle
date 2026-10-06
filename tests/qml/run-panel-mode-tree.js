#!/usr/bin/env node
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, resolve, dirname} from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const source = readFileSync(join(repository, "Panel.qml"), "utf8");
function section(text, start, end, what) {
    const begin = text.indexOf(start), finish = text.indexOf(end, begin);
    if (begin < 0 || finish < 0) throw new Error(`${what} not found`);
    return text.slice(begin, finish);
}
// Panel's real window content (the legacy card and the island surface
// Loader) and its inert stand-in: only the current mode's tree may exist, and
// a live switch in either direction releases the other tree's focus and camera.
const content = section(source, "        Rectangle {\n            id: card", "\n    }\n}", "Production Panel window content");
const inert = section(source, "    readonly property var surface:", "    DesignTokens {\n        id: palette", "Production Panel inert surface");
// The island surface suite's coordinator facade, shared rather than copied.
const surfaceSuite = readFileSync(join(repository, "tests/qml/tst-island-surface.qml"), "utf8");
const facade = section(surfaceSuite, "    QtObject {\n        id: facade", "    // Shaped like LyricsSource", "Island surface facade");
const directory = mkdtempSync(join(tmpdir(), "nookisle-mode-tree-test-"));
try {
    const path = join(directory, "tst-mode-tree.qml");
    writeFileSync(path, `pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "file:${join(repository, "components")}"
import "file:${join(repository, "qml/Displays.js")}" as Displays
import "file:${join(repository, "qml/Settings.js")}" as Settings
TestCase {
    id: test
    name: "ProductionPanelModeTree"
    width: 760
    height: 420
    visible: true
    when: windowShown
${facade}
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
        id: panelComponent
        Item {
            id: root
            width: 760
            height: 420
            property bool islandMode: true
            property real expansion: 1
            property bool expanded: false
            property real expandedWidth: 420
            property real compactWidth: 300
            property var coordinator: facade
            property bool panelAllowed: true
            property bool explicitOpen: false
            property bool fullscreen: false
            property real islandAvailableWidth: Infinity
            property var hostBar: null
            property bool allDisplays: false
            property string primaryScreenName: ""
            property string spectrumOwner: ""
            property var islandTargetScreen: null
            property string cameraOwner: ""
            property string sourceAppIcon: ""
            property bool shelfDropInSupported: true
            property bool shelfDragOutSupported: true
            property bool barCentreShared: false
            property real barCentreSpan: -1
            property var lyricsSource: null
            function toggleExpanded() {}
            function close() {}
            function setHudLevel(kind, value) {}
            DesignTokens { id: palette; reducedMotion: true }
            Item { id: panel; anchors.fill: parent }
            HudModel { id: hudModel }
            QtObject {
                id: batteryModel
                property bool bannerActive: false
                property real bannerLevel: 0
                property string bannerLabel: ""
                property var reading: ({ present: false, onBattery: false, level: 0, state: "Unknown" })
            }
            QtObject { id: powerLoader; property var item: null }
            QtObject { id: privacyLoader; property var item: null }
            QtObject {
                id: peekModel
                property bool active: false
                property var event: null
                property string kind: "track"
                property string powerKind: "plugged"
                property real powerLevel: 0
            }
${inert}
${content}
            readonly property var legacyLoader: contentLoader
            readonly property var islandLoader: surfaceLoader
        }
    }
    function inside(item, ancestor) {
        for (var node = item; node; node = node.parent)
            if (node === ancestor) return true;
        return false;
    }
    function test_onlyTheCurrentModesTreeExists() {
        var panel = createTemporaryObject(panelComponent, test);
        verify(panel.islandLoader.item, "island mode builds the surface");
        compare(panel.legacyLoader.item, null, "and no legacy panel");
        compare(panel.surface, panel.islandLoader.item);
        panel.islandMode = false;
        compare(panel.islandLoader.item, null, "legacy mode builds no island surface");
        verify(panel.legacyLoader.item, "but its own panel");
        compare(panel.surface.expanded, false, "the stand-in reads as a closed island");
        compare(panel.surface.interactive, false);
        compare(panel.surface.settings.hudDuration, Settings.resolve(facade.fileSettings).hudDuration,
            "with the same resolved settings");
        panel.islandMode = true;
        verify(panel.islandLoader.item, "the surface comes back with island mode");
        compare(panel.legacyLoader.item, null);
    }
    // Leaving island mode while the island is open on Home, with the mirror on
    // and the keys on the island, releases the camera and the keyboard focus.
    function test_islandToLegacyReleasesCameraAndFocus() {
        facade.fileSettings = ({ showMirror: true });
        cameraCreations = 0;
        cameraDestructions = 0;
        var panel = createTemporaryObject(panelComponent, test);
        var surface = panel.surface;
        surface.cameraSource = fakeCamera;
        surface.expandTo("home");
        tryCompare(surface, "openSettled", true, 2000);
        tryCompare(test, "cameraCreations", 1, 2000);
        surface.focusKeys();
        verify(inside(panel.Window.activeFocusItem, surface), "the island holds the keys");
        panel.islandMode = false;
        tryCompare(test, "cameraDestructions", 1, 1000);
        compare(panel.islandLoader.item, null);
        verify(!inside(panel.Window.activeFocusItem, panel.islandLoader), "no focus is left in the unloaded island");
        facade.fileSettings = ({});
    }
    // Entering island mode from the legacy panel builds a closed island that
    // takes the keys when summoned, and drops the legacy panel's focus.
    function test_legacyToIslandBuildsAClosedIslandThatTakesFocus() {
        var panel = createTemporaryObject(panelComponent, test, { islandMode: false });
        compare(panel.islandLoader.item, null);
        var legacy = panel.legacyLoader.item;
        legacy.forceActiveFocus();
        verify(inside(panel.Window.activeFocusItem, panel.legacyLoader), "the legacy panel holds the keys");
        panel.islandMode = true;
        compare(panel.legacyLoader.item, null, "the legacy panel is gone");
        verify(!inside(panel.Window.activeFocusItem, panel.legacyLoader));
        var surface = panel.surface;
        verify(surface && surface === panel.islandLoader.item);
        compare(surface.expanded, false, "the new island starts closed");
        surface.expandTo("home");
        surface.focusKeys();
        verify(inside(panel.Window.activeFocusItem, surface), "and takes the keys when summoned");
    }
}
`);
    const environment = {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
        QT_QPA_PLATFORMTHEME: "generic", NO_AT_BRIDGE: "1", QML_DISABLE_DISK_CACHE: "1"};
    delete environment.DISPLAY;
    delete environment.WAYLAND_DISPLAY;
    const result = spawnSync("dbus-run-session", ["--config-file=" + join(repository, "tests/qml/session-bus.conf"),
        "--", process.argv[2] || "/usr/lib/qt6/bin/qmltestrunner", "-input", path],
        {env: environment, encoding: "utf8", timeout: 30000});
    process.stdout.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    if (result.error) throw result.error;
    process.exitCode = result.status === 0 && !/Binding loop|TypeError|ReferenceError/.test(
        (result.stdout || "") + (result.stderr || "")) ? 0 : 1;
} finally {
    rmSync(directory, {recursive: true, force: true});
}
