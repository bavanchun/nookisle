.pragma library

// The camera tile's capture format. Left to itself QtMultimedia picks the
// device's default, which can be far larger than the tile or soft and small,
// so the tile asks for the smallest format at least twice its size in both
// directions: sharp at 2x without decoding more than it shows. Among equal
// sizes the higher frame rate wins. When no format is large enough, the
// largest one is the best available.
//
// formats: the device's videoFormats (each {resolution: {width, height},
// maxFrameRate}); returns one of them, or null for an empty list.
function pick(formats, tileWidth, tileHeight) {
    var list = formats && formats.length !== undefined ? Array.prototype.slice.call(formats) : []
    var needWidth = Math.ceil(2 * Math.max(0, Number(tileWidth) || 0))
    var needHeight = Math.ceil(2 * Math.max(0, Number(tileHeight) || 0))
    function area(format) { return format.resolution.width * format.resolution.height }
    function rate(format) { return Number(format.maxFrameRate) || 0 }
    var best = null, largest = null
    for (var i = 0; i < list.length; ++i) {
        var format = list[i]
        if (!format || !format.resolution || !(format.resolution.width > 0) || !(format.resolution.height > 0))
            continue
        if (!largest || area(format) > area(largest) || (area(format) === area(largest) && rate(format) > rate(largest)))
            largest = format
        if (format.resolution.width < needWidth || format.resolution.height < needHeight)
            continue
        if (!best || area(format) < area(best) || (area(format) === area(best) && rate(format) > rate(best)))
            best = format
    }
    return best || largest
}
