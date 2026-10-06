.pragma library

function clamp(value) {
    if (!isFinite(value)) return 0
    return Math.max(0, Math.min(1, Number(value)))
}

function fromPosition(x, width) {
    if (!isFinite(x) || !isFinite(width) || width <= 0) return null
    return clamp(x / width)
}

// Display writes never go below 1 %, so the preview does not either.
function floorFor(kind, value) { return kind === "brightness" ? Math.max(0.01, value) : value }

function percent(value) { return Math.round(clamp(value) * 100) }

function adjustable(kind) {
    return kind === "volume" || kind === "brightness" || kind === "keyboard"
}
