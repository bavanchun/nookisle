import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"

// LyricsFetch harness running under Quickshell.
// Tests process lifecycle, argv contract, status/error mappings,
// signal isolation, and cancellation cleanup.
// Prints LYRICS_FETCH_RESULT failures=N and quits.
ShellRoot {
    id: test
    property int failures: 0
    property string current: ""
    property int currentStep: 0
    property var recordedEvents: []

    function report(ok, message) {
        if (ok) {
            console.log("PASS " + current + ": " + message)
        } else {
            failures++
            console.error("FAIL " + current + ": " + message)
        }
    }

    function same(actual, expected, message) {
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        report(ok, (message || "") + (ok ? "" : " got " + JSON.stringify(actual) + " expected " + JSON.stringify(expected)))
    }

    function truthy(value, message) {
        report(!!value, message || "expected true")
    }

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string fakeScript: runtimeDir + "/fake-lyrics-fetch.sh"
    readonly property string argvLog: runtimeDir + "/argv.log"

    LyricsFetch {
        id: fetcher
        fetchPath: test.fakeScript
        onFinished: (status, body) => test.handleFinished(status, body)
        onFailed: code => test.handleFailed(code)
    }

    Process {
        id: argvCat
        command: ["cat", test.argvLog]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n")
                test.same(lines, [test.fakeScript, "--lyrics", "case-ok-200"], "exact argv is [fetchPath, '--lyrics', url]")
                test.nextStep()
            }
        }
    }

    Process {
        id: pgrepProc
        command: ["pgrep", "-f", "fake-lyrics-fetch.sh.*case-linger"]
        stdout: StdioCollector {
            onStreamFinished: {
                test.same(text.trim(), "", "no fake child process lingers after cancel")
                test.done()
            }
        }
    }

    function handleFinished(status, text) {
        if (currentStep === 1) {
            same(status, 200, "status is 200")
            var ok = false
            try {
                var json = JSON.parse(text)
                ok = (json.lyrics === "sync content")
            } catch (e) {}
            truthy(ok, "body parsed correctly")
            argvCat.running = true
            return
        }
        if (currentStep === 2) {
            same(status, 404, "status is 404")
            same(text, "Not Found", "404 body preserved")
            nextStep()
            return
        }
        if (currentStep === 8 || currentStep === 9 || currentStep === 10) {
            recordedEvents.push({ event: "finished", status: status, text: text })
            return
        }
        report(false, "unexpected onFinished event in step " + currentStep)
    }

    function handleFailed(code) {
        if (currentStep === 3) {
            same(code, "too-large", "maps error too-large to failed('too-large')")
            nextStep()
            return
        }
        if (currentStep === 4) {
            same(code, "timeout", "maps error timeout to failed('timeout')")
            nextStep()
            return
        }
        if (currentStep === 5) {
            same(code, "network", "maps unknown error to failed('network')")
            nextStep()
            return
        }
        if (currentStep === 6) {
            same(code, "network", "maps garbage output to failed('network')")
            nextStep()
            return
        }
        if (currentStep === 7) {
            same(code, "network", "maps non-zero exit code to failed('network')")
            nextStep()
            return
        }
        if (currentStep === 8 || currentStep === 9 || currentStep === 10) {
            recordedEvents.push({ event: "failed", code: code })
            return
        }
        report(false, "unexpected onFailed event in step " + currentStep)
    }

    function nextStep() {
        currentStep++
        runStep()
    }

    function runStep() {
        if (currentStep === 1) {
            current = "test_argv_and_ok_200"
            fetcher.start("case-ok-200")
            return
        }
        if (currentStep === 2) {
            current = "test_ok_404"
            fetcher.start("case-ok-404")
            return
        }
        if (currentStep === 3) {
            current = "test_error_too_large"
            fetcher.start("case-err-too-large")
            return
        }
        if (currentStep === 4) {
            current = "test_error_timeout"
            fetcher.start("case-err-timeout")
            return
        }
        if (currentStep === 5) {
            current = "test_unknown_error_code"
            fetcher.start("case-err-unknown")
            return
        }
        if (currentStep === 6) {
            current = "test_garbage_output"
            fetcher.start("case-garbage")
            return
        }
        if (currentStep === 7) {
            current = "test_nonzero_exit"
            fetcher.start("case-nonzero-exit")
            return
        }
        if (currentStep === 8) {
            current = "test_start_while_running"
            recordedEvents = []
            fetcher.start("case-slow-a")
            step8TimerA.start()
            return
        }
        if (currentStep === 9) {
            current = "test_cancel_then_start_same_tick"
            recordedEvents = []
            fetcher.start("case-slow-a")
            fetcher.cancel()
            fetcher.start("case-fast-b")
            step9Timer.start()
            return
        }
        if (currentStep === 10) {
            current = "test_cancel_alone_emits_nothing_and_leaves_no_child"
            recordedEvents = []
            fetcher.start("case-linger")
            step10TimerA.start()
            return
        }
    }

    Timer {
        id: step8TimerA
        interval: 100
        repeat: false
        onTriggered: {
            fetcher.start("case-fast-b")
            step8TimerB.start()
        }
    }
    Timer {
        id: step8TimerB
        interval: 400
        repeat: false
        onTriggered: {
            test.same(test.recordedEvents.length, 1, "exactly one event received when start() called while running")
            if (test.recordedEvents.length > 0) {
                var ev = test.recordedEvents[0]
                test.same(ev.event, "finished", "event is finished")
                test.same(ev.status, 200, "status is 200")
                var bodyUrl = ""
                try { bodyUrl = JSON.parse(ev.text).url } catch (e) {}
                test.same(bodyUrl, "fast-b", "only the newer request answers")
            }
            test.nextStep()
        }
    }

    Timer {
        id: step9Timer
        interval: 400
        repeat: false
        onTriggered: {
            test.same(test.recordedEvents.length, 1, "exactly one event received after cancel then start in same tick")
            if (test.recordedEvents.length > 0) {
                var ev = test.recordedEvents[0]
                test.same(ev.event, "finished", "event is finished")
                test.same(ev.status, 200, "status is 200")
                var bodyUrl = ""
                try { bodyUrl = JSON.parse(ev.text).url } catch (e) {}
                test.same(bodyUrl, "fast-b", "newer request answers cleanly")
            }
            test.nextStep()
        }
    }

    Timer {
        id: step10TimerA
        interval: 100
        repeat: false
        onTriggered: {
            fetcher.cancel()
            fetcher.cancel() // verify idempotency
            step10TimerB.start()
        }
    }
    Timer {
        id: step10TimerB
        interval: 300
        repeat: false
        onTriggered: {
            test.same(test.recordedEvents.length, 0, "cancel emits nothing")
            pgrepProc.running = true
        }
    }

    function done() {
        console.log("LYRICS_FETCH_RESULT failures=" + failures)
        Qt.quit()
    }

    Timer {
        id: watchdog
        interval: 15000
        running: true
        onTriggered: {
            test.report(false, "harness watchdog timeout")
            test.done()
        }
    }

    Component.onCompleted: {
        test.nextStep()
    }
}
