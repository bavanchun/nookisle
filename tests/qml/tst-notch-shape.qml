import QtQuick
import QtQuick.Shapes
import QtTest
import "../../components"

TestCase {
    id: test
    name: "NotchShape"
    width: 720
    height: 240
    when: windowShown
    visible: true
    DesignTokens {
        id: design
    }
    Component {
        id: shapeComponent
        NotchShape {
            fillColor: design.notchColor
        }
    }
    // The boring.notch outline for a rect of width w and height h with top
    // (flare) radius f and bottom radius r: each element's end point and,
    // for a quad, its control point.
    function expected(w, h, f, r) {
        return [
            { x: f, y: f, controlX: f, controlY: 0 },
            { x: f, y: h - r },
            { x: f + r, y: h, controlX: f, controlY: h },
            { x: w - f - r, y: h },
            { x: w - f, y: h - r, controlX: w - f, controlY: h },
            { x: w - f, y: f },
            { x: w, y: 0, controlX: w - f, controlY: 0 },
            { x: 0, y: 0 }
        ];
    }
    function comparePath(shape, points) {
        var elements = shape.outline.pathElements;
        compare(shape.outline.startX, 0);
        compare(shape.outline.startY, 0);
        compare(elements.length, points.length);
        for (var i = 0; i < points.length; ++i)
            for (var key in points[i])
                fuzzyCompare(elements[i][key], points[i][key], 1e-9, "element " + i + " " + key);
    }
    function test_path_data() {
        return [
            { tag: "closed", w: design.liveWidth, h: 26, f: design.flareClosed, r: design.bottomRadiusClosed },
            { tag: "open", w: design.openWidth, h: design.openHeight, f: design.flareOpen, r: design.bottomRadiusOpen }
        ];
    }
    function test_path(data) {
        var shape = createTemporaryObject(shapeComponent, test,
            { width: data.w, height: data.h, flare: data.f, bottomRadius: data.r });
        comparePath(shape, expected(data.w, data.h, data.f, data.r));
    }
    function test_bodyExcludesFlares_data() {
        return test_path_data();
    }
    function test_bodyExcludesFlares(data) {
        var shape = createTemporaryObject(shapeComponent, test,
            { width: data.w, height: data.h, flare: data.f, bottomRadius: data.r });
        compare(shape.bodyLeft, data.f);
        compare(shape.bodyRight, data.w - data.f);
        compare(shape.bodyWidth, data.w - 2 * data.f);
        var seam = findChild(shape, "notchTopSeam");
        compare(seam.x, data.f, "the top seam starts where the body does");
        compare(seam.width, data.w - 2 * data.f, "and spans the body alone");
        compare(seam.height, 1);
        compare(seam.color, design.notchColor);
    }
    // A radius larger than the shape can hold is clamped, so the outline
    // never folds over itself mid-morph.
    function test_radiiClampToTheShape() {
        var shape = createTemporaryObject(shapeComponent, test,
            { width: 60, height: 20, flare: 6, bottomRadius: 30 });
        compare(shape.radius, 14, "the bottom radius fits under the flare");
        comparePath(shape, expected(60, 20, 6, 14));
        shape.width = 30;
        compare(shape.radius, 9, "and inside half the body width");
        shape.flare = 40;
        compare(shape.flareSize, 15, "a flare never passes half the width");
        compare(shape.bodyWidth, 0);
        compare(shape.radius, 0);
    }
    function test_fillAndEdge() {
        var shape = createTemporaryObject(shapeComponent, test,
            { width: design.liveWidth, height: 26, flare: design.flareClosed, bottomRadius: design.bottomRadiusClosed });
        compare(shape.preferredRendererType, Shape.CurveRenderer);
        compare(shape.outline.fillColor, design.notchColor);
        compare(shape.outline.strokeWidth, -1, "no edge line by default");
        shape.edgeColor = "#40ffffff";
        compare(shape.outline.strokeWidth, 1);
    }
    // Rendered with the software renderer: the body is filled, the flares
    // leave the space under their curve clear, and the bottom corners
    // are rounded.
    function test_rendersTheOutline() {
        var shape = createTemporaryObject(shapeComponent, test,
            { width: design.openWidth, height: design.openHeight, flare: design.flareOpen, bottomRadius: design.bottomRadiusOpen });
        waitForRendering(shape);
        var image = grabImage(shape);
        // The test window is white, so the black fill is what reads dark.
        function filled(x, y) {
            var px = image.pixel(x, y);
            return px.r < 0.1 && px.g < 0.1 && px.b < 0.1;
        }
        verify(filled(shape.width / 2, 0), "the top edge is filled across the body");
        verify(filled(shape.width / 2, shape.height - 1), "down to the bottom edge");
        verify(filled(shape.flareSize - 1, 2), "a flare fills the top corner next to the body");
        verify(!filled(1, shape.flareSize - 2), "and curves out to the screen edge, clear below");
        verify(filled(shape.width - shape.flareSize, 2));
        verify(!filled(shape.width - 2, shape.flareSize - 2));
        verify(filled(shape.bodyLeft + 1, shape.height / 2), "the body's side is straight");
        verify(!filled(shape.bodyLeft + 1, shape.height - 2), "bottom-left is rounded");
        verify(!filled(shape.bodyRight - 2, shape.height - 2), "bottom-right is rounded");
    }
}
