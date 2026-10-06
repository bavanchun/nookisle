.pragma library

// Which screens show the island, for the displayMode setting:
//   follow  one island on the focused screen (the first screen when none is
//           focused), moving only while it is closed: the behaviour from
//           before this setting existed;
//   fixed   one island on preferredDisplay, or as follow while that screen
//           is not connected;
//   all     one island on every screen: a primary window, which takes the
//           keyboard summon, on preferredDisplay when it is connected or
//           else the first screen, so it never moves with focus, and one
//           more window for each other screen.
// Screens are passed as their names, in Quickshell.screens order.

var MODES = ["follow", "all", "fixed"]

function mode(value) {
    return MODES.indexOf(value) >= 0 ? value : "follow"
}

function follow(names, focused) {
    if (focused && names.indexOf(focused) >= 0) return focused
    return names.length ? names[0] : ""
}

// The primary island's screen name, or "" with no screens.
function primaryScreen(displayMode, preferred, names, focused) {
    var m = mode(displayMode)
    if (m === "fixed" && preferred && names.indexOf(preferred) >= 0) return preferred
    if (m === "all") return preferred && names.indexOf(preferred) >= 0 ? preferred : (names.length ? names[0] : "")
    return follow(names, focused)
}

// The screens that get a window of their own besides the primary: every
// other screen in "all", none otherwise.
function extraScreens(displayMode, names, primary) {
    if (mode(displayMode) !== "all") return []
    return names.filter(function (name) { return name !== primary })
}

// The island that draws the live spectrum, always a visible one: the one
// under the pointer, else the primary, else the first visible island; the
// primary when none is visible. `islands` is [{name, visible, hovered}],
// primary first.
function spectrumOwner(primary, islands) {
    var shown = islands.filter(function (island) { return island.visible })
    for (var i = 0; i < shown.length; ++i)
        if (shown[i].hovered) return shown[i].name
    if (shown.some(function (island) { return island.name === primary })) return primary
    return shown.length ? shown[0].name : primary
}

// The spectrum's lines pause only while the island drawing them is open;
// another island being open does not freeze a closed owner's bars.
// `islands` is [{name, visible, expanded}].
function spectrumPaused(owner, islands) {
    return islands.some(function (island) { return island.name === owner && island.visible && island.expanded })
}

// The island the pointer is on, for the bars' centre-peek suppression: a
// hovered visible island, else an open visible one, in order (the primary
// first); "" for none. `islands` is [{name, visible, hovered, expanded}].
function pointerIsland(islands) {
    var shown = islands.filter(function (island) { return island.visible })
    for (var i = 0; i < shown.length; ++i)
        if (shown[i].hovered) return shown[i].name
    for (var j = 0; j < shown.length; ++j)
        if (shown[j].expanded) return shown[j].name
    return ""
}

// Only the owner draws the live spectrum, so the bars repaint on one screen,
// not on every one. With one island, it is that one.
function spectrumLive(displayMode, screen, owner) {
    return mode(displayMode) !== "all" || screen === owner
}

// What the Service is told about the island as a whole: visible while any
// window shows one, expanded while any visible one is open. `primary` and
// each of `extras` is {visible, expanded}.
function viewState(primary, extras) {
    var shown = extras.filter(function (extra) { return extra.visible })
    return {
        visible: primary.visible || shown.length > 0,
        expanded: (primary.visible && primary.expanded) || shown.some(function (extra) { return extra.expanded })
    }
}

// The shared level readout is suppressed only when no window can show it:
// the primary's own rule (fullscreen, or open without the open readout)
// holds, and no visible extra is closed, or open with the open readout on.
function readoutSuppressed(primaryBlocked, extras, openReadout) {
    return primaryBlocked && !extras.some(function (extra) {
        return extra.visible && (!extra.expanded || openReadout === true)
    })
}

// Peeks likewise: suppressed only when the primary cannot show one and no
// visible extra is closed.
function peekSuppressed(primaryBlocked, extras) {
    return primaryBlocked && !extras.some(function (extra) { return extra.visible && !extra.expanded })
}

// One camera: of several open islands, only the one opened last may run it.
// The islands open now, in the order they opened, after `screen` opens or
// closes. The camera belongs to the last one: a newly opened island takes
// it, and when its owner closes it goes back to the island opened before,
// or to none, so an island still open never stays dark.
function cameraOpenOrder(order, screen, open) {
    var next = (order || []).filter(function (name) { return name !== screen })
    if (open && screen) next.push(screen)
    return next
}
// Drops the islands whose screen went away: one removed while open (its
// screen unplugged) sent no close. Pruned whenever the screens change, so a
// reconnected screen's new, closed island never inherits the old entry.
function pruneCameraOrder(order, present) {
    return (order || []).filter(function (name) { return present.indexOf(name) >= 0 })
}
function cameraOwnerOf(order) {
    return order && order.length ? order[order.length - 1] : ""
}
function cameraAllowed(displayMode, screen, owner) {
    return mode(displayMode) !== "all" || !owner || screen === owner
}
