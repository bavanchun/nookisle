import QtQuick
import Quickshell
import Quickshell.Io
import "../qml/Shelf.js" as Shelf

// Every process the shelf starts, in two halves.
//
// The builders are pure: they turn absolute paths into a command spec
// {argv, cwd, detached, interactive, output} or null, and never run anything,
// so the tests check the exact argument arrays. Commands are always argument
// arrays, never a shell line. Tools that accept "--" get it before their file
// operands; the others (xdg-open, gtk-launch, gio, localsend, zenity, busctl)
// only ever receive absolute paths or URIs, which cannot start with "-".
//
// execute() runs a spec. Interactive GUI tools are started detached and never
// timed out. Everything else runs as a child process with a 30 s timeout and
// a capped stdout, and reports once through finished(job, status, exitCode,
// output) with status ok, failed, timeout, truncated or unavailable. The one
// exception is the file picker: its selection comes back on stdout, so it
// runs as a child that is capped but not timed out, because the user may take
// as long as they like to choose.
Item {
    id: root
    visible: false

    readonly property int timeoutMs: 30000
    readonly property int stdoutLimit: 65536
    readonly property var knownTools: ["localsend", "kdeconnect-cli", "zenity", "magick", "zip", "rembg",
        "gtk-launch", "gio", "xdg-mime", "xdg-open", "busctl", "wl-copy"]
    // Tool name -> true when it is on PATH. Filled once by `which`; a missing
    // `which` leaves it empty, and every optional action then stays hidden.
    property var tools: ({})
    property bool toolsReady: false
    // The mimeinfo.cache texts, user directory first: Open With reads them.
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property var applicationDirs: homeDir.charAt(0) === "/"
        ? [homeDir + "/.local/share/applications", "/usr/share/applications"] : ["/usr/share/applications"]
    property int jobCounter: 0
    property var jobs: ({})
    signal finished(string job, string status, int exitCode, string output)

    // ---- Pure helpers --------------------------------------------------

    function absolute(path) {
        return typeof path === "string" && path.charAt(0) === "/" && !/[\u0000]/.test(path)
    }
    function allAbsolute(paths) {
        if (!Array.isArray(paths) || paths.length === 0) return false
        for (var i = 0; i < paths.length; ++i)
            if (!absolute(paths[i])) return false
        return true
    }
    function baseName(path) {
        var parts = String(path).split("/").filter(function(part) { return part !== "" })
        return parts.length ? parts[parts.length - 1] : ""
    }
    function parentOf(path) {
        var index = String(path).replace(/\/+$/, "").lastIndexOf("/")
        return index > 0 ? String(path).slice(0, index) : "/"
    }
    function stem(name) {
        var dot = name.lastIndexOf(".")
        return dot > 0 ? name.slice(0, dot) : name
    }
    // A file URI for a local path, every segment percent-encoded.
    function pathToUri(path) {
        return Shelf.fileUrl(path)
    }
    // Rename input: one path segment, not "." or "..", not empty, no NUL.
    function validRename(name) {
        return typeof name === "string" && name !== "" && name !== "." && name !== ".."
            && name.indexOf("/") < 0 && name.indexOf("\u0000") < 0 && Shelf.byteLength(name) <= 255
    }
    // An output file in the shelf's temporary directory. stamp keeps two runs
    // from ever writing the same name, so no tool is asked to overwrite.
    function tempOutput(tempDir, base, stamp, extension) {
        if (!absolute(tempDir)) return ""
        var clean = String(base).replace(/[\u0000-\u001f\u007f\/]/g, "").slice(0, 120) || "shelf"
        return tempDir + "/" + clean + "-" + stamp + "." + extension
    }
    function withinTemp(tempDir, path) {
        if (!absolute(tempDir) || !absolute(path) || path.indexOf(tempDir + "/") !== 0) return false
        var name = path.slice(tempDir.length + 1)
        return name.indexOf("/") < 0 && name !== "." && name !== ".."
    }
    function resolveProvider(provider, available) {
        var have = available || {}
        if (provider === "localsend" || provider === "kdeconnect" || provider === "portal") return provider
        if (have["localsend"]) return "localsend"
        if (have["kdeconnect-cli"]) return "kdeconnect"
        return "portal"
    }
    // "[MIME Cache]" lines are "type/subtype=a.desktop;b.desktop;". caches is
    // [{dir, text}] in priority order; returns [{id, dir}] for one type, each
    // id once, from the first directory that lists it.
    function appsForMime(caches, mime) {
        var result = [], seen = {}
        if (typeof mime !== "string" || !/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/i.test(mime)) return result
        for (var i = 0; i < caches.length; ++i) {
            var lines = String(caches[i].text || "").split(/\r?\n/)
            for (var j = 0; j < lines.length; ++j) {
                if (lines[j].indexOf(mime + "=") !== 0) continue
                var ids = lines[j].slice(mime.length + 1).split(";")
                for (var k = 0; k < ids.length; ++k) {
                    if (!/^[A-Za-z0-9._-]+\.desktop$/.test(ids[k]) || seen[ids[k]]) continue
                    seen[ids[k]] = true
                    result.push({ id: ids[k], dir: caches[i].dir })
                }
            }
        }
        return result
    }
    // `which` output lines are absolute paths; their base names are the tools found.
    function parseTools(output) {
        var found = {}
        var lines = String(output).split("\n")
        for (var i = 0; i < lines.length; ++i) {
            var name = baseName(lines[i].trim())
            if (lines[i].trim().charAt(0) === "/" && knownTools.indexOf(name) >= 0) found[name] = true
        }
        return found
    }
    // zenity prints the chosen paths joined by newlines; only absolute ones count.
    function parseSelection(output) {
        return String(output).split("\n").filter(function(line) { return absolute(line) })
    }
    // The first line of `xdg-mime query filetype`, when it looks like a type.
    function parseMime(output) {
        var line = String(output).split("\n")[0].trim()
        return /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/i.test(line) ? line.toLowerCase() : ""
    }

    // ---- Pure command builders -------------------------------------------

    function toolsCommand() {
        return { argv: ["which"].concat(knownTools) }
    }
    function mimeCommand(path) {
        return absolute(path) ? { argv: ["xdg-mime", "query", "filetype", path] } : null
    }
    function openCommand(path) {
        return absolute(path) ? { argv: ["xdg-open", path], detached: true } : null
    }
    function fileSizeCommand(path) {
        return absolute(path) ? { argv: ["stat", "-c", "%s", "--", path] } : null
    }
    // A shelved web link, opened in the default browser.
    function openUrlCommand(url) {
        return Shelf.linkUrl(url) === url && url !== ""
            ? { argv: ["xdg-open", url], detached: true } : null
    }
    // app is an entry of appsForMime: {id, dir}. gtk-launch needs only the
    // id; gio launch needs the .desktop file itself.
    function openWithCommand(app, path, available) {
        var have = available || {}
        var id = app && typeof app === "object" ? String(app.id) : ""
        if (!absolute(path) || !/^[A-Za-z0-9._-]+\.desktop$/.test(id)) return null
        if (have["gtk-launch"]) return { argv: ["gtk-launch", id, path], detached: true }
        if (have["gio"] && applicationDirs.indexOf(app.dir) >= 0)
            return { argv: ["gio", "launch", app.dir + "/" + id, path], detached: true }
        return null
    }
    // The file manager's D-Bus method selects the item; its fallback opens the folder.
    function showInFilesCommand(path) {
        return absolute(path) ? { argv: ["busctl", "--user", "call", "org.freedesktop.FileManager1",
            "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "ShowItems", "ass", "1",
            pathToUri(path), ""] } : null
    }
    function showFolderCommand(path) {
        return absolute(path) ? { argv: ["xdg-open", parentOf(path)], detached: true } : null
    }
    // Items that share one folder are zipped by relative name from there.
    // Distinct parents use junked paths only when every operand is known to be
    // a regular file; recursion is needed for folders and unknown types.
    function compressCommand(paths, tempDir, stamp, allRegular) {
        if (!allAbsolute(paths)) return null
        var parent = parentOf(paths[0])
        var shared = paths.every(function(path) { return parentOf(path) === parent })
        var base = paths.length === 1 ? stem(baseName(paths[0])) : "Shelf"
        var output = tempOutput(tempDir, base, stamp, "zip")
        if (!output) return null
        if (shared)
            return { argv: ["zip", "-q", "-r", output, "--"].concat(paths.map(baseName)), cwd: parent, output: output }
        var mode = allRegular === true ? "-j" : "-r"
        return { argv: ["zip", "-q", mode, output, "--"].concat(paths), output: output }
    }
    // --update=none-fail: an existing target fails the rename instead of
    // being replaced or silently skipped. -T (--no-target-directory): an
    // existing folder of that name is a target too, never a folder to move
    // the item into. A rename creates no output: `target` is where the item
    // goes, and a failed rename must never delete it, since it may be
    // another shelved file.
    function renameCommand(path, name) {
        if (!absolute(path) || !validRename(name)) return null
        var target = parentOf(path).replace(/\/$/, "") + "/" + name
        if (target === path) return null
        return { argv: ["mv", "-T", "--update=none-fail", "--", path, target], target: target }
    }
    // Each input is read as its first frame ("[0]"): an animated GIF or a
    // multi-page image would otherwise make ImageMagick write one numbered
    // file per frame, none of them at the output path the shelf adds. A path
    // already ending in "[...]" would be read as frame syntax, so it is refused.
    function firstFrame(path) { return path + "[0]" }
    function convertCommand(path, format, tempDir, stamp) {
        var extension = { png: "png", jpeg: "jpg", webp: "webp" }[format]
        if (!absolute(path) || !extension || /\]$/.test(path)) return null
        var output = tempOutput(tempDir, stem(baseName(path)), stamp, extension)
        return output ? { argv: ["magick", "--", firstFrame(path), "-quality", "85", output], output: output } : null
    }
    function pdfCommand(paths, tempDir, stamp) {
        if (!allAbsolute(paths) || paths.some(function(path) { return /\]$/.test(path) })) return null
        var output = tempOutput(tempDir, paths.length === 1 ? stem(baseName(paths[0])) : "Shelf", stamp, "pdf")
        return output ? { argv: ["magick", "--"].concat(paths.map(firstFrame), [output]), output: output } : null
    }
    function removeBackgroundCommand(path, tempDir, stamp, available) {
        if (!(available || {})["rembg"] || !absolute(path)) return null
        var output = tempOutput(tempDir, stem(baseName(path)) + "-cutout", stamp, "png")
        return output ? { argv: ["rembg", "i", path, output], output: output } : null
    }
    function shareCommands(provider, paths, available) {
        if (!allAbsolute(paths)) return []
        var chosen = resolveProvider(provider, available)
        if (chosen === "localsend") return [{ argv: ["localsend"].concat(paths), detached: true }]
        // KDE Connect needs a device: the first step lists the reachable ones,
        // and kdeconnectShareCommands sends to the first of them.
        if (chosen === "kdeconnect") return [{ argv: ["kdeconnect-cli", "--list-available", "--id-only"], devices: true }]
        return [{ argv: ["xdg-open", parentOf(paths[0])], detached: true }]
    }
    function parseDevice(output) {
        var line = String(output).split("\n")[0].trim()
        return /^[A-Za-z0-9_][A-Za-z0-9_-]{0,127}$/.test(line) ? line : ""
    }
    function kdeconnectShareCommands(device, paths) {
        if (!/^[A-Za-z0-9_][A-Za-z0-9_-]{0,127}$/.test(String(device)) || !allAbsolute(paths)) return []
        return paths.map(function(path) { return { argv: ["kdeconnect-cli", "-d", device, "--share", pathToUri(path)] } })
    }
    function pickerCommand(available) {
        return (available || {})["zenity"]
            ? { argv: ["zenity", "--file-selection", "--multiple", "--separator=\n"], interactive: true } : null
    }
    // detached: at unload, when a child process would die with the plugin.
    function removeTempCommand(tempDir, path, detached) {
        return withinTemp(tempDir, path) ? { argv: ["rm", "-f", "--", path], detached: detached === true } : null
    }
    // find's own -name takes a glob, so the kept names are escaped.
    function pruneCommand(tempDir, keepNames) {
        if (!absolute(tempDir)) return null
        var argv = ["find", tempDir, "-mindepth", "1", "-maxdepth", "1", "-type", "f"]
        for (var i = 0; i < keepNames.length; ++i)
            argv.push("!", "-name", String(keepNames[i]).replace(/([*?\[\]\\])/g, "\\$1"))
        return { argv: argv.concat(["-delete"]) }
    }

    // ---- Execution ------------------------------------------------------

    // Runs a spec from a builder. Returns the job id, "detached" for a
    // detached launch, or "" when there is nothing to run.
    function execute(spec, stdin) {
        if (!spec || !Array.isArray(spec.argv) || spec.argv.length === 0) return ""
        if (spec.detached) {
            Quickshell.execDetached(spec.cwd ? { command: spec.argv, workingDirectory: spec.cwd } : spec.argv)
            return "detached"
        }
        return run(spec.argv, { cwd: spec.cwd, stdin: stdin, timeoutMs: spec.interactive ? 0 : timeoutMs })
    }
    // options: cwd, stdin (text written then closed), timeoutMs (0 = none), limit.
    function run(argv, options) {
        var opts = options || {}
        if (!Array.isArray(argv) || argv.length === 0) return ""
        for (var i = 0; i < argv.length; ++i)
            if (typeof argv[i] !== "string") return ""
        var job = "job" + (++jobCounter)
        var object = jobComponent.createObject(root, {
            job: job, argv: argv.slice(), cwd: typeof opts.cwd === "string" ? opts.cwd : "",
            payload: typeof opts.stdin === "string" ? opts.stdin : null,
            limit: Number.isInteger(opts.limit) && opts.limit > 0 ? Math.min(opts.limit, stdoutLimit) : stdoutLimit,
            deadlineMs: opts.timeoutMs === 0 ? 0 : (Number.isInteger(opts.timeoutMs) && opts.timeoutMs > 0 ? opts.timeoutMs : timeoutMs)
        })
        if (!object) return ""
        var next = Object.assign({}, jobs)
        next[job] = object
        jobs = next
        object.start()
        return job
    }
    function complete(object, status, exitCode) {
        if (object.done) return
        object.done = true
        var next = Object.assign({}, jobs)
        delete next[object.job]
        jobs = next
        var output = object.output
        finished(object.job, status, exitCode, output)
        object.destroy()
    }
    function cancelAll() {
        for (var job in jobs) {
            var object = jobs[job]
            if (object.running) object.kill()
            complete(object, "failed", -1)
        }
    }
    function openWithApps(mime) {
        var caches = [{ dir: "/usr/share/applications", text: systemMimeCache.text() }]
        if (applicationDirs.length > 1) caches.unshift({ dir: applicationDirs[0], text: userMimeCache.text() })
        return appsForMime(caches, mime)
    }

    Component.onCompleted: {
        var probe = toolsCommand()
        toolsJob = run(probe.argv, { timeoutMs: 5000 })
    }
    Component.onDestruction: cancelAll()
    property string toolsJob: ""
    onFinished: (job, status, exitCode, output) => {
        if (job !== toolsJob) return
        // which exits non-zero when any one tool is missing; its output still
        // lists every tool it found.
        tools = parseTools(output)
        toolsReady = true
    }

    FileView {
        id: userMimeCache
        path: root.applicationDirs.length > 1 ? root.applicationDirs[0] + "/mimeinfo.cache" : ""
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: systemMimeCache
        path: "/usr/share/applications/mimeinfo.cache"
        blockLoading: true
        printErrors: false
    }

    Component {
        id: jobComponent
        Item {
            id: task
            visible: false
            property string job: ""
            property var argv: []
            property string cwd: ""
            property var payload: null
            property int limit: 65536
            property int deadlineMs: 30000
            property string output: ""
            property bool truncated: false
            property bool started: false
            property bool exited: false
            property bool done: false
            readonly property bool running: process.running
            function start() {
                process.command = argv
                if (cwd) process.workingDirectory = cwd
                process.stdinEnabled = payload !== null
                process.running = true
                if (deadlineMs > 0) deadline.start()
            }
            function kill() {
                if (process.running) process.signal(9)
            }
            function take(data) {
                if (truncated) return
                var room = limit - output.length
                if (data.length > room) {
                    output += data.slice(0, Math.max(0, room))
                    truncated = true
                    kill()
                    return
                }
                output += data
            }
            Process {
                id: process
                stdout: SplitParser {
                    splitMarker: ""
                    onRead: data => task.take(data)
                }
                onStarted: {
                    task.started = true
                    if (task.payload !== null) {
                        process.write(task.payload)
                        process.stdinEnabled = false
                    }
                }
                onExited: (exitCode, exitStatus) => {
                    task.exited = true
                    deadline.stop()
                    root.complete(task, task.truncated ? "truncated" : task.timedOut ? "timeout"
                        : exitCode === 0 ? "ok" : "failed", exitCode)
                }
                onRunningChanged: {
                    // A missing binary never emits started or exited: the
                    // launch fails and running drops back to false.
                    if (!running && !task.started && !task.exited) {
                        deadline.stop()
                        root.complete(task, "unavailable", -1)
                    }
                }
            }
            property bool timedOut: false
            Timer {
                id: deadline
                interval: Math.max(1, task.deadlineMs)
                onTriggered: {
                    task.timedOut = true
                    task.kill()
                }
            }
        }
    }
}
