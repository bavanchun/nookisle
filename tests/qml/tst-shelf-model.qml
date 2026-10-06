import QtQuick
import QtTest
import "../../qml/Shelf.js" as Shelf

// The typed shelf model: identity, order, limits, persistence salvage and
// the thumbnail and icon lookups, all pure.
TestCase {
    name: "ShelfModel"

    function add(items, candidates, limit) {
        return Shelf.addItems(items, candidates, { limit: limit, nextId: 1, now: 1000 })
    }

    function test_candidates_from_uris_text_and_drops() {
        compare(Shelf.fromUri("file:///home/u/a%20b.txt"), { kind: "file", uri: "file:///home/u/a%20b.txt" })
        compare(Shelf.fromUri("https://example.com/x?y=1"), { kind: "link", url: "https://example.com/x?y=1" })
        compare(Shelf.fromUri("HTTP://Example.com"), { kind: "link", url: "HTTP://Example.com" })
        for (var bad of ["ftp://x", "file://host/a", "javascript:alert(1)", "https://", "https://a b", "https://user@host/",
                         "http://x\nfile:///etc/passwd", "", null, 3])
            compare(Shelf.fromUri(bad), null, String(bad))
        compare(Shelf.fromText("  https://example.com/p  "), { kind: "link", url: "https://example.com/p" })
        compare(Shelf.fromText("file:///tmp/a.txt"), { kind: "file", uri: "file:///tmp/a.txt" })
        compare(Shelf.fromText("two words"), { kind: "text", text: "two words" })
        compare(Shelf.fromText("   "), null)
        compare(Shelf.fromText("x".repeat(Shelf.TEXT_LIMIT)).kind, "text")
        compare(Shelf.fromText("x".repeat(Shelf.TEXT_LIMIT + 1)), null)
        compare(Shelf.fromText("é".repeat(Shelf.TEXT_LIMIT / 2 + 1)), null, "the text limit counts UTF-8 bytes")
        compare(Shelf.fromDrop(["file:///a", "https://b.example"], "ignored"),
            [{ kind: "file", uri: "file:///a" }, { kind: "link", url: "https://b.example" }])
        compare(Shelf.fromDrop([], "note"), [{ kind: "text", text: "note" }])
        compare(Shelf.fromDrop(null, undefined), [])
        // A pasted uri-list keeps its web links as well as its files.
        compare(Shelf.fromUriList("# comment\r\nfile:///a\r\n\r\nhttps://example.org/x\r\nftp://y\r\n"),
            [{ kind: "file", uri: "file:///a" }, { kind: "link", url: "https://example.org/x" }, null])
        compare(Shelf.fromUriList(""), [])
    }

    function test_identity_keys_normalise_file_paths() {
        compare(Shelf.identity({ kind: "file", uri: "file:///a//b/./c/../d%20e/" }), "file:///a/b/d e")
        compare(Shelf.identity({ kind: "link", url: "https://x.example/" }), "link://https://x.example/")
        compare(Shelf.identity({ kind: "text", text: "hi" }), "text://hi")
        compare(Shelf.identity({ kind: "other" }), "")
        var result = add([], [{ kind: "file", uri: "file:///a/b.txt" }, { kind: "file", uri: "file:///a/./b.txt" },
            { kind: "file", uri: "file:///a//x/../b.txt" }, { kind: "text", text: "b" }, { kind: "text", text: "b" }])
        compare(result.items.length, 2)
        compare(result.added, 2)
        compare(result.rejected, 0, "duplicates are skipped, not rejected")
    }

    function test_items_keep_order_ids_and_only_their_fields() {
        var result = add([], [
            { kind: "text", text: "first line\nsecond", uri: "file:///smuggled", temp: true },
            { kind: "file", uri: "file:///tmp/a%20b.png", name: "  Custom  ", temp: true, extra: 1 },
            { kind: "link", url: "https://example.com/path", addedAt: 5 }])
        compare(result.ids, ["s1", "s2", "s3"])
        compare(result.nextId, 4)
        compare(result.items[0], { kind: "text", text: "first line\nsecond", name: "first line", id: "s1", addedAt: 1000, temp: false })
        compare(result.items[1], { kind: "file", uri: "file:///tmp/a%20b.png", name: "Custom", id: "s2", addedAt: 1000, temp: true })
        compare(result.items[2], { kind: "link", url: "https://example.com/path", name: "example.com/path", id: "s3", addedAt: 5, temp: false })
        compare(Shelf.fileUris(result.items), ["file:///tmp/a%20b.png"])
        compare(Shelf.findItem(result.items, "s3").kind, "link")
        compare(Shelf.removeItem(result.items, "s2").map(function(item) { return item.id }), ["s1", "s3"])
        compare(Shelf.makeItem({ kind: "file", uri: "file:///x", name: "bad\nname" }, "s9", 1).name, "x")
    }

    function test_limit_rejects_overflow_and_is_clamped() {
        compare(Shelf.limitOf(undefined), 64)
        compare(Shelf.limitOf(0), 64)
        compare(Shelf.limitOf(257), 64)
        compare(Shelf.limitOf(2.5), 64)
        compare(Shelf.limitOf(256), 256)
        var candidates = []
        for (var i = 0; i < 70; ++i) candidates.push({ kind: "text", text: "t" + i })
        var result = add([], candidates)
        compare(result.items.length, 64)
        compare(result.full, true)
        compare(result.rejected, 6)
        compare(result.items[63].text, "t63", "the earliest items are kept, overflow is never evicted in")
        var small = add([], candidates.slice(0, 3), 2)
        compare(small.items.length, 2)
        compare(small.full, true)
    }

    function test_rename_replaces_the_uri_in_place() {
        var items = add([], [{ kind: "file", uri: "file:///d/a.txt" }, { kind: "file", uri: "file:///d/b.txt" }]).items
        var renamed = Shelf.renameItem(items, "s1", "file:///d/c.txt")
        compare(renamed.map(function(item) { return item.uri }), ["file:///d/c.txt", "file:///d/b.txt"])
        compare(renamed[0].id, "s1")
        compare(renamed[0].name, "c.txt")
        compare(Shelf.renameItem(items, "s1", "file:///d/b.txt"), null, "a rename onto another shelved file is refused")
        compare(Shelf.renameItem(items, "s9", "file:///d/z.txt"), null)
        compare(Shelf.renameItem(items, "s1", "https://x.example"), null)
    }

    function test_serialise_drops_ids_and_temp_items() {
        var items = add([], [{ kind: "file", uri: "file:///a" }, { kind: "file", uri: "file:///tmp/z.zip", temp: true },
            { kind: "link", url: "https://l.example" }, { kind: "text", text: "t" }]).items
        compare(JSON.parse(Shelf.serialise(items)), { version: 1, items: [
            { kind: "file", name: "a", addedAt: 1000, uri: "file:///a" },
            { kind: "link", name: "l.example", addedAt: 1000, url: "https://l.example" },
            { kind: "text", name: "t", addedAt: 1000, text: "t" }] })
    }

    function test_salvage_keeps_each_valid_entry() {
        var text = JSON.stringify({ version: 1, items: [
            { kind: "file", uri: "file:///keep", name: "Keep", addedAt: 7 },
            { kind: "file", uri: "https://not-a-file" }, 7, null, [1], { kind: "text", text: "" },
            { kind: "text", text: "x".repeat(Shelf.TEXT_LIMIT + 1) }, { kind: "bogus" },
            { kind: "link", url: "https://keep.example", temp: true },
            { kind: "file", uri: "file:///keep" }] })
        var result = Shelf.salvage(text, { nextId: 10, now: 1 })
        compare(result.items.map(function(item) { return item.id + ":" + Shelf.identity(item) }),
            ["s10:file:///keep", "s11:link://https://keep.example"])
        compare(result.items[0].name, "Keep")
        compare(result.items[0].addedAt, 7)
        compare(result.items[1].temp, false, "a stored entry can never become a temp item")
        compare(result.dropped, 8)
        compare(result.nextId, 12)
        for (var bad of ["", "{ not json", "[]", "null", JSON.stringify({ version: 2, items: [{ kind: "text", text: "t" }] }),
                         JSON.stringify({ version: 1, items: "nope" })])
            compare(Shelf.salvage(bad, {}).items, [], bad)
        var many = []
        for (var i = 0; i < 10; ++i) many.push({ kind: "text", text: "n" + i })
        compare(Shelf.salvage(JSON.stringify({ version: 1, items: many }), { limit: 4 }).items.length, 4)
    }

    function test_thumbnail_lookup_uses_the_freedesktop_names() {
        // The example from the freedesktop thumbnail specification.
        compare(Shelf.thumbnailName("file:///home/jens/photos/me.png"), "c6ee772d9e49320e97ec29a7eb5b1697.png")
        compare(Shelf.thumbnailCandidates("/home/u/.cache", "file:///home/jens/photos/me.png"), [
            "/home/u/.cache/thumbnails/normal/c6ee772d9e49320e97ec29a7eb5b1697.png",
            "/home/u/.cache/thumbnails/large/c6ee772d9e49320e97ec29a7eb5b1697.png"])
        compare(Shelf.thumbnailCandidates("relative", "file:///a"), [])
        verify(Shelf.thumbnailable("image/png") && Shelf.thumbnailable("image/jpeg"))
        verify(!Shelf.thumbnailable("image/webp") && !Shelf.thumbnailable(undefined))
    }

    function test_mime_icons() {
        compare(Shelf.mimeIcons("image/png"), ["image-png", "image-x-generic"])
        compare(Shelf.mimeIcons("application/pdf"), ["application-pdf", "application-x-generic"])
        compare(Shelf.mimeIcons("text/x-python"), ["text-x-python", "text-x-generic"])
        compare(Shelf.mimeIcons("inode/directory"), ["folder"])
        compare(Shelf.mimeIcons("../../etc"), ["text-x-generic"])
        compare(Shelf.mimeIcons(undefined), ["text-x-generic"])
    }

    function test_local_paths() {
        compare(Shelf.localPath("file:///a%20b/c%23d.txt"), "/a b/c#d.txt")
        compare(Shelf.localPath("file:///a?query"), "")
        compare(Shelf.localPath("https://x"), "")
        compare(Shelf.localPath("file:///%00"), "")
    }

    function test_selection_rules() {
        var order = ["a", "b", "c", "d", "e"]
        var state = Shelf.selectClick(Shelf.emptySelection(), order, "b", {})
        compare(state, { selected: ["b"], anchor: "b" })
        state = Shelf.selectClick(state, order, "d", { ctrl: true })
        compare(state, { selected: ["b", "d"], anchor: "d" })
        state = Shelf.selectClick(state, order, "b", { ctrl: true })
        compare(state, { selected: ["d"], anchor: "b" }, "Ctrl toggles off and moves the anchor")
        state = Shelf.selectClick({ selected: ["b"], anchor: "b" }, order, "d", { shift: true })
        compare(state, { selected: ["b", "c", "d"], anchor: "b" })
        state = Shelf.selectClick(state, order, "a", { shift: true })
        compare(state, { selected: ["a", "b"], anchor: "b" }, "a new Shift range replaces the old one")
        state = Shelf.selectClick({ selected: ["e"], anchor: "b" }, order, "c", { shift: true, ctrl: true })
        compare(state, { selected: ["b", "c", "e"], anchor: "b" }, "Ctrl+Shift adds the range")
        compare(Shelf.selectClick({ selected: [], anchor: "gone" }, order, "c", { shift: true }), { selected: ["c"], anchor: "c" },
            "Shift without a live anchor selects one")
        compare(Shelf.selectClick({ selected: ["a"], anchor: "a" }, order, "zzz", {}), { selected: ["a"], anchor: "a" })
        compare(Shelf.pruneSelection({ selected: ["a", "x", "c"], anchor: "x" }, order), { selected: ["a", "c"], anchor: "" })
    }

    function test_drag_mime_data() {
        var items = add([], [{ kind: "file", uri: "file:///a%20b" }, { kind: "link", url: "https://l.example" },
            { kind: "text", text: "one" }, { kind: "text", text: "two" }]).items
        compare(Shelf.dragMimeData(items), { "text/uri-list": "file:///a%20b\r\nhttps://l.example\r\n", "text/plain": "one\ntwo" })
        compare(Shelf.dragMimeData(items.slice(0, 2)), { "text/uri-list": "file:///a%20b\r\nhttps://l.example\r\n",
            "text/plain": "https://l.example" }, "links fall back to plain text when there is no text item")
        compare(Shelf.dragMimeData(items.slice(0, 1)), { "text/uri-list": "file:///a%20b\r\n" })
        compare(Shelf.dragMimeData(items.slice(2, 3)), { "text/plain": "one" })
        compare(Shelf.dragMimeData([]), {})
    }

    function test_middle_elide() {
        compare(Shelf.middleElide("short.pdf", 20), "short.pdf")
        compare(Shelf.middleElide("a-very-long-report-name.pdf", 16), "a-very-l\u2026ame.pdf")
        compare(Shelf.middleElide("a-very-long-report-name.pdf", 16).length, 16)
        compare(Shelf.middleElide("abcdef", 1).length, 3)
        compare(Shelf.fileUrl("/a b/#?.txt"), "file:///a%20b/%23%3F.txt")
    }

    function test_menu_entries_depend_on_kind_selection_and_tools() {
        var items = add([], [{ kind: "file", uri: "file:///p/a.png" }, { kind: "file", uri: "file:///p/b.jpg" },
            { kind: "file", uri: "file:///p/c.txt" }, { kind: "link", url: "https://l.example" }, { kind: "text", text: "t" }]).items
        var mimes = { s1: "image/png", s2: "image/jpeg", s3: "text/plain" }
        var all = { "zip": true, "magick": true, "rembg": true }
        function actions(selection, context) {
            return Shelf.menuEntries(selection, context).map(function(entry) { return entry.separator ? "|" : entry.action })
        }
        compare(actions([items[0]], { tools: all, mimes: mimes, apps: [{ id: "org.gnome.Loupe.desktop", dir: "/d" }] }),
            ["open", "openWith", "showInFiles", "|", "copy", "copyPath", "|", "compress", "rename", "convert", "pdf",
             "removeBackground", "|", "share", "remove"])
        compare(actions([items[0], items[1]], { tools: all, mimes: mimes }),
            ["open", "|", "copy", "copyPath", "|", "compress", "convert", "pdf", "|", "share", "remove"],
            "several images: no single-item entries, still convert and PDF")
        compare(actions([items[0], items[2]], { tools: all, mimes: mimes }),
            ["open", "|", "copy", "copyPath", "|", "compress", "|", "share", "remove"], "a non-image blocks the image tools")
        compare(actions([items[0]], { tools: {}, mimes: mimes }),
            ["open", "showInFiles", "|", "copy", "copyPath", "|", "rename", "|", "share", "remove"], "missing tools hide their entries")
        compare(actions([items[3]], { tools: all }), ["open", "|", "copy", "|", "remove"])
        compare(actions([items[4]], { tools: all }), ["copy", "|", "remove"])
        compare(actions([items[3], items[4]], { tools: all }), ["copy", "|", "remove"], "text cannot be opened")
        compare(actions([], { tools: all }), [])
        var openWith = Shelf.menuEntries([items[0]], { apps: [{ id: "org.gnome.Loupe.desktop", dir: "/d" }, { id: "gimp.desktop", dir: "/d", name: "GIMP" }] })[1]
        compare(openWith.entries.map(function(entry) { return entry.label }), ["Loupe", "GIMP"])
        compare(openWith.entries[0].argument, { id: "org.gnome.Loupe.desktop", dir: "/d" })
        var convert = Shelf.menuEntries([items[0]], { tools: all, mimes: mimes }).filter(function(entry) { return entry.action === "convert" })[0]
        compare(convert.entries.map(function(entry) { return entry.argument }), ["png", "jpeg", "webp"])
    }
}
