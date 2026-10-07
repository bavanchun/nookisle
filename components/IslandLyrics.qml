pragma ComponentBehavior: Bound

import QtQuick

// The Lyrics view: the song's lines around the one being sung, following
// the playback position, with the track and the lyrics' source in a footer
// under a progress hairline. The current line is large
// and bright in the card's text colour; the line before it and the lines
// after it are smaller and dimmed. When the song moves on, the lines glide
// up one step while the next line grows into the current one: one finite
// ease per line, none at all under reduced motion. Every state that is not
// a synced song (off, looking up, not found, untimed lyrics only, no track
// length, an error) replaces the lines with a short centred message. Pure
// QtQuick; LyricsSource does the fetching.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    // Panel.qml's LyricsSource, passed down through IslandSurface.
    property var source: null

    readonly property var endpoint: coordinator && coordinator.panelAllowed === true && coordinator.uiAllowed === true
        ? coordinator.selectedEndpoint : null
    readonly property var presentation: endpoint && endpoint.presentation ? endpoint.presentation : ({})
    readonly property string title: String(presentation.title || presentation.hostApp || "Player")
    readonly property string artists: Array.isArray(presentation.artists) ? presentation.artists.join(", ") : ""
    readonly property real lengthSeconds: endpoint && endpoint.lengthSeconds > 0 ? endpoint.lengthSeconds : 0
    readonly property real progressFraction: lengthSeconds > 0 && coordinator
        ? Math.max(0, Math.min(1, Number(coordinator.positionSeconds) / lengthSeconds)) || 0 : 0
    // What the view shows: the source's display state, plus the one case
    // only the view can tell apart (nothing playing).
    readonly property string stateName: {
        var s = source ? String(source.displayState || "off") : "off";
        return s !== "off" && !endpoint ? "empty" : s;
    }
    readonly property bool synced: stateName === "ready"
    readonly property var lines: synced && source.lines ? source.lines : []
    readonly property string note: "♪"

    // The line on screen. It follows the source's currentIndex through
    // advance(), so the glide knows where the new current line came from.
    property int shownIndex: -1
    readonly property int targetIndex: synced ? source.currentIndex : -1
    onTargetIndexChanged: advance()
    // A view opened mid-song starts on the line being sung, with no glide.
    Component.onCompleted: shownIndex = targetIndex
    function lineText(index) {
        return index >= 0 && index < lines.length ? String(lines[index].text) : "";
    }
    // Before the first line the current slot holds a note, like a break.
    readonly property string currentText: synced ? (shownIndex < 0 ? note : lineText(shownIndex)) : ""
    readonly property string earlierText: lineText(shownIndex - 2)
    readonly property string previousText: lineText(shownIndex - 1)
    readonly property string nextText: lineText(shownIndex + 1)
    readonly property string laterText: lineText(shownIndex + 2)

    // Line styles. The current line is the lyric token plus a step, so it
    // reads as the headline of the card; the upcoming line is what it grows
    // from, and the lines further away shrink and fade.
    readonly property int currentSize: tokens.lyricCurrentSize + 4
    readonly property int upcomingSize: tokens.titleSize
    readonly property int lineSpacing: tokens.medium + 2
    // High contrast lifts every neighbour to at least 0.66, the least that
    // keeps the secondary colour at 4.5:1 on the notch.
    readonly property real alphaFloor: tokens.highContrast ? 0.66 : 0
    readonly property color neighbourColor: tokens.highContrast ? tokens.text : tokens.secondary
    readonly property real earlierAlpha: Math.max(0.3, alphaFloor)
    readonly property real previousAlpha: Math.max(0.55, alphaFloor)
    readonly property real nextAlpha: Math.max(0.9, alphaFloor)
    readonly property real laterAlpha: Math.max(0.5, alphaFloor)
    readonly property real nextScale: upcomingSize / currentSize
    // The glide: 0 when a line change starts, 1 at rest. `glideShift` is
    // how far below its rest the line group starts: one full step when the
    // song moved on by a line, a short rise for a seek or the first line.
    property real glide: 1
    property real glideShift: 0
    property bool glideForward: false
    readonly property int glideDuration: tokens.lyricLineDuration * 2
    function advance() {
        var forward = targetIndex === shownIndex + 1;
        var shift = forward ? currentLine.height + lineSpacing : 6;
        shownIndex = targetIndex;
        glideMotion.stop();
        if (glideDuration <= 0 || !root.visible) {
            glide = 1;
            return;
        }
        glideForward = forward;
        glideShift = shift;
        glide = 0;
        glideMotion.start();
    }
    NumberAnimation {
        id: glideMotion
        target: root
        property: "glide"
        to: 1
        duration: root.glideDuration
        easing.type: Easing.OutCubic
    }

    // Return from the summoned root lands here: on Try again when it shows,
    // so Tab and Space reach it, otherwise on the view itself, where the
    // surface's shortcut keys and Escape still arrive by bubbling.
    function focusControls() {
        if (retryButton.visible) {
            retryButton.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        root.forceActiveFocus();
    }

    Accessible.role: Accessible.Pane
    Accessible.name: "Lyrics"

    Item {
        id: stage
        objectName: "lyricsStage"
        x: root.tokens.inset
        y: root.tokens.small
        width: root.width - root.tokens.inset * 2
        height: hairline.y - root.tokens.small - y
        clip: true
        // Where the current line rests: a little above the middle, so the
        // lines to come have room below it.
        readonly property real restY: Math.round(height * 0.40)

        Item {
            id: lineGroup
            objectName: "lyricsLines"
            width: parent.width
            height: parent.height
            visible: root.synced
            transform: Translate { y: root.glideShift * (1 - root.glide) }
            Text {
                objectName: "lyricsEarlierLine"
                y: previousLine.y - root.tokens.gap - height
                width: parent.width
                // Only when it rests wholly inside the stage, so no descenders
                // peek out under the top fade.
                visible: text !== "" && previousLine.visible && y >= 0
                text: root.earlierText
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: root.neighbourColor
                opacity: root.earlierAlpha * (root.glideForward ? root.glide : 1)
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.bodySize
            }
            Text {
                id: previousLine
                objectName: "lyricsPreviousLine"
                y: currentLine.y - root.lineSpacing - height
                width: parent.width
                visible: text !== ""
                text: root.previousText
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: root.neighbourColor
                // The old current line restyles as it becomes this one, so
                // it fades in under the glide rather than jumping.
                opacity: root.previousAlpha * (root.glideForward ? root.glide : 1)
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.bodySize
            }
            Text {
                id: currentLine
                objectName: "lyricsCurrentLine"
                readonly property bool isNote: text === root.note
                y: stage.restY
                width: parent.width
                text: root.currentText
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: isNote ? root.tokens.tint : root.tokens.text
                // Grows out of the upcoming line's size and dimness on a
                // step forward, or fades in on a seek.
                readonly property real fromOpacity: root.glideForward ? root.nextAlpha * 0.8 : 0
                readonly property real fromScale: root.glideForward ? root.nextScale : 1
                opacity: fromOpacity + (1 - fromOpacity) * root.glide
                scale: fromScale + (1 - fromScale) * root.glide
                transformOrigin: Item.TopLeft
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                // A break is a single note, drawn larger so it holds the
                // line's place.
                font.pixelSize: isNote ? Math.round(root.currentSize * 1.4) : root.currentSize
                font.weight: Font.DemiBold
                Accessible.role: Accessible.StaticText
                Accessible.name: isNote ? "Instrumental" : text
            }
            Text {
                id: nextLine
                objectName: "lyricsNextLine"
                y: currentLine.y + currentLine.height + root.lineSpacing
                width: parent.width
                visible: text !== ""
                text: root.nextText
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: text === root.note ? root.tokens.tint : root.neighbourColor
                opacity: root.nextAlpha
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.upcomingSize
                font.weight: Font.Medium
            }
            Text {
                objectName: "lyricsLaterLine"
                y: nextLine.y + nextLine.height + root.tokens.gap
                width: parent.width
                visible: text !== "" && nextLine.visible
                text: root.laterText
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: text === root.note ? root.tokens.tint : root.neighbourColor
                opacity: root.laterAlpha * (root.glideForward ? root.glide : 1)
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.upcomingSize
            }
        }
        // Soft edges: the notch's own colour fading over the lines at the top
        // and bottom of the stage, so lines slide in and out of view rather
        // than being cut. Plain gradients, which the software renderer draws.
        Rectangle {
            width: parent.width
            height: root.tokens.medium
            visible: root.synced
            gradient: Gradient {
                GradientStop { position: 0; color: root.tokens.notchColor }
                GradientStop { position: 1; color: Qt.rgba(root.tokens.notchColor.r, root.tokens.notchColor.g, root.tokens.notchColor.b, 0) }
            }
        }
        Rectangle {
            y: parent.height - height
            width: parent.width
            height: root.tokens.medium
            visible: root.synced
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(root.tokens.notchColor.r, root.tokens.notchColor.g, root.tokens.notchColor.b, 0) }
                GradientStop { position: 1; color: root.tokens.notchColor }
            }
        }

        // Stacked when the stage has room for the icon, two lines and the
        // button; on a short stage, such as the open notch's, one row:
        // icon, text, button.
        Grid {
            id: message
            objectName: "lyricsMessage"
            readonly property bool compact: stage.height < root.tokens.rowHeight * 3
            anchors.centerIn: parent
            width: parent.width - root.tokens.inset
            columns: compact ? 3 : 1
            spacing: compact ? root.tokens.gap : root.tokens.small + 2
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            visible: !root.synced
            readonly property var copy: ({
                "off": ["Lyrics are off", "Turn on Synced lyrics in the settings to look them up on LRCLIB"],
                "empty": ["Nothing is playing", "Lyrics follow the song once a source plays"],
                "no-meta": ["Nothing to look up", "This source does not report a title and artist"],
                "loading": ["Looking up lyrics…", "Asking LRCLIB for this track"],
                "none": ["No synced lyrics for this track", "LRCLIB has no timed lyrics for it"],
                "plain": ["Only unsynced lyrics", "LRCLIB has the words for this track, but not their timing"],
                "instrumental": ["Instrumental", "This track has no lyrics"],
                "no-length": ["Lyrics need the track length", "This source does not report the track length, which lyrics need"],
                "error": ["Lyrics could not be loaded", ""]
            })
            readonly property var words: copy[root.stateName] || ["", ""]
            readonly property string errorDetail: root.source && root.source.errorCode === "timeout"
                ? "LRCLIB did not answer in time"
                : root.source && root.source.errorCode === "too-large" ? "The answer was too large to read"
                : root.source && root.source.errorCode === "busy" ? "LRCLIB is busy right now"
                : root.source && root.source.errorCode === "rate-limited" ? "LRCLIB is limiting requests, try again shortly"
                : "Check the connection and try again"
            IslandIcon {
                objectName: "lyricsMessageIcon"
                width: 24
                height: 24
                name: root.stateName === "error" ? "retry" : "music"
                ink: root.stateName === "error" ? root.tokens.error
                    : root.stateName === "off" || root.stateName === "empty" ? root.tokens.secondary : root.tokens.tint
            }
            Column {
                width: message.compact
                    ? message.width - 24 - (retryButton.visible ? retryButton.width + message.spacing : 0) - message.spacing
                    : message.width
                spacing: root.tokens.small + 2
                Text {
                    objectName: "lyricsMessageTitle"
                    width: parent.width
                    horizontalAlignment: message.compact ? Text.AlignLeft : Text.AlignHCenter
                    wrapMode: message.compact ? Text.NoWrap : Text.WordWrap
                    elide: message.compact ? Text.ElideRight : Text.ElideNone
                    text: message.words[0]
                    textFormat: Text.PlainText
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.bodySize
                    font.weight: Font.Medium
                }
                Text {
                    objectName: "lyricsMessageDetail"
                    width: parent.width
                    visible: text !== ""
                    horizontalAlignment: message.compact ? Text.AlignLeft : Text.AlignHCenter
                    wrapMode: message.compact ? Text.NoWrap : Text.WordWrap
                    elide: message.compact ? Text.ElideRight : Text.ElideNone
                    text: root.stateName === "error" ? message.errorDetail : message.words[1]
                    textFormat: Text.PlainText
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    renderType: root.tokens.textRenderType
                    font.pixelSize: root.tokens.captionSize
                }
            }
            Item {
                width: message.width
                height: root.tokens.small
                visible: retryButton.visible && !message.compact
            }
            IslandButton {
                id: retryButton
                objectName: "lyricsRetry"
                visible: root.stateName === "error"
                tokens: root.tokens
                primary: true
                text: "Try again"
                onActivated: if (root.source) root.source.retry()
            }
        }
    }

    // The song's progress, in the artwork's colour, above the footer.
    Rectangle {
        id: hairline
        objectName: "lyricsHairline"
        visible: root.lengthSeconds > 0
        x: root.tokens.inset
        y: footer.y - root.tokens.small - height
        width: root.width - root.tokens.inset * 2
        height: root.tokens.hairlineHeight
        radius: height / 2
        color: Qt.rgba(root.tokens.text.r, root.tokens.text.g, root.tokens.text.b, 0.16)
        Accessible.ignored: true
        Rectangle {
            width: Math.round(hairline.width * root.progressFraction)
            height: parent.height
            radius: parent.radius
            color: root.tokens.tint
        }
    }

    // The track on the left, and a standing reminder of where the lines come
    // from on the right. With nothing playing only the attribution shows.
    Item {
        id: footer
        objectName: "lyricsFooter"
        x: root.tokens.inset
        y: root.height - height - root.tokens.medium
        width: root.width - root.tokens.inset * 2
        height: root.tokens.wingArt
        Item {
            id: track
            objectName: "lyricsTrack"
            readonly property real available: attribution.x - root.tokens.gap - x
            visible: !!root.endpoint
            width: Math.max(0, available)
            height: parent.height
            Artwork {
                id: footerArt
                objectName: "lyricsArtwork"
                width: root.tokens.wingArt
                height: width
                radius: root.tokens.wingArtRadius
                tokens: root.tokens
                artworkPath: root.endpoint
                    ? String(root.endpoint.artworkPath || "") : ""
                border.width: 1
                border.color: root.tokens.stroke
            }
            Text {
                id: titleText
                objectName: "lyricsTitle"
                x: footerArt.width + root.tokens.gap
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(0, track.width - x))
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.captionSize
                font.weight: Font.Medium
            }
            Text {
                objectName: "lyricsArtists"
                x: titleText.x + titleText.width
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, track.width - x)
                visible: root.artists !== "" && width > 0
                text: " · " + root.artists
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.captionSize
            }
        }
        Text {
            id: attribution
            objectName: "lyricsAttribution"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Lyrics from LRCLIB"
            textFormat: Text.PlainText
            color: root.tokens.secondary
            opacity: 0.7
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
    }
}
