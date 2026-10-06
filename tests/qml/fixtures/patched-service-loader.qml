// Service-loader block of the patched Omarchy shell, used as the host
// fixture for the qml-patched-host-lifecycle test. It is not a loadable QML
// document: the runner slices the block between its start and end markers.
//
// Source: https://github.com/bavanchun/omarchy, file shell/shell.qml at
// commit ce38fe69a272ece9c112e8eba7270c9b62370aef ("fix(shell): own pending
// service loads across reloads"), the fix as first written on Omarchy 4.0.x.
// Later rebases of the same fix also carry newer host plugin APIs that this
// harness does not provide. Omarchy is released under the MIT licence,
// Copyright (c) David Heinemeier Hansson.
//
// The block is copied verbatim. Stock Omarchy 4.0.4 does not ship this fix,
// so the test proves the plugin's contract with the patched loader, not with
// the installed host.

  property var _services: ({})
  property var _serviceLoads: ({})
  property int _serviceLoadGeneration: 0

  function serviceFor(pluginId) {
    return _services[String(pluginId)] || null
  }

  function firstPartyServiceFor(pluginId) {
    return serviceFor(pluginId)
  }

  function _serviceManifest(key) {
    if (pluginReloading) return null
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest || !pluginRegistry.isEnabled(key)) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    return manifest
  }

  function _serviceLoadCurrent(key, load) {
    return !load.done && _serviceLoads[key] === load
      && load.generation === _serviceLoadGeneration && !_services[key]
      && _serviceManifest(key) === load.manifest
      && pluginRegistry.entryPointUrl(load.manifest, "service") === load.url
  }

  function _releaseServiceLoad(key, load) {
    load.done = true
    if (_serviceLoads[key] === load) {
      var next = ({})
      for (var id in _serviceLoads) if (id !== key) next[id] = _serviceLoads[id]
      _serviceLoads = next
    }
    if (load.connected) {
      load.component.statusChanged.disconnect(load.finalize)
      load.connected = false
    }
    var comp = load.component
    load.component = null
    if (comp) comp.destroy()
  }

  function ensureService(pluginId) {
    var key = String(pluginId)
    if (pluginReloading) return null
    if (_services[key]) return _services[key]
    var manifest = _serviceManifest(key)
    if (!manifest) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null

    var pending = _serviceLoads[key]
    if (pending && _serviceLoadCurrent(key, pending)) return null
    if (pending) _releaseServiceLoad(key, pending)
    // Reserve before compilation/construction, both of which may reenter the host.
    var load = { generation: _serviceLoadGeneration, manifest: manifest, url: url,
      component: null, finalize: null, connected: false, finalizing: false, done: false }
    var loads = ({})
    for (var id in _serviceLoads) loads[id] = _serviceLoads[id]
    loads[key] = load
    _serviceLoads = loads
    var comp = load.component = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (load.done || load.finalizing) return
      if (comp.status === Component.Loading) return
      load.finalizing = true
      if (!_serviceLoadCurrent(key, load)) {
        _releaseServiceLoad(key, load)
        return
      }
      if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        _releaseServiceLoad(key, load)
        return
      }
      var inst = comp.createObject(serviceHost)
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        _releaseServiceLoad(key, load)
        return
      }
      function discardIfStale() {
        if (_serviceLoadCurrent(key, load)) return false
        inst.destroy()
        _releaseServiceLoad(key, load)
        return true
      }
      if (discardIfStale()) return
      if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
      if (discardIfStale()) return
      if ("shell" in inst) inst.shell = shell
      if (discardIfStale()) return
      if ("manifest" in inst) inst.manifest = manifest
      if (discardIfStale()) return
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.barWidgetRegistry
      if (discardIfStale()) return
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistry
      if (discardIfStale()) return
      var snext = ({})
      for (var sk in _services) snext[sk] = _services[sk]
      snext[key] = inst
      _services = snext
      _releaseServiceLoad(key, load)
    }
    load.finalize = finalize
    if (!comp || !_serviceLoadCurrent(key, load)) {
      _releaseServiceLoad(key, load)
      return _services[key] || null
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      load.connected = true
      return null
    }
    finalize()
    return _services[key] || null
  }

  function _syncServices() {
    if (pluginReloading || !pluginRegistry || !pluginRegistry.installedPlugins) return
    var pending = _serviceLoads
    for (var loadingId in pending) {
      if (!_serviceLoadCurrent(loadingId, pending[loadingId]))
        _releaseServiceLoad(loadingId, pending[loadingId])
    }
    var plugins = pluginRegistry.installedPlugins
    for (var id in plugins) {
      var m = plugins[id]
      if (!m) continue
      if (!Array.isArray(m.kinds) || m.kinds.indexOf("service") === -1) continue
      if (!m.entryPoints || !m.entryPoints.service) continue
      if (!pluginRegistry.isEnabled(id)) continue
      if (_services[id]) continue
      ensureService(id)
    }
    // Drop services for plugins that have been disabled or removed.
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillThere && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _services) if (k !== existingId) next[k] = _services[k]
      _services = next
    }
  }

  function unloadPluginServices() {
    _serviceLoadGeneration++
    var pending = _serviceLoads
    _serviceLoads = ({})
    for (var loadingId in pending) _releaseServiceLoad(loadingId, pending[loadingId])
    for (var existingId in _services) {
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
    }
    _services = ({})
  }

  Connections {
    target: shell.pluginRegistry
  }
