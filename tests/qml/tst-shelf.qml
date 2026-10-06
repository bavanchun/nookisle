import QtQuick
import QtTest
import "../../qml/Shelf.js" as Shelf

TestCase {
    id: test
    name: "Shelf"
    width: 384
    height: 260
    when: windowShown
    visible: true

    function test_normalizeAcceptsOnlyLocalFileUris() {
        compare(Shelf.normalize("  file:///tmp/a.txt \n".replace("\n", "")), "file:///tmp/a.txt");
        compare(Shelf.normalize("http://example.com/a"), "");
        compare(Shelf.normalize("tmp/a.txt"), "");
        compare(Shelf.normalize("file://host/a.txt"), "");
        compare(Shelf.normalize("file:///tmp/a\r\nfile:///etc/passwd"), "");
        compare(Shelf.normalize("file:///tmp/a\u0000b"), "");
        compare(Shelf.normalize(null), "");
    }
    function test_normalizeBoundsLength() {
        var base = "file:///";
        var fits = base + new Array(4096 - base.length + 1).join("a");
        compare(Shelf.normalize(fits), fits);
        compare(Shelf.normalize(fits + "a"), "");
    }
    function test_addDedupesAndKeepsOrder() {
        var result = Shelf.add([], ["file:///b", "file:///a", "file:///b", "http://x"]);
        compare(result.items, ["file:///b", "file:///a"]);
        compare(result.added, 2);
        compare(result.rejected, 1);
        verify(!result.full);
    }
    function test_addRejectsOverflowInsteadOfEvicting() {
        var items = [];
        for (var i = 0; i < Shelf.LIMIT; ++i)
            items.push("file:///f" + i);
        var result = Shelf.add(items, ["file:///extra"]);
        compare(result.items.length, 24);
        compare(result.items[0], "file:///f0");
        verify(result.full);
        compare(result.added, 0);
    }
    function test_removeAndDisplayName() {
        compare(Shelf.remove(["file:///a", "file:///b"], "file:///a"), ["file:///b"]);
        compare(Shelf.displayName("file:///tmp/a%20b.txt"), "a b.txt");
        compare(Shelf.displayName("file:///tmp/dir/"), "dir");
        compare(Shelf.displayName("file:///tmp/%E0%A4%A.txt"), "%E0%A4%A.txt");
    }
    function test_uriListRoundTrip() {
        var parsed = Shelf.parseUriList("# comment\r\nfile:///a\r\n\r\nfile:///b%20c\r\nftp://x\r\n");
        compare(parsed, ["file:///a", "file:///b%20c", ""]);
        compare(Shelf.toUriList(["file:///a", "file:///b"]), "file:///a\r\nfile:///b\r\n");
        compare(Shelf.toUriList([]), "");
        compare(Shelf.parseUriList(Shelf.toUriList(["file:///a"])), ["file:///a"]);
    }
}
