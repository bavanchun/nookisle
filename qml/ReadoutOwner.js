.pragma library

// A media-key action publishes its owner before changing the device. Ignore
// stale records so an unrelated later device change can still show the HUD.
function allows(record, kind, nowMs) {
    var fields = String(record || "").trim().split(/\s+/)
    if (fields.length !== 4 || fields[0] !== kind || !/^\d+-\d+$/.test(fields[1])
            || !/^\d+$/.test(fields[3])) return true
    var expires = Number(fields[3])
    if (!Number.isFinite(expires) || expires < nowMs) return true
    return fields[2] !== "fallback"
}
