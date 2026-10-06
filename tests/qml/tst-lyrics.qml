import QtQuick
import QtTest
import "../../components"
import "../../qml/Lyrics.js" as Lyrics
// Written by lyrics-fixture-server.py, which run-lyrics.sh starts first.
import "../../build/lyrics-fixture/port.js" as Fixture

TestCase {
    id: test
    name: "Lyrics"
    when: windowShown
    visible: true
    width: 10
    height: 10

    readonly property string base: "http://127.0.0.1:" + Fixture.port
    function url(route) {
        return base + "/api/" + route;
    }
    function track(title, lengthSeconds) {
        return {
            token: { owner: "fixture" },
            trackToken: { id: title || "Fixture Song" },
            status: "Playing",
            lengthSeconds: lengthSeconds === undefined ? 200 : lengthSeconds,
            presentation: {
                title: title || "Fixture Song",
                artists: ["Fixture Artist", "Guest"],
                album: "Fixture Album",
                hostApp: "Spotify"
            }
        };
    }

    // The fixture's request count, read through its own route: Qt refuses
    // file:// reads from QML XMLHttpRequest, so requests.log is for people.
    property int observed: -1
    function requestCount() {
        test.observed = -1;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                test.observed = Number(xhr.responseText);
        };
        xhr.open("GET", base + "/__requests");
        xhr.send();
        tryVerify(function () { return test.observed >= 0; }, 3000, "the fixture reports its request count");
        return test.observed;
    }

    Component {
        id: sourceComponent
        LyricsSource {
            lyricsEnabled: true
            wanted: false
        }
    }
    function makeSource(route, endpoint, extra) {
        var properties = { endpointUrl: url(route), endpoint: endpoint === undefined ? track() : endpoint };
        for (var key in extra)
            properties[key] = extra[key];
        var source = createTemporaryObject(sourceComponent, test, properties);
        verify(source);
        return source;
    }
    function openReady(route) {
        var source = makeSource(route || "get");
        source.wanted = true;
        tryCompare(source, "lyricsState", "ready", 3000);
        return source;
    }

    // Pure Lyrics.js.
    function test_parseBasicAndMultiTimestamp() {
        var parsed = Lyrics.parseLrc("[00:12.00][01:02.50]Chorus\n[00:05]Intro\n[00:30.125]Verse");
        compare(parsed.lines.length, 4);
        compare(parsed.lines.map(function (l) { return l.text; }), ["Intro", "Chorus", "Verse", "Chorus"]);
        fuzzyCompare(parsed.lines[0].t, 5, 1e-9);
        fuzzyCompare(parsed.lines[1].t, 12, 1e-9);
        fuzzyCompare(parsed.lines[2].t, 30.125, 1e-9);
        fuzzyCompare(parsed.lines[3].t, 62.5, 1e-9);
    }
    function test_parseOffsetShiftsEarlier() {
        var parsed = Lyrics.parseLrc("[offset:+500]\n[00:10.00]Line");
        compare(parsed.offset, 500);
        fuzzyCompare(parsed.lines[0].t, 9.5, 1e-9);
        fuzzyCompare(Lyrics.parseLrc("[offset:-250]\n[00:10.00]Line").lines[0].t, 10.25, 1e-9);
    }
    function test_parseIgnoresMetadataTags() {
        var parsed = Lyrics.parseLrc("[ar:Someone]\n[ti:Song]\n[al:Album]\n[by:me]\n[length:03:20]\nplain text\n[00:01.00]Only");
        compare(parsed.lines.length, 1);
        compare(parsed.lines[0].text, "Only");
    }
    function test_emptyLineIsNote() {
        var parsed = Lyrics.parseLrc("[00:01.00]A\n[00:02.00]\n[00:03.00]   ");
        compare(parsed.lines[1].text, "♪");
        compare(parsed.lines[2].text, "♪");
    }
    function test_parseBoundsInput() {
        var many = [];
        for (var i = 0; i < 2100; ++i)
            many.push("[00:01.00]" + (i === 0 ? new Array(700).join("x") : "l" + i));
        var parsed = Lyrics.parseLrc(many.join("\n"));
        compare(parsed.lines.length, 2000, "at most 2000 lines");
        compare(parsed.lines[0].text.length, 512, "each line at most 512 characters");
        compare(parsed.lines[1].text, "l1", "equal times keep their order");
        compare(Lyrics.parseLrc(null).lines.length, 0);
    }
    function test_byteLengthCountsUtf8() {
        compare(Lyrics.byteLength("abc"), 3);
        compare(Lyrics.byteLength("ó"), 2);
        compare(Lyrics.byteLength("ア"), 3);
        compare(Lyrics.byteLength("🎵"), 4, "a surrogate pair is one four-byte character");
        compare(Lyrics.byteLength(null), 0);
        verify(Lyrics.byteLength(new Array(1000).join("ア"), 10) <= 13, "counting stops past the limit");
    }
    function test_lineAtBoundaries() {
        var lines = [{ t: 10, text: "a" }, { t: 20, text: "b" }, { t: 30, text: "c" }];
        compare(Lyrics.lineAt(lines, 0), -1, "before the first line");
        compare(Lyrics.lineAt(lines, 9.8), -1, "just outside the lead");
        compare(Lyrics.lineAt(lines, 9.85), 0, "inside the lead");
        compare(Lyrics.lineAt(lines, 10), 0, "exactly on the boundary");
        compare(Lyrics.lineAt(lines, 19.9), 1);
        compare(Lyrics.lineAt(lines, 25), 1);
        compare(Lyrics.lineAt(lines, 500), 2, "after the last line");
        compare(Lyrics.lineAt([], 5), -1);
    }
    function test_lruOrderAndLimit() {
        var list = [];
        for (var i = 0; i < 17; ++i)
            list = Lyrics.lruPut(list, "k" + i, i, 16);
        compare(list.length, 16);
        compare(list[0].key, "k16");
        verify(!list.some(function (e) { return e.key === "k0"; }), "the oldest entry is evicted");
        var before = list;
        var got = Lyrics.lruGet(list, "k5");
        compare(got.hit, 5);
        compare(got.list[0].key, "k5", "a hit moves to the front");
        compare(got.list.length, 16);
        compare(before[0].key, "k16", "never mutates");
        compare(Lyrics.lruGet(list, "absent").hit, undefined);
        list = Lyrics.lruPut(got.list, "k9", 99, 16);
        compare(list.length, 16, "a re-put replaces, never duplicates");
        compare(list[0].value, 99);
        compare(Lyrics.lruDrop(list, "k9").length, 15);
    }
    function test_requestUrlEncodes() {
        var u = Lyrics.requestUrl("https://example.invalid/api/get",
            { title: "AC/DC & Friends", artist: "Sigur Rós", album: "", duration: 245 });
        compare(u, "https://example.invalid/api/get?track_name=AC%2FDC%20%26%20Friends&artist_name=Sigur%20R%C3%B3s&duration=245");
        verify(Lyrics.requestUrl("b", { title: "t", artist: "a", album: "x y", duration: 1 }).indexOf("&album_name=x%20y&") > 0);
    }
    function test_trackMetaUsesFirstArtist() {
        var meta = Lyrics.trackMeta(track("Song", 244.6));
        compare(meta.title, "Song");
        compare(meta.artist, "Fixture Artist");
        compare(meta.album, "Fixture Album");
        compare(meta.duration, 245);
        compare(Object.keys(meta).sort(), ["album", "artist", "duration", "title"], "nothing else is sent");
        var bare = track("Song");
        bare.presentation.artists = [];
        compare(Lyrics.trackMeta(bare), null);
        bare = track("Song");
        bare.presentation.title = "  ";
        compare(Lyrics.trackMeta(bare), null);
        compare(Lyrics.trackMeta(null), null);
        compare(Lyrics.cacheKey(Lyrics.trackMeta(track("Song "))), Lyrics.cacheKey(Lyrics.trackMeta(track("song"))));
    }
    function test_interpretStates() {
        compare(Lyrics.interpret(404, "").state, "none");
        verify(Lyrics.interpret(404, "").cache);
        compare(Lyrics.interpret(200, '{"instrumental":true}').state, "instrumental");
        var ready = Lyrics.interpret(200, JSON.stringify({ syncedLyrics: "[00:01.00]Hi" }));
        compare(ready.state, "ready");
        compare(ready.lines.length, 1);
        verify(ready.cache);
        compare(Lyrics.interpret(200, JSON.stringify({ syncedLyrics: null, plainLyrics: "words" })).state, "plain");
        compare(Lyrics.interpret(200, JSON.stringify({ syncedLyrics: "no timing", plainLyrics: "" })).state, "none");
        compare(Lyrics.interpret(200, "not json").state, "none");
        compare(Lyrics.interpret(200, "[1]").state, "none");
        var error = Lyrics.interpret(0, "");
        compare(error.state, "error");
        compare(error.code, "network");
        verify(!error.cache, "transport errors are never cached");
        compare(Lyrics.interpret(500, "").state, "error");
    }

    // LyricsSource against the local fixture.
    function test_fetchReady() {
        var before = requestCount();
        var source = openReady("get");
        compare(source.lines.length, 6);
        compare(source.lines[2].text, "♪");
        fuzzyCompare(source.lines[0].t, 0.5, 1e-9);
        compare(source.errorCode, "");
        compare(requestCount(), before + 1);
    }
    function test_currentIndexFollowsPosition() {
        var source = openReady("get");
        source.positionSeconds = 0;
        compare(source.currentIndex, -1);
        source.positionSeconds = 0.4;
        compare(source.currentIndex, 0);
        source.positionSeconds = 3.2;
        compare(source.currentIndex, 1);
        source.positionSeconds = 8.6;
        compare(source.currentIndex, 4);
        source.positionSeconds = 60;
        compare(source.currentIndex, 5);
    }
    function test_cacheHitMakesNoRequest() {
        var source = openReady("get");
        source.wanted = false;
        compare(source.lyricsState, "idle");
        var before = requestCount();
        source.wanted = true;
        compare(source.lyricsState, "ready", "a cached answer applies at once");
        compare(source.lines.length, 6);
        wait(150);
        compare(requestCount(), before);
    }
    function test_trackChangeWhileOpenLooksUpAgain() {
        var source = openReady("get");
        var before = requestCount();
        source.endpoint = track("Another Song");
        compare(source.lyricsState, "loading");
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 1);
        compare(source.cache.length, 2);
    }
    function test_skippingThroughTracksAsksOnce() {
        var source = openReady("get");
        var before = requestCount();
        source.endpoint = track("Skipped one");
        source.endpoint = track("Skipped two");
        wait(100);
        source.endpoint = track("Kept");
        compare(source.lyricsState, "loading");
        compare(source.active, null, "nothing is asked while the track settles");
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 1, "only the track that stays is looked up");
        compare(source.cache.length, 2);
    }
    function test_settleIsCancelledWhenLyricsTurnOff() {
        var source = openReady("get");
        var before = requestCount();
        source.endpoint = track("Changed then off");
        source.lyricsEnabled = false;
        wait(source.settleMs + 200);
        compare(source.lyricsState, "idle");
        compare(requestCount(), before, "a pending lookup dies with the setting");
    }
    function test_staleAnswerNeverReachesTheNextTrack() {
        var source = makeSource("get");
        source.wanted = true;
        verify(source.active !== null);
        var asked = Lyrics.cacheKey(Lyrics.trackMeta(track()));
        // Closed before the answer arrives, then the song changes.
        source.wanted = false;
        source.endpoint = track("Next song");
        compare(source.lyricsState, "idle");
        tryVerify(function () { return source.active === null; }, 3000, "the first lookup completes");
        compare(source.lyricsState, "idle", "the old track's answer is not shown for the new one");
        compare(source.lines.length, 0);
        verify(Lyrics.lruGet(source.cache, asked).hit !== undefined, "it still fills the cache");
    }
    function test_missingIsCachedNone() {
        var source = makeSource("missing");
        source.wanted = true;
        tryCompare(source, "lyricsState", "none", 3000);
        source.wanted = false;
        var before = requestCount();
        source.wanted = true;
        compare(source.lyricsState, "none");
        wait(150);
        compare(requestCount(), before, "a miss is cached");
    }
    function test_instrumental() {
        var source = makeSource("instrumental");
        source.wanted = true;
        tryCompare(source, "lyricsState", "instrumental", 3000);
        compare(source.lines.length, 0);
    }
    function test_plainOnly() {
        var source = makeSource("plain");
        source.wanted = true;
        tryCompare(source, "lyricsState", "plain", 3000);
        compare(source.lines.length, 0);
    }
    function test_declaredTooLarge() {
        var source = makeSource("big-declared");
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "too-large");
        compare(source.active, null);
    }
    function test_chunkedTooLarge() {
        var source = makeSource("big-chunked");
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "too-large");
        compare(source.cache.length, 0, "an error is never cached");
    }
    function test_multibyteTooLarge() {
        // Under the cap in characters, over it in bytes.
        var source = makeSource("big-multibyte");
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "too-large");
    }
    function test_timeout() {
        var source = makeSource("slow", undefined, { timeoutMs: 300 });
        source.wanted = true;
        compare(source.lyricsState, "loading");
        tryCompare(source, "lyricsState", "error", 2000);
        compare(source.errorCode, "timeout");
        compare(source.active, null);
    }
    function test_garbageIsNone() {
        var source = makeSource("garbage");
        source.wanted = true;
        tryCompare(source, "lyricsState", "none", 3000);
    }
    function test_noLengthMakesNoRequest() {
        var before = requestCount();
        var source = makeSource("get", track("Stream", 0));
        source.wanted = true;
        compare(source.lyricsState, "no-length");
        wait(150);
        compare(requestCount(), before);
        source.endpoint = track("Stream", 180);
        tryCompare(source, "lyricsState", "ready", 3000, "a length arriving later starts the lookup");
    }
    function test_noMetaIsIdle() {
        var before = requestCount();
        var bare = track("Song");
        bare.presentation.artists = [];
        var source = makeSource("get", bare);
        source.wanted = true;
        compare(source.lyricsState, "idle");
        wait(150);
        compare(requestCount(), before);
    }
    function test_disabledMakesNoRequest() {
        var before = requestCount();
        var source = makeSource("get", undefined, { lyricsEnabled: false });
        source.wanted = true;
        source.endpoint = track("Other");
        wait(200);
        compare(source.lyricsState, "idle");
        compare(requestCount(), before, "lyrics off sends nothing");
    }
    function test_closedViewMakesNoRequest() {
        var before = requestCount();
        var source = makeSource("get");
        source.endpoint = track("Changed while closed");
        wait(200);
        compare(source.lyricsState, "idle");
        compare(requestCount(), before, "a closed view sends nothing");
    }
    function test_disableClearsCache() {
        var source = openReady("get");
        verify(source.cache.length > 0);
        source.lyricsEnabled = false;
        compare(source.cache.length, 0);
        compare(source.lines.length, 0);
        compare(source.lyricsState, "idle");
        var before = requestCount();
        source.lyricsEnabled = true;
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 1, "the forgotten answer is fetched again");
    }
    function test_disableAbortsInFlight() {
        var source = makeSource("slow", undefined, { timeoutMs: 5000 });
        source.wanted = true;
        compare(source.lyricsState, "loading");
        verify(source.active !== null);
        source.lyricsEnabled = false;
        compare(source.active, null);
        compare(source.lyricsState, "idle");
        verify(!source.timeout.running);
    }
    function test_retryAfterError() {
        var source = makeSource("slow", undefined, { timeoutMs: 300 });
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 2000);
        source.endpointUrl = url("get");
        source.retry();
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(source.errorCode, "");
    }
    function test_retryDropsCachedMiss() {
        var source = makeSource("missing");
        source.wanted = true;
        tryCompare(source, "lyricsState", "none", 3000);
        var before = requestCount();
        source.retry();
        tryCompare(source, "lyricsState", "none", 3000);
        compare(requestCount(), before + 1, "Try again really asks again");
    }
}
