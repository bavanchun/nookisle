import QtQuick
import Quickshell

// The first-run welcome, 400x600. Closing the window counts as skipping the
// rest; either way the Service records that onboarding is done.
FloatingWindow {
    id: window
    required property var tokens
    property var coordinator: null
    property bool closingFromService: false
    signal finished
    title: "Welcome to Nookisle"
    // Fixed, so Hyprland floats and centres it like the settings window.
    implicitWidth: 400
    implicitHeight: 600
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    color: tokens.surface
    onClosed: if (!closingFromService) finished()
    OnboardingView {
        anchors.fill: parent
        tokens: window.tokens
        coordinator: window.coordinator
        hostVisible: window.visible
        onFinished: window.finished()
    }
}
