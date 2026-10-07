import QtQuick
import QtTest
import "../.."

TestCase {
    id: test
    name: "BarWidget"
    width: 800
    height: 80
    when: windowShown
    visible: true

    QtObject {
        id: coordinator
        property bool panelAllowed: true
        property bool autoShow: true
        property bool islandPointerActive: false
        property string islandScreenName: ""
        property var spanNotes: []
        property var placementNotes: []
        function noteBarCentreSpan(screen, span) {
            spanNotes = spanNotes.concat([{ screen: screen, span: span }])
        }
        function noteBarPlacement(screen, offCentre) {
            placementNotes = placementNotes.concat([{ screen: screen, offCentre: offCentre }])
        }
    }
    QtObject {
        id: host
        function serviceFor(name) { return coordinator }
    }
    QtObject {
        id: hostBar
        property bool vertical: false
        property string position: "top"
        property bool barHidden: false
        property int barSize: 26
        property var shell: host
        property var centerPeekCalls: []
        function setCenterHoverRevealSuppressed(suppressed) {
            centerPeekCalls = centerPeekCalls.concat([suppressed])
        }
    }
    Component {
        id: widgetComponent
        BarWidget {
            bar: hostBar
            width: implicitWidth
            height: implicitHeight
        }
    }

    function init() {
        coordinator.panelAllowed = true
        coordinator.autoShow = true
        coordinator.islandPointerActive = false
        coordinator.islandScreenName = ""
        coordinator.spanNotes = []
        coordinator.placementNotes = []
        hostBar.vertical = false
        hostBar.position = "top"
        hostBar.barHidden = false
        hostBar.barSize = 26
        hostBar.centerPeekCalls = []
    }

    function test_topHorizontalEntryIsOnlyASpacer() {
        var widget = createTemporaryObject(widgetComponent, test)
        verify(widget.spacerAllowed)
        verify(widget.visible)
        compare(widget.implicitHeight, hostBar.barSize)
        verify(widget.implicitWidth > 0)
        compare(widget.Accessible.name, "Nookisle")
        verify(!findChild(widget, "barDetailsButton"))
        verify(!findChild(widget, "barPlayButton"))
        verify(!findChild(widget, "barGroupSurface"))
    }

    function test_hiddenTopBarDoesNotControlIslandAvailability() {
        hostBar.barHidden = true
        var widget = createTemporaryObject(widgetComponent, test)
        verify(widget.spacerAllowed)
        verify(widget.visible, "barHidden does not switch the island off")
        verify(widget.implicitWidth > 0)
    }

    function test_nonTopOrVerticalLayoutsHaveNoWidget_data() {
        return [
            { tag: "bottom", position: "bottom", vertical: false },
            { tag: "left", position: "left", vertical: true },
            { tag: "right", position: "right", vertical: true }
        ]
    }
    function test_nonTopOrVerticalLayoutsHaveNoWidget(data) {
        hostBar.position = data.position
        hostBar.vertical = data.vertical
        var widget = createTemporaryObject(widgetComponent, test)
        verify(!widget.spacerAllowed)
        verify(!widget.visible)
        compare(widget.implicitWidth, 0)
        compare(widget.implicitHeight, 0)
    }

    function test_admissionAndAutoShowOnlyHideTheSpacer_data() {
        return [
            { tag: "locked", panelAllowed: false, autoShow: true },
            { tag: "auto-show-off", panelAllowed: true, autoShow: false }
        ]
    }
    function test_admissionAndAutoShowOnlyHideTheSpacer(data) {
        coordinator.panelAllowed = data.panelAllowed
        coordinator.autoShow = data.autoShow
        var widget = createTemporaryObject(widgetComponent, test)
        verify(widget.spacerAllowed)
        verify(!widget.visible)
        verify(widget.implicitWidth > 0, "the host keeps stable spacer geometry")
    }

    function test_centerPeekSuppressionTracksPointer() {
        var widget = createTemporaryObject(widgetComponent, test)
        coordinator.islandPointerActive = true
        compare(hostBar.centerPeekCalls, [true])
        coordinator.islandPointerActive = false
        compare(hostBar.centerPeekCalls, [true, false])
        widget.destroy()
    }

    function test_nonSpacerNeverSuppressesCenterPeek() {
        hostBar.position = "bottom"
        var widget = createTemporaryObject(widgetComponent, test)
        coordinator.islandPointerActive = true
        compare(hostBar.centerPeekCalls, [])
        widget.destroy()
    }
}
