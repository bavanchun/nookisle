import QtQuick
import QtTest
import "../../qml/Spectrum.js" as Spectrum

TestCase {
    name: "SpectrumFrames"
    // Six seconds of real helper output at 15 lines a second, captured from
    // the pink-noise fixture the performance cohorts play.
    readonly property var pinkNoise: [
        "29 28 28 18 22 21 28 31 35 30 37 35",
        "24 23 23 15 19 33 35 28 32 28 34 33",
        "30 25 26 22 30 31 29 31 32 34 33 35",
        "36 25 21 18 27 25 32 30 32 31 32 33",
        "30 20 28 29 22 28 27 29 29 31 30 32",
        "24 32 34 27 24 27 22 33 28 31 31 35",
        "20 26 28 23 28 22 27 29 33 33 31 36",
        "23 22 23 18 29 27 25 27 27 32 32 30",
        "21 22 19 27 27 28 28 26 28 34 32 34",
        "30 23 19 22 25 24 32 28 30 31 32 32",
        "26 27 22 24 20 26 29 31 29 31 34 35",
        "26 22 21 20 25 28 28 29 29 32 32 35",
        "32 23 17 19 24 26 23 30 30 31 32 39",
        "26 19 21 22 29 27 26 32 34 29 32 35",
        "21 26 23 24 24 27 28 31 33 32 37 37",
        "40 21 28 30 21 27 33 33 33 33 35 35",
        "33 18 23 31 24 30 27 27 29 31 39 34",
        "27 26 33 25 30 29 24 28 30 32 32 36",
        "25 27 27 23 29 28 25 28 28 34 31 36",
        "31 22 22 23 24 32 27 23 33 31 33 38",
        "26 27 22 28 28 29 24 29 29 35 34 34",
        "24 22 24 23 23 27 25 27 32 29 32 37",
        "33 30 19 19 32 36 23 28 33 30 31 35",
        "27 25 16 15 26 30 28 23 34 30 36 33",
        "22 20 23 15 22 24 26 29 29 33 32 36",
        "18 19 19 21 26 22 29 28 29 33 33 37",
        "24 16 15 18 23 28 28 25 29 32 34 33",
        "19 15 17 25 27 25 28 26 28 35 35 32",
        "30 19 17 21 22 27 29 26 27 32 34 37",
        "31 18 28 23 20 25 24 29 28 30 34 31",
        "26 34 28 19 25 22 28 30 29 35 32 34",
        "29 28 23 20 30 24 26 28 33 30 33 37",
        "24 23 19 29 29 22 28 33 34 30 33 37",
        "22 21 24 24 27 27 31 32 30 30 31 33",
        "21 17 20 20 32 23 34 28 32 32 34 34",
        "32 19 16 27 33 25 33 25 28 30 35 34",
        "29 16 22 22 28 28 27 28 29 30 33 32",
        "25 17 24 25 27 23 26 30 28 33 38 33",
        "20 22 26 24 22 24 32 25 32 29 31 37",
        "17 18 21 22 23 23 26 29 30 29 34 34",
        "23 14 18 23 27 27 23 31 36 34 36 34",
        "26 24 23 26 26 22 26 27 35 32 36 39",
        "22 25 25 33 29 28 26 29 39 32 29 34",
        "18 20 21 27 26 28 27 29 35 29 33 36",
        "30 25 17 22 22 32 28 24 29 31 38 35",
        "25 20 18 27 31 26 27 25 31 30 33 35",
        "30 29 29 24 25 22 30 29 33 33 31 36",
        "24 24 24 20 21 33 29 31 31 32 30 34",
        "23 22 26 27 28 27 25 26 30 36 32 35",
        "24 30 21 22 23 25 35 33 31 30 35 30",
        "35 25 18 21 21 28 29 27 30 33 34 32",
        "28 27 19 17 24 23 25 33 28 31 31 36",
        "23 28 23 18 28 24 29 28 30 34 30 36",
        "25 23 27 20 28 21 30 26 29 33 33 34",
        "30 20 30 25 27 17 25 28 35 35 32 38",
        "24 29 25 21 23 20 30 28 31 36 31 36",
        "29 26 20 17 18 16 28 29 26 29 34 36",
        "30 32 24 14 20 25 29 26 33 30 34 35",
        "34 30 20 17 28 21 29 27 28 32 33 33",
        "35 32 29 14 29 26 24 28 30 33 35 36",
        "29 26 24 24 24 22 28 31 30 33 36 35",
        "32 25 20 26 24 18 28 30 28 34 33 33",
        "26 20 18 21 30 33 25 31 35 30 34 33",
        "21 17 14 22 28 28 26 27 31 32 34 35",
        "18 16 20 18 30 23 25 29 27 31 34 36",
        "14 18 20 21 25 33 25 30 30 29 35 35",
        "12 17 24 21 23 27 28 33 34 35 34 37",
        "19 28 29 19 30 22 32 28 31 30 30 31",
        "15 23 24 21 29 28 30 29 33 32 30 33",
        "15 24 20 17 30 26 25 26 28 31 33 36",
        "33 31 24 20 24 26 31 29 29 35 33 36",
        "27 26 20 16 20 36 26 24 27 29 32 39",
        "22 28 26 29 22 30 30 27 33 32 34 34",
        "18 23 22 24 18 25 26 28 28 30 33 33",
        "16 19 30 27 27 26 23 23 29 32 36 36",
        "27 18 24 22 22 30 24 25 29 29 32 31",
        "22 18 20 29 21 25 23 31 33 29 33 33",
        "28 15 17 29 27 25 27 29 31 33 34 34",
        "23 16 29 25 22 30 31 31 31 31 36 35",
        "28 28 25 25 25 28 26 31 30 31 30 36",
        "37 23 20 23 22 27 25 27 29 32 30 32",
        "38 19 25 19 18 22 29 25 31 30 32 34",
        "31 19 23 29 22 27 25 28 25 35 33 35",
        "29 21 25 24 19 22 24 32 31 31 32 32",
        "26 17 23 20 24 18 26 29 32 29 32 31",
        "23 17 19 23 29 30 28 30 34 29 31 38",
        "32 28 22 27 24 28 29 28 28 31 33 33",
        "26 23 18 26 30 23 27 25 32 26 33 36",
        "21 20 21 22 24 28 27 26 31 32 27 35",
        "24 16 19 25 25 32 26 26 34 34 36 34"
    ]
    function levels(line) {
        return Spectrum.parse(line)
    }
    function test_parse() {
        compare(Spectrum.parse("0 1 2 3 4 5 6 7 8 9 10 99"), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 99])
        compare(Spectrum.parse(" 0 1 2 3 4 5 6 7 8 9 10 11 "), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        var bad = ["1 2 x", "1 2 3 4 5 6 7 8 9 10 11 12 13", "1 2 3 4 5 6 7 8 9 10 11 100",
            "1 2 3 4 5 6 7 8 9 10 11 1.5", "1 2 3 4 5 6 7 8 9 10  11", "0x1 2 3 4 5 6 7 8 9 10 11 12",
            "1e1 2 3 4 5 6 7 8 9 10 11 12", ""]
        for (var i = 0; i < bad.length; ++i)
            compare(Spectrum.parse(bad[i]), null, bad[i])
    }
    // An identical line produces no repaint; nor does one that moves no bar
    // by the deadband.
    function test_identicalAndNearIdenticalLinesAreDropped() {
        var shown = [40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40]
        verify(!Spectrum.shouldDraw(shown, shown.slice(), 14))
        var near = shown.slice()
        near[3] += 6
        near[7] -= 6
        verify(!Spectrum.shouldDraw(shown, near, 14), "every bar moves less than one pixel")
        near[5] += 8
        verify(Spectrum.shouldDraw(shown, near, 14), "one bar moving a pixel draws")
    }
    function test_nothingOnScreenAlwaysDraws() {
        verify(Spectrum.shouldDraw([], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 14))
        verify(Spectrum.shouldDraw(null, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 14))
    }
    function test_singleBandUsesRenderedPixelSpan() {
        var shown = [40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40]
        var next = shown.slice()
        next[3] = 45
        verify(!Spectrum.shouldDraw(shown, next, 18), "five levels move less than one pixel in an 18 px span")
        next[3] = 46
        verify(Spectrum.shouldDraw(shown, next, 18), "six levels move a bar more than one pixel without a hairline")
        next[3] = 47
        verify(!Spectrum.shouldDraw(shown, next, 14), "seven levels still move less than one pixel in a 14 px span")
        next[3] = 48
        verify(Spectrum.shouldDraw(shown, next, 14), "eight levels move a bar more than one pixel with a hairline")
    }
    // Small steps against the line on screen add up: drift cannot hide.
    function test_slowDriftStillDraws() {
        var shown = [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]
        var next = shown.slice()
        var drawn = 0
        for (var step = 0; step < 20; ++step) {
            next = next.map(function (v) { return v + 1 })
            if (Spectrum.shouldDraw(shown, next, 14)) {
                shown = next
                drawn++
            }
        }
        compare(drawn, 2, "one-level steps draw every eight levels in a 14 px span")
        compare(shown[0], 66)
    }
    // A fading line settles flat instead of resting up to 2 px high.
    function test_quietLinesSettleFlat() {
        var shown = [12, 10, 8, 6, 12, 10, 8, 6, 12, 10, 8, 6]
        verify(Spectrum.shouldDraw(shown, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 14))
        verify(!Spectrum.shouldDraw([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 14))
    }
    // On real helper output the screen follows every visible move, yet a
    // good share of lines never repaint, and no bar is ever a deadband from
    // the latest line.
    function test_pinkNoiseDrawsUnderHalfTheLines() {
        var shown = [], drawn = 0, worst = 0
        for (var i = 0; i < pinkNoise.length; ++i) {
            var next = levels(pinkNoise[i])
            verify(next, "line " + i + " is valid")
            if (Spectrum.shouldDraw(shown, next, 14)) {
                shown = next
                drawn++
            }
            for (var b = 0; b < next.length; ++b)
                worst = Math.max(worst, Math.abs(next[b] - shown[b]))
        }
        verify(drawn <= pinkNoise.length * 0.8, "drawn " + drawn + " of " + pinkNoise.length)
        verify(drawn >= pinkNoise.length * 0.5, "but the bars keep moving: " + drawn)
        verify(worst * 14 / 99 < 1, "no bar strays a pixel from the latest line: " + worst)
    }
}
