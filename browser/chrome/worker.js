import { DocumentRouter, HOST } from "./router.js";

const router = new DocumentRouter(retire);
let native = null;
const pending = new Map();
function send(message) {
  if (!native || !router.bridgeSession) return;
  try { native.postMessage(message); } catch { closeNative(native, true); }
}
function clearPending() { for (const item of pending.values()) clearTimeout(item.timer); pending.clear(); }
function retire(record) {
  send({ type: "browserGone", protocolVersion: 1, bridgeSession: router.bridgeSession,
    tabId: record.tabId, documentId: record.documentId });
  for (const [id, item] of pending) if (item.record === record) { clearTimeout(item.timer); pending.delete(id); }
}
function post(record, message) {
  try { record.port.postMessage(message); return true; } catch { record.port.disconnect(); return false; }
}
function disconnected(port) {
  if (native !== port) return;
  // Reading lastError acknowledges Chrome's bounded diagnostic without logging data.
  void chrome.runtime.lastError;
  release(true);
}
function release(reconnect) {
  native = null; clearPending(); router.reset();
  if (reconnect && router.documents.size) chrome.alarms.create("native-reconnect", { delayInMinutes: 0.5 });
}
// Chrome fires onDisconnect only on the other end of a port, so a port this
// worker closes itself is released here; otherwise `native` would keep a dead
// port and connectNative() would never open another.
function closeNative(port, reconnect) {
  if (native !== port) return;
  port.disconnect();
  release(reconnect);
}
function connectNative() {
  if (native || !router.documents.size) return;
  let port;
  try { port = chrome.runtime.connectNative(HOST); }
  catch { chrome.alarms.create("native-reconnect", { delayInMinutes: 0.5 }); return; }
  native = port;
  port.onDisconnect.addListener(() => disconnected(port));
  port.onMessage.addListener(message => {
    if (native !== port || message.protocolVersion !== 1) return;
    if (message.type === "bridgeHello") {
      if (typeof message.bridgeSession !== "string" || !message.bridgeSession || message.bridgeSession.length > 128
          || typeof message.busEpoch !== "string" || !message.busEpoch || message.busEpoch.length > 128) { closeNative(port, true); return; }
      clearPending(); router.reset(message.bridgeSession, message.busEpoch);
      for (const record of router.documents.values()) {
        if (record.state) send(router.state(record, record.state));
        post(record, { type: "refresh" });
      }
      return;
    }
    if (message.bridgeSession !== router.bridgeSession) return;
    const record = router.resolve(message.endpointToken);
    if (message.type === "browserSubscribe") {
      if (record) post(record, { type: "subscription", endpointToken: message.endpointToken, visible: message.visible === true,
        cadenceMs: message.cadenceMs });
    } else if (message.type === "browserCommand") {
      if (!record || pending.size >= 16 || pending.has(message.requestId)) {
        send({ type: "browserResult", protocolVersion: 1, bridgeSession: router.bridgeSession,
          requestId: message.requestId, status: record ? "busy" : "target-gone" }); return;
      }
      // Raise is answered here, after resolve and the busy check but before the
      // pending slot is taken. Resolving first is what makes a stale endpoint
      // token answer target-gone instead of activating a recycled tab id;
      // answering before pending.set is what stops the 2.5s timer firing a
      // second result for the same requestId and leaking a slot.
      if (message.action === "Raise") {
        const session = router.bridgeSession;
        raiseTab(record.tabId).then(status => {
          send({ type: "browserResult", protocolVersion: 1, bridgeSession: session,
            requestId: message.requestId, status });
        });
        return;
      }
      const item = { record, session: router.bridgeSession, token: message.endpointToken };
      item.timer = setTimeout(() => {
        if (pending.get(message.requestId) !== item) return;
        pending.delete(message.requestId);
        send({ type: "browserResult", protocolVersion: 1, bridgeSession: item.session,
          requestId: message.requestId, status: "timeout" });
      }, 2500);
      pending.set(message.requestId, item);
      post(record, message);
    }
  });
}
// Resolved at dispatch rather than persisted: a tab can be dragged to another
// window while its port stays alive, and adding windowId to the router record
// would push a stable window identifier into the native-messaging stream.
async function raiseTab(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    await chrome.tabs.update(tab.id, { active: true });
    await chrome.windows.update(tab.windowId, { focused: true });
    return "success";
  } catch (error) {
    // The tab closed between snapshot and command. Without this the promise
    // rejects unhandled, no result is ever sent, and the caller waits out the
    // transport timeout instead of being told the target is gone.
    return "target-gone";
  }
}
chrome.runtime.onConnect.addListener(port => {
  if (port.name !== "nookisle-document") { port.disconnect(); return; }
  const record = router.connect(port);
  if (!record) { port.disconnect(); return; }
  port.onDisconnect.addListener(() => {
    if (!router.disconnect(record)) return;
    retire(record);
    if (!router.documents.size && native) { closeNative(native, false); chrome.alarms.clear("native-reconnect"); }
  });
  port.onMessage.addListener(message => {
    if (router.documents.get(record.key) !== record) return;
    if (message.type === "state") {
      const state = router.state(record, message.state); if (state) send(state);
    } else if (message.type === "result") {
      const item = pending.get(message.requestId);
      if (!item || item.record !== record || item.session !== router.bridgeSession) return;
      clearTimeout(item.timer); pending.delete(message.requestId);
      send({ type: "browserResult", protocolVersion: 1, bridgeSession: item.session,
        requestId: message.requestId, status: router.resolve(item.token) === record ? message.status : "target-gone" });
    }
  });
  post(record, { type: "transport", bridgeSession: router.bridgeSession, busEpoch: router.busEpoch });
  connectNative();
});
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "native-reconnect") connectNative(); });
