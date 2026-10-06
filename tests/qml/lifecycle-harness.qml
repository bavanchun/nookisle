import QtQuick
import Quickshell
import Quickshell.Io
import "../.." as Plugin
import "../../qml/SourceState.js" as SourceState
import "../../qml/Settings.js" as Settings

ShellRoot {
    id: test
    property int stage: 0
    property int reopenGeneration: 0
    property double started: Date.now()
    property var active: null
    property var prior: null
    property var stockProbe: null
    property var late: null
    property var oldManifest: null
    property int exits: 0
    // One announced protocol-error exit (code 4), provoked on purpose.
    property bool expectProtocolExit: false
    property int failures: 0
    property var originalPid: null
    property bool leaseReady: false
    property int contentionExits: 0
    property int eofExits: 0
    property int churnCount: 0
    QtObject {
        id: registry
        property int registryRevision: 0
        property var installedPlugins: ({})
        property bool enabled: true
        // A working settings store, so configure() (phase 06's hud:false path)
        // has somewhere real to write to; the real host's shellConfigMutator
        // does the same read-modify-write against its own config object.
        property var shellConfig: ({ plugins: [{ id: "io.github.bavanchun.nookisle", settings: ({}) }] })
        function isEnabled(id) { return enabled }
        // Function-valued properties, so a test can remove them and exercise
        // the scoped host that offers neither.
        property var shellConfigProvider: function() { return registry.shellConfig }
        property var shellConfigMutator: function(mutate) {
            mutate(registry.shellConfig)
            registry.registryRevision++
        }
    }
    QtObject {
        id: lock
        property bool locked: false
        property bool strandedLockResolved: false
        property bool strandedLock: false
    }
    // The stock host gives a third-party service its scoped PluginShellApi
    // (/usr/share/omarchy/shell/services/PluginShellApi.qml), which has no
    // pluginReloading property; only first-party plugins get the shell root.
    QtObject {
        id: stockHost
        property string pluginId: "io.github.bavanchun.nookisle"
        property var barConfig: ({})
        function serviceFor(id) { return null }
    }
    QtObject {
        id: host
        property bool pluginReloading: false
        property var pluginRegistry: registry
        property var _services: ({ "omarchy.lock": lock })
        property string omarchyPath: "/unused-host-path"
        property var barWidgetRegistry: null
        property var bar: null
        function serviceFor(pluginId) { return _services[String(pluginId)] || null }
        // The scoped host settings API: a public bar config copy plus
        // updateEntryInline, which stores settings flat and replaces them.
        property var barConfig: ({ layout: { left: [], center: [{ id: "io.github.bavanchun.nookisle" }], right: [] } })
        property var inlineWrites: []
        function updateEntryInline(id, settings) {
            var entry = { id: id }
            for (var key in settings) entry[key] = settings[key]
            inlineWrites = inlineWrites.concat([entry])
            // Like the real host, the public copy is not refreshed on write.
            return true
        }
        // Installed shell.qml:295–314 body; test chooses delayed completion order.
        function finalize(comp, serviceHost, manifest, key) {
            var shell = host
            if (comp.status !== Component.Ready) {
                console.warn("service plugin load failed for " + key + ": " + comp.errorString())
                return
            }
            var inst = comp.createObject(serviceHost)
            if (!inst) {
                console.warn("service plugin createObject returned null for", key)
                return
            }
            if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
            if ("shell" in inst) inst.shell = shell
            if ("manifest" in inst) inst.manifest = manifest
            if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.barWidgetRegistry
            if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistry
            var snext = ({})
            for (var sk in _services) snext[sk] = _services[sk]
            snext[key] = inst
            _services = snext
        }
    }
    Item { id: serviceHost; visible: false }
    Component {
        id: serviceComponent
        Plugin.Service {
            helperPath: Qt.resolvedUrl("../../build/bin/nookisle-helper").toString()
            onHelperExited: code => {
                test.exits++
                if (code === 73) test.contentionExits++
                if (code === 0) test.eofExits++
                if (code === 4 && test.expectProtocolExit) { test.expectProtocolExit = false; return }
                test.check(code === 0 || code === 73, "owned helper EOF exit or bounded lease contention: " + code)
            }
        }
    }
    Process {
        id: leaseHolder
        command: [Qt.resolvedUrl("../../build/bin/nookisle-helper").toString()]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => { if (data.indexOf('"hello"') >= 0) test.leaseReady = true } }
        onExited: code => { test.check(code === 0, "independent lease holder exits on EOF"); test.leaseReady = false }
    }
    // Fixture backlight devices under a private temp directory, so the source
    // can be proven against sysfs-shaped files without
    // touching the host's own backlight device. QML has no filesystem-write
    // API of its own, hence the one-shot shell child.
    property string backlightFixtureRoot: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nookisle-hud-test-" + Date.now()
    property var hudEvents: []
    property bool backlightFixtureReady: false
    function captureHud(kind, level, muted) { test.hudEvents.push({ kind: kind, level: level, muted: muted }) }
    // A private screenshot folder for the helper's watch, and a screenshot
    // written into it once the watch is on.
    property string shotsRoot: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nookisle-shots-" + Date.now()
    property bool shotsReady: false
    property bool statusPresenceChecked: false
    property var capturesShelved: []
    Process {
        id: shotsSetup
        command: ["mkdir", "-p", test.shotsRoot]
        onExited: (exitCode, exitStatus) => { test.shotsReady = exitCode === 0 }
    }
    Process {
        id: shotWriter
        command: ["sh", "-c", "printf png > \"$1/screenshot-2026-09-27_18-00-00.png\"", "sh", test.shotsRoot]
    }
    function shelved(path) {
        var uri = test.shelfUri(path)
        return test.active.shelfEntries.some(function (entry) { return entry.uri === uri })
    }
    Process {
        id: backlightFixtureSetup
        stdinEnabled: false
        command: ["sh", "-c",
            "mkdir -p '" + test.backlightFixtureRoot + "/class/backlight/aaa_zero' '" +
                test.backlightFixtureRoot + "/class/backlight/bbb_valid' '" +
                test.backlightFixtureRoot + "/class/backlight/appletb_backlight' '" +
                test.backlightFixtureRoot + "/class/backlight/intel_backlight' '" +
                test.backlightFixtureRoot + "/class/leds/tpacpi::kbd_backlight' && " +
            "printf %s 0 > '" + test.backlightFixtureRoot + "/class/backlight/aaa_zero/max_brightness' && " +
            "printf %s 100 > '" + test.backlightFixtureRoot + "/class/backlight/bbb_valid/max_brightness' && " +
            "printf %s 10 > '" + test.backlightFixtureRoot + "/class/backlight/bbb_valid/brightness' && " +
            "printf %s 100 > '" + test.backlightFixtureRoot + "/class/backlight/appletb_backlight/max_brightness' && " +
            "printf %s 10 > '" + test.backlightFixtureRoot + "/class/backlight/appletb_backlight/brightness' && " +
            "printf %s 4096 > '" + test.backlightFixtureRoot + "/class/backlight/intel_backlight/max_brightness' && " +
            "printf %s 2048 > '" + test.backlightFixtureRoot + "/class/backlight/intel_backlight/brightness' && " +
            "printf %s 2 > '" + test.backlightFixtureRoot + "/class/leds/tpacpi::kbd_backlight/max_brightness' && " +
            "printf %s 1 > '" + test.backlightFixtureRoot + "/class/leds/tpacpi::kbd_backlight/brightness' && " +
            // The fixture records its arguments, then changes the fixture
            // sysfs level the way a real write would.
            "printf '%s\\n' '#!/bin/sh' 'd=${0%/*}' 'printf \"%s\" \"$*\" > \"$d/brightnessctl-args\"' " +
                "'if [ -d \"$d/class/leds/$2\" ]; then printf 2 > \"$d/class/leds/$2/brightness\"; " +
                "else printf 41 > \"$d/class/backlight/$2/brightness\"; fi' > '" +
                test.backlightFixtureRoot + "/brightnessctl-fixture' && " +
            "chmod +x '" + test.backlightFixtureRoot + "/brightnessctl-fixture'"]
        onExited: (exitCode, exitStatus) => { test.backlightFixtureReady = exitCode === 0 }
    }
    FileView {
        id: brightnessWriteProbe
        path: test.backlightFixtureRoot + "/brightnessctl-args"
        blockAllReads: true
        printErrors: false
    }
    // A spectrum stand-in: one valid line, then it idles until stopped. After
    // `exec sleep` the child's command line no longer names the fixture, so
    // leaks are checked by PID through /proc, never by name.
    readonly property string spectrumFixture: test.backlightFixtureRoot + "/spectrum-fixture"
    property bool spectrumFixtureReady: false
    property var spectrumPid: null
    property var probedPid: null
    property double probeStarted: 0
    property string probeResult: ""
    Process {
        id: spectrumFixtureSetup
        stdinEnabled: false
        // Also a stand-in whose stream fails (exit 2) and one that drops
        // out (exit 1), for the give-up and retry paths.
        command: ["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' '#!/bin/sh' '[ \"$*\" = \"--fps 15\" ] && echo 0 1 2 3 4 5 6 7 8 9 10 11 || echo 9 9 9 9 9 9 9 9 9 9 9 9' 'exec sleep 15'"
            + " > \"$1/spectrum-fixture\" && chmod +x \"$1/spectrum-fixture\""
            + " && printf '%s\\n' '#!/bin/sh' 'exit 2' > \"$1/spectrum-fails\" && chmod +x \"$1/spectrum-fails\""
            + " && printf '%s\\n' '#!/bin/sh' 'exit 1' > \"$1/spectrum-drops\" && chmod +x \"$1/spectrum-drops\"",
            "sh", test.backlightFixtureRoot]
        onExited: (exitCode, exitStatus) => { test.spectrumFixtureReady = exitCode === 0 }
    }
    // The Service's settings file, read and overwritten from outside the way
    // a user's editor would.
    FileView {
        id: settingsProbe
        blockAllReads: true
        printErrors: false
    }
    FileView {
        id: badSettingsProbe
        blockAllReads: true
        printErrors: false
    }
    function readSettingsProbe() {
        settingsProbe.reload()
        try { return JSON.parse(settingsProbe.text()) } catch (error) { return null }
    }
    // The persisted shelf, read and rewritten from outside like the settings file.
    FileView {
        id: shelfProbe
        blockAllReads: true
        printErrors: false
    }
    function readShelfProbe() {
        shelfProbe.reload()
        try { return JSON.parse(shelfProbe.text()) } catch (error) { return null }
    }
    // A real 8x8 PNG for the thumbnail, MIME and action path.
    readonly property string shelfFixture: test.backlightFixtureRoot + "/shelf photo.png"
    property bool shelfFixtureReady: false
    Process {
        id: shelfFixtureSetup
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf %s "
            + "'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC'"
            + " | base64 -d > \"$1\"", "sh", test.shelfFixture]
        onExited: (exitCode, exitStatus) => { test.shelfFixtureReady = exitCode === 0 }
    }
    property string shelfExists: ""
    Process {
        id: shelfExistsProbe
        onExited: (exitCode, exitStatus) => { test.shelfExists = exitCode === 0 ? "yes" : "no" }
    }
    function shelfUri(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }
    FileView {
        id: shelfOpenProbe
        path: Quickshell.env("SHELF_OPEN_LOG") || ""
        blockLoading: true
        printErrors: false
    }
    function readShelfOpenLog() {
        shelfOpenProbe.reload()
        return shelfOpenProbe.text().trim()
    }
    property string shelfPhoto: ""
    property string shelfZip: ""
    property string shelfZipPath: ""
    property string shelfOrphanPath: ""
    property string shelfFailedPath: ""
    property string shelfMode: ""
    Process {
        id: shelfModeProbe
        stdout: SplitParser { onRead: data => { test.shelfMode = data.trim() } }
    }
    // The Service's IPC status() as a local process would read it.
    function ipcHandler(service) {
        for (var i = 0; i < service.data.length; ++i) {
            var child = service.data[i]
            if (child && typeof child.status === "function" && typeof child.configure === "function")
                return child
        }
        return null
    }
    // The media-keys helper's question for volume, mic, keyboard and
    // brightness, asked while the island is or is not on screen.
    function readouts(service, device, showing) {
        var was = service.islandShowing
        service.islandShowing = showing
        var ipc = ipcHandler(service)
        var answers = [ipc.hudReadout("volume", "default"), ipc.hudReadout("mic", "default"),
            ipc.hudReadout("keyboard", "default"), ipc.hudReadout("brightness", device)].join(" ")
        service.islandShowing = was
        return answers
    }
    function ipcStatus(service) {
        var handler = test.ipcHandler(service)
        return handler ? JSON.parse(handler.status()) : null
    }
    // Changes the settings directory's mode, to make the file unwritable.
    property bool settingsChmodDone: false
    Process {
        id: settingsChmod
        stdinEnabled: false
        onExited: (exitCode, exitStatus) => { test.settingsChmodDone = exitCode === 0 }
    }
    function chmodSettingsDir(mode) {
        settingsChmodDone = false
        settingsChmod.command = ["chmod", mode, test.active.settingsDir]
        settingsChmod.running = true
    }
    readonly property var calendarAccount: ({ kind: "caldav", url: "https://cloud.example.com/dav/", user: "me" })
    readonly property var calendarFile: ({ kind: "file", path: "/tmp/nookisle-test.ics" })
    property var clearResults: []
    property var credentialOrder: []
    function noteClear(url, user, ok, error) {
        clearResults = clearResults.concat([{ url: url, user: user, ok: ok, error: error }])
        credentialOrder = credentialOrder.concat(["clear"])
    }
    function noteCalendarFrame(frame) {
        if (frame.requestId === "harness-store") credentialOrder = credentialOrder.concat([frame.requestId])
    }
    property string settingsModes: ""
    property double settingsModesStarted: 0
    Process {
        id: settingsModeProbe
        stdinEnabled: false
        stdout: StdioCollector { onStreamFinished: test.settingsModes = text.trim().split("\n").join(" ") }
    }
    // Polls until /proc/<pid> is gone ("gone") or 2 s pass ("leaked").
    Process {
        id: pidProbe
        stdinEnabled: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) test.probeResult = "gone"
            else if (Date.now() - test.probeStarted > 2000) test.probeResult = "leaked"
            else Qt.callLater(test.runPidProbe)
        }
    }
    function probePid(pid) {
        probedPid = pid
        probeStarted = Date.now()
        probeResult = ""
        runPidProbe()
    }
    function runPidProbe() {
        pidProbe.command = ["test", "-e", "/proc/" + test.probedPid]
        pidProbe.running = true
    }
    function levelsAre(levels, expected) { return JSON.stringify(levels) === JSON.stringify(expected) }
    function canonical(value) {
        if (Array.isArray(value)) return value.map(canonical)
        if (value && typeof value === "object") {
            var ordered = {}
            Object.keys(value).sort().forEach(function (key) { ordered[key] = canonical(value[key]) })
            return ordered
        }
        return value
    }
    function sameValues(left, right) { return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right)) }
    function check(condition, message) {
        if (!condition) { failures++; console.error("FAIL " + message) }
        else console.log("PASS " + message)
    }
    function sleepEndpoint(owner, canPause) {
        var token = { busEpoch: "sleep", wellKnownName: "org.mpris.MediaPlayer2.sleep", uniqueOwner: owner, endpointGeneration: 1 }
        return { token: token, trackToken: { endpointToken: token, trackGeneration: 1, rawTrackId: "/sleep" },
            status: "Playing", capabilities: { CanControl: true, CanPause: canPause, CanPlay: true, CanGoNext: true, CanGoPrevious: false }, presentation: {} }
    }
    function transportEndpoint(shuffle, loopStatus) {
        var endpoint = sleepEndpoint("sleep-a", true)
        endpoint.shuffle = shuffle
        endpoint.loopStatus = loopStatus
        endpoint.capabilities.CanShuffle = true
        endpoint.capabilities.CanLoop = true
        endpoint.capabilities.CanSeek = true
        return endpoint
    }
    function pendingCommand(service) {
        for (var id in service.pendingRequests) return service.pendingRequests[id]
        return null
    }
    function freshManifest() { return { id: "io.github.bavanchun.nookisle", kinds: ["service"], entryPoints: { service: "Service.qml" } } }
    function installManifest(value) {
        // Mirrors the host's publicPluginManifest: stamp a plain-number scan
        // generation once per manifest object, since Service.qml now compares
        // that instead of raw manifest object identity.
        registry.registryRevision++
        value.__registryRevision = registry.registryRevision
        registry.installedPlugins = ({ "io.github.bavanchun.nookisle": value })
    }
    function registerService(value) { host._services = ({ "omarchy.lock": lock, "io.github.bavanchun.nookisle": value }) }
    function done() {
        tick.stop()
        if (active) active.dispose()
        if (prior) prior.dispose()
        if (late) late.dispose()
        leaseHolder.stdinEnabled = false
        console.log("LIFECYCLE_RESULT failures=" + failures)
        Qt.quit()
    }
    Timer {
        id: tick
        running: true
        repeat: true
        interval: 40
        onTriggered: {
            if (Date.now() - test.started > 25000) {
                if (test.stage === 672)
                    console.log("spectrum deadline", test.active.spectrumDesired, test.active.spectrumState,
                        test.active.spectrumRunning, test.active.spectrumLevels.length, test.active.spectrumPath,
                        test.active.island, test.active.uiAllowed, test.active.selectedEndpoint ? test.active.selectedEndpoint.status : "none")
                test.check(false, "harness deadline stage " + test.stage + " after " + (Date.now() - test.started) + " ms")
                test.done()
                return
            }
            if (test.stage === 0) {
                // A Service given the stock scoped API must load without a
                // Connections warning; run-lifecycle.sh fails on that warning.
                test.stockProbe = serviceComponent.createObject(serviceHost)
                test.stockProbe.shell = stockHost
                test.active = serviceComponent.createObject(serviceHost)
                test.check(!test.active.helperRunning, "no helper before injection")
                test.oldManifest = test.freshManifest()
                test.installManifest(test.oldManifest)
                test.active.shell = host
                test.active.manifest = test.oldManifest
                test.active.pluginRegistry = registry
                test.stage++
            } else if (test.stage === 1) {
                test.stockProbe.destroy()
                test.stockProbe = null
                test.check(!test.active.helperRunning, "no helper before registry ownership")
                test.registerService(test.active)
                test.stage++
            } else if (test.stage === 2 && test.active.connected) {
                test.originalPid = test.active.helperPid
                test.check(!test.active.uiAllowed, "unresolved lock fails closed")
                lock.strandedLockResolved = true
                lock.strandedLock = true
                test.stage++
            } else if (test.stage === 3) {
                test.check(!test.active.uiAllowed, "stranded lock fails closed after same-turn assignments")
                lock.strandedLock = false
                test.stage++
            } else if (test.stage === 4 && test.active.uiAllowed) {
                test.check(test.active.command({}, "PlayPause") !== "", "command admitted before lock barrier")
                lock.locked = true
                test.stage = 40
            } else if (test.stage === 40 && test.active.outputBudget === 0) {
                test.check(Object.keys(test.active.pendingRequests).length === 0, "closed gate ACK retires canceled command credits")
                lock.locked = false
                test.churnCount++
                if (test.churnCount < 8) test.stage = 4
                else { test.installManifest(test.freshManifest()); test.stage = 5 }
            } else if (test.stage === 5) {
                test.check(test.active.uiAllowed && test.active.helperPid === test.originalPid, "normal rescan preserves admitted service")
                lock.locked = true
                test.check(!test.active.uiAllowed, "lock closes UI admission synchronously")
                test.stage++
            } else if (test.stage === 6) {
                lock.locked = false
                test.stage = 60
            } else if (test.stage === 60 && test.active.uiAllowed) {
                // A host that scopes the lock service away from third parties
                // leaves nothing to consult. The compositor still covers every
                // surface while locked, so an absent provider must admit the
                // widget rather than hide it for the life of the session.
                var withLock = host._services
                var withoutLock = ({})
                for (var serviceKey in withLock)
                    if (serviceKey !== "omarchy.lock") withoutLock[serviceKey] = withLock[serviceKey]
                host._services = withoutLock
                test.check(test.active.panelAllowed, "absent lock provider admits instead of hiding")
                host._services = withLock
                test.active.endpoints = [test.sleepEndpoint("sleep-a", true)]
                test.stage = 61
            } else if (test.stage === 61 && test.active.selectedEndpoint) {
                var svc = test.active
                var token = svc.selectedEndpoint.token
                var before = Object.keys(svc.pendingRequests).length
                test.check(svc.sleepArmable && svc.sleepLockVerified, "sleep timer is armable with a pausable source and a visible lock")
                test.check(svc.armSleepTimer(15) === "ok", "arming accepted")
                var armedAt = svc.sleepDeadline
                test.check(armedAt > Date.now() + 14.9 * 60000 && armedAt < Date.now() + 15.1 * 60000, "arming stores an absolute deadline")
                test.check(SourceState.same(svc.sleepTarget, token), "arming records the selected token")
                test.check(Object.keys(svc.pendingRequests).length === before, "arming dispatches nothing")
                test.check(svc.armSleepTimer(30) === "ok" && svc.sleepDeadline > armedAt + 14 * 60000, "re-arming replaces the deadline")
                var kept = svc.sleepDeadline
                test.check(svc.armSleepTimer(0) === "invalid-value" && svc.armSleepTimer(721) === "invalid-value"
                    && svc.sleepDeadline === kept, "out-of-range arming is refused and keeps the deadline")
                svc.sleepDeadline = Date.now() + 60000
                svc.fireSleepTimer()
                test.check(svc.sleepDeadline > Date.now() && Object.keys(svc.pendingRequests).length === before,
                    "an early trigger reschedules instead of pausing")
                // Busy at expiry: one bounded re-fire, then a stated failure.
                var realPending = svc.pendingRequests
                var fake = Object.assign({}, realPending)
                fake["sleep-busy"] = { epoch: svc.admissionEpoch, deadline: Date.now() + 4000,
                    endpointToken: token, action: "PlayPause", revision: svc.selectionRevision }
                svc.pendingRequests = fake
                svc.sleepDeadline = Date.now() - 1
                svc.fireSleepTimer()
                test.check(svc.sleepRetried && svc.sleepDeadline > Date.now() && svc.sleepFailure === "",
                    "busy at expiry schedules exactly one re-fire")
                svc.sleepDeadline = Date.now() - 1
                svc.fireSleepTimer()
                test.check(svc.sleepFailure === "busy" && svc.sleepDeadline === 0, "busy again reports failure instead of retrying forever")
                svc.pendingRequests = realPending
                // Source gone at expiry: another endpoint is never addressed.
                test.check(svc.armSleepTimer(15) === "ok" && svc.sleepFailure === "", "re-arming clears the previous failure")
                svc.endpoints = [test.sleepEndpoint("sleep-b", true)]
                svc.sleepDeadline = Date.now() - 1
                svc.fireSleepTimer()
                test.check(svc.sleepFailure === "source-changed" && Object.keys(svc.pendingRequests).length === before,
                    "a changed source is never retargeted")
                svc.endpoints = [test.sleepEndpoint("sleep-a", false)]
                test.check(!svc.sleepArmable && svc.armSleepTimer(15) === "unavailable", "a source without CanPause cannot be armed")
                svc.endpoints = [test.sleepEndpoint("sleep-a", true)]
                test.check(svc.armSleepTimer(15) === "ok", "re-armed for expiry")
                svc.sleepDeadline = Date.now() - 1
                svc.fireSleepTimer()
                var sent = []
                for (var id in svc.pendingRequests) sent.push(svc.pendingRequests[id])
                test.check(sent.length === before + 1 && sent[sent.length - 1].action === "Pause"
                    && SourceState.same(sent[sent.length - 1].endpointToken, token) && svc.sleepDeadline === 0,
                    "expiry sends exactly one Pause to the armed token")
                test.stage = 62
            } else if (test.stage === 62 && Object.keys(test.active.pendingRequests).length === 0) {
                test.check(test.active.armSleepTimer(15) === "ok", "armed before lock")
                lock.locked = true
                test.check(test.active.sleepDeadline === 0 && test.active.sleepTarget === null, "locking cancels the sleep timer")
                lock.locked = false
                test.stage = 63
            } else if (test.stage === 63 && test.active.uiAllowed) {
                var present = host._services
                var scoped = ({})
                for (var scopedKey in present)
                    if (scopedKey !== "omarchy.lock") scoped[scopedKey] = present[scopedKey]
                host._services = scoped
                test.check(!test.active.sleepLockVerified && test.active.sleepArmable,
                    "an unseen lock still allows arming, and says so")
                host._services = present
                // Media-key verbs: bounded codes, and never the user's error line.
                var ipc = test.active
                ipc.actionError = "stale-track"
                test.check(ipc.externalPrevious() === "unavailable", "a verb the source does not advertise is unavailable")
                test.check(ipc.externalNext() === "ok", "a media-key verb dispatches")
                var dispatched = []
                for (var rid in ipc.pendingRequests) dispatched.push(ipc.pendingRequests[rid])
                test.check(dispatched.length === 1 && dispatched[0].action === "Next" && dispatched[0].external === true
                    && SourceState.same(dispatched[0].endpointToken, ipc.selectedEndpoint.token), "exactly one Next to the selected source")
                test.check(ipc.externalPlayPause() === "busy", "a second verb while one is pending is busy")
                test.check(ipc.actionError === "stale-track", "dispatching never writes the error line")
                test.stage = 64
            } else if (test.stage === 64 && Object.keys(test.active.pendingRequests).length === 0) {
                // The helper knows no such endpoint and answers with a failure.
                test.check(test.active.actionError === "stale-track", "an IPC command's failed result never writes the error line")
                test.active.actionError = ""
                test.active.endpoints = [test.transportEndpoint(null, null)]
                test.stage = 640
            } else if (test.stage === 640 && test.active.selectedEndpoint) {
                var unavailable = test.active
                test.check(unavailable.externalShuffle() === "unavailable" && unavailable.externalRepeat() === "unavailable",
                    "unknown shuffle and repeat state never dispatches")
                unavailable.endpoints = [test.transportEndpoint(false, "Bogus")]
                test.check(unavailable.externalRepeat() === "unavailable", "invalid repeat state is unavailable")
                unavailable.endpoints = [test.transportEndpoint(false, "None")]
                test.stage = 641
            } else if (test.stage === 641 && test.active.selectedEndpoint && Object.keys(test.active.pendingRequests).length === 0) {
                var shuffleOff = test.active
                test.check(shuffleOff.externalShuffle() === "ok", "shuffle dispatches when available")
                var firstToggle = test.pendingCommand(shuffleOff)
                test.check(firstToggle && firstToggle.action === "SetShuffle" && firstToggle.value === true,
                    "shuffle sends the opposite of false")
                test.check(shuffleOff.externalRepeat() === "busy", "transport verbs share pending admission")
                test.stage = 642
            } else if (test.stage === 642 && Object.keys(test.active.pendingRequests).length === 0) {
                var shuffleOn = test.active
                shuffleOn.endpoints = [test.transportEndpoint(true, "None")]
                test.check(shuffleOn.externalShuffle() === "ok", "shuffle dispatches from true state")
                var secondToggle = test.pendingCommand(shuffleOn)
                test.check(secondToggle && secondToggle.action === "SetShuffle" && secondToggle.value === false,
                    "shuffle sends the opposite of true")
                test.stage = 643
            } else if (test.stage === 643 && Object.keys(test.active.pendingRequests).length === 0) {
                var repeatOff = test.active
                test.check(repeatOff.externalRepeat() === "ok", "repeat dispatches from off")
                var playlist = test.pendingCommand(repeatOff)
                test.check(playlist && playlist.action === "SetLoopStatus" && playlist.value === "Playlist",
                    "repeat advances off to playlist")
                test.stage = 644
            } else if (test.stage === 644 && Object.keys(test.active.pendingRequests).length === 0) {
                var repeatPlaylist = test.active
                repeatPlaylist.endpoints = [test.transportEndpoint(true, "Playlist")]
                test.check(repeatPlaylist.externalRepeat() === "ok", "repeat dispatches from playlist")
                test.check(test.pendingCommand(repeatPlaylist).value === "Track", "repeat advances playlist to track")
                test.stage = 645
            } else if (test.stage === 645 && Object.keys(test.active.pendingRequests).length === 0) {
                var repeatTrack = test.active
                repeatTrack.endpoints = [test.transportEndpoint(true, "Track")]
                test.check(repeatTrack.externalRepeat() === "ok", "repeat dispatches from track")
                test.check(test.pendingCommand(repeatTrack).value === "None", "repeat advances track to off")
                test.stage = 646
            } else if (test.stage === 646 && Object.keys(test.active.pendingRequests).length === 0) {
                var seek = test.active
                test.check(seek.externalSeek(-3601) === "unavailable" && seek.externalSeek(3601) === "unavailable",
                    "seek rejects offsets beyond one hour")
                test.check(seek.externalSeek(-15.5) === "ok", "relative seek dispatches")
                var offset = test.pendingCommand(seek)
                test.check(offset && offset.action === "Seek" && offset.value === -15.5,
                    "relative seek carries the signed seconds")
                test.stage = 647
            } else if (test.stage === 647 && Object.keys(test.active.pendingRequests).length === 0) {
                var missing = test.active
                missing.endpoints = []
                test.check(missing.externalShuffle() === "unavailable" && missing.externalRepeat() === "unavailable"
                    && missing.externalSeek(15) === "unavailable", "missing source refuses all new transport verbs")
                missing.endpoints = [test.sleepEndpoint("sleep-a", true)]
                lock.locked = true
                test.check(test.active.externalPlayPause() === "unavailable", "a visible lock refuses media-key verbs")
                lock.locked = false
                test.stage = 65
            } else if (test.stage === 65 && test.active.uiAllowed) {
                var visible = host._services
                var hidden = ({})
                for (var hiddenKey in visible)
                    if (hiddenKey !== "omarchy.lock") hidden[hiddenKey] = visible[hiddenKey]
                host._services = hidden
                test.check(test.active.externalNext() === "ok", "media keys work where the lock cannot be seen, as the desktop's own bindings do")
                host._services = visible
                test.stage = 650
            } else if (test.stage === 650 && test.active.settingsDirReady && test.active.onboardingOffered) {
                // Typed settings in the plugin's own file, beside the shell's booleans.
                var typed = test.active
                test.check(typed.hud === false, "hud starts off by default")
                test.check(typed.settingsFilePath === Quickshell.env("XDG_CONFIG_HOME") + "/nookisle/settings.json",
                    "the settings file lives under XDG_CONFIG_HOME")
                var reported = test.ipcStatus(typed)
                test.check(reported !== null && reported.settings !== null && typeof reported.settings === "object"
                    && sameValues(Object.keys(reported.settings).sort(), Settings.keys("file").filter(function (key) { return !Settings.entry(key).internal && key !== "calendarSources" }).sort())
                    && sameValues(reported.settings, Settings.publicValues(Settings.defaults("file"))),
                    "status() reports the schema's file keys, with calendar sources redacted")
                test.check(typed.fileSettings.hoverDwell === 300 && typed.fileSettings.leaveGrace === 100,
                    "without a settings file every typed setting is its default")
                test.check(typed.configure(JSON.parse('{"hoverDwell":"x"}')) === false, "a non-number hoverDwell is refused")
                test.check(typed.configure({ hoverDwell: 1001 }) === false && typed.configure({ hoverDwell: 2.5 }) === false,
                    "an out-of-range or fractional hoverDwell is refused")
                test.check(typed.configureError === "invalid", "a refused value names its cause, got " + typed.configureError)
                var revision = registry.registryRevision
                test.check(typed.configure({ hoverDwell: 450, hud: "x" }) === false && typed.fileSettings.hoverDwell === 300
                    && registry.registryRevision === revision, "a batch with one invalid value writes nothing to either store")
                test.check(typed.configure(JSON.parse('{"island":true}')) === true && typed.island === true
                    && registry.registryRevision === revision + 1, "a boolean batch writes the shell config as before")
                test.check(typed.configure({ hoverDwell: 450, hud: true }) === true && typed.fileSettings.hoverDwell === 450
                    && typed.hud === true && registry.shellConfig.plugins[0].settings.hoverDwell === undefined,
                    "a mixed batch writes each key to its own store")
                test.check(typed.configure({ leaveGrace: 150 }) === true && typed.fileSettings.leaveGrace === 150,
                    "a file-only batch leaves the shell config alone")
                test.check(sameValues(test.ipcStatus(typed).settings,
                    Settings.publicValues(Settings.resolve({ hoverDwell: 450, leaveGrace: 150 }))),
                    "status() reports the written typed values")
                test.check(typed.configure({ alwaysShowTabs: false }) && typed.fileSettings.alwaysShowTabs === false,
                    "tab row can be hidden while not remembering a tab")
                test.check(typed.configure({ rememberLastTab: true, alwaysShowTabs: false })
                    && typed.fileSettings.rememberLastTab === true && typed.fileSettings.alwaysShowTabs === true,
                    "remembering a tab keeps its row visible even with conflicting batch values")
                test.check(typed.configure({ rememberLastTab: false, alwaysShowTabs: true })
                    && typed.fileSettings.rememberLastTab === false && typed.fileSettings.alwaysShowTabs === true,
                    "tab preferences can be restored")
                test.check(typed.fileSettings.idleStyle === "glance" && typed.configure({ showIdleFace: true }) === true
                    && typed.fileSettings.idleStyle === "face",
                    "the old idle face switch still selects the face over a saved style")
                test.check(typed.configure({ showIdleFace: false }) === true && typed.fileSettings.idleStyle === "glance",
                    "and turning it off returns to the glance")
                test.stage = 651
            } else if (test.stage === 651) {
                settingsProbe.path = test.active.settingsFilePath
                var saved = test.readSettingsProbe()
                if (saved && saved.version === 1 && saved.values && saved.values.leaveGrace === 150) {
                    var expectedValues = Settings.defaults("file")
                    expectedValues.hoverDwell = 450
                    expectedValues.leaveGrace = 150
                    test.check(sameValues(saved.values, expectedValues),
                        "the file holds version 1 and exactly the typed values written")
                    test.settingsModes = ""
                    test.settingsModesStarted = Date.now()
                    settingsModeProbe.command = ["stat", "-c", "%a", test.active.settingsDir, test.active.settingsFilePath]
                    settingsModeProbe.running = true
                    test.stage = 652
                }
            } else if (test.stage === 652 && test.settingsModes && !settingsModeProbe.running) {
                if (test.settingsModes !== "700 600" && Date.now() - test.settingsModesStarted < 2000) {
                    test.settingsModes = ""
                    settingsModeProbe.running = true
                    return
                }
                test.check(test.settingsModes === "700 600", "the settings directory is 0700 and the file 0600, got " + test.settingsModes)
                test.chmodSettingsDir("500")
                test.stage = 6520
            } else if (test.stage === 6520 && test.settingsChmodDone) {
                // An unwritable destination fails the save, and the whole batch with it.
                var blocked = test.active
                var blockedRevision = registry.registryRevision
                test.check(blocked.configure({ hoverDwell: 600, hud: false }) === false && blocked.hud === true
                    && registry.registryRevision === blockedRevision && blocked.fileSettings.hoverDwell === 450,
                    "a mixed batch whose file save fails changes neither store")
                test.check(blocked.configure({ leaveGrace: 200 }) === false && blocked.fileSettings.leaveGrace === 150,
                    "a file-only batch whose save fails is refused and keeps the old value")
                test.check(blocked.configureError === "save-failed", "a failed save names its cause, got " + blocked.configureError)
                var kept = test.readSettingsProbe()
                test.check(kept && sameValues(kept.values, Settings.resolve({ hoverDwell: 450, leaveGrace: 150 })),
                    "the file on disk keeps its last good values")
                test.chmodSettingsDir("700")
                test.stage = 6521
            } else if (test.stage === 6521 && test.settingsChmodDone) {
                settingsProbe.setText(JSON.stringify({ version: 1, values: { hoverDwell: 700, leaveGrace: "x", bogus: true } }))
                test.stage = 653
            } else if (test.stage === 653 && test.active.fileSettings.hoverDwell === 700) {
                var reloaded = test.active.fileSettings
                test.check(reloaded.leaveGrace === 100 && !("bogus" in reloaded),
                    "a reloaded file keeps valid values, defaults invalid ones and drops unknown keys")
                settingsProbe.setText("{ not json")
                test.stage = 654
            } else if (test.stage === 654 && test.active.fileSettings.hoverDwell === 300) {
                test.check(JSON.stringify(test.active.fileSettings) === JSON.stringify(Settings.defaults("file")),
                    "a corrupt settings file reads as all defaults")
                test.check(test.active.configure({ hoverDwell: 300 }), "the next settings save succeeds")
                test.check(test.active.configureError === "", "a success clears the cause")
                // The welcome's remembered player persists as an app identity
                // and steers Auto; forgetting it clears both.
                var chooser = test.active, heldEndpoints = chooser.endpoints
                function fakeEndpoint(name, owner, status) {
                    return { token: { busEpoch: "bus", wellKnownName: "org.mpris.MediaPlayer2." + name,
                        uniqueOwner: owner, endpointGeneration: "1" }, status: status,
                        presentation: { hostApp: name, controlScope: "application" } }
                }
                var spotify = fakeEndpoint("spotify", ":1.71", "Paused"), mpv = fakeEndpoint("mpv", ":1.72", "Playing")
                chooser.endpoints = [spotify, mpv]
                test.check(chooser.rememberSource(spotify.token)
                    && chooser.fileSettings.preferredSource === "org.mpris.MediaPlayer2.spotify"
                    && chooser.selectionState.preferred === "org.mpris.MediaPlayer2.spotify"
                    && chooser.selectionMode === "auto"
                    && SourceState.same(chooser.selectionState.selected, spotify.token),
                    "a remembered player is saved and followed while another plays")
                test.check(chooser.rememberSource({ wellKnownName: "org.mpris.MediaPlayer2.gone" }) === false,
                    "a player that is not present cannot be remembered")
                test.check(chooser.rememberSource(null) && chooser.fileSettings.preferredSource === ""
                    && chooser.selectionState.preferred === "", "forgetting clears the file and the selection's preference")
                chooser.endpoints = heldEndpoints
                // Reduced motion follows the desktop unless told not to, and
                // stops the spectrum capture.
                chooser.desktopReducedMotion = true
                test.check(chooser.reducedMotion === true && chooser.spectrumDesired === false,
                    "a desktop without animations reduces motion and wants no spectrum")
                test.check(chooser.configure({ followDesktopMotion: false }) && chooser.reducedMotion === false,
                    "not following the desktop keeps full motion")
                test.check(chooser.configure({ followDesktopMotion: true }) && chooser.reducedMotion === true,
                    "following it again reduces motion")
                chooser.desktopReducedMotion = false
                test.check(chooser.reducedMotion === false, "the desktop's animations back on restore motion")
                badSettingsProbe.path = test.active.settingsFilePath + ".bad"
                badSettingsProbe.reload()
                test.check(badSettingsProbe.text() === "{ not json",
                    "the corrupt original is preserved before a settings save")
                // The settings and welcome windows.
                var windows = test.active
                var ipc = test.ipcHandler(windows)
                test.check(windows.onboardingOffered === true && windows.fileSettings.onboardingDone === false,
                    "the first usable island offered the unfinished welcome")
                test.check(ipc.onboarding() === "ok" && windows.onboardingWindowOpen === true, "onboarding() reopens the welcome")
                lock.locked = true
                test.check(windows.onboardingWindowOpen === false && windows.fileSettings.onboardingDone === false,
                    "a lock interrupts the unfinished welcome without completing it")
                lock.locked = false
                test.stage = 6541
            } else if (test.stage === 6541 && test.active.uiAllowed && test.active.onboardingWindowOpen) {
                var windows = test.active
                var ipc = test.ipcHandler(windows)
                test.check(windows.onboardingOffered === true && windows.fileSettings.onboardingDone === false,
                    "unlocking reoffers the unfinished welcome")
                test.check(ipc.settings() === "ok" && windows.settingsWindowOpen === true && windows.settingsSection === "",
                    "settings() opens the settings window")
                test.reopenGeneration = windows.settingsWindowGeneration
                test.check(windows.openSettings("calendar") === true && windows.settingsSection === "calendar",
                    "the window can open on one section")
                test.check(windows.settingsWindowOpen === false,
                    "an open window is unmapped first, to map again on the current workspace")
                test.stage = 6542
            } else if (test.stage === 6542 && test.active.settingsWindowOpen) {
                var windows = test.active
                var ipc = test.ipcHandler(windows)
                test.check(windows.settingsWindowGeneration === test.reopenGeneration + 1
                    && windows.settingsSection === "calendar", "and it maps again on the asked section")
                windows.finishOnboarding()
                test.check(windows.onboardingWindowOpen === false && windows.fileSettings.onboardingDone === true,
                    "finishing the welcome closes it and records it in the settings file")
                test.check(ipc.onboarding() === "ok" && windows.onboardingWindowOpen === true,
                    "onboarding() still reopens a finished welcome")
                lock.locked = true
                test.check(!windows.settingsWindowOpen && !windows.onboardingWindowOpen
                    && ipc.settings() === "unavailable" && ipc.onboarding() === "unavailable",
                    "a lock closes both windows and refuses to open them")
                lock.locked = false
                test.stage = 655
            } else if (test.stage === 655 && test.active.uiAllowed && test.active.brightnessMonitorRunning) {
                test.check(!test.active.onboardingWindowOpen, "unlocking does not offer a finished welcome again")
                test.stage = 6551
            } else if (test.stage === 6551) {
                // Opt-in shelf persistence: private, atomic, salvaged per item.
                var persisting = test.active
                test.check(persisting.shelfPersist === false && persisting.shelfFilePath
                    === Quickshell.env("XDG_STATE_HOME") + "/nookisle/shelf.json", "shelf persistence is off by default and lives under XDG_STATE_HOME")
                persisting.shelfClear()
                test.check(persisting.configure({ shelfPersist: true }) === true && persisting.shelfPersist === true,
                    "shelf persistence can be turned on")
                persisting.shelfAdd(["file:///tmp/persisted%20one.txt", "https://example.com/p"])
                persisting.shelfAddDrop([], "persisted note")
                shelfProbe.path = persisting.shelfFilePath
                test.stage = 656
            } else if (test.stage === 656) {
                var stored = test.readShelfProbe()
                if (stored && Array.isArray(stored.items) && stored.items.length === 3) {
                    test.check(stored.version === 1 && stored.items[0].uri === "file:///tmp/persisted%20one.txt"
                        && stored.items[1].url === "https://example.com/p" && stored.items[2].text === "persisted note"
                        && !("id" in stored.items[0]) && !("temp" in stored.items[0]), "the shelf file holds each item without ids")
                    test.shelfMode = ""
                    shelfModeProbe.command = ["stat", "-c", "%a", test.active.shelfFilePath]
                    shelfModeProbe.running = true
                    test.stage = 657
                }
            } else if (test.stage === 657 && test.shelfMode !== "") {
                test.check(test.shelfMode === "600", "the shelf file is readable only by its owner")
                test.check(test.active.configure({ shelfPersist: false }) === true, "shelf persistence can be turned off")
                test.stage = 658
            } else if (test.stage === 658 && test.readShelfProbe() === null) {
                test.check(test.active.shelfEntries.length === 3, "turning persistence off deletes the file but keeps the session's shelf")
                shelfProbe.setText(JSON.stringify({ version: 1, items: [
                    { kind: "file", uri: "file:///tmp/kept.txt", name: "Kept", addedAt: 5 },
                    { kind: "file", uri: "http://not-a-file" }, 7, null, { kind: "text", text: "" },
                    { kind: "link", url: "https://example.com/kept" },
                    { kind: "file", uri: "file:///tmp/persisted%20one.txt" }] }))
                test.check(test.active.configure({ shelfPersist: true }) === true, "shelf persistence can be turned back on")
                test.stage = 6585
            } else if (test.stage === 6585 && test.active.shelfLoaded) {
                var merged = test.active.shelfEntries
                test.check(merged.length === 5 && merged[0].uri === "file:///tmp/kept.txt" && merged[0].name === "Kept"
                    && merged[0].addedAt === 5 && merged[1].url === "https://example.com/kept"
                    && merged[2].uri === "file:///tmp/persisted%20one.txt" && merged[3].url === "https://example.com/p"
                    && merged[4].text === "persisted note",
                    "loading salvages valid entries, drops corrupt ones and merges the session's items without duplicates")
                test.stage = 659
            } else if (test.stage === 659) {
                var rewritten = test.readShelfProbe()
                if (rewritten && Array.isArray(rewritten.items) && rewritten.items.length === 5) {
                    test.check(true, "the salvaged shelf is written back whole")
                    test.check(test.active.configure({ shelfPersist: false }) === true, "persistence off again")
                    test.active.shelfClear()
                    shelfFixtureSetup.running = true
                    test.stage = 6590
                }
            } else if (test.stage === 6590 && test.shelfFixtureReady && test.active.connected
                && test.active.shelfTempReady && test.active.shelfActions.toolsReady) {
                // Thumbnails, MIME icons and file actions through the real helper and tools.
                var viewer = test.active
                test.check(viewer.shelfAdd([test.shelfUri(test.shelfFixture)]) === 1, "a local image is shelved")
                test.shelfPhoto = viewer.shelfEntries[0].id
                test.stage = 6591
            } else if (test.stage === 6591 && test.active.shelfMimes[test.shelfPhoto] === "image/png") {
                var photo = test.active
                test.check(JSON.stringify(photo.shelfIcons(test.shelfPhoto)) === JSON.stringify(["image-png", "image-x-generic"]),
                    "a shelved file's MIME type picks its theme icons")
                var candidates = photo.shelfThumbnailCandidates(test.shelfPhoto)
                test.check(candidates.length === 0, "the Service does not expose an unvalidated cache entry")
                test.check(photo.requestShelfThumbnail(test.shelfPhoto) === true, "a missing thumbnail is requested from the helper")
                test.stage = 6592
            } else if (test.stage === 6592 && test.active.shelfThumbnails[test.shelfPhoto]) {
                var thumbed = test.active
                var generated = thumbed.shelfThumbnails[test.shelfPhoto]
                test.check(generated === Quickshell.env("XDG_CACHE_HOME") + "/thumbnails/normal/" + Qt.md5(test.shelfUri(test.shelfFixture)) + ".png"
                    && JSON.stringify(thumbed.shelfThumbnailCandidates(test.shelfPhoto)) === JSON.stringify([generated]),
                    "the helper validates the cache entry before the view receives it")
                // The helper exits unexpectedly with a thumbnail request in
                // flight: a malformed frame makes it terminate (exit code 4)
                // through the real process-exit path, not stopOwned().
                var dropped = Object.assign({}, thumbed.shelfThumbnails)
                delete dropped[test.shelfPhoto]
                thumbed.shelfThumbnails = dropped
                thumbed.shelfThumbnailRequests = ({ "thumb-in-flight": test.shelfPhoto })
                test.expectProtocolExit = true
                test.check(thumbed.send("thumbnail", { requestId: "malformed" }) === true, "a malformed frame is sent")
                test.stage = 65921
            } else if (test.stage === 65921 && !test.active.connected && !test.active.helperRunning) {
                var lost = test.active
                test.check(Object.keys(lost.shelfThumbnailRequests).length === 0
                    && lost.shelfThumbnailOwed.indexOf(test.shelfPhoto) >= 0,
                    "an unexpected helper exit drops the request it owed and remembers the item")
                test.check(!test.expectProtocolExit, "the helper exited with the protocol error it was provoked into")
                test.check(lost.requestShelfThumbnail(test.shelfPhoto) === false, "no request is sent while the helper is gone")
                test.check(lost.retryConnection() === true, "the helper is started again")
                test.stage = 65922
            } else if (test.stage === 65922 && test.active.connected && test.active.shelfThumbnails[test.shelfPhoto]) {
                var back = test.active
                test.check(back.shelfThumbnailOwed.length === 0 && Object.keys(back.shelfThumbnailRequests).length === 0,
                    "the replacement helper was asked again and answered")
                // A busy answer is retried when its timer fires.
                var cleared = Object.assign({}, back.shelfThumbnails)
                delete cleared[test.shelfPhoto]
                back.shelfThumbnails = cleared
                back.shelfThumbnailRequests = ({ "thumb-busy": test.shelfPhoto })
                back.receiveThumbnail({ requestId: "thumb-busy", status: "busy" })
                test.check(back.shelfThumbnailBusy[test.shelfPhoto] === 1 && Object.keys(back.shelfThumbnailRequests).length === 0,
                    "a busy answer waits for its retry")
                test.stage = 65923
            } else if (test.stage === 65923 && test.active.shelfThumbnails[test.shelfPhoto]) {
                var retried = test.active
                test.check(!(test.shelfPhoto in retried.shelfThumbnailBusy) && !retried.shelfThumbnailMisses[test.shelfPhoto],
                    "the retry timer asked again and the answer cleared the busy count")
                test.check(retried.shelfAction("compress", [test.shelfPhoto]) === true, "compress starts")
                test.stage = 6593
            } else if (test.stage === 6593 && test.active.shelfEntries.length === 2) {
                var zipped = test.active.shelfEntries[1]
                test.shelfZip = zipped.id
                test.check(zipped.temp === true && zipped.uri.indexOf(test.shelfUri(Quickshell.env("XDG_RUNTIME_DIR") + "/nookisle/shelf/")) === 0
                    && /\.zip$/.test(zipped.uri), "the zip lands in the runtime temp directory as a temporary item")
                test.check(test.active.shelfAction("rename", [test.shelfPhoto], "a/b") === false && test.active.shelfNotice === "rename-invalid",
                    "a rename with a slash is refused before anything runs")
                test.check(test.active.shelfAction("rename", [test.shelfPhoto], "renamed photo.png") === true, "rename starts")
                var renameJobs = Object.keys(test.active.shelfJobs).map(function(key) { return test.active.shelfJobs[key] })
                    .filter(function(job) { return job.name === "rename" })
                test.check(renameJobs.length === 1 && renameJobs[0].output === "" && /renamed photo\.png$/.test(renameJobs[0].target),
                    "a rename has a target but no output, so its failure can never delete a file")
                test.stage = 6594
            } else if (test.stage === 6594 && /renamed%20photo\.png$/.test(test.active.shelfEntries[0].uri)) {
                test.check(test.active.shelfEntries[0].id === test.shelfPhoto && test.active.shelfEntries[0].name === "renamed photo.png",
                    "a rename keeps the item in place under its new name")
                test.shelfExists = ""
                var zipPath = decodeURIComponent(test.active.shelfEntries[1].uri.slice(7))
                test.check(test.active.shelfRemoveItem(test.shelfZip) === true, "the temporary item is removed")
                test.shelfZipPath = zipPath
                test.stage = 6595
            } else if (test.stage === 6595 && Object.keys(test.active.shelfActions.jobs).length === 0) {
                shelfExistsProbe.command = ["test", "-e", test.shelfZipPath]
                shelfExistsProbe.running = true
                test.stage = 6596
            } else if (test.stage === 6596 && test.shelfExists !== "") {
                test.check(test.shelfExists === "no", "removing a temporary item deletes its file")
                var full = test.active
                var fillers = []
                for (var n = full.shelfEntries.length; n < full.shelfLimit; ++n)
                    fillers.push({ kind: "text", text: "filler " + n })
                test.check(full.shelfAddCandidates(fillers) === fillers.length, "the shelf is filled for output cleanup")
                test.check(full.shelfAction("compress", [test.shelfPhoto]) === true, "compression can finish while the shelf is full")
                for (var key in full.shelfJobs) test.shelfOrphanPath = full.shelfJobs[key].output
                test.stage = 6597
            } else if (test.stage === 6597 && Object.keys(test.active.shelfJobs).length === 0
                && Object.keys(test.active.shelfActions.jobs).length === 0) {
                test.shelfExists = ""
                shelfExistsProbe.command = ["test", "-e", test.shelfOrphanPath]
                shelfExistsProbe.running = true
                test.stage = 6598
            } else if (test.stage === 6598 && test.shelfExists !== "") {
                test.check(test.shelfExists === "no" && test.active.shelfEntries.length === test.active.shelfLimit,
                    "a generated output rejected by the full shelf is deleted")
                var service = test.active
                test.shelfFailedPath = service.shelfTempDir + "/failed-creator.zip"
                var job = service.shelfActions.execute({ argv: ["python3", "-c",
                    "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text('partial'); sys.exit(1)", test.shelfFailedPath] })
                var pending = Object.assign({}, service.shelfJobs)
                pending[job] = { name: "compress", id: test.shelfPhoto, output: test.shelfFailedPath, path: test.shelfFixture }
                service.shelfJobs = pending
                test.stage = 6599
            } else if (test.stage === 6599 && Object.keys(test.active.shelfJobs).length === 0
                && Object.keys(test.active.shelfActions.jobs).length === 0) {
                test.shelfExists = ""
                shelfExistsProbe.command = ["test", "-e", test.shelfFailedPath]
                shelfExistsProbe.running = true
                test.stage = 65991
            } else if (test.stage === 65991 && test.shelfExists !== "") {
                test.check(test.shelfExists === "no", "a failed creator's partial output is deleted")
                test.active.shelfClear()
                test.check(test.active.configure({ showCalendar: true }), "calendar can be enabled while hidden")
                test.stage = 6799
            } else if (test.stage === 6799 && test.active.calendarSource) {
                test.check(!test.active.islandShowing, "the hidden island keeps its calendar source loaded")
                test.check(test.active.configure({ showCalendar: false }), "calendar can be disabled again")
                test.stage = 6800
            } else if (test.stage === 6800) {
                // Removing a CalDAV source is the Service's transaction and
                // needs neither the island nor the calendar source.
                var service = test.active
                test.check(!service.islandShowing && !service.calendarSource && service.calendarSupported,
                    "the island is closed, no calendar source is loaded, and the helper has calendar support")
                test.clearResults = []
                test.credentialOrder = []
                service.calendarClearFinished.connect(test.noteClear)
                service.calendarFrame.connect(test.noteCalendarFrame)
                test.check(service.configure({ calendarSources: [test.calendarAccount, test.calendarFile] }), "two sources saved")
                test.check(service.removeCalendarSource(test.calendarAccount) === true, "the account is removed")
                test.check(JSON.stringify(service.fileSettings.calendarSources) === JSON.stringify([test.calendarFile]),
                    "the settings no longer list it")
                var onDisk = test.readSettingsProbe()
                test.check(onDisk && JSON.stringify(onDisk.values.calendarSources) === JSON.stringify([test.calendarFile])
                    && JSON.stringify(onDisk.values.calendarPendingClears) === JSON.stringify([test.calendarAccount]),
                    "the removal and the clear it owes are on disk together, before any password is touched")
                test.check(service.calendarClearPending(test.calendarAccount.url, test.calendarAccount.user),
                    "the clear is with the helper")
                test.stage = 6801
            } else if (test.stage === 6801 && test.active.fileSettings.calendarPendingClears.length === 0
                && !test.active.calendarClearPending(test.calendarAccount.url, test.calendarAccount.user)) {
                test.check(test.clearResults.length === 1 && test.clearResults[0].url === test.calendarAccount.url
                    && test.clearResults[0].user === test.calendarAccount.user,
                    "the helper answered the clear, and the Service reported it")
                var cleared = test.readSettingsProbe()
                test.check(cleared && JSON.stringify(cleared.values.calendarPendingClears) === "[]", "the answered clear is forgotten on disk")
                // Re-adding the account while its clear is with the helper:
                // a new password waits for that answer, then goes out.
                var readd = test.active
                test.credentialOrder = []
                test.check(readd.configure({ calendarSources: [test.calendarAccount] }) && readd.removeCalendarSource(test.calendarAccount)
                    && readd.calendarClearPending(test.calendarAccount.url, test.calendarAccount.user), "removed again; its clear is in flight")
                test.check(readd.configure({ calendarSources: [test.calendarAccount] }), "the account is added back")
                test.check(readd.fileSettings.calendarPendingClears.length === 1, "a clear already with the helper stays until answered")
                test.check(readd.sendCalendarCredential({ requestId: "harness-store", action: "store",
                    url: test.calendarAccount.url, user: test.calendarAccount.user, password: "harness-dummy" }) === true,
                    "the store for that account is accepted")
                test.check(readd.heldCalendarStores.length === 1, "and held behind the clear")
                test.stage = 6802
            } else if (test.stage === 6802 && test.credentialOrder.length === 2) {
                test.check(test.credentialOrder[0] === "clear" && test.credentialOrder[1] === "harness-store",
                    "the helper answered the clear before it saw the new password: " + test.credentialOrder.join(","))
                test.check(test.active.heldCalendarStores.length === 0 && test.active.fileSettings.calendarPendingClears.length === 0,
                    "nothing is left waiting")
                var again = test.active
                // A clear not yet sent is dropped when the account comes back.
                again.calendarSupported = false
                again.configure({ calendarSources: [test.calendarAccount] })
                test.check(again.removeCalendarSource(test.calendarAccount) && again.fileSettings.calendarPendingClears.length === 1
                    && !again.calendarClearPending(test.calendarAccount.url, test.calendarAccount.user),
                    "without calendar support the clear waits, saved")
                again.configure({ calendarSources: [test.calendarAccount] })
                test.check(again.fileSettings.calendarPendingClears.length === 0, "adding the account again drops its unsent clear")
                again.calendarSupported = true
                // An account still used by another source keeps its password.
                var tinted = Object.assign({ color: "#00ff00" }, test.calendarAccount)
                again.configure({ calendarSources: [test.calendarAccount, tinted] })
                test.check(again.removeCalendarSource(test.calendarAccount)
                    && JSON.stringify(again.fileSettings.calendarSources) === JSON.stringify([tinted])
                    && again.fileSettings.calendarPendingClears.length === 0, "a shared account is not cleared")
                test.chmodSettingsDir("500")
                test.stage = 6803
            } else if (test.stage === 6803 && test.settingsChmodDone) {
                var locked = test.active
                test.check(locked.removeCalendarSource(test.calendarAccount) === false
                    && locked.fileSettings.calendarSources.length === 1 && locked.fileSettings.calendarPendingClears.length === 0,
                    "a settings save that fails removes nothing and clears nothing")
                test.chmodSettingsDir("700")
                test.stage = 6804
            } else if (test.stage === 6804 && test.settingsChmodDone) {
                test.active.calendarClearFinished.disconnect(test.noteClear)
                test.active.calendarFrame.disconnect(test.noteCalendarFrame)
                test.check(test.active.configure({ calendarSources: [] }), "calendar sources reset")
                test.stage = 66
            } else if (test.stage === 66 && Object.keys(test.active.pendingRequests).length === 0) {
                // Island settings and shelf contract.
                var own = test.active
                test.check(own.island === true && own.hud === true, "island and hud on")
                test.check(own.visualizer === true && own.peek === false && own.tint === true
                    && own.power === true && own.lyrics === false,
                    "spectrum, tint and power start on; track peeks and lyrics start off")
                test.check(own.configure({ hud: "x" }) === false, "a non-boolean hud setting is refused")
                test.check(own.configure({ unknown: true }) === false, "an unknown setting is refused")
                test.check(own.configure({ lyrics: "yes" }) === false, "a non-boolean lyrics setting is refused")
                // Scoped host: no provider or mutator on the registry.
                var provider = registry.shellConfigProvider
                var mutator = registry.shellConfigMutator
                registry.shellConfigProvider = null
                registry.shellConfigMutator = null
                test.check(own.configure({ hud: false }) === true && own.hud === false && own.island === true,
                    "the scoped host writes a setting through updateEntryInline and it reads back")
                test.check(own.configure({ island: false }) === true && own.island === false && own.hud === false,
                    "a second write keeps the first, because updateEntryInline replaces every key")
                test.check(own.configure({ island: true, hud: true }) === true && own.island && own.hud, "settings restored")
                var last = host.inlineWrites[host.inlineWrites.length - 1]
                test.check(last.island === true && last.hud === true && last.reducedMotion === undefined,
                    "each write sends every known setting, and only known settings")
                test.check(own.configure({ visualizer: false, lyrics: true }) === true
                    && own.visualizer === false && own.lyrics === true,
                    "visualizer and lyrics write through the scoped host too")
                var last2 = host.inlineWrites[host.inlineWrites.length - 1]
                test.check(last2.visualizer === false && last2.lyrics === true,
                    "the write carries the two changed keys")
                // "id" is this fake host's own record of the entry, not a setting.
                test.check(Object.keys(last2).every(function (key) { return key === "id" || own.settingKeys.indexOf(key) >= 0 })
                    && last2.island === true && last2.hud === true && last2.reducedMotion === undefined,
                    "a write carries only keys already stored plus the changed ones, never one outside settingKeys")
                test.check(own.configure({ visualizer: true, lyrics: false }) === true, "visualizer and lyrics restored")
                host.barConfig = { layout: { left: [], center: [{ id: "io.github.bavanchun.nookisle", hud: false }], right: [] } }
                test.check(own.hud === false && own.island === true, "a fresh host copy replaces what this instance wrote")
                host.barConfig = { layout: { left: [], center: [{ id: "io.github.bavanchun.nookisle", hud: true }], right: [] } }
                test.check(own.hud === true && own.island === true, "fresh host copy restores hud")
                registry.shellConfigProvider = provider
                registry.shellConfigMutator = mutator
                test.check(own.shelfAdd(["file:///tmp/a.txt", "ftp://x", "file:///tmp/a.txt"]) === 1
                    && own.shelfItems.length === 1 && own.shelfNotice === "shelf-rejected", "the shelf keeps a local file once and reports a rejection")
                test.check(own.shelfAdd(["https://example.com/a"]) === 1 && own.shelfEntries.length === 2
                    && own.shelfEntries[1].kind === "link" && own.shelfItems.length === 1, "a web link is shelved as a link item, not a file")
                test.check(own.shelfAddDrop([], "a note") === 1 && own.shelfEntries[2].kind === "text"
                    && own.shelfEntries.length === 3 && own.shelfItems.length === 1, "dropped text is shelved as a text item")
                var linkOpen = own.shelfOpenCommand(own.shelfEntries[1].id)
                var textOpen = own.shelfOpenCommand(own.shelfEntries[2].id)
                test.check(linkOpen && JSON.stringify(linkOpen.argv) === JSON.stringify(["xdg-open", "https://example.com/a"])
                    && linkOpen.detached === true && textOpen && textOpen.copyId === own.shelfEntries[2].id,
                    "Open dispatches web links and text by their kinds")
                test.check(own.shelfAction("open", [own.shelfEntries[1].id]) === true,
                    "opening a link launches the default URL handler")
                test.check(own.shelfAction("open", [own.shelfEntries[2].id]) === true
                    && own.clipboardCopyPayload === "a note", "opening text copies its content")
                // Brightness monitor lifetime: bound to hud, not to
                // an imperative stop in stopOwned(), which also runs on a
                // helper reconnect.
                test.check(own.brightnessMonitorRunning === true, "the backlight monitor runs while hud is on")
                test.check(own.configure({ hud: false }) === true, "hud can be turned off")
                test.stage = 65992
            } else if (test.stage === 65992 && test.readShelfOpenLog() === "https://example.com/a") {
                test.check(true, "the URL handler received the validated link")
                test.stage = 660
            } else if (test.stage === 660 && !test.active.brightnessMonitorRunning) {
                test.check(test.active.hud === false, "configure(hud:false) is reflected on the coordinator")
                test.check(test.readouts(test.active, "intel_backlight", true) === "unavailable unavailable unavailable unavailable",
                    "with hud off no key readout is the island's, so Omarchy shows its own")
                test.check(test.active.configure({ hud: true }) === true, "hud restored")
                test.stage = 661
            } else if (test.stage === 661 && test.active.brightnessMonitorRunning) {
                // L4 (code review): island:false hides the pill that would
                // ever show the HUD, so the backlight monitor must stop then
                // too, not just when hud:false.
                test.check(test.active.configure({ island: false }) === true, "island can be turned off")
                test.stage = 6610
            } else if (test.stage === 6610 && !test.active.brightnessMonitorRunning) {
                test.check(test.active.island === false, "configure(island:false) is reflected on the coordinator")
                test.check(test.readouts(test.active, "intel_backlight", true) === "unavailable unavailable unavailable unavailable",
                    "the legacy widget draws no key readout, so Omarchy shows its own")
                test.check(test.active.configure({ island: true }) === true, "island restored")
                test.stage = 6611
            } else if (test.stage === 6611 && test.active.brightnessMonitorRunning) {
                // backlightChanged: the helper's event for the watched device re-reads
                // sysfs and emits exactly one hudEvent; an unrelated device
                // emits nothing. A fixture directory stands in for /sys.
                test.active.hudEvent.connect(test.captureHud)
                test.hudEvents = []
                test.backlightFixtureReady = false
                backlightFixtureSetup.running = true
                test.stage = 662
            } else if (test.stage === 662 && test.backlightFixtureReady) {
                test.stage = 663
            } else if (test.stage === 663) {
                var svc = test.active
                svc.backlightSysRoot = test.backlightFixtureRoot
                test.stage = 6631
            } else if (test.stage === 6631 && test.active.backlightDevice !== "") {
                test.check(test.active.backlightDevice === "intel_backlight",
                    "auto-detection prefers the display backlight to an alphabetically earlier device or Touch Bar")
                test.check(test.active.configure({ backlightDevice: "bbb_valid" }) === true,
                    "a configured backlight device overrides auto-detection")
                test.stage = 66311
            } else if (test.stage === 66311 && test.active.backlightDevice === "bbb_valid") {
                test.check(test.active.configure({ backlightDevice: "intel_backlight" }) === true,
                    "the display backlight can be selected again")
                test.stage = 6632
            } else if (test.stage === 6632 && test.active.backlightDevice === "intel_backlight") {
                var svc = test.active
                svc.receive({ type: "backlightChanged", device: "intel_backlight" })
                test.check(test.hudEvents.length === 1 && test.hudEvents[0].kind === "brightness"
                    && Math.abs(test.hudEvents[0].level - 0.5) < 0.001, "a helper backlight event for the watched device emits exactly one brightness event")
                svc.receive({ type: "backlightChanged", device: "other_device" })
                test.check(test.hudEvents.length === 1, "an unrelated device emits nothing")
                test.check(test.ipcHandler(svc).keyboardBacklightChanged() === "ok"
                    && test.hudEvents.length === 2 && test.hudEvents[1].kind === "keyboard"
                    && Math.abs(test.hudEvents[1].level - 0.5) < 0.001,
                    "the keyboardBacklightChanged IPC verb re-reads the discovered LED and emits one keyboard event")
                test.check(test.readouts(svc, "intel_backlight", true) === "ok ok ok ok",
                    "a showing island draws the volume, mic, keyboard and watched-backlight readouts")
                svc.hudHeldKind = "volume"
                test.check(test.readouts(svc, "intel_backlight", true) === "ok unavailable unavailable unavailable",
                    "a held volume bar leaves other key kinds to Omarchy's OSD")
                svc.hudHeldKind = ""
                test.check(test.readouts(svc, "bbb_valid", true) === "ok ok ok unavailable",
                    "a backlight the island does not watch is left to Omarchy")
                test.check(test.readouts(svc, "intel_backlight", false) === "unavailable unavailable unavailable unavailable",
                    "a hidden island draws no key readout")
                test.check(test.ipcHandler(svc).hudReadout("backlight", "intel_backlight") === "unavailable",
                    "an unknown readout kind is left to Omarchy")
                // Panel's HudModel draws nothing while suppressed: fullscreen,
                // or open with showOpenNotchHud off and no closed island.
                svc.hudSuppressed = true
                test.check(test.readouts(svc, "intel_backlight", true) === "unavailable unavailable unavailable unavailable",
                    "a suppressed readout, such as an open island without the header readout, is left to Omarchy")
                svc.hudSuppressed = false
                svc.brightnessctlBinary = test.backlightFixtureRoot + "/brightnessctl-fixture"
                test.hudEvents = []
                test.check(svc.setBrightnessLevel("keyboard", 0.75), "keyboard level dispatches through the source")
                test.stage = 6633
            } else if (test.stage === 6633) {
                brightnessWriteProbe.reload()
                if (String(brightnessWriteProbe.text()).trim() !== "-d tpacpi::kbd_backlight set 75%"
                    || test.hudEvents.length === 0) return
                test.check(true, "brightnessctl receives the selected LED device and percentage")
                test.check(test.hudEvents.length === 1 && test.hudEvents[0].kind === "keyboard"
                    && Math.abs(test.hudEvents[0].level - 1) < 0.001,
                    "a completed keyboard write re-reads the LED and reports the level it actually applied")
                test.hudEvents = []
                test.check(test.active.setBrightnessLevel("brightness", 0), "display level dispatches through the source")
                test.stage = 6634
            } else if (test.stage === 6634) {
                brightnessWriteProbe.reload()
                if (String(brightnessWriteProbe.text()).trim() !== "-d intel_backlight set 1%"
                    || test.hudEvents.length === 0) return
                test.check(true, "a display write never goes below 1%")
                test.check(test.hudEvents.length === 1 && test.hudEvents[0].kind === "brightness"
                    && Math.abs(test.hudEvents[0].level - 41 / 4096) < 0.0001,
                    "a completed display write re-reads the backlight level")
                var svc = test.active
                svc.hudEvent.disconnect(test.captureHud)
                // Shelf cap (phase 07): shelfAdd rejects overflow rather than
                // evicting what is already shelved.
                svc.shelfClear()
                var many = []
                for (var i = 0; i < svc.shelfLimit + 6; ++i) many.push("file:///tmp/cap" + i + ".txt")
                svc.shelfAdd(many)
                test.check(svc.shelfLimit === 64 && svc.shelfItems.length === 64 && svc.shelfNotice === "shelf-full",
                    "shelfAdd caps the Service list at the default shelfLimit of 64")
                svc.shelfClear()
                svc.shelfAdd(["file:///tmp/a.txt"])
                // Missing-binary clipboard path (phase 07): a binary Paste
                // cannot find never disables it; it reports the reason
                // instead. QProcess resolves the executable using this
                // process's own PATH regardless of the child's configured
                // environment, so a fake binary name is what actually forces
                // the missing-binary branch deterministically.
                svc.clipboardPasteBinary = "nookisle-nonexistent-test-binary"
                svc.shelfPaste()
                test.stage = 664
            } else if (test.stage === 664 && test.active.shelfNotice === "clipboard-unavailable") {
                // No text/uri-list on the clipboard: Ctrl+V reads its plain
                // text the way a drop's text is read (run-lifecycle.sh fake).
                test.active.clipboardPasteBinary = "nookisle-fake-paste"
                test.active.shelfClear()
                test.active.shelfNotice = ""
                test.active.shelfPaste()
                test.stage = 6641
            } else if (test.stage === 6641 && test.active.shelfEntries.length === 1) {
                var pastedLink = test.active.shelfEntries[0]
                test.check(pastedLink.kind === "link" && pastedLink.url === "https://example.org/pasted",
                    "a pasted single URL becomes a link item")
                test.active.shelfPaste()
                test.stage = 6642
            } else if (test.stage === 6642 && test.active.shelfEntries.length === 2) {
                var pastedText = test.active.shelfEntries[1]
                test.check(pastedText.kind === "text" && pastedText.text === "a pasted note\nsecond line",
                    "other pasted text becomes a text item")
                test.active.shelfPaste()
                test.stage = 6643
            } else if (test.stage === 6643 && test.active.shelfNotice === "clipboard-no-files") {
                test.check(test.active.shelfEntries.length === 2, "an empty clipboard adds nothing and says so")
                test.active.shelfNotice = ""
                test.active.shelfPaste()
                test.stage = 6644
            } else if (test.stage === 6644 && test.active.shelfEntries.length >= 4) {
                var both = test.active.shelfEntries
                test.check(both.length === 4 && both[2].kind === "link" && both[2].url === "https://example.org/from-uri-list"
                    && both[3].kind === "file" && both[3].uri === "file:///tmp/pasted-file.txt",
                    "a uri-list takes precedence over plain text and keeps its web link")
                test.active.clipboardPasteBinary = "wl-paste"
                test.active.shelfClear()
                test.active.shelfNotice = ""
                test.stage = 6645
            } else if (test.stage === 6645) {
                // M7 (code review): shelfCopy must refuse a uri that was
                // never shelved, so a caller cannot make an arbitrary string
                // reach the clipboard process.
                var svc4 = test.active
                svc4.shelfClear()
                svc4.shelfAdd(["file:///tmp/on-shelf.txt"])
                svc4.clipboardCopyStarted = false
                svc4.shelfCopy("file:///tmp/not-on-shelf.txt")
                test.check(svc4.clipboardCopyStarted === false, "shelfCopy refuses a uri that was never shelved")
                svc4.shelfCopy("file:///tmp/on-shelf.txt")
                test.stage = 6646
            } else if (test.stage === 6646 && test.active.clipboardCopyExited) {
                test.check(test.active.clipboardCopyStarted === true, "shelfCopy proceeds for a uri that is on the shelf")
                test.active.shelfNotice = ""
                test.active.shelfClear()
                test.active.shelfAdd(["file:///tmp/a.txt"])
                test.stage = 665
            } else if (test.stage === 665) {
                var own2 = test.active
                own2.islandPointerActive = true
                var thumbId = own2.shelfEntries[0].id
                // A rename or removal drops the item's pending request, so its
                // re-request is sent and the old answer is ignored.
                own2.shelfThumbnailRequests = ({ "thumb-stale": thumbId, "thumb-other": "other-id" })
                own2.forgetShelfIds([thumbId])
                test.check(JSON.stringify(own2.shelfThumbnailRequests) === JSON.stringify({ "thumb-other": "other-id" }),
                    "forgetting an item drops only its pending thumbnail request")
                own2.receiveThumbnail({ requestId: "thumb-stale", status: "failed" })
                test.check(!own2.shelfThumbnailMisses[thumbId], "a dropped request's late answer never marks a miss")
                // Busy answers are retried, a bounded number of times.
                for (var attempt = 1; attempt <= own2.shelfThumbnailBusyLimit + 1; ++attempt) {
                    own2.shelfThumbnailRequests = ({ "thumb-busy": thumbId })
                    own2.receiveThumbnail({ requestId: "thumb-busy", status: "busy" })
                    if (attempt <= own2.shelfThumbnailBusyLimit)
                        test.check(own2.shelfThumbnailBusy[thumbId] === attempt && !own2.shelfThumbnailMisses[thumbId]
                            && own2.shelfThumbnailRetryIds.indexOf(thumbId) >= 0, "busy answer " + attempt + " schedules a retry")
                }
                test.check(own2.shelfThumbnailMisses[thumbId] === true && !(thumbId in own2.shelfThumbnailBusy),
                    "after the retry limit the item keeps its icon")
                own2.forgetShelfIds([thumbId])
                // A helper stop drops every request it still owed.
                own2.shelfThumbnailRequests = ({ "thumb-owed": thumbId })
                own2.stopOwned()
                test.check(Object.keys(own2.shelfThumbnailRequests).length === 0 && own2.shelfThumbnailRetryIds.length === 0,
                    "a helper stop drops its pending thumbnail requests")
                test.check(own2.shelfItems.length === 1 && !own2.connected, "a helper stop keeps the shelf")
                // The owned Service restarts its helper on its own; wait for readmission.
                test.stage = 67
            } else if (test.stage === 67 && test.active.uiAllowed && test.active.connected
                    && test.active.receiverState.lastSequence !== "") {
                test.check(test.active.shelfItems.length === 1, "the shelf survives a helper restart")
                // The gate can open before the helper's first snapshot. Wait for
                // that commit so it cannot overwrite the fixture source.
                test.active.endpoints = [test.sleepEndpoint("sleep-a", true)]
                spectrumFixtureSetup.running = true
                test.stage = 670
            } else if (test.stage === 670 && test.spectrumFixtureReady) {
                // Spectrum process lifetime and the progress cadence.
                var sp = test.active
                test.check(sp.visualizer === true, "the live spectrum is on by default")
                sp.spectrumPath = test.spectrumFixture
                sp.viewVisible = true
                test.stage = 671
            } else if (test.stage === 671) {
                var sp1 = test.active
                test.check(!sp1.spectrumRunning && sp1.spectrumState === "off",
                    "no spectrum while the island itself is not showing (legacy panel)")
                test.check(sp1.subscriptionKey.endsWith(":hidden"),
                    "a collapsed legacy view still sends no progress subscription")
                sp1.islandShowing = true
                test.stage = 672
            } else if (test.stage === 672 && test.active.spectrumState === "running" && test.active.spectrumLevels.length === 12) {
                var sp2 = test.active
                sp2.spectrumBarSpan = 14
                test.check(sp2.spectrumRunning, "the spectrum runs while the island shows a playing source")
                test.check(test.levelsAre(sp2.spectrumLevels, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
                    "a valid line becomes the levels, from a capture started with --fps 15")
                test.check(sp2.subscriptionKey.endsWith(":1000"), "a collapsed playing island subscribes at 1000 ms")
                var kept = sp2.spectrumLevels
                sp2.onSpectrumLine("1 2 x")
                sp2.onSpectrumLine("1 2 3 4 5 6 7 8 9 10 11 12 13")
                sp2.onSpectrumLine("1 2 3 4 5 6 7 8 9 10 11 100")
                sp2.onSpectrumLine("1 2 3 4 5 6 7 8 9 10 11 1.5")
                sp2.onSpectrumLine("1 2 3 4 5 6 7 8 9 10  11")
                sp2.onSpectrumLine("0x1 2 3 4 5 6 7 8 9 10 11 12")
                sp2.onSpectrumLine("1e1 2 3 4 5 6 7 8 9 10 11 12")
                test.check(sp2.spectrumLevels === kept, "malformed or out-of-range lines leave the levels unchanged")
                sp2.onSpectrumLine("0 1 2 3 4 5 6 7 8 9 10 11")
                test.check(sp2.spectrumLevels === kept, "a line equal to the one on show is dropped, so it never repaints")
                sp2.onSpectrumLine("0 1 2 3 4 5 6 7 8 9 10 12")
                test.check(sp2.spectrumLevels === kept, "a line within the deadband of the one on show is dropped too")
                sp2.onSpectrumLine("0 1 2 3 4 5 6 7 8 9 10 20")
                test.check(sp2.spectrumLevels !== kept && test.levelsAre(sp2.spectrumLevels, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20]),
                    "a line that moves a bar visibly replaces the levels")
                sp2.spectrumBarSpan = 18
                sp2.spectrumLevels = [40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40]
                var tallKept = sp2.spectrumLevels
                sp2.onSpectrumLine("45 40 40 40 40 40 40 40 40 40 40 40")
                test.check(sp2.spectrumLevels === tallKept, "a subpixel single-bar change is dropped in the taller notch")
                sp2.onSpectrumLine("46 40 40 40 40 40 40 40 40 40 40 40")
                test.check(sp2.spectrumLevels !== tallKept && sp2.spectrumLevels[0] === 46,
                    "a one-pixel single-bar change is drawn in the taller notch")
                sp2.viewExpanded = true
                test.check(sp2.spectrumLevels.length === 0,
                    "expanding drops the levels, so the pill never comes back frozen after a silent stretch")
                sp2.onSpectrumLine("9 9 9 9 9 9 9 9 9 9 9 9")
                test.check(sp2.spectrumLevels.length === 0, "lines are not drawn while expanded")
                test.spectrumPid = sp2.spectrumPid
                test.stage = 673
            } else if (test.stage === 673) {
                var sp3 = test.active
                test.check(sp3.subscriptionKey.endsWith(":250"), "an expanded view subscribes at 250 ms")
                test.check(sp3.spectrumRunning, "the spectrum keeps running while expanded")
                // With an island on every screen, another island may be open
                // while the one drawing the bars is closed: its lines flow.
                sp3.spectrumPaused = false
                sp3.onSpectrumLine("5 5 5 5 5 5 5 5 5 5 5 5")
                test.check(test.levelsAre(sp3.spectrumLevels, [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]),
                    "lines are drawn while the drawing island is closed, even with another open")
                sp3.spectrumPaused = true
                test.check(sp3.spectrumLevels.length === 0, "pausing drops the levels")
                sp3.spectrumPaused = Qt.binding(function() { return sp3.viewExpanded })
                sp3.viewExpanded = false
                sp3.onSpectrumLine("0 1 2 3 4 5 6 7 8 9 10 12")
                test.check(test.levelsAre(sp3.spectrumLevels, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]),
                    "after a collapse, the line last shown before the expand is drawn again, not dropped as a repeat")
                lock.locked = true
                test.check(sp3.spectrumState === "off", "a lock stops the spectrum at once")
                test.check(sp3.spectrumLevels.length === 0, "a lock clears the levels")
                test.stage = 674
            } else if (test.stage === 674 && !test.active.spectrumRunning) {
                test.probePid(test.spectrumPid)
                test.stage = 675
            } else if (test.stage === 675 && test.probeResult) {
                test.check(test.probeResult === "gone", "the stopped spectrum process is gone (lock)")
                lock.locked = false
                test.stage = 676
            } else if (test.stage === 676 && test.active.uiAllowed && test.active.spectrumState === "running") {
                test.spectrumPid = test.active.spectrumPid
                test.check(test.active.configure({ visualizer: false }) === true, "visualizer can be turned off")
                test.check(test.active.spectrumLevels.length === 0 && test.active.spectrumState === "off",
                    "visualizer:false clears the levels and reports off")
                test.stage = 677
            } else if (test.stage === 677 && !test.active.spectrumRunning) {
                test.probePid(test.spectrumPid)
                test.stage = 678
            } else if (test.stage === 678 && test.probeResult) {
                test.check(test.probeResult === "gone", "the stopped spectrum process is gone (visualizer:false)")
                test.active.spectrumPath = test.spectrumFixture + "-missing"
                test.check(test.active.configure({ visualizer: true }) === true, "visualizer restored")
                test.stage = 679
            } else if (test.stage === 679 && test.active.spectrumState === "unavailable") {
                test.check(!test.active.spectrumRunning && test.active.spectrumLevels.length === 0,
                    "a missing binary reports unavailable and draws nothing")
                test.active.spectrumPath = test.spectrumFixture
                test.active.islandShowing = false
                test.active.islandShowing = true
                test.stage = 6790
            } else if (test.stage === 6790 && test.active.spectrumState === "running") {
                test.check(true, "the next desired edge retries after unavailable")
                // A pause and replay inside one stop: the old process is still
                // exiting when the capture is wanted again.
                test.spectrumPid = test.active.spectrumPid
                test.active.islandShowing = false
                test.active.islandShowing = true
                test.stage = 67900
            } else if (test.stage === 67900 && test.active.spectrumState === "running"
                    && test.active.spectrumPid !== test.spectrumPid) {
                test.check(test.active.spectrumRetryCount === 0 && !test.active.spectrumGaveUp,
                    "a stop and restart before the old process exited restarts it, not counted as a failure")
                test.spectrumPid = test.active.spectrumPid
                test.active.islandShowing = false
                test.active.viewVisible = false
                test.stage = 6791
            } else if (test.stage === 6791 && !test.active.spectrumRunning) {
                test.check(test.active.spectrumState === "off", "hiding the island stops the spectrum")
                test.probePid(test.spectrumPid)
                test.stage = 6792
            } else if (test.stage === 6792 && test.probeResult) {
                test.check(test.probeResult === "gone", "the stopped spectrum process is gone (hidden)")
                test.active.spectrumPath = test.backlightFixtureRoot + "/spectrum-fails"
                test.active.viewVisible = true
                test.active.islandShowing = true
                test.stage = 6793
            } else if (test.stage === 6793 && test.active.spectrumState === "unavailable") {
                test.check(!test.active.spectrumRunning && test.active.spectrumGaveUp
                    && test.active.spectrumRetryCount === 0, "a failed stream (exit 2) gives up at once, without retrying")
                test.active.spectrumPath = test.backlightFixtureRoot + "/spectrum-drops"
                test.active.islandShowing = false
                test.active.islandShowing = true
                test.stage = 6794
            } else if (test.stage === 6794 && test.active.spectrumRetryCount === 1 && !test.active.spectrumRunning) {
                test.check(test.active.spectrumState === "off" && !test.active.spectrumGaveUp,
                    "a dropped stream (exit 1) is retried, not given up")
                test.active.islandShowing = false
                test.active.viewVisible = false
                test.active.spectrumPath = test.spectrumFixture
                // Left armed on purpose: the supersession below must cancel it.
                test.check(test.active.armSleepTimer(60) === "ok", "armed before supersession")
                test.stage = 7
            } else if (test.stage === 7 && test.active.uiAllowed) {
                test.prior = test.active
                host.pluginReloading = true
                // A Service that died before sending leaves its owed clear in
                // the settings file; the retired one above can no longer send.
                settingsProbe.path = test.active.settingsFilePath
                settingsProbe.setText(JSON.stringify({ version: 1, values: Settings.resolve(Object.assign({},
                    test.active.fileSettings, { calendarSources: [], calendarPendingClears: [test.calendarAccount] })) }))
                settingsProbe.waitForJob()
                host._services = ({ "omarchy.lock": lock })
                test.installManifest(test.freshManifest())
                host.pluginReloading = false
                host.finalize(serviceComponent, serviceHost, registry.installedPlugins["io.github.bavanchun.nookisle"], "io.github.bavanchun.nookisle")
                test.active = host.serviceFor("io.github.bavanchun.nookisle")
                test.clearResults = []
                test.active.calendarClearFinished.connect(test.noteClear)
                test.check(test.prior.retired, "the old Service can no longer send")
                // A shelf save the retired Service had running finishes now: the
                // shelf file belongs to its successor, so nothing is deleted.
                var jobsBefore = Object.keys(test.prior.shelfActions.jobs).length
                test.prior.shelfWriteJob = "late-write"
                test.prior.handleShelfJob("late-write", "ok", 0, "")
                test.check(Object.keys(test.prior.shelfActions.jobs).length === jobsBefore && test.prior.shelfWriteJob === "",
                    "a retired Service finishing a shelf save never removes the shelf file")
                test.check(test.readSettingsProbe().values.calendarPendingClears.length === 1,
                    "a clear is saved in the settings file but was never sent")
                test.stage = 75
            } else if (test.stage === 75 && test.active.uiAllowed && test.active.fileSettings.calendarPendingClears.length === 0) {
                test.check(test.clearResults.length === 1 && test.clearResults[0].url === test.calendarAccount.url,
                    "after a restart the new Service sent the saved clear and the helper answered it")
                test.check(JSON.stringify(test.readSettingsProbe().values.calendarPendingClears) === "[]",
                    "and forgot it on disk")
                test.active.calendarClearFinished.disconnect(test.noteClear)
                test.check(test.active.configure({ calendarSources: [] }), "calendar sources reset")
                test.stage = 8
            } else if (test.stage === 8 && test.active.uiAllowed && !test.prior.helperRunning) {
                test.check(test.exits >= 1, "replacement waits for old helper exit")
                test.check(test.prior.sleepDeadline === 0 && test.prior.sleepTarget === null, "a superseded instance holds no armed sleep timer")
                test.check(test.prior.shelfItems.length === 0 && !test.prior.islandPointerActive, "a superseded instance holds no shelf or pointer state")
                host.finalize(serviceComponent, serviceHost, test.oldManifest, "io.github.bavanchun.nookisle")
                test.late = host.serviceFor("io.github.bavanchun.nookisle")
                test.stage++
            } else if (test.stage === 9 && !test.active.helperRunning) {
                test.check(test.late !== test.active, "actual finalize contract overwrites fresh service with late old load")
                test.check(test.late.diagnostic === "stale-host-load" && !test.late.helperRunning, "old load rejected without launching helper")
                test.check(host.serviceFor("io.github.bavanchun.nookisle") === test.late, "BLOCKER host retains stale inactive owner; sync skips occupied entry")
                registry.enabled = false
                registry.registryRevision++
                host.finalize(serviceComponent, serviceHost, registry.installedPlugins["io.github.bavanchun.nookisle"], "io.github.bavanchun.nookisle")
                test.active = host.serviceFor("io.github.bavanchun.nookisle")
                test.stage++
            } else if (test.stage === 10) {
                test.check(!test.active.helperRunning, "pending load after disable cannot launch")
                test.active.dispose()
                host._services = ({ "omarchy.lock": lock })
                // Count only attempts against the deliberately held lease;
                // earlier replacement races have their own assertions.
                test.contentionExits = 0
                leaseHolder.running = true
                test.stage++
            } else if (test.stage === 11 && test.leaseReady) {
                registry.enabled = true
                registry.registryRevision++
                host.finalize(serviceComponent, serviceHost, registry.installedPlugins["io.github.bavanchun.nookisle"], "io.github.bavanchun.nookisle")
                test.active = host.serviceFor("io.github.bavanchun.nookisle")
                test.stage++
            } else if (test.stage === 12 && test.active.diagnostic === "retry-exhausted") {
                test.check(test.contentionExits === 4 && test.active.retryCount === 3, "lease contention stops after initial attempt plus retries 1/2/4 seconds")
                test.check(leaseHolder.running && !test.active.helperRunning, "contender never kills or attaches to lease owner")
                test.check(test.eofExits === 3, "both displaced service helpers, and the deliberate shelf stop, exited cleanly on EOF")
                leaseHolder.stdinEnabled = false
                test.stage++
            } else if (test.stage === 13 && !leaseHolder.running) {
                test.check(test.active.retryConnection(), "explicit current-owner retry accepted")
                test.stage++
            } else if (test.stage === 14 && test.active.uiAllowed
                    && test.active.receiverState.lastSequence !== "") {
                // This retry also publishes an empty snapshot after admission.
                test.active.spectrumPath = test.spectrumFixture
                test.active.endpoints = [test.sleepEndpoint("sleep-a", true)]
                test.active.islandShowing = true
                test.stage = 140
            } else if (test.stage === 140 && test.active.spectrumState === "running") {
                test.spectrumPid = test.active.spectrumPid
                test.active.dispose()
                test.stage = 141
            } else if (test.stage === 141 && !test.active.spectrumRunning) {
                test.check(!test.active.islandShowing && test.active.spectrumState === "off", "dispose releases the island state")
                test.probePid(test.spectrumPid)
                test.stage = 142
            } else if (test.stage === 142 && test.probeResult) {
                test.check(test.probeResult === "gone", "the spectrum process is gone after dispose()")
                test.stage = 15
            } else if (test.stage === 15 && !test.active.helperRunning) {
                test.check(test.eofExits === 4, "explicit retry session also tears down cleanly")
                var packagedBrightness = Qt.createComponent(Qt.resolvedUrl("../../build/package/components/BrightnessSource.qml"))
                test.check(packagedBrightness.status === Component.Ready,
                    "staged brightness source loads: " + packagedBrightness.errorString())
                var packagedMic = Qt.createComponent(Qt.resolvedUrl("../../build/package/components/MicSource.qml"))
                test.check(packagedMic.status === Component.Ready,
                    "staged mic source loads: " + packagedMic.errorString())
                var packaged = Qt.createComponent(Qt.resolvedUrl("../../build/package/Service.qml"))
                test.check(packaged.status === Component.Ready, "staged production Service loads")
                if (packaged.status !== Component.Ready) { console.error(packaged.errorString()); test.done(); return }
                host.finalize(packaged, serviceHost, registry.installedPlugins["io.github.bavanchun.nookisle"], "io.github.bavanchun.nookisle")
                test.active = host.serviceFor("io.github.bavanchun.nookisle")
                test.check(test.active.helperPath.endsWith("build/package/libexec/nookisle-helper"), "production helper path resolves relative to staged Service")
                test.stage++
            } else if (test.stage === 16 && test.active.uiAllowed) {
                test.check(test.active.connected, "packaged default helper path completes real handshake and gate ACK")
                test.active.captureShelved.connect(function (kind, path) { test.capturesShelved.push(kind + ":" + path) })
                shotsSetup.running = true
                test.stage = 160
            } else if (test.stage === 160 && test.shotsReady && !test.statusPresenceChecked) {
                // status() carries the closed island's activity key and how
                // many apps capture each device, never which.
                test.active.reportActivity("recording|music", { mic: ["Zoom"], camera: [], screen: ["OBS", "Meet"] })
                var presence = test.ipcStatus(test.active)
                test.check(presence && presence.activity === "recording|music", "status reports the activity key")
                test.check(presence && test.sameValues(presence.privacy, { mic: 1, camera: 0, screen: 2 }),
                    "status reports privacy counts")
                var raw = test.ipcHandler(test.active).status()
                test.check(raw.indexOf("Zoom") < 0 && raw.indexOf("OBS") < 0, "status never names a capturing app")
                test.active.reportActivity("", null)
                test.check(test.sameValues(test.ipcStatus(test.active).privacy, { mic: 0, camera: 0, screen: 0 }),
                    "no privacy state reads as zero")
                test.statusPresenceChecked = true
            } else if (test.stage === 160 && test.shotsReady) {
                // A folder that does not exist is refused by the helper and
                // changes nothing.
                test.check(test.active.configure({ screenshotsToShelf: true, screenshotDir: test.shotsRoot + "/absent" }),
                    "screenshot settings accepted")
                test.check(!test.active.configure({ screenshotDir: "relative/folder" }), "a relative folder is refused")
                test.stage = 161
            } else if (test.stage === 161 && test.active.watchStatus === "invalid") {
                test.check(test.active.configure({ screenshotDir: test.shotsRoot, recordingsToShelf: true }),
                    "screenshot folder accepted")
                test.stage = 162
            } else if (test.stage === 162 && test.active.watchStatus === "ok" && test.active.watchWanted.screenshots
                    && test.active.watchKey.indexOf(test.shotsRoot) >= 0) {
                // The real helper watches the folder: a screenshot written
                // there is shelved.
                shotWriter.running = true
                test.stage = 163
            } else if (test.stage === 163 && test.shelved(test.shotsRoot + "/screenshot-2026-09-27_18-00-00.png")) {
                test.check(test.capturesShelved.indexOf("screenshot:" + test.shotsRoot + "/screenshot-2026-09-27_18-00-00.png") >= 0,
                    "a screenshot the helper saw is shelved and announced")
                // A recording that stops names its saved file; with the
                // option on, it is shelved too.
                test.active.systemEvent({ kind: "recording", active: true, startedAt: 1000, path: test.shotsRoot + "/rec.mp4" })
                test.check(test.active.recordingState.active && test.active.recordingState.startedAt === 1000, "recording state follows the helper")
                test.active.systemEvent({ kind: "recording", active: false, startedAt: 0, path: test.shotsRoot + "/rec.mp4" })
                test.check(test.shelved(test.shotsRoot + "/rec.mp4"), "a stopped recording is shelved when asked")
                test.active.systemEvent({ kind: "camera", holders: ["zoom", 5] })
                test.check(test.active.cameraHolders.length === 0, "a malformed event is dropped")
                test.check(test.capturesShelved.indexOf("recording:" + test.shotsRoot + "/rec.mp4") >= 0, "and announced")
                // Shelving recordings alone does not keep the /tmp watch.
                test.check(test.active.configure({ recordingActivity: false, screenshotsToShelf: false }), "options off")
                test.stage = 164
            } else if (test.stage === 164 && !test.active.watchWanted.recording && !test.active.watchWanted.screenshots) {
                test.check(test.active.fileSettings.recordingsToShelf === true, "the recording watch stops with the activity alone")
                test.check(test.active.configure({ recordingsToShelf: false }), "shelving off")
                test.active.systemEvent({ kind: "recording", active: true, startedAt: 2000, path: test.shotsRoot + "/b.mp4" })
                test.check(!test.active.recordingState.active, "no recording state while its watch is off")
                test.active.destroy()
                host._services = ({ "omarchy.lock": lock })
                test.active = null
                test.stage = 17
            } else if (test.stage === 17) {
                host.finalize(serviceComponent, serviceHost, registry.installedPlugins["io.github.bavanchun.nookisle"], "io.github.bavanchun.nookisle")
                test.active = host.serviceFor("io.github.bavanchun.nookisle")
                test.stage++
            } else if (test.stage === 18 && test.active.uiAllowed) {
                test.check(true, "actual Service.destroy releases child lease for fresh owner")
                test.active.dispose()
                test.stage++
            } else if (test.stage === 19 && !test.active.helperRunning) {
                test.done()
            }
        }
    }
}
