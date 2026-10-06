import QtQuick
import Quickshell

// Keeps the LyricsFetch test's import root at the project boundary, like
// shelf-actions-test.qml; the runner forces the offscreen Qt platform.
ShellRoot {
    Loader { source: "tests/qml/lyrics-fetch-harness.qml" }
}
