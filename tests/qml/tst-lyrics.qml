import QtQuick
import QtTest
import "../../components"
import "../../qml/Lyrics.js" as Lyrics

TestCase {
    id: test
    name: "Lyrics"
    when: windowShown
    visible: true
    width: 10
    height: 10

    readonly property string syncedLrc: [
        "[ar:Fixture Artist]",
        "[ti:Fixture Song]",
        "[offset:+500]",
        "[00:01.00]First line",
        "[00:03.50][00:09.00]Chorus line",
        "[00:05.25]",
        "[00:07.000]Third line",
        "[00:11.5]Last line"
    ].join("\n")

    readonly property var bodies: ({
        "/api/get": {
            id: 1,
            trackName: "Fixture Song",
            artistName: "Fixture Artist",
            albumName: "Fixture Album",
            duration: 200.0,
            instrumental: false,
            plainLyrics: "First line\nChorus line",
            syncedLyrics: syncedLrc
        },
        "/api/instrumental": {
            id: 2,
            trackName: "Interlude",
            instrumental: true,
            plainLyrics: null,
            syncedLyrics: null
        },
        "/api/plain": {
            id: 3,
            trackName: "Untimed",
            instrumental: false,
            plainLyrics: "Words without timing",
            syncedLyrics: null
        }
    })

    readonly property string base: "https://lrclib.test"
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

    property int totalRequests: 0
    function requestCount() {
        return test.totalRequests;
    }

    Component {
        id: fakeFetcherComponent
        QtObject {
            id: fake
            signal finished(int status, string text)
            signal failed(string code)

            property var requests: []
            property int cancelCount: 0
            property string currentRoute: "get"

            function start(url) {
                requests.push(url);
                test.totalRequests++;
                var route = extractRoute(url);
                if (route === "slow") return;
                Qt.callLater(function () {
                    respond(route, String(url));
                });
            }

            function cancel() {
                cancelCount++;
            }

            function extractRoute(url) {
                var s = String(url || "");
                var match = s.match(/\/api\/([a-zA-Z0-9_-]+)/);
                return match ? match[1] : (currentRoute || "get");
            }

            function param(url, name) {
                var match = url.match(new RegExp("[?&]" + name + "=([^&]*)"));
                return match ? decodeURIComponent(match[1]) : "";
            }
            function bodyWithDuration(seconds) {
                var body = JSON.parse(JSON.stringify(test.bodies["/api/get"]));
                body.duration = seconds;
                return JSON.stringify(body);
            }
            function respond(route, url) {
                var nth = requests.length;
                var hasAlbum = param(url, "album_name") !== "";
                var suffixed = param(url, "track_name").indexOf("Remaster") >= 0;
                if (route === "album-strict") {
                    if (hasAlbum)
                        finished(404, "");
                    else
                        finished(200, JSON.stringify(test.bodies["/api/get"]));
                } else if (route === "suffix-only") {
                    if (hasAlbum || suffixed)
                        finished(404, "");
                    else
                        finished(200, JSON.stringify(test.bodies["/api/get"]));
                } else if (route === "plain-then-synced") {
                    if (nth === 1)
                        finished(404, "");
                    else if (nth === 2)
                        finished(200, JSON.stringify(test.bodies["/api/plain"]));
                    else
                        finished(200, JSON.stringify(test.bodies["/api/get"]));
                } else if (route === "busy-then-404") {
                    if (nth === 1)
                        failed("busy");
                    else
                        finished(404, "");
                } else if (route === "404-then-busy") {
                    if (nth === 1)
                        finished(404, "");
                    else
                        failed("busy");
                } else if (route === "drift-answer") {
                    if (nth === 1)
                        finished(404, "");
                    else
                        finished(200, bodyWithDuration(202));
                } else if (route === "edge-answer") {
                    if (nth === 1)
                        finished(404, "");
                    else
                        finished(200, bodyWithDuration(201));
                } else if (route === "busy-once") {
                    if (nth === 1)
                        failed("busy");
                    else
                        finished(200, JSON.stringify(test.bodies["/api/get"]));
                } else if (route === "busy-always") {
                    failed("busy");
                } else if (route === "limited") {
                    failed("rate-limited");
                } else if (route === "get") {
                    finished(200, JSON.stringify(test.bodies["/api/get"]));
                } else if (route === "instrumental") {
                    finished(200, JSON.stringify(test.bodies["/api/instrumental"]));
                } else if (route === "plain") {
                    finished(200, JSON.stringify(test.bodies["/api/plain"]));
                } else if (route === "missing") {
                    finished(404, JSON.stringify({ code: 404, name: "TrackNotFound" }));
                } else if (route === "garbage") {
                    finished(200, "not json");
                } else if (route === "big-declared" || route === "big-chunked" || route === "big-multibyte") {
                    failed("too-large");
                } else {
                    failed("network");
                }
            }
        }
    }

    Component {
        id: sourceComponent
        LyricsSource {
            lyricsEnabled: true
            wanted: false
        }
    }
    function makeSource(route, endpoint, extra) {
        var fetcher = createTemporaryObject(fakeFetcherComponent, test, { currentRoute: route || "get" });
        var properties = {
            endpointUrl: url(route),
            endpoint: endpoint === undefined ? track() : endpoint,
            fetcher: fetcher
        };
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
        compare(Lyrics.interpret(500, "").code, "network");
    }
    function test_interpretNamesARefusal() {
        var busy = Lyrics.interpret(503, "");
        compare(busy.state, "error");
        compare(busy.code, "busy");
        verify(!busy.cache);
        var limited = Lyrics.interpret(429, "");
        compare(limited.state, "error");
        compare(limited.code, "rate-limited");
        verify(!limited.cache);
    }

    function test_stripVersionSuffix() {
        var stripped = [
            ["Here Comes The Sun - Remastered 2009", "Here Comes The Sun"],
            ["Hotel California - 2013 Remaster", "Hotel California"],
            ["Wonderwall - Remastered", "Wonderwall"],
            ["'39 - Remastered 2011", "'39"],
            ["Get Lucky (feat. Pharrell Williams and Nile Rodgers)", "Get Lucky"],
            ["STAY (with Justin Bieber)", "STAY"],
            ["Song [ft. Someone]", "Song"],
            ["Song (feat. Someone) - Remastered 2009", "Song"]
        ];
        for (var i = 0; i < stripped.length; ++i) {
            compare(Lyrics.stripVersionSuffix(stripped[i][0]), stripped[i][1], stripped[i][0]);
            compare(Lyrics.stripVersionSuffix(stripped[i][1]), stripped[i][1], "idempotent: " + stripped[i][0]);
        }
        var kept = ["Old Town Road - Remix", "Hotel California - Live On MTV, 1994", "Gangnam Style (강남스타일)",
            "Life on Mars?", "Song - Acoustic", "Song (Sped Up)", "Song - Radio Edit", "Song (Instrumental)",
            "Song - Demo", "Song (Karaoke Version)", "Song - Slowed", "Song (Deluxe Version)", "Plain"];
        for (var j = 0; j < kept.length; ++j)
            compare(Lyrics.stripVersionSuffix(kept[j]), kept[j], kept[j]);
        compare(Lyrics.stripVersionSuffix("(feat. Only A Guest)"), "(feat. Only A Guest)", "an empty result keeps the original");
        compare(Lyrics.stripVersionSuffix(""), "");
        compare(Lyrics.stripVersionSuffix(null), "");
    }
    function test_stripVersionSuffixIsBounded() {
        var long = new Array(4097).join("a") + " - Remastered";
        var started = Date.now();
        compare(Lyrics.stripVersionSuffix(long), long, "left unchanged above 200 characters");
        var spaces = "x" + new Array(4096).join(" ") + "(feat. ";
        compare(Lyrics.stripVersionSuffix(spaces), spaces);
        var nested = new Array(2000).join("(feat. ") + "x";
        compare(Lyrics.stripVersionSuffix(nested), nested);
        var edge = new Array(171).join("b") + " - Remastered 2009";
        compare(Lyrics.stripVersionSuffix(edge), new Array(171).join("b"), "a title within the limit is still stripped");
        verify(Date.now() - started < 500, "adversarial titles return within a fixed time bound");
    }
    function test_requestPlan() {
        var meta = Lyrics.trackMeta(track("Song - Remastered 2009"));
        var plan = Lyrics.requestPlan(meta);
        compare(plan.length, 3);
        compare(plan[0], meta);
        compare(plan[1].album, "", "the second attempt drops the album");
        compare(plan[1].title, "Song - Remastered 2009");
        compare(plan[2].title, "Song", "the third also strips the title");
        compare(plan[2].album, "");
        for (var i = 0; i < plan.length; ++i) {
            verify(Object.keys(plan[i]).every(function (key) { return Object.keys(meta).indexOf(key) >= 0; }),
                "no field beyond the original ones is ever sent");
            compare(plan[i].artist, meta.artist);
            compare(plan[i].duration, meta.duration);
            verify(plan[i].album === meta.album || plan[i].album === "");
            verify(plan[i].title === meta.title || plan[i].title === Lyrics.stripVersionSuffix(meta.title));
        }
        var plain = Lyrics.requestPlan(Lyrics.trackMeta(track("Plain Song")));
        compare(plain.length, 2, "a title that does not change adds no third attempt");
        var bare = track("Plain Song");
        bare.presentation.album = "";
        compare(Lyrics.requestPlan(Lyrics.trackMeta(bare)).length, 1, "nothing narrower to try without an album or suffix");
        var bareSuffix = track("Song - Remastered");
        bareSuffix.presentation.album = "";
        var narrowed = Lyrics.requestPlan(Lyrics.trackMeta(bareSuffix));
        compare(narrowed.length, 2);
        compare(narrowed[1].title, "Song");
        var urls = narrowed.map(function (entry) { return Lyrics.requestUrl("b", entry); });
        compare(urls[0] === urls[1], false, "duplicates are removed");
        compare(Lyrics.requestPlan(null).length, 0);
    }
    function test_interpretChecksAFallbackDuration() {
        var answer = function (seconds) {
            return JSON.stringify({ duration: seconds, syncedLyrics: "[00:01.00]Hi" });
        };
        compare(Lyrics.interpret(200, answer(200)).state, "ready", "no expectation: accepted as before");
        compare(Lyrics.interpret(200, answer(200), 200).state, "ready");
        compare(Lyrics.interpret(200, answer(201), 200).state, "ready", "one second off is the edge");
        compare(Lyrics.interpret(200, answer(199.2), 200).state, "ready");
        compare(Lyrics.interpret(200, answer(202), 200).state, "none", "two seconds off is another recording");
        compare(Lyrics.interpret(200, answer(150), 200).state, "none");
        compare(Lyrics.interpret(200, JSON.stringify({ syncedLyrics: "[00:01.00]Hi" }), 200).state, "none", "no duration cannot be checked");
        compare(Lyrics.interpret(200, JSON.stringify({ duration: 202, instrumental: true }), 200).state, "none");
        verify(Lyrics.interpret(200, answer(202), 200).cache);
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
        compare(requestCount(), before + 2, "Try again really asks again, the walk included");
    }

    // A refusal (LRCLIB shedding load) is retried once, then reported as such.
    function test_busyOnceRetriesAndLoads() {
        var before = requestCount();
        var source = makeSource("busy-once", undefined, { retryMs: 30 });
        source.wanted = true;
        compare(source.lyricsState, "loading");
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 2, "one extra request");
        compare(source.errorCode, "");
        compare(source.cache.length, 1, "the answer is cached once it is conclusive");
        compare(source.fetcher.requests[0], source.fetcher.requests[1], "the retry asks the same question");
    }
    function test_busyTwiceEndsInErrorAndCachesNothing() {
        var before = requestCount();
        var source = makeSource("busy-always", undefined, { retryMs: 30 });
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "busy");
        compare(requestCount(), before + 2, "never more than one retry");
        compare(source.cache.length, 0, "an error is never cached");
        compare(source.active, null);
        verify(!source.retryTimer.running);
        wait(150);
        compare(requestCount(), before + 2);
    }
    function test_rateLimitedIsNotRetried() {
        var before = requestCount();
        var source = makeSource("limited", undefined, { retryMs: 30 });
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "rate-limited");
        wait(150);
        compare(requestCount(), before + 1, "only a busy refusal is retried");
    }
    function test_loadingShowsWhileTheRetryWaits() {
        var source = makeSource("busy-once", undefined, { retryMs: 400 });
        source.wanted = true;
        tryVerify(function () { return source.retryTimer.running; }, 2000);
        compare(source.lyricsState, "loading");
        compare(source.errorCode, "");
        source.refresh();
        compare(source.fetcher.requests.length, 1, "asking again while it waits adds nothing");
        tryCompare(source, "lyricsState", "ready", 3000);
    }
    function test_closingTheViewDuringTheRetryWaitSendsNothing() {
        var before = requestCount();
        var source = makeSource("busy-once", undefined, { retryMs: 150 });
        source.wanted = true;
        tryVerify(function () { return source.retryTimer.running; }, 2000);
        source.wanted = false;
        verify(!source.retryTimer.running, "closing cancels the retry");
        compare(source.lyricsState, "idle");
        wait(300);
        compare(requestCount(), before + 1, "nothing further is sent after closing");
        compare(source.cache.length, 0);
    }
    function test_lyricsOffDuringTheRetryWaitSendsNothing() {
        var before = requestCount();
        var source = makeSource("busy-once", undefined, { retryMs: 150 });
        source.wanted = true;
        tryVerify(function () { return source.retryTimer.running; }, 2000);
        source.lyricsEnabled = false;
        verify(!source.retryTimer.running);
        compare(source.active, null);
        wait(300);
        compare(requestCount(), before + 1);
        compare(source.cache.length, 0);
        compare(source.lyricsState, "idle");
    }
    function test_trackChangeDuringTheRetryWaitDropsTheRetry() {
        var before = requestCount();
        var source = makeSource("busy-once", undefined, { retryMs: 100 });
        source.wanted = true;
        tryVerify(function () { return source.retryTimer.running; }, 2000);
        source.endpoint = track("Another Song");
        verify(!source.retryTimer.running, "the old track's retry is gone");
        wait(250);
        compare(requestCount(), before + 1, "the old track is not asked again");
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 2);
        verify(source.fetcher.requests[1].indexOf("Another%20Song") > 0, "the second request is for the new track");
        compare(source.cache.length, 1);
    }
    function test_destructionDuringTheRetryWaitSendsNothing() {
        var before = requestCount();
        var source = makeSource("busy-once", undefined, { retryMs: 100 });
        source.wanted = true;
        tryVerify(function () { return source.retryTimer.running; }, 2000);
        source.destroy();
        wait(300);
        compare(requestCount(), before + 1);
    }
    function test_tryAgainAfterABusyErrorAsksAgain() {
        var source = makeSource("busy-always", undefined, { retryMs: 30 });
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "busy");
        source.endpointUrl = url("get");
        source.retry();
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(source.errorCode, "");
    }

    // After a real miss the lookup tries narrower questions, each with the
    // same or fewer fields, and stays inside four requests.
    function test_albumFallbackFindsTheTrackAndIsCached() {
        var before = requestCount();
        var source = makeSource("album-strict");
        source.wanted = true;
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 2, "the album, then without it");
        verify(source.fetcher.requests[0].indexOf("album_name=") > 0);
        compare(source.fetcher.requests[1].indexOf("album_name="), -1);
        compare(source.cache.length, 1);
        compare(source.cache[0].key, Lyrics.cacheKey(Lyrics.trackMeta(track())), "cached under the original key");
        source.wanted = false;
        source.wanted = true;
        compare(source.lyricsState, "ready");
        wait(150);
        compare(requestCount(), before + 2, "a reopen sends nothing");
    }
    function test_suffixFallbackFindsTheTrack() {
        var before = requestCount();
        var source = makeSource("suffix-only", track("Fixture Song - Remastered 2009"));
        source.wanted = true;
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 3, "the album, then without it, then the stripped title");
        verify(source.fetcher.requests[2].indexOf("track_name=Fixture%20Song&") > 0);
        compare(source.fetcher.requests[2].indexOf("album_name="), -1);
    }
    function test_aHitSendsExactlyOneRequest() {
        var before = requestCount();
        var source = makeSource("get", track("Fixture Song - Remastered 2009"));
        source.wanted = true;
        tryCompare(source, "lyricsState", "ready", 3000);
        wait(150);
        compare(requestCount(), before + 1);
    }
    function test_plainAnswerKeepsLookingForSyncedLyrics() {
        var before = requestCount();
        var source = makeSource("plain-then-synced", track("Fixture Song - Remastered 2009"));
        source.wanted = true;
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 3);
        compare(source.lines.length, 6);
    }
    function test_plainWithoutSyncedStaysPlain() {
        var before = requestCount();
        var source = makeSource("plain");
        source.wanted = true;
        tryCompare(source, "lyricsState", "plain", 3000);
        wait(150);
        compare(requestCount(), before + 1, "a plain answer to the first question is final");
    }
    function test_aDriftingFallbackAnswerIsAMiss() {
        var before = requestCount();
        var source = makeSource("drift-answer");
        source.wanted = true;
        tryCompare(source, "lyricsState", "none", 3000);
        compare(requestCount(), before + 2);
        compare(source.cache.length, 1, "the miss is cached");
    }
    function test_aFallbackAnswerOneSecondOffIsAccepted() {
        var source = makeSource("edge-answer");
        source.wanted = true;
        tryCompare(source, "lyricsState", "ready", 3000);
    }
    function test_missWalkIsNeverMoreThanFourRequests() {
        var before = requestCount();
        var source = makeSource("busy-then-404", track("Fixture Song - Remastered 2009"), { retryMs: 30 });
        source.wanted = true;
        tryCompare(source, "lyricsState", "none", 3000);
        compare(requestCount(), before + 4, "busy, then three misses");
        compare(source.cache.length, 1);
        wait(150);
        compare(requestCount(), before + 4);
    }
    function test_aBusyRefusalAfterAMissEndsInErrorAndCachesNothing() {
        var before = requestCount();
        var source = makeSource("404-then-busy", track("Fixture Song - Remastered 2009"), { retryMs: 30 });
        source.wanted = true;
        tryCompare(source, "lyricsState", "error", 3000);
        compare(source.errorCode, "busy");
        compare(requestCount(), before + 3, "a miss, a refusal and its one retry");
        compare(source.cache.length, 0, "a walk that ended in an error caches nothing");
    }
    function test_closingTheViewMidWalkSendsNoFurtherRequest() {
        var before = requestCount();
        var source = makeSource("album-strict");
        source.wanted = true;
        source.wanted = false;
        wait(200);
        compare(requestCount(), before + 1, "the answer in flight finishes, nothing follows");
        compare(source.cache.length, 0, "a walk stopped before its last attempt caches nothing");
        compare(source.active, null);
        compare(source.lyricsState, "idle");
    }
    function test_turningLyricsOffMidWalkSendsNoFurtherRequest() {
        var before = requestCount();
        var source = makeSource("album-strict");
        source.wanted = true;
        source.lyricsEnabled = false;
        wait(200);
        compare(requestCount(), before + 1);
        compare(source.cache.length, 0);
        compare(source.lyricsState, "idle");
    }
    function test_aTrackChangeMidWalkNeverAppliesTheStaleAnswer() {
        var before = requestCount();
        var source = makeSource("album-strict");
        source.wanted = true;
        source.endpoint = track("Another Song");
        wait(100);
        compare(requestCount(), before + 1, "the old walk stopped after its first request");
        compare(source.lyricsState, "loading");
        tryCompare(source, "lyricsState", "ready", 3000);
        compare(requestCount(), before + 3, "the new track walks on its own");
        verify(source.fetcher.requests[1].indexOf("Another%20Song") > 0);
        verify(source.fetcher.requests[2].indexOf("Another%20Song") > 0);
        compare(source.cache.length, 1);
        compare(source.cache[0].key, Lyrics.cacheKey(Lyrics.trackMeta(track("Another Song"))));
    }
}
