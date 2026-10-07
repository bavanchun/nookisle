pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../qml/Strings.js" as Strings

// The Home player, after boring.notch's NotchHomeView: the 90 px cover with
// its glow and app badge on the left; beside it the title and artist (both
// scrolling when they do not fit), an inline lyric line or a status line,
// the scrubber with its times, and the button row.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    // The typed settings, resolved (IslandSurface.settings).
    property var settings: ({})
    property var lyricsSource: null
    // The source app's icon, resolved by the host; empty hides the badge.
    property string appIcon: ""
    // Both side panels share Home: the button row drops its edge slots.
    property bool crowded: false
    // The calendar's items and options while it is on, for the idle glance.
    property var calendarItems: []
    property var calendarOptions: ({})
    signal lyricsRequested
    signal sourcesRequested
    readonly property bool controlsAllowed: !!coordinator && coordinator.panelAllowed === true && coordinator.uiAllowed === true
    readonly property var endpoint: controlsAllowed ? coordinator.selectedEndpoint : null
    readonly property var presentation: endpoint && endpoint.presentation ? endpoint.presentation : ({})
    readonly property var capabilities: endpoint && endpoint.capabilities ? endpoint.capabilities : ({})
    readonly property bool playing: !!endpoint && endpoint.status === "Playing"
    readonly property bool unavailable: !!coordinator && coordinator.pinUnavailable === true
    readonly property bool metadataTruncated: !!endpoint && endpoint.presentationTruncated === true
    readonly property string title: endpoint ? String(presentation.title || presentation.hostApp || Strings.player)
        : unavailable ? String(coordinator.selectedLabel || "Selected source") : !controlsAllowed ? "Connect Nookisle" : "No music source yet"
    readonly property string artist: Array.isArray(presentation.artists) ? presentation.artists.join(", ") : ""
    readonly property string pending: coordinator ? String(coordinator.pendingAction || "") : ""
    readonly property string artworkPath: endpoint ? String(endpoint.artworkPath || "") : ""
    readonly property real lengthSeconds: endpoint ? Math.max(0, Number(endpoint.lengthSeconds) || 0) : 0
    readonly property bool interacting: progress.gesturing || toolbar.interacting
    // Connected and healthy with nothing to play: the glance takes the
    // title's place. A lost pinned source or a lost connection keeps its
    // explaining title.
    readonly property bool glanceShown: !endpoint && controlsAllowed && !unavailable
    readonly property color sliderFill: settings.sliderColor === "white" ? "#ffffff"
        : settings.sliderColor === "accent" ? tokens.accent : tokens.tint
    // The status line: an action's error, or the connection state while no
    // source is shown.
    readonly property string statusText: {
        var error = coordinator ? Strings.resultText(coordinator.actionError) : "";
        if (error)
            return error;
        if (endpoint)
            return "";
        if (controlsAllowed)
            return unavailable ? "Choose a source again, or switch to Auto." : "Open Spotify, or play music in your browser.";
        return Strings.statusText(coordinator ? coordinator.statusText : "connecting");
    }
    // The lyric line: with lyrics on, it holds its place for every track,
    // showing the current synced line, or the lookup's state while there is
    // none, so the block under it never jumps as lyrics arrive.
    readonly property bool lyricsOn: !!coordinator && coordinator.lyrics === true && !!lyricsSource
        && lyricsSource.lyricsEnabled === true
    readonly property string lyricsState: lyricsOn ? String(lyricsSource.lyricsState || "idle") : "off"
    readonly property var lyricLines: lyricsState === "ready" && Array.isArray(lyricsSource.lines)
        ? lyricsSource.lines : []
    readonly property bool lyricShown: lyricsOn && !!endpoint && statusText === ""
    readonly property bool lyricSynced: lyricShown && lyricLines.length > 0
    readonly property int lyricIndex: lyricSynced ? lyricsSource.currentIndex : -1
    readonly property string lyricText: {
        if (lyricIndex >= 0 && lyricIndex < lyricLines.length)
            return String(lyricLines[lyricIndex].text);
        if (lyricSynced)
            return "♪";
        switch (lyricsState) {
        case "idle":
        case "loading":
            return "Loading lyrics…";
        case "plain":
            return "Unsynced lyrics";
        case "instrumental":
            return "Instrumental";
        }
        return "No lyrics found";
    }
    // Arabic and Persian lines take Vazirmatn when it is installed.
    readonly property bool vazirmatn: Qt.fontFamilies().indexOf("Vazirmatn") >= 0
    function lyricFont(text) {
        return vazirmatn && /[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]/.test(text) ? "Vazirmatn" : tokens.fontFamily;
    }
    function timeText(seconds) {
        var s = Math.max(0, Math.floor(Number(seconds) || 0)), m = Math.floor(s / 60);
        return (m >= 60 ? Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") : "") + (m % 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }
    function dispatch(action) {
        if (!coordinator || pending !== "")
            return false;
        var intent = coordinator.captureIntent();
        if (!intent)
            return false;
        coordinator.invoke(action, intent);
        return true;
    }
    function invokePlayPause() {
        if (!endpoint || capabilities.CanControl !== true || !(playing ? capabilities.CanPause === true : capabilities.CanPlay === true))
            return false;
        return dispatch("PlayPause");
    }
    function raiseSource() {
        return capabilities.CanRaise === true && dispatch("Raise");
    }
    function focusControls() {
        if (!endpoint) {
            sourceChoice.forceActiveFocus(Qt.TabFocusReason);
            return true;
        }
        return toolbar.focusControls();
    }
    readonly property int artPadding: 5
    // The cover scales to pausedArtScale while paused, on the button spring.
    readonly property real pausedScale: tokens.pausedArtScale
    readonly property real artScale: artSpring.value
    // 0 while playing, 1 when fully paused: drives the dark overlay.
    readonly property real pausedAmount: Math.max(0, Math.min(1, (1 - artScale) / (1 - pausedScale)))
    onPlayingChanged: artSpring.moveTo(playing || !endpoint ? 1 : pausedScale, 0.35, 0.7, tokens.reducedMotion)
    SpringDriver {
        id: artSpring
        // Set once: a binding here would jump with `playing` before the
        // spring could move.
        Component.onCompleted: settle(root.playing || !root.endpoint ? 1 : root.pausedScale)
    }
    // A double-tap's own acknowledgement: a quick dip on top of the scale.
    property real pulse: 1
    SequentialAnimation {
        id: artPulse
        NumberAnimation {
            target: root
            property: "pulse"
            to: 0.92
            duration: root.tokens.feedbackDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "pulse"
            to: 1
            duration: root.tokens.feedbackDuration * 2
            easing.type: Easing.OutBack
            easing.overshoot: 2
        }
    }
    Item {
        id: artBox
        objectName: "artBox"
        // boring.notch pads the cover by 5 px, and the text column starts
        // 10 px down, so Home's columns share one top line.
        x: root.artPadding
        y: root.artPadding
        width: root.tokens.heroArt
        height: width
        ArtGlow {
            tokens: root.tokens
            target: heroArt
            radius: heroArt.radius
            scale: heroArt.scale
            lit: root.settings.lightingEffect !== false
            playing: root.playing
            gpuAllowed: true
        }
        // Nothing playing: the idle face, 80x70, in the cover's place. Its
        // blink runs only while it is visible.
        IdleFace {
            objectName: "homeIdleFace"
            visible: !root.endpoint
            anchors.centerIn: parent
            width: 80
            height: 70
            color: root.tokens.secondary
            reducedMotion: root.tokens.reducedMotion === true
        }
        Artwork {
            id: heroArt
            objectName: "heroArtwork"
            // A placeholder cover beside a "no source" heading reads as a
            // broken cover rather than an empty state.
            visible: !!root.endpoint
            width: parent.width
            height: width
            tokens: root.tokens
            artworkPath: root.artworkPath
            radius: root.tokens.heroArtRadius
            scale: root.artScale * root.pulse
            // Paused, the cover darkens: a blurred dark copy with GPU effects
            // (drawn over the cover below), a flat black veil otherwise.
            Rectangle {
                objectName: "pausedVeil"
                anchors.fill: parent
                radius: parent.radius
                color: "#000000"
                visible: !root.tokens.gpuEffects
                opacity: 0.5 * root.pausedAmount
            }
            // Paused, one tap resumes, as the play glyph on the cover says.
            // Playing, one tap raises the source app (when it allows that),
            // after the double-click interval has passed without a second
            // tap; a double tap toggles play/pause. A MouseArea, not a
            // TapHandler: it acts on the platform's own double-click event,
            // which is also what QtTest can send.
            MouseArea {
                objectName: "heroArtGesture"
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    if (!root.playing && root.invokePlayPause()) {
                        // The second press of a double tap must not pause
                        // what the first one just resumed.
                        resumeGuard.restart();
                        return;
                    }
                    raiseTimer.restart();
                }
                onDoubleClicked: {
                    raiseTimer.stop();
                    if (resumeGuard.running)
                        return;
                    if (root.invokePlayPause() && root.tokens.feedbackDuration > 0) {
                        artPulse.stop();
                        root.pulse = 1;
                        artPulse.start();
                    }
                }
                Timer {
                    id: resumeGuard
                    interval: Qt.styleHints.mouseDoubleClickInterval
                    repeat: false
                }
                Timer {
                    id: raiseTimer
                    interval: Qt.styleHints.mouseDoubleClickInterval
                    repeat: false
                    onTriggered: root.raiseSource()
                }
            }
        }
        // The paused blur is the cover's sibling, never its child: an effect
        // inside its own source keeps that source on the old window when the
        // panel moves to a new one, and the scene graph then syncs through
        // the deleted window.
        Loader {
            x: heroArt.x
            y: heroArt.y
            width: heroArt.width
            height: heroArt.height
            scale: heroArt.scale
            visible: heroArt.visible
            active: root.tokens.gpuEffects && root.pausedAmount > 0
            sourceComponent: MultiEffect {
                objectName: "pausedBlur"
                source: heroArt
                blurEnabled: true
                blur: 0.6
                brightness: -0.6
                opacity: 0.8 * root.pausedAmount
            }
        }
        // Paused, a play glyph on the cover: a tap there resumes.
        IslandIcon {
            objectName: "pausedPlayGlyph"
            anchors.centerIn: heroArt
            width: 30
            height: 30
            name: "play"
            ink: "#ffffff"
            visible: heroArt.visible && opacity > 0
            opacity: root.pausedAmount
        }
        // The source app's badge, overhanging the cover's corner. Tapping it
        // chooses the source.
        Image {
            id: badge
            objectName: "appBadge"
            x: parent.width - width + 10
            y: parent.height - height + 10
            width: 30
            height: 30
            sourceSize: Qt.size(60, 60)
            source: root.appIcon
            visible: !!root.endpoint && root.appIcon !== "" && status === Image.Ready
            activeFocusOnTab: true
            fillMode: Image.PreserveAspectFit
            Accessible.role: Accessible.Button
            Accessible.name: "Choose the source"
            Accessible.onPressAction: root.sourcesRequested()
            Keys.onReturnPressed: event => { event.accepted = true; root.sourcesRequested(); }
            Keys.onEnterPressed: event => { event.accepted = true; root.sourcesRequested(); }
            Keys.onSpacePressed: event => { event.accepted = true; root.sourcesRequested(); }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: 6
                border.width: badge.activeFocus ? root.tokens.focusWidth : 0
                border.color: root.tokens.accent
            }
            TapHandler {
                onTapped: root.sourcesRequested()
            }
        }
        // Without an app icon, the badge is a small raised tile with the
        // sources glyph, so it reads as a control rather than a stray icon.
        Rectangle {
            objectName: "sourceBadgeTile"
            visible: !!root.endpoint && !badge.visible
            x: badge.x
            y: badge.y
            width: 30
            height: 30
            radius: 8
            color: root.tokens.raisedSurface
            border.width: 1
            border.color: Qt.rgba(root.tokens.text.r, root.tokens.text.g, root.tokens.text.b, 0.12)
        }
        IslandButton {
            objectName: "sourceBadgeFallback"
            visible: !!root.endpoint && !badge.visible
            x: badge.x
            y: badge.y
            width: 30
            height: 30
            tokens: root.tokens
            iconName: "sources"
            accessibleLabel: "Choose the source"
            onActivated: root.sourcesRequested()
            Keys.onReturnPressed: event => { event.accepted = true; root.sourcesRequested(); }
            Keys.onEnterPressed: event => { event.accepted = true; root.sourcesRequested(); }
        }
    }
    // Home's shared top line: the cover's top edge. The first line of text
    // (the title, or the glance's time) is placed so its capitals start on
    // it, and the calendar aligns its month the same way (HomeView).
    readonly property real capTop: artPadding
    // From a text line's top to the top of its capitals: the ascent less
    // the capital height (the tight box of "H" sits above the baseline).
    function capOffset(metrics) {
        return metrics.ascent + metrics.tightBoundingRect("H").y;
    }
    FontMetrics {
        id: titleMetrics
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.titleSize + 2
        font.weight: Font.Bold
    }
    FontMetrics {
        id: glanceMetrics
        font.family: root.tokens.fontFamily
        font.pixelSize: 34
        font.weight: Font.Light
    }
    Column {
        id: details
        objectName: "playerDetails"
        x: artBox.x + artBox.width + root.artPadding + root.tokens.gap
        y: Math.round(root.capTop - root.capOffset(root.glanceShown ? glanceMetrics : titleMetrics))
        width: root.width - x
        spacing: 0
        HomeGlance {
            objectName: "homeGlance"
            width: parent.width
            visible: root.glanceShown
            tokens: root.tokens
            calendarItems: root.calendarItems
            calendarOptions: root.calendarOptions
        }
        Row {
            width: parent.width
            visible: !root.glanceShown
            spacing: root.tokens.small
            Marquee {
                objectName: "trackTitle"
                width: parent.width - (root.metadataTruncated ? truncationMarker.width + parent.spacing : 0)
                tokens: root.tokens
                text: root.title
                pixelSize: root.tokens.titleSize + 2
                weight: Font.Bold
                color: root.tokens.text
            }
            Text {
                id: truncationMarker
                objectName: "homeTruncationMarker"
                visible: root.metadataTruncated
                text: "…"
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.bodySize
                activeFocusOnTab: true
                Accessible.name: "Some source details were trimmed"
                IslandToolTip {
                    tokens: root.tokens
                    visible: truncationHover.hovered || truncationMarker.activeFocus
                    delay: truncationHover.hovered ? 600 : 0
                    text: "This source sent more text than fits; some details were trimmed."
                }
                HoverHandler { id: truncationHover }
            }
        }
        Marquee {
            objectName: "trackArtist"
            width: parent.width
            visible: root.artist !== ""
            tokens: root.tokens
            text: root.artist
            weight: Font.Medium
            color: root.tokens.secondary
        }
        // One line under the artist: the lyric, or the status. Clipped, so
        // a new line dropping in never draws over the artist.
        Item {
            objectName: "lyricRow"
            width: parent.width
            height: root.tokens.bodySize + root.tokens.small * 2
            visible: root.lyricShown || root.statusText !== ""
            clip: true
            Marquee {
                id: inlineLyric
                objectName: "inlineLyric"
                width: parent.width
                visible: root.lyricShown
                tokens: root.tokens
                text: root.lyricText
                fontFamily: root.lyricFont(root.lyricText)
                color: root.tokens.secondary
                // Each new line drops in from above and fades up; a state
                // message ("Loading lyrics…") is dimmer than a line.
                property real enter: 1
                y: -root.tokens.gap * (1 - enter)
                opacity: enter * (root.playing ? (root.lyricSynced ? 1 : 0.7) : 0)
                Behavior on opacity {
                    enabled: root.tokens.lyricLineDuration > 0
                    NumberAnimation { duration: root.tokens.lyricLineDuration }
                }
                onTextChanged: if (root.tokens.lyricLineDuration > 0) {
                    lineIn.stop();
                    enter = 0;
                    lineIn.start();
                }
                NumberAnimation {
                    id: lineIn
                    target: inlineLyric
                    property: "enter"
                    to: 1
                    duration: root.tokens.lyricLineDuration
                    easing.type: Easing.OutCubic
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Lyrics: " + text
                // Hidden while paused, so it takes no tap then.
                TapHandler {
                    enabled: root.playing
                    onTapped: root.lyricsRequested()
                }
            }
            Text {
                objectName: "playerStatus"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                visible: root.statusText !== ""
                text: root.statusText
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.coordinator && root.coordinator.actionError ? root.tokens.error : root.tokens.secondary
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.captionSize
            }
        }
        Row {
            visible: !root.endpoint
            width: parent.width
            spacing: root.tokens.small
            IslandButton {
                id: sourceChoice
                objectName: "homeSourceButton"
                tokens: root.tokens
                tonal: true
                text: "Sources"
                accessibleLabel: "Choose a source"
                onActivated: root.sourcesRequested()
                Keys.onReturnPressed: event => { event.accepted = true; root.sourcesRequested(); }
                Keys.onEnterPressed: event => { event.accepted = true; root.sourcesRequested(); }
            }
            IslandButton {
                objectName: "homeRetryButton"
                visible: !root.controlsAllowed && !!root.coordinator && root.coordinator.panelAllowed === true
                tokens: root.tokens
                text: "Retry"
                primary: true
                onActivated: root.coordinator.retryConnection()
            }
        }
        // The scrubber across the column, with the times under it, as
        // boring.notch lays it out.
        Column {
            objectName: "scrubberBlock"
            visible: !!root.endpoint
            width: parent.width
            topPadding: root.tokens.small
            IntentSlider {
                id: progress
                objectName: "progressControl"
                width: parent.width
                height: root.tokens.scrubHeightActive + 3
                trackPadding: 0
                tokens: root.tokens
                coordinator: root.coordinator
                thickens: true
                fillColor: root.sliderFill
                maximum: root.lengthSeconds
                sample: root.coordinator ? root.coordinator.positionSeconds : 0
                step: 5
                actionEnabled: root.controlsAllowed && root.capabilities.CanControl === true
                    && root.capabilities.CanSetPosition === true && maximum > 0 && root.pending !== "SetPosition"
                disabledReason: root.endpoint && root.endpoint.seekUnavailableReason === "track-id-oversized"
                    ? "This track's ID is too long to seek reliably"
                    : maximum <= 0 ? "Duration unknown, so seeking is unavailable" : "This source does not support seeking"
            }
            Item {
                width: parent.width
                height: elapsed.implicitHeight
                Text {
                    id: elapsed
                    objectName: "elapsedTime"
                    text: root.timeText(progress.displayValue)
                    textFormat: Text.PlainText
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    font.weight: Font.Medium
                    font.features: root.tokens.numberFeatures
                }
                Text {
                    objectName: "totalTime"
                    anchors.right: parent.right
                    text: root.lengthSeconds > 0 ? root.timeText(root.lengthSeconds) : "--:--"
                    textFormat: Text.PlainText
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                    font.weight: Font.Medium
                    font.features: root.tokens.numberFeatures
                }
            }
        }
    }
    // The buttons sit at the foot of Home, level with the calendar's last
    // row, so the column's space is balanced rather than all above them;
    // never over the scrubber on a short Home.
    MusicToolbar {
        id: toolbar
        objectName: "musicToolbar"
        visible: !!root.endpoint
        x: details.x
        y: Math.max(details.y + details.height + root.tokens.small, root.height - height)
        width: details.width
        height: root.tokens.playSize
        tokens: root.tokens
        coordinator: root.coordinator
        slots: root.settings.musicControlSlots || ["shuffle", "previous", "playPause", "next", "repeat"]
        limit: root.settings.musicControlSlotLimit || 5
        crowded: root.crowded
    }
}
