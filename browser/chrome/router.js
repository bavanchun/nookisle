export const HOST = "io.github.bavanchun.nookisle";
export const LIMIT = 64;
export function supportedUrl(value) {
  try { const u = new URL(value); return u.protocol === "https:" &&
    ["www.youtube.com", "music.youtube.com", "open.spotify.com"].includes(u.hostname); }
  catch { return false; }
}
export function sameToken(a, b) {
  return !!a && !!b && ["busEpoch", "transport", "bridgeSession", "tabId", "documentId", "frameId", "mediaGeneration"]
    .every(key => a[key] === b[key]);
}
export class DocumentRouter {
  constructor(retire = () => {}) { this.documents = new Map(); this.bridgeSession = ""; this.busEpoch = ""; this.retire = retire; }
  connect(port) {
    const sender = port.sender;
    if (!sender || sender.frameId !== 0 || !Number.isInteger(sender.tab?.id) || sender.tab.id < 0 ||
        typeof sender.documentId !== "string" || !sender.documentId || sender.documentId.length > 128 || !supportedUrl(sender.url)) return null;
    const key = sender.tab.id + ":" + sender.documentId;
    if (![...this.documents.values()].some(record => record.tabId === sender.tab.id) && this.documents.size >= LIMIT) return null;
    // Only one top-level document per tab is current, including tab-ID reuse and BFCache.
    for (const old of this.documents.values()) if (old.tabId === sender.tab.id) {
      this.documents.delete(old.key); this.retire(old); old.port.disconnect();
    }
    const record = { key, tabId: sender.tab.id, documentId: sender.documentId, frameId: 0, port, state: null };
    this.documents.set(key, record);
    return record;
  }
  disconnect(record) {
    if (this.documents.get(record.key) !== record) return false;
    this.documents.delete(record.key); return true;
  }
  reset(session = "", busEpoch = "") {
    this.bridgeSession = session; this.busEpoch = busEpoch;
    for (const record of this.documents.values()) {
      try { record.port.postMessage({ type: "transport", bridgeSession: session, busEpoch }); } catch { /* Disconnect event retires it. */ }
    }
  }
  token(record) {
    return { busEpoch: this.busEpoch, transport: "extension", bridgeSession: this.bridgeSession,
      tabId: record.tabId, documentId: record.documentId, frameId: 0, mediaGeneration: record.state?.mediaGeneration };
  }
  state(record, value) {
    if (this.documents.get(record.key) !== record || !value || typeof value.mediaGeneration !== "string" ||
        value.mediaGeneration.length > 128 || !value.mediaGeneration || typeof value.trackGeneration !== "string" ||
        !value.trackGeneration || value.trackGeneration.length > 128 || new TextEncoder().encode(JSON.stringify(value)).length > 7000) return null;
    record.state = value;
    return this.bridgeSession ? { type: "browserState", protocolVersion: 1, bridgeSession: this.bridgeSession,
      endpointToken: this.token(record), state: value } : null;
  }
  resolve(token) {
    const record = this.documents.get(token?.tabId + ":" + token?.documentId);
    return record?.state && sameToken(token, this.token(record)) ? record : null;
  }
}
