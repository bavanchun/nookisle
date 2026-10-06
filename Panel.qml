pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "components"
import "qml/Tint.js" as Tint
import "qml/SourceState.js" as SourceState
import "qml/IslandKeys.js" as IslandKeys
import "qml/FullscreenPolicy.js" as FullscreenPolicy
import "qml/CatchZone.js" as CatchZone
import "qml/Displays.js" as Displays
import "qml/ReadoutOwner.js" as ReadoutOwner
import "qml/Idle.js" as Idle
import "qml/DeviceEvents.js" as DeviceEvents
import "qml/Settings.js" as Settings

Item {
    id: root
    property var shell: null
    property var manifest: null
    property var service: null
    readonly property var coordinator: shell ? shell.serviceFor("io.github.bavanchun.nookisle") : null
    readonly property bool panelAllowed: coordinator !== null && coordinator.panelAllowed === true
    readonly property var hostBar: shell ? shell.bar : null
    // The drag catch zone may only cover empty bar centre space, so it is off
    // whenever the host's centre section holds anything besides this spacer.
    // Published per screen by the spacer BarWidget; -1 while unmeasured.
    readonly property real barCentreSpan: {
        var spans = coordinator && coordinator.barCentreSpans ? coordinator.barCentreSpans : null;
        var name = islandTargetScreen ? islandTargetScreen.name : "";
        return spans && typeof spans[name] === "number" ? spans[name] : -1;
    }
    readonly property var barLayout: shell && shell.barConfig ? shell.barConfig.layout : hostBar ? hostBar.layoutConfig : null
    readonly property bool barCentreShared: CatchZone.centreShared(barLayout, "io.github.bavanchun.nookisle")
    // Whether the host bar already shows the time, for the idle glance.
    readonly property bool barHasClock: Idle.layoutHasModule(barLayout, "omarchy.clock")
    readonly property int barClearance: hostBar && hostBar.position === "top" && hostBar.barHidden !== true ? Math.max(0, hostBar.barSize || 0) : 0
    // Island mode requires a live top bar to overlay; a hidden or non-top bar
    // falls back to the legacy summon-only panel (plan Decisions, "Bar auto-hidden").
    readonly property bool islandMode: coordinator && coordinator.island === true
        && hostBar && hostBar.position === "top" && hostBar.barHidden !== true
    property bool opened: false
    property bool expanded: false
    property bool dismissed: false
    property bool explicitOpen: false
    property real expansion: 0
    property string chosenScreenName: ""
    property real anchorCenterX: -1
    property real anchorLeftX: -1
    readonly property var targetScreen: {
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; ++i)
            if (screens[i].name === chosenScreenName)
                return screens[i];
        var focused = Hyprland.focusedMonitor;
        for (var j = 0; j < screens.length; ++j)
            if (focused && screens[j].name === focused.name)
                return screens[j];
        return screens.length ? screens[0] : null;
    }
    readonly property var monitor: targetScreen ? Hyprland.monitorFor(targetScreen) : null
    // In island mode, fullscreen must be read from the island's own monitor,
    // not the legacy target monitor: the two diverge whenever focus moved
    // between the legacy `targetScreen` binding and `islandTargetScreen`.
    readonly property var islandMonitor: islandTargetScreen ? Hyprland.monitorFor(islandTargetScreen) : null
    readonly property var activeMonitor: root.islandMode ? root.islandMonitor : root.monitor
    // Island mode picks its own screen, independent of the legacy chosenScreenName
    // binding above: it moves only while collapsed (multi-monitor motion contract),
    // never mid-expansion the way the legacy targetScreen binding does.
    property string islandScreenName: ""
    property bool pendingScreenMove: false
    // The primary island's screen for the displayMode setting
    // (qml/Displays.js): the focused screen in "follow", as before the
    // setting existed; preferredDisplay in "fixed" while it is connected; a
    // screen that never moves with focus in "all".
    function chooseIslandScreen() {
        var screens = Quickshell.screens;
        var focused = Hyprland.focusedMonitor;
        var names = [];
        for (var i = 0; i < screens.length; ++i)
            names.push(screens[i].name);
        return Displays.primaryScreen(root.displayMode, root.preferredDisplay, names, focused ? focused.name : "");
    }
    function applyIslandScreen() {
        if (root.surface.expanded) {
            pendingScreenMove = true;
            return;
        }
        pendingScreenMove = false;
        islandScreenName = chooseIslandScreen();
    }
    readonly property var islandTargetScreen: {
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; ++i)
            if (screens[i].name === islandScreenName)
                return screens[i];
        return screens.length ? screens[0] : null;
    }
    readonly property var windowScreen: root.islandMode ? root.islandTargetScreen : root.targetScreen
    // Where the island shows: displayMode and preferredDisplay (settings).
    readonly property string displayMode: Displays.mode(root.surface.settings.displayMode)
    readonly property string preferredDisplay: root.surface.settings.preferredDisplay || ""
    readonly property bool allDisplays: root.islandMode && displayMode === "all"
    onDisplayModeChanged: if (root.islandMode) root.applyIslandScreen()
    onPreferredDisplayChanged: if (root.islandMode) root.applyIslandScreen()
    readonly property real availableWidth: targetScreen ? Math.max(1, targetScreen.width - palette.gap * 2) : palette.expandedWidth
    readonly property real compactWidth: Math.min(palette.compactWidth, availableWidth)
    readonly property real expandedWidth: Math.min(palette.expandedWidth, availableWidth)
    // The island's own screen less a gap on each side: the cap on every
    // notch width, and on its window.
    readonly property real islandAvailableWidth: islandTargetScreen ? Math.max(1, islandTargetScreen.width - palette.gap * 2) : palette.openWidth
    // Fullscreen on the active monitor's workspace. The legacy panel always
    // hides over it; the island follows the fullscreenBehavior setting
    // (qml/FullscreenPolicy.js): by default it hides only over the app that
    // is playing. `explicitOpen` still overrides either wherever this is read.
    readonly property var fullscreenWorkspace: activeMonitor && activeMonitor.activeWorkspace ? activeMonitor.activeWorkspace : null
    readonly property bool workspaceFullscreen: !!fullscreenWorkspace && fullscreenWorkspace.hasFullscreen === true
    // The fullscreen client's class, from its own workspace's toplevels.
    // Hyprland fills lastIpcObject only on refreshToplevels(), which a
    // fullscreen event does not trigger, so the handlers below ask for it.
    readonly property string fullscreenClass: {
        if (!workspaceFullscreen || !fullscreenWorkspace.toplevels)
            return "";
        var toplevels = fullscreenWorkspace.toplevels.values || [];
        for (var i = 0; i < toplevels.length; ++i) {
            var ipc = toplevels[i] ? toplevels[i].lastIpcObject : null;
            if (ipc && Number(ipc.fullscreen) > 0)
                return String(ipc["class"] || "");
        }
        return "";
    }
    readonly property bool fullscreenNow: !root.islandMode ? workspaceFullscreen
        : FullscreenPolicy.shouldHide(root.surface.settings.fullscreenBehavior, workspaceFullscreen, fullscreenClass,
            root.coordinator ? root.coordinator.selectedEndpoint : null)
    onWorkspaceFullscreenChanged: Hyprland.refreshToplevels()
    onFullscreenWorkspaceChanged: Hyprland.refreshToplevels()
    // While a HUD bar is held, `fullscreen` keeps the value the drag started
    // with, so a fullscreen flip mid-drag never unmaps the window under the
    // pointer; the policy applies again on release.
    // Only this window's own held bar latches it; with an island on every
    // screen, a drag on another island leaves this one's policy free.
    readonly property bool hudHeld: root.surface.hudHeldHere
    property bool fullscreen: false
    Binding {
        target: root
        property: "fullscreen"
        value: root.fullscreenNow
        when: !root.hudHeld
        restoreMode: Binding.RestoreNone
    }
    readonly property bool surfaceVisible: opened && panelAllowed && !!targetScreen && (!fullscreen || explicitOpen)
    // The Overlay window is never shown over fullscreen unless the island was
    // opened explicitly; the HUD cannot override this.
    // `explicitOpen` also overrides `autoShow`, so a keyboard summon with
    // `autoShow:false` still shows the island instead of reporting "open"
    // while nothing is visible.
    readonly property bool islandVisible: root.islandMode && root.panelAllowed && !!root.coordinator
        && (root.coordinator.autoShow !== false || root.explicitOpen) && !!root.windowScreen && (!root.fullscreen || root.explicitOpen)
    readonly property bool activeVisible: root.islandMode ? root.islandVisible : root.surfaceVisible
    readonly property bool motionAllowed: surfaceVisible && !palette.reducedMotion
    readonly property string artworkPath: activeVisible && coordinator && coordinator.selectedEndpoint ? String(coordinator.selectedEndpoint.artworkPath || "") : ""
    // Native-probe gates G4 (drag files in) and G5 (drag files out) were not
    // performed: nobody dragged within the probe's 60s window. The
    // recorded decision keeps the DropArea and the drag-out handle enabled
    // rather than hiding them on no evidence of failure; Paste and Copy ship
    // as the proven route in and out either way, and both interactions are
    // recorded as unverified live until a human drags once each way.
    readonly property bool shelfDropInSupported: true
    // The selected source's app icon for the player's badge: from its MPRIS
    // DesktopEntry first, then from its app name (SourceState); the first
    // candidate that resolves wins, and empty (no badge) when none does.
    readonly property string sourceAppIcon: {
        var endpoint = root.coordinator ? root.coordinator.selectedEndpoint : null;
        var names = SourceState.badgeIconCandidates(endpoint ? endpoint.presentation : null,
            id => DesktopEntries.byId(id), name => DesktopEntries.heuristicLookup(name));
        for (var i = 0; i < names.length; ++i) {
            if (names[i].charAt(0) === "/")
                return "file://" + names[i];
            var path = Quickshell.iconPath(names[i], true);
            if (path)
                return path;
        }
        return "";
    }
    readonly property bool shelfDragOutSupported: true
    // The island surface in island mode. In legacy mode it is not built, and
    // this inert stand-in answers Panel's reads instead: collapsed, not
    // interactive, the same resolved settings, and actions that do nothing.
    readonly property var surface: surfaceLoader.item ? surfaceLoader.item : inertSurface
    QtObject {
        id: inertSurface
        readonly property bool expanded: false
        readonly property var settings: Settings.resolve(root.coordinator ? root.coordinator.fileSettings : null)
        readonly property bool hudHeldHere: false
        readonly property int busyCount: 0
        readonly property string view: "home"
        readonly property real pillHeight: palette.pillMinHeight + palette.small
        readonly property bool pointerInside: false
        readonly property bool interactive: false
        readonly property var hitShape: null
        readonly property var catchZone: null
        readonly property var hudHitShape: ({ present: false })
        readonly property var hoverExtension: ({ height: 0 })
        // No closed island, so no activities to report.
        readonly property var activities: null
        signal collapseRequested()
        signal settingsOpened()
        signal volumeStepRequested(real delta)
        function expandTo(view) {}
        function focusKeys() {}
        function scheduleAutoClose(duration) {}
        function cancelAutoClose() {}
        function collapse() {}
        function resetForHost() {}
    }
    DesignTokens {
        id: palette
        theme: ({surface: Color.popups.background, text: Color.popups.text,
            accent: Color.accent, onAccent: Color.background, stroke: Color.popups.border,
            error: Color.urgent, fontFamily: Style.font.family, radius: Style.cornerRadius,
            titleSize: Style.font.title, bodySize: Style.font.body, captionSize: Style.font.bodySmall})
        light: root.coordinator ? root.coordinator.lightTheme === true : false
        highContrast: root.coordinator ? root.coordinator.highContrast === true : false
        reducedMotion: root.coordinator ? root.coordinator.reducedMotion === true : false
        customAccent: root.coordinator && root.coordinator.fileSettings
            && root.coordinator.fileSettings.useCustomAccentColor === true
            ? root.coordinator.fileSettings.customAccentColor : ""
        tintEnabled: root.coordinator ? root.coordinator.tint === true : true
        // Hardware scene-graph APIs only. Unknown (no window yet, or the
        // offscreen platform) and Software keep the fallback.
        gpuEffects: [GraphicsInfo.OpenGL, GraphicsInfo.OpenGLRhi, GraphicsInfo.VulkanRhi,
            GraphicsInfo.MetalRhi, GraphicsInfo.Direct3D11Rhi].indexOf(surfaceLoader.GraphicsInfo.api) >= 0
    }
    Binding {
        target: root.coordinator
        property: "bodyFontSize"
        value: Style.font.body
        when: root.coordinator !== null
    }
    Binding {
        target: root.coordinator
        property: "islandPointerActive"
        value: root.islandMode && root.pointerIsland !== ""
        when: root.coordinator !== null
    }
    // Exposes which screen the island lives on so each screen's BarWidget can
    // suppress its own centre-hover peek only when the island is actually on
    // that screen, instead of every bar suppressing on any island's hover.
    Binding {
        target: root.coordinator
        property: "islandScreenName"
        // With an island on every screen, the one the pointer is on.
        value: !root.islandMode ? "" : root.pointerIsland || root.primaryScreenName
        when: root.coordinator !== null
    }
    // The spectrum and the collapsed progress subscription follow the island
    // itself, never the legacy panel that stands in for it on a hidden or
    // non-top bar.
    Binding {
        target: root.coordinator
        property: "islandShowing"
        value: root.islandMode && root.islandViewVisible
        when: root.coordinator !== null
    }
    Binding {
        target: root.coordinator
        property: "spectrumBarSpan"
        value: root.islandMode ? root.spectrumSurface.spectrumBarSpan : 0
        when: root.coordinator !== null
    }
    // Volume HUD source: Panel-side only, loaded only in island mode with hud
    // on, so this is the sole place in the plugin that ever imports
    // Quickshell.Services.Pipewire.
    Loader {
        id: volumeLoader
        active: root.islandMode && root.panelAllowed && root.coordinator && root.coordinator.hud === true
        source: "components/VolumeSource.qml"
        // A fresh load must start from a fresh baseline: a stale per-sink
        // baseline from before a `hud` toggle or a `barHidden` flip could
        // otherwise compare a fresh first reading against a reading that no
        // longer reflects reality.
        onLoaded: {
            hudModel.resetBaselines();
            volumeLoader.item.emit();
            // The output it finds on load is a baseline, not a switch.
            root.deviceState = DeviceEvents.noteOutput(root.deviceState, volumeLoader.item.sinkName, "").state;
        }
    }
    Connections {
        target: volumeLoader.item
        function onSample(sinkId, volume, muted) { hudModel.noteVolume(sinkId, volume, muted) }
        function onLocalChange(samples) { hudModel.expectLocal("volume", samples) }
        function onOutputChanged(name, label) {
            var noted = DeviceEvents.noteOutput(root.deviceState, name, label);
            root.deviceState = noted.state;
            if (noted.event && root.coordinator && root.coordinator.fileSettings.outputPeek === true)
                root.noteDeviceEvent(noted.event);
        }
    }
    // Device and output peeks (qml/DeviceEvents.js): a Bluetooth connect or
    // low battery, and a switch of the sound output. A connect and the
    // output switch it causes become one peek.
    property var deviceState: DeviceEvents.initial()
    property var lastDeviceEvent: null
    property double lastDeviceEventAt: 0
    function noteDeviceEvent(event) {
        var now = Date.now();
        var merged = DeviceEvents.merge(root.lastDeviceEvent, root.lastDeviceEventAt, event, now);
        if (merged) {
            root.lastDeviceEvent = merged;
            peekModel.updateEvent("device", DeviceEvents.payload(merged));
            return;
        }
        root.lastDeviceEvent = event;
        root.lastDeviceEventAt = now;
        peekModel.showEvent("device", DeviceEvents.payload(event), palette.devicePeekDuration);
    }
    // A timer that ran out: Omarchy notifies too; the notch adds the moment.
    Connections {
        target: root.coordinator
        ignoreUnknownSignals: true
        function onCaptureShelved(kind, path) {
            peekModel.showEvent("capture", { icon: kind === "recording" ? "record" : "image",
                title: kind === "recording" ? "Screen recording" : "Screenshot", detail: "Added to shelf",
                level: -1, alert: false, thumbnail: kind === "screenshot" ? path : "" }, palette.capturePeekDuration);
        }
        function onTimerFinished(label) {
            peekModel.showEvent("timerDone", { icon: "ring", title: label, detail: "Timer done", level: -1, alert: false },
                palette.timerDonePeekDuration);
        }
    }
    Loader {
        id: deviceLoader
        active: root.islandMode && root.panelAllowed && !!root.coordinator
            && root.coordinator.fileSettings.deviceEvents !== "off"
        source: "components/DeviceSource.qml"
        onLoaded: root.deviceState = DeviceEvents.resetDevices(root.deviceState)
    }
    Connections {
        target: deviceLoader.item
        function onDeviceSample(sample) {
            var noted = DeviceEvents.note(root.deviceState, sample, root.coordinator ? root.coordinator.fileSettings.deviceEvents : "off", Date.now());
            root.deviceState = noted.state;
            if (noted.event)
                root.noteDeviceEvent(noted.event);
        }
    }
    readonly property string readoutRuntime: Quickshell["env"]("XDG_RUNTIME_DIR") || ""
    readonly property string readoutDir: readoutRuntime ? readoutRuntime + "/nookisle" : ""
    FileView { id: volumeReadout; path: root.readoutDir ? root.readoutDir + "/key-readout.volume" : ""; blockAllReads: true; printErrors: false }
    FileView { id: micReadout; path: root.readoutDir ? root.readoutDir + "/key-readout.mic" : ""; blockAllReads: true; printErrors: false }
    FileView { id: brightnessReadout; path: root.readoutDir ? root.readoutDir + "/key-readout.brightness" : ""; blockAllReads: true; printErrors: false }
    FileView { id: keyboardReadout; path: root.readoutDir ? root.readoutDir + "/key-readout.keyboard" : ""; blockAllReads: true; printErrors: false }
    function keyReadoutAllowed(kind) {
        if (!root.readoutDir) return true
        var view = kind === "volume" ? volumeReadout : kind === "mic" ? micReadout
            : kind === "brightness" ? brightnessReadout : keyboardReadout
        view.reload()
        return ReadoutOwner.allows(view.text(), kind, Date.now())
    }
    HudModel {
        id: hudModel
        tokens: palette
        duration: root.surface.settings.hudDuration
        readoutAllowed: root.keyReadoutAllowed
    }
    Binding {
        target: hudModel
        property: "suppressed"
        // Suppressed over fullscreen, and while the island is open (hover or
        // explicit) unless the open header shows the readout
        // (showOpenNotchHud). Never while a HUD bar is held: nothing that
        // happens mid-drag hides the bar under the pointer. The model still
        // tracks the volume baseline while suppressed.
        // With an island on every screen, only when no window can show it.
        value: root.islandMode && !hudModel.held && Displays.readoutSuppressed(root.fullscreen
            || ((root.surface.expanded || root.explicitOpen) && root.surface.settings.showOpenNotchHud === false),
            root.extraStates, root.surface.settings.showOpenNotchHud !== false)
    }
    // The media-key bindings ask the Service whether a key's readout is the
    // island's; a suppressed model draws none, so Omarchy's OSD must.
    Binding {
        target: root.coordinator
        property: "hudSuppressed"
        value: hudModel.suppressed
        when: root.coordinator !== null
    }
    Binding {
        target: root.coordinator
        property: "hudHeldKind"
        value: hudModel.held ? hudModel.kind : ""
        when: root.coordinator !== null
    }
    // Microphone mute: the same gate as the volume source, one readout per
    // mute change.
    Loader {
        id: micLoader
        active: root.islandMode && root.panelAllowed && !!root.coordinator && root.coordinator.hud === true
        source: "components/MicSource.qml"
    }
    Connections {
        target: micLoader.item
        function onSample(kind, level, muted, label) { hudModel.show(kind, level, muted, label) }
    }
    Connections {
        target: root.coordinator
        // Volume never reaches the Service; only the brightness monitor's
        // hudEvent arrives here (plan Decisions, "HUD sources and triggers").
        function onHudEvent(kind, level, muted) { if (root.islandMode) hudModel.show(kind, level, muted) }
    }
    // Track and power peeks. Only in island mode, only while the collapsed
    // island is on screen, and never over the HUD: a peek is suppressed (and
    // dismissed) while the island is hidden, expanded, explicitly open, over
    // fullscreen, or showing the level readout. Suppression still advances
    // both baselines, so nothing replays when it ends.
    PeekModel {
        id: peekModel
        tokens: palette
        trackEnabled: !!root.coordinator && root.coordinator.peek === true
        // Charger changes and low or critical battery warnings peek only
        // with powerStyle "peek"; "banner" widens the closed notch instead
        // (BatteryModel, which takes the warnings from batteryWarning).
        powerEnabled: !!root.coordinator && root.coordinator.power === true
            && root.surface.settings.showPowerNotifications !== false && root.surface.settings.powerStyle === "peek"
    }
    BatteryModel {
        id: batteryModel
        powerStyle: root.surface.settings.powerStyle
        enabled: root.islandMode && !!root.coordinator && root.coordinator.power === true
            && root.surface.settings.showPowerNotifications !== false
    }
    Connections {
        target: peekModel
        function onBatteryWarning(kind, level) { batteryModel.warn(kind, level) }
    }
    Binding {
        target: peekModel
        property: "suppressed"
        value: !root.islandMode || hudModel.active || Displays.peekSuppressed(!root.islandVisible
            || root.surface.expanded || root.explicitOpen || root.fullscreen, root.extraStates)
    }
    // Power source: Panel-side only, loaded only in island mode with power on,
    // so this loader is the plugin's one route to UPower; the import itself
    // lives in PowerSource.qml alone.
    // Privacy indicators: who uses the microphone, a camera or the screen.
    // PipeWire's graph plus the helper's camera holders; loaded only in
    // island mode with the indicators on.
    Loader {
        id: privacyLoader
        active: root.islandMode && root.panelAllowed && !!root.coordinator
            && root.coordinator.fileSettings.privacyIndicators === true
        source: "components/PrivacySource.qml"
    }
    // status() reports the closed island's activity key and privacy counts.
    function reportPresence() {
        if (root.coordinator && typeof root.coordinator.reportActivity === "function")
            root.coordinator.reportActivity(root.closedActivities ? root.closedActivities.key : "",
                privacyLoader.item ? privacyLoader.item.state : null);
    }
    // The surface Loader builds the island with its activities already
    // shown, and legacy mode has none: a new or gone surface reports too,
    // not only a key change on the one in place.
    readonly property var closedActivities: surface.activities
    onClosedActivitiesChanged: reportPresence()
    Connections {
        target: root.closedActivities
        function onKeyChanged() { root.reportPresence() }
    }
    Connections {
        target: privacyLoader.item
        ignoreUnknownSignals: true
        function onStateChanged() { root.reportPresence() }
    }
    Connections {
        target: privacyLoader
        function onItemChanged() { root.reportPresence() }
    }
    Binding {
        target: privacyLoader.item
        when: !!privacyLoader.item
        property: "cameraHolders"
        value: root.coordinator ? root.coordinator.cameraHolders : []
    }
    Loader {
        id: powerLoader
        active: root.islandMode && root.panelAllowed && !!root.coordinator && root.coordinator.power === true
        source: "components/PowerSource.qml"
        // `item` is already assigned here, so the Connections below receives
        // this first sample as a fresh baseline; the first real plug or
        // unplug after a load then peeks.
        onLoaded: {
            peekModel.resetPowerBaseline();
            batteryModel.resetBaseline();
            powerLoader.item.emitSample();
        }
    }
    Connections {
        target: powerLoader.item
        function onSample(present, onBattery, level) {
            peekModel.notePower(present, onBattery, level);
            batteryModel.note(powerLoader.item.reading);
        }
    }
    // trackToken changes only with the track id, title or artists, never
    // with artwork, position or volume, so those updates never peek.
    function noteTrack() {
        var endpoint = root.coordinator ? root.coordinator.selectedEndpoint : null;
        peekModel.noteTrack(endpoint ? SourceState.key(endpoint.token) : "",
            endpoint && endpoint.trackToken ? JSON.stringify(endpoint.trackToken) : "");
    }
    Connections {
        target: root.coordinator
        function onSelectedEndpointChanged() { root.noteTrack() }
    }
    NumberAnimation {
        id: morph
        target: root
        property: "expansion"
        duration: root.expanded ? palette.expandDuration : palette.collapseDuration
        easing.type: Easing.OutCubic
    }
    function settleOrAnimate() {
        morph.stop();
        if (motionAllowed) {
            morph.to = expanded ? 1 : 0;
            morph.start();
        } else
            expansion = expanded ? 1 : 0;
    }
    function open(payloadJson) {
        // Refused while the panel is not allowed (locked, or the lock state
        // not yet known), as the bar button refuses it: a summon kept from
        // then would surface on unlock and take the keyboard exclusively.
        if (!panelAllowed)
            return;
        var payload = {};
        try {
            payload = JSON.parse(payloadJson || "{}");
        } catch (error) {
            return;
        }
        if (!payload || typeof payload !== "object" || Array.isArray(payload))
            return;
        if (typeof payload.screenName === "string" && payload.screenName)
            chosenScreenName = payload.screenName;
        anchorLeftX = typeof payload.anchorLeftX === "number" && isFinite(payload.anchorLeftX)
            ? payload.anchorLeftX : -1;
        anchorCenterX = typeof payload.anchorCenterX === "number" && isFinite(payload.anchorCenterX)
            ? payload.anchorCenterX : -1;
        dismissed = false;
        explicitOpen = true;
        // A summon always takes the keyboard back, even from a settings or
        // welcome window left open elsewhere, possibly on another workspace.
        panel.keyboardLent = false;
        if (root.islandMode) {
            root.surface.expandTo("home");
            // Focus the surface root, where the shortcut keys and the view
            // switch live; Return steps into the view, whose own Escape
            // ladder (source/settings first, then collapse) runs from there.
            Qt.callLater(root.surface.focusKeys);
            // `autoClose` in the payload closes the island again after the
            // summonAutoClose setting (0 never), unless the user interacts.
            if (payload.autoClose === true)
                root.surface.scheduleAutoClose(root.surface.settings.summonAutoClose);
            else
                root.surface.cancelAutoClose();
            return;
        }
        opened = true;
        expanded = true;
    }
    function close() {
        // A menu, picker or share action, or a held HUD bar, holds the
        // island open; only Escape closes it then.
        if (root.islandMode && (root.surface.busyCount > 0 || root.hudHeld === true))
            return;
        dismissed = true;
        panel.keyboardLent = false;
        if (root.islandMode) {
            explicitOpen = false;
            opened = false;
            root.surface.collapse();
            return;
        }
        // Hide before revoking the fullscreen override: its visibility handler
        // also collapses the panel and must not re-enter an open surface binding.
        // explicitOpen must be reset after opened, in that order: opened=false
        // alone already drives surfaceVisible false (it is the first operand
        // of its "&&" chain), so resetting explicitOpen first would instead
        // flip surfaceVisible through its fullscreen-override term while
        // `opened` is still true, re-entering the surfaceVisible evaluation
        // from inside its own change handler and tripping a binding loop.
        opened = false;
        explicitOpen = false;
        expanded = false;
    }
    function toggleExpanded() {
        if (panelAllowed && opened)
            close();
    }
    function syncSubscription() {
        if (!coordinator) return;
        if (root.islandMode) {
            coordinator.viewVisible = root.islandViewVisible;
            coordinator.viewExpanded = root.islandViewExpanded;
        } else {
            coordinator.viewVisible = surfaceVisible;
            coordinator.viewExpanded = expanded && surfaceVisible;
        }
    }
    onPanelAllowedChanged: {
        if (!panelAllowed) {
            opened = false;
            expanded = false;
            explicitOpen = false;
            dismissed = false;
            if (root.islandMode) root.surface.resetForHost();
        }
        syncSubscription();
    }
    onExpandedChanged: {
        if (!expanded && opened)
            opened = false;
        settleOrAnimate();
        syncSubscription();
        if (expanded)
            Qt.callLater(() => { if (contentLoader.item) contentLoader.item.forceActiveFocus(); });
    }
    onSurfaceVisibleChanged: {
        if (!surfaceVisible) {
            expanded = false;
            morph.stop();
            expansion = 0;
        }
        syncSubscription();
    }
    onIslandVisibleChanged: syncSubscription()
    onMotionAllowedChanged: if (!motionAllowed) {
        morph.stop();
        expansion = expanded ? 1 : 0;
    }
    onCoordinatorChanged: {
        syncSubscription();
        reportPresence();
    }
    onIslandModeChanged: {
        if (root.islandMode) {
            applyIslandScreen();
            // Entering island mode must not inherit stale legacy state: a
            // legacy explicit/hover-open panel left `opened`, `expanded` and
            // `explicitOpen` set, which would suppress the HUD, keep the pill
            // interactive over fullscreen and make `isPluginOpen` report open
            // while the island is actually collapsed.
            opened = root.surface.expanded;
            expanded = false;
            explicitOpen = false;
            morph.stop();
            expansion = 0;
            syncSubscription();
        } else {
            // Island mode no longer drives visibility; reset the mirrored open
            // state directly so the legacy panel does not inherit a stale
            // hover-open flag left over from the island.
            opened = false;
            explicitOpen = false;
            root.surface.resetForHost();
            // The surface is unloaded without a close: withdraw its camera
            // claim so no other island waits on a camera nobody holds.
            if (root.primaryCameraName) {
                root.noteCameraIsland(root.primaryCameraName, false);
                root.primaryCameraName = "";
            }
        }
    }
    onWindowScreenChanged: {
        if (root.islandMode) root.surface.resetForHost();
    }
    onFullscreenChanged: {
        if (root.islandMode && root.fullscreen && !root.explicitOpen)
            root.surface.resetForHost();
    }
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { if (root.islandMode) root.applyIslandScreen(); }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { if (root.islandMode) root.applyIslandScreen(); }
    }
    Connections {
        target: root.surface
        function onExpandedChanged() {
            if (root.islandMode) root.opened = root.surface.expanded;
            if (!root.surface.expanded && root.pendingScreenMove) root.applyIslandScreen();
            // Call directly rather than relying on `opened` mirroring into
            // `surfaceVisible`: `opened` can already be true on entry, which
            // would otherwise make `syncSubscription()` never run on a hover expand.
            root.syncSubscription();
        }
        function onCollapseRequested() { root.explicitOpen = false; }
        // An explicit press on the gear lends the keyboard to the settings
        // window even when it was already open, where the window-open change
        // that lends it on its own never comes.
        function onSettingsOpened() { if (root.explicitOpen) panel.keyboardLent = true; }
    }
    function rememberTargetScreen() {
        // Read the current target after its binding has settled. Writing the
        // remembered name from the change handler re-enters that same binding.
        if (targetScreen && chosenScreenName !== targetScreen.name)
            chosenScreenName = targetScreen.name;
    }
    onTargetScreenChanged: {
        if (chosenScreenName !== "") {
            expanded = false;
            morph.stop();
            expansion = 0;
        }
        Qt.callLater(rememberTargetScreen);
    }
    onArtworkPathChanged: if (coordinator && typeof coordinator.retainArtwork === "function")
        coordinator.retainArtwork(artworkPath ? [artworkPath] : [])
    // Wheel volume from the collapsed pill. VolumeSource is loaded only in
    // island mode with hud on, so with hud:false the wheel does nothing.
    Connections {
        target: root.surface
        function onVolumeStepRequested(delta) { if (volumeLoader.item) volumeLoader.item.adjust(delta) }
    }
    // Synced lyrics for the Lyrics view. Held here, not in the view, so the
    // cache outlives a view change. It asks LRCLIB only in island mode with
    // the opt-in lyrics setting on, and only while the island shows the
    // Lyrics view. The position is the expanded view's own subscription.
    LyricsFetch {
        id: lyricsFetch
    }
    LyricsSource {
        id: lyricsSource
        fetcher: lyricsFetch
        lyricsEnabled: root.islandMode && !!root.coordinator && root.coordinator.lyrics === true
        wanted: root.islandVisible && root.surface.expanded && (root.surface.view === "home" || root.surface.view === "lyrics")
            || root.extraLyricsWanted
        endpoint: root.coordinator && root.coordinator.uiAllowed === true ? root.coordinator.selectedEndpoint : null
        positionSeconds: root.coordinator ? root.coordinator.positionSeconds : 0
    }
    // The artwork's palette, once per artwork change at 48 px. Island mode
    // only, so the legacy panel keeps the plain accent; artworkPath is already
    // empty unless the island shows, and the helper publishes one only for a
    // local cover file or, with remoteArtwork on, a fetched one. The helper's
    // file:// URL goes through SourceState.artworkUrl, the rule Artwork uses.
    ColorQuantizer {
        id: quantizer
        source: root.islandMode && palette.tintEnabled && !palette.highContrast
            ? SourceState.artworkUrl(root.artworkPath) : ""
        depth: 3
        rescaleSize: 48
        onColorsChanged: root.applyArtColor()
        onSourceChanged: if (String(source) === "") {
            tintMorph.stop();
            palette.artColor = "transparent";
        }
    }
    ColorAnimation {
        id: tintMorph
        target: palette
        property: "artColor"
        duration: palette.tintDuration
        easing.type: Easing.OutCubic
    }
    function applyArtColor() {
        if (String(quantizer.source) === "")
            return;
        var colors = [];
        for (var i = 0; i < quantizer.colors.length; ++i) {
            var c = quantizer.colors[i];
            colors.push({r: c.r, g: c.g, b: c.b});
        }
        var picked = Tint.pick(colors);
        var target = picked ? Qt.rgba(picked.r, picked.g, picked.b, 1) : Qt.rgba(0, 0, 0, 0);
        tintMorph.stop();
        if (!picked || palette.reducedMotion) {
            palette.artColor = target;
            return;
        }
        // Ease from the accent, never from transparent: the way through a
        // dark translucent colour would flash the card and the bars.
        if (palette.artColor.a < 1)
            palette.artColor = palette.accent;
        tintMorph.to = target;
        tintMorph.start();
    }
    // With displayMode "all", one more island for every screen but the
    // primary's (components/IslandWindow.qml). The primary above keeps the
    // keyboard summon and publishes the island's state; these share its
    // models and keep their own surfaces.
    readonly property var extraScreens: {
        if (!root.allDisplays)
            return [];
        var screens = Quickshell.screens;
        var names = [];
        for (var i = 0; i < screens.length; ++i)
            names.push(screens[i].name);
        var extra = Displays.extraScreens("all", names, root.islandScreenName);
        return screens.filter(screen => extra.indexOf(screen.name) >= 0);
    }
    Variants {
        id: extraIslands
        // Extra islands exist only in island mode, like the primary one.
        model: root.islandMode ? root.extraScreens : []
        IslandWindow {
            tokens: palette
            coordinator: root.coordinator
            shown: root.islandMode && root.panelAllowed && !!root.coordinator && root.coordinator.autoShow !== false
            hudModel: hudModel
            peekModel: peekModel
            batteryModel: batteryModel
            batteryReading: powerLoader.item ? powerLoader.item.reading : batteryModel.reading
            batteryPowerAvailable: !!powerLoader.item && powerLoader.item.powerCommand.length > 0
            privacy: privacyLoader.item ? privacyLoader.item.state : null
            lyricsSource: lyricsSource
            appIcon: root.sourceAppIcon
            pillHeight: root.surface.pillHeight
            dropInSupported: root.shelfDropInSupported
            dragOutSupported: root.shelfDragOutSupported
            barCentreShared: root.barCentreShared
            barHasClock: root.barHasClock
            liveSpectrum: Displays.spectrumLive("all", screenName, root.spectrumOwner)
            cameraAllowed: Displays.cameraAllowed("all", screenName, root.cameraOwner)
            onHudLevelRequested: (kind, value) => root.setHudLevel(kind, value)
            onVolumeStepRequested: delta => { if (volumeLoader.item) volumeLoader.item.adjust(delta); }
            onBatteryPowerRequested: if (powerLoader.item) powerLoader.item.openPowerSettings()
            onIslandOpened: root.noteCameraIsland(screenName, true)
            onIslandClosed: root.noteCameraIsland(screenName, false)
        }
    }
    // Each extra window's state, for the rules shared across windows
    // (qml/Displays.js); empty outside "all", where each rule reduces to the
    // primary's own.
    readonly property var extraStates: extraIslands.instances.map(window => ({
        name: window.screenName, visible: window.visible,
        expanded: window.surface.expanded, hovered: window.surface.pointerInside }))
    // Every island, the primary first: each shared owner below is chosen
    // from the visible ones, re-evaluated as windows show, hide, or go with
    // their screen. With one island each reduces to that island's own.
    readonly property var islandStates: [{ name: root.primaryScreenName, visible: root.islandVisible,
        expanded: root.surface.expanded, hovered: root.surface.pointerInside }].concat(root.extraStates)
    readonly property string pointerIsland: Displays.pointerIsland(root.islandStates)
    // The Service's view state covers every visible window, so fullscreen on
    // the primary's screen does not stop the subscription or the spectrum
    // while another island is open.
    readonly property bool islandViewVisible: Displays.viewState({ visible: root.islandVisible,
        expanded: root.surface.expanded }, root.extraStates).visible
    readonly property bool islandViewExpanded: Displays.viewState({ visible: root.islandVisible,
        expanded: root.surface.expanded }, root.extraStates).expanded
    onIslandViewVisibleChanged: syncSubscription()
    onIslandViewExpandedChanged: syncSubscription()
    // The one island that draws the live spectrum: under the pointer, else
    // the primary.
    readonly property string primaryScreenName: root.islandTargetScreen ? root.islandTargetScreen.name : ""
    readonly property string spectrumOwner: Displays.spectrumOwner(root.primaryScreenName, root.islandStates)
    // Its lines pause only while the drawing island itself is open. Follow
    // and fixed leave the Service's own default (viewExpanded).
    Binding {
        target: root.coordinator
        property: "spectrumPaused"
        value: Displays.spectrumPaused(root.spectrumOwner, root.islandStates)
        when: root.coordinator !== null && root.allDisplays
    }
    readonly property var spectrumSurface: {
        for (var i = 0; i < extraIslands.instances.length; ++i)
            if (extraIslands.instances[i].screenName === root.spectrumOwner)
                return extraIslands.instances[i].surface;
        return root.surface;
    }
    readonly property bool extraLyricsWanted: extraIslands.instances.some(window => window.visible
        && window.surface.expanded && (window.surface.view === "home" || window.surface.view === "lyrics"))
    // One camera: of the islands open, only the one opened last may run it;
    // when it closes, the camera goes back to the one opened before it.
    property var cameraOpenOrder: []
    readonly property string cameraOwner: Displays.cameraOwnerOf(cameraOpenOrder)
    // The screens that have an island now; a change prunes the open order.
    readonly property var cameraScreens: root.extraScreens.map(screen => screen.name)
        .concat(primaryCameraName ? [primaryCameraName] : [])
    onCameraScreensChanged: cameraOpenOrder = Displays.pruneCameraOrder(cameraOpenOrder, cameraScreens)
    function noteCameraIsland(screenName, open) {
        cameraOpenOrder = Displays.cameraOpenOrder(cameraOpenOrder, screenName, open);
    }
    // The name the primary island opened under: it closes under that name
    // even if its screen went away meanwhile.
    property string primaryCameraName: ""
    Connections {
        target: root.surface
        function onExpandedChanged() {
            if (root.surface.expanded && root.islandTargetScreen) {
                root.primaryCameraName = root.islandTargetScreen.name;
                root.noteCameraIsland(root.primaryCameraName, true);
            } else if (!root.surface.expanded && root.primaryCameraName) {
                root.noteCameraIsland(root.primaryCameraName, false);
                root.primaryCameraName = "";
            }
        }
    }
    function setHudLevel(kind, value) {
        if (kind === "volume") {
            if (volumeLoader.item)
                volumeLoader.item.setVolume(value);
        } else if (root.coordinator && (kind === "brightness" || kind === "keyboard")) {
            hudModel.expectLocal(kind);
            if (!root.coordinator.setBrightnessLevel(kind, value)) hudModel.cancelLocal(kind);
        }
    }
    Component.onCompleted: if (root.islandMode) applyIslandScreen();
    Component.onDestruction: {
        if (coordinator) {
            coordinator.viewVisible = false;
            coordinator.viewExpanded = false;
            coordinator.islandPointerActive = false;
            coordinator.islandShowing = false;
            if (typeof coordinator.retainArtwork === "function")
                coordinator.retainArtwork([]);
        }
    }
    PanelWindow {
        id: panel
        objectName: "nookisleWindow"
        visible: root.activeVisible
        screen: root.windowScreen
        implicitWidth: root.islandMode ? palette.notchWindowWidth(root.islandAvailableWidth) : root.expandedWidth
        implicitHeight: root.islandMode ? palette.notchWindowHeight() : palette.panelHeight(root.expandedWidth)
        anchors.top: true
        anchors.left: !root.islandMode
        margins.left: Math.max(palette.gap, Math.min(root.targetScreen ? root.targetScreen.width - width - palette.gap : 0,
            root.anchorLeftX >= 0 ? root.anchorLeftX : (root.anchorCenterX >= 0 ? root.anchorCenterX : (root.targetScreen ? root.targetScreen.width / 2 : 0)) - width / 2))
        margins.top: root.islandMode ? 0 : root.barClearance + palette.gap
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "nookisle"
        WlrLayershell.layer: root.islandMode ? WlrLayer.Overlay : WlrLayer.Top
        readonly property string focusMode: IslandKeys.keyboardFocus(visible, root.islandMode,
            root.explicitOpen, root.surface.expanded, root.expanded, keyboardLent)
        // The island lends the keyboard only to a settings or welcome window
        // opened while it is summoned (the header gear, or a verb). A window
        // that was already open, perhaps on another workspace, does not
        // count: lending to it made Hyprland focus that window and switch
        // the user to its workspace, and summoned keys went there instead.
        readonly property bool pluginWindowOpen: !!root.coordinator
            && (root.coordinator.settingsWindowOpen === true || root.coordinator.onboardingWindowOpen === true)
        property bool keyboardLent: false
        onPluginWindowOpenChanged: keyboardLent = pluginWindowOpen && root.explicitOpen
        WlrLayershell.keyboardFocus: focusMode === "exclusive" ? WlrKeyboardFocus.Exclusive
            : focusMode === "onDemand" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // In island mode, union the body with the active HUD bar and the
        // closed drag catch zone. Both extra regions jump per state.
        mask: Region {
            item: root.islandMode ? (root.surface.interactive ? root.surface.hitShape : null) : card
            Region {
                item: root.islandMode && root.surface.interactive && root.surface.hudHitShape.present ? root.surface.hudHitShape : null
                intersection: Intersection.Combine
            }
            radius: root.islandMode ? 0 : card.radius
            Region {
                item: root.islandMode && root.surface.interactive ? root.surface.catchZone : null
                intersection: Intersection.Combine
            }
            Region {
                item: root.islandMode && root.surface.interactive && root.surface.hoverExtension.height > 0
                    ? root.surface.hoverExtension : null
                intersection: Intersection.Combine
            }
        }
        Rectangle {
            id: card
            objectName: "nookisleCard"
            anchors.fill: parent
            visible: !root.islandMode
            radius: palette.expandedRadius
            opacity: root.expansion
            color: palette.surface
            border.color: palette.stroke
            border.width: palette.highContrast ? palette.focusWidth : 1
            clip: true
            // The legacy panel's tree exists only in legacy mode: in island
            // mode it would hold a few MiB for a card that never shows.
            Loader {
                id: contentLoader
                objectName: "legacyContentLoader"
                active: !root.islandMode
                // Unloaded, it keeps no focus: keys never go to an empty Loader.
                onActiveChanged: if (!active) focus = false
                width: root.expanded ? root.expandedWidth : root.compactWidth
                height: parent.height
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: IslandContent {
                    tokens: palette
                    coordinator: root.coordinator
                    expanded: root.expanded
                    admitted: root.panelAllowed
                    visible: panel.visible
                    onToggleRequested: root.toggleExpanded()
                    onCloseRequested: root.close()
                }
            }
        }
        // The island surface exists only in island mode; legacy mode keeps
        // none of its objects (Home, the camera, the shelf), and Panel reads
        // root.surface, an inert stand-in, instead.
        Loader {
            id: surfaceLoader
            objectName: "nookisleSurfaceLoader"
            anchors.fill: parent
            active: root.islandMode
            // Unloaded, it keeps no focus: keys never go to an empty Loader.
            onActiveChanged: if (!active) focus = false
            sourceComponent: IslandSurface {
                objectName: "nookisleSurface"
                tokens: palette
                coordinator: root.coordinator
                availableWidth: root.islandAvailableWidth
                // The window's own visibility: hiding it stops the camera even
                // while the island stays expanded.
                hostVisible: panel.visible
                // The collapsed pill sits flush over the bar like a notch: bind its
                // height to the live bar size (26 on this host) so it neither
                // overlaps nor gaps against the bar edge. Falls back to the design
                // tokens' own pill height when the host bar height is unknown.
                pillHeight: root.hostBar && root.hostBar.barSize > 0
                    ? root.hostBar.barSize : (palette.pillMinHeight + palette.small)
                explicitOpen: root.explicitOpen
                interactive: !root.fullscreen || root.explicitOpen
                hudModel: hudModel
                // A bar drag sets the level: the sink's volume, or the display or
                // keyboard backlight through the Service.
                onHudLevelRequested: (kind, value) => root.setHudLevel(kind, value)
                batteryActive: batteryModel.bannerActive
                batteryLevel: batteryModel.bannerLevel
                batteryLabel: batteryModel.bannerLabel
                batteryKind: batteryModel.bannerKind
                privacy: privacyLoader.item ? privacyLoader.item.state : null
                batteryReading: powerLoader.item ? powerLoader.item.reading : batteryModel.reading
                batteryPowerAvailable: !!powerLoader.item && powerLoader.item.powerCommand.length > 0
                onBatteryPowerRequested: if (powerLoader.item) powerLoader.item.openPowerSettings()
                liveSpectrum: Displays.spectrumLive(root.allDisplays ? "all" : "follow", root.primaryScreenName, root.spectrumOwner)
                cameraAllowed: Displays.cameraAllowed(root.allDisplays ? "all" : "follow",
                    root.islandTargetScreen ? root.islandTargetScreen.name : "", root.cameraOwner)
                peekActive: peekModel.active
                peekEvent: peekModel.event
                peekKind: peekModel.kind
                powerKind: peekModel.powerKind
                powerLevel: peekModel.powerLevel
                lyricsSource: lyricsSource
                appIcon: root.sourceAppIcon
                dropInSupported: root.shelfDropInSupported
                dragOutSupported: root.shelfDragOutSupported
                barCentreShared: root.barCentreShared
                barCentreSpan: root.barCentreSpan
                barHasClock: root.barHasClock
            }
        }
    }
}
