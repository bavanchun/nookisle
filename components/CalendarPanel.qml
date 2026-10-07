pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Calendar.js" as Calendar

// The Home calendar: the month and year, a snapping day wheel from a week
// back to two weeks ahead, and the selected day's events and reminders. It
// reads everything from `source`, a CalendarSource (items, setCompleted), so
// the tests feed it a fake. The owner passes the settings in `options`, the
// source definitions in `sources`, and calls refresh() when it shows. A
// one-shot timer moves the panel to the new local day at midnight.
Item {
    id: root
    required property var tokens
    property var source: null
    property var sources: []
    property var options: ({ hideCompletedReminders: true, hideAllDayEvents: false,
        autoScrollToNextEvent: true, showFullEventTitles: false, calendarSelection: [] })
    // Narrower list while the camera shares Home.
    property bool compact: false
    property var now: new Date()
    // Opens a local source's file or folder; replaceable in tests.
    property var opener: function (url) { Qt.openUrlExternally(url) }
    property var selectedDay: Calendar.startOfDay(now)
    // With no calendar configured, the panel offers to add one instead of
    // saying the day is empty.
    readonly property bool noCalendars: !sources || sources.length === 0
    signal addCalendarRequested()
    readonly property var days: Calendar.dayRange(now)
    readonly property int todayIndex: Calendar.DAYS_BACK
    readonly property var rows: Calendar.itemsForDay(source && source.items ? source.items : [], selectedDay, options)
    readonly property bool showingToday: Calendar.sameDay(selectedDay, now)
    readonly property int scrollTarget: showingToday && options.autoScrollToNextEvent !== false
        ? Calendar.scrollTarget(rows, now) : -1
    property bool calendarScrollTouched: false
    property bool calendarAligning: false
    readonly property int listWidth: compact ? 170 : 215
    readonly property string errorCode: source && source.actionError ? String(source.actionError)
        : source && source.errors && source.errors.length ? String(source.errors[0].code || "")
        : source && source.lastStatus && source.lastStatus !== "ok" ? String(source.lastStatus) : ""
    // The notch ink at an alpha, for the muted labels.
    function ink(alpha) {
        return Qt.rgba(tokens.text.r, tokens.text.g, tokens.text.b, tokens.highContrast ? 1 : alpha);
    }
    implicitWidth: listWidth
    implicitHeight: header.y + header.height + wheel.height + 120 + 8 * 2

    // The owner calls this whenever the panel is shown: the current time,
    // with today selected and in view. While the panel stays visible, its
    // one clock (nextDay, below) calls it again just after midnight.
    function refresh(date) {
        var changedDay = !Calendar.sameDay(now, date);
        now = date;
        selectedDay = Calendar.startOfDay(now);
        wheel.currentIndex = todayIndex;
        wheel.positionViewAtIndex(todayIndex, ListView.Center);
        calendarScrollTouched = false;
        Qt.callLater(scrollToTarget);
        if (changedDay && source && typeof source.refresh === "function")
            source.refresh();
        armNextDay();
    }
    function armNextDay() {
        nextDay.stop();
        if (!root.visible) return;
        var current = new Date();
        nextDay.interval = Math.max(1000, Calendar.addDays(Calendar.startOfDay(current), 1).getTime() - current.getTime() + 1000);
        nextDay.start();
    }
    onVisibleChanged: if (visible) armNextDay(); else nextDay.stop()
    Timer {
        id: nextDay
        repeat: false
        onTriggered: root.refresh(new Date())
    }
    function selectDay(index) {
        if (index < 0 || index >= days.length)
            return;
        selectedDay = days[index];
        wheel.currentIndex = index;
    }
    function focusDay(index) {
        if (index < 0 || index >= wheel.count)
            return false;
        wheel.positionViewAtIndex(index, ListView.Contain);
        wheel.forceLayout();
        var target = wheel.itemAtIndex(index);
        if (!target)
            return false;
        target.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }
    function focusRow(index, lastControl) {
        if (index < 0 || index >= list.count)
            return false;
        calendarScrollTouched = true;
        list.positionViewAtIndex(index, ListView.Contain);
        list.forceLayout();
        var target = list.itemAtIndex(index);
        if (!target)
            return false;
        var control = lastControl && target.checkControl.visible ? target.checkControl : target;
        control.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }
    // Focus the first Tab stop outside the calendar, after it or before it.
    // Explicit, because Qt's own order through a ListView follows delegate
    // creation, not day order, so an unaccepted key could land on a day.
    function leave(forward) {
        var item = root;
        for (var guard = 0; guard < 1000; ++guard) {
            item = item.nextItemInFocusChain(forward);
            if (!item || item === root)
                return false;
            var inside = false;
            for (var node = item; node; node = node.parent)
                if (node === root) { inside = true; break; }
            if (!inside) {
                item.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
                return true;
            }
        }
        return false;
    }
    function toggle(item) {
        if (item.todo && root.source && typeof root.source.setCompleted === "function")
            root.source.setCompleted(item.sourceId, item.uid, !item.completed);
    }
    function activate(item) {
        var target = Calendar.openTarget(item, root.sources);
        if (target)
            root.opener(target);
    }
    // Rows change with the day, a new window page or a completion; the list
    // then opens at the current or next event.
    onRowsChanged: {
        calendarScrollTouched = false;
        Qt.callLater(scrollToTarget);
    }
    function scrollToTarget() {
        if (calendarScrollTouched)
            return;
        calendarAligning = true;
        list.forceLayout();
        if (scrollTarget >= 0) {
            list.positionViewAtIndex(scrollTarget, ListView.Beginning);
            list.forceLayout();
            var target = list.itemAtIndex(scrollTarget);
            if (target)
                list.contentY = Math.min(target.y, Math.max(0, list.contentHeight - list.height));
        } else
            list.positionViewAtBeginning();
        Qt.callLater(function () { root.calendarAligning = false; });
    }
    Component.onCompleted: {
        wheel.currentIndex = todayIndex;
        wheel.positionViewAtIndex(todayIndex, ListView.Center);
        scrollToTarget();
        armNextDay();
    }

    // Where the month's capitals start, so a host can put them on its own
    // top line (Home puts them level with the cover and the title).
    property real capTop: 0
    FontMetrics {
        id: monthMetrics
        font: monthText.font
    }
    Row {
        id: header
        y: Math.round(root.capTop - (monthMetrics.ascent + monthMetrics.tightBoundingRect("H").y))
        width: root.listWidth
        spacing: 6
        Text {
            id: monthText
            objectName: "calendarMonth"
            text: Calendar.MONTHS[root.selectedDay.getMonth()]
            textFormat: Text.PlainText
            color: root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.titleSize + 4
            font.weight: Font.DemiBold
        }
        Text {
            objectName: "calendarYear"
            anchors.baseline: monthText.baseline
            text: root.selectedDay.getFullYear()
            textFormat: Text.PlainText
            color: root.ink(0.6)
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.titleSize + 4
            font.weight: Font.Light
        }
    }
    ListView {
        id: wheel
        objectName: "calendarWheel"
        y: header.y + header.height + 8
        width: root.listWidth
        height: 40
        orientation: ListView.Horizontal
        snapMode: ListView.SnapToItem
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        spacing: 2
        model: root.days
        delegate: Item {
            id: day
            required property var modelData
            required property int index
            readonly property bool today: Calendar.sameDay(modelData, root.now)
            readonly property bool selected: Calendar.sameDay(modelData, root.selectedDay)
            objectName: "calendarDay-" + index
            width: 28
            height: wheel.height
            activeFocusOnTab: true
            onActiveFocusChanged: if (activeFocus) wheel.positionViewAtIndex(index, ListView.Contain)
            Accessible.role: Accessible.Button
            Accessible.name: Qt.formatDate(day.modelData, "dddd, d MMMM yyyy")
            Accessible.onPressAction: root.selectDay(day.index)
            // Tab moves through the days, then the rows; at either end of the
            // calendar it leaves for the next Tab stop instead of wrapping, so
            // the calendar never traps focus inside Home.
            Keys.onTabPressed: event => {
                event.accepted = root.focusDay(day.index + 1) || root.focusRow(0, false) || root.leave(true);
            }
            Keys.onBacktabPressed: event => {
                event.accepted = root.focusDay(day.index - 1) || root.leave(false);
            }
            Keys.onReturnPressed: event => { event.accepted = true; root.selectDay(day.index); }
            Keys.onEnterPressed: event => { event.accepted = true; root.selectDay(day.index); }
            Keys.onSpacePressed: event => { event.accepted = true; root.selectDay(day.index); }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Calendar.WEEKDAYS[day.modelData.getDay()]
                textFormat: Text.PlainText
                color: root.ink(day.selected ? 0.9 : 0.5)
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.captionSize - 1
            }
            Rectangle {
                objectName: "calendarDayCircle"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 20
                height: 20
                radius: 10
                color: day.selected ? root.tokens.text : "transparent"
                border.color: day.activeFocus ? root.tokens.accent : day.today ? root.tokens.text : "transparent"
                border.width: day.activeFocus ? root.tokens.focusWidth : day.today && !day.selected ? 1 : 0
                Text {
                    anchors.centerIn: parent
                    text: day.modelData.getDate()
                    textFormat: Text.PlainText
                    color: day.selected ? root.tokens.surface : root.tokens.text
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    font.weight: day.today ? Font.DemiBold : Font.Normal
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.selectDay(day.index)
            }
        }
    }
    ListView {
        id: list
        objectName: "calendarList"
        y: notice.visible ? notice.y + notice.height + 4 : wheel.y + wheel.height + 8
        width: root.listWidth
        height: Math.max(0, Math.min(120 - (notice.visible ? notice.height + 4 : 0), root.height - y))
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        footer: Item { height: root.scrollTarget >= 0 ? list.height : 0 }
        onContentHeightChanged: if (!root.calendarScrollTouched) Qt.callLater(root.scrollToTarget)
        onContentYChanged: if (!root.calendarAligning) root.calendarScrollTouched = true
        onMovementStarted: root.calendarScrollTouched = true
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            property alias checkControl: check
            objectName: "calendarRow-" + index
            width: list.width
            height: Math.max(28, details.implicitHeight)
            activeFocusOnTab: true
            onActiveFocusChanged: if (activeFocus) {
                root.calendarScrollTouched = true;
                list.positionViewAtIndex(index, ListView.Contain);
            }
            Accessible.role: Accessible.Button
            Accessible.name: row.modelData.title || "Untitled"
            Accessible.onPressAction: root.activate(row.modelData)
            Keys.onTabPressed: event => {
                if (check.visible) {
                    check.forceActiveFocus(Qt.TabFocusReason);
                    event.accepted = true;
                } else
                    event.accepted = root.focusRow(row.index + 1, false) || root.leave(true);
            }
            Keys.onBacktabPressed: event => {
                event.accepted = root.focusRow(row.index - 1, true) || root.focusDay(wheel.count - 1);
            }
            Keys.onReturnPressed: event => { event.accepted = true; root.activate(row.modelData); }
            Keys.onEnterPressed: event => { event.accepted = true; root.activate(row.modelData); }
            Keys.onSpacePressed: event => { event.accepted = true; root.activate(row.modelData); }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: row.activeFocus ? root.tokens.focusWidth : 0
                border.color: root.tokens.accent
                radius: 4
            }
            Rectangle {
                objectName: "calendarBar"
                width: 3
                height: parent.height
                radius: 1.5
                color: row.modelData.color || root.tokens.secondary
            }
            // A reminder's check circle: a 14 px ring, filled with an 8 px dot
            // once completed.
            Item {
                id: check
                objectName: "calendarCheck"
                visible: row.modelData.todo === true
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 14 : 0
                height: 14
                activeFocusOnTab: visible
                onActiveFocusChanged: if (activeFocus) {
                    root.calendarScrollTouched = true;
                    list.positionViewAtIndex(row.index, ListView.Contain);
                }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Complete " + (row.modelData.title || "reminder")
                Accessible.checked: row.modelData.completed === true
                Accessible.onPressAction: root.toggle(row.modelData)
                Keys.onTabPressed: event => {
                    event.accepted = root.focusRow(row.index + 1, false) || root.leave(true);
                }
                Keys.onBacktabPressed: event => {
                    row.forceActiveFocus(Qt.TabFocusReason);
                    event.accepted = true;
                }
                Keys.onReturnPressed: event => { event.accepted = true; root.toggle(row.modelData); }
                Keys.onEnterPressed: event => { event.accepted = true; root.toggle(row.modelData); }
                Keys.onSpacePressed: event => { event.accepted = true; root.toggle(row.modelData); }
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: "transparent"
                    border.color: check.activeFocus ? root.tokens.accent : row.modelData.color || root.tokens.text
                    border.width: check.activeFocus ? root.tokens.focusWidth : 1.5
                }
                Rectangle {
                    objectName: "calendarCheckDot"
                    visible: row.modelData.completed === true
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: row.modelData.color || root.tokens.text
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: root.toggle(row.modelData)
                }
            }
            MouseArea {
                x: details.x
                width: parent.width - x
                height: parent.height
                onClicked: root.activate(row.modelData)
            }
            Column {
                id: details
                x: check.visible ? check.x + check.width + 6 : 8
                width: parent.width - x
                Text {
                    objectName: "calendarTitle"
                    width: parent.width
                    text: row.modelData.title || "Untitled"
                    textFormat: Text.PlainText
                    color: row.modelData.todo && row.modelData.completed ? root.ink(0.5) : root.tokens.text
                    font.strikeout: row.modelData.todo === true && row.modelData.completed === true
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.bodySize
                    elide: root.options.showFullEventTitles === true ? Text.ElideNone : Text.ElideRight
                    wrapMode: root.options.showFullEventTitles === true ? Text.WordWrap : Text.NoWrap
                    maximumLineCount: root.options.showFullEventTitles === true ? 3 : 1
                }
                Text {
                    objectName: "calendarTime"
                    width: parent.width
                    visible: text.length > 0
                    text: Calendar.timeLabel(row.modelData)
                        + (row.modelData.location ? " · " + row.modelData.location : "")
                    textFormat: Text.PlainText
                    color: root.ink(0.6)
                    elide: Text.ElideRight
                    font.features: root.tokens.numberFeatures
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                }
                Text {
                    objectName: "calendarUnsupported"
                    width: parent.width
                    visible: !!row.modelData.unsupported
                        && row.modelData.unsupported.indexOf("RRULE") >= 0
                    text: "Repeats · pattern not fully supported"
                    textFormat: Text.PlainText
                    color: root.ink(0.65)
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: Math.max(9, root.tokens.captionSize - 1)
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "Repeats — pattern not fully supported"
                }
            }
        }
        Text {
            objectName: "calendarEmpty"
            visible: list.count === 0 && !root.noCalendars
            anchors.centerIn: parent
            text: root.showingToday ? "Nothing on today" : "Nothing on this day"
            textFormat: Text.PlainText
            color: root.ink(0.5)
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
    }
    Column {
        objectName: "calendarNone"
        visible: root.noCalendars
        x: (root.listWidth - width) / 2
        y: wheel.y + wheel.height + 16
        spacing: root.tokens.gap
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No calendars yet"
            textFormat: Text.PlainText
            color: root.ink(0.6)
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
        IslandButton {
            objectName: "calendarAddButton"
            anchors.horizontalCenter: parent.horizontalCenter
            tokens: root.tokens
            tonal: true
            text: "Add calendar"
            accessibleLabel: "Add a calendar in the settings"
            onActivated: root.addCalendarRequested()
            Keys.onReturnPressed: event => { event.accepted = true; root.addCalendarRequested(); }
            Keys.onEnterPressed: event => { event.accepted = true; root.addCalendarRequested(); }
        }
    }
    Text {
        id: notice
        objectName: "calendarError"
        y: wheel.y + wheel.height + 8
        width: root.listWidth
        height: visible ? Math.min(28, implicitHeight) : 0
        visible: root.errorCode.length > 0
        text: visible ? Calendar.errorText(root.errorCode) : ""
        textFormat: Text.PlainText
        color: root.tokens.error
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 2
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
}
