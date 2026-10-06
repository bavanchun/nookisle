pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../qml/Strings.js" as Strings

Item {
    id: root
    required property var tokens
    property var coordinator: null
    property bool expanded: false
    property bool pickerOpen: false
    property bool settingsOpen: false
    // True while a slider inside the loaded expanded content is mid-gesture.
    // The island surface reads this to defer a hover-leave collapse so a drag
    // that briefly leaves the card does not cut the gesture short.
    readonly property bool interacting: expandedLoader.item ? expandedLoader.item.interacting : false
    readonly property bool narrow: width < 320
    property bool admitted: coordinator && coordinator.panelAllowed === true
    readonly property bool controlsAllowed: admitted && coordinator && coordinator.uiAllowed === true
    readonly property var endpoint: controlsAllowed && coordinator ? coordinator.selectedEndpoint : null
    readonly property var presentation: endpoint && endpoint.presentation ? endpoint.presentation : ({})
    readonly property var capabilities: endpoint && endpoint.capabilities ? endpoint.capabilities : ({})
    readonly property bool playing: endpoint && endpoint.status === "Playing"
    readonly property bool unavailable: coordinator && coordinator.pinUnavailable === true
    readonly property string title: endpoint ? String(presentation.title || presentation.hostApp || Strings.player) : unavailable ? String(coordinator.selectedLabel || "Selected source") : !controlsAllowed ? "Connect Nookisle" : "No music source yet"
    readonly property string artist: Array.isArray(presentation.artists) ? presentation.artists.join(", ") : ""
    readonly property string album: endpoint ? String(presentation.album || "") : ""
    // The helper trims presentation fields under budget pressure. Showing a
    // trimmed title as if it were complete is the truthfulness failure this
    // marker exists to prevent.
    readonly property bool metadataTruncated: !!endpoint && endpoint.presentationTruncated === true
    // The helper states why seeking is unavailable for one case only, and the
    // bridge never states it at all, so this is an override rather than a
    // replacement: without the local fallback an ordinary source would show a
    // disabled control with an empty reason.
    function seekReason(maximum) {
        if (endpoint && endpoint.seekUnavailableReason === "track-id-oversized")
            return "This track's ID is too long to seek reliably";
        return maximum <= 0 ? "Duration unknown, so seeking is unavailable" : "This source does not support seeking";
    }
    readonly property string sourceLabel: endpoint && coordinator ? String(coordinator.selectedLabel || presentation.hostApp || Strings.player) : ""
    readonly property string pending: coordinator ? String(coordinator.pendingAction || "") : ""
    readonly property string displayArtworkPath: endpoint ? String(endpoint.artworkPath || "") : ""
    readonly property string errorText: actionError(coordinator ? coordinator.actionError : "")
    readonly property bool playEnabled: controlsAllowed && endpoint && capabilities.CanControl === true && (playing ? capabilities.CanPause === true : capabilities.CanPlay === true)
    signal toggleRequested
    signal closeRequested
    // Moves keyboard focus from this view onto its controls: the play
    // button, which most keys want, or the source button when no source is
    // shown. With the source list or the settings open, focus stays here, so
    // Escape still closes them first.
    function focusControls() {
        if (expandedLoader.item && !pickerOpen && !settingsOpen)
            expandedLoader.item.focusControls();
    }
    function returnToPlayer() {
        var target = settingsOpen ? "openSettingsButton" : "openSourcePicker";
        settingsOpen = false;
        pickerOpen = false;
        if (expandedLoader.item)
            expandedLoader.item.restoreFocus(target);
    }
    onExpandedChanged: if (!expanded) {
        pickerOpen = false;
        settingsOpen = false;
    }
    onAdmittedChanged: if (!admitted) {
        pickerOpen = false;
        settingsOpen = false;
    }
    onVisibleChanged: if (!visible) {
        pickerOpen = false;
        settingsOpen = false;
    }
    Keys.onEscapePressed: event => {
        if (settingsOpen || pickerOpen)
            returnToPlayer();
        else if (expanded)
            toggleRequested();
        else
            closeRequested();
        event.accepted = true;
    }
    function actionError(code) {
        return Strings.resultText(code);
    }
    function connectionText() {
        return Strings.statusText(coordinator ? coordinator.statusText : "connecting");
    }
    function sourceCount() {
        var n = coordinator ? coordinator.endpoints.length : 0;
        return n + (n === 1 ? " source" : " sources");
    }
    function timeText(seconds) {
        var s = Math.max(0, Math.floor(Number(seconds) || 0)), m = Math.floor(s / 60);
        return (m >= 60 ? Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") : "") + (m % 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }
    Item {
        visible: !root.expanded
        anchors.fill: parent
        Artwork {
            x: root.tokens.gap
            anchors.verticalCenter: parent.verticalCenter
            width: root.tokens.inset + root.tokens.gap
            height: width
            tokens: root.tokens
            artworkPath: root.displayArtworkPath
        }
        IslandButton {
            objectName: "compactExpandButton"
            x: root.tokens.primaryTarget
            width: parent.width - x - root.tokens.target * 2 - root.tokens.gap
            height: parent.height
            tokens: root.tokens
            accessibleLabel: "Expand Nookisle"
            onActivated: root.toggleRequested()
            contentItem: Item {
                Text {
                    y: root.tokens.small
                    width: parent.width
                    text: root.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.bodySize
                    font.weight: Font.Medium
                }
                Text {
                    y: root.tokens.inset + root.tokens.small
                    width: parent.width
                    text: root.unavailable ? "No longer connected" : root.sourceLabel || "Tap to open"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
            }
        }
        IslandButton {
            objectName: "compactPlayButton"
            x: parent.width - root.tokens.target * 2 - root.tokens.gap
            anchors.verticalCenter: parent.verticalCenter
            tokens: root.tokens
            iconName: root.playing ? "pause" : "play"
            accessibleLabel: root.playing ? Strings.pause : Strings.play
            actionEnabled: root.playEnabled
            disabledReason: "The source is not ready or does not support play/pause"
            pending: root.pending === "PlayPause"
            coordinator: root.coordinator
            actionName: "PlayPause"
        }
        IslandButton {
            x: parent.width - root.tokens.target - root.tokens.small
            anchors.verticalCenter: parent.verticalCenter
            tokens: root.tokens
            iconName: "expand"
            accessibleLabel: "Expand Nookisle"
            onActivated: root.toggleRequested()
        }
    }
    Loader {
        id: expandedLoader
        objectName: "expandedContentLoader"
        anchors.fill: parent
        active: root.visible && root.expanded && root.admitted
        sourceComponent: Item {
            readonly property bool interacting: progress.gesturing || volumeControl.gesturing
            function focusControls() {
                (playButton.visible ? playButton : sourceButton).forceActiveFocus(Qt.TabFocusReason);
            }
            function restoreFocus(target) {
                if (target === "openSettingsButton") settingsButton.forceActiveFocus(Qt.TabFocusReason);
                else sourceButton.forceActiveFocus(Qt.TabFocusReason);
            }
            Loader {
                id: pickerOverlay
                objectName: "sourceOverlay"
                active: root.pickerOpen
                // The player stage is now always visible, so this must paint
                // above it rather than relying on declaration order.
                z: 1
                // Below the narrow threshold the overlay covers the whole stage,
                // which is the previous behaviour; above it the header stays
                // visible so the user can see what they are switching away from.
                // Explicit geometry rather than conditional anchors: assigning
                // `undefined` to an anchor does not detach it the way it reads.
                x: 0
                width: parent.width
                y: root.narrow ? 0 : root.tokens.inset + root.tokens.bandHeader + root.tokens.bandSpacing
                height: parent.height - y
                sourceComponent: Rectangle {
                    color: root.tokens.cardSurface
                    radius: root.narrow ? 0 : root.tokens.rowRadius
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.tokens.hairline
                        visible: !root.narrow
                    }
                    SourcePicker {
                        anchors.fill: parent
                        overlay: !root.narrow
                        tokens: root.tokens
                        coordinator: root.coordinator
                        onDismissed: root.returnToPlayer()
                    }
                }
            }
            Loader {
                anchors.fill: parent
                active: root.settingsOpen
                sourceComponent: IslandSettings {
                    tokens: root.tokens
                    coordinator: root.coordinator
                    onDismissed: root.returnToPlayer()
                }
            }
            Item {
                id: playerStage
                readonly property int artworkSize: root.tokens.heroArtSize + root.tokens.inset + root.tokens.gap
                anchors.fill: parent
                // Visible behind the source overlay so switching keeps its
                // context, but inert: `enabled` is what now cancels captured
                // intent on every control underneath.
                visible: !root.settingsOpen
                enabled: !root.pickerOpen
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.tokens.inset
                    spacing: root.tokens.bandSpacing
                    // Every band is an always-visible wrapper with a fixed height.
                    // A ColumnLayout drops invisible children from layout, so a
                    // visible-toggled band would collapse the moment there is no
                    // endpoint or no error and take the window height with it.
                    Item {
                        id: headerBand
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.tokens.bandHeader
                        ArtGlow {
                            tokens: root.tokens
                            target: heroArt
                            radius: heroArt.radius
                            scale: heroArt.scale
                        }
                        Artwork {
                            id: heroArt
                            objectName: "heroArtwork"
                            // A placeholder cover beside a "no source" heading
                            // reads as a broken cover rather than an empty state.
                            visible: !!root.endpoint
                            width: playerStage.artworkSize
                            height: width
                            tokens: root.tokens
                            artworkPath: root.displayArtworkPath
                            radius: Math.min(root.tokens.expandedRadius, root.tokens.medium)
                            border.width: 1
                            border.color: root.tokens.stroke
                        }
                        Column {
                            x: root.endpoint ? playerStage.artworkSize + root.tokens.inset : 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x
                            spacing: root.tokens.small
                            Text {
                                objectName: "sourceEyebrow"
                                width: parent.width
                                text: root.sourceLabel
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                visible: text !== ""
                                color: root.tokens.tintText
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.captionSize
                                font.weight: Font.Medium
                            }
                            Text {
                                id: trackTitle
                                objectName: "trackTitle"
                                width: parent.width
                                text: root.title
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: root.tokens.text
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.titleSize
                                font.weight: Font.DemiBold
                                IslandToolTip {
                                    parent: trackTitle
                                    tokens: root.tokens
                                    visible: titleHover.hovered && trackTitle.truncated
                                    delay: 600
                                    text: trackTitle.text
                                }
                                HoverHandler { id: titleHover }
                            }
                            Text {
                                width: parent.width
                                text: root.unavailable ? "No longer connected" : root.artist || (root.endpoint ? (root.playing ? "Playing" : "Paused") : "")
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.tokens.secondary
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.bodySize
                            }
                            Row {
                                width: parent.width
                                spacing: root.tokens.small
                                Text {
                                    objectName: "albumLine"
                                    width: parent.width - (root.metadataTruncated ? root.tokens.inset + root.tokens.small : 0)
                                    text: root.album
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                    color: root.tokens.secondary
                                    font.family: root.tokens.fontFamily
                                    font.pixelSize: root.tokens.captionSize
                                }
                                IslandIcon {
                                    objectName: "truncationMarker"
                                    name: "expand"
                                    ink: root.tokens.secondary
                                    visible: root.metadataTruncated
                                    IslandToolTip {
                                        tokens: root.tokens
                                        visible: truncationHover.hovered
                                        delay: 600
                                        text: "This source sent more text than fits; some details were trimmed."
                                    }
                                    HoverHandler { id: truncationHover }
                                }
                            }
                        }
                    }
                    Item {
                        id: progressBand
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.tokens.bandProgress
                        Item {
                            anchors.fill: parent
                            visible: !!root.endpoint
                            Text {
                                width: parent.width / 2
                                y: root.tokens.target
                                height: root.tokens.inset
                                text: root.timeText(progress.displayValue)
                                textFormat: Text.PlainText
                                color: root.tokens.secondary
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.captionSize
                                verticalAlignment: Text.AlignVCenter
                            }
                            IntentSlider {
                                id: progress
                                objectName: "progressControl"
                                width: parent.width
                                tokens: root.tokens
                                coordinator: root.coordinator
                                action: "SetPosition"
                                maximum: root.endpoint ? Math.max(0, root.endpoint.lengthSeconds || 0) : 0
                                sample: root.coordinator ? root.coordinator.positionSeconds : 0
                                step: 5
                                actionEnabled: root.controlsAllowed && root.capabilities.CanControl === true && root.capabilities.CanSetPosition === true && maximum > 0 && root.pending !== "SetPosition" && !root.pickerOpen
                                disabledReason: root.seekReason(maximum)
                            }
                            Text {
                                anchors.right: parent.right
                                width: parent.width / 2
                                y: root.tokens.target
                                height: root.tokens.inset
                                // Remaining, not total. timeText clamps its input
                                // to zero, so the sign is prefixed rather than
                                // produced by passing a negative value.
                                text: root.endpoint && root.endpoint.lengthSeconds > 0
                                    ? "-" + root.timeText(root.endpoint.lengthSeconds - progress.displayValue) : "--:--"
                                textFormat: Text.PlainText
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                color: root.tokens.secondary
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.captionSize
                            }
                        }
                        // The empty state replaces the progress and transport
                        // bands, which are both blank when there is no endpoint.
                        Column {
                            objectName: "emptyState"
                            visible: !root.endpoint
                            width: parent.width
                            spacing: root.tokens.medium
                            Text {
                                width: parent.width
                                text: root.unavailable ? "Choose a source again, or switch to Auto." : root.controlsAllowed ? "Open Spotify, or play music in your browser." : root.connectionText()
                                color: root.tokens.secondary
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.bodySize
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                            IslandButton {
                                objectName: "retryButton"
                                visible: !root.controlsAllowed
                                tokens: root.tokens
                                primary: true
                                text: "Reconnect"
                                onActivated: if (root.coordinator)
                                    root.coordinator.retryConnection()
                            }
                        }
                    }
                    Item {
                        id: transportBand
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.tokens.bandTransport(root.narrow)
                        Rectangle {
                            objectName: "transportSurface"
                            anchors.fill: parent
                            radius: Math.min(root.tokens.expandedRadius, root.tokens.medium)
                            color: root.tokens.surfaceRaised
                            visible: !!root.endpoint
                            Rectangle {
                                width: parent.width - root.tokens.medium * 2
                                height: 1
                                x: root.tokens.medium
                                color: root.tokens.hairline
                            }
                        }
                        Row {
                            y: root.tokens.gap
                            x: root.tokens.gap
                            spacing: root.tokens.gap
                            visible: !!root.endpoint
                            IslandButton {
                                anchors.verticalCenter: parent.verticalCenter
                                tokens: root.tokens
                                iconName: "previous"
                                accessibleLabel: "Previous track"
                                actionEnabled: root.controlsAllowed && root.capabilities.CanControl === true && root.capabilities.CanGoPrevious === true && !root.pickerOpen
                                disabledReason: "This source does not support previous track"
                                pending: root.pending === "Previous"
                                coordinator: root.coordinator
                                actionName: "Previous"
                            }
                            IslandButton {
                                id: playButton
                                objectName: "expandedPlayButton"
                                tokens: root.tokens
                                primary: true
                                width: root.tokens.primaryTarget + root.tokens.inset
                                height: width
                                iconName: root.playing ? "pause" : "play"
                                accessibleLabel: root.playing ? Strings.pause : Strings.play
                                actionEnabled: root.playEnabled && !root.pickerOpen
                                disabledReason: "This source does not support play/pause"
                                pending: root.pending === "PlayPause"
                                coordinator: root.coordinator
                                actionName: "PlayPause"
                            }
                            IslandButton {
                                anchors.verticalCenter: parent.verticalCenter
                                tokens: root.tokens
                                objectName: "nextTrackButton"
                                iconName: "next"
                                accessibleLabel: "Next track"
                                actionEnabled: root.controlsAllowed && root.capabilities.CanControl === true && root.capabilities.CanGoNext === true && !root.pickerOpen
                                disabledReason: "This source does not support next track"
                                pending: root.pending === "Next"
                                coordinator: root.coordinator
                                actionName: "Next"
                            }
                        }
                        IslandIcon {
                            objectName: "volumeIcon"
                            x: parent.width - root.tokens.gap - root.tokens.target * 4
                            y: root.narrow ? root.tokens.rowHeight + root.tokens.inset + root.tokens.small
                                : root.tokens.inset + root.tokens.gap + root.tokens.small
                            name: "volume"
                            ink: root.tokens.secondary
                            visible: !!root.endpoint && root.capabilities.CanSetVolume === true
                        }
                        IntentSlider {
                            id: volumeControl
                            objectName: "volumeControl"
                            x: parent.width - root.tokens.gap - root.tokens.target * 3
                            y: root.narrow ? root.tokens.rowHeight + root.tokens.inset
                                : root.tokens.inset + root.tokens.gap
                            width: root.tokens.target * 3
                            tokens: root.tokens
                            coordinator: root.coordinator
                            action: "SetVolume"
                            label: "Volume"
                            sample: root.endpoint ? root.endpoint.volume : 0
                            maximum: 1
                            step: 0.05
                            actionEnabled: root.controlsAllowed && root.capabilities.CanControl === true && root.capabilities.CanSetVolume === true && root.pending !== "SetVolume" && !root.pickerOpen
                            visible: !!root.endpoint && root.capabilities.CanSetVolume === true
                        }
                    }
                    Item {
                        id: statusBand
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: root.tokens.bandStatus
                        // Capped and elided: this is the one Text in the stage
                        // that would otherwise grow without bound and push the
                        // footer off the card at narrow widths and large fonts.
                        Text {
                            id: errorMessage
                            objectName: "actionErrorMessage"
                            width: parent.width
                            text: root.errorText
                            visible: text !== ""
                            opacity: text !== "" ? 1 : 0
                            Behavior on opacity {
                                enabled: root.tokens.feedbackDuration > 0
                                NumberAnimation { duration: root.tokens.feedbackDuration }
                            }
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: root.tokens.error
                            font.family: root.tokens.fontFamily
                            font.pixelSize: root.tokens.bodySize
                            textFormat: Text.PlainText
                            Accessible.name: text
                            IslandToolTip {
                                parent: errorMessage
                                tokens: root.tokens
                                visible: errorHover.hovered && errorMessage.truncated
                                delay: 600
                                text: errorMessage.text
                            }
                            HoverHandler { id: errorHover }
                        }
                        // Shares the status band with the error line and yields
                        // to it, so an armed timer never changes the band height.
                        Text {
                            objectName: "sleepIndicator"
                            width: parent.width
                            anchors.bottom: parent.bottom
                            visible: root.errorText === "" && text !== ""
                            text: !root.coordinator ? ""
                                : root.coordinator.sleepFailure ? Strings.sleepFailureText(root.coordinator.sleepFailure)
                                : root.coordinator.sleepDeadline > 0 ? Strings.sleepUntil(root.coordinator.sleepDeadline) : ""
                            elide: Text.ElideRight
                            color: root.coordinator && root.coordinator.sleepFailure ? root.tokens.error : root.tokens.secondary
                            font.family: root.tokens.fontFamily
                            font.pixelSize: root.tokens.captionSize
                            textFormat: Text.PlainText
                            Accessible.name: text
                        }
                    }
                    Item {
                        id: footerBand
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.tokens.bandFooter
                        IslandButton {
                            id: sourceButton
                            objectName: "openSourcePicker"
                            width: parent.width - root.tokens.inset - root.tokens.target * 3
                            tokens: root.tokens
                            text: (root.coordinator && root.coordinator.selectionMode === "pinned" ? "Pinned · " : "Auto · ") + root.sourceCount()
                            accessibleLabel: "Choose a music source. " + text
                            background: Rectangle {
                                radius: root.tokens.rowRadius
                                color: sourceButton.hovered || sourceButton.down ? root.tokens.hover : root.tokens.surfaceRaised
                                border.width: sourceButton.visualFocus ? root.tokens.focusWidth : 0
                                border.color: root.tokens.accent
                                Behavior on color {
                                    enabled: root.tokens.feedbackDuration > 0
                                    ColorAnimation { duration: root.tokens.feedbackDuration }
                                }
                            }
                            contentItem: Item {
                                IslandIcon {
                                    x: root.tokens.small
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "sources"
                                    ink: root.tokens.tint
                                }
                                Column {
                                    x: root.tokens.target
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - root.tokens.target
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        text: root.coordinator && root.coordinator.selectionMode === "pinned" ? "Pinned" : "Auto"
                                        textFormat: Text.PlainText
                                        color: root.tokens.text
                                        font.family: root.tokens.fontFamily
                                        font.pixelSize: root.tokens.bodySize
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: root.sourceCount()
                                        textFormat: Text.PlainText
                                        color: root.tokens.secondary
                                        font.family: root.tokens.fontFamily
                                        font.pixelSize: root.tokens.captionSize
                                        elide: Text.ElideRight
                                    }
                                }
                                IslandIcon {
                                    anchors.right: parent.right
                                    anchors.rightMargin: root.tokens.small
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "expand"
                                    ink: root.tokens.secondary
                                }
                            }
                            onActivated: { root.settingsOpen = false; root.pickerOpen = true; }
                        }
                        IslandButton {
                            objectName: "raiseButton"
                            x: parent.width - root.tokens.target * 3
                            tokens: root.tokens
                            iconName: "raise"
                            accessibleLabel: "Show player"
                            actionEnabled: root.controlsAllowed && root.capabilities.CanRaise === true && !root.pickerOpen
                            disabledReason: "This source cannot bring its window forward"
                            pending: root.pending === "Raise"
                            coordinator: root.coordinator
                            actionName: "Raise"
                        }
                        IslandButton {
                            id: settingsButton
                            objectName: "openSettingsButton"
                            x: parent.width - root.tokens.target * 2
                            tokens: root.tokens
                            iconName: "settings"
                            accessibleLabel: "Nookisle settings"
                            onActivated: { root.pickerOpen = false; root.settingsOpen = true; }
                        }
                        IslandButton {
                            x: parent.width - root.tokens.target
                            tokens: root.tokens
                            iconName: "close"
                            accessibleLabel: "Close Nookisle"
                            onActivated: root.toggleRequested()
                        }
                    }
                }
            }
        }
    }
}
