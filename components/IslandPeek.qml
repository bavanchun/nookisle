pragma ComponentBehavior: Bound

import QtQuick

// The peek's content, bloomed from the pill for a few seconds: a track row
// (art with its glow, title and artists, live bars, progress hairline) or a
// one-row power readout (glyph, label, level bar, percentage), or an event
// row for a device, a finished timer or a capture (glyph, title and detail,
// and a level bar when it has a level). Pure QtQuick.
// Laid out at the peek's final size and revealed by the growing card, which
// clips it, so the content never reflows while the card blooms.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    // "track", "power", "device", "timerDone" or "capture".
    property string kind: "track"
    // An event peek's content (PeekModel.event).
    property var event: null
    readonly property bool eventKind: ["device", "timerDone", "capture"].indexOf(kind) >= 0
    readonly property real eventLevel: event && typeof event.level === "number" ? event.level : -1
    readonly property color eventInk: event && event.alert ? tokens.error : tokens.text
    property bool inlineTrack: false
    // "plugged", "unplugged", "low" or "critical".
    property string powerKind: "plugged"
    property real powerLevel: 0
    // False while the peek is off screen: the bars then stop following the
    // spectrum lines, so a hidden peek costs nothing per line.
    property bool showing: false
    // As ClosedNotch.liveSpectrum: only the island under the pointer draws
    // the live bars.
    property bool liveSpectrum: true
    readonly property var endpoint: coordinator ? coordinator.selectedEndpoint : null
    readonly property var presentation: endpoint && endpoint.presentation ? endpoint.presentation : ({})
    readonly property string title: endpoint ? String(presentation.title || presentation.hostApp || "Player") : "Nookisle"
    readonly property string artists: Array.isArray(presentation.artists) ? presentation.artists.join(", ") : ""
    readonly property bool playing: !!endpoint && endpoint.status === "Playing"
    readonly property real lengthSeconds: endpoint && endpoint.lengthSeconds > 0 ? endpoint.lengthSeconds : 0
    readonly property real progressFraction: lengthSeconds > 0 && coordinator
        ? Math.max(0, Math.min(1, Number(coordinator.positionSeconds) / lengthSeconds)) || 0 : 0
    readonly property bool powerAlert: powerKind === "low" || powerKind === "critical"
    // Low and critical warn in the error colour, plugged in reads green, and
    // on battery stays in the card's text colour.
    readonly property color powerInk: powerAlert ? tokens.error : powerKind === "plugged" ? tokens.charging : tokens.text
    readonly property int percent: Math.round(Math.max(0, Math.min(1, powerLevel)) * 100)
    readonly property string powerLabel: powerKind === "low" ? "Battery low"
        : powerKind === "critical" ? "Battery critical"
        : powerKind === "unplugged" ? "On battery"
        : percent >= 100 ? "Fully charged" : "Charging"
    // The row on screen. A kind change while the peek shows (a power event
    // over a track peek) fades the old row out before the new one fades in,
    // while the card eases to the new shape, so the two never overlap.
    property string shownKind: "track"
    property real rowFade: 1
    Component.onCompleted: shownKind = kind
    onKindChanged: {
        swap.stop();
        if (!root.showing || root.tokens.reducedMotion) {
            root.shownKind = root.kind;
            root.rowFade = 1;
        } else
            swap.start();
    }
    onShowingChanged: {
        if (!root.showing) {
            swap.stop();
            boltPulse.stop();
            root.shownKind = root.kind;
            root.rowFade = 1;
        } else
            root.pulseBolt();
    }
    onShownKindChanged: pulseBolt()
    onPowerKindChanged: pulseBolt()
    // A plug-in greets the bolt with one pulse: it swells and a ring spreads
    // from it and fades. Finite, and skipped under reduced motion.
    function pulseBolt() {
        if (!root.showing || root.shownKind !== "power" || root.powerKind !== "plugged" || root.tokens.reducedMotion)
            return;
        boltPulse.restart();
    }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: root; property: "rowFade"; to: 0; duration: 90; easing.type: Easing.InCubic }
        ScriptAction { script: root.shownKind = root.kind }
        NumberAnimation { target: root; property: "rowFade"; to: 1; duration: 130; easing.type: Easing.OutCubic }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: kind === "power" ? powerLabel + ", " + percent + " percent"
        : eventKind ? (event ? event.title + ", " + event.detail
            + (eventLevel >= 0 ? ", " + Math.round(eventLevel * 100) + " percent" : "") : "")
        : "Now playing: " + title + (artists ? " by " + artists : "")

    Item {
        id: trackRow
        objectName: "peekTrackRow"
        anchors.fill: parent
        visible: root.shownKind === "track" && !root.inlineTrack
        opacity: root.rowFade
        readonly property int pad: root.tokens.medium
        ArtGlow {
            objectName: "peekArtGlow"
            tokens: root.tokens
            target: peekArt
            radius: peekArt.radius
        }
        Artwork {
            id: peekArt
            objectName: "peekArtwork"
            x: trackRow.pad
            // Centred on the card as it rests, not on the growing clip.
            y: Math.round((root.tokens.peekHeight - height) / 2)
            width: root.tokens.peekArtSize
            height: width
            radius: root.tokens.peekArtRadius
            tokens: root.tokens
            artworkPath: root.endpoint
                ? String(root.endpoint.artworkPath || "") : ""
            border.width: 1
            border.color: root.tokens.stroke
        }
        Column {
            x: peekArt.x + peekArt.width + trackRow.pad
            anchors.verticalCenter: peekArt.verticalCenter
            width: peekBars.x - x - trackRow.pad
            spacing: 2
            Text {
                objectName: "peekTitle"
                width: parent.width
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.tokens.text
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.titleSize
                font.weight: Font.Medium
            }
            Text {
                objectName: "peekArtists"
                visible: text !== ""
                width: parent.width
                text: root.artists
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.captionSize
            }
        }
        SpectrumBars {
            id: peekBars
            objectName: "peekSpectrum"
            visible: !!root.coordinator && root.coordinator.visualizer === true && root.liveSpectrum
                && !root.tokens.reducedMotion
                && root.coordinator.spectrumState !== "unavailable"
            x: trackRow.width - width - trackRow.pad
            anchors.verticalCenter: peekArt.verticalCenter
            width: root.tokens.spectrumWidth
            height: maxHeight
            tokens: root.tokens
            live: !!root.coordinator && root.coordinator.spectrumState === "running"
            playing: root.playing
            levels: root.showing && root.shownKind === "track" && root.coordinator && root.coordinator.spectrumLevels
                ? root.coordinator.spectrumLevels : []
            maxHeight: 24
        }
        // The pill's hairline, carried into the peek along its bottom edge.
        // It runs under the title and the bars, not under the art, so it
        // never crosses the glow, and stays clear of the rounded corners.
        Rectangle {
            id: hairline
            objectName: "peekHairline"
            visible: root.lengthSeconds > 0
            x: peekArt.x + peekArt.width + trackRow.pad
            y: root.tokens.peekHeight - root.tokens.hairlineHeight - 3
            width: trackRow.width - trackRow.pad - x
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
    }
    Item {
        objectName: "peekInlineTrack"
        anchors.fill: parent
        visible: root.shownKind === "track" && root.inlineTrack
        opacity: root.rowFade
        Text {
            objectName: "peekInlineTitle"
            x: root.tokens.small
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, (parent.width - root.tokens.idleWidth) / 2 - root.tokens.gap)
            text: root.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.tokens.tintText
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
        Text {
            objectName: "peekInlineArtist"
            x: parent.width - width - root.tokens.small
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, (parent.width - root.tokens.idleWidth) / 2 - root.tokens.gap)
            horizontalAlignment: Text.AlignRight
            text: root.artists
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.tokens.tintText
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
    }

    Item {
        id: powerRow
        objectName: "peekPowerRow"
        anchors.fill: parent
        visible: root.shownKind === "power"
        opacity: root.rowFade
        readonly property int pad: root.tokens.medium
        Rectangle {
            id: boltRing
            objectName: "peekBoltRing"
            anchors.centerIn: powerIcon
            width: powerIcon.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: root.powerInk
            opacity: 0
            visible: opacity > 0
        }
        IslandIcon {
            id: powerIcon
            objectName: "peekPowerIcon"
            x: powerRow.pad
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            name: root.powerKind === "plugged" ? "bolt" : "battery"
            level: root.powerLevel
            ink: root.powerInk
        }
        ParallelAnimation {
            id: boltPulse
            objectName: "peekBoltPulse"
            onStopped: {
                powerIcon.scale = 1;
                boltRing.opacity = 0;
            }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: powerIcon; property: "scale"; from: 1; to: 1.3; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: powerIcon; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                ParallelAnimation {
                    NumberAnimation { target: boltRing; property: "scale"; from: 1; to: 1.5; duration: 520; easing.type: Easing.OutCubic }
                    NumberAnimation { target: boltRing; property: "opacity"; from: 0.7; to: 0; duration: 520; easing.type: Easing.OutCubic }
                }
            }
        }
        Text {
            objectName: "peekPowerLabel"
            x: powerIcon.x + powerIcon.width + root.tokens.gap
            anchors.verticalCenter: parent.verticalCenter
            width: levelTrack.x - x - root.tokens.gap
            text: root.powerLabel
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.bodySize
            font.weight: Font.Medium
        }
        Rectangle {
            id: levelTrack
            objectName: "peekPowerTrack"
            x: percentLabel.x - width - root.tokens.gap
            anchors.verticalCenter: parent.verticalCenter
            width: 72
            height: root.tokens.small
            radius: height / 2
            color: root.tokens.surfaceSunken
            Rectangle {
                objectName: "peekPowerFill"
                width: Math.max(height, Math.round(levelTrack.width * Math.max(0, Math.min(1, root.powerLevel))))
                height: parent.height
                radius: parent.radius
                color: root.powerInk
            }
        }
        Text {
            id: percentLabel
            objectName: "peekPowerPercent"
            // A fixed slot for "100%", so the bar never shifts as the level
            // changes by a digit.
            x: powerRow.width - powerRow.pad - width
            anchors.verticalCenter: parent.verticalCenter
            width: percentMetrics.advanceWidth
            horizontalAlignment: Text.AlignRight
            text: root.percent + "%"
            textFormat: Text.PlainText
            color: root.powerInk
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.weight: Font.Medium
            TextMetrics {
                id: percentMetrics
                font: percentLabel.font
                text: "100%"
            }
        }
    }
    Item {
        id: eventRow
        objectName: "peekEventRow"
        anchors.fill: parent
        visible: ["device", "timerDone", "capture"].indexOf(root.shownKind) >= 0
        opacity: root.rowFade
        readonly property int pad: root.tokens.medium
        readonly property bool hasLevel: root.eventLevel >= 0
        readonly property string thumbnail: root.event && root.event.thumbnail ? String(root.event.thumbnail) : ""
        IslandIcon {
            id: eventIcon
            objectName: "peekEventIcon"
            visible: eventRow.thumbnail === ""
            x: eventRow.pad
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            name: root.event ? String(root.event.icon || "bluetooth") : "bluetooth"
            level: root.event && root.event.icon === "ring" ? 0 : 1
            ink: root.event && root.event.alert ? root.tokens.error : root.tokens.accent
        }
        Image {
            objectName: "peekEventThumbnail"
            visible: eventRow.thumbnail !== ""
            x: eventRow.pad
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 16
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize: Qt.size(48, 32)
            source: eventRow.thumbnail !== "" ? "file://" + eventRow.thumbnail : ""
        }
        Text {
            id: eventTitle
            objectName: "peekEventTitle"
            x: eventRow.pad + 24 + root.tokens.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, (eventRow.hasLevel ? eventTrack.x : eventRow.width - eventRow.pad) - x - root.tokens.gap)
            text: root.event ? String(root.event.title || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.eventInk
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.bodySize
            font.weight: Font.Medium
        }
        Text {
            objectName: "peekEventDetail"
            x: eventTitle.x + eventTitle.width + root.tokens.small
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, (eventRow.hasLevel ? eventTrack.x : eventRow.width - eventRow.pad) - x - root.tokens.gap)
            text: root.event ? String(root.event.detail || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
        }
        Rectangle {
            id: eventTrack
            objectName: "peekEventTrack"
            visible: eventRow.hasLevel
            x: eventPercent.x - width - root.tokens.gap
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: root.tokens.small
            radius: height / 2
            color: root.tokens.surfaceSunken
            Rectangle {
                width: Math.max(height, Math.round(eventTrack.width * Math.max(0, Math.min(1, root.eventLevel))))
                height: parent.height
                radius: parent.radius
                color: root.event && root.event.alert ? root.tokens.error : root.tokens.text
            }
        }
        Text {
            id: eventPercent
            objectName: "peekEventPercent"
            visible: eventRow.hasLevel
            x: eventRow.width - eventRow.pad - width
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(Math.max(0, Math.min(1, root.eventLevel)) * 100) + "%"
            textFormat: Text.PlainText
            color: root.eventInk
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.weight: Font.Medium
        }
    }
}
