import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "qml/Protocol.js" as Protocol
import "qml/Timers.js" as Timers
import "qml/Settings.js" as Settings
import "components"
import "qml/Calendar.js" as Calendar
import "qml/SourceState.js" as SourceState
import "qml/Shelf.js" as Shelf
import "qml/Spectrum.js" as Spectrum
import "qml/Strings.js" as Strings
import "qml/Motion.js" as Motion

Item {
    id: root
    visible: false
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null
    property string omarchyPath: ""
    readonly property string pluginId: "io.github.bavanchun.nookisle"
    // Panel.qml binds this to the shell's Style.font.body and BarWidget.qml
    // reads it; without the declaration the binding has no target and the bar
    // font silently falls back to its literal default.
    property int bodyFontSize: 12
    property string helperPath: Qt.resolvedUrl("libexec/nookisle-helper").toString()
    readonly property var currentService: shell ? shell.serviceFor(pluginId) : null
    readonly property var lockService: {
        var revision = pluginRegistry ? pluginRegistry.registryRevision : 0
        return SourceState.lockProvider(pluginRegistry, shell)
    }
    readonly property bool ownsRegistration: {
        if (!shell || !manifest || !pluginRegistry || disposed || retired) return false
        var revision = pluginRegistry.registryRevision
        return manifest.id === pluginId && !!pluginRegistry.installedPlugins[pluginId]
            && pluginRegistry.isEnabled(pluginId) && !shell.pluginReloading && currentService === root
    }
    // The lock service is an authentication service, so hosts that scope plugin
    // APIs never hand it to a third party and there is nothing to consult. The
    // compositor is the real boundary either way: ext-session-lock keeps every
    // other surface off screen while locked, and Hyprland's failsafe covers a
    // lock this shell did not take. An absent provider therefore means "nothing
    // to gate", not "stay hidden" — but a reachable one still decides.
    readonly property bool lockReady: !lockService
        || (lockService.locked === false
            && lockService.strandedLockResolved === true && lockService.strandedLock === false)
    readonly property bool panelAllowed: ownsRegistration && lockReady
    readonly property bool uiAllowed: panelAllowed && gateAcknowledged && connected
    readonly property int sourceCount: endpoints.length
    readonly property string statusText: !lockReady ? "lock-unavailable" : diagnostic || (connected ? "" : "connecting")
    readonly property bool helperRunning: helper.running
    readonly property var helperPid: helper.processId
    property var endpoints: []
    property var selectionState: SourceState.initial()
    readonly property var selectedEndpoint: connected ? SourceState.find(endpoints, selectionState.selected) : null
    readonly property string selectionMode: selectionState.mode
    readonly property bool pinUnavailable: selectionMode === "pinned" && !selectedEndpoint
    readonly property string selectedLabel: pinUnavailable ? selectionState.pinnedLabel : SourceState.label(selectedEndpoint)
    property double positionSeconds: 0
    property string progressSequence: ""
    property int selectionRevision: 0
    property string selectedIdentity: ""
    property bool viewVisible: false
    property bool viewExpanded: false
    // Hosts that scope their registry away from third-party plugins (Omarchy
    // since 2026-09) offer no shellConfigProvider/Mutator. They hand the plugin
    // a public copy of the bar config instead and write through
    // updateEntryInline, which stores settings flat on the bar entry and
    // replaces every key it is given. Both shapes are read here.
    readonly property var settings: {
        var revision = pluginRegistry ? pluginRegistry.registryRevision : 0
        var config = pluginRegistry && typeof pluginRegistry.shellConfigProvider === "function"
            ? pluginRegistry.shellConfigProvider()
            : shell && shell.barConfig ? ({ bar: shell.barConfig }) : null
        return Object.assign(entrySettings(configurationEntry(config)), settingsWritten)
    }
    // The scoped host refreshes its public bar config copy only when the plugin
    // set changes, not when a setting is written, so a write would otherwise
    // read back stale until the next plugin event. What this instance wrote is
    // layered on top, and dropped as soon as the host delivers a fresh copy.
    property var settingsWritten: ({})
    Connections {
        target: root.shell && "barConfig" in root.shell ? root.shell : null
        ignoreUnknownSignals: true
        function onBarConfigChanged() { root.settingsWritten = ({}) }
    }
    function entrySettings(entry) {
        if (!entry) return ({})
        var flat = {}
        for (var key in entry)
            if (key !== "id" && key !== "settings") flat[key] = entry[key]
        return Object.assign(flat, Protocol.object(entry.settings) ? entry.settings : {})
    }
    readonly property bool autoShow: settings.autoShow !== false
    readonly property bool island: settings.island !== false
    readonly property bool hud: settings.hud === true
    // On by default: at spectrumFps lines a second the live bars fit the
    // collapsed-playing budget.
    readonly property bool visualizer: settings.visualizer !== false
    readonly property bool peek: settings.peek === true
    readonly property bool tint: settings.tint !== false
    readonly property bool power: settings.power !== false
    readonly property bool lyrics: settings.lyrics === true
    readonly property bool showCalendar: fileSettings.showCalendar === true
    readonly property var calendarSource: calendarLoader.item
    signal calendarFrame(var frame)
    // Written by Panel.qml while the pointer is over the island, read by the bar
    // widget, which alone holds the bar API that suppresses the centre peek.
    property bool islandPointerActive: false
    // The name of the screen the island currently lives on, written by
    // Panel.qml. Each screen's BarWidget compares this against its own
    // screen so only the bar under the island suppresses its centre-hover
    // peek (code review L7).
    property string islandScreenName: ""
    // Written by Panel.qml: true only while the island itself, not the legacy
    // panel, is on screen. viewVisible alone cannot say this, because it also
    // mirrors the legacy panel when the island falls back to it.
    property bool islandShowing: false
    // Written by Panel.qml: its HudModel's suppression (fullscreen, or open
    // with showOpenNotchHud off and no closed island elsewhere), when the
    // island is on screen but draws no readout.
    property bool hudSuppressed: false
    // Panel's held HUD kind. The model ignores every other kind while its bar
    // is dragged, so keys of those kinds need Omarchy's OSD instead.
    property string hudHeldKind: ""
    // True while the island that draws the spectrum is open, so its lines
    // are not drawn. With one island this is viewExpanded; with one on every
    // screen Panel sets it from the drawing island alone, since another
    // island being open must not freeze a closed one's bars.
    property bool spectrumPaused: viewExpanded
    // The shelf: typed items from qml/Shelf.js (files, links, text), in
    // memory, and on disk only while the opt-in shelfPersist setting is on.
    // Cleared from memory on dispose and retirement, not in stopOwned(): that
    // also runs when the helper restarts, and a reconnect must not throw away
    // what the user shelved.
    property var shelfEntries: []
    property int shelfNextId: 1
    // The shelved file URIs in order: the view of the legacy grid and the
    // uri-list clipboard.
    readonly property var shelfItems: Shelf.fileUris(shelfEntries)
    // Screen name -> the empty bar centre width the spacer BarWidget measured
    // there, or -1 when it could not; Panel sizes the drag catch zone by it.
    property var barCentreSpans: ({})
    function noteBarCentreSpan(screenName, span) {
        var key = String(screenName || "")
        if (barCentreSpans[key] === span) return
        var next = Object.assign({}, barCentreSpans)
        next[key] = span
        barCentreSpans = next
    }
    // What already holds the suggested summon chord, read-only from
    // `hyprctl binds -j` when the welcome or Shortcuts shows the snippet; ""
    // when it is free or unknown.
    property string summonConflict: ""
    function checkSummonBinding() {
        if (!summonBindsProcess.running) summonBindsProcess.running = true
    }
    Process {
        id: summonBindsProcess
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.summonConflict = Strings.summonConflict(text)
        }
    }
    // Screens whose island spacer is away from the bar's middle: the widget
    // is not the bar's centre anchor, so the notch sits over the wrong place.
    property var barOffCentre: ({})
    readonly property bool islandOffCentre: Object.keys(barOffCentre).some(key => barOffCentre[key] === true)
    function noteBarPlacement(screenName, offCentre) {
        var key = String(screenName || "")
        if (barOffCentre[key] === (offCentre === true)) return
        var next = Object.assign({}, barOffCentre)
        next[key] = offCentre === true
        barOffCentre = next
    }
    property string shelfNotice: ""
    signal hudEvent(string kind, real level, bool muted)
    // The source owns discovery, sysfs and brightnessctl. Display backlight
    // change events come from the helper's udev monitor, which watches only
    // while the source is active; the monitor runs once the helper confirms.
    readonly property string backlightDevice: brightnessSourceLoader.item ? brightnessSourceLoader.item.backlightDevice : ""
    readonly property bool backlightWatchWanted: !!brightnessSourceLoader.item && brightnessSourceLoader.item.active === true
    property bool backlightWatching: false
    property string backlightWatchKey: ""
    property string backlightWatchRequest: ""
    readonly property bool brightnessMonitorRunning: backlightWatchWanted && backlightWatching
    property string backlightSysRoot: "/sys"
    property string brightnessctlBinary: "brightnessctl"
    function onBacklightChanged(device) { if (brightnessSourceLoader.item) brightnessSourceLoader.item.onBacklightChanged(device) }
    function syncBacklightWatch() {
        if (!connected || !connectionGeneration || stopping) {
            backlightWatchKey = ""
            backlightWatching = false
            return
        }
        var key = connectionGeneration + ":" + backlightWatchWanted
        if (key === backlightWatchKey) return
        backlightWatchKey = key
        backlightWatching = false
        backlightWatchRequest = String(++requestCounter)
        if (!send("backlightWatch", { requestId: backlightWatchRequest, enabled: backlightWatchWanted })) backlightWatchKey = ""
    }
    onBacklightWatchWantedChanged: Qt.callLater(syncBacklightWatch)
    function keyboardBacklightChanged() { return !!brightnessSourceLoader.item && brightnessSourceLoader.item.keyboardChanged() }
    // Whether the island will draw the readout for a media key the installed
    // bindings are about to act on. Anything else sends the key to Omarchy's
    // own command and OSD, so exactly one readout appears. Brightness needs
    // the backlight the key moves to be the one the island watches.
    function hudReadout(kind, device) {
        if (!hud || !island || !islandShowing || hudSuppressed || !panelAllowed || retired || disposed) return false
        if (hudHeldKind !== "" && kind !== hudHeldKind) return false
        if (kind === "volume" || kind === "mic") return true
        var source = brightnessSourceLoader.item
        if (!source || !source.active) return false
        if (kind === "keyboard") return source.keyboardDevice !== ""
        if (kind === "brightness")
            return root.brightnessMonitorRunning && source.backlightDevice !== "" && device === source.backlightDevice
        return false
    }
    function setBrightnessLevel(kind, level) {
        if (!brightnessSourceLoader.item) return false
        brightnessSourceLoader.item.brightnessctlBinary = root.brightnessctlBinary
        return brightnessSourceLoader.item.setLevel(kind, level)
    }
    // Clipboard round-trip for the file shelf. Missing binaries or an empty
    // clipboard never disable Paste/Copy; they report the reason in shelfNotice
    // instead (hard constraint 7). The binary names are overridable only by
    // the lifecycle harness: QProcess resolves the executable using this
    // process's own PATH regardless of the child's configured environment, so
    // a fake binary name is the only deterministic way to prove the
    // missing-binary path without depending on (or corrupting) the host's PATH.
    property string clipboardPasteBinary: "wl-paste"
    property string clipboardCopyBinary: "wl-copy"
    // Ctrl+V reads the clipboard's file links first. When it offers no
    // text/uri-list, its plain text is shelved the way a drop's text is: a
    // single web URL becomes a link, a local file URI a file, and other
    // text a text item (Shelf.fromText).
    property string clipboardPasteType: "text/uri-list"
    property bool clipboardPasteFallback: false
    function shelfPaste() {
        if (clipboardPaste.running || clipboardPasteFallback || clipboardCopy.running) { shelfNotice = "clipboard-busy"; return }
        startClipboardPaste("text/uri-list")
    }
    function startClipboardPaste(type) {
        clipboardPasteFallback = false
        clipboardPasteBuffer = ""
        clipboardPasteTruncated = false
        clipboardPasteStarted = false
        clipboardPasteExited = false
        clipboardPasteType = type
        clipboardPaste.command = [clipboardPasteBinary, "--no-newline", "--type", type]
        clipboardPaste.running = true
    }
    function shelfCopy(uri) {
        if (clipboardPaste.running || clipboardCopy.running) { shelfNotice = "clipboard-busy"; return }
        // Only a URI already on the shelf may ever reach the clipboard: this
        // is the one guard shelfCopy owns itself, rather than trusting every
        // caller to only ever pass a shelved item (code review M7).
        var normalized = Shelf.normalize(uri)
        if (!normalized || shelfItems.indexOf(normalized) < 0) return
        startClipboardCopy(Shelf.toUriList([normalized]), "text/uri-list")
    }
    // Copies shelved items by id: files as a uri-list, links and text as
    // plain text. Only item content ever reaches the clipboard.
    function shelfCopyItems(ids) {
        var files = [], texts = []
        for (var i = 0; i < ids.length; ++i) {
            var item = Shelf.findItem(shelfEntries, ids[i])
            if (!item) continue
            if (item.kind === "file") files.push(item.uri)
            else texts.push(item.kind === "link" ? item.url : item.text)
        }
        if (files.length) return startClipboardCopy(Shelf.toUriList(files), "text/uri-list")
        return texts.length ? startClipboardCopy(texts.join("\n"), "text/plain") : false
    }
    function shelfCopyItem(id) {
        return shelfCopyItems([id])
    }
    // Copy Path: the local paths of shelved files, one per line.
    function shelfCopyText(text) {
        return startClipboardCopy(String(text), "text/plain")
    }
    function startClipboardCopy(payload, type) {
        if (clipboardPaste.running || clipboardCopy.running) { shelfNotice = "clipboard-busy"; return false }
        clipboardCopyStarted = false
        clipboardCopyExited = false
        clipboardCopyPayload = payload
        clipboardCopy.command = [clipboardCopyBinary, "--type", type]
        clipboardCopy.running = true
        return true
    }
    property string clipboardPasteBuffer: ""
    property bool clipboardPasteTruncated: false
    property bool clipboardPasteStarted: false
    property bool clipboardPasteExited: false
    // Sent on stdin rather than as an argv element (see the clipboardCopy
    // Process below), so a shelved path never lingers readable in
    // `/proc/<pid>/cmdline` for as long as wl-copy keeps serving the
    // selection (code review M7).
    property string clipboardCopyPayload: ""
    property bool clipboardCopyStarted: false
    property bool clipboardCopyExited: false
    // Reduced motion is the person's own switch, or, while followDesktopMotion
    // is on (the default), Hyprland running without animations. The desktop
    // is asked at start and whenever Hyprland reloads its config.
    property bool desktopReducedMotion: false
    property bool reducedMotion: settings.reducedMotion === true
        || (fileSettings.followDesktopMotion !== false && desktopReducedMotion)
    function checkDesktopMotion() {
        if (!desktopMotionProcess.running) desktopMotionProcess.running = true
    }
    Process {
        id: desktopMotionProcess
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.desktopReducedMotion = Motion.desktopReducesMotion(text)
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") root.checkDesktopMotion() }
    }
    property bool highContrast: settings.highContrast === true
    readonly property bool remoteArtwork: settings.remoteArtwork === true
    property bool lightTheme: Qt.styleHints.colorScheme === Qt.Light
    property string actionError: ""
    // Absolute epoch-ms deadline, 0 when disarmed. Stored absolute rather than
    // as elapsed time because a QML Timer counts monotonically: after a suspend
    // an elapsed-time timer and a wall-clock label disagree.
    property double sleepDeadline: 0
    property var sleepTarget: null
    property string sleepFailure: ""
    property bool sleepRetried: false
    // Arming follows ordinary admission, so a reachable lock provider that
    // reports a lock still blocks and cancels it. Hosts that scope the lock
    // service away from third parties leave no signal to consult; arming is
    // allowed there anyway because the only thing this can ever send is Pause,
    // and pausing on a locked session is harmless. sleepLockVerified lets the
    // UI say which case applies instead of promising a cancellation it cannot see.
    readonly property bool sleepArmable: uiAllowed && !!selectedEndpoint
        && !!selectedEndpoint.capabilities && selectedEndpoint.capabilities.CanPause === true
    readonly property bool sleepLockVerified: !!lockService
    readonly property string pendingAction: {
        for (var id in pendingRequests) {
            if (selectedEndpoint && SourceState.same(pendingRequests[id].endpointToken, selectedEndpoint.token))
                return pendingRequests[id].action || ""
        }
        return ""
    }
    property string subscriptionKey: ""
    property string artworkSelectionKey: ""
    property string artworkPolicyKey: ""
    property string diagnostic: ""
    property bool connected: false
    property bool calendarSupported: false
    property bool gateAcknowledged: false
    property string connectionGeneration: ""
    property string admissionEpoch: ""
    property var pendingRequests: ({})
    property var outstandingBytes: ({})
    property int outputBudget: 0
    property bool disposed: false
    property bool retired: false
    property bool admittedOnce: false
    property bool stopping: false
    property bool failedPermanently: false
    property bool desiredGate: false
    property double epochCounter: 0
    property double requestCounter: 0
    property double retryWindow: 0
    property int retryCount: 0
    property var receiverState: Protocol.receiver()
    // Milliseconds of pending work: advanced by deadlineTicker alone, never
    // by the wall clock (see Protocol.expiredRequest).
    property double deadlineClock: 0
    property var stallWindow: ({ started: 0, count: 0 })
    property int restartDelay: 0
    signal commandFinished(string requestId, string status)
    signal helperExited(int exitCode)

    function reconcile() {
        if (!ownsRegistration) {
            if (admittedOnce && currentService !== root) Qt.callLater(retireSuperseded)
            stopOwned()
            return
        }
        if (!admittedOnce) {
            // The host captures a manifest before asynchronous construction. A
            // replaced manifest proves this initial registration came from an
            // old scan. Compare __registryRevision (a plain number the host
            // stamps once per raw manifest), not object identity: QML's
            // property system does not reliably preserve plain-JS-object
            // identity for a `property var` value read back through the
            // host's scoped registry facade.
            var registryManifest = pluginRegistry.installedPlugins[pluginId]
            if (!registryManifest || registryManifest.__registryRevision !== manifest.__registryRevision) {
                diagnostic = "stale-host-load"
                failedPermanently = true
                stopOwned()
                return
            }
            admittedOnce = true
        }
        if (!lockReady) closeGate()
        Qt.callLater(activate)
    }
    function retireSuperseded() {
        if (admittedOnce && currentService !== root) retired = true
    }
    function activate() {
        if (!ownsRegistration || disposed || failedPermanently || stopping) return
        if (!helper.running && !retry.running) startHelper()
        if (connected && lockReady && !desiredGate) setGate(true)
    }
    function startHelper() {
        if (!ownsRegistration || helper.running || disposed || stopping || failedPermanently) return
        receiverState = Protocol.receiver()
        connectionGeneration = ""
        connected = false
        calendarSupported = false
        gateAcknowledged = false
        desiredGate = false
        outstandingBytes = ({})
        outputBudget = 0
        helper.stdinEnabled = true
        helper.command = [helperPath]
        helper.running = true
        handshake.restart()
    }
    function send(type, fields) {
        if (!helper.running || !connectionGeneration || stopping) return false
        var frame = fields || {}
        frame.type = type
        frame.protocolVersion = 1
        frame.connectionGeneration = connectionGeneration
        var line = Protocol.encode(frame)
        if (line.length > Protocol.frameLimit) return false
        if (outputBudget + line.length > 131072) { protocolError("output-backpressure"); return false }
        var key = type === "controlGate" ? "gate:" + fields.admissionEpoch
            : (type === "command" ? "command:" : "request:") + fields.requestId
        outstandingBytes[key] = { bytes: line.length, epoch: admissionEpoch }
        outputBudget += line.length
        helper.write(line)
        return true
    }
    function cancelRequests() { pendingRequests = ({}); scheduleDeadlines() }
    function releaseCredit(key) {
        if (!outstandingBytes[key]) return
        outputBudget -= outstandingBytes[key].bytes
        delete outstandingBytes[key]
    }
    // Ticks only while a snapshot is staged or a request is pending, so a
    // settled service arms no recurring timer.
    function scheduleDeadlines() {
        deadlineTicker.running = !!receiverState.staging || Object.keys(pendingRequests).length > 0
    }
    function tickDeadlines() {
        deadlineClock += deadlineTicker.interval
        Protocol.expire(receiverState, deadlineClock, receive)
        if (stopping || disposed) return
        var id = Protocol.expiredRequest(pendingRequests, deadlineClock)
        if (id) {
            commandFinished(id, "timeout")
            // Unknown consumption cannot safely release byte credits; a
            // restart resets them.
            recoverFromStall("command-timeout")
            return
        }
        scheduleDeadlines()
    }
    // A helper that stops answering is restarted with backoff; only repeated
    // stalls end in the permanent failure that needs a manual retry.
    function recoverFromStall(code) {
        var delay = Protocol.stallRecovery(stallWindow, Date.now())
        if (delay < 0) { protocolError(code); return }
        diagnostic = code
        var running = helper.running
        restartDelay = running ? delay : 0
        stopOwned()
        if (!running) { retry.interval = delay; retry.start() }
    }
    function retryConnection() {
        if (!ownsRegistration || !admittedOnce || helper.running || stopping || diagnostic === "stale-host-load") return false
        failedPermanently = false
        diagnostic = ""
        Qt.callLater(activate)
        return true
    }
    function setGate(enabled) {
        gateAcknowledged = false
        desiredGate = enabled
        admissionEpoch = String(++epochCounter)
        cancelRequests()
        if (connected && send("controlGate", { admissionEpoch: admissionEpoch, enabled: enabled })) gateDeadline.restart()
    }
    function closeGate() {
        gateAcknowledged = false
        cancelRequests()
        if (desiredGate) setGate(false)
    }
    function stopOwned() {
        closeGate()
        // One hook instead of an enumerated event list. This funnel covers lock,
        // helper exit, protocol error, retirement, supersession and disposal -
        // an armed timer must not outlive the instance that armed it.
        cancelSleepTimer()
        retry.stop()
        handshake.stop()
        gateDeadline.stop()
        deadlineTicker.stop()
        connected = false
        calendarSupported = false
        endpoints = []
        // The stopped helper will never answer its thumbnail requests.
        shelfThumbnailHelperLost()
        receiverState = Protocol.receiver()
        if (helper.running && !stopping) {
            stopping = true
            helper.stdinEnabled = false
            terminateDelay.restart()
        }
    }
    function protocolError(code) {
        diagnostic = code
        failedPermanently = true
        stopOwned()
    }
    function receive(event) {
        if (!ownsRegistration || stopping || disposed) return
        var isRequestResponse = event.type === "requestAck" || event.type === "calendarResult"
            || event.type === "calendarWindowResult"
        if (event.type === "requestAck" && event.requestId === watchRequestId)
            watchStatus = event.status === "invalid" ? "invalid" : "ok"
        var key = event.type === "controlGateAck" ? "gate:" + event.admissionEpoch
            : (isRequestResponse ? "request:" : "command:") + event.requestId
        releaseCredit(key)
        if (event.type === "error") { protocolError(event.code); return }
        if (event.type === "hello") {
            connectionGeneration = event.connectionGeneration
            connected = true
            calendarSupported = event.calendarSupported === true
            handshake.stop()
            diagnostic = ""
            Qt.callLater(activate)
        } else if (event.type === "controlGateAck") {
            // This ordered stdin barrier proves earlier requests were consumed,
            // including commands whose stale results the helper deliberately drops.
            if (event.enabled === false) {
                for (var credit in outstandingBytes) {
                    if (credit.indexOf("command:") === 0 && Number(outstandingBytes[credit].epoch) < Number(event.admissionEpoch))
                        releaseCredit(credit)
                }
            }
            if (event.admissionEpoch === admissionEpoch && event.enabled === desiredGate) {
                gateDeadline.stop()
                gateAcknowledged = event.enabled === true && ownsRegistration && lockReady
            }
        } else if (event.type === "snapshot") {
            endpoints = event.endpoints
        } else if (event.type === "progress") {
            if (uiAllowed && viewVisible && (viewExpanded || islandShowing) && selectedEndpoint
                && SourceState.same(event.endpointToken, selectedEndpoint.token)
                && SourceState.sameTrack(event.trackToken, selectedEndpoint.trackToken)
                && Protocol.counter(event.sequence) && Protocol.newer(event.sequence, progressSequence)
                && typeof event.positionSeconds === "number" && isFinite(event.positionSeconds)) {
                progressSequence = event.sequence
                positionSeconds = Math.max(0, selectedEndpoint.lengthSeconds > 0
                    ? Math.min(event.positionSeconds, selectedEndpoint.lengthSeconds) : event.positionSeconds)
            }
        } else if (event.type === "requestAck") {
            if (event.requestId === backlightWatchRequest)
                backlightWatching = backlightWatchWanted && event.status === "ok"
        } else if (event.type === "backlightChanged") {
            if (typeof event.device === "string") onBacklightChanged(event.device)
        } else if (event.type === "snapshotDiscarded") {
            diagnostic = event.code
        } else if (event.type === "thumbnailResult") {
            receiveThumbnail(event)
        } else if (event.type === "systemEvent") {
            systemEvent(event)
        } else if (event.type === "calendarResult" || event.type === "calendarWindowResult" || event.type === "calendarChanged") {
            if (event.type !== "calendarResult" || !finishCalendarClear(event)) calendarFrame(event)
        } else if (event.type === "result") {
            var pending = pendingRequests[event.requestId]
            if (!pending || !uiAllowed || pending.epoch !== admissionEpoch) return
            var next = Object.assign({}, pendingRequests)
            delete next[event.requestId]
            pendingRequests = next
            scheduleDeadlines()
            // The error line describes the user's own last command. A result for
            // an IPC-dispatched command never writes it, or any local process
            // could make the user's presses appear to fail.
            if (!pending.external && selectedEndpoint && SourceState.same(pending.endpointToken, selectedEndpoint.token)
                && pending.revision === selectionRevision) actionError = event.status === "success" ? "" : String(event.status)
            commandFinished(event.requestId, String(event.status))
        }
    }
    function command(endpointToken, action, trackToken, value) {
        if (!uiAllowed || !Protocol.validTransportValue(action, value)
            || Object.keys(pendingRequests).length >= 16) return ""
        var id = String(++requestCounter)
        var fields = { requestId: id, admissionEpoch: admissionEpoch,
            endpointToken: endpointToken, action: action }
        if (trackToken !== undefined) fields.trackToken = trackToken
        if (value !== undefined) fields.value = value
        if (!send("command", fields)) return ""
        var next = Object.assign({}, pendingRequests)
        next[id] = { epoch: admissionEpoch, deadline: deadlineClock + 4000,
            endpointToken: endpointToken, action: action, value: value, revision: selectionRevision }
        pendingRequests = next
        scheduleDeadlines()
        return id
    }
    function selectSource(token) {
        var endpoint = SourceState.find(endpoints, token)
        if (!endpoint) return false
        selectionState = SourceState.pin(selectionState, endpoint)
        selectionRevision++
        actionError = ""
        return true
    }
    function selectAuto() {
        selectionState = SourceState.auto(selectionState, endpoints)
        selectionRevision++
        actionError = ""
    }
    // The remembered player: an app identity in the settings file that Auto
    // follows whenever that app is present, across restarts. The welcome's
    // Media step sets it; a null token forgets it. Either way the selection
    // returns to Auto.
    readonly property string preferredSource: fileSettings.preferredSource || ""
    onPreferredSourceChanged: {
        selectionState = SourceState.prefer(selectionState, preferredSource, endpoints)
        selectionRevision++
    }
    function rememberSource(token) {
        var endpoint = token ? SourceState.find(endpoints, token) : null
        if (token && !endpoint) return false
        var identity = endpoint ? SourceState.appIdentity(endpoint) : ""
        if (token && !identity) return false
        if (identity !== preferredSource && !configure({ preferredSource: identity })) return false
        selectionState = SourceState.prefer(SourceState.auto(selectionState, endpoints), identity, endpoints)
        selectionRevision++
        actionError = ""
        return true
    }
    function armSleepTimer(minutes) {
        if (!sleepArmable) return "unavailable"
        var span = Number(minutes)
        if (!isFinite(span) || span <= 0 || span > 720) return "invalid-value"
        // start() on a running Timer is a no-op, so a re-arm would silently keep
        // the first deadline while the label showed the second.
        sleepTimer.stop()
        sleepFailure = ""
        sleepRetried = false
        sleepTarget = selectedEndpoint.token
        sleepDeadline = Date.now() + span * 60000
        sleepTimer.interval = Math.max(1, sleepDeadline - Date.now())
        sleepTimer.restart()
        return "ok"
    }
    function cancelSleepTimer() {
        sleepTimer.stop()
        sleepFailure = ""
        sleepDeadline = 0
        sleepTarget = null
        sleepRetried = false
    }
    function fireSleepTimer() {
        var remaining = sleepDeadline - Date.now()
        if (sleepDeadline > 0 && remaining > 1) {
            // Woke early, or the deadline moved: reschedule rather than pausing.
            sleepTimer.interval = remaining
            sleepTimer.restart()
            return
        }
        var armed = sleepTarget
        var retried = sleepRetried
        cancelSleepTimer()
        if (!armed) return
        // A fresh intent, not one stored across the wait: the selection revision
        // and the admission epoch both rotate over minutes, so a stored intent
        // would be refused and the pause would never happen.
        var intent = captureIntent()
        if (!intent || !SourceState.same(intent.endpointToken, armed)
            || !selectedEndpoint || !selectedEndpoint.capabilities
            || selectedEndpoint.capabilities.CanPause !== true) {
            sleepFailure = "source-changed"
            return
        }
        if (pendingAction) {
            // One bounded re-fire rather than a silent loss: the single-shot is
            // already consumed and a user command happens to be in flight.
            if (retried) { sleepFailure = "busy"; return }
            sleepRetried = true
            sleepTarget = armed
            sleepDeadline = Date.now() + 2000
            sleepTimer.interval = 2000
            sleepTimer.restart()
            return
        }
        if (!invoke("Pause", intent)) sleepFailure = "refused"
    }
    // Transport verbs for local callers pass their actions as literals. Returns bounded
    // codes and never metadata: "ok" means dispatched, not that playback
    // changed. It calls command() rather than invoke() because invoke() writes
    // the user's error line, and capture and dispatch happen in one step, so
    // there is no stale intent to validate.
    function dispatchExternal(action, capable, value) {
        if (!uiAllowed || !selectedEndpoint || !selectedEndpoint.capabilities
            || selectedEndpoint.capabilities.CanControl !== true || !capable(selectedEndpoint.capabilities))
            return "unavailable"
        if (pendingAction) return "busy"
        var intent = captureIntent()
        if (!intent) return "unavailable"
        var id = command(intent.endpointToken, action, intent.trackToken, value)
        if (!id) return "busy"
        var next = Object.assign({}, pendingRequests)
        next[id] = Object.assign({}, next[id], { external: true })
        pendingRequests = next
        return "ok"
    }
    function externalPlayPause() {
        return dispatchExternal("PlayPause", function(c) { return c.CanPlay === true || c.CanPause === true })
    }
    function externalNext() {
        return dispatchExternal("Next", function(c) { return c.CanGoNext === true })
    }
    function externalPrevious() {
        return dispatchExternal("Previous", function(c) { return c.CanGoPrevious === true })
    }
    function externalShuffle() {
        if (!selectedEndpoint || typeof selectedEndpoint.shuffle !== "boolean") return "unavailable"
        return dispatchExternal("SetShuffle", function(c) { return c.CanShuffle === true },
            !selectedEndpoint.shuffle)
    }
    function externalRepeat() {
        var next = selectedEndpoint ? Protocol.nextLoopStatus(selectedEndpoint.loopStatus) : null
        if (next === null) return "unavailable"
        return dispatchExternal("SetLoopStatus", function(c) { return c.CanLoop === true }, next)
    }
    function externalSeek(seconds) {
        if (!Protocol.validSeekOffset(seconds)) return "unavailable"
        return dispatchExternal("Seek", function(c) { return c.CanSeek === true }, seconds)
    }
    function captureIntent() {
        if (!uiAllowed || !selectedEndpoint) return null
        return { endpointToken: selectedEndpoint.token, trackToken: selectedEndpoint.trackToken,
            connection: connectionGeneration, epoch: admissionEpoch, revision: selectionRevision }
    }
    function invoke(action, intent, value) {
        if (!intent || !uiAllowed || intent.connection !== connectionGeneration || intent.epoch !== admissionEpoch
            || intent.revision !== selectionRevision || !selectedEndpoint
            || !SourceState.same(intent.endpointToken, selectedEndpoint.token)) {
            actionError = "target-gone"; return ""
        }
        if (action === "SetPosition" && !SourceState.sameTrack(intent.trackToken, selectedEndpoint.trackToken)) {
            actionError = "stale-track"; return ""
        }
        if (pendingAction) { actionError = "busy"; return "" }
        if (!Protocol.validTransportValue(action, value)) { actionError = "invalid-value"; return "" }
        actionError = ""
        return command(intent.endpointToken, action, intent.trackToken, value)
    }
    function subscribeView() {
        if (!connected || !connectionGeneration || stopping) { subscriptionKey = ""; return }
        // The collapsed island shows a progress hairline, so it subscribes too,
        // at 1 Hz: a 240 px line over a whole track moves about a pixel a
        // second. The legacy panel still subscribes only while expanded.
        var active = uiAllowed && viewVisible && (viewExpanded || islandShowing)
            && selectedEndpoint && selectedEndpoint.status === "Playing"
        var cadence = viewExpanded ? 250 : 1000
        var token = active ? selectedEndpoint.token : ({})
        var key = connectionGeneration + ":" + admissionEpoch + ":"
            + (active ? SourceState.key(token) + ":" + cadence : "hidden")
        if (key === subscriptionKey) return
        subscriptionKey = key
        send("subscribe", { requestId: String(++requestCounter), admissionEpoch: admissionEpoch,
            endpointToken: token, visible: !!active, cadenceMs: cadence })
    }
    function selectArtwork() {
        if (!connected || !connectionGeneration || stopping) {
            artworkSelectionKey = ""; artworkPolicyKey = ""; return
        }
        var policy = connectionGeneration + ":" + remoteArtwork
        if (policy !== artworkPolicyKey) {
            artworkPolicyKey = policy
            send("artworkPolicy", { requestId: String(++requestCounter), enabled: remoteArtwork })
        }
        // remoteArtwork is the helper's consent for network fetches only: a
        // player's local cover file loads without it, so selection does not
        // wait on it.
        var active = uiAllowed && viewVisible && selectedEndpoint
        var key = connectionGeneration + ":" + admissionEpoch + ":"
            + (active ? JSON.stringify(selectedEndpoint.trackToken) : "hidden")
        if (key === artworkSelectionKey) return
        artworkSelectionKey = key
        send("artworkSelect", { requestId: String(++requestCounter), admissionEpoch: admissionEpoch,
            endpointToken: active ? selectedEndpoint.token : ({}), visible: !!active })
    }
    // Local desktop signals from the helper (SystemWatch): who holds a
    // camera, a screen recording, new screenshots and changed reminders.
    // Each watch runs only while its feature is on and the island is
    // allowed on screen; turning a watch off clears what it reported.
    property var cameraHolders: []
    property var recordingState: ({ active: false, startedAt: 0, path: "" })
    property bool remindersUnavailable: false
    // "ok", or "invalid" when the helper refused the last watch request
    // (a screenshot folder that does not exist).
    property string watchStatus: "ok"
    property string watchKey: ""
    property string watchRequestId: ""
    signal screenshotSaved(string path)
    signal recordingSaved(string path)
    signal remindersChanged()
    readonly property bool watchesAllowed: uiAllowed && island
    readonly property var watchWanted: ({
        cameraDevices: watchesAllowed && fileSettings.privacyIndicators === true,
        // The recording watch wakes on every change in /tmp, so only the
        // activity runs it; shelving recordings rides on it.
        recording: watchesAllowed && fileSettings.recordingActivity === true,
        reminders: watchesAllowed && fileSettings.timers === true,
        screenshots: watchesAllowed && fileSettings.screenshotsToShelf === true,
        screenshotDir: String(fileSettings.screenshotDir || "")
    })
    function syncWatch() {
        var wanted = watchWanted
        if (!wanted.cameraDevices) cameraHolders = []
        if (!wanted.recording) recordingState = { active: false, startedAt: 0, path: "" }
        if (!connected || !connectionGeneration || stopping) { watchKey = ""; return }
        var key = connectionGeneration + ":" + JSON.stringify(wanted)
        if (key === watchKey) return
        watchKey = key
        watchRequestId = String(++requestCounter)
        send("watch", Object.assign({ requestId: watchRequestId }, wanted))
    }
    onWatchWantedChanged: Qt.callLater(syncWatch)
    // Omarchy's screen recording: stop it from the island, and, opt-in,
    // shelve the saved file (the shelf may persist, so it is off by default).
    readonly property bool recordingShown: island && fileSettings.recordingActivity === true && recordingState.active === true
    signal captureShelved(string kind, string path)
    function stopRecording() {
        if (!watchesAllowed || recordingState.active !== true) return false
        systemActions.stopRecording()
        return true
    }
    function shelveCapture(kind, path) {
        if (!watchesAllowed || fileSettings.shelfEnabled === false) return false
        if (shelfAdd([Shelf.fileUrl(path)]) <= 0) return false
        captureShelved(kind, path)
        return true
    }
    onRecordingSaved: path => { if (fileSettings.recordingsToShelf === true) shelveCapture("recording", path) }
    onScreenshotSaved: path => shelveCapture("screenshot", path)
    function systemEvent(frame) {
        var event = Protocol.systemEvent(frame)
        if (!event) return
        if (event.kind === "camera") {
            if (watchWanted.cameraDevices) cameraHolders = event.holders
        } else if (event.kind === "recording") {
            if (!watchWanted.recording) return
            var was = recordingState.active === true
            recordingState = { active: event.active, startedAt: event.startedAt, path: event.path }
            if (was && !event.active && event.path !== "") recordingSaved(event.path)
        } else if (event.kind === "screenshot") {
            if (watchWanted.screenshots) screenshotSaved(event.path)
        } else if (event.kind === "reminders") {
            remindersUnavailable = event.unavailable
            if (watchWanted.reminders) remindersChanged()
        }
    }
    // Timers are Omarchy's reminders (systemd user timers made by
    // omarchy-reminder), so they outlive a shell restart, notify even with
    // the island off, and match the bar's Reminder indicator. The list is
    // read on start, after each change the island makes, when the helper sees
    // a reminder unit come or go, and once when the soonest is due; a timer
    // that leaves the list at its time finished, and one that leaves earlier
    // was cancelled.
    readonly property bool timersEnabled: island && fileSettings.timers === true
    property var timerList: []
    property bool timersAvailable: true
    property string timerBuffer: ""
    property bool timerReadAgain: false
    signal timerFinished(string label)
    function refreshTimers() {
        if (!timersEnabled || !ownsRegistration) { timerList = []; timerDue.stop(); return }
        if (timerRead.running) { timerReadAgain = true; return }
        timerBuffer = ""
        timerRead.running = true
    }
    function timersRead(exitCode) {
        timersAvailable = exitCode === 0
        var next = exitCode === 0 ? Timers.parse(timerBuffer) : []
        timerBuffer = ""
        var done = Timers.finished(timerList, next, Date.now())
        timerList = next
        for (var i = 0; i < done.length; ++i) timerFinished(done[i].label)
        timerDue.stop()
        if (next.length > 0) {
            timerDue.interval = Math.max(1000, next[0].at + 1000 - Date.now())
            timerDue.start()
        }
        if (timerReadAgain) { timerReadAgain = false; Qt.callLater(refreshTimers) }
    }
    // "ok", "invalid" (minutes outside 1..1440) or "unavailable".
    function startTimer(minutes, label) {
        if (!Timers.validMinutes(minutes)) return "invalid"
        if (!timersEnabled || !timersAvailable) return "unavailable"
        systemActions.startReminder(minutes, label)
        timerSettle.restart()
        return "ok"
    }
    // "ok", "invalid" (not a reminder unit), "unknown" (not in the list) or
    // "unavailable".
    function cancelTimer(unit) {
        if (!Timers.validUnit(unit)) return "invalid"
        if (!timersEnabled) return "unavailable"
        if (!Timers.known(timerList, unit)) return "unknown"
        systemActions.cancelReminder(unit)
        timerSettle.restart()
        return "ok"
    }
    onTimersEnabledChanged: refreshTimers()
    onRemindersChanged: refreshTimers()
    Process {
        id: timerRead
        command: ["omarchy-reminder", "show", "--json"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { if (root.timerBuffer.length < 65536) root.timerBuffer += data }
        }
        onExited: (exitCode, exitStatus) => root.timersRead(exitCode)
    }
    Timer { id: timerDue; repeat: false; onTriggered: root.refreshTimers() }
    SystemActions { id: systemActions }
    // What the closed island shows, for status(): its activity key and how
    // many apps capture each device. The Panel reports them; only counts are
    // kept here, so no app name ever reaches IPC.
    property string activityKey: ""
    property var privacyCounts: ({ mic: 0, camera: 0, screen: 0 })
    function reportActivity(key, privacy) {
        activityKey = String(key || "")
        function count(list) { return Array.isArray(list) ? list.length : 0 }
        privacyCounts = { mic: count(privacy && privacy.mic), camera: count(privacy && privacy.camera),
            screen: count(privacy && privacy.screen) }
    }
    function timerStatus() {
        return timerList.map(function (entry) { return { unit: entry.unit, label: entry.label, at: entry.at } })
    }
    // A change the island made shows up once systemd has it.
    Timer { id: timerSettle; interval: 400; repeat: false; onTriggered: root.refreshTimers() }
    function retainArtwork(paths) {
        if (!connected || !Array.isArray(paths) || paths.length > 2) return
        send("artworkRetain", { requestId: String(++requestCounter), paths: paths })
    }
    onEndpointsChanged: selectionState = SourceState.reconcile(selectionState, endpoints)
    onSelectedEndpointChanged: {
        var identity = selectedEndpoint ? SourceState.key(selectedEndpoint.token) : ""
        if (identity !== selectedIdentity) {
            selectedIdentity = identity
            selectionRevision++
            actionError = ""
        }
        positionSeconds = selectedEndpoint ? selectedEndpoint.positionSeconds || 0 : 0
        progressSequence = ""
        Qt.callLater(subscribeView)
        Qt.callLater(selectArtwork)
    }
    onUiAllowedChanged: {
        if (!uiAllowed) cancelSleepTimer()
        Qt.callLater(subscribeView); Qt.callLater(selectArtwork)
        Qt.callLater(offerOnboarding)
        Qt.callLater(syncWatch)
    }
    onViewVisibleChanged: { Qt.callLater(subscribeView); Qt.callLater(selectArtwork) }
    onViewExpandedChanged: Qt.callLater(subscribeView)
    // Lines are not drawn while paused, and a silent stretch sends no more
    // lines at all, so levels kept across a pause would come back frozen.
    // Flat bars until the next line instead.
    onSpectrumPausedChanged: if (spectrumPaused) spectrumLevels = []
    onIslandShowingChanged: Qt.callLater(subscribeView)
    onRemoteArtworkChanged: Qt.callLater(selectArtwork)
    function dispose() {
        disposed = true
        stopOwned()
        releaseIslandState()
    }
    function configurationEntry(config) {
        var entries = config && Array.isArray(config.plugins) ? config.plugins.slice() : []
        var layout = config && config.bar ? config.bar.layout : null
        for (var section of ["left", "center", "right"])
            if (layout && Array.isArray(layout[section])) entries = entries.concat(layout[section])
        for (var entry of entries)
            if (entry && entry.id === pluginId) return entry
        return null
    }
    readonly property int shelfLimit: Shelf.limitOf(fileSettings.shelfLimit)
    readonly property bool shelfPersist: fileSettings.shelfPersist === true
    // Adds candidates from Shelf.js (fromUri, fromText, fromDrop). Returns how
    // many were added; the notice says why anything was not.
    function shelfAddCandidates(candidates) {
        var result = Shelf.addItems(shelfEntries, Array.isArray(candidates) ? candidates : [],
            { limit: shelfLimit, nextId: shelfNextId })
        shelfNextId = result.nextId
        shelfEntries = result.items
        shelfNotice = result.full ? "shelf-full" : result.rejected ? "shelf-rejected" : ""
        if (result.added) {
            queueShelfMime(result.ids)
            saveShelf()
        }
        return result.added
    }
    // Dropped or pasted URIs: local files and http(s) links.
    function shelfAdd(uris) {
        var list = Array.isArray(uris) ? uris : []
        return shelfAddCandidates(list.map(function(uri) { return Shelf.fromUri(String(uri)) }))
    }
    // A whole drop: its URLs, or its text when it carries none.
    function shelfAddDrop(urls, text) {
        return shelfAddCandidates(Shelf.fromDrop(urls, text))
    }
    // Removes the item holding this file URI (the legacy grid's remove).
    function shelfRemove(uri) {
        var value = Shelf.normalize(uri)
        for (var i = 0; i < shelfEntries.length; ++i)
            if (shelfEntries[i].kind === "file" && shelfEntries[i].uri === value) return shelfRemoveItem(shelfEntries[i].id)
        shelfNotice = ""
        return false
    }
    function shelfRemoveItem(id) {
        var item = Shelf.findItem(shelfEntries, id)
        if (!item) return false
        shelfEntries = Shelf.removeItem(shelfEntries, id)
        forgetShelfItems([item])
        shelfNotice = ""
        saveShelf()
        return true
    }
    function shelfClear() {
        var removed = shelfEntries
        shelfEntries = []
        forgetShelfItems(removed)
        shelfNotice = ""
        saveShelf()
    }
    // Drops the per-item caches and deletes the files the shelf created.
    function forgetShelfItems(items, unloading) {
        forgetShelfIds(items.map(function(item) { return item.id }))
        for (var i = 0; i < items.length; ++i)
            if (items[i].temp)
                shelfActions.execute(shelfActions.removeTempCommand(shelfTempDir, Shelf.localPath(items[i].uri), unloading === true))
    }
    function forgetShelfIds(ids) {
        var thumbnails = Object.assign({}, shelfThumbnails), mimes = Object.assign({}, shelfMimes)
        var misses = Object.assign({}, shelfThumbnailMisses), busy = Object.assign({}, shelfThumbnailBusy)
        for (var i = 0; i < ids.length; ++i) {
            delete thumbnails[ids[i]]
            delete mimes[ids[i]]
            delete misses[ids[i]]
            delete busy[ids[i]]
        }
        shelfThumbnails = thumbnails
        shelfMimes = mimes
        shelfThumbnailMisses = misses
        shelfThumbnailBusy = busy
        dropShelfThumbnailRequests(ids)
    }
    function releaseIslandState() {
        // Memory only: a persisted shelf stays on disk for the next load, and
        // the temporary files this load created are deleted with it.
        var removed = shelfEntries
        shelfEntries = []
        forgetShelfItems(removed, true)
        shelfNotice = ""
        islandPointerActive = false
        islandShowing = false
        hudSuppressed = false
        hudHeldKind = ""
        settingsWindowOpen = false
        closeOnboarding(false)
    }
    // The settings and onboarding windows. The Service owns them, so the IPC
    // verbs, the legacy settings view and the header gear open the same
    // window, and a lock, retirement or dispose closes it.
    readonly property bool windowsAllowed: panelAllowed && !retired && !disposed
    property bool settingsWindowOpen: false
    property string settingsSection: ""
    property bool onboardingWindowOpen: false
    property bool onboardingOffered: false
    onWindowsAllowedChanged: if (!windowsAllowed) {
        settingsWindowOpen = false
        closeOnboarding(false)
    }
    // Opens the settings window, on one section when given its id. A window
    // already open may sit on another workspace, where a gear click would
    // seem to do nothing, so it is unmapped and mapped again on the current
    // one, keeping its section unless a new one is asked for.
    property int settingsWindowGeneration: 0
    function openSettings(section) {
        if (!windowsAllowed) return false
        var asked = typeof section === "string" ? section : ""
        var reopen = settingsWindowOpen
        settingsSection = asked || (reopen && settingsLoader.item ? String(settingsLoader.item.section || "") : "")
        if (reopen) {
            settingsWindowOpen = false
            Qt.callLater(function () {
                if (!root.windowsAllowed) return
                root.settingsWindowOpen = true
                root.settingsWindowGeneration++
            })
            return true
        }
        settingsWindowOpen = true
        settingsWindowGeneration++
        if (settingsLoader.item && settingsSection) settingsLoader.item.showSection(settingsSection)
        return true
    }
    function openOnboarding() {
        if (!windowsAllowed) return false
        onboardingWindowOpen = true
        return true
    }
    // A service-driven close interrupts an unfinished welcome. Suppress its
    // window's closed signal before unloading it, so lock and retirement can
    // never record completion. A user close or Finish does record it.
    function closeOnboarding(completed) {
        if (onboardingLoader.item) onboardingLoader.item.closingFromService = true
        onboardingWindowOpen = false
        if (completed) {
            if (fileSettings.onboardingDone !== true) configure({ onboardingDone: true })
        } else if (fileSettings.onboardingDone !== true) {
            onboardingOffered = false
        }
    }
    function finishOnboarding() { closeOnboarding(true) }
    // The first time this instance's island becomes usable, a settings file
    // without onboardingDone opens the welcome.
    function offerOnboarding() {
        if (onboardingOffered || !uiAllowed || !island || fileSettings.onboardingDone === true) return
        onboardingOffered = true
        openOnboarding()
    }
    DesignTokens {
        id: windowTokens
        highContrast: root.highContrast
        reducedMotion: root.reducedMotion
        customAccent: root.fileSettings.useCustomAccentColor === true ? root.fileSettings.customAccentColor : ""
    }
    LazyLoader {
        id: settingsLoader
        active: root.settingsWindowOpen && root.windowsAllowed
        SettingsWindow {
            tokens: windowTokens
            coordinator: root
            Component.onCompleted: if (root.settingsSection) showSection(root.settingsSection)
            onClosed: root.settingsWindowOpen = false
        }
    }
    LazyLoader {
        id: onboardingLoader
        active: root.onboardingWindowOpen && root.windowsAllowed
        OnboardingWindow {
            tokens: windowTokens
            coordinator: root
            onFinished: root.finishOnboarding()
        }
    }

    // Persistence: $XDG_STATE_HOME/nookisle/shelf.json, written only while
    // shelfPersist is on and this instance owns the registration. The
    // directory is created 700 and the atomic writer publishes a 600 file.
    // Loading salvages each entry on its own, and
    // turning the setting off deletes the file.
    readonly property string shelfStateDir: {
        var state = Quickshell.env("XDG_STATE_HOME") || ""
        if (state.charAt(0) !== "/") {
            var home = Quickshell.env("HOME") || ""
            state = home.charAt(0) === "/" ? home + "/.local/state" : ""
        }
        return state ? state + "/nookisle" : ""
    }
    readonly property string shelfFilePath: shelfStateDir ? shelfStateDir + "/shelf.json" : ""
    readonly property string shelfWriterPath: Shelf.localPath(Qt.resolvedUrl("scripts/write-private-shelf.py").toString())
    readonly property bool shelfPersistActive: shelfPersist && ownsRegistration && !!shelfFilePath
    // The file goes only when the user turned shelfPersist off, and only by
    // the owning instance. A retired, disposed or non-owning instance is not
    // persisting either, but the file belongs to its successor. A function,
    // not a binding: the change handlers below must read it current.
    function shelfFileUnwanted() { return !shelfPersist && !!shelfFilePath && ownsRegistration }
    property bool shelfStateReady: false
    property bool shelfLoaded: false
    property string shelfWritePending: ""
    property string shelfWriteJob: ""
    onShelfPersistActiveChanged: {
        if (shelfPersistActive) {
            shelfLoaded = false
            shelfFile.reload()
        } else if (shelfFileUnwanted()) {
            shelfLoaded = false
            shelfWritePending = ""
            shelfActions.execute({ argv: ["rm", "-f", "--", shelfFilePath] })
        }
    }
    function saveShelf() {
        if (shelfPersistActive && shelfLoaded) shelfSave.restart()
    }
    function writeShelf() {
        if (!shelfPersistActive || !shelfLoaded) return
        if (!shelfStateReady) {
            if (!shelfStateDirProcess.running) shelfStateDirProcess.running = true
            return
        }
        shelfWritePending = Shelf.serialise(shelfEntries)
        startShelfWrite()
    }
    function startShelfWrite() {
        if (!shelfPersistActive || !shelfLoaded || !shelfStateReady || !shelfWritePending || shelfWriteJob) return
        var payload = shelfWritePending
        shelfWritePending = ""
        shelfWriteJob = shelfActions.execute({ argv: ["python3", shelfWriterPath, shelfFilePath] }, payload)
        if (!shelfWriteJob) console.warn("nookisle: the shelf could not be saved")
    }
    // Stored items come first, then anything shelved before the file loaded.
    function loadShelf(text) {
        if (!shelfPersistActive || shelfLoaded) return
        var stored = Shelf.salvage(text, { limit: shelfLimit, nextId: shelfNextId })
        var keys = {}
        for (var i = 0; i < stored.items.length; ++i) keys[Shelf.identity(stored.items[i])] = true
        var merged = stored.items.slice(), overflow = false
        for (var j = 0; j < shelfEntries.length; ++j) {
            if (keys[Shelf.identity(shelfEntries[j])]) continue
            if (merged.length >= shelfLimit) { overflow = true; continue }
            merged.push(shelfEntries[j])
        }
        shelfNextId = stored.nextId
        shelfEntries = merged
        shelfLoaded = true
        if (overflow) shelfNotice = "shelf-full"
        queueShelfMime(stored.items.map(function(item) { return item.id }))
        if (stored.dropped > 0 || merged.length !== stored.items.length) saveShelf()
    }
    Timer { id: shelfSave; interval: 250; onTriggered: root.writeShelf() }
    FileView {
        id: shelfFile
        // A fixed path: reload() in onShelfPersistActiveChanged is the one
        // load that counts, so the merge in loadShelf runs exactly once.
        path: root.shelfFilePath
        blockLoading: true
        printErrors: false
        onLoaded: root.loadShelf(text())
        onLoadFailed: root.loadShelf("")
    }
    Process {
        id: shelfStateDirProcess
        command: ["install", "-d", "-m", "700", root.shelfStateDir]
        onExited: (exitCode, exitStatus) => {
            root.shelfStateReady = exitCode === 0
            if (exitCode === 0) root.writeShelf()
            else console.warn("nookisle: the shelf state directory could not be created")
        }
    }

    // Temporary files (zips, conversions) live in $XDG_RUNTIME_DIR/nookisle/shelf.
    // The directory is created 700 when this instance starts and pruned of every
    // file no item holds; an item's file is deleted when the item goes.
    readonly property string shelfTempRoot: {
        var runtime = Quickshell.env("XDG_RUNTIME_DIR") || ""
        return runtime.charAt(0) === "/" ? runtime + "/nookisle" : ""
    }
    readonly property string shelfTempDir: shelfTempRoot ? shelfTempRoot + "/shelf" : ""
    property bool shelfTempReady: false
    function prepareShelfTemp() {
        if (!ownsRegistration || !shelfTempDir || shelfTempReady || shelfTempDirProcess.running) return
        shelfTempDirProcess.running = true
    }
    Process {
        id: shelfTempDirProcess
        command: ["install", "-d", "-m", "700", root.shelfTempRoot, root.shelfTempDir]
        onExited: (exitCode, exitStatus) => {
            root.shelfTempReady = exitCode === 0
            if (exitCode !== 0) return
            var keep = []
            for (var i = 0; i < root.shelfEntries.length; ++i)
                if (root.shelfEntries[i].temp) keep.push(root.shelfActions.baseName(Shelf.localPath(root.shelfEntries[i].uri)))
            root.shelfActions.execute(root.shelfActions.pruneCommand(root.shelfTempDir, keep))
        }
    }

    // Thumbnails. The helper checks the freedesktop cache's URI and MTime
    // before returning a path; on a miss it decodes a PNG or JPEG in its
    // sandboxed decoder and writes the 128 px entry. Every other file shows
    // the icons of its MIME type.
    readonly property string shelfCacheHome: {
        var cache = Quickshell.env("XDG_CACHE_HOME") || ""
        if (cache.charAt(0) !== "/") {
            var home = Quickshell.env("HOME") || ""
            cache = home.charAt(0) === "/" ? home + "/.cache" : ""
        }
        return cache
    }
    property var shelfThumbnails: ({})
    property var shelfMimes: ({})
    property var shelfThumbnailRequests: ({})
    // Busy replies per item: retried after a pause, at most
    // shelfThumbnailBusyLimit times, then the item keeps its icon.
    property var shelfThumbnailBusy: ({})
    readonly property int shelfThumbnailBusyLimit: 3
    property var shelfThumbnailRetryIds: []
    Timer {
        id: shelfThumbnailRetry
        interval: 750
        repeat: false
        onTriggered: {
            var ids = root.shelfThumbnailRetryIds
            root.shelfThumbnailRetryIds = []
            for (var i = 0; i < ids.length; ++i) root.requestShelfThumbnail(ids[i])
        }
    }
    // Pending requests whose answers must no longer count because the item
    // was renamed or removed (its URI changed). A late answer to a dropped
    // request is ignored.
    function dropShelfThumbnailRequests(ids) {
        var next = {}
        for (var request in shelfThumbnailRequests)
            if (ids.indexOf(shelfThumbnailRequests[request]) < 0) next[request] = shelfThumbnailRequests[request]
        shelfThumbnailRequests = next
        shelfThumbnailRetryIds = shelfThumbnailRetryIds.filter(function(id) { return ids.indexOf(id) < 0 })
        shelfThumbnailOwed = shelfThumbnailOwed.filter(function(id) { return ids.indexOf(id) < 0 })
    }
    // Items whose thumbnail a helper still owed when it stopped or exited,
    // asked again once a replacement helper connects: their tiles asked
    // once and will not ask again on their own.
    property var shelfThumbnailOwed: []
    function shelfThumbnailHelperLost() {
        var owed = shelfThumbnailOwed.slice()
        function owe(id) { if (owed.indexOf(id) < 0) owed.push(id) }
        for (var request in shelfThumbnailRequests) owe(shelfThumbnailRequests[request])
        for (var i = 0; i < shelfThumbnailRetryIds.length; ++i) owe(shelfThumbnailRetryIds[i])
        shelfThumbnailRequests = ({})
        shelfThumbnailRetry.stop()
        shelfThumbnailRetryIds = []
        shelfThumbnailOwed = owed
    }
    function resendOwedShelfThumbnails() {
        if (!connected) return
        var owed = shelfThumbnailOwed
        shelfThumbnailOwed = []
        for (var i = 0; i < owed.length; ++i) requestShelfThumbnail(owed[i])
    }
    // Items the helper could not thumbnail: they keep their icon and are not asked again.
    property var shelfThumbnailMisses: ({})
    property int shelfThumbnailCounter: 0
    function shelfThumbnailCandidates(id) {
        var item = Shelf.findItem(shelfEntries, id)
        if (!item || item.kind !== "file") return []
        return shelfThumbnails[id] ? [shelfThumbnails[id]] : []
    }
    function requestShelfThumbnail(id) {
        var item = Shelf.findItem(shelfEntries, id)
        if (!item || item.kind !== "file" || !Shelf.thumbnailable(shelfMimes[id])
            || shelfThumbnailMisses[id]) return false
        for (var pending in shelfThumbnailRequests)
            if (shelfThumbnailRequests[pending] === id) return true
        var requestId = "thumb" + (++shelfThumbnailCounter)
        if (!send("thumbnail", { requestId: requestId, uri: item.uri, name: Shelf.thumbnailName(item.uri) })) return false
        var next = Object.assign({}, shelfThumbnailRequests)
        next[requestId] = id
        shelfThumbnailRequests = next
        return true
    }
    function receiveThumbnail(event) {
        var id = shelfThumbnailRequests[event.requestId]
        if (id === undefined) return
        var next = Object.assign({}, shelfThumbnailRequests)
        delete next[event.requestId]
        shelfThumbnailRequests = next
        var item = Shelf.findItem(shelfEntries, id)
        if (!item) return
        var expected = Shelf.thumbnailCandidates(shelfCacheHome, item.uri)
        if (event.status !== "ready" || expected.indexOf(event.path) < 0) {
            // busy is transient and retried, a bounded number of times;
            // anything else is final for this item.
            var busy = Object.assign({}, shelfThumbnailBusy)
            if (event.status === "busy" && (busy[id] || 0) < shelfThumbnailBusyLimit) {
                busy[id] = (busy[id] || 0) + 1
                shelfThumbnailBusy = busy
                if (shelfThumbnailRetryIds.indexOf(id) < 0) shelfThumbnailRetryIds = shelfThumbnailRetryIds.concat([id])
                shelfThumbnailRetry.restart()
                return
            }
            delete busy[id]
            shelfThumbnailBusy = busy
            var misses = Object.assign({}, shelfThumbnailMisses)
            misses[id] = true
            shelfThumbnailMisses = misses
            var invalid = Object.assign({}, shelfThumbnails)
            delete invalid[id]
            shelfThumbnails = invalid
            return
        }
        var answered = Object.assign({}, shelfThumbnailBusy)
        delete answered[id]
        shelfThumbnailBusy = answered
        var thumbnails = Object.assign({}, shelfThumbnails)
        thumbnails[id] = event.path
        shelfThumbnails = thumbnails
    }
    function shelfIcons(id) {
        var item = Shelf.findItem(shelfEntries, id)
        if (!item) return []
        if (item.kind === "link") return ["text-html", "text-x-generic"]
        if (item.kind === "text") return ["text-x-generic"]
        return Shelf.mimeIcons(shelfMimes[id])
    }
    // One `xdg-mime query filetype` at a time, for each new file item.
    property var shelfMimeQueue: []
    property string shelfMimeJob: ""
    property string shelfMimeTarget: ""
    function queueShelfMime(ids) {
        var queue = shelfMimeQueue.slice()
        for (var i = 0; i < ids.length; ++i) {
            var item = Shelf.findItem(shelfEntries, ids[i])
            if (item && item.kind === "file" && queue.indexOf(ids[i]) < 0) queue.push(ids[i])
        }
        shelfMimeQueue = queue
        Qt.callLater(nextShelfMime)
    }
    function nextShelfMime() {
        while (!shelfMimeJob && shelfMimeQueue.length) {
            var id = shelfMimeQueue[0]
            shelfMimeQueue = shelfMimeQueue.slice(1)
            var item = Shelf.findItem(shelfEntries, id)
            if (!item) continue
            var job = shelfActions.execute(shelfActions.mimeCommand(Shelf.localPath(item.uri)))
            if (!job) continue
            shelfMimeJob = job
            shelfMimeTarget = id
        }
    }

    // Shelf actions. Each runs through ShelfActions; the ones that make a
    // file (zip, conversion, PDF, cut-out) add it as a temporary item.
    property var shelfJobs: ({})
    function shelfFilePaths(ids) {
        var paths = []
        for (var i = 0; i < ids.length; ++i) {
            var item = Shelf.findItem(shelfEntries, ids[i])
            var path = item && item.kind === "file" ? Shelf.localPath(item.uri) : ""
            if (path) paths.push(path)
        }
        return paths
    }
    function shelfOpenCommand(id) {
        var item = Shelf.findItem(shelfEntries, id)
        if (!item) return null
        if (item.kind === "file") return shelfActions.openCommand(Shelf.localPath(item.uri))
        if (item.kind === "link") return shelfActions.openUrlCommand(item.url)
        return item.kind === "text" ? { copyId: id } : null
    }
    // name: open, openWith, showInFiles, copy, copyPath, compress, rename,
    // convert, pdf, removeBackground, share, remove. argument: the desktop id
    // (openWith), the new name (rename) or the format png|jpeg|webp (convert).
    function shelfAction(name, ids, argument) {
        var list = Array.isArray(ids) ? ids : [ids]
        var paths = shelfFilePaths(list)
        var stamp = Date.now()
        var tools = shelfActions.tools
        var specs = []
        switch (name) {
        case "remove":
            for (var i = 0; i < list.length; ++i) shelfRemoveItem(list[i])
            return true
        case "copy":
            return list.length === 1 ? shelfCopyItem(list[0]) : shelfCopyItems(list)
        case "copyPath":
            return paths.length ? shelfCopyText(paths.join("\n")) : false
        case "open":
            specs = list.map(function(id) { return shelfOpenCommand(id) })
            break
        case "openWith":
            specs = paths.slice(0, 1).map(function(path) { return shelfActions.openWithCommand(argument, path, tools) })
            break
        case "showInFiles":
            specs = paths.slice(0, 1).map(function(path) { return shelfActions.showInFilesCommand(path) })
            break
        case "share":
            return shelfSharePaths(paths)
        case "rename":
            if (list.length !== 1 || paths.length !== 1) return false
            if (!shelfActions.validRename(argument)) { shelfNotice = "rename-invalid"; return false }
            specs = [shelfActions.renameCommand(paths[0], argument)]
            break
        case "compress":
            var allRegular = list.every(function(id) {
                return !!shelfMimes[id] && shelfMimes[id] !== "inode/directory"
            })
            specs = shelfTempReady ? [shelfActions.compressCommand(paths, shelfTempDir, stamp, allRegular)] : []
            break
        case "convert":
            specs = shelfTempReady ? paths.map(function(path, index) {
                return shelfActions.convertCommand(path, argument, shelfTempDir, stamp + index) }) : []
            break
        case "pdf":
            specs = shelfTempReady ? [shelfActions.pdfCommand(paths, shelfTempDir, stamp)] : []
            break
        case "removeBackground":
            specs = shelfTempReady ? paths.slice(0, 1).map(function(path) {
                return shelfActions.removeBackgroundCommand(path, shelfTempDir, stamp, tools) }) : []
            break
        default:
            return false
        }
        var started = false
        for (var j = 0; j < specs.length; ++j) {
            var spec = specs[j]
            if (!spec) continue
            if (spec.copyId) {
                started = shelfCopyItem(spec.copyId) || started
                continue
            }
            var job = shelfActions.execute(spec)
            if (!job) continue
            started = true
            if (job === "detached") continue
            var next = Object.assign({}, shelfJobs)
            next[job] = { name: name, id: list[0], output: spec.output || "", target: spec.target || "", path: paths[0] || "" }
            shelfJobs = next
        }
        if (!started) shelfNotice = "action-unavailable"
        return started
    }
    // Share tile: files dropped on it are sent without being shelved.
    function shelfShareUris(uris) {
        var paths = []
        for (var i = 0; i < (Array.isArray(uris) ? uris.length : 0); ++i) {
            var path = Shelf.localPath(String(uris[i]))
            if (path) paths.push(path)
        }
        return shelfSharePaths(paths)
    }
    function shelfSharePaths(paths) {
        var specs = shelfActions.shareCommands(fileSettings.shareProvider, paths, shelfActions.tools)
        var started = false
        for (var j = 0; j < specs.length; ++j) {
            var job = shelfActions.execute(specs[j])
            if (!job) continue
            started = true
            if (specs[j].devices) {
                var next = Object.assign({}, shelfJobs)
                next[job] = { name: "shareDevices", paths: paths }
                shelfJobs = next
            }
        }
        if (!started) shelfNotice = "action-unavailable"
        return started
    }
    // Share tile clicked with nothing dropped: a picker when zenity exists.
    property string shelfPickerJob: ""
    function shelfPickAndShare() {
        if (shelfPickerJob) return false
        var job = shelfActions.execute(shelfActions.pickerCommand(shelfActions.tools))
        shelfPickerJob = job
        return job !== ""
    }
    function discardShelfOutput(path) {
        if (path) shelfActions.execute(shelfActions.removeTempCommand(shelfTempDir, path))
    }
    function handleShelfJob(job, status, exitCode, output) {
        if (job === shelfWriteJob) {
            shelfWriteJob = ""
            if (status !== "ok") console.warn("nookisle: the shelf could not be saved")
            if (shelfFileUnwanted()) shelfActions.execute({ argv: ["rm", "-f", "--", shelfFilePath] })
            else if (shelfPersistActive) Qt.callLater(startShelfWrite)
            return
        }
        if (job === shelfMimeJob) {
            var mime = status === "ok" ? shelfActions.parseMime(output) : ""
            if (mime && Shelf.findItem(shelfEntries, shelfMimeTarget)) {
                var mimes = Object.assign({}, shelfMimes)
                mimes[shelfMimeTarget] = mime
                shelfMimes = mimes
            }
            shelfMimeJob = ""
            shelfMimeTarget = ""
            Qt.callLater(nextShelfMime)
            return
        }
        if (job === shelfPickerJob) {
            shelfPickerJob = ""
            if (status === "ok")
                shelfShareUris(shelfActions.parseSelection(output).map(function(path) { return shelfActions.pathToUri(path) }))
            return
        }
        var pending = shelfJobs[job]
        if (!pending) return
        var next = Object.assign({}, shelfJobs)
        delete next[job]
        shelfJobs = next
        if (status !== "ok") {
            discardShelfOutput(pending.output)
            // A file manager without FileManager1 still gets its folder opened.
            if (pending.name === "showInFiles") shelfActions.execute(shelfActions.showFolderCommand(pending.path))
            else shelfNotice = status === "timeout" ? "action-timeout" : status === "unavailable" ? "action-unavailable" : "action-failed"
            return
        }
        if (pending.name === "shareDevices") {
            var device = shelfActions.parseDevice(output)
            var shares = shelfActions.kdeconnectShareCommands(device, pending.paths)
            if (!shares.length) { shelfNotice = "share-no-device"; return }
            for (var k = 0; k < shares.length; ++k) shelfActions.execute(shares[k])
            return
        }
        if (pending.name === "rename") {
            var renamed = Shelf.renameItem(shelfEntries, pending.id, shelfActions.pathToUri(pending.target))
            if (renamed) {
                shelfEntries = renamed
                forgetShelfCaches(pending.id)
                queueShelfMime([pending.id])
                saveShelf()
            }
        } else if (pending.output) {
            if (!shelfAddCandidates([{ kind: "file", uri: shelfActions.pathToUri(pending.output), temp: true }]))
                discardShelfOutput(pending.output)
        }
    }
    function forgetShelfCaches(id) {
        forgetShelfIds([id])
    }
    // Loaded by file path rather than as a type from a directory import: a
    // Service created from a staged copy (the lifecycle suite does this) gets
    // no module registration for its components directory. The Loader is
    // synchronous, so the item exists once the Service is constructed.
    Loader {
        id: shelfActionsLoader
        source: "components/ShelfActions.qml"
    }
    readonly property var shelfActions: shelfActionsLoader.item
    Connections {
        target: shelfActionsLoader.item
        function onFinished(job, status, exitCode, output) { root.handleShelfJob(job, status, exitCode, output) }
    }
    // The host's shell.json keys. Every other schema key lives in the
    // plugin's own settings file below.
    readonly property var settingKeys: Settings.keys("shell")
    // Why the last configure() returned false, for the settings window's
    // message: "invalid" (a value the schema refuses), "not-ready" (the
    // settings folder is still being created), "save-failed" (settings.json
    // could not be written), "host" (the shell config could not be written)
    // or "unavailable" (this instance does not own the plugin). "" after a
    // success. The IPC verb keeps its one "invalid-settings" answer.
    property string configureError: ""
    function refuseConfigure(code) { configureError = code; return false }
    // A batch is validated whole against the schema, then split by store.
    // Nothing is written unless every key is valid and every store it
    // touches is writable.
    function configure(options) {
        configureError = ""
        if (!ownsRegistration || !pluginRegistry) return refuseConfigure("unavailable")
        if (!Protocol.object(options) || !Settings.validateBatch(options)) return refuseConfigure("invalid")
        options = Settings.applyAliases(options, fileSettings)
        // A remembered Shelf tab needs its tab row even when Shelf is empty.
        if (options.rememberLastTab === true)
            options = Object.assign({}, options, { alwaysShowTabs: true })
        var shellOptions = {}, fileOptions = {}, hasFile = false, hasShell = false
        for (var key in options) {
            if (settingKeys.indexOf(key) >= 0) { shellOptions[key] = options[key]; hasShell = true }
            else { fileOptions[key] = options[key]; hasFile = true }
        }
        if (!hasFile) return configureShell(shellOptions) || refuseConfigure("host")
        if (!settingsFilePath) return refuseConfigure("save-failed")
        if (hasShell && typeof pluginRegistry.shellConfigMutator !== "function"
            && (!shell || typeof shell.updateEntryInline !== "function")) return refuseConfigure("host")
        // The file is written first and synchronously, so a failed save
        // rejects the batch before the shell config changes.
        if (!writeFileSettings(fileOptions)) return refuseConfigure(settingsDirReady ? "save-failed" : "not-ready")
        return hasShell ? configureShell(shellOptions) || refuseConfigure("host") : true
    }
    function configureShell(options) {
        if (typeof pluginRegistry.shellConfigMutator === "function") {
            pluginRegistry.shellConfigMutator(function(config) {
                var entry = root.configurationEntry(config)
                if (entry) entry.settings = Object.assign({}, entry.settings || {}, options)
            })
            return true
        }
        if (!shell || typeof shell.updateEntryInline !== "function") return false
        // updateEntryInline replaces the entry's keys with exactly what it is
        // given, so send every known setting, not only the changed one.
        var next = {}
        for (var i = 0; i < settingKeys.length; ++i)
            if (typeof settings[settingKeys[i]] === "boolean") next[settingKeys[i]] = settings[settingKeys[i]]
        // It returns false when nothing changed, which is still success here.
        shell.updateEntryInline(pluginId, Object.assign(next, options))
        settingsWritten = Object.assign({}, settingsWritten, options)
        return true
    }
    // Typed settings live in the plugin's own file,
    // $XDG_CONFIG_HOME/nookisle/settings.json, as {version: 1, values}.
    // It holds exactly the schema's file keys, all of them preferences.
    // FileView neither creates directories nor sets modes: each instance runs
    // `install -d -m 700` when it starts and publishes a fresh 0600 file atomically
    // via write-private-shelf.py --if-missing, so the file is created with 0600
    // with no world-readable window and QSaveFile preserves 0600 on subsequent saves.
    // A write is refused until the directory exists, and a save
    // that fails leaves the values unchanged. Every value passes through
    // Settings.resolve, so an unknown key is dropped and an invalid or
    // corrupt one reads as its default.
    readonly property string settingsDir: {
        var config = Quickshell.env("XDG_CONFIG_HOME") || ""
        if (config.charAt(0) !== "/") {
            var home = Quickshell.env("HOME") || ""
            config = home.charAt(0) === "/" ? home + "/.config" : ""
        }
        return config ? config + "/nookisle" : ""
    }
    readonly property string settingsFilePath: settingsDir ? settingsDir + "/settings.json" : ""
    property var fileSettings: Settings.resolve(null)
    function calendarSend(type, fields) {
        if (!uiAllowed || !showCalendar || !calendarSupported || !island) return false
        return type === "calendarCredential" ? sendCalendarCredential(fields) : send(type, fields)
    }
    // Removing a calendar source is a Service transaction, because the
    // Service outlives the island and the settings window and owns the
    // helper connection. One settings save writes the list without the source
    // and, if no remaining source signs in with that CalDAV account, the
    // account's identifiers (url and user, never a password) in the internal
    // calendarPendingClears key; configure() returns only once that is on
    // disk. The Service then sends a clear for each saved account whenever the
    // helper is connected (so a clear survives a restart), forgets it once the
    // helper answers, and skips an account that is configured again. This clear
    // is the one calendarCredential message the Service composes itself; it
    // only forwards CalendarSource's own credential requests, holding a
    // password store for an account until that account's clear in flight is
    // answered, so a re-added password is never deleted after it was stored.
    property var calendarClearsInFlight: ({})
    property var heldCalendarStores: []
    property int calendarClearCount: 0
    signal calendarClearFinished(string url, string user, bool ok, string error)
    function removeCalendarSource(definition) {
        var removal = Calendar.withoutSource(fileSettings.calendarSources, definition)
        if (!removal.found) return false
        var clears = Calendar.clearsAfterRemoval(fileSettings.calendarPendingClears, definition, removal.next)
        if (!configure({ calendarSources: removal.next, calendarPendingClears: clears })) return false
        sendCalendarClears()
        return true
    }
    // Whether a clear for this account is with the helper now.
    function calendarClearPending(url, user) {
        return !!calendarClearsInFlight[Calendar.accountKey(url, user)]
    }
    function sendCalendarClears() {
        var pending = fileSettings.calendarPendingClears || []
        var keep = Calendar.clearsToKeep(pending, fileSettings.calendarSources, calendarClearsInFlight)
        if (keep.length !== pending.length && !configure({ calendarPendingClears: keep })) return
        if (!connected || !calendarSupported || retired || disposed || !ownsRegistration) return
        var toSend = Calendar.clearsToSend(keep, fileSettings.calendarSources, calendarClearsInFlight)
        var inFlight = Object.assign({}, calendarClearsInFlight)
        for (var i = 0; i < toSend.length; ++i) {
            var id = "calendar-clear:" + (++calendarClearCount)
            if (!send("calendarCredential", { requestId: id, action: "clear", url: toSend[i].url, user: toSend[i].user })) break
            inFlight[Calendar.accountKey(toSend[i].url, toSend[i].user)] = id
        }
        calendarClearsInFlight = inFlight
    }
    // CalendarSource's credential requests. A store waits while a clear for
    // the same account is with the helper.
    function sendCalendarCredential(fields) {
        if (fields.action === "store" && calendarClearPending(fields.url, fields.user)) {
            heldCalendarStores = heldCalendarStores.concat([fields])
            return true
        }
        return send("calendarCredential", fields)
    }
    // Answers a held store the helper will never see, so its sender is not
    // left waiting.
    function refuseHeldStore(fields) {
        calendarFrame({ type: "calendarResult", requestId: fields.requestId, status: "unavailable" })
    }
    // True when the answer is to one of the Service's own clears.
    function finishCalendarClear(event) {
        var key = ""
        for (var candidate in calendarClearsInFlight)
            if (calendarClearsInFlight[candidate] === event.requestId) key = candidate
        if (!key) return false
        var inFlight = Object.assign({}, calendarClearsInFlight)
        delete inFlight[key]
        calendarClearsInFlight = inFlight
        var entry = (fileSettings.calendarPendingClears || []).filter(item => Calendar.accountKey(item.url, item.user) === key)[0]
        configure({ calendarPendingClears: (fileSettings.calendarPendingClears || [])
            .filter(item => Calendar.accountKey(item.url, item.user) !== key) })
        var ok = event.status === "ok" || event.ok === true
        var parts = key.split("\n")
        calendarClearFinished(entry ? entry.url : parts[0], entry ? entry.user : parts.slice(1).join("\n"),
            ok, ok ? "" : String(event.error || event.status || "error"))
        var held = heldCalendarStores.filter(fields => Calendar.accountKey(fields.url, fields.user) === key)
        heldCalendarStores = heldCalendarStores.filter(fields => Calendar.accountKey(fields.url, fields.user) !== key)
        for (var i = 0; i < held.length; ++i)
            if (!send("calendarCredential", held[i])) refuseHeldStore(held[i])
        return true
    }
    // Clears in flight when the helper goes away are sent again to the next
    // one; held stores are answered as unavailable and their passwords dropped.
    onConnectedChanged: {
        Qt.callLater(syncWatch)
        Qt.callLater(syncBacklightWatch)
        if (!connected) {
            calendarClearsInFlight = ({})
            var held = heldCalendarStores
            heldCalendarStores = []
            for (var i = 0; i < held.length; ++i) refuseHeldStore(held[i])
        } else {
            Qt.callLater(sendCalendarClears)
            Qt.callLater(resendOwedShelfThumbnails)
        }
    }
    onFileSettingsChanged: sendCalendarClears()
    property bool settingsDirReady: false
    property bool settingsSaveFailed: false
    property bool settingsBackupFailed: false
    property bool settingsNeedsBackup: false
    property var settingsBackupData: null
    function prepareSettingsDir() {
        if (settingsDir && !settingsDirReady && !settingsDirProcess.running && !settingsInitProcess.running) settingsDirProcess.running = true
    }
    // True once the values are on disk. FileView reports saved or saveFailed
    // from inside waitForJob, so the outcome is known before this returns.
    function writeFileSettings(values) {
        if (!settingsDirReady) {
            prepareSettingsDir()
            return false
        }
        var next = Settings.resolve(Object.assign({}, fileSettings, values))
        if (settingsNeedsBackup) {
            settingsBackupFailed = false
            settingsBackupFile.setData(settingsBackupData)
            settingsBackupFile.waitForJob()
            if (settingsBackupFailed) return false
            settingsNeedsBackup = false
            settingsBackupData = null
        }
        settingsSaveFailed = false
        settingsFile.setText(Settings.serialise(next))
        settingsFile.waitForJob()
        if (settingsSaveFailed) return false
        fileSettings = Settings.resolve(next)
        return true
    }
    IpcHandler {
        enabled: root.ownsRegistration
        target: root.ownsRegistration ? "nookisle" : ""
        function status(): string {
            return JSON.stringify({ connected: root.connected, lockReady: root.lockReady,
                panelAllowed: root.panelAllowed, controlsAllowed: root.uiAllowed,
                sourceCount: root.sourceCount, selectionMode: root.selectionMode,
                pinUnavailable: root.pinUnavailable, helperRunning: root.helperRunning,
                viewVisible: root.viewVisible, viewExpanded: root.viewExpanded,
                diagnostic: root.diagnostic, remoteArtwork: root.remoteArtwork,
                settings: Settings.publicValues(root.fileSettings),
                reducedMotion: root.reducedMotion, highContrast: root.highContrast,
                island: root.island, hud: root.hud, visualizer: root.visualizer,
                peek: root.peek, tint: root.tint, power: root.power, lyrics: root.lyrics,
                shelfCount: root.shelfEntries.length, brightnessHud: root.brightnessMonitorRunning,
                timers: root.timerStatus(), activity: root.activityKey, privacy: root.privacyCounts,
                spectrum: root.spectrumState })
        }
        function retry(): string { return root.retryConnection() ? "ok" : "unavailable" }
        // Transport verbs only: no action string
        // crosses this boundary. No window-management, focus or presence verb
        // (Raise included) is ever exposed here, valued or not.
        function playPause(): string { return root.externalPlayPause() }
        function next(): string { return root.externalNext() }
        function previous(): string { return root.externalPrevious() }
        function shuffle(): string { return root.externalShuffle() }
        function repeat(): string { return root.externalRepeat() }
        function seek(seconds: real): string { return root.externalSeek(seconds) }
        // Open the settings window, or the welcome steps again.
        function settings(): string { return root.openSettings("") ? "ok" : "unavailable" }
        function onboarding(): string { return root.openOnboarding() ? "ok" : "unavailable" }
        // LED brightness changes emit no uevent, so the keyboard key bindings
        // call this after changing the level; it only re-reads sysfs.
        function keyboardBacklightChanged(): string { return root.keyboardBacklightChanged() ? "ok" : "unavailable" }
        // Read-only: the media-keys helper asks before each volume, mic,
        // brightness or keyboard key whether the island shows its readout.
        function hudReadout(kind: string, device: string): string { return root.hudReadout(kind, device) ? "ok" : "unavailable" }
        // Start an Omarchy reminder the island counts down, or cancel one it
        // lists. Neither opens a window or takes focus.
        function timer(minutes: int, label: string): string { return root.startTimer(minutes, label) }
        function timerCancel(unit: string): string { return root.cancelTimer(unit) }
        function configure(json: string): string {
            try { return root.configure(JSON.parse(json)) ? "ok" : "invalid-settings" }
            catch (error) { return "invalid-settings" }
        }
    }
    // Supersession and host reload both retire; a retired instance is not
    // destroyed, so it must not keep shelved links alive beside its successor.
    onRetiredChanged: if (retired) releaseIslandState()
    onOwnsRegistrationChanged: {
        reconcile()
        Qt.callLater(prepareShelfTemp)
        Qt.callLater(refreshTimers)
    }
    onManifestChanged: reconcile()
    onPluginRegistryChanged: reconcile()
    onLockReadyChanged: {
        if (!lockReady) closeGate()
        else Qt.callLater(activate)
    }
    // Only a first-party plugin receives the shell root, whose
    // pluginReloading flag this retires on. A third-party plugin receives
    // the host's scoped PluginShellApi, which has no such signal, so the
    // handler is unused there and must not warn. The stock host also keeps
    // this service across a plugin reload (manifest keepLoaded: true, see
    // unloadPluginServices), so an update needs a full shell restart
    // (docs/install.md, "Updating an installed plugin").
    Connections {
        target: root.shell
        ignoreUnknownSignals: true
        function onPluginReloadingChanged() {
            if (root.shell.pluginReloading) {
                root.retired = true
                root.stopOwned()
            }
        }
    }
    // SpectrumDesiredChanged only fires on a change, not on the property's
    // initial evaluation. BrightnessSource starts its own monitors.
    Component.onCompleted: {
        // The settings file loads while this object is created, before the
        // preferredSource handler is connected.
        if (preferredSource) selectionState = SourceState.prefer(selectionState, preferredSource, endpoints)
        checkDesktopMotion()
        Qt.callLater(startSpectrum)
        Qt.callLater(prepareSettingsDir)
    }
    Component.onDestruction: dispose()
    Loader {
        id: calendarLoader
        active: root.showCalendar && root.calendarSupported && root.island && root.uiAllowed
        source: "components/CalendarSource.qml"
        onLoaded: item.coordinator = root
    }

    Process {
        id: helper
        stdinEnabled: true
        onStarted: { if (!root.ownsRegistration || root.disposed) root.stopOwned() }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (!root.stopping && !root.disposed) {
                    Protocol.feed(root.receiverState, data, root.deadlineClock, root.receive)
                    root.scheduleDeadlines()
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => { /* Helper diagnostics are represented by bounded exit codes. */ }
        }
        onExited: (exitCode, exitStatus) => {
            handshake.stop()
            gateDeadline.stop()
            deadlineTicker.stop()
            terminateDelay.stop()
            killDelay.stop()
            var intentional = root.stopping
            root.stopping = false
            root.connected = false
            root.closeGate()
            root.endpoints = []
            root.connectionGeneration = ""
            root.receiverState = Protocol.receiver()
            root.outstandingBytes = ({})
            root.outputBudget = 0
            // An exit, expected or not, ends every thumbnail request it owed.
            root.shelfThumbnailHelperLost()
            root.helperExited(exitCode)
            if (!root.ownsRegistration || root.disposed || root.failedPermanently) return
            if (intentional) {
                if (root.restartDelay > 0) {
                    retry.interval = root.restartDelay
                    root.restartDelay = 0
                    retry.start()
                } else Qt.callLater(root.activate)
                return
            }
            if (exitCode === 73 || exitCode === 3) {
                var now = Date.now()
                if (now - root.retryWindow >= 60000) { root.retryWindow = now; root.retryCount = 0 }
                if (root.retryCount < 3) {
                    retry.interval = 1000 * Math.pow(2, root.retryCount++)
                    root.diagnostic = exitCode === 73 ? "lease-busy" : "bus-unavailable"
                    retry.start()
                } else { root.diagnostic = "retry-exhausted"; root.failedPermanently = true }
            } else { root.diagnostic = "helper-exited-" + exitCode; root.failedPermanently = true }
        }
    }
    Timer { id: retry; onTriggered: root.activate() }
    // Single-shot: not a recurring cadence, and no render work between arming
    // and firing. The label is an absolute time computed once, so nothing
    // repaints while it waits.
    Timer { id: sleepTimer; onTriggered: root.fireSleepTimer() }
    Timer { id: handshake; interval: 3000; onTriggered: root.protocolError("helper-handshake-timeout") }
    Timer { id: gateDeadline; interval: 3000; onTriggered: root.recoverFromStall("gate-ack-timeout") }
    Timer { id: terminateDelay; interval: 250; onTriggered: { if (helper.running) { helper.signal(15); killDelay.start() } } }
    Timer { id: killDelay; interval: 750; onTriggered: { if (helper.running) helper.signal(9) } }
    Timer { id: deadlineTicker; interval: Protocol.deadlineTick; repeat: true; onTriggered: root.tickDeadlines() }
    Loader {
        id: brightnessSourceLoader
        source: "components/BrightnessSource.qml"
    }
    Binding {
        target: brightnessSourceLoader.item
        property: "active"
        value: root.hud && root.island && root.panelAllowed && !root.retired && !root.disposed
        when: brightnessSourceLoader.item !== null
    }
    Binding {
        target: brightnessSourceLoader.item
        property: "sysRoot"
        value: root.backlightSysRoot
        when: brightnessSourceLoader.item !== null
    }
    Binding {
        target: brightnessSourceLoader.item
        property: "backlightOverride"
        value: root.fileSettings.backlightDevice || ""
        when: brightnessSourceLoader.item !== null
    }
    Connections {
        target: brightnessSourceLoader.item
        function onSample(kind, level, muted) { root.hudEvent(kind, level, muted) }
    }
    FileView {
        id: settingsFile
        path: root.settingsFilePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        // Invalid sources a hand edit left in the file are ignored with a
        // note naming only how many, never the source itself.
        onLoaded: {
            var notes = []
            var parsed = Settings.parseFile(text())
            root.settingsNeedsBackup = parsed === null
            root.settingsBackupData = root.settingsNeedsBackup ? data() : null
            if (root.settingsNeedsBackup)
                console.warn("nookisle: invalid settings.json; using defaults and saving the original to settings.json.bad before the next write")
            root.fileSettings = Settings.resolve(parsed, notes)
            if (notes.length) console.warn(Settings.noteText(notes))
        }
        onLoadFailed: root.fileSettings = Settings.resolve(null)
        onFileChanged: reload()
        // A watch starts only on a file that exists, so the save that
        // creates the file reloads it to begin watching.
        onSaved: reload()
        onSaveFailed: {
            root.settingsSaveFailed = true
            console.warn("nookisle: the settings file could not be saved")
        }
    }
    FileView {
        id: settingsBackupFile
        path: root.settingsFilePath ? root.settingsFilePath + ".bad" : ""
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaved: settingsBackupModeProcess.running = true
        onSaveFailed: {
            root.settingsBackupFailed = true
            console.warn("nookisle: could not preserve invalid settings.json; settings save refused")
        }
    }
    Process {
        id: settingsBackupModeProcess
        command: ["chmod", "600", root.settingsFilePath + ".bad"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) console.warn("nookisle: could not restrict the settings backup file")
        }
    }
    Process {
        id: settingsDirProcess
        command: ["install", "-d", "-m", "700", root.settingsDir]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.settingsDirReady = false
                console.warn("nookisle: the settings directory could not be created")
            } else if (root.shelfWriterPath && root.settingsFilePath && !settingsInitProcess.running) {
                settingsInitProcess.running = true
            } else {
                root.settingsDirReady = false
                console.warn("nookisle: the settings file could not be initialized")
            }
        }
    }
    Process {
        id: settingsInitProcess
        command: ["python3", root.shelfWriterPath, "--if-missing", root.settingsFilePath]
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify({ version: 1, values: {} }) + "\n")
            stdinEnabled = false
        }
        onExited: (exitCode, exitStatus) => {
            root.settingsDirReady = exitCode === 0
            if (exitCode !== 0) console.warn("nookisle: the initial settings file could not be created")
        }
    }
    // Live spectrum for the collapsed pill: a small native binary that
    // captures the default sink's monitor locally and prints 12 levels 0..99
    // per line, at most spectrumFps lines a second, and nothing while the signal is
    // silent. Nothing it reads leaves the process except those numbers. It
    // runs only while the island itself is on screen and the selected source
    // is playing; lock, retirement and dispose stop it through uiAllowed,
    // retired and disposed. Started and stopped imperatively, like the
    // backlight monitor above, so a C++-side write of `running` never
    // replaces a binding.
    property string spectrumPath: Qt.resolvedUrl("libexec/nookisle-spectrum").toString()
    // 15 lines a second, not the binary's 30. Each line costs the shell one
    // repaint, about 1 ms of CPU whatever the bars bind or the window's size,
    // so the line rate sets the collapsed-playing cost: 2.87 pp at 30 and
    // 2.13 at 20, both over the 2 pp budget.
    readonly property int spectrumFps: 15
    property var spectrumLevels: []
    // Written by Panel.qml from the closed notch's rendered bar geometry.
    property real spectrumBarSpan: 0
    // "off" | "running" | "unavailable" (missing binary, stream failure, or
    // retries exhausted until the next desired edge).
    property string spectrumState: "off"
    // Reduced motion shows a still glyph, so nothing is captured for it.
    readonly property bool spectrumDesired: visualizer && !reducedMotion && island && islandShowing && uiAllowed
        && !!selectedEndpoint && selectedEndpoint.status === "Playing" && !retired && !disposed
    readonly property bool spectrumRunning: spectrum.running
    readonly property var spectrumPid: spectrum.processId
    property bool spectrumStarted: false
    property bool spectrumExited: false
    property bool spectrumStopRequested: false
    property bool spectrumGaveUp: false
    property int spectrumRetryCount: 0
    property double spectrumRetryWindow: 0
    function startSpectrum() {
        if (!spectrumDesired || spectrumGaveUp || spectrum.running) return
        spectrumStarted = false
        spectrumExited = false
        spectrumStopRequested = false
        spectrum.command = [spectrumPath, "--fps", String(spectrumFps)]
        spectrum.running = true
    }
    function stopSpectrum() {
        spectrumRetry.stop()
        spectrumLevels = []
        if (spectrumState !== "unavailable") spectrumState = "off"
        if (spectrum.running) {
            spectrumStopRequested = true
            spectrum.running = false
        }
    }
    function giveUpSpectrum() {
        spectrumGaveUp = true
        spectrumLevels = []
        spectrumState = "unavailable"
    }
    // A valid line replaces the levels when it moves a rendered bar at least
    // one pixel, or when the bars are quiet and need to settle flat.
    function onSpectrumLine(line) {
        var levels = Spectrum.parse(line)
        if (!levels) return
        // Parsed but not drawn while the drawing island is open: its pill is
        // hidden then, and stopping the process on every hover would cost a
        // reconnect each time.
        if (spectrumPaused) return
        if (!Spectrum.shouldDraw(spectrumLevels, levels, spectrumBarSpan)) return
        spectrumLevels = levels
    }
    onSpectrumDesiredChanged: {
        if (spectrumDesired) {
            spectrumGaveUp = false
            spectrumRetryCount = 0
            Qt.callLater(startSpectrum)
        } else stopSpectrum()
    }
    Process {
        id: spectrum
        // Stderr has no parser, so it is closed: the binary reports failure
        // through its exit code alone.
        stdout: SplitParser {
            onRead: line => root.onSpectrumLine(line)
        }
        onStarted: {
            root.spectrumStarted = true
            if (root.spectrumDesired) root.spectrumState = "running"
        }
        onExited: (exitCode, exitStatus) => {
            root.spectrumExited = true
            root.spectrumLevels = []
            var requested = root.spectrumStopRequested
            root.spectrumStopRequested = false
            if (!root.spectrumDesired) {
                if (root.spectrumState !== "unavailable") root.spectrumState = "off"
                return
            }
            // Stopped on purpose and wanted again before it had exited (a
            // quick pause and play): start it again, not as a failure.
            if (requested) { Qt.callLater(root.startSpectrum); return }
            // 2 means the PipeWire stream itself failed; retrying cannot help.
            if (exitCode === 2) { root.giveUpSpectrum(); return }
            root.spectrumState = "off"
            var now = Date.now()
            if (now - root.spectrumRetryWindow >= 60000) {
                root.spectrumRetryWindow = now
                root.spectrumRetryCount = 0
            }
            if (root.spectrumRetryCount < 3) {
                spectrumRetry.interval = 1000 * Math.pow(2, root.spectrumRetryCount++)
                spectrumRetry.start()
            } else root.giveUpSpectrum()
        }
        onRunningChanged: {
            // A missing or non-executable binary never emits started or
            // exited: running drops back without either. A stop issued before
            // started is no longer desired, so it is never misread as that.
            if (!running && !root.spectrumStarted && !root.spectrumExited
                && !root.spectrumStopRequested && root.spectrumDesired)
                root.giveUpSpectrum()
        }
    }
    Timer { id: spectrumRetry; onTriggered: root.startSpectrum() }
    // File shelf clipboard round-trip. One-shot each, never queued: shelfPaste
    // and shelfCopy both refuse to start a second run while either is busy.
    Process {
        id: clipboardPaste
        onStarted: root.clipboardPasteStarted = true
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                // Capped and dropped past the cap rather than grown unbounded.
                var remaining = 131072 - root.clipboardPasteBuffer.length
                if (remaining <= 0) {
                    root.clipboardPasteTruncated = true
                    return
                }
                if (data.length > remaining) root.clipboardPasteTruncated = true
                root.clipboardPasteBuffer += data.slice(0, remaining)
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.clipboardPasteExited = true
            var text = root.clipboardPasteBuffer
            var truncated = root.clipboardPasteTruncated
            root.clipboardPasteBuffer = ""
            root.clipboardPasteTruncated = false
            var links = root.clipboardPasteType === "text/uri-list"
            if (exitCode !== 0) {
                // wl-paste fails for a type the clipboard does not offer: with
                // no file links, try its plain text once. The restart waits
                // for this handler to return; the flag keeps Ctrl+V busy.
                if (links) {
                    root.clipboardPasteFallback = true
                    Qt.callLater(root.startClipboardPaste, "text")
                } else {
                    root.shelfNotice = "clipboard-no-files"
                }
                return
            }
            var added = 0
            if (links) {
                // A cut-off last line still starts with "file:///" and would
                // otherwise pass normalize() as a truncated, wrong path
                // (code review L3).
                if (truncated) {
                    var lastBreak = Math.max(text.lastIndexOf("\n"), text.lastIndexOf("\r"))
                    text = lastBreak >= 0 ? text.slice(0, lastBreak) : ""
                }
                added = root.shelfAddCandidates(Shelf.fromUriList(text))
            } else if (!truncated) {
                // Text past the read cap is also past Shelf's text limit.
                added = root.shelfAddDrop([], text)
            }
            if (added === 0 && root.shelfNotice === "") root.shelfNotice = "clipboard-no-files"
        }
        onRunningChanged: {
            // A missing wl-paste binary never emits "started" or "exited":
            // the launch fails synchronously and running drops back to false
            // without either signal, which is what this distinguishes.
            if (!running && !clipboardPasteStarted && !clipboardPasteExited)
                root.shelfNotice = "clipboard-unavailable"
        }
    }
    Process {
        id: clipboardCopy
        // The payload travels on stdin, never on the command line (code
        // review M7): written once the process has started, then the write
        // side is closed so wl-copy sees EOF and serves the selection.
        stdinEnabled: true
        onStarted: {
            root.clipboardCopyStarted = true
            clipboardCopy.write(root.clipboardCopyPayload)
            clipboardCopy.stdinEnabled = false
        }
        onExited: (exitCode, exitStatus) => {
            root.clipboardCopyExited = true
            root.clipboardCopyPayload = ""
            if (exitCode !== 0) root.shelfNotice = "clipboard-unavailable"
        }
        onRunningChanged: {
            if (!running && !clipboardCopyStarted && !clipboardCopyExited)
                root.shelfNotice = "clipboard-unavailable"
        }
    }
    // A hung wl-paste/wl-copy (a frozen clipboard owner) must not disable
    // Paste/Copy forever: this single-shot, non-repeating timeout kills
    // whichever process is still running past its bound and reports why
    // (code review L2).
    Timer {
        id: clipboardTimeout
        interval: 5000
        running: clipboardPaste.running || clipboardCopy.running
        onTriggered: {
            if (clipboardPaste.running) clipboardPaste.signal(9)
            if (clipboardCopy.running) clipboardCopy.signal(9)
            root.shelfNotice = "clipboard-unavailable"
        }
    }
}
