import QtQuick
import Quickshell
// Quickshell indexes only directories reached by a static import from here.
// The harness loads the staged Service by URL, and its `import "components"`
// finds types only once that directory is indexed; the real host loads
// plugins by file URL, where directory imports need no index.
import "build/package/components" as StagedComponents

// Keeps the isolated test's import root at the project boundary. No desktop UI
// configuration is loaded; the runner forces the offscreen Qt platform.
ShellRoot {
    Loader { source: "tests/qml/lifecycle-harness.qml" }
}
