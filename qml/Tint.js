.pragma library

// Pure colour math for the artwork tint. Every colour is a plain {r, g, b}
// object in 0..1, so the tests need no QML colour type and nothing here
// depends on the theme: DesignTokens passes the live palette in.

// A graphic (bar, fill, glow) must reach this against the surface, and the
// tinted card must keep body text and secondary text readable (WCAG 1.4.11
// and 1.4.3).
var GRAPHIC_CONTRAST = 3
var TEXT_CONTRAST = 4.5
var SECONDARY_CONTRAST = 3
var LIGHTNESS_STEP = 0.04
var LIGHTNESS_STEPS = 12

function channel(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
}

// WCAG relative luminance with sRGB linearisation.
function luminance(c) {
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

function hsl(c) {
    var max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b)
    var l = (max + min) / 2, d = max - min
    if (d === 0)
        return { h: 0, s: 0, l: l }
    var s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    var h
    if (max === c.r)
        h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0)
    else if (max === c.g)
        h = (c.b - c.r) / d + 2
    else
        h = (c.r - c.g) / d + 4
    return { h: h / 6, s: s, l: l }
}

function hueChannel(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
}

function fromHsl(h, s, l) {
    if (s === 0)
        return { r: l, g: l, b: l }
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s
    var p = 2 * l - q
    return { r: hueChannel(p, q, h + 1 / 3), g: hueChannel(p, q, h), b: hueChannel(p, q, h - 1 / 3) }
}

// The most vivid usable colour of a palette, or null when none qualifies (a
// greyscale or near-black cover). Near-black, near-white and washed-out
// colours are skipped; the rest score by saturation, favouring a mid
// lightness that reads on both dark and light themes.
function pick(colors) {
    var best = null, bestScore = 0
    for (var i = 0; colors && i < colors.length; ++i) {
        var c = colors[i]
        if (!c || !isFinite(c.r) || !isFinite(c.g) || !isFinite(c.b))
            continue
        var v = hsl(c)
        if (v.l < 0.12 || v.l > 0.92 || v.s < 0.18)
            continue
        var score = v.s * (1 - Math.abs(v.l - 0.55) * 1.4)
        if (score > bestScore) {
            bestScore = score
            best = { r: c.r, g: c.g, b: c.b }
        }
    }
    return best
}

// The floor a graphic's artwork colour is lifted to on the black notch:
// saturation at least VIBRANT_SATURATION and lightness within
// VIBRANT_LIGHTNESS, so an olive or brown cover lights the spectrum and
// slider as gold or amber. A near-grey colour (saturation under
// NEUTRAL_SATURATION) keeps its own values, so grey never turns a hue.
var VIBRANT_SATURATION = 0.45
var VIBRANT_LIGHTNESS = [0.55, 0.7]
var NEUTRAL_SATURATION = 0.12
function vibrant(c) {
    var v = hsl(c)
    if (v.s < NEUTRAL_SATURATION)
        return { r: c.r, g: c.g, b: c.b }
    return fromHsl(v.h, Math.max(v.s, VIBRANT_SATURATION),
        Math.min(VIBRANT_LIGHTNESS[1], Math.max(VIBRANT_LIGHTNESS[0], v.l)))
}

// The strongest wash of the tint into the card: the card never mixes in
// more than this, on a light or a dark theme.
function cardWash(light) {
    return light ? 0.07 : 0.10
}

// Whether a graphic in colour c reads at 3:1 both on the plain surface and
// on the card washed with c itself at `wash`. The wash pulls the card toward
// c, so the plain surface alone overstates the contrast the bars, fills and
// hairline really get; mixing in less than `wash` only brings it back up.
function graphicReads(c, surface, wash) {
    return contrast(c, surface) >= GRAPHIC_CONTRAST
        && contrast(c, mix(surface, c, wash || 0)) >= GRAPHIC_CONTRAST
}

// The colour itself when `reads` accepts it; otherwise the first HSL
// lightness step away from the surface that it accepts, or null when twelve
// steps are not enough. The hue and saturation are kept.
function walk(c, surface, reads) {
    if (reads(c))
        return { r: c.r, g: c.g, b: c.b }
    var v = hsl(c)
    var direction = luminance(surface) < 0.4 ? 1 : -1
    for (var i = 1; i <= LIGHTNESS_STEPS; ++i) {
        var l = Math.max(0, Math.min(1, v.l + direction * LIGHTNESS_STEP * i))
        var candidate = fromHsl(v.h, v.s, l)
        if (reads(candidate))
            return candidate
    }
    return null
}

// A graphic colour that reads at 3:1 (see graphicReads), or null.
function guardGraphic(c, surface, wash) {
    return walk(c, surface, function (x) { return graphicReads(x, surface, wash) })
}

// A text colour that reads at 4.5:1 on `background`, or null.
function guardText(c, background) {
    return walk(c, background, function (x) { return contrast(x, background) >= TEXT_CONTRAST })
}

// The label for a fill in colour c: the fill's own hue, deep on a dark
// theme and pale on a light one, as a theme's own label on its accent is.
function fillLabel(c, surface) {
    var v = hsl(c)
    return fromHsl(v.h, Math.min(v.s, 0.5), luminance(surface) < 0.4 ? 0.1 : 0.97)
}

// A filled control in colour c (a primary button, a selected pill): the
// fill reads as a graphic on the surface and the tinted card, and its label
// (fillLabel) reads at 4.5:1 on it. Returns { fill, label }, or null when
// twelve lightness steps cannot get there.
function guardFill(c, surface, wash) {
    var fill = walk(c, surface, function (x) {
        return graphicReads(x, surface, wash) && contrast(fillLabel(x, surface), x) >= TEXT_CONTRAST
    })
    return fill ? { fill: fill, label: fillLabel(fill, surface) } : null
}

// Linear blend of an opaque base, matching Qt.tint(surface, rgba(tint, alpha)).
function mix(surface, tint, alpha) {
    return {
        r: surface.r + (tint.r - surface.r) * alpha,
        g: surface.g + (tint.g - surface.g) * alpha,
        b: surface.b + (tint.b - surface.b) * alpha
    }
}

// The strongest card tint that keeps text and secondary text readable, or 0.
function cardAlpha(tint, surface, text, secondary, light) {
    var alphas = [cardWash(light), 0.05]
    for (var i = 0; i < alphas.length; ++i) {
        var mixed = mix(surface, tint, alphas[i])
        if (contrast(text, mixed) >= TEXT_CONTRAST && contrast(secondary, mixed) >= SECONDARY_CONTRAST)
            return alphas[i]
    }
    return 0
}

// Rec. 709 luma of a gamma-encoded colour: 0.2126 R + 0.7152 G + 0.0722 B.
function luma709(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

// The colour itself when its Rec. 709 luma is at least `minimum`, otherwise
// the colour blended toward white just far enough to reach it, which keeps
// its hue. boring.notch lifts the artist tint to 0.6 this way.
function atLeastLuma(c, minimum) {
    var luma = luma709(c)
    if (luma >= minimum || luma >= 1)
        return { r: c.r, g: c.g, b: c.b }
    var t = (minimum - luma) / (1 - luma)
    return { r: c.r + (1 - c.r) * t, g: c.g + (1 - c.g) * t, b: c.b + (1 - c.b) * t }
}
