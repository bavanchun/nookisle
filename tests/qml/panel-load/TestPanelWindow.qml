import QtQuick
import Quickshell

// A layer-shell PanelWindow cannot exist without a Wayland (or X11) backend,
// which the offscreen test platform has none of. This is the one
// substitution the full-Panel load test makes: a plain Quickshell window
// with the PanelWindow members the plugin binds (anchors, margins, the
// exclusion mode), so every binding and handler of the production Panel
// and IslandWindow still compiles and runs.
FloatingWindow {
    property TestPanelAnchors anchors: TestPanelAnchors {}
    property TestPanelMargins margins: TestPanelMargins {}
    property int exclusionMode: ExclusionMode.Normal
    property int exclusiveZone: 0
}
