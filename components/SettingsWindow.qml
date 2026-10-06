import QtQuick
import Quickshell

// The settings window: a fixed 700x600, in the dark tokens. The Service
// owns its lifetime and opens it from the settings() verb, the legacy
// settings view, and later the header gear; its own closed signal tells the
// Service the user closed it.
FloatingWindow {
    id: window
    required property var tokens
    property var coordinator: null
    readonly property alias section: pane.currentSection
    function showSection(id) { return pane.showSection(id) }
    title: "Nookisle Settings"
    // One size, like boring.notch's settings window: a toplevel whose
    // minimum and maximum sizes match is a fixed-size dialog to the
    // compositor, which Hyprland floats and centres instead of tiling it
    // across the workspace.
    implicitWidth: 700
    implicitHeight: 600
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    color: tokens.surface
    SettingsPane {
        id: pane
        anchors.fill: parent
        tokens: window.tokens
        coordinator: window.coordinator
        screens: Quickshell.screens.map(screen => screen.name)
    }
}
