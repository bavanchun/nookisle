.pragma library

// The first-run onboarding steps as a pure state machine. A state is
// { index, direction, skipped, finished }: index into STEPS, the direction of
// the last move (1 forward, -1 back) for the slide, the ids skipped so far,
// and whether the flow is complete. Every function returns a new state.

// Each step between Welcome and Done offers real choices; nothing changes
// until the person picks, so skipping a step keeps its defaults.
var STEPS = [
    { id: "welcome", title: "Welcome" },
    { id: "look", title: "The idle notch" },
    { id: "media", title: "Media" },
    { id: "calendar", title: "Calendar" },
    { id: "camera", title: "Camera mirror" },
    { id: "shortcuts", title: "Keys and placement" },
    { id: "done", title: "All set" }
]

// The settings each step offers, in order, as schema keys. A key the
// schema does not have is left out, so a later style setting shows up here
// by being added to the list.
var STEP_SETTINGS = {
    look: ["idleStyle", "remoteArtwork"],
    media: ["lyrics", "peek"],
    calendar: ["showCalendar"],
    camera: ["showMirror"]
}

function start() {
    return { index: 0, direction: 1, skipped: [], finished: false }
}

function step(state) {
    return STEPS[state.index]
}

function isLast(state) {
    return state.index === STEPS.length - 1
}

function moved(state, index, direction, skipped) {
    return { index: index, direction: direction, skipped: skipped, finished: false }
}

// Forward one step; on the last step, finish.
function next(state) {
    if (state.finished) return state
    if (isLast(state)) return { index: state.index, direction: 1, skipped: state.skipped.slice(), finished: true }
    return moved(state, state.index + 1, 1, state.skipped.slice())
}

function back(state) {
    if (state.finished || state.index === 0) return state
    return moved(state, state.index - 1, -1, state.skipped.slice())
}

// Forward one step, recording the current one as skipped. Skipping the last
// step finishes, like next().
function skip(state) {
    if (state.finished) return state
    var skipped = state.skipped.slice()
    if (!isLast(state) && skipped.indexOf(step(state).id) < 0) skipped.push(step(state).id)
    return isLast(state) ? next(state) : moved(state, state.index + 1, 1, skipped)
}

// Closing (Escape or the window's close): finished, with every step not
// yet reached recorded as skipped.
function close(state) {
    if (state.finished) return state
    var done = skipAll(state)
    return { index: done.index, direction: 1, skipped: done.skipped, finished: true }
}

// Straight to Done, recording every step passed over as skipped.
function skipAll(state) {
    if (state.finished) return state
    var skipped = state.skipped.slice()
    for (var i = state.index; i < STEPS.length - 1; ++i)
        if (skipped.indexOf(STEPS[i].id) < 0) skipped.push(STEPS[i].id)
    return moved(state, STEPS.length - 1, 1, skipped)
}
