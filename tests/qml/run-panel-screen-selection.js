#!/usr/bin/env node
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, resolve, dirname} from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const source = readFileSync(join(repository, "Panel.qml"), "utf8");
function section(start, end) {
    const begin = source.indexOf(start), finish = source.indexOf(end, begin);
    if (begin < 0 || finish < 0) throw new Error("Production Panel screen contract not found");
    return source.slice(begin, finish);
}
// Exercise production bindings and handlers, not a copied selection engine.
// Only the compositor inventory is supplied; no native window is created.
const binding = section("    property string chosenScreenName:", "    readonly property var monitor:")
    .replaceAll("Quickshell.screens", "testScreens")
    .replaceAll("Hyprland.focusedMonitor", "testFocusedMonitor");
const handler = section(source.includes("    function rememberTargetScreen()")
    ? "    function rememberTargetScreen()" : "    onTargetScreenChanged:", "    onArtworkPathChanged:");
const visibilityBindings = section("    readonly property bool surfaceVisible:", "    readonly property string artworkPath:");
// Stops before onIslandModeChanged: the handlers from there on reference
// windowScreen/fullscreen island-only triggers this legacy-only fixture does
// not stub. islandSurfaceConnections below carries the one handler
// (Connections{target:root.surface}) the island fixture actually needs.
const visibilityHandlers = section("    function settleOrAnimate()", "    onIslandModeChanged:");
// Island mode's own screen choice: a separate, non-reactive binding that
// moves only while collapsed (plan Decisions, "Multi-monitor"), unlike the
// legacy targetScreen binding above.
const islandModeBinding = section("    readonly property bool islandMode:", "    property bool opened:");
const islandScreenSection = section("    property string islandScreenName:", "    readonly property var windowScreen:")
    .replaceAll("Quickshell.screens", "testScreens")
    .replaceAll("Hyprland.focusedMonitor", "testFocusedMonitor");
// The extra windows' screens with displayMode "all".
const extraScreensBinding = section("    readonly property var extraScreens:", "    Variants {")
    .replaceAll("Quickshell.screens", "testScreens");
const islandOpenClose = section("    function open(payloadJson)", "    function toggleExpanded()");
// Self-contained: only reads/writes root and surface, no bare `contentLoader`
// id like the legacy onExpandedChanged handler that visibilityHandlers carries.
const islandSurfaceConnections = section("    Connections {\n        target: root.surface", "    function rememberTargetScreen()");
// The layer's keyboard focus, with every Panel handler that can end a
// summon: the island must never hold the keyboard exclusively once it is
// hidden or collapsed, and a hover open must never take it.
const panelAllowedBinding = section("    readonly property bool panelAllowed:", "    readonly property var hostBar:");
const islandVisibility = section("    readonly property bool surfaceVisible:", "    readonly property bool motionAllowed:");
const allowedHandler = section("    onPanelAllowedChanged:", "    onExpandedChanged:");
const islandHandlers = section("    onIslandModeChanged:", "    Connections {\n        target: Hyprland");
const focusBinding = section("        readonly property string focusMode:", "        mask: Region")
    .replace("WlrLayershell.keyboardFocus:", "property int keyboardFocus:")
    .replaceAll("WlrKeyboardFocus.", "wlrFocus.");
