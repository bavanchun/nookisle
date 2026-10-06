.pragma library

function rect(x, y, width, height) {
    return { x: x, y: y, width: Math.max(0, width), height: Math.max(0, height) }
}

// The shell may union this rectangle with the closed notch's input region.
// Returning null while inactive makes the input growth a single state change.
function activeRect(active, occupied) {
    return active && occupied && occupied.width > 0 && occupied.height > 0 ? occupied : null
}

function inlineWingWidth(width, centerGap, inset) {
    return Math.max(0, (width - centerGap) / 2 - inset)
}

function belowPosition(notchWidth, pillWidth, notchHeight, gap) {
    return { x: (notchWidth - pillWidth) / 2, y: notchHeight + gap }
}

function capsuleBarWidth(showPercent) { return showPercent ? 65 : 108 }
