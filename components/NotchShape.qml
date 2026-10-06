pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// The notch outline, after boring.notch's NotchShape: a concave quad flare
// at each top corner that meets the screen's top edge, straight sides, and
// quad-rounded bottom corners. The item's width includes both flares; the
// body the content lives in spans [flare, width - flare].
Shape {
    id: root
    // The top concave radius, and the bottom corner radius. Both are clamped
    // so the path stays valid at any size the morph passes through.
    property real flare: 6
    property real bottomRadius: 14
    property color fillColor: "#000000"
    // The edge line the software fallback draws in place of the shadow;
    // transparent draws none.
    property color edgeColor: "transparent"
    property real edgeWidth: 1
    readonly property real flareSize: Math.max(0, Math.min(flare, height, width / 2))
    readonly property real bodyWidth: Math.max(0, width - 2 * flareSize)
    readonly property real radius: Math.max(0, Math.min(bottomRadius, height - flareSize, bodyWidth / 2))
    readonly property real bodyLeft: flareSize
    readonly property real bodyRight: width - flareSize
    readonly property alias outline: outline
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        id: outline
        fillColor: root.fillColor
        strokeColor: root.edgeColor
        strokeWidth: root.edgeColor.a > 0 ? root.edgeWidth : -1
        startX: 0
        startY: 0
        PathQuad { x: root.flareSize; y: root.flareSize; controlX: root.flareSize; controlY: 0 }
        PathLine { x: root.flareSize; y: root.height - root.radius }
        PathQuad { x: root.flareSize + root.radius; y: root.height; controlX: root.flareSize; controlY: root.height }
        PathLine { x: root.width - root.flareSize - root.radius; y: root.height }
        PathQuad { x: root.width - root.flareSize; y: root.height - root.radius; controlX: root.width - root.flareSize; controlY: root.height }
        PathLine { x: root.width - root.flareSize; y: root.flareSize }
        PathQuad { x: root.width; y: 0; controlX: root.width - root.flareSize; controlY: 0 }
        PathLine { x: 0; y: 0 }
    }
    // A 1 px strip of the fill across the top of the body, so no
    // antialiased seam shows between the notch and the screen edge.
    Rectangle {
        objectName: "notchTopSeam"
        x: root.flareSize
        y: 0
        width: root.bodyWidth
        height: 1
        color: root.fillColor
    }
}
