pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Production lyrics transport. Wraps nookisle-artwork-fetch in a short-lived
// child process with the --lyrics flag. The child caps output while streaming,
// refuses compressed answers and unverified hosts, and exits with 0 on both
// success ("ok <status>\n<body>") and handled errors ("error <code>\n").
Item {
    id: root
    visible: false

    property string fetchPath: Qt.resolvedUrl("../libexec/nookisle-artwork-fetch").toString()

    signal finished(int status, string text)
    signal failed(string code)

    property var currentWorker: null

    function start(url) {
        cancel()
        var worker = workerComponent.createObject(root, {
            targetUrl: String(url || "")
        })
        if (!worker) {
            root.failed("network")
            return
        }
        root.currentWorker = worker
        worker.start()
    }

    function cancel() {
        if (!root.currentWorker)
            return
        var worker = root.currentWorker
        root.currentWorker = null
        worker.cancel()
        worker.destroy()
    }

    Component.onDestruction: cancel()

    function parseOutput(text) {
        if (typeof text !== "string") {
            root.failed("network")
            return
        }
        var newlineIndex = text.indexOf("\n")
        var firstLine = newlineIndex >= 0 ? text.slice(0, newlineIndex).trim() : text.trim()
        var parts = firstLine.split(" ")
        if (parts[0] === "ok" && parts.length === 2) {
            var status = parseInt(parts[1], 10)
            if (isNaN(status)) {
                root.failed("network")
                return
            }
            var body = newlineIndex >= 0 ? text.slice(newlineIndex + 1) : ""
            root.finished(status, body)
            return
        }
        if (parts[0] === "error" && parts.length === 2) {
            var code = parts[1].trim()
            if (code === "too-large" || code === "timeout" || code === "busy"
                    || code === "rate-limited" || code === "network")
                root.failed(code)
            else
                root.failed("network")
            return
        }
        root.failed("network")
    }

    Component {
        id: workerComponent
        Item {
            id: worker
            visible: false
            property string targetUrl: ""
            property bool started: false
            property bool exited: false
            property int exitCode: -1
            property bool streamFinished: false
            property string stdoutText: ""
            property bool cancelled: false

            function start() {
                process.command = [root.fetchPath, "--lyrics", targetUrl]
                process.running = true
            }

            function cancel() {
                if (cancelled)
                    return
                cancelled = true
                if (process.running) {
                    try {
                        process.signal(9)
                    } catch (error) {}
                    process.running = false
                }
            }

            function tryComplete() {
                if (cancelled || root.currentWorker !== worker)
                    return
                if (exited && exitCode !== 0) {
                    cancelled = true
                    root.currentWorker = null
                    root.failed("network")
                    worker.destroy()
                    return
                }
                if (exited && streamFinished) {
                    cancelled = true
                    root.currentWorker = null
                    root.parseOutput(stdoutText)
                    worker.destroy()
                }
            }

            Process {
                id: process
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (worker.cancelled)
                            return
                        worker.stdoutText = text
                        worker.streamFinished = true
                        worker.tryComplete()
                    }
                }
                onStarted: {
                    worker.started = true
                }
                onExited: (code, exitStatus) => {
                    if (worker.cancelled)
                        return
                    worker.exited = true
                    worker.exitCode = code
                    worker.tryComplete()
                }
                onRunningChanged: {
                    if (worker.cancelled)
                        return
                    if (!running && !worker.started && !worker.exited) {
                        if (root.currentWorker === worker) {
                            worker.cancelled = true
                            root.currentWorker = null
                            root.failed("network")
                        }
                        worker.destroy()
                    }
                }
            }
        }
    }
}
