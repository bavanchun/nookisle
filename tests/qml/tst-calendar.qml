import QtQuick
import QtTest
import "../../components"
import "../../qml/Calendar.js" as Calendar
import "../../qml/Settings.js" as Settings

TestCase {
    name: "CalendarSource"
    // The window the panel and editor cases below click in.
    width: 480
    height: 800
    visible: true
    Item {
        id: fake
        property bool showCalendar: true
        property var fileSettings: ({ calendarSources: [], calendarRefresh: 15 })
        property var sent: []
        signal calendarFrame(var frame)
        function calendarSend(type, fields) {
            sent = sent.concat([{ type: type, fields: fields }])
            return true
        }
    }
    Component { id: sourceComponent; CalendarSource {} }
    // The idle Home's line: the event happening now, or the next one today,
    // with a relative time under an hour and the clock time beyond.
    function test_nextEventLine() {
        var rows = Calendar.itemsForDay(fixtureItems(), Calendar.startOfDay(noon), {})
        compare(Calendar.nextEvent(rows, noon), { title: "Lunch", when: "Now" })
        compare(Calendar.nextEvent(rows, new Date(2026, 8, 26, 12, 40)), { title: "Remote call", when: "In 20 min" })
        compare(Calendar.nextEvent(rows, new Date(2026, 8, 26, 13, 40)), { title: "Review", when: "15:00" })
        compare(Calendar.nextEvent(rows, new Date(2026, 8, 26, 17, 30)), { title: "Pay rent", when: "In 30 min" },
            "a reminder that is due counts")
        compare(Calendar.nextEvent(rows, new Date(2026, 8, 26, 23, 0)), null, "nothing left today")
        compare(Calendar.nextEvent([], noon), null)
    }
    function test_configure_and_pages() {
        var source = createTemporaryObject(sourceComponent, this)
        source.coordinator = fake
        compare(fake.sent[0].type, "calendarConfigure")
        fake.calendarFrame({ type: "calendarResult", requestId: fake.sent[0].fields.requestId, status: "ok" })
        compare(fake.sent[1].type, "calendarWindow")
        fake.calendarFrame({ type: "calendarWindowResult", requestId: fake.sent[1].fields.requestId, items: [{ uid: "one" }], errors: [], nextOffset: 1 })
        compare(source.items.length, 1)
        compare(fake.sent[2].fields.offset, 1)
        fake.calendarFrame({ type: "calendarWindowResult", requestId: fake.sent[2].fields.requestId, items: [{ uid: "two" }], errors: [], nextOffset: -1 })
        compare(source.items.length, 2)
        verify(source.setCompleted("source", "one", true))
        compare(fake.sent[3].type, "calendarSetCompleted")
        fake.calendarFrame({ type: "calendarResult", requestId: "stale", status: "ok" })
        compare(source.pending, true)
        fake.calendarFrame({ type: "calendarResult", requestId: fake.sent[3].fields.requestId, status: "ok" })
        compare(fake.sent[4].type, "calendarWindow")
        fake.calendarFrame({ type: "calendarWindowResult", requestId: fake.sent[4].fields.requestId, items: [], errors: [], nextOffset: -1 })
        verify(source.storeCredential("https://example.com/dav/", "person", "fixture"))
        compare(fake.sent[5].type, "calendarCredential")
    }
    // A locked or missing keyring reads as such, never as a refused password.
    function test_keyringErrorsHaveTheirOwnText() {
        for (var code of ["secret-service-locked", "secret-service-unavailable", "secret-service-error"]) {
            verify(Calendar.errorText(code).indexOf("Error:") !== 0, code)
            verify(Calendar.errorText(code) !== Calendar.errorText("auth-error"), code)
        }
    }
    function test_dayRefreshWaitsForCurrentPage() {
        fake.sent = []
        var source = createTemporaryObject(sourceComponent, this)
        source.coordinator = fake
        var configureId = fake.sent[0].fields.requestId
        source.refresh()
        verify(source.refreshDirty, "a day change while configure is pending is retained")
        fake.calendarFrame({ type: "calendarResult", requestId: configureId, status: "ok" })
        compare(fake.sent[1].type, "calendarWindow")
    }
    function test_failedCompletionKeepsItsError() {
        fake.sent = []
        var source = createTemporaryObject(sourceComponent, this)
        source.coordinator = fake
        fake.calendarFrame({ type: "calendarResult", requestId: fake.sent[0].fields.requestId, status: "ok" })
        fake.calendarFrame({ type: "calendarWindowResult", requestId: fake.sent[1].fields.requestId,
            items: [], errors: [], nextOffset: -1 })
        source.setCompleted("source", "reminder", true)
        fake.calendarFrame({ type: "calendarResult", requestId: fake.sent[2].fields.requestId,
            ok: false, error: "read-only" })
        compare(source.actionError, "read-only")
    }

    // ---- The Home panel and the source editor, against fakes ----

    DesignTokens { id: design; reducedMotion: true }
    // Friday 26 September 2026, noon, local time.
    readonly property var noon: new Date(2026, 8, 26, 12, 0)
    readonly property var localSource: ({ kind: "file", path: "/home/me/cal/work.ics", color: "#ff9f0a" })
    readonly property var remoteSource: ({ kind: "ics-url", url: "https://calendar.google.com/calendar/ical/secret-token/basic.ics" })
    function at(hours, minutes, dayOffset) {
        var d = new Date(2026, 8, 26 + (dayOffset || 0), hours, minutes || 0)
        return Qt.formatDateTime(d, "yyyy-MM-ddThh:mm:ss.zzz")
    }
    function fixtureItems() {
        var local = Calendar.sourceId(localSource), remote = Calendar.sourceId(remoteSource)
        return [
            { sourceId: local, uid: "standup", start: at(9), end: at(9, 30), title: "Standup", color: "#ff9f0a" },
            { sourceId: local, uid: "lunch", start: at(11, 30), end: at(12, 30), title: "Lunch", location: "Canteen" },
            { sourceId: local, uid: "review", start: at(15), end: at(16), title: "Review" },
            { sourceId: local, uid: "holiday", allDay: true, start: "2026-09-26T00:00:00.000", end: "2026-09-27T00:00:00.000", title: "Holiday" },
            { sourceId: local, uid: "rent", todo: true, completed: false, due: at(18), start: "", end: "", title: "Pay rent" },
            { sourceId: local, uid: "filed", todo: true, completed: true, due: at(10), start: "", end: "", title: "File taxes" },
            { sourceId: local, uid: "dentist", start: at(10, 0, 1), end: at(11, 0, 1), title: "Dentist" },
            { sourceId: remote, uid: "call", start: at(13), end: at(13, 30), title: "Remote call" }
        ]
    }
    QtObject {
        id: fakeSource
        property var items: []
        property var errors: []
        property string actionError: ""
        property string lastStatus: ""
        property bool pending: false
        property var calls: []
        property int requests: 0
        property int windowRequests: 0
        signal updated()
        signal credentialFinished(string requestId, string action, bool ok, string error)
        signal testFinished(string requestId, string sourceId, bool ok, string error)
        // Like CalendarSource: every user action is accepted with a request id
        // and answered later through the signals above.
        function record(call) { calls = calls.concat([call]); return "request-" + (++requests) }
        function setCompleted(sourceId, uid, completed) { return record(["setCompleted", sourceId, uid, completed]) }
        function refresh() { windowRequests++ }
        function testSource(sourceId) { return record(["test", sourceId]) }
        function storeCredential(url, user, password) { return record(["store", url, user, password]) }
        function clearCredential(url, user) { return record(["clear", url, user]) }
        function lastRequest() { return "request-" + requests }
    }
    QtObject {
        id: fakeCoordinator
        property var fileSettings: ({ calendarSources: [] })
        property var configured: []
        property var removed: []
        property bool refuse: false
        property var clearing: []
        function calendarClearPending(url, user) { return clearing.indexOf(url + "\n" + user) >= 0 }
        signal calendarClearFinished(string url, string user, bool ok, string error)
        function configure(options) {
            configured = configured.concat([JSON.parse(JSON.stringify(options))])
            if (refuse || !Settings.validateBatch(options)) return false
            fileSettings = Object.assign({}, fileSettings, options)
            return true
        }
        function removeCalendarSource(definition) {
            var removal = Calendar.withoutSource(fileSettings.calendarSources, definition)
            if (!removal.found || !configure({ calendarSources: removal.next })) return false
            removed = removed.concat([definition])
            return true
        }
    }
    Component {
        id: panelComponent
        CalendarPanel {
            tokens: design
            source: fakeSource
            sources: [test.localSource, test.remoteSource]
            now: test.noon
            property var opened: []
            opener: function (url) { opened = opened.concat([url]) }
        }
    }
    // The panel between two other Tab stops, as on Home.
    Component {
        id: tabHostComponent
        Column {
            property alias panel: hosted
            property alias before: beforeStop
            property alias after: afterStop
            Item { id: beforeStop; objectName: "beforeCalendar"; width: 10; height: 10; activeFocusOnTab: true }
            CalendarPanel {
                id: hosted
                width: 360
                height: 190
                tokens: design
                source: fakeSource
                sources: [test.localSource, test.remoteSource]
                now: test.noon
                opener: function (url) {}
            }
            Item { id: afterStop; objectName: "afterCalendar"; width: 10; height: 10; activeFocusOnTab: true }
        }
    }
    Component {
        id: editorComponent
        CalendarSourceEditor {
            width: 420
            tokens: design
            coordinator: fakeCoordinator
        }
    }
    function titles(rows) { return rows.map(function (row) { return row.title }) }

    TestCase {
        id: test
        name: "CalendarPanel"
        when: windowShown
        visible: true
        width: 480
        height: 480
        readonly property var localSource: parent.localSource
        readonly property var remoteSource: parent.remoteSource
        readonly property var noon: parent.noon

        function init() {
            fakeSource.items = parent.fixtureItems()
            fakeSource.errors = []
            fakeSource.actionError = ""
            fakeSource.lastStatus = ""
            fakeSource.calls = []
            fakeSource.pending = false
            fakeSource.windowRequests = 0
        }

        // The calendar draws in the tokens' ink, like the rest of Home: a
        // theme's text colour reaches it, and today is circled in that ink
        // rather than in the accent.
        function test_calendarDrawsInTheTokensInk() {
            design.theme = ({ text: "#e6d3a3" })
            var panel = createTemporaryObject(panelComponent, test)
            compare(findChild(panel, "calendarMonth").color, design.text)
            var today = findChild(panel, "calendarDay-" + panel.todayIndex)
            var circle = findChild(today, "calendarDayCircle")
            compare(circle.color, design.text, "the selected today is filled with the ink")
            compare(circle.children[0].color, design.surface, "its number is cut out of it")
            design.theme = ({})
        }

        function test_dayChangeRequestsFreshWindow() {
            var panel = createTemporaryObject(panelComponent, test)
            panel.refresh(new Date(2026, 8, 26, 18))
            compare(fakeSource.windowRequests, 0, "time passing within today uses the same page")
            panel.refresh(new Date(2026, 8, 27, 0, 1))
            compare(fakeSource.windowRequests, 1, "a new local day asks the helper for a new window")
            panel.refresh(new Date(2026, 8, 27, 12))
            compare(fakeSource.windowRequests, 1, "the new page is not requested twice")
        }

        function test_sourceAndReminderErrorsAppearWithoutBlockingRows() {
            var panel = createTemporaryObject(panelComponent, test)
            var notice = findChild(panel, "calendarError")
            verify(!notice.visible)
            fakeSource.errors = [{ sourceId: "source", code: "auth-error" }]
            compare(notice.text, Calendar.ERRORS["auth-error"])
            verify(notice.visible)
            verify(findChild(panel, "calendarList").height < 120)
            fakeSource.errors = []
            fakeSource.actionError = "read-only"
            compare(notice.text, Calendar.ERRORS["read-only"])
            compare(panel.rows.length, 6, "a notice keeps the event rows available")
            fakeSource.actionError = ""
            fakeSource.lastStatus = "window-limit"
            compare(notice.text, Calendar.ERRORS["window-limit"])
        }
        function test_unsupportedRecurrenceIsMarkedOnItsVisibleRow() {
            fakeSource.items = [Object.assign({}, parent.fixtureItems()[0], { unsupported: ["RRULE"] })]
            var panel = createTemporaryObject(panelComponent, test)
            var row = findChild(panel, "calendarRow-0")
            verify(row)
            var hint = findChild(row, "calendarUnsupported")
            verify(hint, "the row contains the recurrence hint")
            verify(hint.visible, "the RRULE hint is visible: " + JSON.stringify(row.modelData.unsupported))
            verify(hint.text.indexOf("Repeats") >= 0)
            compare(hint.Accessible.name, "Repeats — pattern not fully supported")
        }

        function test_day_range() {
            var days = Calendar.dayRange(noon)
            compare(days.length, 22)
            verify(Calendar.sameDay(days[0], new Date(2026, 8, 19)))
            verify(Calendar.sameDay(days[7], noon))
            verify(Calendar.sameDay(days[21], new Date(2026, 9, 10)))
        }

        function test_hide_rules() {
            var items = parent.fixtureItems()
            var defaults = { hideCompletedReminders: true, hideAllDayEvents: false, calendarSelection: [] }
            compare(parent.titles(Calendar.itemsForDay(items, noon, defaults)),
                ["Holiday", "Standup", "Lunch", "Remote call", "Review", "Pay rent"])
            compare(parent.titles(Calendar.itemsForDay(items, noon, { hideCompletedReminders: false })),
                ["Holiday", "Standup", "File taxes", "Lunch", "Remote call", "Review", "Pay rent"])
            compare(parent.titles(Calendar.itemsForDay(items, noon, { hideAllDayEvents: true })),
                ["Standup", "Lunch", "Remote call", "Review", "Pay rent"])
            compare(parent.titles(Calendar.itemsForDay(items, noon, { calendarSelection: [Calendar.sourceId(remoteSource)] })),
                ["Remote call"])
            compare(parent.titles(Calendar.itemsForDay(items, new Date(2026, 8, 27), defaults)), ["Dentist"])
            compare(parent.titles(Calendar.itemsForDay(items, new Date(2026, 8, 25), defaults)), [])
        }

        function test_scroll_target() {
            var rows = Calendar.itemsForDay(parent.fixtureItems(), noon, { calendarSelection: [] })
            compare(rows[Calendar.scrollTarget(rows, noon)].title, "Lunch", "the event happening now")
            compare(rows[Calendar.scrollTarget(rows, new Date(2026, 8, 26, 12, 45))].title, "Remote call", "else the next")
            compare(rows[Calendar.scrollTarget(rows, new Date(2026, 8, 26, 17, 0))].title, "Pay rent", "a reminder due later counts")
            compare(Calendar.scrollTarget(rows, new Date(2026, 8, 26, 19, 0)), -1, "all over")
        }

        function test_labels_and_targets() {
            var items = parent.fixtureItems()
            compare(Calendar.timeLabel(items[1]), "11:30 – 12:30")
            compare(Calendar.timeLabel(items[3]), "All day")
            compare(Calendar.timeLabel(items[4]), "Due 18:00")
            compare(Calendar.openTarget(items[0], [localSource, remoteSource]), "file:///home/me/cal/work.ics")
            compare(Calendar.openTarget(items[7], [localSource, remoteSource]), "", "a remote source opens nothing")
            compare(Calendar.sourceId({ kind: "caldav", url: "https://x/dav/", user: "me" }), "6e8455e25937815a",
                "the helper's source id: SHA-256 of kind, path, url and user")
        }

        function test_reminder_follows_due_not_start() {
            var reminder = { sourceId: "s", uid: "report", todo: true, completed: false,
                start: parent.at(9), due: parent.at(18), title: "Send report" }
            var meeting = { sourceId: "s", uid: "sync", start: parent.at(9, 30), end: parent.at(10, 30), title: "Sync" }
            compare(Calendar.timeLabel(reminder), "Due 18:00", "the due time, not DTSTART")
            var rows = Calendar.itemsForDay([reminder, meeting], noon, { calendarSelection: [] })
            compare(parent.titles(rows), ["Sync", "Send report"], "ordered by due time")
            compare(rows[Calendar.scrollTarget(rows, new Date(2026, 8, 26, 10, 0))].title, "Sync",
                "a reminder started earlier is not current before it is due")
            compare(rows[Calendar.scrollTarget(rows, new Date(2026, 8, 26, 11, 0))].title, "Send report",
                "it is the next target until its due time")
            compare(Calendar.scrollTarget(rows, new Date(2026, 8, 26, 18, 30)), -1)
            var startOnly = { sourceId: "s", uid: "plan", todo: true, start: parent.at(8), due: "", title: "Plan" }
            compare(Calendar.timeLabel(startOnly), "", "no due time, no due label")
            verify(Calendar.onDay(startOnly, noon), "a reminder without DUE sits at its start")
        }

        function test_all_day_reminder_follows_due_date() {
            var reminder = { sourceId: "s", uid: "visa", todo: true, allDay: true, completed: false,
                start: "2026-09-26T00:00:00.000", due: "2026-09-28T00:00:00.000", title: "Renew visa" }
            verify(!Calendar.onDay(reminder, new Date(2026, 8, 26)), "not on its start date")
            verify(Calendar.onDay(reminder, new Date(2026, 8, 28)), "on its due date")
            verify(!Calendar.onDay(reminder, new Date(2026, 8, 27)), "and only that day")
            var noDue = Object.assign({}, reminder, { due: "" })
            verify(Calendar.onDay(noDue, new Date(2026, 8, 26)), "without DUE it sits on its start date")
            verify(!Calendar.onDay(noDue, new Date(2026, 8, 28)))
        }

        function test_removal_rules() {
            var account = { kind: "caldav", url: "https://cloud.example.com/dav/", user: "me" }
            var tinted = Object.assign({ color: "#00ff00" }, account)
            var other = { kind: "caldav", url: "https://cloud.example.com/dav/", user: "you" }
            var removal = Calendar.withoutSource([localSource, account, other], account)
            compare(removal.next, [localSource, other])
            verify(removal.found)
            verify(Calendar.clearOwed(account, removal.next), "the last user of an account owes a clear")
            removal = Calendar.withoutSource([account, tinted], account)
            compare(removal.next, [tinted], "one entry at a time")
            verify(!Calendar.clearOwed(account, removal.next), "a remaining source keeps the password")
            verify(!Calendar.clearOwed(localSource, []), "only CalDAV accounts have passwords")
            verify(!Calendar.withoutSource([localSource], account).found)
        }

        // A user name or password inside a URL would be written to the
        // settings file; only the password field may carry a secret.
        function test_sources_refuse_userinfo_in_urls() {
            compare(Calendar.makeSource("caldav", { url: "https://me:fixture-secret@cloud.example.com/dav/", user: "me" }, true), null)
            compare(Calendar.makeSource("caldav", { url: "https://me@cloud.example.com/dav/", user: "me" }, true), null,
                "a user name alone is refused too")
            compare(Calendar.makeSource("ics-url", { url: "webcal://token@calendar.example/basic.ics" }, true), null)
            compare(Calendar.makeSource("ics-url", { url: "https://calendar.example/basic.ics?a=b@c" }, true).url,
                "https://calendar.example/basic.ics?a=b@c", "an @ after the host is not userinfo")
            verify(Calendar.hasUserinfo("https://me:x@cloud.example.com/"))
            verify(Calendar.hasUserinfo(" WEBCAL://me@cloud.example.com/"))
            verify(!Calendar.hasUserinfo("https://cloud.example.com/dav/@me/"))
            verify(!Calendar.hasUserinfo("https://cloud.example.com#a@b"))
        }

        function test_pending_clears_follow_the_settings() {
            var account = { kind: "caldav", url: "https://cloud.example.com/dav/", user: "me" }
            var other = { kind: "caldav", url: "https://other.example/", user: "x" }
            var pending = Calendar.clearsAfterRemoval([], account, [])
            compare(pending, [account], "only the account's identifiers are kept")
            compare(Calendar.clearsAfterRemoval(pending, account, []), [account], "once")
            compare(Calendar.clearsAfterRemoval([], account, [account]), [], "an account still in use owes nothing")
            pending = [account, other]
            var inFlight = {}
            inFlight[Calendar.accountKey(other.url, other.user)] = "request-1"
            compare(Calendar.clearsToSend(pending, [], inFlight), [account], "one already with the helper is not sent twice")
            compare(Calendar.clearsToSend(pending, [account], {}), [other], "an account configured again is skipped")
            compare(Calendar.clearsToKeep(pending, [account, other], inFlight), [other],
                "configured again: an unsent clear is dropped, one in flight stays until answered")
        }

        function test_panel_header_and_wheel() {
            var panel = createTemporaryObject(panelComponent, test)
            compare(findChild(panel, "calendarMonth").text, "September")
            compare(findChild(panel, "calendarYear").text, "2026")
            var wheel = findChild(panel, "calendarWheel")
            compare(wheel.count, 22)
            compare(wheel.snapMode, ListView.SnapToItem)
            compare(wheel.currentIndex, 7)
            compare(findChild(panel, "calendarList").width, 215)
            compare(findChild(panel, "calendarList").height, 120)
            panel.compact = true
            compare(findChild(panel, "calendarList").width, 170)
        }

        function test_panel_selects_days() {
            var panel = createTemporaryObject(panelComponent, test)
            compare(parent.titles(panel.rows), ["Holiday", "Standup", "Lunch", "Remote call", "Review", "Pay rent"])
            var tomorrow = findChild(panel, "calendarDay-8")
            mouseClick(tomorrow)
            verify(Calendar.sameDay(panel.selectedDay, new Date(2026, 8, 27)))
            compare(parent.titles(panel.rows), ["Dentist"])
            compare(panel.scrollTarget, -1, "only today auto-scrolls")
            mouseClick(findChild(panel, "calendarDay-6"))
            compare(panel.rows.length, 0)
            verify(findChild(panel, "calendarEmpty").visible)
            mouseClick(findChild(panel, "calendarDay-7"))
            compare(panel.rows.length, 6)
        }
        // With no calendar configured, the panel offers to add one rather
        // than saying the day is empty.
        function test_panel_without_calendars_offers_to_add_one() {
            fakeSource.items = []
            var panel = createTemporaryObject(panelComponent, test, { sources: [] })
            verify(!findChild(panel, "calendarEmpty").visible, "not \u201cNothing on today\u201d")
            verify(findChild(panel, "calendarNone").visible)
            var add = findChild(panel, "calendarAddButton")
            var asked = 0
            panel.addCalendarRequested.connect(function () { asked++ })
            mouseClick(add)
            compare(asked, 1)
            panel.sources = [test.localSource]
            verify(!findChild(panel, "calendarNone").visible)
            verify(findChild(panel, "calendarEmpty").visible, "with a calendar, an empty day says so")
        }
        // High contrast draws the panel's dimmed text fully white.
        function test_panel_text_is_opaque_in_high_contrast() {
            fakeSource.items = []
            var panel = createTemporaryObject(panelComponent, test)
            verify(findChild(panel, "calendarEmpty").color.a < 0.6, "dimmed normally")
            design.highContrast = true
            compare(findChild(panel, "calendarEmpty").color.a, 1)
            compare(findChild(panel, "calendarYear").color.a, 1)
            design.highContrast = false
        }
        function test_panel_days_events_and_reminders_accept_keys() {
            var panel = createTemporaryObject(panelComponent, test,
                { options: { hideCompletedReminders: false, calendarSelection: [] } })
            var day = findChild(panel, "calendarDay-8")
            verify(day.activeFocusOnTab)
            day.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Return)
            verify(Calendar.sameDay(panel.selectedDay, new Date(2026, 8, 27)))
            keyClick(Qt.Key_Tab)
            verify(panel.Window.activeFocusItem !== day, "Tab leaves a day cell")
            panel.selectDay(7)
            var list = findChild(panel, "calendarList")
            list.positionViewAtBeginning()
            waitForRendering(panel)
            var eventRow = findChild(panel, "calendarRow-0")
            verify(eventRow.activeFocusOnTab)
            eventRow.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Return)
            compare(panel.opened, ["file:///home/me/cal/work.ics"])
            list.positionViewAtIndex(panel.rows.length - 1, ListView.Beginning)
            waitForRendering(panel)
            var reminder = null
            for (var i = 0; i < 12 && !reminder; ++i) {
                var candidate = findChild(panel, "calendarRow-" + i)
                if (candidate && candidate.modelData.uid === "rent") reminder = candidate
            }
            verify(reminder)
            var check = findChild(reminder, "calendarCheck")
            verify(check.activeFocusOnTab)
            check.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Space)
            compare(fakeSource.calls, [["setCompleted", Calendar.sourceId(localSource), "rent", true]])
        }

        function test_tabTraversalKeepsFocusedCalendarItemsVisible() {
            var events = []
            for (var i = 0; i < 10; ++i)
                events.push({ sourceId: Calendar.sourceId(localSource), uid: "event-" + i,
                    start: parent.at(8 + i), end: parent.at(8 + i, 30), title: "Event " + i })
            fakeSource.items = events
            fakeSource.errors = [{ sourceId: "source", code: "auth-error" }]
            var panel = createTemporaryObject(panelComponent, test,
                { options: { autoScrollToNextEvent: false, calendarSelection: [] } })
            var wheel = findChild(panel, "calendarWheel")
            var day = findChild(panel, "calendarDay-7")
            day.forceActiveFocus(Qt.TabFocusReason)
            for (var previous = 6; previous >= 2; --previous) {
                keyClick(Qt.Key_Backtab)
                var focusedDay = panel.Window.activeFocusItem
                compare(focusedDay.objectName, "calendarDay-" + previous)
                var dayX = focusedDay.mapToItem(wheel, 0, 0).x
                verify(dayX >= -0.5 && dayX + focusedDay.width <= wheel.width + 0.5,
                    "focused day " + previous + " stays inside the wheel")
            }
            for (var following = 3; following <= 12; ++following) {
                keyClick(Qt.Key_Tab)
                var nextDay = panel.Window.activeFocusItem
                compare(nextDay.objectName, "calendarDay-" + following)
                var nextX = nextDay.mapToItem(wheel, 0, 0).x
                verify(nextX >= -0.5 && nextX + nextDay.width <= wheel.width + 0.5,
                    "focused day " + following + " stays inside the wheel")
            }
            var list = findChild(panel, "calendarList")
            verify(findChild(panel, "calendarError").visible)
            verify(list.height < 120, "the error message leaves a shorter list")
            verify(list.y + list.height <= panel.height, "the shorter list stays inside the panel")
            list.positionViewAtBeginning()
            var firstRow = findChild(panel, "calendarRow-0")
            firstRow.forceActiveFocus(Qt.TabFocusReason)
            for (var next = 1; next <= 5; ++next) {
                keyClick(Qt.Key_Tab)
                var focusedRow = panel.Window.activeFocusItem
                compare(focusedRow.objectName, "calendarRow-" + next)
                var rowY = focusedRow.mapToItem(list, 0, 0).y
                verify(rowY >= -0.5 && rowY + focusedRow.height <= list.height + 0.5,
                    "focused event row " + next + " stays inside the list")
            }
            for (var earlier = 4; earlier >= 0; --earlier) {
                keyClick(Qt.Key_Backtab)
                var previousRow = panel.Window.activeFocusItem
                compare(previousRow.objectName, "calendarRow-" + earlier)
                var previousY = previousRow.mapToItem(list, 0, 0).y
                verify(previousY >= -0.5 && previousY + previousRow.height <= list.height + 0.5,
                    "focused event row " + earlier + " stays inside the list")
            }
        }

        // Tab moves through the calendar and then out of it at either end:
        // it never traps focus inside Home.
        function test_tabLeavesTheCalendarAtItsEnds() {
            var host = createTemporaryObject(tabHostComponent, test)
            var panel = host.panel
            var wheel = findChild(panel, "calendarWheel")
            var list = findChild(panel, "calendarList")
            verify(panel.focusDay(wheel.count - 1))
            keyClick(Qt.Key_Tab)
            compare(panel.Window.activeFocusItem.objectName, "calendarRow-0",
                "Tab from the last day enters the first event row")
            keyClick(Qt.Key_Backtab)
            compare(panel.Window.activeFocusItem.objectName, "calendarDay-" + (wheel.count - 1),
                "Shift+Tab from the first event row returns to the last day")

            verify(panel.focusRow(list.count - 1, false))
            keyClick(Qt.Key_Tab)
            compare(panel.Window.activeFocusItem.objectName, "calendarCheck",
                "the last reminder's check remains in the tab order")
            keyClick(Qt.Key_Tab)
            compare(panel.Window.activeFocusItem, host.after, "Tab past the final check leaves the calendar")

            verify(panel.focusDay(0))
            keyClick(Qt.Key_Backtab)
            compare(panel.Window.activeFocusItem, host.before, "Shift+Tab before the first day leaves the calendar")

            panel.selectDay(6)
            compare(list.count, 0)
            verify(panel.focusDay(wheel.count - 1))
            keyClick(Qt.Key_Tab)
            compare(panel.Window.activeFocusItem, host.after, "with no events, Tab from the last day leaves")

            panel.selectDay(8)
            compare(list.count, 1)
            verify(panel.focusRow(0, false))
            keyClick(Qt.Key_Tab)
            compare(panel.Window.activeFocusItem, host.after, "Tab after a final event without a check leaves")
        }

        function test_panel_scrolls_to_the_current_event() {
            var panel = createTemporaryObject(panelComponent, test)
            compare(panel.scrollTarget, 2)
            var list = findChild(panel, "calendarList")
            tryVerify(function () { return list.indexAt(10, list.contentY + 1) === 2 }, 1000,
                "the list opens at Lunch")
            panel.options = Object.assign({}, panel.options, { autoScrollToNextEvent: false })
            compare(panel.scrollTarget, -1)
        }
        function test_autoScrolled_event_starts_at_the_top_after_layout_changes() {
            var panel = createTemporaryObject(panelComponent, test, {
                options: { showFullEventTitles: true, autoScrollToNextEvent: true, calendarSelection: [] },
                height: 142 })
            var list = findChild(panel, "calendarList")
            verify(list.height > 0 && list.height < 120)
            var changed = parent.fixtureItems()
            changed[3] = Object.assign({}, changed[3], {
                title: "A long all-day event whose title wraps across several lines before today's next meeting" })
            fakeSource.items = changed
            tryVerify(function () {
                var row = list.itemAtIndex(panel.scrollTarget)
                return row && Math.abs(row.y - list.contentY) < 1
            }, 1000, "the next event aligns after variable-height delegates settle")
            var target = list.itemAtIndex(panel.scrollTarget)
            verify(target && target.mapToItem(list, 0, 0).y >= -1,
                "the event title is not clipped above the list")
            panel.options = { showFullEventTitles: false, autoScrollToNextEvent: true, calendarSelection: [] }
            tryVerify(function () {
                var row = list.itemAtIndex(panel.scrollTarget)
                return row && Math.abs(row.y - list.contentY) < 1
            }, 1000, "reflow keeps the next event aligned")
        }

        function test_panel_toggles_reminders_and_opens_sources() {
            var panel = createTemporaryObject(panelComponent, test, { options: { hideCompletedReminders: false, calendarSelection: [] } })
            var list = findChild(panel, "calendarList")
            // Let the panel's own opening scroll run first.
            waitForRendering(panel)
            wait(0)
            panel.calendarScrollTouched = true
            list.positionViewAtIndex(panel.rows.length - 1, ListView.Beginning)
            waitForRendering(panel)
            var rentRow = null
            for (var i = 0; i < 12 && !rentRow; ++i) {
                var candidate = findChild(panel, "calendarRow-" + i)
                if (candidate && candidate.modelData.uid === "rent") rentRow = candidate
            }
            verify(rentRow)
            mouseClick(findChild(rentRow, "calendarCheck"))
            compare(fakeSource.calls, [["setCompleted", Calendar.sourceId(localSource), "rent", true]])
            list.positionViewAtBeginning()
            waitForRendering(panel)
            var holiday = findChild(panel, "calendarRow-0")
            verify(!findChild(holiday, "calendarCheck").visible, "events have no check circle")
            mouseClick(holiday, holiday.width - 10, holiday.height / 2)
            compare(panel.opened, ["file:///home/me/cal/work.ics"])
            var done = null
            for (var j = 0; j < 12 && !done; ++j) {
                var row = findChild(panel, "calendarRow-" + j)
                if (row && row.modelData.uid === "filed") done = row
            }
            verify(findChild(done, "calendarCheckDot").visible, "a completed reminder shows the filled dot")
        }

        function test_panel_title_modes() {
            var panel = createTemporaryObject(panelComponent, test)
            var title = findChild(findChild(panel, "calendarRow-0"), "calendarTitle")
            compare(title.elide, Text.ElideRight)
            panel.options = { showFullEventTitles: true, calendarSelection: [] }
            title = findChild(findChild(panel, "calendarRow-0"), "calendarTitle")
            compare(title.wrapMode, Text.WordWrap)
        }
    }

    TestCase {
        id: editorTest
        name: "CalendarSourceEditor"
        when: windowShown
        visible: true
        width: 480
        height: 800

        function init() {
            fakeCoordinator.fileSettings = { calendarSources: [] }
            fakeCoordinator.configured = []
            fakeCoordinator.removed = []
            fakeCoordinator.refuse = false
            fakeSource.calls = []
            fakeSource.errors = []
            fakeSource.pending = false
            fakeSource.requests = 0
        }
        // Fields appear and disappear with the kind, so the column lays out
        // again before a click lands.
        function tap(editor, name) {
            waitForRendering(editor)
            mouseClick(findChild(editor, name))
        }

        function test_adds_a_local_file() {
            var editor = createTemporaryObject(editorComponent, editorTest)
            verify(!findChild(editor, "calendarAdd").enabled)
            findChild(editor, "calendarPathField").text = "/home/me/calendar.ics"
            verify(findChild(editor, "calendarAdd").enabled)
            tap(editor, "calendarAdd")
            compare(fakeCoordinator.configured, [{ calendarSources: [{ kind: "file", path: "/home/me/calendar.ics" }] }])
            compare(findChild(editor, "calendarPathField").text, "")
            compare(findChild(editor, "calendarSourceRow-0").modelData.path, "/home/me/calendar.ics")
            findChild(editor, "calendarPathField").text = "relative.ics"
            verify(!findChild(editor, "calendarAdd").enabled, "only absolute paths")
        }

        function test_remote_needs_consent_and_hides_the_link() {
            var editor = createTemporaryObject(editorComponent, editorTest)
            tap(editor, "calendarKind-ics-url")
            findChild(editor, "calendarUrlField").text = "webcal://calendar.google.com/calendar/ical/secret-token/basic.ics"
            verify(!editor.remoteAllowed && !editor.localNetworkAllowed, "both opt-ins start off")
            verify(!findChild(editor, "calendarAdd").enabled, "no remote source without consent")
            tap(editor, "calendarAllowRemote")
            verify(findChild(editor, "calendarAdd").enabled)
            tap(editor, "calendarAdd")
            var added = fakeCoordinator.fileSettings.calendarSources[0]
            compare(added, { kind: "ics-url", url: "https://calendar.google.com/calendar/ical/secret-token/basic.ics" })
            var label = findChild(findChild(editor, "calendarSourceRow-0"), "calendarSourceLabel").text
            compare(label, "calendar.google.com (link hidden)")
            verify(label.indexOf("secret-token") < 0 && editor.notice.indexOf("secret-token") < 0)
            verify(!editor.remoteAllowed, "consent is asked again for the next source")
            findChild(editor, "calendarUrlField").text = "http://example.com/cal.ics"
            tap(editor, "calendarAllowRemote")
            verify(!findChild(editor, "calendarAdd").enabled, "plain http is refused")
        }

        function addCaldav(editor, password) {
            tap(editor, "calendarKind-caldav")
            findChild(editor, "calendarUrlField").text = "https://cloud.example.com/dav/"
            findChild(editor, "calendarUserField").text = "me"
            findChild(editor, "calendarPasswordField").text = password
            tap(editor, "calendarAllowRemote")
            tap(editor, "calendarAdd")
        }

        function test_url_with_userinfo_is_refused_with_a_hint() {
            var editor = createTemporaryObject(editorComponent, editorTest)
            tap(editor, "calendarKind-caldav")
            findChild(editor, "calendarUrlField").text = "https://me:fixture-secret@cloud.example.com/dav/"
            findChild(editor, "calendarUserField").text = "me"
            tap(editor, "calendarAllowRemote")
            var hint = findChild(editor, "calendarUserinfoHint")
            verify(hint.visible, "the editor says why")
            verify(hint.text.indexOf("password field") >= 0, "and points at the password field")
            verify(hint.text.indexOf("fixture-secret") < 0, "without repeating the secret")
            verify(!findChild(editor, "calendarAdd").enabled)
            editor.add()
            compare(JSON.stringify(fakeCoordinator.configured).indexOf("fixture-secret"), -1, "nothing reaches the settings")
            findChild(editor, "calendarUrlField").text = "https://cloud.example.com/dav/"
            verify(!hint.visible)
            verify(findChild(editor, "calendarAdd").enabled)
        }

        function test_local_network_opt_in() {
            var editor = createTemporaryObject(editorComponent, editorTest)
            tap(editor, "calendarKind-caldav")
            findChild(editor, "calendarUrlField").text = "https://radicale.lan/me/cal/"
            findChild(editor, "calendarUserField").text = "me"
            tap(editor, "calendarAllowRemote")
            verify(!editor.localNetworkAllowed, "local network starts off")
            tap(editor, "calendarAllowLocal")
            verify(editor.localNetworkAllowed)
            tap(editor, "calendarAdd")
            compare(fakeCoordinator.fileSettings.calendarSources[0],
                { kind: "caldav", url: "https://radicale.lan/me/cal/", user: "me", allowLocalNetwork: true },
                "the explicit opt-in is written to the source")
            verify(!editor.localNetworkAllowed, "and asked again for the next source")
            tap(editor, "calendarKind-caldav")
            findChild(editor, "calendarUrlField").text = "https://cloud.example.com/dav/"
            findChild(editor, "calendarUserField").text = "me"
            tap(editor, "calendarAllowRemote")
            tap(editor, "calendarAdd")
            verify(!("allowLocalNetwork" in fakeCoordinator.fileSettings.calendarSources[1]), "without it, nothing is written")
        }

        function test_readding_an_account_being_cleared_needs_its_password() {
            fakeCoordinator.clearing = ["https://cloud.example.com/dav/\nme"]
            var editor = createTemporaryObject(editorComponent, editorTest, { source: fakeSource })
            tap(editor, "calendarKind-caldav")
            findChild(editor, "calendarUrlField").text = "https://cloud.example.com/dav/"
            findChild(editor, "calendarUserField").text = "me"
            tap(editor, "calendarAllowRemote")
            verify(!findChild(editor, "calendarAdd").enabled, "its old password is being deleted")
            verify(findChild(editor, "calendarReaddHint").visible)
            findChild(editor, "calendarPasswordField").text = "fixture-password"
            verify(findChild(editor, "calendarAdd").enabled, "a new password makes it whole again")
            findChild(editor, "calendarUserField").text = "someone-else"
            findChild(editor, "calendarPasswordField").text = ""
            verify(findChild(editor, "calendarAdd").enabled, "other accounts are not affected")
            fakeCoordinator.clearing = []
        }

        function test_caldav_password_goes_only_to_the_keyring() {
            var editor = createTemporaryObject(editorComponent, editorTest)
            tap(editor, "calendarKind-caldav")
            findChild(editor, "calendarUrlField").text = "https://cloud.example.com/dav/"
            findChild(editor, "calendarUserField").text = "me"
            findChild(editor, "calendarPasswordField").text = "fixture-password"
            compare(findChild(editor, "calendarPasswordField").echoMode, TextInput.Password)
            tap(editor, "calendarAllowRemote")
            verify(!findChild(editor, "calendarAdd").enabled, "no source to hand the password to")
            verify(findChild(editor, "calendarPasswordHint").visible)
            editor.source = fakeSource
            verify(findChild(editor, "calendarAdd").enabled)
            tap(editor, "calendarAdd")
            compare(findChild(editor, "calendarPasswordField").text, "", "the field is cleared at once")
            compare(fakeSource.calls, [["store", "https://cloud.example.com/dav/", "me", "fixture-password"]])
            verify(JSON.stringify(fakeCoordinator.configured).indexOf("fixture-password") < 0,
                "the password never reaches the settings")
            compare(fakeCoordinator.fileSettings.calendarSources[0], { kind: "caldav", url: "https://cloud.example.com/dav/", user: "me" })
            verify(editor.notice.indexOf("Added") === 0)
            fakeSource.credentialFinished(fakeSource.lastRequest(), "store", true, "")
            verify(editor.notice.indexOf("Saved the password") === 0 && !editor.noticeIsError)
        }

        function test_failed_password_store_is_reported() {
            var editor = createTemporaryObject(editorComponent, editorTest, { source: fakeSource })
            addCaldav(editor, "fixture-password")
            fakeSource.credentialFinished("some-other-request", "store", false, "lookup")
            verify(!editor.noticeIsError, "an unrelated result is ignored")
            fakeSource.credentialFinished(fakeSource.lastRequest(), "store", false, "unavailable")
            verify(editor.noticeIsError)
            verify(editor.notice.indexOf("was not saved") >= 0, editor.notice)
            verify(findChild(editor, "calendarNotice").visible)
        }

        readonly property var account: ({ kind: "caldav", url: "https://cloud.example.com/dav/", user: "me" })

        // Removal is the Service's transaction; the editor only asks for it
        // and reports the outcome, so it needs no calendar source.
        function test_removal_goes_through_the_service() {
            fakeCoordinator.fileSettings = { calendarSources: [parent.localSource, account] }
            var editor = createTemporaryObject(editorComponent, editorTest)
            tap(editor, "calendarSourceRemove-1")
            compare(fakeCoordinator.removed, [account])
            compare(fakeCoordinator.fileSettings.calendarSources, [parent.localSource])
            verify(editor.notice.indexOf("Removed") === 0 && !editor.noticeIsError, editor.notice)
            fakeCoordinator.calendarClearFinished(account.url, account.user, false, "secret-service-unavailable")
            verify(editor.noticeIsError && editor.notice.indexOf("could not be deleted") >= 0, editor.notice)
            fakeCoordinator.calendarClearFinished("https://unrelated.example/", "x", false, "lookup")
            verify(editor.notice.indexOf("could not be deleted") >= 0, "an unrelated account's result changes nothing")
        }

        function test_refused_removal_is_reported() {
            fakeCoordinator.fileSettings = { calendarSources: [account] }
            fakeCoordinator.refuse = true
            var editor = createTemporaryObject(editorComponent, editorTest)
            tap(editor, "calendarSourceRemove-0")
            compare(fakeCoordinator.fileSettings.calendarSources, [account])
            verify(editor.noticeIsError && editor.notice.indexOf("Not saved") === 0, editor.notice)
        }

        function test_tests_a_source() {
            var broken = { kind: "file", path: "/missing.ics" }
            fakeCoordinator.fileSettings = { calendarSources: [parent.localSource, broken] }
            var editor = createTemporaryObject(editorComponent, editorTest)
            verify(!findChild(editor, "calendarSourceTest-0").enabled, "no source, no test")
            verify(findChild(editor, "calendarTestHint").visible)
            editor.source = fakeSource
            tap(editor, "calendarSourceTest-1")
            compare(fakeSource.calls, [["test", Calendar.sourceId(broken)]], "a fresh load of that one source")
            var brokenRequest = fakeSource.lastRequest()
            var status = findChild(findChild(editor, "calendarSourceRow-1"), "calendarSourceStatus")
            verify(status.text.indexOf("Testing") >= 0)
            tap(editor, "calendarSourceTest-1")
            compare(fakeSource.calls.length, 1, "a source already testing is not asked again")
            fakeSource.errors = []
            fakeSource.updated()
            verify(status.text.indexOf("Testing") >= 0, "a window update is not the test's answer")
            tap(editor, "calendarSourceTest-0")
            var localRequest = fakeSource.lastRequest()
            fakeSource.testFinished(brokenRequest, Calendar.sourceId(broken), false, "missing-source")
            verify(status.text.indexOf("does not exist") >= 0, status.text)
            var localStatus = findChild(findChild(editor, "calendarSourceRow-0"), "calendarSourceStatus")
            verify(localStatus.text.indexOf("Testing") >= 0, "each test waits for its own answer")
            fakeSource.testFinished(localRequest, Calendar.sourceId(parent.localSource), true, "")
            verify(localStatus.text.indexOf("Connected") >= 0, localStatus.text)
            tap(editor, "calendarSourceTest-1")
            compare(fakeSource.calls.length, 3, "a finished test can run again")
        }
    }

    QtObject {
        id: queueCoordinator
        property bool showCalendar: true
        property var fileSettings: ({ calendarSources: [], calendarRefresh: 15 })
        property var sent: []
        signal calendarFrame(var frame)
        function calendarSend(type, fields) {
            sent = sent.concat([{ type: type, fields: JSON.parse(JSON.stringify(fields)) }])
            return true
        }
        function answer(index, fields) {
            calendarFrame(Object.assign({ type: "calendarResult", requestId: sent[index].fields.requestId }, fields))
        }
    }
    TestCase {
        id: queueTest
        name: "CalendarSourceQueue"
        when: windowShown

        function init() { queueCoordinator.sent = [] }
        function started() {
            var source = createTemporaryObject(sourceComponent, queueTest)
            source.coordinator = queueCoordinator
            compare(queueCoordinator.sent[0].type, "calendarConfigure")
            verify(source.pending)
            return source
        }

        function test_actions_wait_while_busy_and_go_in_order() {
            var source = started()
            var credentials = [], tests = []
            source.credentialFinished.connect(function (id, action, ok, error) { credentials.push([id, action, ok, error]) })
            source.testFinished.connect(function (id, sourceId, ok, error) { tests.push([id, sourceId, ok, error]) })
            var store = source.storeCredential("https://cloud.example.com/dav/", "me", "fixture-password")
            var test = source.testSource("abc123")
            verify(store && test && store !== test)
            compare(queueCoordinator.sent.length, 1, "both wait behind the configure")
            compare(source.queue.length, 2)
            queueCoordinator.answer(0, { status: "invalid-source" })
            compare(queueCoordinator.sent[1].type, "calendarCredential")
            compare(queueCoordinator.sent[1].fields.requestId, store)
            compare(queueCoordinator.sent[1].fields.password, "fixture-password")
            verify(JSON.stringify(source.pendingRequest).indexOf("fixture-password") < 0,
                "the request in flight is remembered without its password")
            queueCoordinator.answer(1, { status: "unavailable" })
            compare(credentials, [[store, "store", false, "unavailable"]])
            compare(queueCoordinator.sent[2].type, "calendarTest")
            compare(queueCoordinator.sent[2].fields.sourceId, "abc123")
            compare(tests.length, 0, "no answer before the load finishes")
            queueCoordinator.answer(2, { ok: false, error: "auth-error" })
            compare(tests, [[test, "abc123", false, "auth-error"]])
            compare(source.queue.length, 0)
        }

        function test_success_refreshes_the_window() {
            var source = started()
            queueCoordinator.answer(0, { status: "ok" })
            compare(queueCoordinator.sent[1].type, "calendarWindow")
            queueCoordinator.calendarFrame({ type: "calendarWindowResult", requestId: queueCoordinator.sent[1].fields.requestId,
                items: [], errors: [], nextOffset: -1 })
            var passed = []
            source.testFinished.connect(function (id, sourceId, ok, error) { passed.push(ok) })
            source.testSource("abc123")
            compare(queueCoordinator.sent[2].type, "calendarTest", "an idle source sends at once")
            queueCoordinator.answer(2, { ok: true })
            compare(passed, [true])
            compare(queueCoordinator.sent[3].type, "calendarWindow", "a passing test reloads the window")
            queueCoordinator.calendarFrame({ type: "calendarChanged" })
            compare(queueCoordinator.sent.length, 4, "a change while busy waits")
            queueCoordinator.calendarFrame({ type: "calendarWindowResult", requestId: queueCoordinator.sent[3].fields.requestId,
                items: [], errors: [], nextOffset: -1 })
            compare(queueCoordinator.sent[4].type, "calendarWindow", "then refreshes")
        }

        function test_completion_is_queued_not_dropped() {
            var source = started()
            verify(source.setCompleted("abc123", "task", true))
            compare(queueCoordinator.sent.length, 1)
            queueCoordinator.answer(0, { status: "invalid-source" })
            compare(queueCoordinator.sent[1].type, "calendarSetCompleted")
            compare(queueCoordinator.sent[1].fields.completed, true)
        }
    }
}
