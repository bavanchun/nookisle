.pragma library

// How the open header's right-hand entries share the room beside the centre
// span. The room is fixed (the header's side width), and nothing may cross
// into the centre, which sits under a camera cutout when there is one.
//
// `slots` lists the shown entries by priority, most important first:
// { key, width, compact } where `compact` is the entry's narrower form (the
// battery without its percentage, Timers without its time left) or absent.
// The plan, in order, stops at the first step that fits:
//   1. every entry at full width;
//   2. compact forms, taken from the least important entry up;
//   3. an overflow button at the row's inner end, with the least important
//      entries folded into its menu until the rest fit beside it.
// Folding keeps priority strict: an entry never stays in the row while a
// more important one is folded. Returns { compact: { key: bool },
// inline: [keys], folded: [keys], overflow: bool, width }.

// Priority, most important first: an active recording's Stop, the battery,
// Timers, the mirror toggle, then the settings gear.
var PRIORITY = ["recording", "battery", "timers", "camera", "settings"]

function span(widths, spacing) {
    var total = 0
    for (var i = 0; i < widths.length; ++i)
        total += widths[i]
    return widths.length ? total + spacing * (widths.length - 1) : 0
}

function plan(slots, room, spacing, overflowWidth) {
    var compact = {}, widths = []
    for (var i = 0; i < slots.length; ++i) {
        compact[slots[i].key] = false
        widths.push(slots[i].width)
    }
    var keys = slots.map(function (slot) { return slot.key })
    if (span(widths, spacing) <= room)
        return { compact: compact, inline: keys, folded: [], overflow: false, width: span(widths, spacing) }
    for (var j = slots.length - 1; j >= 0; --j) {
        if (slots[j].compact === undefined || slots[j].compact >= slots[j].width)
            continue
        compact[slots[j].key] = true
        widths[j] = slots[j].compact
        if (span(widths, spacing) <= room)
            return { compact: compact, inline: keys, folded: [], overflow: false, width: span(widths, spacing) }
    }
    var inline = [], kept = [overflowWidth]
    for (var k = 0; k < slots.length; ++k) {
        if (span(kept.concat([widths[k]]), spacing) > room)
            break
        kept.push(widths[k])
        inline.push(slots[k].key)
    }
    return { compact: compact, inline: inline, folded: keys.slice(inline.length), overflow: true,
        width: span(kept, spacing) }
}
