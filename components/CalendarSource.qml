pragma ComponentBehavior: Bound
import QtQuick

// The calendar's only QML protocol owner. The helper performs all parsing,
// network access and completion writes; this object only owns the visible
// subscription and assembles bounded pages. One request is in flight at a
// time. Window and configure requests are refused while busy and retried by
// their dirty flags; user actions (completion, credentials, tests) wait in
// `queue` and go out in order, so a busy moment never drops one.
Item {
    id: root
    property var coordinator: null
    property var items: []
    property var errors: []
    property string lastStatus: ""
    property string actionError: ""
    property int offset: 0
    property bool pending: false
    property string pendingId: ""
    property bool configurationDirty: false
    property bool refreshDirty: false
    property string configuredKey: ""
    property var queue: []
    // What the request in flight was, without any password.
    property string pendingType: ""
    property var pendingRequest: ({})
    signal updated()
    // The helper's answer to a credential store or clear, and to a source test.
    signal credentialFinished(string requestId, string action, bool ok, string error)
    signal testFinished(string requestId, string sourceId, bool ok, string error)

    function newRequestId() {
        return String(Date.now()) + ":" + String(Math.random())
    }
    function send(type, request) {
        if (!coordinator || pending || !coordinator.calendarSend(type, request)) return false
        pending = true
        pendingId = request.requestId
        pendingType = type
        pendingRequest = { action: request.action || "", sourceId: request.sourceId || "" }
        return true
    }
    function ask(type, fields) {
        return send(type, Object.assign({ requestId: newRequestId() }, fields || {}))
    }
    // Queues a user action and returns its request id, or "" without a
    // coordinator.
    function enqueue(type, fields) {
        if (!coordinator) return ""
        var request = Object.assign({ requestId: newRequestId() }, fields || {})
        queue = queue.concat([{ type: type, request: request }])
        drain()
        return request.requestId
    }
    function drain() {
        if (pending || queue.length === 0) return
        if (send(queue[0].type, queue[0].request)) queue = queue.slice(1)
    }
    function configure() {
        if (!coordinator) return
        var key = JSON.stringify([coordinator.fileSettings.calendarSources, coordinator.fileSettings.calendarRefresh])
        if (ask("calendarConfigure", { enabled: coordinator.showCalendar,
            sources: coordinator.fileSettings.calendarSources,
            refreshMinutes: coordinator.fileSettings.calendarRefresh })) {
            configuredKey = key
            configurationDirty = false
        }
    }
    function refresh() {
        if (pending) { refreshDirty = true; return }
        offset = 0
        items = []
        if (!ask("calendarWindow", { offset: 0 })) refreshDirty = true
    }
    function setCompleted(sourceId, uid, completed) {
        actionError = ""
        return enqueue("calendarSetCompleted", { sourceId: sourceId, uid: uid, completed: completed })
    }
    // A fresh load of one source; testFinished reports it once that load ends.
    function testSource(sourceId) {
        return enqueue("calendarTest", { sourceId: sourceId })
    }
    // After a successful store the helper refetches every source with this
    // url and user, then announces calendarChanged.
    function storeCredential(url, user, password) {
        return enqueue("calendarCredential", { action: "store", url: url, user: user, password: password })
    }
    function clearCredential(url, user) {
        return enqueue("calendarCredential", { action: "clear", url: url, user: user })
    }
    Connections {
        target: root.coordinator
        function onFileSettingsChanged() {
            var key = JSON.stringify([root.coordinator.fileSettings.calendarSources, root.coordinator.fileSettings.calendarRefresh])
            if (key === root.configuredKey) return
            root.configurationDirty = true
            if (!root.pending) root.configure()
        }
        function onCalendarFrame(frame) {
            if (frame.type === "calendarChanged") {
                if (root.pending) root.refreshDirty = true
                else root.refresh()
                return
            }
            if (frame.requestId !== root.pendingId) return
            var finishedType = root.pendingType
            var finished = root.pendingRequest
            root.pending = false
            root.pendingId = ""
            root.pendingType = ""
            root.pendingRequest = ({})
            if (frame.type === "calendarResult") {
                var ok = frame.ok === true || frame.status === "ok"
                var error = ok ? "" : String(frame.error || frame.status || "error")
                if (finishedType === "calendarCredential")
                    root.credentialFinished(frame.requestId, finished.action, ok, error)
                else if (finishedType === "calendarTest")
                    root.testFinished(frame.requestId, finished.sourceId, ok, error)
                else if (finishedType === "calendarSetCompleted")
                    root.actionError = error
            }
            if (root.configurationDirty) { root.configure(); root.drain(); return }
            if (frame.type === "calendarResult") {
                root.lastStatus = frame.status || (frame.ok === true ? "ok" : String(frame.error || ""))
                // Queued user actions go before the window reload, so a
                // password clear is not held behind every page.
                if (root.lastStatus === "ok" || root.refreshDirty) {
                    if (root.queue.length > 0) root.refreshDirty = true
                    else { root.refreshDirty = false; root.refresh() }
                }
            } else if (frame.type === "calendarWindowResult") {
                root.items = root.items.concat(frame.items || [])
                root.errors = frame.errors || []
                root.updated()
                if (frame.nextOffset >= 0) root.ask("calendarWindow", { offset: frame.nextOffset })
                else if (root.refreshDirty) { root.refreshDirty = false; root.refresh() }
            }
            root.drain()
        }
    }
    onCoordinatorChanged: configure()
    Component.onDestruction: {
        if (coordinator && coordinator.connected)
            coordinator.send("calendarConfigure", { requestId: String(Date.now()), enabled: false, sources: [], refreshMinutes: 15 })
    }
}
