import QtQuick
import QtQuick.Shapes

// The drop target outline: a 3 px dashed rounded stroke that fades from
// white at 10 % to the accent at 90 % while a drag hovers. A path, not an
// effect, so it draws the same under the software renderer.
Shape {
    id: root
    property var ink
    property bool active: false
    property real radius: 12
    // Drawn at rest too (the shelf's drop zone), not only while a drag hovers.
    property bool resting: false
    readonly property real inset: 1.5
    visible: resting || active || strokePath.strokeColor.a > 0.11
    preferredRendererType: Shape.GeometryRenderer
    ShapePath {
        id: strokePath
        strokeWidth: 3
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 2]
        fillColor: "transparent"
        strokeColor: root.active ? Qt.rgba(root.ink.accent.r, root.ink.accent.g, root.ink.accent.b, 0.9) : Qt.rgba(1, 1, 1, 0.1)
        Behavior on strokeColor { ColorAnimation { duration: root.ink.duration } }
        startX: root.inset + root.radius; startY: root.inset
        PathLine { x: root.width - root.inset - root.radius; y: root.inset }
        PathArc { x: root.width - root.inset; y: root.inset + root.radius; radiusX: root.radius; radiusY: root.radius }
        PathLine { x: root.width - root.inset; y: root.height - root.inset - root.radius }
        PathArc { x: root.width - root.inset - root.radius; y: root.height - root.inset; radiusX: root.radius; radiusY: root.radius }
        PathLine { x: root.inset + root.radius; y: root.height - root.inset }
        PathArc { x: root.inset; y: root.height - root.inset - root.radius; radiusX: root.radius; radiusY: root.radius }
        PathLine { x: root.inset; y: root.inset + root.radius }
        PathArc { x: root.inset + root.radius; y: root.inset; radiusX: root.radius; radiusY: root.radius }
    }
}
