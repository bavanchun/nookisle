pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Protocol.js" as Protocol
import "../qml/SourceState.js" as SourceState

// The player's button row, after boring.notch's: up to five slots from the
// `musicControlSlots` setting, at most `musicControlSlotLimit`. A slot whose
// capability the source lacks hides rather than greys out, except favorite,
// which dims to 0.35 as boring.notch's does. With both side panels on Home
// and five slots, the first and last drop. Shuffle and repeat are dimmed
// while off and full ink with a dot under them while on; repeat shows
// repeat-one for a repeated track.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    property var slots: ["shuffle", "previous", "playPause", "next", "repeat"]
    property int limit: 5
    // Both the calendar and the mirror share Home with the player.
    property bool crowded: false
    readonly property var endpoint: controlsAllowed ? coordinator.selectedEndpoint : null
    readonly property bool controlsAllowed: !!coordinator && coordinator.panelAllowed === true && coordinator.uiAllowed === true
    readonly property var capabilities: endpoint && endpoint.capabilities ? endpoint.capabilities : ({})
    readonly property bool canControl: capabilities.CanControl === true
    readonly property bool canSetVolume: canControl && capabilities.CanSetVolume === true
    readonly property bool playing: !!endpoint && endpoint.status === "Playing"
    readonly property string pending: coordinator ? String(coordinator.pendingAction || "") : ""
    readonly property bool shuffleOn: !!endpoint && endpoint.shuffle === true
    readonly property string loopStatus: endpoint && typeof endpoint.loopStatus === "string" ? endpoint.loopStatus : ""
    readonly property bool volumeOpen: volumeSlotOpen
    property bool volumeSlotOpen: false
    property var volumeSourceToken: null
    readonly property var shown: {
        var list = Array.isArray(slots) ? slots.slice(0, Math.max(0, limit)) : [];
        if (crowded && limit === 5 && list.length === 5)
            list = list.slice(1, 4);
        return list;
    }
    // True while the volume popover's slider is mid-drag.
    property bool interacting: false
    implicitHeight: tokens.playSize
    implicitWidth: row.implicitWidth
    // Whether a slot kind shows for the current source. Favorite always
    // shows (dimmed when unsupported); none is an empty gap.
    function available(kind) {
        if (kind === "none" || kind === "favorite")
            return true;
        if (!endpoint || !canControl)
            return false;
        switch (kind) {
        case "shuffle":
            return capabilities.CanShuffle === true && typeof endpoint.shuffle === "boolean";
        case "repeat":
            return capabilities.CanLoop === true && Protocol.nextLoopStatus(endpoint.loopStatus) !== null;
        case "previous":
            return capabilities.CanGoPrevious === true;
        case "next":
            return capabilities.CanGoNext === true;
        case "playPause":
            return capabilities.CanPlay === true || capabilities.CanPause === true;
        case "volume":
            return capabilities.CanSetVolume === true;
        case "back15":
        case "forward15":
            return capabilities.CanSeek === true;
        }
        return false;
    }
    function enabledFor(kind) {
        if (!available(kind) || kind === "none" || pending !== "")
            return false;
        if (kind === "favorite")
            return !!endpoint && canControl && capabilities.CanFavorite === true;
        if (kind === "playPause")
            return playing ? capabilities.CanPause === true : capabilities.CanPlay === true;
        return true;
    }
    function iconFor(kind) {
        switch (kind) {
        case "playPause":
            return playing ? "pause" : "play";
        case "repeat":
            return loopStatus === "Track" ? "repeat-one" : "repeat";
        case "favorite":
            return endpoint && endpoint.liked === true ? "favorite-filled" : "favorite";
        }
        return kind;
    }
    function labelFor(kind) {
        return ({
            shuffle: shuffleOn ? "Shuffle on" : "Shuffle off",
            previous: "Previous",
            playPause: playing ? "Pause" : "Play",
            next: "Next",
            repeat: loopStatus === "Track" ? "Repeat track" : loopStatus === "Playlist" ? "Repeat all" : "Repeat off",
            volume: "Volume",
            favorite: endpoint && endpoint.liked === true ? "Remove from favorites" : "Add to favorites",
            back15: "Back 15 seconds",
            forward15: "Forward 15 seconds"
        })[kind] || "";
    }
    function toggle(kind) {
        return kind === "shuffle" || kind === "repeat";
    }
    function active(kind) {
        return (kind === "shuffle" && shuffleOn) || (kind === "repeat" && loopStatus !== "" && loopStatus !== "None");
    }
    // One command through a freshly captured intent. Returns whether it was
    // sent.
    function dispatch(action, value) {
        if (!coordinator || pending !== "")
            return false;
        var intent = coordinator.captureIntent();
        if (!intent)
            return false;
        coordinator.invoke(action, intent, value);
        return true;
    }
    function trigger(kind) {
        switch (kind) {
        case "shuffle":
            return dispatch("SetShuffle", !shuffleOn);
        case "repeat":
            return dispatch("SetLoopStatus", Protocol.nextLoopStatus(loopStatus));
        case "previous":
            return dispatch("Previous");
        case "next":
            return dispatch("Next");
        case "playPause":
            return dispatch("PlayPause");
        case "favorite":
            return dispatch("Favorite");
        case "back15":
            return dispatch("Seek", -15);
        case "forward15":
            return dispatch("Seek", 15);
        case "volume":
            volumeSlotOpen = !volumeSlotOpen;
            return true;
        }
        return false;
    }
    function focusControls() {
        for (var i = 0; i < repeater.count; ++i) {
            var slot = repeater.itemAt(i);
            if (slot && slot.kind === "playPause" && slot.button.visible) {
                slot.button.forceActiveFocus(Qt.TabFocusReason);
                return true;
            }
        }
        for (var j = 0; j < repeater.count; ++j) {
            var other = repeater.itemAt(j);
            if (other && other.button.visible && other.button.enabled) {
                other.button.forceActiveFocus(Qt.TabFocusReason);
                return true;
            }
        }
        return false;
    }
    onEndpointChanged: {
        var nextToken = endpoint ? endpoint.token : null;
        if (!SourceState.same(volumeSourceToken, nextToken))
            volumeSlotOpen = false;
        volumeSourceToken = nextToken;
    }
    onCanSetVolumeChanged: if (!canSetVolume)
        volumeSlotOpen = false
    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height
        spacing: root.tokens.toolbarGap
        Repeater {
            id: repeater
            model: root.shown
            Item {
                id: slot
                required property string modelData
                required property int index
                readonly property string kind: modelData
                readonly property alias button: button
                objectName: "toolbarSlot-" + kind
                visible: root.available(kind)
                width: kind === "volume" ? button.width + volumeTray.width : button.width
                height: row.height
                IslandButton {
                    id: button
                    objectName: "toolbarButton-" + slot.kind
                    visible: slot.kind !== "none"
                    anchors.verticalCenter: parent.verticalCenter
                    tokens: root.tokens
                    bounce: true
                    iconName: root.iconFor(slot.kind)
                    iconSize: slot.kind === "playPause" ? 24 : 18
                    // A toggle that is off reads dimmer; on, it is full ink
                    // with a dot under it. The artwork colour stays off the
                    // buttons.
                    iconColor: root.toggle(slot.kind) && !root.active(slot.kind) ? root.tokens.secondary : root.tokens.text
                    accessibleLabel: root.labelFor(slot.kind)
                    width: slot.kind === "playPause" ? root.tokens.playSize : root.tokens.buttonSize
                    height: width
                    actionEnabled: root.enabledFor(slot.kind)
                    pending: root.pending !== "" && root.pending === ({ playPause: "PlayPause", next: "Next", previous: "Previous",
                        shuffle: "SetShuffle", repeat: "SetLoopStatus", favorite: "Favorite", back15: "Seek", forward15: "Seek" })[slot.kind]
                    opacity: slot.kind === "favorite" && !root.enabledFor("favorite") && root.pending === "" ? 0.35 : 1
                    onActivated: root.trigger(slot.kind)
                }
                Rectangle {
                    objectName: "toolbarActiveDot-" + slot.kind
                    visible: root.active(slot.kind)
                    x: button.x + (button.width - width) / 2
                    y: button.y + button.height - height
                    width: 4
                    height: 4
                    radius: 2
                    color: root.tokens.text
                }
                // Closing the tray (the speaker, a source change, losing
                // CanSetVolume) under its focused slider hands the keyboard to
                // the speaker button, so the arrows never write volume through
                // a hidden slider.
                Connections {
                    target: root
                    enabled: slot.kind === "volume"
                    function onVolumeSlotOpenChanged() {
                        var focused = button.Window.activeFocusItem;
                        for (var node = focused; node; node = node.parent)
                            if (node === volumeTray) {
                                if (!root.volumeSlotOpen)
                                    button.forceActiveFocus(Qt.TabFocusReason);
                                return;
                            }
                    }
                }
                // The volume slot's slider, sliding out beside the speaker.
                Item {
                    id: volumeTray
                    objectName: "volumeTray"
                    visible: slot.kind === "volume"
                    x: button.width
                    width: slot.kind === "volume" && root.volumeSlotOpen ? 48 + root.tokens.small : 0
                    height: parent.height
                    clip: true
                    Behavior on width {
                        enabled: !root.tokens.reducedMotion
                        NumberAnimation {
                            duration: root.volumeSlotOpen ? 120 : 200
                            easing.type: Easing.OutCubic
                        }
                    }
                    IntentSlider {
                        id: volumeSlider
                        objectName: "volumeSlider"
                        x: root.tokens.small
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48
                        height: 24
                        trackPadding: 0
                        visible: slot.kind === "volume" && root.volumeSlotOpen
                        tokens: root.tokens
                        coordinator: root.coordinator
                        action: "SetVolume"
                        label: "Player volume"
                        maximum: 1
                        step: 0.05
                        sample: root.endpoint ? Number(root.endpoint.volume) || 0 : 0
                        liveInterval: 100
                        // A write in flight must not cancel this drag; the
                        // slider queues its latest value until the reply.
                        actionEnabled: root.controlsAllowed && root.canControl
                            && root.capabilities.CanSetVolume === true
                        disabledReason: "This source does not support volume changes"
                        onGesturingChanged: root.interacting = gesturing
                    }
                }
            }
        }
    }
}
