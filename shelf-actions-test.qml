import QtQuick
import Quickshell

// Keeps the ShelfActions test's import root at the project boundary, like
// lifecycle-test.qml; the runner forces the offscreen Qt platform.
ShellRoot {
    Loader { source: "tests/qml/shelf-actions-harness.qml" }
}
