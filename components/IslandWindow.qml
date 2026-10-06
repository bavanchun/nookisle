pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../qml/FullscreenPolicy.js" as FullscreenPolicy

// One more island, for a screen other than the primary's, when displayMode
// is "all". Panel.qml's own window stays the primary: it takes the keyboard
// summon and publishes the island's state to the Service. This window
// shares Panel's models (the level readout, peeks, battery, lyrics) and
// keeps its own surface, so everything a surface owns stays per window: its
// busy guard, its HUD input growth, its drag catch zone, and its fullscreen
// policy, read from its own monitor. It never takes the keyboard.
PanelWindow {
    id: window
    required property var modelData
    readonly property var screenInfo: modelData
    readonly property string screenName: screenInfo ? String(screenInfo.name) : ""
    property var tokens: null
    property var coordinator: null
    // True while Panel shows its island at all: island mode, admitted,
    // autoShow on.
    property bool shown: false
    property var hudModel: null
    property var peekModel: null
    property var batteryModel: null
    property var batteryReading: null
    property var privacy: null
    property bool batteryPowerAvailable: false
    property var lyricsSource: null
    property string appIcon: ""
    property real pillHeight: 26
    property bool dropInSupported: true
    property bool dragOutSupported: true
    property bool barCentreShared: false
    property bool barHasClock: false
    // Panel.qml's per-window arbitration: the live spectrum and the camera.
    property bool liveSpectrum: true
    property bool cameraAllowed: true
    readonly property alias surface: surface
    signal hudLevelRequested(string kind, real value)
    signal volumeStepRequested(real delta)
    signal batteryPowerRequested
    // This window's island has just opened or closed. Not `opened`/`closed`:
    // PanelWindow already has a `closed` signal, and redeclaring it warns.
    signal islandOpened
    signal islandClosed

    // This screen's fullscreen policy, as Panel reads its own monitor's.
    readonly property var monitor: screenInfo ? Hyprland.monitorFor(screenInfo) : null
    readonly property var fullscreenWorkspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace : null
    readonly property bool workspaceFullscreen: !!fullscreenWorkspace && fullscreenWorkspace.hasFullscreen === true
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
    readonly property bool fullscreenNow: FullscreenPolicy.shouldHide(surface.settings.fullscreenBehavior,
        workspaceFullscreen, fullscreenClass, coordinator ? coordinator.selectedEndpoint : null)
    onWorkspaceFullscreenChanged: Hyprland.refreshToplevels()
    onFullscreenWorkspaceChanged: Hyprland.refreshToplevels()
    // Its own held HUD bar keeps the value its drag started with, as on
    // Panel; a bar held on another island does not.
    property bool fullscreen: false
    Binding {
        target: window
        property: "fullscreen"
        value: window.fullscreenNow
        when: !surface.hudHeldHere
        restoreMode: Binding.RestoreNone
    }
    onFullscreenChanged: if (fullscreen)
        surface.resetForHost()
    // This screen's bar centre span, published by its own spacer.
    readonly property real barCentreSpan: {
        var spans = coordinator && coordinator.barCentreSpans ? coordinator.barCentreSpans : null;
        return spans && typeof spans[screenName] === "number" ? spans[screenName] : -1;
    }

    screen: screenInfo
    visible: shown && !fullscreen
    implicitWidth: tokens ? tokens.notchWindowWidth(screenInfo ? Math.max(1, screenInfo.width - tokens.gap * 2) : tokens.openWidth) : 680
    implicitHeight: tokens ? tokens.notchWindowHeight() : 220
    anchors.top: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nookisle"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // The body, the active HUD bar and the closed drag catch zone, as on
    // Panel's own window.
    mask: Region {
        item: surface.interactive ? surface.hitShape : null
        Region {
            item: surface.interactive && surface.hudHitShape.present ? surface.hudHitShape : null
            intersection: Intersection.Combine
        }
        Region {
            item: surface.interactive ? surface.catchZone : null
            intersection: Intersection.Combine
        }
        Region {
            item: surface.interactive && surface.hoverExtension.height > 0 ? surface.hoverExtension : null
            intersection: Intersection.Combine
        }
    }
    onVisibleChanged: if (!visible)
        surface.resetForHost()
    Connections {
        target: surface
        function onExpandedChanged() {
            if (surface.expanded)
                window.islandOpened();
            else
                window.islandClosed();
        }
    }
    IslandSurface {
        id: surface
        objectName: "nookisleSurface-" + window.screenName
        anchors.fill: parent
        tokens: window.tokens
        coordinator: window.coordinator
        availableWidth: window.screenInfo ? Math.max(1, window.screenInfo.width - window.tokens.gap * 2) : window.tokens.openWidth
        hostVisible: window.visible
        pillHeight: window.pillHeight
        interactive: !window.fullscreen
        liveSpectrum: window.liveSpectrum
        cameraAllowed: window.cameraAllowed
        hudModel: window.hudModel
        onHudLevelRequested: (kind, value) => window.hudLevelRequested(kind, value)
        onVolumeStepRequested: delta => window.volumeStepRequested(delta)
        batteryActive: !!window.batteryModel && window.batteryModel.bannerActive
        batteryLevel: window.batteryModel ? window.batteryModel.bannerLevel : 0
        batteryLabel: window.batteryModel ? window.batteryModel.bannerLabel : ""
        batteryKind: window.batteryModel ? window.batteryModel.bannerKind : ""
        batteryReading: window.batteryReading
        privacy: window.privacy
        batteryPowerAvailable: window.batteryPowerAvailable
        onBatteryPowerRequested: window.batteryPowerRequested()
        peekActive: !!window.peekModel && window.peekModel.active
        peekKind: window.peekModel ? window.peekModel.kind : "track"
        peekEvent: window.peekModel ? window.peekModel.event : null
        powerKind: window.peekModel ? window.peekModel.powerKind : "plugged"
        powerLevel: window.peekModel ? window.peekModel.powerLevel : 0
        lyricsSource: window.lyricsSource
        appIcon: window.appIcon
        dropInSupported: window.dropInSupported
        dragOutSupported: window.dragOutSupported
        barCentreShared: window.barCentreShared
        barHasClock: window.barHasClock
        barCentreSpan: window.barCentreSpan
    }
}
