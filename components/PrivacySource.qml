pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import "../qml/Privacy.js" as Privacy

// Who is capturing the microphone, a camera or the screen, from the local
// PipeWire graph: node types and links need no tracking, so only the few
// capture streams in use are tracked, for their application names. The
// helper's camera holders cover apps that open a camera without PipeWire.
// Panel.qml loads this only with privacy indicators on.
Item {
    id: root
    // Service.cameraHolders: processes holding /dev/videoN open.
    property var cameraHolders: []
    // Touching the singleton at load starts it; a first read from a timer
    // would find it empty.
    readonly property bool ready: Pipewire.ready
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodeObjects: Pipewire.nodes.values
    readonly property var nodes: nodeObjects.map(function (node) {
        var props = node.properties || {};
        return { id: node.id, type: PwNodeType.toString(node.type), name: String(node.name || ""),
            app: String(props["application.name"] || "") };
    })
    readonly property var links: Pipewire.linkGroups.values.map(function (group) {
        return { source: group.source ? group.source.id : -1, target: group.target ? group.target.id : -1 };
    })
    readonly property var trackedIds: Privacy.captureStreamIds(nodes, links)
    PwObjectTracker {
        objects: root.nodeObjects.filter(node => root.trackedIds.indexOf(node.id) >= 0)
            .concat(root.source ? [root.source] : [])
    }
    readonly property bool micMuted: !!source && !!source.audio && source.audio.muted === true
    readonly property var state: ready ? Privacy.classify(nodes, links, cameraHolders, micMuted)
        : Privacy.classify([], [], cameraHolders, false)
}
