.pragma library

// Mirror omarchy-audio-output-sink: a DSP output's stream feeds the sink
// whose volume really controls loudness. An unlinked DSP uses its own level.
function resolve(selected, links) {
    if (!selected || !selected.name || selected.name.indexOf("alsa_output.") === 0)
        return selected
    var name = selected.name
    for (var i = 0; i < (links || []).length; ++i) {
        var link = links[i]
        var stream = link && link.source
        var target = link && link.target
        if (!stream || !target || !target.isSink) continue
        var matchingName = stream.name && stream.name.indexOf(name) === 0
        var effects = name === "easyeffects_sink" && stream.properties
            && stream.properties["application.name"] === "EasyEffects"
        if (matchingName || effects) return target
    }
    return selected
}
