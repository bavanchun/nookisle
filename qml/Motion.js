.pragma library

// Closed-form spring curves. A spring here is SwiftUI's (response, damping):
// natural frequency w = 2*pi / response and damping ratio z = damping. Island
// motion drives one finite NumberAnimation on t and maps it through these
// curves, so it matches the spring exactly and the scene graph goes quiet
// when the animation ends. All times are in seconds.

// Below this fraction of the travel the spring counts as settled.
var SETTLE = 0.005
var MAX_DURATION = 0.8

function omega(response) {
    return 2 * Math.PI / response
}

// Step response of a unit spring released at 0 with no velocity toward 1.
function springStep(t, response, damping) {
    if (t <= 0) return 0
    var w = omega(response), z = damping
    if (z < 1) {
        var wd = w * Math.sqrt(1 - z * z)
        return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + z * w / wd * Math.sin(wd * t))
    }
    if (z === 1)
        return 1 - Math.exp(-w * t) * (1 + w * t)
    var root = Math.sqrt(z * z - 1)
    var r1 = -w * (z - root), r2 = -w * (z + root)
    return 1 + (r2 * Math.exp(r1 * t) - r1 * Math.exp(r2 * t)) / (r1 - r2)
}

// The largest distance from 1 the spring can still reach after t: the decay
// envelope when under-damped, and the remaining gap otherwise, which then
// only shrinks.
function envelope(t, response, damping) {
    if (damping < 1)
        return Math.exp(-damping * omega(response) * t) / Math.sqrt(1 - damping * damping)
    return 1 - springStep(t, response, damping)
}

// The time at which the envelope falls below SETTLE, capped at MAX_DURATION.
function springDuration(response, damping) {
    if (damping <= 0) return MAX_DURATION
    if (damping < 1) {
        var t = Math.log(1 / (SETTLE * Math.sqrt(1 - damping * damping))) / (damping * omega(response))
        return Math.min(t, MAX_DURATION)
    }
    if (envelope(MAX_DURATION, response, damping) > SETTLE) return MAX_DURATION
    var low = 0, high = MAX_DURATION
    for (var i = 0; i < 60; ++i) {
        var mid = (low + high) / 2
        if (envelope(mid, response, damping) > SETTLE) low = mid
        else high = mid
    }
    return high
}

// The spring over [0, duration], scaled so it ends exactly at 1.
function normalised(t, response, damping, duration) {
    if (duration <= 0 || t >= duration) return 1
    return springStep(t, response, damping) / springStep(duration, response, damping)
}

// Whether `hyprctl getoption animations:enabled -j` says the desktop runs
// without animations, which the island takes as a wish for reduced motion.
// Anything unreadable says no.
function desktopReducesMotion(json) {
    try {
        var option = JSON.parse(String(json || ""))
        return !!option && typeof option === "object" && option.int === 0
    } catch (error) {
        return false
    }
}
