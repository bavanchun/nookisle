// Omarchy v4.0.2, 346e69e1cec6c4e8924531874af6ba010a1bc99e.
// Original shell/shell.qml SHA-256:
// 9f1db77dcc3c111ceccc860ac472d19b35d385958a63d270ea51e413ab86f1f0
// Pinned regression contract: intentionally retains the stale-load bug.
function finalize() {
    if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        return
    }
    var inst = comp.createObject(serviceHost)
    if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        return
    }
    if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
    if ("shell" in inst) inst.shell = shell
    if ("manifest" in inst) inst.manifest = manifest
    if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.barWidgetRegistry
    if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistry
    var snext = ({})
    for (var sk in _services) snext[sk] = _services[sk]
    snext[key] = inst
    _services = snext
}
