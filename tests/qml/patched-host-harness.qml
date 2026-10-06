import QtQuick
import Quickshell
import Quickshell.Io
// Quickshell indexes only directories reached by a static import. The staged
// Service is loaded by URL, so its own `import "components"` finds types only
// once that directory is indexed; the real host loads plugins by file URL.
import "package/components" as StagedComponents

ShellRoot {
    id: test
    property string pluginId: "io.github.bavanchun.nookisle"
    property string serviceUrl: Qt.resolvedUrl("package/Service.qml").toString()
    property string helperPath: Qt.resolvedUrl("package/libexec/nookisle-helper").toString().slice(7)
    property int stage: 0
    property int cycles: 0
    property int failures: 0
    property double started: Date.now()
    property var active: null
    property var activePid: null
    property var stale: null
    property bool delayNext: false
    property var delayed: null
    property int factoryCount: 0
    property int createdCount: 0
    property bool countReady: false
    property int helperCount: 0

    QtObject {
        id: registry
        property var installedPlugins: ({})
        property int registryRevision: 0
        property bool enabled: true
        function isEnabled(id) { return id === "omarchy.lock" || enabled }
        function entryPointUrl(manifest, kind) { return manifest.entryPoints[kind] }
    }
    Component {
        id: lockComponent
        QtObject {
            property bool locked: false
            property bool strandedLockResolved: true
            property bool strandedLock: false
        }
    }
    Item {
        id: shell
        property bool pluginReloading: false
        property var pluginRegistry: registry
        property string omarchyPath: "/isolated-host"
        property var barWidgetRegistry: null
        Item { id: serviceHost; visible: false }
        // PRODUCTION_SERVICE_LOADER
    }

    // The ordinary path returns Qt's actual Component unchanged. Only a
    // requested delayed load wraps its real factory so callback order can be
    // controlled without network timing. Service and Process stay production.
    function createServiceComponent(url, mode) {
        factoryCount++
        var real = Qt.createComponent(url, mode)
        if (!delayNext) return real
        delayNext = false
        check(real.status === Component.Ready, "delayed factory has compiled production Service")
        var facade = {
            status: Component.Loading, destroyed: 0, callbacks: [], saved: null,
            statusChanged: {
                connect: function(callback) { facade.callbacks.push(callback); facade.saved = callback },
                disconnect: function(callback) {
                    var index = facade.callbacks.indexOf(callback)
                    test.check(index >= 0, "loader disconnects its exact pending callback")
                    if (index >= 0) facade.callbacks.splice(index, 1)
                }
            },
            createObject: function(parent) { test.createdCount++; return real.createObject(parent) },
            errorString: function() { return real.errorString() },
            destroy: function() { facade.destroyed++; real.destroy() },
            completeLate: function() { facade.status = Component.Ready; facade.saved() }
        }
        delayed = facade
        return facade
    }
    function check(condition, message) {
        if (condition) console.log("PASS " + message)
        else { failures++; console.error("FAIL " + message) }
    }
    function install() {
        registry.installedPlugins = {
            "omarchy.lock": { id: "omarchy.lock", kinds: [] },
            "io.github.bavanchun.nookisle": { id: pluginId, kinds: ["service"], entryPoints: { service: serviceUrl } }
        }
        registry.registryRevision++
    }
    function restoreLock() {
        shell._services = { "omarchy.lock": lockComponent.createObject(serviceHost) }
    }
    function countHelpers() {
        countReady = false
        helperCount = 0
        counter.running = true
    }
    Process {
        id: counter
        // Match this run's unique staged executable, never the live plugin.
        command: ["pgrep", "-f", "^" + test.helperPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$"]
        stdout: SplitParser { onRead: data => { if (data.trim()) test.helperCount++ } }
        onExited: code => {
            test.check(code === 0 || code === 1, "helper process census succeeds")
            test.countReady = true
        }
    }
    function done() {
        tick.stop()
        shell.unloadPluginServices()
        console.log("PATCHED_HOST_RESULT failures=" + failures + " cycles=" + cycles)
        Qt.quit()
    }
    Timer {
        id: tick
        interval: 40
        repeat: true
        running: true
        onTriggered: {
            if (Date.now() - test.started > 20000) { test.check(false, "deadline at stage " + test.stage); test.done(); return }
            if (test.stage === 0) {
                test.install()
                test.restoreLock()
                test.delayNext = true
                test.check(shell.ensureService(test.pluginId) === null, "pending old load has no registered Service")
                test.stale = test.delayed
                var factories = test.factoryCount
                shell.ensureService(test.pluginId)
                shell._syncServices()
                test.check(test.factoryCount === factories, "ensure and sync deduplicate pending load")
                test.check(test.createdCount === 0, "pending load has not constructed Service")
                shell.pluginReloading = true
                shell.unloadPluginServices()
                test.install()
                shell.pluginReloading = false
                test.restoreLock()
                test.active = shell.ensureService(test.pluginId)
                test.check(test.active !== null, "real Qt factory synchronously registers fresh Service")
                test.stage++
            } else if (test.stage === 1 && test.active && test.active.uiAllowed) {
                test.activePid = test.active.helperPid
                test.check(test.active.helperPath === "file://" + test.helperPath, "production Service resolves unique staged helper")
                test.check(test.stale.destroyed === 1 && test.stale.callbacks.length === 0, "unload destroys pending factory and disconnects callback")
                test.stale.completeLate()
                test.check(shell.serviceFor(test.pluginId) === test.active, "late stale finalizer cannot displace fresh Service")
                test.check(test.createdCount === 0, "late stale callback cannot construct a Service or helper")
                test.install()
                shell._syncServices()
                test.check(shell.serviceFor(test.pluginId) === test.active, "ordinary rescan preserves fresh registration")
                test.countHelpers()
                test.stage++
            } else if (test.stage === 2 && test.countReady) {
                test.check(test.active.uiAllowed && test.active.helperPid === test.activePid, "fresh Service remains admitted with original PID after late callback")
                test.check(test.helperCount === 1, "exactly one helper after late callback and rescan")
                test.stage = 3
            } else if (test.stage === 3) {
                registry.enabled = false
                registry.registryRevision++
                shell._syncServices()
                test.active = null
                test.check(shell.serviceFor(test.pluginId) === null, "disable removes service registration")
                test.stage++
            } else if (test.stage === 4) {
                test.countHelpers()
                test.stage++
            } else if (test.stage === 5 && test.countReady) {
                if (test.helperCount !== 0) { test.stage = 4; return }
                test.check(test.helperCount === 0, "disable releases all staged helper processes")
                registry.enabled = true
                registry.registryRevision++
                test.delayNext = true
                shell.ensureService(test.pluginId)
                test.stale = test.delayed
                registry.enabled = false
                registry.registryRevision++
                shell._syncServices()
                test.stale.completeLate()
                test.check(shell.serviceFor(test.pluginId) === null && Object.keys(shell._serviceLoads).length === 0,
                    "pending load after disable cannot register or retain a claim")
                test.check(test.createdCount === 0, "disabled late callback never constructs a Service")
                registry.enabled = true
                registry.registryRevision++
                shell._syncServices()
                test.active = shell.serviceFor(test.pluginId)
                test.stage++
            } else if (test.stage === 6 && test.active && test.active.uiAllowed) {
                test.countHelpers()
                test.stage++
            } else if (test.stage === 7 && test.countReady) {
                test.check(test.helperCount === 1, "reenable completes real handshake with exactly one helper")
                shell.pluginReloading = true
                shell.unloadPluginServices()
                test.active = null
                test.check(Object.keys(shell._services).length === 0 && Object.keys(shell._serviceLoads).length === 0,
                    "unload clears registrations and pending claims")
                test.install()
                shell.pluginReloading = false
                test.restoreLock()
                test.active = shell.ensureService(test.pluginId)
                test.stage++
            } else if (test.stage === 8 && test.active && test.active.uiAllowed) {
                test.countHelpers()
                test.stage++
            } else if (test.stage === 9 && test.countReady) {
                test.check(test.helperCount === 1, "reload completes real handshake with exactly one helper")
                test.check(test.active.retryCount <= 3, "reload remains within production helper retry budget")
                test.cycles++
                if (test.cycles < 5) test.stage = 3
                else {
                    shell.unloadPluginServices()
                    test.active = null
                    test.stage = 10
                }
            } else if (test.stage === 10) {
                test.countHelpers()
                test.stage++
            } else if (test.stage === 11 && test.countReady) {
                if (test.helperCount !== 0) { test.stage = 10; return }
                test.check(test.helperCount === 0, "final unload leaves no staged helper process")
                test.check(Object.keys(shell._serviceLoads).length === 0, "final unload leaves no pending factory")
                test.done()
            }
        }
    }
}
