.pragma library

// The drag catch zone: while the island is closed, a bar-high drop region
// wider than the closed body lets a file drag near the notch open the shelf.
// It only ever covers empty bar centre space, so it exists only while the
// bar's centre section holds nothing but the island's own spacer.

function entryId(entry) {
    return entry && typeof entry === "object" ? entry.id : entry
}

// True when the bar centre holds any entry besides this plugin's spacer.
function centreShared(layout, pluginId) {
    var centre = layout && Array.isArray(layout.center) ? layout.center : []
    return centre.some(function(entry) { return entryId(entry) !== pluginId })
}

// The host bar lays out a centre holder filling the bar, plus one module row
// anchored left and one anchored right. Given the bar's width, the holder's
// width and the holder's siblings ({x, width} in bar coordinates), returns
// {left, right}, or null when the layout is not that shape.
function classifyRows(barWidth, holderWidth, siblings) {
    if (!(barWidth > 0) || holderWidth < barWidth - 1 || !Array.isArray(siblings)) return null
    var left = [], right = []
    siblings.forEach(function(row) {
        if (row.x + row.width / 2 < barWidth / 2) left.push(row)
        else right.push(row)
    })
    return left.length === 1 && right.length === 1 ? { left: left[0], right: right[0] } : null
}

// The empty bar width centred on `centre` between the two rows: twice the
// nearer gap, 0 when a row reaches the centre, -1 when the rows are unknown.
function freeSpan(centre, rows) {
    if (!rows) return -1
    var gap = Math.min(centre - (rows.left.x + rows.left.width), rows.right.x - centre)
    return Math.max(0, Math.floor(2 * gap))
}

// The catch width for one surface state, or 0 while there is no zone:
// {enabled, expanded, interactive, dropIn, shared, requested, body, limit}.
// `body` is the closed body's width and `limit` the free centre span; an
// unknown span (negative) means no zone rather than a guess.
function width(state) {
    if (!state.enabled || state.expanded || !state.interactive || !state.dropIn || state.shared) return 0
    if (!(state.limit >= 0)) return 0
    return Math.max(state.body, Math.min(state.requested, state.limit))
}

// Whether the island's spacer sits away from the bar's middle, which means
// it is not the bar's centre anchor and the notch covers the wrong place.
// Two pixels absorb rounding.
function offCentre(centre, barWidth) {
    return barWidth > 0 && Math.abs(centre - barWidth / 2) > 2
}
