.pragma library

// Which spectrum lines reach the screen. Each line the shell draws costs
// about 1 ms of CPU, whatever the bars bind, so the collapsed-playing cost
// follows the number of lines drawn, not the number received.
//
// Compare with the line on screen, not the previous line, so slow drift
// eventually draws. The span is the actual travel of a bar above its minimum
// height; 99 levels cover that span. Draw every move of at least one pixel,
// including when the notch has no progress hairline and the bars are taller.
// Quiet lines still draw when they differ, letting the bars settle flat.

// Exactly 12 decimal integers 0..99, single-space separated. Number() alone
// would also take "", "0x1" or "1e1".
var LINE = /^\d{1,2}(?: \d{1,2}){11}$/

// The levels of a valid line, or null.
function parse(line) {
    var text = String(line).trim()
    return LINE.test(text) ? text.split(" ").map(Number) : null
}

function quiet(levels, barSpan) {
    for (var i = 0; i < levels.length; ++i)
        if (levels[i] * barSpan >= 99)
            return false
    return true
}

// Whether `next` should replace `shown` (the levels on screen; empty when
// nothing is). With unknown geometry, draw rather than miss a visible move.
function shouldDraw(shown, next, barSpan) {
    if (!shown || shown.length !== next.length || !isFinite(barSpan) || barSpan <= 0)
        return true
    var changed = false
    for (var i = 0; i < next.length; ++i) {
        var delta = Math.abs(next[i] - shown[i])
        if (delta * barSpan >= 99)
            return true
        if (delta > 0)
            changed = true
    }
    return changed && quiet(next, barSpan)
}
