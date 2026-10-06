import QtQuick
import Quickshell
import "../../components"

// ShelfActions under Quickshell itself, since its Process and execDetached
// types exist only there. The builders are pure, so their exact argument
// arrays are checked without running anything; the runner is checked with
// real, harmless processes (sleep, yes, printf, cat, pwd, a missing binary).
// Prints SHELF_ACTIONS_RESULT failures=N and quits.
ShellRoot {
    id: test
    property int failures: 0
    property string current: ""
    function report(ok, message) {
        if (ok) console.log("PASS " + current + ": " + message)
        else { failures++; console.error("FAIL " + current + ": " + message) }
    }
    function same(actual, expected, message) {
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        report(ok, (message || "") + (ok ? "" : " got " + JSON.stringify(actual) + " expected " + JSON.stringify(expected)))
    }
    function truthy(value, message) { report(!!value, message || "expected true") }

    ShelfActions { id: actions }
    readonly property var everyTool: ({ "localsend": true, "kdeconnect-cli": true, "zenity": true, "magick": true,
        "zip": true, "rembg": true, "gtk-launch": true, "gio": true })

    function test_open_and_show_in_files() {
        same(actions.openCommand("/home/u/a b.pdf"), { argv: ["xdg-open", "/home/u/a b.pdf"], detached: true })
        same(actions.openCommand("relative.pdf"), null)
        same(actions.openCommand("-rf"), null)
        same(actions.openUrlCommand("https://example.com/a b"), null, "only a clean http(s) link is opened")
        same(actions.openUrlCommand("https://example.com/a"), { argv: ["xdg-open", "https://example.com/a"], detached: true })
        same(actions.openUrlCommand("file:///etc/passwd"), null)
        same(actions.openUrlCommand("https://example.com/a?q=1"),
            { argv: ["xdg-open", "https://example.com/a?q=1"], detached: true })
        same(actions.openUrlCommand("javascript:alert(1)"), null)
        same(actions.openUrlCommand("https://example.com/\n--help"), null)
        same(actions.showInFilesCommand("/home/u/a b#1.pdf").argv,
            ["busctl", "--user", "call", "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
             "org.freedesktop.FileManager1", "ShowItems", "ass", "1", "file:///home/u/a%20b%231.pdf", ""])
        truthy(!actions.showInFilesCommand("/a").detached)
        same(actions.showFolderCommand("/home/u/a.pdf"), { argv: ["xdg-open", "/home/u"], detached: true })
        same(actions.fileSizeCommand("/home/u/a.pdf"), { argv: ["stat", "-c", "%s", "--", "/home/u/a.pdf"] })
        same(actions.fileSizeCommand("relative.pdf"), null)
    }

    function test_open_with_prefers_gtk_launch_and_checks_the_desktop_id() {
        var loupe = { id: "org.gnome.Loupe.desktop", dir: "/usr/share/applications" }
        same(actions.openWithCommand(loupe, "/p/a.png", everyTool),
            { argv: ["gtk-launch", "org.gnome.Loupe.desktop", "/p/a.png"], detached: true })
        same(actions.openWithCommand(loupe, "/p/a.png", { "gio": true }),
            { argv: ["gio", "launch", "/usr/share/applications/org.gnome.Loupe.desktop", "/p/a.png"], detached: true },
            "gio launches the .desktop file from the directory that listed it")
        same(actions.openWithCommand({ id: "a.desktop", dir: "/tmp/elsewhere" }, "/p/a.png", { "gio": true }), null,
            "gio never launches a .desktop file from an unknown directory")
        same(actions.openWithCommand({ id: "../evil.desktop", dir: "/usr/share/applications" }, "/p/a.png", everyTool), null)
        same(actions.openWithCommand({ id: "app.desktop --x" }, "/p/a.png", everyTool), null)
        same(actions.openWithCommand("app.desktop", "/p/a.png", everyTool), null)
        same(actions.openWithCommand(loupe, "/p/a.png", {}), null)
    }

    function test_apps_come_from_mimeinfo_caches_in_order() {
        var user = { dir: "/home/u/.local/share/applications", text: "[MIME Cache]\nimage/png=mine.desktop;shared.desktop;\n" }
        var system = { dir: "/usr/share/applications",
            text: "[MIME Cache]\nimage/png=shared.desktop;system.desktop;bad id.desktop;\nimage/pngx=other.desktop;\n" }
        same(actions.appsForMime([user, system], "image/png"), [
            { id: "mine.desktop", dir: user.dir }, { id: "shared.desktop", dir: user.dir },
            { id: "system.desktop", dir: system.dir }])
        same(actions.appsForMime([user, system], "text/plain"), [])
        same(actions.appsForMime([user], "image/png=mine.desktop;"), [])
    }

    function test_compress_uses_zip_with_double_dash_into_the_temp_directory() {
        var shared = actions.compressCommand(["/home/u/Docs/a.txt", "/home/u/Docs/Folder"], "/run/user/1/nookisle/shelf", 42)
        same(shared.argv, ["zip", "-q", "-r", "/run/user/1/nookisle/shelf/Shelf-42.zip", "--", "a.txt", "Folder"])
        same(shared.cwd, "/home/u/Docs")
        same(shared.output, "/run/user/1/nookisle/shelf/Shelf-42.zip")
        var spread = actions.compressCommand(["/a/one.txt", "/b/two.txt"], "/t", 7, true)
        same(spread.argv, ["zip", "-q", "-j", "/t/Shelf-7.zip", "--", "/a/one.txt", "/b/two.txt"])
        var folders = actions.compressCommand(["/a/DirA", "/b/DirB"], "/t", 8)
        same(folders.argv, ["zip", "-q", "-r", "/t/Shelf-8.zip", "--", "/a/DirA", "/b/DirB"])
        same(actions.compressCommand(["/a/report.pdf"], "/t", 1).output, "/t/report-1.zip")
        same(actions.compressCommand([], "/t", 1), null)
        same(actions.compressCommand(["/a/x"], "relative", 1), null)
    }

    function test_rename_rejects_unsafe_names_and_never_overwrites() {
        same(actions.renameCommand("/home/u/a.txt", "b.txt"),
            { argv: ["mv", "-T", "--update=none-fail", "--", "/home/u/a.txt", "/home/u/b.txt"], target: "/home/u/b.txt" })
        // A rename writes no new file, so there is no output a failure could discard.
        same(actions.renameCommand("/run/user/1/nookisle/shelf/a-1.zip", "b-2.png").output, undefined)
        for (var name of ["", ".", "..", "a/b", "/abs", "x\u0000y"])
            same(actions.renameCommand("/home/u/a.txt", name), null, JSON.stringify(name))
        same(actions.renameCommand("/home/u/a.txt", "a.txt"), null)
        truthy(actions.validRename("-leading dash is a valid name"))
        same(actions.renameCommand("/a.txt", "-n").argv, ["mv", "-T", "--update=none-fail", "--", "/a.txt", "/-n"])
    }

    function test_image_tools_write_new_files_in_the_temp_directory() {
        same(actions.convertCommand("/p/photo.png", "jpeg", "/t", 5).argv,
            ["magick", "--", "/p/photo.png[0]", "-quality", "85", "/t/photo-5.jpg"])
        same(actions.convertCommand("/p/photo.png", "webp", "/t", 5).output, "/t/photo-5.webp")
        same(actions.convertCommand("/p/photo.png", "gif", "/t", 5), null)
        same(actions.convertCommand("/p/photo.png[0]", "png", "/t", 5), null)
        same(actions.pdfCommand(["/p/a.png", "/p/b.jpg"], "/t", 9).argv,
            ["magick", "--", "/p/a.png[0]", "/p/b.jpg[0]", "/t/Shelf-9.pdf"])
        same(actions.pdfCommand(["/p/a.png", "/p/b[1]"], "/t", 9), null)
        same(actions.removeBackgroundCommand("/p/a.png", "/t", 3, {}), null)
        same(actions.removeBackgroundCommand("/p/a.png", "/t", 3, everyTool).argv, ["rembg", "i", "/p/a.png", "/t/a-cutout-3.png"])
    }

    function test_share_provider_choice() {
        same(actions.resolveProvider("auto", everyTool), "localsend")
        same(actions.resolveProvider("auto", { "kdeconnect-cli": true }), "kdeconnect")
        same(actions.resolveProvider("auto", {}), "portal")
        same(actions.resolveProvider("kdeconnect", {}), "kdeconnect")
        same(actions.shareCommands("auto", ["/p/a b.png", "/p/c.png"], everyTool),
            [{ argv: ["localsend", "/p/a b.png", "/p/c.png"], detached: true }])
        same(actions.shareCommands("kdeconnect", ["/p/a b.png"], {}),
            [{ argv: ["kdeconnect-cli", "--list-available", "--id-only"], devices: true }])
        same(actions.parseDevice("a1b2_c3\nother\n"), "a1b2_c3")
        same(actions.parseDevice("--help\n"), "")
        same(actions.kdeconnectShareCommands("a1b2_c3", ["/p/a b.png", "/p/c.png"]), [
            { argv: ["kdeconnect-cli", "-d", "a1b2_c3", "--share", "file:///p/a%20b.png"] },
            { argv: ["kdeconnect-cli", "-d", "a1b2_c3", "--share", "file:///p/c.png"] }])
        same(actions.kdeconnectShareCommands("-x", ["/p/a.png"]), [])
        same(actions.shareCommands("portal", ["/p/a.png"], {}), [{ argv: ["xdg-open", "/p"], detached: true }])
        same(actions.shareCommands("auto", ["relative"], everyTool), [])
        same(actions.pickerCommand({}), null)
        truthy(actions.pickerCommand(everyTool).interactive)
        same(actions.parseSelection("/a/b.png\n/c d.txt\nnot absolute\n"), ["/a/b.png", "/c d.txt"])
    }

    function test_temp_cleanup_stays_inside_the_temp_directory() {
        same(actions.removeTempCommand("/t/shelf", "/t/shelf/a.zip"), { argv: ["rm", "-f", "--", "/t/shelf/a.zip"], detached: false })
        same(actions.removeTempCommand("/t/shelf", "/t/shelf/a.zip", true).detached, true, "unload removal outlives the plugin")
        same(actions.removeTempCommand("/t/shelf", "/t/shelf/../x"), null)
        same(actions.removeTempCommand("/t/shelf", "/t/shelf/..photo-1.zip").argv,
            ["rm", "-f", "--", "/t/shelf/..photo-1.zip"], "a valid name beginning with dots can be cleaned up")
        same(actions.removeTempCommand("/t/shelf", "/t/shelf/sub/x"), null)
        same(actions.removeTempCommand("/t/shelf", "/t/other/a.zip"), null)
        same(actions.pruneCommand("/t/shelf", ["a.zip", "b[1]*.png"]).argv,
            ["find", "/t/shelf", "-mindepth", "1", "-maxdepth", "1", "-type", "f",
             "!", "-name", "a.zip", "!", "-name", "b\\[1\\]\\*.png", "-delete"])
    }

    function test_parsers() {
        same(actions.parseTools("/usr/bin/zip\n/usr/bin/magick\nwhich: no rembg\n/usr/bin/unknown\n"), { "zip": true, "magick": true })
        same(actions.parseMime("image/png\n"), "image/png")
        same(actions.parseMime("error: no such file\n"), "")
        same(actions.pathToUri("/a b/#?%.txt"), "file:///a%20b/%23%3F%25.txt")
        same(actions.mimeCommand("/a.txt").argv, ["xdg-mime", "query", "filetype", "/a.txt"])
    }


    // ---- Runner ---------------------------------------------------------
    property var expected: ({})
    property var outcomes: ({})
    property var zipSpec: null
    property string zipFixture: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/zip-fixture"
    // An animated GIF, converted and turned into a PDF in a temp directory.
    property string frameFixture: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/frame-fixture"
    property var frameSpecs: []
    // A shelved file beside a folder, a file and a free name.
    property string renameFixture: (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/rename-fixture"
    Connections {
        target: actions
        function onFinished(job, status, exitCode, output) {
            if (!(job in test.expected)) return
            var next = Object.assign({}, test.outcomes)
            next[job] = { status: status, exitCode: exitCode, output: output }
            test.outcomes = next
            if (test.expected[job] === "zip")
                test.expect(actions.run(["unzip", "-Z1", test.zipSpec.output]), "archive")
            if ((test.expected[job] === "convertFrames" || test.expected[job] === "pdfFrames")
                && Object.keys(next).filter(function(id) { return /Frames$/.test(test.expected[id]) }).length === 2)
                test.expect(actions.run(["find", test.frameFixture + "/out", "-type", "f", "-printf", "%p\n"]), "frameTree")
            // Once both refused renames have answered, list what is left.
            if ((test.expected[job] === "renameOntoFolder" || test.expected[job] === "renameOntoFile")
                && Object.keys(next).filter(function(id) { return test.expected[id].indexOf("renameOnto") === 0 }).length === 2)
                test.expect(actions.run(["find", test.renameFixture, "-type", "f", "-printf", "%P\n"]), "renameTree")
            if (Object.keys(next).length === Object.keys(test.expected).length) test.finish()
        }
    }
    function expect(job, name) {
        truthy(job !== "" && job !== "detached", name + " starts")
        var next = Object.assign({}, expected)
        next[job] = name
        expected = next
    }
    function startRunner() {
        current = "runner"
        same(actions.run([]), "", "an empty command is refused")
        same(actions.run(["echo", 1]), "", "a non-string argument is refused")
        same(actions.execute(null), "", "a missing spec runs nothing")
        expect(actions.run(["sleep", "5"], { timeoutMs: 200 }), "timeout")
        expect(actions.run(["yes"], { limit: 1000 }), "cap")
        expect(actions.run(["printf", "%s", "--"]), "output")
        expect(actions.run(["false"]), "exit")
        expect(actions.run(["nookisle-no-such-binary"]), "missing")
        expect(actions.run(["cat"], { stdin: "payload" }), "stdin")
        expect(actions.run(["pwd"], { cwd: "/tmp" }), "cwd")
        expect(actions.execute({ argv: ["sleep", "5"], interactive: true }), "interactive")
        zipSpec = actions.compressCommand([zipFixture + "/left/DirA", zipFixture + "/right/DirB"], zipFixture, 42)
        expect(actions.execute(zipSpec), "zip")
        expect(actions.execute(actions.renameCommand(renameFixture + "/foo.txt", "Documents")), "renameOntoFolder")
        expect(actions.execute(actions.renameCommand(renameFixture + "/foo.txt", "taken.txt")), "renameOntoFile")
        frameSpecs = [actions.convertCommand(frameFixture + "/anim.gif", "png", frameFixture + "/out", 7),
            actions.pdfCommand([frameFixture + "/anim.gif"], frameFixture + "/out", 8)]
        expect(actions.execute(frameSpecs[0]), "convertFrames")
        expect(actions.execute(frameSpecs[1]), "pdfFrames")
    }
    function finish() {
        var byName = {}
        for (var job in outcomes) byName[expected[job]] = outcomes[job]
        same(byName.timeout.status, "timeout", "a hung command is killed at its deadline")
        same(byName.cap.status, "truncated", "an endless stdout is cut at the cap and the process stopped")
        same(byName.cap.output.length, 1000, "the captured output is exactly the cap")
        same([byName.output.status, byName.output.output], ["ok", "--"], "stdout and a zero exit are reported")
        same(byName.exit.status, "failed", "a non-zero exit is reported")
        same(byName.missing.status, "unavailable", "a missing binary is reported, not left pending")
        same(byName.stdin.output, "payload", "stdin is written and closed")
        same(byName.cwd.output, "/tmp\n", "the working directory is honoured")
        same(byName.interactive.status, "failed", "an interactive job has no deadline and ends only when cancelled")
        same(byName.zip.status, "ok", "folders under different parents are compressed")
        same([byName.convertFrames.status, byName.pdfFrames.status], ["ok", "ok"], "an animated GIF converts and makes a PDF")
        same(byName.frameTree.output.split("\n").filter(String).sort(), [frameSpecs[0].output, frameSpecs[1].output].sort(),
            "each writes exactly the output the shelf adds, with no leftover frame files")
        same(byName.renameOntoFolder.status, "failed", "a rename onto an existing folder is refused")
        same(byName.renameOntoFile.status, "failed", "a rename onto an existing file is refused")
        same(byName.renameTree.output.split("\n").filter(String).sort(), ["foo.txt", "taken.txt"],
            "the file stayed put: nothing moved into the folder or over the other file")
        report(byName.archive.status === "ok" && byName.archive.output.indexOf("DirA/one.txt") >= 0
            && byName.archive.output.indexOf("DirB/two.txt") >= 0,
            "the archive contains the contents of both folders")
        done()
    }
    function done() {
        console.log("SHELF_ACTIONS_RESULT failures=" + failures)
        Qt.quit()
    }
    // The interactive job has no deadline, so it is cancelled once every
    // timed job has answered; if it had been timed out it would already have
    // reported "timeout" instead.
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            var pending = []
            for (var job in test.expected) if (!(job in test.outcomes)) pending.push(test.expected[job])
            test.same(pending, ["interactive"], "only the interactive job is still running after the timed ones")
            actions.cancelAll()
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { test.report(false, "deadline"); test.done() }
    }
    Component.onCompleted: {
        var names = []
        for (var key in test) if (key.indexOf("test_") === 0 && typeof test[key] === "function") names.push(key)
        names.sort()
        for (var i = 0; i < names.length; ++i) {
            current = names[i]
            test[names[i]]()
        }
        startRunner()
    }
}
