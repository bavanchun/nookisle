.pragma library

// User-visible copy shared by more than one component, plus the two code maps.
// Single-use visible copy stays inline at its call site.

var player = "Player"
var play = "Play"
var pause = "Pause"
var sendingCommand = "Sending command"
var backToPlayer = "Back to player"
var browserScope = "browser source"
var chromeTabScope = "Chrome tab"
// The one Hyprland binding that summons the island, for
// ~/.config/hypr/bindings.lua: Omarchy's o.bind helper, SUPER+M (free in
// stock Omarchy), and auto-close after summonAutoClose. The docs show this
// same line.
var summonChord = "SUPER + M"
var summonBinding = 'o.bind("' + summonChord + '", "Nookisle", [[omarchy-shell shell summon io.github.bavanchun.nookisle \'{"autoClose":true}\']])'

// How to make the island the bar's centre anchor by hand; the installer's
// --centre does both.
var centrePlacement = 'omarchy bar move io.github.bavanchun.nookisle --section center --index 0\n'
    + '# then in ~/.config/omarchy/shell.json, inside "bar":\n'
    + '"centerAnchor": "io.github.bavanchun.nookisle"'

// What already holds the summon chord in `hyprctl binds -j` output, or ""
// when it is free or already the island's. SUPER is modmask 64.
function summonConflict(bindsJson) {
    var binds
    try { binds = JSON.parse(String(bindsJson || "")) } catch (error) { return "" }
    if (!Array.isArray(binds)) return ""
    for (var i = 0; i < binds.length; ++i) {
        var bind = binds[i]
        if (!bind || String(bind.key || "").toUpperCase() !== "M" || bind.modmask !== 64) continue
        var description = String(bind.description || "")
        if (description === "Nookisle") return ""
        var what = description || [bind.dispatcher, bind.arg].filter(function (part) { return !!part }).join(" ")
        return what.length > 80 ? what.slice(0, 79) + "\u2026" : what || "another binding"
    }
    return ""
}

// Result codes the helper and bridge can emit. Every code in docs/protocol.md
// has an entry; an unrecognised code falls through to the generic sentence.
var resultCodes = {
    "target-gone": "Source disconnected. Choose a source again.",
    "stale-track": "The track changed. Try again.",
    "unsupported": "This source does not support that action.",
    "busy": "Still finishing the previous command.",
    "disconnected": "The connection dropped. Reconnect to continue.",
    "closed": "Controls are closed for this session.",
    "invalid-value": "That value is out of range for this source.",
    "timeout": "No response yet. Check the player.",
    "error": "The command could not be sent. Check the player.",
    "locked": "Controls are locked while the session is locked."
}

// Why a settings edit was not saved, by Service.configureError. A refused
// value says what is allowed where the schema can say it.
var settingErrors = {
    "not-ready": "Not saved yet: the settings folder is still being created. Try again in a moment.",
    "save-failed": "Not saved: settings.json could not be written. Check that ~/.config/nookisle is writable.",
    "host": "Not saved: the shell's configuration could not be updated.",
    "unavailable": "Not saved: another Nookisle instance owns the settings."
}

function settingErrorText(code, spec) {
    if (settingErrors[code]) return settingErrors[code]
    if (code !== "invalid") return "Not saved: the change was refused."
    if (spec && spec.key === "customAccentColor") return "Use a colour written like #a9c7ff."
    if (spec && spec.key === "backlightDevice")
        return "Use a device name from /sys/class/backlight, like intel_backlight, or leave it empty."
    if (spec && (spec.type === "int" || spec.type === "real") && spec.min !== undefined && spec.max !== undefined)
        return "Enter a number from " + spec.min + " to " + spec.max + "."
    return "Not saved: that value is not allowed here."
}

// Sleep timer copy, shared by the settings row and the player's status band.
var sleepFailures = {
    "source-changed": "The sleep timer could not pause: that source is gone.",
    "busy": "The sleep timer could not pause while another command was running.",
    "refused": "The sleep timer could not pause this source."
}

function sleepFailureText(code) {
    return sleepFailures[code] || sleepFailures["refused"]
}

// Shelf notice codes (Service.shelfNotice). Empty means nothing to say.
var shelfNotices = {
    "shelf-full": "The shelf is full. Remove something before adding more.",
    "shelf-rejected": "Some items were not added: the shelf takes files, web links and text.",
    "clipboard-no-files": "The clipboard held nothing the shelf can keep.",
    "clipboard-unavailable": "The clipboard tool is not available.",
    "clipboard-busy": "The clipboard is busy with another request.",
    "action-failed": "That shelf action did not finish.",
    "action-timeout": "That shelf action took too long and was stopped.",
    "action-unavailable": "The tool for that action is not available.",
    "share-no-device": "KDE Connect has no reachable device to share with.",
    "rename-invalid": "That name cannot be used. It must not be empty, \".\", \"..\" or contain \"/\"."
}

function shelfNoticeText(code) {
    if (!code) return ""
    return shelfNotices[code] || ""
}

// An absolute wall-clock time, formatted once from the stored deadline.
function sleepUntil(deadline) {
    var at = new Date(deadline)
    return "Pauses at " + at.getHours() + ":" + (at.getMinutes() < 10 ? "0" : "") + at.getMinutes()
}

function resultText(code) {
    if (!code)
        return ""
    return resultCodes[code] || "That action could not be completed."
}

// statusText is NOT a closed set. Three of its sources are open-ended: the
// helper's exit code, a protocol-error code that arrives over the wire, and a
// discarded-snapshot code that also arrives over the wire. Only the six codes
// below are authored locally. Anything else - including every wire-supplied
// value - falls through to the generic sentence and is never rendered verbatim,
// because a helper-supplied string must not reach user-facing text.
var statusCodes = {
    "connecting": "Connecting to the music controller.",
    "lease-busy": "Another instance is using the music controller.",
    "bus-unavailable": "The connection to the player was lost.",
    "retry-exhausted": "Could not connect. Try again.",
    "lock-unavailable": "Waiting for the session to unlock.",
    "stale-host-load": "The shell reloaded. Reconnect to continue."
}

function statusText(code) {
    if (!code)
        return "The music controller is not ready yet. Try reconnecting."
    if (statusCodes[code])
        return statusCodes[code]
    if (String(code).indexOf("helper-exited-") === 0)
        return "The music controller stopped unexpectedly. Try reconnecting."
    return "The music controller is not ready yet. Try reconnecting."
}

// A remembered player's app identity as a name: the MPRIS app or the
// extension's platform, with a capital. "" for none.
function appName(identity) {
    var name = String(identity || "").replace(/^org\.mpris\.MediaPlayer2\./, "").replace(/^extension:/, "")
    return name ? name.charAt(0).toUpperCase() + name.slice(1) : ""
}

// Detailed source name for the picker rows. controlScope values with a real
// producer are: application, browser, endpoint (helper) and document (bridge).
// "tab" has no producer anywhere in the repo; the branch is kept for legacy
// payloads but is not a covered value.
function sourceName(presentation) {
    var p = presentation || {}
    var host = String(p.hostApp || player)
    var name = p.platform && p.platform !== host ? p.platform + " · " + host : host
    if (p.controlScope === "browser")
        return name + " · " + browserScope
    if (p.controlScope === "document" || p.controlScope === "tab")
        return name + " · " + chromeTabScope
    return name
}
