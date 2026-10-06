import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { DocumentRouter, supportedUrl } from "../../browser/chrome/router.js";
import "../../browser/chrome/adapters.js";

class Event {
  listeners = [];
  addListener(listener) { this.listeners.push(listener); }
  emit(value) { for (const listener of this.listeners) listener(value); }
}
class Port {
  constructor(tabId = 1, documentId = "document-a") {
    this.name = "nookisle-document";
    this.sender = { tab: { id: tabId }, documentId, frameId: 0, url: "https://www.youtube.com/watch?v=fixture" };
  }
  onMessage = new Event(); onDisconnect = new Event(); messages = []; closed = false;
  postMessage(message) { if (this.closed) throw Error("closed"); this.messages.push(message); }
  // As in Chrome, a port's own disconnect() fires onDisconnect only on the
  // other end; drop() is the other end closing, which fires it here.
  disconnect() { this.closed = true; }
  drop() { if (this.closed) return; this.closed = true; this.onDisconnect.emit(); }
}
const state = generation => ({ platform: "YouTube", title: "Fixture", mediaGeneration: generation, trackGeneration: "track-a",
  status: "Playing", capabilities: { CanControl: true, CanPlay: true, CanPause: true } });

test("sender validation is site-limited, HTTPS and top-frame only", () => {
  for (const value of ["https://www.youtube.com/", "https://music.youtube.com/", "https://open.spotify.com/"]) assert.ok(supportedUrl(value));
  for (const value of ["http://www.youtube.com/", "https://youtube.com.evil.test/", "https://example.com/", "bad"]) assert.equal(supportedUrl(value), false);
  const router = new DocumentRouter();
  const port = new Port(); port.sender.frameId = 2;
  assert.equal(router.connect(port), null);
  port.sender.frameId = 0; delete port.sender.documentId;
  assert.equal(router.connect(port), null);
});
test("tab reuse retires the old document immediately and stale disconnect cannot remove its replacement", () => {
  const retired = [], router = new DocumentRouter(record => retired.push(record));
  router.reset("session", "epoch");
  const old = router.connect(new Port()); router.state(old, state("media-a")); const stale = router.token(old);
  const fresh = router.connect(new Port(1, "document-b")); router.state(fresh, state("media-b"));
  assert.equal(old.port.closed, true); assert.deepEqual(retired, [old]);
  assert.equal(router.resolve(stale), null); assert.equal(router.disconnect(old), false);
  assert.equal(router.resolve(router.token(fresh)), fresh);
  assert.equal(router.documents.size, 1);
});
test("every token field and media generation is authoritative across bridge reconnect", () => {
  const router = new DocumentRouter(); router.reset("session", "epoch");
  const record = router.connect(new Port()); router.state(record, state("media-a")); const token = router.token(record);
  for (const field of Object.keys(token)) assert.equal(router.resolve({ ...token, [field]: "different" }), null, field);
  router.state(record, state("media-b")); assert.equal(router.resolve(token), null);
  const changed = router.token(record); router.reset(); assert.equal(router.resolve(changed), null);
  assert.equal(record.port.messages.at(-1).bridgeSession, "");
  router.reset("new-session", "epoch"); assert.equal(router.resolve(changed), null);
  assert.equal(router.resolve(router.token(record)), record);
});
test("document registry and UTF-8 state bytes are bounded", () => {
  const router = new DocumentRouter();
  for (let i = 0; i < 64; ++i) assert.ok(router.connect(new Port(i, "doc")));
  assert.equal(router.connect(new Port(65, "doc")), null);
  const replacement = router.connect(new Port(0, "new-doc")); assert.ok(replacement);
  assert.equal(router.documents.size, 64);
  assert.equal(router.state(replacement, { ...state("gen"), title: "😀".repeat(3000) }), null);
});
function mediaFixture() {
  return { readyState: 4, paused: true, ended: false, currentSrc: "blob:fixture", currentTime: 12, duration: 120,
    volume: 0.4, seekable: { length: 1 }, played: 0, pausedCalls: 0,
    async play() { this.played++; this.paused = false; }, pause() { this.pausedCalls++; this.paused = true; },
    addEventListener() {}, removeEventListener() {} };
}
function button(label) {
  return { textContent: "", disabled: false, hidden: false, clicks: 0, getAttribute(name) { return name === "aria-label" ? label : null; },
    getClientRects() { return [{}]; }, click() { this.clicks++; } };
}
function documentFixture(media, nodes = {}) {
  return { documentElement: {}, querySelectorAll() { return media; }, querySelector(selector) { return nodes[selector] || null; } };
}
test("YouTube adapter controls only a single captured media element and reports unsupported capabilities truthfully", async () => {
  const media = mediaFixture(), next = button("Next");
  const doc = documentFixture([media], { ".ytp-next-button": next });
  const adapter = NookisleAdapter.adapter(doc, { hostname: "www.youtube.com" });
  assert.equal(adapter.state.capabilities.CanSeek, true);
  assert.equal(await adapter.execute("Play"), "success"); assert.equal(media.played, 1);
  assert.equal(await adapter.execute("SetPosition", 36), "success"); assert.equal(media.currentTime, 36);
  assert.equal(await adapter.execute("SetVolume", 2), "invalid-value"); assert.equal(media.volume, 0.4);
  assert.equal(await adapter.execute("Next"), "success"); assert.equal(next.clicks, 1);
  next.hidden = true; assert.equal(NookisleAdapter.adapter(doc, { hostname: "www.youtube.com" }).state.capabilities.CanGoNext, false);
  const ambiguous = NookisleAdapter.adapter(documentFixture([media, mediaFixture()]), { hostname: "www.youtube.com" });
  assert.equal(ambiguous.state.capabilities.CanControl, false); assert.equal(await ambiguous.execute("Play"), "unsupported");
});
test("YouTube artwork follows the current video, not the page head's first-video link", () => {
  const stale = { href: "https://i.ytimg.com/vi/AAAAAAAAAAA/maxresdefault.jpg" };
  const doc = documentFixture([mediaFixture()], { 'link[rel="image_src"]': stale });
  const artwork = href => NookisleAdapter.adapter(doc, { hostname: "www.youtube.com", href }).state.artworkUrl;
  assert.equal(artwork("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10"), "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg");
  // In-page navigation changes the URL while the head link stays on the first video.
  assert.equal(artwork("https://www.youtube.com/watch?list=PL1&v=9bZkp7q19f0"), "https://i.ytimg.com/vi/9bZkp7q19f0/hqdefault.jpg");
  assert.equal(artwork("https://www.youtube.com/shorts/aqz-KE-bpKQ"), "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg");
  assert.equal(artwork("https://www.youtube.com/live/jfKfPfyJRdk?si=x"), "https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault.jpg");
  assert.equal(artwork("https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"), "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg");
  for (const href of ["https://www.youtube.com/", "https://www.youtube.com/watch?v=bad/../id", "https://www.youtube.com/watch?v=",
    "https://www.youtube.com/embed/dQw4w9WgXcQx", "https://www.youtube.com/embed/short",
    "https://www.youtube.com/embed/videoseries?list=PL1",
    "https://www.youtube.com/results?search_query=x", "not a url", undefined])
    assert.equal(artwork(href), "", String(href));
});
test("Spotify button-only adapter does not invent seek or volume and unknown button labels fail closed", async () => {
  const play = button("Play"), doc = documentFixture([], { '[data-testid="control-button-playpause"]': play });
  const adapter = NookisleAdapter.adapter(doc, { hostname: "open.spotify.com" });
  assert.equal(adapter.state.capabilities.CanSeek, false); assert.equal(adapter.state.capabilities.CanSetVolume, false);
  assert.equal(await adapter.execute("Play"), "success"); assert.equal(play.clicks, 1);
  assert.equal(await adapter.execute("Pause"), "success"); assert.equal(play.clicks, 1);
  play.getAttribute = () => "Unknown locale";
  assert.equal(NookisleAdapter.adapter(doc, { hostname: "open.spotify.com" }).state.capabilities.CanControl, false);
});
test("Spotify and YouTube Music expose favorite only with a readable enabled like control", async () => {
  const play = button("Play"), spotifyLike = button("Add to Your Library");
  const spotify = documentFixture([], { '[data-testid="control-button-playpause"]': play,
    '[data-testid="now-playing-bar"] [data-testid="add-button"]': spotifyLike });
  let adapter = NookisleAdapter.adapter(spotify, { hostname: "open.spotify.com" });
  assert.equal(adapter.state.capabilities.CanFavorite, true);
  assert.equal(adapter.state.liked, false);
  assert.equal(await adapter.execute("Favorite"), "success");
  assert.equal(spotifyLike.clicks, 1);
  spotifyLike.getAttribute = name => name === "aria-label" ? "Remove from Your Library" : null;
  adapter = NookisleAdapter.adapter(spotify, { hostname: "open.spotify.com" });
  assert.equal(adapter.state.liked, true);
  const media = mediaFixture(), musicLike = button("Like");
  musicLike.getAttribute = name => name === "aria-pressed" ? "false" : null;
  const music = documentFixture([media], { 'ytmusic-player-bar ytmusic-like-button-renderer button[aria-pressed]': musicLike });
  adapter = NookisleAdapter.adapter(music, { hostname: "music.youtube.com" });
  assert.equal(adapter.state.capabilities.CanFavorite, true);
  assert.equal(adapter.state.liked, false);
  assert.equal(await adapter.execute("Favorite"), "success");
  assert.equal(musicLike.clicks, 1);
  musicLike.hidden = true;
  adapter = NookisleAdapter.adapter(music, { hostname: "music.youtube.com" });
  assert.equal(adapter.state.capabilities.CanFavorite, false);
  assert.equal(await adapter.execute("Favorite"), "unsupported");
  assert.equal(adapter.state.capabilities.CanShuffle, false);
  assert.equal(adapter.state.capabilities.CanLoop, false);
});
test("worker disconnect rejects stale results and reconnect never replays captured commands", async () => {
  const runtime = { onConnect: new Event(), nativePorts: [], connectNative() { const port = new Port(); this.nativePorts.push(port); return port; } };
  const alarms = { onAlarm: new Event(), created: [], create(...args) { this.created.push(args); }, clear() {} };
  globalThis.chrome = { runtime, alarms };
  await import(`../../browser/chrome/worker.js?test=${Date.now()}`);
  const content = new Port(); runtime.onConnect.emit(content); content.onMessage.emit({ type: "state", state: state("media") });
  const native = runtime.nativePorts[0]; native.onMessage.emit({ protocolVersion: 1, type: "bridgeHello", bridgeSession: "a", busEpoch: "e" });
  const token = native.messages.find(message => message.type === "browserState").endpointToken;
  native.onMessage.emit({ protocolVersion: 1, type: "browserCommand", bridgeSession: "a", endpointToken: token, requestId: "one", action: "Play" });
  assert.equal(content.messages.filter(message => message.type === "browserCommand").length, 1);
  native.drop(); assert.equal(alarms.created.length, 1);
  assert.equal(content.messages.at(-1).type, "transport"); assert.equal(content.messages.at(-1).bridgeSession, "");
  content.onMessage.emit({ type: "result", requestId: "one", status: "success" });
  alarms.onAlarm.emit({ name: "native-reconnect" });
  const replacement = runtime.nativePorts[1]; replacement.onMessage.emit({ protocolVersion: 1, type: "bridgeHello", bridgeSession: "b", busEpoch: "e" });
  assert.equal(replacement.messages.filter(message => message.type === "browserResult").length, 0);
  assert.equal(content.messages.filter(message => message.type === "browserCommand").length, 1);
  replacement.onMessage.emit({ protocolVersion: 1, type: "browserCommand", bridgeSession: "b", endpointToken: token, requestId: "two", action: "Play" });
  assert.equal(replacement.messages.at(-1).status, "target-gone");
  content.drop(); assert.equal(replacement.closed, true);
  delete globalThis.chrome;
});
async function loadWorker() {
  const runtime = { onConnect: new Event(), nativePorts: [],
    connectNative() { const port = new Port(); this.nativePorts.push(port); return port; } };
  const alarms = { onAlarm: new Event(), created: [], create(...args) { this.created.push(args); }, clear() {} };
  globalThis.chrome = { runtime, alarms };
  await import(`../../browser/chrome/worker.js?test=${Date.now()}-${Math.random()}`);
  return { runtime, alarms };
}
test("closing the last tab releases the native port, so the next tab reconnects", async () => {
  const { runtime } = await loadWorker();
  const first = new Port(); runtime.onConnect.emit(first);
  runtime.nativePorts[0].onMessage.emit({ protocolVersion: 1, type: "bridgeHello", bridgeSession: "a", busEpoch: "e" });
  first.drop();
  assert.equal(runtime.nativePorts[0].closed, true);
  const second = new Port(2, "document-b"); runtime.onConnect.emit(second);
  assert.equal(runtime.nativePorts.length, 2);
  assert.equal(runtime.nativePorts[1].closed, false);
  delete globalThis.chrome;
});
test("a malformed hello or a failed post closes the port and schedules a reconnect", async () => {
  const { runtime, alarms } = await loadWorker();
  const content = new Port(); runtime.onConnect.emit(content);
  runtime.nativePorts[0].onMessage.emit({ protocolVersion: 1, type: "bridgeHello", bridgeSession: "", busEpoch: "e" });
  assert.equal(runtime.nativePorts[0].closed, true);
  assert.equal(alarms.created.length, 1);
  alarms.onAlarm.emit({ name: "native-reconnect" });
  const replacement = runtime.nativePorts[1];
  assert.ok(replacement);
  replacement.onMessage.emit({ protocolVersion: 1, type: "bridgeHello", bridgeSession: "b", busEpoch: "e" });
  replacement.postMessage = () => { throw Error("closed"); };
  content.onMessage.emit({ type: "state", state: state("media") });
  assert.equal(replacement.closed, true);
  assert.equal(alarms.created.length, 2);
  alarms.onAlarm.emit({ name: "native-reconnect" });
  assert.equal(runtime.nativePorts.length, 3);
  delete globalThis.chrome;
});
test("content lifetime validates bridge and media tokens, stops timers, and restores BFCache without navigation", async () => {
  const media = mediaFixture(), title = { textContent: "First track" }, like = button("Like");
  like.getAttribute = name => name === "aria-pressed" ? "false" : null;
  const doc = documentFixture([media], { "ytmusic-player-bar .title": title,
    'ytmusic-player-bar ytmusic-like-button-renderer button[aria-pressed]': like });
  const events = new Map(), ports = [], timers = new Map(), observers = []; let sequence = 0, reloads = 0, clock = 0;
  const location = { hostname: "music.youtube.com", href: "https://music.youtube.com/watch?v=fixture", reload() { reloads++; } };
  const context = vm.createContext({ document: doc, location, NookisleAdapter,
    performance: { now: () => clock },
    crypto: { randomUUID: () => `generation-${++sequence}` },
    chrome: { runtime: { connect() { const port = new Port(); ports.push(port); return port; } } },
    MutationObserver: class { constructor(callback) { observers.push(callback); } observe() {} disconnect() {} },
    addEventListener(name, callback) { events.set(name, callback); },
    setTimeout(callback, ms) { const id = ++sequence; timers.set(id, { callback, ms }); return id; },
    clearTimeout(id) { timers.delete(id); } });
  vm.runInContext(fs.readFileSync(new URL("../../browser/chrome/content-script.js", import.meta.url), "utf8"), context);
  const port = ports[0], generation = port.messages[0].state.mediaGeneration, originalTrack = port.messages[0].state.trackGeneration;
  port.onMessage.emit({ type: "transport", bridgeSession: "new", busEpoch: "epoch" });
  const endpointToken = { bridgeSession: "old", busEpoch: "epoch", mediaGeneration: generation };
  port.onMessage.emit({ type: "browserCommand", requestId: "old", action: "Play", endpointToken });
  await Promise.resolve(); assert.equal(media.played, 0);
  endpointToken.bridgeSession = "new";
  port.onMessage.emit({ type: "browserCommand", requestId: "good", action: "Play", endpointToken });
  await Promise.resolve(); await Promise.resolve(); assert.equal(media.played, 1);
  port.onMessage.emit({ type: "subscription", visible: true, cadenceMs: 100, endpointToken });
  assert.ok([...timers.values()].some(timer => timer.ms === 100));
  title.textContent = "Second track"; location.href = "https://music.youtube.com/watch?v=next-fixture";
  port.onMessage.emit({ type: "refresh" });
  const nextTrack = port.messages.filter(message => message.type === "state").at(-1).state;
  assert.equal(nextTrack.mediaGeneration, generation, "track transition preserves the pinned document endpoint");
  assert.notEqual(nextTrack.trackGeneration, originalTrack);
  port.onMessage.emit({ type: "browserCommand", requestId: "stale-seek", action: "SetPosition", value: 70,
    endpointToken, trackToken: { trackGeneration: originalTrack, rawTrackId: originalTrack } });
  await Promise.resolve(); assert.equal(media.currentTime, 12);
  assert.equal(port.messages.filter(message => message.requestId === "stale-seek").at(-1).status, "stale-track");
  port.onMessage.emit({ type: "browserCommand", requestId: "stale-favorite", action: "Favorite",
    endpointToken, trackToken: { trackGeneration: originalTrack, rawTrackId: originalTrack } });
  await Promise.resolve(); await Promise.resolve();
  assert.equal(port.messages.filter(message => message.requestId === "stale-favorite").at(-1).status, "stale-track");
  assert.equal(like.clicks, 0);
  port.onMessage.emit({ type: "browserCommand", requestId: "current-favorite", action: "Favorite",
    endpointToken, trackToken: { trackGeneration: nextTrack.trackGeneration, rawTrackId: nextTrack.trackGeneration } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(port.messages.filter(message => message.requestId === "current-favorite").at(-1).status, "success");
  assert.equal(like.clicks, 1);
  const replacement = mediaFixture(); replacement.paused = false; doc.querySelectorAll = () => [replacement];
  port.onMessage.emit({ type: "refresh" }); assert.equal(timers.size, 0, "replacement cancels the previous progress lease");
  const newToken = { ...endpointToken, mediaGeneration: port.messages.filter(message => message.type === "state").at(-1).state.mediaGeneration };
  port.onMessage.emit({ type: "subscription", visible: true, cadenceMs: 100, endpointToken: newToken }); assert.equal(timers.size, 1);
  const beforeCadence = port.messages.length; replacement.currentTime = 18; clock = 50; observers[0]([]);
  const mutationTimer = [...timers].at(-1); timers.delete(mutationTimer[0]); mutationTimer[1].callback();
  assert.equal(port.messages.length, beforeCadence, "player mutations cannot publish position faster than the selected cadence");
  clock = 100; observers[0]([]);
  const dueMutation = [...timers].at(-1); timers.delete(dueMutation[0]); dueMutation[1].callback();
  assert.equal(port.messages.length, beforeCadence + 1);
  port.onMessage.emit({ type: "subscription", visible: false, endpointToken }); assert.equal(timers.size, 0, "old-generation unsubscribe still revokes sampling");
  observers[1]([{ addedNodes: [{ nodeType: 1, matches: () => false, querySelector: () => null }], removedNodes: [] }]);
  assert.equal(timers.size, 0, "unrelated document insertion does not schedule media reads");
  const messagesBeforeHiddenProgress = port.messages.length;
  replacement.currentTime = 24; observers[0]([]);
  for (const [id, timer] of [...timers]) { timers.delete(id); timer.callback(); }
  assert.equal(port.messages.length, messagesBeforeHiddenProgress, "hidden position-only mutations do not publish state");
  assert.equal(timers.size, 0, "hidden progress does not install a periodic timer");
  port.onMessage.emit({ type: "transport", bridgeSession: "", busEpoch: "" }); assert.equal(timers.size, 0);
  events.get("pagehide")(); assert.equal(port.closed, true); assert.equal(timers.size, 0);
  events.get("pageshow")({ persisted: true }); assert.equal(ports.length, 2); assert.equal(reloads, 0);
  assert.notEqual(ports[1].messages[0].state.mediaGeneration, generation);
  events.get("pagehide")();
});
