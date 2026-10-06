(() => {
  let port = null, retry = null, publishTimer = null, sampleTimer = null;
  let current = null, identity = "", generation = crypto.randomUUID(), trackGeneration = crypto.randomUUID(), route = location.href;
  let subscribed = false, cadence = 1000, last = "", stopped = false;
  let lastPosition = NaN, lastPositionAt = -Infinity, publishPosition = false;
  let bridgeSession = "", busEpoch = "";
  const events = ["play", "pause", "ended", "loadedmetadata", "durationchange", "seeked", "volumechange", "ratechange", "emptied"];
  function send(message) { try { port?.postMessage(message); } catch { disconnect(); } }
  function sync(forcePosition = false) {
    const next = NookisleAdapter.adapter(document, location);
    const mediaChanged = current?.media !== next.media;
    if (mediaChanged || identity !== next.identity || route !== location.href) trackGeneration = crypto.randomUUID();
    identity = next.identity; route = location.href;
    if (mediaChanged) {
      generation = crypto.randomUUID(); subscribed = false;
      clearTimeout(sampleTimer); sampleTimer = null;
      if (current?.media) for (const event of events) current.media.removeEventListener(event, schedule);
      if (next.media) for (const event of events) next.media.addEventListener(event, schedule);
    }
    current = next;
    next.state.mediaGeneration = generation;
    next.state.trackGeneration = trackGeneration;
    const structural = { ...next.state }; delete structural.positionSeconds;
    const encoded = JSON.stringify(structural);
    const now = performance.now();
    if (encoded !== last || forcePosition || (subscribed && next.state.status === "Playing"
        && now - lastPositionAt >= cadence && lastPosition !== next.state.positionSeconds)) {
      last = encoded; lastPosition = next.state.positionSeconds; lastPositionAt = now;
      if (forcePosition) next.state.positionEvent = true;
      send({ type: "state", state: next.state });
    }
    clearTimeout(sampleTimer); sampleTimer = null;
    if (subscribed && next.state.status === "Playing") sampleTimer = setTimeout(sync, cadence);
  }
  function schedule(event) {
    publishPosition ||= event?.type === "seeked";
    if (!publishTimer && !stopped) publishTimer = setTimeout(() => {
      publishTimer = null; const force = publishPosition; publishPosition = false; sync(force);
    }, 100);
  }
  function disconnect() {
    port = null; subscribed = false; bridgeSession = busEpoch = ""; clearTimeout(sampleTimer); sampleTimer = null;
    if (!retry && !stopped) retry = setTimeout(() => { retry = null; connect(); }, 1000);
  }
  function connect() {
    if (port || stopped) return;
    try {
      const captured = chrome.runtime.connect({ name: "nookisle-document" });
      port = captured;
      captured.onDisconnect.addListener(() => { void chrome.runtime.lastError; if (port === captured) disconnect(); });
      captured.onMessage.addListener(async message => {
        if (captured !== port) return;
        if (message.type === "transport") {
          bridgeSession = message.bridgeSession; busEpoch = message.busEpoch;
          subscribed = false; clearTimeout(sampleTimer); sampleTimer = null; return;
        }
        if (message.type === "refresh") { last = ""; sync(true); return; }
        if (message.type === "subscription") {
          if (message.endpointToken?.bridgeSession !== bridgeSession || message.endpointToken?.busEpoch !== busEpoch) return;
          // An unsubscribe always revokes the old lease, even after media replacement.
          if (message.visible === true && message.endpointToken?.mediaGeneration !== generation) return;
          subscribed = message.visible === true;
          cadence = message.cadenceMs <= 250 ? Math.max(100, message.cadenceMs || 250) : 1000;
          sync(); return;
        }
        if (message.type !== "browserCommand") return;
        sync();
        const token = message.endpointToken;
        let status = "target-gone";
        if (bridgeSession && token?.bridgeSession === bridgeSession && token?.busEpoch === busEpoch
            && token?.mediaGeneration === generation) {
          if ((message.action === "SetPosition" || message.action === "Favorite")
              && (message.trackToken?.trackGeneration !== trackGeneration
              || message.trackToken?.rawTrackId !== trackGeneration)) status = "stale-track";
          else try { status = await current.execute(message.action, message.value); } catch { status = "error"; }
        }
        if (captured === port) send({ type: "result", requestId: message.requestId, status });
        sync(true);
      });
      last = ""; sync();
    } catch { disconnect(); }
  }
  const roots = '#movie_player,ytmusic-player-bar,ytd-watch-metadata,#owner #channel-name,[data-testid="now-playing-bar"]';
  const observer = new MutationObserver(schedule);
  function observe() {
    observer.disconnect();
    for (const root of [...document.querySelectorAll(roots)].slice(0, 16)) observer.observe(root, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ["src", "disabled", "hidden", "aria-disabled", "aria-label", "aria-pressed", "aria-checked"] });
  }
  let discoveryTimer = null;
  function discover() {
    if (!discoveryTimer && !stopped) discoveryTimer = setTimeout(() => {
      discoveryTimer = null; observe(); sync();
    }, 100);
  }
  // Discovery sees child insertion/removal only. Unrelated text, style, progress and comment
  // mutations do not cause media reads. Root scans are coalesced and root observers bounded.
  const discovery = new MutationObserver(records => {
    for (const record of records) for (const node of [...record.addedNodes, ...record.removedNodes]) {
      if (node.nodeType === 1 && (node.matches(roots) || node.querySelector(roots))) { discover(); return; }
    }
  });
  observe();
  discovery.observe(document.documentElement, { childList: true, subtree: true });
  addEventListener("popstate", schedule);
  addEventListener("yt-navigate-finish", schedule);
  addEventListener("pagehide", () => {
    stopped = true; observer.disconnect(); discovery.disconnect();
    clearTimeout(retry); clearTimeout(publishTimer); clearTimeout(sampleTimer); clearTimeout(discoveryTimer);
    retry = publishTimer = sampleTimer = discoveryTimer = null;
    port?.disconnect(); port = null;
  });
  // A BFCache restoration is a new transport lifetime even when Chrome retains the document.
  addEventListener("pageshow", event => {
    if (!event.persisted) return;
    stopped = false; generation = crypto.randomUUID(); trackGeneration = crypto.randomUUID(); last = "";
    observe(); discovery.observe(document.documentElement, { childList: true, subtree: true }); connect();
  });
  connect();
})();
