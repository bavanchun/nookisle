(function(root) {
  const text = node => (node?.textContent || "").trim().slice(0, 512);
  const usable = node => !!node && !node.disabled && !node.hidden && node.getAttribute("aria-disabled") !== "true"
    && node.getClientRects().length > 0;
  const finite = value => Number.isFinite(value) && value >= 0;
  const likedState = node => {
    if (!usable(node)) return null;
    const pressed = node.getAttribute("aria-pressed") ?? node.getAttribute("aria-checked");
    if (pressed === "true" || pressed === "false") return pressed === "true";
    const label = (node.getAttribute("aria-label") || "").toLowerCase();
    if (label === "add to your library" || label === "like") return false;
    if (label === "remove from your library" || label === "unlike") return true;
    return null;
  };
  // The current YouTube video's own thumbnail. The page head's image link is
  // not updated by YouTube's in-page navigation, so it names the first video
  // of the tab; the URL always names the current one.
  const youtubeArtwork = location => {
    let url;
    try { url = new URL(location.href || ""); } catch (error) { return ""; }
    const path = url.pathname.match(/^\/(?:shorts|live|embed)\/([^/]+)/);
    const id = url.pathname === "/watch" ? url.searchParams.get("v") : path ? path[1] : null;
    // A playlist embed's "videoseries" has an id's shape but names no video.
    return id && id !== "videoseries" && /^[A-Za-z0-9_-]{11}$/.test(id)
      ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : "";
  };
  function adapter(document, location) {
    const spotify = location.hostname === "open.spotify.com";
    const music = location.hostname === "music.youtube.com";
    const candidates = [...document.querySelectorAll(spotify ? "video,audio" : "#movie_player video, #movie_player audio")]
      .filter(node => node.readyState > 0);
    // Multiple media elements are ambiguous; never redirect a command to an arbitrary first match.
    const media = candidates.length === 1 ? candidates[0] : null;
    const button = selector => document.querySelector(selector);
    const play = spotify ? button('[data-testid="control-button-playpause"]') : null;
    const label = (play?.getAttribute("aria-label") || "").toLowerCase();
    const paused = media ? media.paused : /^(play|phát)$/.test(label) ? true : /^(pause|tạm dừng)$/.test(label) ? false : null;
    const next = button(spotify ? '[data-testid="control-button-skip-forward"]' : music ? 'ytmusic-player-bar .next-button' : '.ytp-next-button');
    const previous = button(spotify ? '[data-testid="control-button-skip-back"]' : music ? 'ytmusic-player-bar .previous-button' : '.ytp-prev-button');
    const title = text(button(spotify ? '[data-testid="context-item-info-title"]' : music ? 'ytmusic-player-bar .title' : 'ytd-watch-metadata h1'));
    const artist = text(button(spotify ? '[data-testid="context-item-info-subtitles"]' : music ? 'ytmusic-player-bar .byline' : '#owner #channel-name'));
    const artwork = spotify || music ? button(spotify ? '[data-testid="cover-art-image"]' : 'ytmusic-player-bar img') : null;
    const artworkUrl = (spotify || music ? artwork?.currentSrc || artwork?.src || "" : youtubeArtwork(location)).slice(0, 2048);
    const favorite = spotify ? button('[data-testid="now-playing-bar"] [data-testid="add-button"]')
      || button('[data-testid="now-playing-bar"] [data-testid="control-button-heart"]')
      : music ? button('ytmusic-player-bar ytmusic-like-button-renderer button[aria-pressed]') : null;
    const liked = likedState(favorite);
    const length = media && finite(media.duration) ? media.duration : 0;
    const controls = !!media || (usable(play) && paused !== null);
    return {
      media, identity: JSON.stringify([media?.currentSrc || "", title, artist]),
      state: { platform: spotify ? "Spotify" : music ? "YouTube Music" : "YouTube", title, artists: artist ? [artist] : [], artworkUrl,
        status: paused === null ? "Stopped" : paused ? "Paused" : "Playing",
        positionSeconds: media && finite(media.currentTime) ? media.currentTime : 0,
        lengthSeconds: length, volume: media ? media.volume : 0,
        liked,
        capabilities: { CanControl: controls, CanPlay: controls, CanPause: controls,
          CanGoNext: usable(next), CanGoPrevious: usable(previous),
          CanSeek: !!media && length > 0 && media.seekable?.length > 0, CanSetVolume: !!media,
          CanFavorite: controls && liked !== null, CanShuffle: false, CanLoop: false } },
      async execute(action, value) {
        if (!controls) return "unsupported";
        if (["Play", "Pause", "PlayPause"].includes(action)) {
          const shouldPlay = action === "Play" || (action === "PlayPause" && paused);
          if (media) { if (shouldPlay) await media.play(); else media.pause(); }
          else if (shouldPlay === paused) play.click();
        } else if (action === "Next" || action === "Previous") {
          const target = action === "Next" ? next : previous;
          if (!usable(target)) return "unsupported";
          target.click();
        } else if (action === "SetPosition") {
          if (!this.state.capabilities.CanSeek) return "unsupported";
          if (!finite(value) || value > length) return "invalid-value";
          media.currentTime = value;
        } else if (action === "Seek") {
          if (!this.state.capabilities.CanSeek) return "unsupported";
          if (!Number.isFinite(value) || value < -3600 || value > 3600) return "invalid-value";
          media.currentTime = Math.max(0, Math.min(length, media.currentTime + value));
        } else if (action === "SetVolume") {
          if (!media) return "unsupported";
          if (!finite(value) || value > 1) return "invalid-value";
          media.volume = value;
        } else if (action === "Favorite") {
          if (!this.state.capabilities.CanFavorite) return "unsupported";
          favorite.click();
        } else return "unsupported";
        return "success";
      }
    };
  }
  root.NookisleAdapter = { adapter };
})(globalThis);
