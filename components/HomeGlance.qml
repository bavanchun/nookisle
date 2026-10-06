pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../qml/Calendar.js" as Calendar

// Home with nothing playing: the time, large, over the date and, with the
// calendar on, the event happening now or next. The time moves on with a
// one-shot timer armed to the next minute boundary, and only while the
// glance is on screen, so an idle open island costs one wake-up a minute.
Item {
    id: root
    required property var tokens
    // The calendar's items and options, or empty with the calendar off.
    property var calendarItems: []
    property var calendarOptions: ({})
    property var now: new Date()
    readonly property bool hostVisible: !root.Window.window || root.Window.window.visible
    readonly property bool ticking: visible && hostVisible
    readonly property var next: calendarItems.length > 0
        ? Calendar.nextEvent(Calendar.itemsForDay(calendarItems, Calendar.startOfDay(now), calendarOptions), now) : null
    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight
    function tick() {
        now = new Date();
        arm();
    }
    function arm() {
        minute.stop();
        if (!ticking)
            return;
        var current = new Date();
        minute.interval = Math.max(1000, 60000 - current.getSeconds() * 1000 - current.getMilliseconds() + 50);
        minute.start();
    }
    onTickingChanged: if (ticking) tick(); else minute.stop()
    Component.onCompleted: if (ticking) arm()
    Timer {
        id: minute
        objectName: "glanceMinute"
        repeat: false
        onTriggered: root.tick()
    }
    Column {
        id: column
        width: root.width
        Text {
            objectName: "glanceTime"
            text: Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat))
            color: root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: 34
            font.weight: Font.Light
            font.features: root.tokens.numberFeatures
            textFormat: Text.PlainText
        }
        Text {
            objectName: "glanceDate"
            width: parent.width
            text: Qt.formatDate(root.now, "dddd, d MMMM")
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.bodySize
            font.weight: Font.Medium
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            objectName: "glanceEvent"
            width: parent.width
            visible: root.next !== null
            text: root.next ? root.next.when + " · " + root.next.title : ""
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.features: root.tokens.numberFeatures
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
}
