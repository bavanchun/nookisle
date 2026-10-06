.pragma library

function className(value) {
    if (typeof value !== "string") return ""
    return value.trim().toLowerCase().replace(/\.desktop$/, "")
}

// Panel passes the fullscreen client's class from its own monitor and the
// selected endpoint. An unknown identity never hides another application.
function shouldHide(behavior, fullscreen, clientClass, endpoint) {
    if (!fullscreen || behavior === "never") return false
    if (behavior === "always") return true
    if (behavior !== "nowPlayingOnly" || !endpoint) return false
    var presentation = endpoint.presentation || {}
    var expected = presentation.controlScope === "document"
        ? presentation.browserClass : presentation.desktopEntry || presentation.browserClass
    return className(clientClass) !== "" && className(clientClass) === className(expected)
}
