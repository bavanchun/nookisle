.pragma library

// Pure key and wheel arithmetic for the island. The key codes and modifier
// masks arrive in a `codes` table from the QML caller, so nothing here needs
// a Qt import and the tests can drive it with the real Qt.Key_* values.
//
// codes: {space, left, right, up, down, n, p, tab, backtab, returnKey, enter,
//         shift, blocked}
// `blocked` is the Ctrl|Alt|Meta mask: a chord with any of them is left alone,
// so application and compositor shortcuts never turn into playback actions.

var SEEK_STEP = 5
var VOLUME_STEP = 0.05

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

// Wheel volume: up never pushes past 100 %, and never pulls a sink that was
// over-amplified elsewhere back down; down always steps, and stops at 0.
function nextVolume(current, delta) {
    var level = Number(current) || 0
    return delta > 0 ? Math.min(Math.max(1, level), level + delta) : Math.max(0, level + delta)
}

// The HUD bar's absolute volume: 0..100 %, never over-amplified.
function absoluteVolume(level) {
    return clamp(Number(level) || 0, 0, 1)
}

// Which keyboard focus the Panel's layer asks for. A summoned (explicitly
// opened) island takes the keyboard exclusively: Hyprland did not hand focus
// to the already-mapped on-demand layer when its interactivity flipped, so
// summoned keys went to the window underneath. A hover-opened island never
// takes the keyboard. While the
// island lends the keyboard to a settings or welcome window it opened
// (`lent`), it gives up the grab: an exclusive layer would keep every key
// from that window.
function keyboardFocus(visible, explicitOpen, islandExpanded, lent) {
    return visible && explicitOpen && islandExpanded && lent !== true ? "exclusive" : "none"
}

// The capability each playback action needs, matching the expanded
// transport's own enable rules (PlayerPanel), so a key or a swipe never
// sends what the matching button would refuse.
function canInvoke(action, state) {
    var caps = state && state.capabilities ? state.capabilities : {}
    if (caps.CanControl !== true)
        return false
    switch (action) {
    case "PlayPause":
        return state.playing ? caps.CanPause === true : caps.CanPlay === true
    case "Next":
        return caps.CanGoNext === true
    case "Previous":
        return caps.CanGoPrevious === true
    case "SetPosition":
        return caps.CanSetPosition === true && Number(state.lengthSeconds) > 0
    case "SetVolume":
        return caps.CanSetVolume === true
    }
    return false
}

function step(views, current, delta) {
    if (!views || !views.length)
        return null
    var index = views.indexOf(current)
    var next = index < 0 ? 0 : (index + delta + views.length) % views.length
    return views[next]
}

// Returns null (not handled, so the key propagates or does nothing), or one of
// {invoke: "PlayPause"|"Next"|"Previous"}, {invoke: "SetPosition", value},
// {invoke: "SetVolume", value}, {view: name}, {enter: true}.
// `rootFocused` is true only while the surface root itself holds focus: Tab,
// Shift+Tab and Return then belong to the island, and anywhere inside a view
// they keep their normal traversal and activation.
// state: {capabilities, playing, positionSeconds, lengthSeconds, volume,
//         views, view}
function resolve(key, modifiers, rootFocused, state, codes) {
    if (!codes || !state || (modifiers & codes.blocked))
        return null
    function action(name, value) {
        if (!canInvoke(name, state))
            return null
        return value === undefined ? {invoke: name} : {invoke: name, value: value}
    }
    var length = Number(state.lengthSeconds) || 0
    var position = Number(state.positionSeconds) || 0
    var volume = Number(state.volume) || 0
    switch (key) {
    case codes.space:
        return action("PlayPause")
    case codes.left:
    case codes.right:
        return action("SetPosition", clamp(position + (key === codes.left ? -SEEK_STEP : SEEK_STEP), 0, Math.max(0, length - 1)))
    case codes.up:
    case codes.down:
        return action("SetVolume", clamp(volume + (key === codes.up ? VOLUME_STEP : -VOLUME_STEP), 0, 1))
    case codes.n:
        return action("Next")
    case codes.p:
        return action("Previous")
    case codes.tab:
    case codes.backtab:
        if (!rootFocused)
            return null
        var backwards = key === codes.backtab || (modifiers & codes.shift) !== 0
        var view = step(state.views, state.view, backwards ? -1 : 1)
        return view === null ? null : {view: view}
    case codes.returnKey:
    case codes.enter:
        return rootFocused ? {enter: true} : null
    }
    return null
}
