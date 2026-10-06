# Exact-document browser transport

This optional MV3 extension targets only HTTPS `www.youtube.com`, `music.youtube.com`, and `open.spotify.com` top-level documents. It requests `nativeMessaging` and reconnect alarms, not browsing history, all-sites access, or active-tab control. This repository does **not** install or enable it in a Chrome profile. Site adapters use currently available media elements and site controls; absent, hidden, or ambiguous controls are unsupported. In particular, Spotify's DRM player may expose buttons but no seek/volume media element. Site updates can invalidate selectors; unit and isolated transport tests do not establish live site compatibility.

## Explicit registration

When browser installation is authorized, load the packaged `browser/chrome/` directory (or from the installed plugin at `~/.config/omarchy/plugins/io.github.bavanchun.nookisle/browser/chrome/`) using Chrome's unpacked-extension workflow. Record its exact 32-character extension ID from Chrome's Extensions page; unpacked IDs depend on the installation path, so moving that directory requires regenerating registration. Then generate artifacts in a new staging directory:

```sh
python3 ~/.config/omarchy/plugins/io.github.bavanchun.nookisle/bridge/write-native-manifests.py \
  --extension-id EXACT_EXTENSION_ID \
  --binary ~/.config/omarchy/plugins/io.github.bavanchun.nookisle/libexec/nookisle-native-host \
  --output-dir "$XDG_RUNTIME_DIR/nookisle-native-staging"
```

Manually register `io.github.bavanchun.nookisle.json` in the intended Chrome user's `~/.config/google-chrome/NativeMessagingHosts/` (or Chromium's `~/.config/chromium/NativeMessagingHosts/`), and `native-host.json` in `${XDG_CONFIG_HOME:-$HOME/.config}/nookisle/`, preserving mode 0600. Then remove the temporary staging directory:

```sh
rm -r "$XDG_RUNTIME_DIR/nookisle-native-staging"
```

These are separate files: Chrome verifies `allowed_origins`, while the native executable verifies the same exact caller origin. Other Chrome channels/profile roots require their documented native-host registration location. Do not use wildcards or copy an unrelated extension ID. Registration files contain no media metadata. Remove these two registered files and disable/remove the extension to roll back; no system service is installed.

The helper must already be running and share the browser's session-bus environment. One authenticated Chrome extension/profile connection is admitted at a time; other profile connections fail closed and retry, never merging colliding tab IDs. Chrome owns the native process only while its native port is connected. The native host never starts another helper, reconnects to a different desktop session, or logs URLs, titles, socket secrets, or messages. Removing the final supported content port closes the native process. Worker disconnect invalidates the bridge session and all pending commands; reconnect uses a fresh session and republishes current documents without replaying commands.

## Protocol and lifetime

The Chrome-owned native executable uses POSIX polling and UNIX sockets with header-only `nlohmann/json` (3.11 or later) and OpenSSL Crypto for JSON parsing and the existing SHA-256 session key. It does not load Qt. The core browser registry still uses the helper's QtCore/QtNetwork runtime. Building requires the nlohmann-json headers/CMake package and OpenSSL development package in addition to the helper's existing dependencies. JSON is restricted to UTF-8 objects with a maximum nesting depth of 32; no private parser or cryptographic implementation is bundled. Both input directions use the same strict parser and reject malformed frames without forwarding or silently discarding nested data.

The core's existing exclusive lease protects a private `0700` directory under `XDG_RUNTIME_DIR`, keyed by the first 16 hexadecimal SHA-256 characters of `DBUS_SESSION_BUS_ADDRESS`. The core creates `browser.sock` and a `0600` `browser.json` capability file there. Both peers verify the connected UID with `SO_PEERCRED`. The native host reads non-symlink, same-owner, private regular configuration files and authenticates with the runtime secret before the core issues a fresh `bridgeSession`.

Chrome framing is native-endian unsigned 32-bit length plus UTF-8 JSON. The socket uses compact JSON lines. Both cap individual frames at 64 KiB and outbound queues at 128 KiB, aborting malformed/oversized input and incomplete EOF. Native startup authentication has a 3-second deadline. The core caps 64 documents and 16 pending commands, applies its admission gate, and expires commands after 3 seconds. Browser state is capped at 8 KiB including the envelope. No same-user malware isolation is claimed: a same-UID process can access same-user configuration and runtime capabilities.

Every endpoint captures `{busEpoch, transport: "extension", bridgeSession, tabId, documentId, frameId: 0, mediaGeneration}`. Commands must match all fields. Document ports are checked against Chrome-provided sender URL, tab ID, document ID and frame ID. Only media-element replacement or document transport restoration advances `mediaGeneration`; track identity and SPA route changes advance a separate `trackGeneration`, retaining the selected endpoint while making old seeks stale. BFCache restoration creates a new media lifetime without reloading the page. Neither a reused tab ID nor a similarly titled MPRIS source is a fallback. Successful results mean the selected site's method or button was invoked, not proof the remote service completed playback.

`browserState` publishes the captured endpoint and bounded presentation/capabilities; `browserGone` removes the document. The core sends `browserCommand` and `browserSubscribe`; replies are `browserResult`. A visible, playing subscription samples at the requested bounded 100–250 ms or 1-second cadence. Hidden/paused/disconnected/locked subscriptions stop sampling. Normal media and DOM changes publish throttled state without a permanent polling loop. A bounded HTTPS artwork URL can be offered to the core's shared safe artwork loader (on YouTube, the current video's `i.ytimg.com` thumbnail, derived from the video id in the page URL (`/watch?v=`, `/shorts/`, `/live/` or `/embed/`; a playlist embed names no video and offers none), because the page head's image link stays on the tab's first video across in-page navigation); the browser transport itself neither fetches nor decodes it, and QML receives only the core's resulting local path.

Primary API references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [runtime ports and document senders](https://developer.chrome.com/docs/extensions/reference/api/runtime), and [MV3 worker lifetime](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle).