// The fullscreen value a held HUD drag latches until its release.
const fullscreenLatch = section("    readonly property bool hudHeld:", "    readonly property bool surfaceVisible:");
const directory = mkdtempSync(join(tmpdir(), "nookisle-screen-test-"));
try {
    const path = join(directory, "tst-screen.qml");
    writeFileSync(path, `import QtQuick
import QtTest
import "${join(repository, "qml/IslandKeys.js")}" as IslandKeys
import "${join(repository, "qml/Displays.js")}" as Displays
TestCase {
    id: test
    name: "ProductionPanelScreenSelection"
    QtObject { id: morph; property int stops: 0; function stop() { stops++; } }
    Component {
        id: selectionComponent
        Item {
            id: root
            property var testScreens: []
            property var testFocusedMonitor: null
            property bool expanded: false
            property real expansion: 0
${binding}
${handler}
        }
    }
    Component {
        id: visibilityComponent
        Item {
            id: root
            property bool opened: false
            property bool expanded: false
            property bool dismissed: false
            property bool explicitOpen: false
            property real expansion: 0
            property bool panelAllowed: true
            property bool fullscreen: false
            property var targetScreen: ({name: "A"})
            property string chosenScreenName: "A"
            property real anchorLeftX: -1
            property real anchorCenterX: -1
            // islandMode stays false here: this fixture only exercises the
            // legacy visibility contract. surface is a stub so the sliced
            // legacy handlers (which touch it only behind an "islandMode"
            // guard that is always false here) never dereference a real one.
            property bool islandMode: false
            property QtObject coordinator: QtObject {
                property bool viewVisible: false
                property bool viewExpanded: false
            }
            QtObject { id: palette; property bool reducedMotion: true }
            QtObject {
                id: morph
                property real to: 0
                function stop() {}
                function start() { root.expansion = to }
            }
            Item { id: contentLoader; property Item item: Item {} }
            QtObject { id: panel; property bool keyboardLent: false }
            // Panel reads the island surface as root.surface.
            readonly property var surface: surfaceObject
            QtObject {
                id: surfaceObject
                property bool expanded: false
                function expandTo(target) { expanded = true }
                function collapse() { expanded = false }
                function resetForHost() { collapse() }
                function forceActiveFocus() {}
            }
${visibilityBindings}
${visibilityHandlers}
        }
    }
    Component {
        id: islandSelectionComponent
        Item {
            id: root
            property var testScreens: []
            property var testFocusedMonitor: null
            property bool panelAllowed: true
            property bool opened: false
            property bool explicitOpen: false
            property bool dismissed: false
            property string chosenScreenName: ""
            property real anchorLeftX: -1
            property real anchorCenterX: -1
            property QtObject coordinator: QtObject { property bool island: true; property bool autoShow: true }
            property QtObject hostBar: QtObject { property string position: "top"; property bool barHidden: false }
            // The display settings, as Panel reads them from the file store.
            property string displayMode: "follow"
            property string preferredDisplay: ""
            readonly property bool allDisplays: root.islandMode && displayMode === "all"
            readonly property alias surfaceStub: surfaceObject
            // Screen selection is this fixture's only concern; syncSubscription
            // (called from islandSurfaceConnections) has no
            // subscription state to reconcile here.
            function syncSubscription() {}
            QtObject { id: panel; property bool keyboardLent: false }
            // Panel reads the island surface as root.surface.
            readonly property var surface: surfaceObject
            QtObject {
                id: surfaceObject
                property bool expanded: false
                property string view: "home"
                property int expandToCalls: 0
                property int collapseCalls: 0
                property int forceActiveFocusCalls: 0
                property int focusContentCalls: 0
                signal collapseRequested()
                signal settingsOpened()
                function expandTo(target) { view = target; expanded = true; expandToCalls++ }
                function collapse() { expanded = false; collapseCalls++; collapseRequested() }
                function resetForHost() { collapse() }
                function forceActiveFocus() { forceActiveFocusCalls++ }
                function focusContent() { focusContentCalls++ }
                function focusKeys() {}
                function scheduleAutoClose(ms) {}
                function cancelAutoClose() {}
            }
${islandModeBinding}
${islandScreenSection}
${extraScreensBinding}
${islandOpenClose}
${islandSurfaceConnections}
        }
    }
    Component {
        id: islandFocusComponent
        Item {
            id: root
            property QtObject coordinator: QtObject {
                property bool island: true
                property bool autoShow: true
                property bool panelAllowed: true
                property bool viewVisible: false
                property bool viewExpanded: false
                property bool settingsWindowOpen: false
                property bool onboardingWindowOpen: false
            }
            property QtObject hostBar: QtObject { property string position: "top"; property bool barHidden: false }
            property bool opened: false
            property bool expanded: false
            property bool dismissed: false
            property bool explicitOpen: false
            property real expansion: 0
            property bool fullscreen: false
            property var targetScreen: ({name: "A"})
            property var windowScreen: ({name: "A"})
            property string chosenScreenName: ""
            property real anchorLeftX: -1
            property real anchorCenterX: -1
            property bool pendingScreenMove: false
            property int screenMoves: 0
            readonly property alias surfaceStub: surfaceObject
            readonly property alias window: panel
            function applyIslandScreen() { screenMoves++ }
            function syncSubscription() {}
            QtObject { id: morph; function stop() {} }
            readonly property var wlrFocus: ({None: 0, OnDemand: 1, Exclusive: 2})
            // Panel reads the island surface as root.surface.
            readonly property var surface: surfaceObject
            QtObject {
                id: surfaceObject
                property bool expanded: false
                property string view: "home"
                signal collapseRequested()
                signal settingsOpened()
                // The surface's close guard contract: collapse() refuses
                // while busy unless forced (Escape); resetForHost() is the
                // host's safety reset, which drops every hold and closes.
                property int busyCount: 0
                property int hostResets: 0
                function beginBusy() { busyCount++ }
                function expandTo(target) { view = target; expanded = true }
                function collapse(force) {
                    if (force !== true && busyCount > 0) return false
                    expanded = false
                    collapseRequested()
                    return true
                }
                function resetForHost() { busyCount = 0; hostResets++; return collapse(true) }
                function focusKeys() {}
                function scheduleAutoClose(ms) {}
                function cancelAutoClose() {}
            }
            QtObject {
                id: panel
                property bool visible: root.activeVisible
${focusBinding}
            }
${panelAllowedBinding}
${islandModeBinding}
${islandVisibility}
${islandOpenClose}
${allowedHandler}
${islandHandlers}
${islandSurfaceConnections}
        }
    }
    function summoned() {
        var panel = createTemporaryObject(islandFocusComponent, test)
        compare(panel.islandMode, true)
        compare(panel.window.keyboardFocus, 0, "a collapsed island never holds the keyboard")
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "a summoned, shown island takes the keyboard exclusively")
        return panel
    }
    // Each way a summon can end must drop the exclusive grab at once, with
    // no deferred step that could leave a hidden or collapsed layer holding
    // the user's keyboard.
    function test_islandReleasesKeyboard_data() {
        return [{tag: "escape-or-view-close"}, {tag: "host-close"}, {tag: "lock"}, {tag: "island-off"},
            {tag: "screen-move"}, {tag: "screen-lost"}, {tag: "bar-hidden"}, {tag: "service-gone"}]
    }
    function test_islandReleasesKeyboard(data) {
        var panel = summoned()
        if (data.tag === "escape-or-view-close") panel.surfaceStub.collapse()
        else if (data.tag === "host-close") panel.close()
        else if (data.tag === "lock") panel.coordinator.panelAllowed = false
        else if (data.tag === "island-off") panel.coordinator.island = false
        else if (data.tag === "screen-move") panel.windowScreen = {name: "B"}
        else if (data.tag === "screen-lost") panel.windowScreen = null
        else if (data.tag === "bar-hidden") panel.hostBar.barHidden = true
        else if (data.tag === "service-gone") panel.coordinator = null
        compare(panel.window.keyboardFocus, 0)
        compare(panel.explicitOpen, false, "the summon itself ended")
        compare(panel.surfaceStub.expanded, false)
    }
    // The settings and welcome windows need the keyboard: while either is
    // open, a summoned island stays open but gives up its exclusive grab,
    // and takes it back when the window closes.
    function test_islandLendsKeyboardToItsWindows_data() {
        return [{tag: "settings", flag: "settingsWindowOpen"}, {tag: "welcome", flag: "onboardingWindowOpen"}]
    }
    function test_islandLendsKeyboardToItsWindows(data) {
        var panel = summoned()
        panel.coordinator[data.flag] = true
        compare(panel.window.keyboardFocus, 0, "the window gets the keyboard")
        compare(panel.explicitOpen, true, "the island stays summoned")
        compare(panel.surfaceStub.expanded, true)
        panel.coordinator[data.flag] = false
        compare(panel.window.keyboardFocus, 2, "closing the window returns the keyboard to the island")
    }
    // A window left open before the summon, perhaps on another workspace,
    // is not lent the keyboard: the summon holds it, and a later summon
    // takes it back from a window that was lent it.
    function test_summonTakesKeyboardFromAnOpenWindow_data() {
        return [{tag: "settings", flag: "settingsWindowOpen"}, {tag: "welcome", flag: "onboardingWindowOpen"}]
    }
    function test_summonTakesKeyboardFromAnOpenWindow(data) {
        var panel = createTemporaryObject(islandFocusComponent, test)
        panel.coordinator[data.flag] = true
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "the summoned island holds the keyboard")
        panel.coordinator[data.flag] = false
        panel.coordinator[data.flag] = true
        compare(panel.window.keyboardFocus, 0, "a window opened from the summoned island is lent it")
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "summoning again takes it back")
        panel.close()
        compare(panel.window.keyboardFocus, 0)
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "a fresh summon ignores the window still open")
    }
    // The gear lends the keyboard to the settings window even when it was
    // already open (nothing about the window changes); a summon still takes
    // it back, and closing the window returns it.
    function test_gearLendsKeyboardToAnAlreadyOpenSettingsWindow() {
        var panel = createTemporaryObject(islandFocusComponent, test)
        panel.coordinator.settingsWindowOpen = true
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "the summon holds the keyboard over the open window")
        panel.surfaceStub.settingsOpened()
        compare(panel.window.keyboardFocus, 0, "the gear hands it to the settings window")
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "a later summon takes it back")
        panel.surfaceStub.settingsOpened()
        panel.coordinator.settingsWindowOpen = false
        compare(panel.window.keyboardFocus, 2, "closing the window returns it to the island")
    }
    // Fullscreen keeps a summoned island on screen (and so its grab); a
    // fullscreen that starts while it is only hover-open collapses it.
    function test_islandFullscreenKeepsOnlyAVisibleSummon() {
        var panel = summoned()
        panel.fullscreen = true
        compare(panel.window.visible, true)
        compare(panel.window.keyboardFocus, 2)
        panel.close()
        compare(panel.window.visible, false)
        compare(panel.window.keyboardFocus, 0)
        panel.fullscreen = false
        panel.surfaceStub.expandTo("home")
        panel.fullscreen = true
        compare(panel.surfaceStub.expanded, false)
        compare(panel.window.keyboardFocus, 0)
    }
    // Host safety resets bypass the close guard: a lock or panel disallow,
    // leaving island mode, a screen change and fullscreen all close the
    // island and clear its busy count, so it never shows over a lock screen
    // or carries a menu's hold to another mode or screen.
    function test_islandHostResetsBypassTheCloseGuard_data() {
        return [{tag: "lock"}, {tag: "island-off"}, {tag: "bar-hidden"}, {tag: "service-gone"},
            {tag: "screen-move"}, {tag: "screen-lost"}, {tag: "fullscreen"}]
    }
    function test_islandHostResetsBypassTheCloseGuard(data) {
        var panel = createTemporaryObject(islandFocusComponent, test)
        // Fullscreen closes only an island the user did not summon.
        if (data.tag === "fullscreen") panel.surfaceStub.expandTo("home")
        else panel.open("{}")
        var resets = panel.surfaceStub.hostResets
        panel.surfaceStub.beginBusy()
        panel.surfaceStub.beginBusy()
        compare(panel.surfaceStub.expanded, true)
        if (data.tag === "lock") panel.coordinator.panelAllowed = false
        else if (data.tag === "island-off") panel.coordinator.island = false
        else if (data.tag === "bar-hidden") panel.hostBar.barHidden = true
        else if (data.tag === "service-gone") panel.coordinator = null
        else if (data.tag === "screen-move") panel.windowScreen = {name: "B"}
        else if (data.tag === "screen-lost") panel.windowScreen = null
        else if (data.tag === "fullscreen") panel.fullscreen = true
        compare(panel.surfaceStub.expanded, false, "the host reset closes a busy island")
        compare(panel.surfaceStub.busyCount, 0, "and clears its busy count")
        verify(panel.surfaceStub.hostResets > resets, "through the host reset")
        compare(panel.window.keyboardFocus, 0)
    }
    // Ordinary closes still wait for the hold to end.
    function test_islandOrdinaryCloseRespectsTheGuard() {
        var panel = summoned()
        // Building the fixture settles its bindings through one reset; count from here.
        var resets = panel.surfaceStub.hostResets
        panel.surfaceStub.beginBusy()
        panel.close()
        compare(panel.surfaceStub.expanded, true, "a host close waits while busy")
        compare(panel.explicitOpen, true)
        compare(panel.surfaceStub.collapse(), false, "a plain collapse is refused while busy")
        compare(panel.surfaceStub.expanded, true)
        compare(panel.surfaceStub.busyCount, 1)
        compare(panel.surfaceStub.hostResets, resets, "no host reset ran")
    }
    function test_islandHoverNeverTakesKeyboard() {
        var panel = createTemporaryObject(islandFocusComponent, test)
        panel.surfaceStub.expandTo("home")
        compare(panel.window.visible, true)
        compare(panel.window.keyboardFocus, 0, "a hover open never takes the keyboard")
        panel.open("{}")
        compare(panel.window.keyboardFocus, 2, "a summon over a hover open takes it")
        panel.surfaceStub.collapse()
        panel.surfaceStub.expandTo("shelf")
        compare(panel.explicitOpen, false)
        compare(panel.window.keyboardFocus, 0, "a hover open after a summon ended does not inherit the grab")
    }
    // A summon that arrives while the panel is not allowed (locked, or the
    // lock state not yet known) is refused, so it cannot surface later and
    // take the keyboard the moment the screen unlocks.
    function test_islandSummonWhileNotAllowedIsRefused() {
        var panel = createTemporaryObject(islandFocusComponent, test)
        panel.coordinator.panelAllowed = false
        panel.open("{}")
        compare(panel.explicitOpen, false)
        compare(panel.surfaceStub.expanded, false)
        panel.coordinator.panelAllowed = true
        compare(panel.window.visible, true)
        compare(panel.window.keyboardFocus, 0)
    }
    function test_legacyPanelKeepsOnDemandFocus() {
        var panel = createTemporaryObject(islandFocusComponent, test)
        panel.coordinator.island = false
        panel.open("{}")
        compare(panel.window.keyboardFocus, 1)
        panel.close()
        compare(panel.window.keyboardFocus, 0)
    }
    function test_visibilityClosesSynchronously_data() {
        return [{tag: "normal-close", full: false, locked: false},
            {tag: "fullscreen-close", full: true, locked: false},
            {tag: "lock", full: false, locked: true}]
    }
    function test_visibilityClosesSynchronously(data) {
        var panel = createTemporaryObject(visibilityComponent, test)
        panel.fullscreen = data.full
        panel.open("{}")
        compare(panel.surfaceVisible, true)
        compare(panel.coordinator.viewVisible, true)
        compare(panel.coordinator.viewExpanded, true)
        if (data.locked) panel.panelAllowed = false
        else panel.close()
        compare(panel.surfaceVisible, false)
        compare(panel.expanded, false)
        compare(panel.opened, false)
        compare(panel.expansion, 0)
        compare(panel.coordinator.viewVisible, false)
        compare(panel.coordinator.viewExpanded, false)
    }
    function test_retainsChoiceWithoutSynchronousBindingFeedback() {
        var panel = createTemporaryObject(selectionComponent, test)
        var first = {name: "A"}, second = {name: "B"}
        panel.testFocusedMonitor = first
        panel.testScreens = [first, second]
        compare(panel.targetScreen.name, "A")
        compare(panel.chosenScreenName, "")
        tryCompare(panel, "chosenScreenName", "A")
        panel.expanded = true
        panel.expansion = 1
        panel.testFocusedMonitor = second
        compare(panel.targetScreen.name, "A")
        compare(panel.expanded, true)
        panel.testScreens = [second]
        compare(panel.targetScreen.name, "B")
        compare(panel.expanded, false)
        compare(panel.expansion, 0)
        compare(panel.chosenScreenName, "A")
        tryCompare(panel, "chosenScreenName", "B")
    }
    function test_rapidRemovalOnlyRetainsCurrentTarget() {
        var panel = createTemporaryObject(selectionComponent, test)
        panel.testScreens = [{name: "A"}]
        panel.testScreens = [{name: "B"}]
        panel.testScreens = [{name: "C"}]
        compare(panel.chosenScreenName, "")
        tryCompare(panel, "chosenScreenName", "C")
        panel.expanded = true
        panel.expansion = 0.7
        panel.testScreens = []
        compare(panel.targetScreen, null)
        compare(panel.expanded, false)
        compare(panel.expansion, 0)
        panel.testScreens = [{name: "D"}]
        tryCompare(panel, "chosenScreenName", "D")
        compare(panel.targetScreen.name, "D")
    }
    function test_islandFocusMovesWhileCollapsed() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        var first = {name: "A"}, second = {name: "B"}
        panel.testScreens = [first, second]
        panel.testFocusedMonitor = first
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "A")
        panel.testFocusedMonitor = second
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "B")
        compare(panel.islandTargetScreen.name, "B")
    }
    function test_islandMoveDeferredWhileExpandedThenAppliedOnCollapse() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        var first = {name: "A"}, second = {name: "B"}
        panel.testScreens = [first, second]
        panel.testFocusedMonitor = first
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "A")
        panel.surfaceStub.expandTo("home")
        panel.testFocusedMonitor = second
        panel.applyIslandScreen()
        compare(panel.pendingScreenMove, true)
        compare(panel.islandScreenName, "A")
        panel.surfaceStub.collapse()
        compare(panel.islandScreenName, "B")
        compare(panel.pendingScreenMove, false)
    }
    function test_islandNoFocusedMonitorFallsBackToFirstScreen() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        panel.testScreens = [{name: "X"}, {name: "Y"}]
        panel.testFocusedMonitor = null
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "X")
        compare(panel.islandTargetScreen.name, "X")
    }
    // Fixed stays on preferredDisplay whatever has focus, and follows focus
    // while that screen is missing, returning when it comes back.
    function test_fixedDisplay() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        var a = {name: "A"}, b = {name: "B"}
        panel.testScreens = [a, b]
        panel.testFocusedMonitor = a
        panel.displayMode = "fixed"
        panel.preferredDisplay = "B"
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "B")
        panel.testFocusedMonitor = b
        panel.applyIslandScreen()
        panel.testFocusedMonitor = a
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "B", "focus never moves it")
        panel.testScreens = [a]
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "A", "a missing screen falls back to follow")
        panel.testScreens = [a, b]
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "B", "and it returns when the screen does")
        compare(panel.extraScreens, [], "one island only")
    }
    // All: the primary stays on one screen and every other screen gets a
    // window, following screens as they come and go.
    function test_allDisplays() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        var a = {name: "A"}, b = {name: "B"}, c = {name: "C"}
        panel.testScreens = [a, b, c]
        panel.testFocusedMonitor = b
        panel.displayMode = "all"
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "A", "the primary does not follow focus")
        compare(panel.extraScreens.map(screen => screen.name), ["B", "C"])
        panel.testFocusedMonitor = c
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "A")
        panel.testScreens = [a, b]
        panel.applyIslandScreen()
        compare(panel.extraScreens.map(screen => screen.name), ["B"], "a removed screen loses its window")
        var d = {name: "D"}
        panel.testScreens = [a, b, d]
        panel.applyIslandScreen()
        compare(panel.extraScreens.map(screen => screen.name), ["B", "D"], "an added screen gets one")
        panel.preferredDisplay = "D"
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "D", "preferredDisplay picks the primary")
        compare(panel.extraScreens.map(screen => screen.name), ["A", "B"])
        panel.testScreens = [b, d]
        panel.preferredDisplay = ""
        panel.applyIslandScreen()
        compare(panel.islandScreenName, "B", "without it, the first screen")
        compare(panel.extraScreens.map(screen => screen.name), ["D"])
        panel.testFocusedMonitor = d
        panel.displayMode = "follow"
        panel.applyIslandScreen()
        compare(panel.extraScreens, [], "follow has one island")
        compare(panel.islandScreenName, "D", "on the focused screen")
    }
    function test_islandModeFalseForNonTopOrHiddenBar_data() {
        return [{tag: "bottom-bar", position: "bottom", hidden: false},
            {tag: "hidden-bar", position: "top", hidden: true}]
    }
    function test_islandModeFalseForNonTopOrHiddenBar(data) {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        compare(panel.islandMode, true)
        panel.hostBar.position = data.position
        panel.hostBar.barHidden = data.hidden
        compare(panel.islandMode, false)
    }
    function test_islandSurfaceExpansionMirrorsOpened() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        compare(panel.islandMode, true)
        compare(panel.opened, false)
        panel.surfaceStub.expandTo("home")
        compare(panel.opened, true)
        panel.surfaceStub.collapse()
        compare(panel.opened, false)
    }
    Component {
        id: fullscreenLatchComponent
        Item {
            id: root
            property bool fullscreenNow: false
            property alias held: hudModel.held
            QtObject { id: hudModel; property bool held: false }
            // Only the primary's own held bar latches its fullscreen.
            property alias heldHere: surfaceObject.ownBar
            // Panel reads the island surface as root.surface.
            readonly property var surface: surfaceObject
            QtObject {
                id: surfaceObject
                property bool ownBar: true
                readonly property bool hudHeldHere: hudModel.held && ownBar
            }
${fullscreenLatch}
        }
    }
    // A held HUD drag keeps the fullscreen value it started with, so a
    // fullscreen flip mid-drag never hides the bar under the pointer; the
    // policy applies again on release.
    function test_heldDragLatchesFullscreen() {
        var panel = createTemporaryObject(fullscreenLatchComponent, test)
        compare(panel.fullscreen, false)
        panel.fullscreenNow = true
        compare(panel.fullscreen, true, "unheld, it follows the policy")
        panel.fullscreenNow = false
        compare(panel.fullscreen, false)
        panel.held = true
        panel.fullscreenNow = true
        compare(panel.fullscreen, false, "held, a flip waits")
        panel.held = false
        compare(panel.fullscreen, true, "and applies on release")
        panel.held = true
        panel.fullscreenNow = false
        compare(panel.fullscreen, true, "either way")
        panel.held = false
        compare(panel.fullscreen, false)
    }
    // With an island on every screen, a bar held on another island leaves
    // this window's fullscreen policy free: it hides over its own screen's
    // fullscreen client at once.
    function test_barHeldElsewhereDoesNotLatch() {
        var panel = createTemporaryObject(fullscreenLatchComponent, test)
        panel.heldHere = false
        panel.held = true
        panel.fullscreenNow = true
        compare(panel.fullscreen, true, "held on another island: the flip applies")
    }
    function test_islandCloseCollapsesSurfaceAndClearsExplicitOpen() {
        var panel = createTemporaryObject(islandSelectionComponent, test)
        panel.open("{}")
        compare(panel.explicitOpen, true)
        compare(panel.surfaceStub.expandToCalls, 1)
        compare(panel.opened, true)
        panel.close()
        compare(panel.explicitOpen, false)
        compare(panel.surfaceStub.collapseCalls, 1)
        compare(panel.opened, false)
    }
}
`);
    const environment = {...process.env, QT_QPA_PLATFORM: "offscreen",
        QT_QPA_PLATFORMTHEME: "generic", NO_AT_BRIDGE: "1", QML_DISABLE_DISK_CACHE: "1"};
    delete environment.DISPLAY;
    delete environment.WAYLAND_DISPLAY;
    delete environment.HYPRLAND_INSTANCE_SIGNATURE;
    const result = spawnSync("dbus-run-session", ["--config-file=" + join(repository, "tests/qml/session-bus.conf"),
        "--", process.argv[2] || "/usr/lib/qt6/bin/qmltestrunner", "-input", path],
        {env: environment, encoding: "utf8", timeout: 15000});
    process.stdout.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    if (result.error) throw result.error;
    process.exitCode = result.status === 0 && !/Binding loop|TypeError|ReferenceError/.test(
        (result.stdout || "") + (result.stderr || "")) ? 0 : 1;
} finally {
    rmSync(directory, {recursive: true, force: true});
}
