pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Idle.js" as Idle

// The closed notch's content, after boring.notch's closed live activity: a
// left wing, the empty centre of the notch body, and a right wing, filled as
// ClosedModel says. Live music puts the 20 px cover on the left and the
// spectrum (or a static play-state glyph when the spectrum binary is not
// available) on the right, with a progress hairline along the bottom. The
// wings mirror each other: the cover sits closedInset from the body's left
// end and the spectrum as far from its right end. The
// battery banner puts its label on the left and the battery on the right.
// The inline HUD draws itself (HudInline) over the widened notch. Sized to
// fill the notch body.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    // What each wing holds, from ClosedModel: "art", "spectrum",
    // "batteryLabel", "batteryIcon", "face" or "none". HudInline draws
    // the HUD's "hudIcon" and "hudLevel" content over the widened notch.
    property string leftContent: "none"
    property string rightContent: "none"
    // The body's centre: "title" (the track title, without a hardware notch),
    // an idle style ("glance", "face", "horizon"), an activity's label
    // ("recordingLabel", "timerLabel") or "none".
    property string centreContent: "none"
    // A second activity, shrunk to a glyph at the trailing end: "recording",
    // "music", "timer", "sleepTimer" or "none" (ClosedModel.minimalContent).
    property string minimalContent: "none"
    // ActivityModel: the activities' minute labels and the timer's ring.
    property var activities: null
    // PrivacySource's state, or null while the indicators are off. The dots
    // themselves are PrivacyDots, drawn above every closed layer; the wings
    // only keep clear of them.
    property var privacy: null
    readonly property bool privacyShown: !!privacy && privacy.any === true
    readonly property bool micMutedShown: privacyShown && privacy.micMuted === true
    // The privacy column's room at the trailing end, then the minimal glyph,
    // then the right wing's content.
    readonly property real trailingEdge: tokens.closedInset
        + (micMutedShown ? tokens.privacyMutedInset : privacyShown ? tokens.privacyInset : 0)
    readonly property real minimalWidth: minimalContent === "none" ? 0
        : minimalContent === "sleepTimer" ? sleepMinimal.implicitWidth : tokens.minimalGlyph
    // What the right wing holds at its inset: the bars (or the play-state
    // glyph) or an activity's minutes; nothing while idle. The music slot is
    // as wide playing as paused (the wider of the bars or play-state glyph
    // and the pause glyph), so the centre title never moves on a pause.
    readonly property real rightContentWidth: rightContent === "spectrum"
        ? Math.max(pauseGlyph.width, spectrumSlot ? tokens.closedSpectrumWidth : glyph.width)
        : rightContent === "recordingValue" || rightContent === "timerValue" ? activityValueText.implicitWidth : 0
    // Without a camera cutout the minimal glyph closes the centre region,
    // just before the right wing's content. Over a cutout, or with nothing
    // on the right (idle), it takes the outer end, and the right wing's
    // content moves in beside it.
    readonly property bool minimalOuter: hardwareNotch || rightContentWidth <= 0
    readonly property real rightInset: trailingEdge + (minimalOuter && minimalWidth > 0 ? minimalWidth + tokens.small : 0)
    readonly property real minimalX: minimalOuter ? width - trailingEdge - minimalWidth
        : width - rightInset - rightContentWidth - tokens.gap - minimalWidth
    // The centre region's trailing edge, from the body's right end.
    readonly property real centreRight: rightInset + (rightContentWidth > 0 ? rightContentWidth + tokens.gap : 0)
        + (!minimalOuter && minimalWidth > 0 ? minimalWidth + tokens.gap : 0)
    // The idle glance's inputs (IdleGlance), and the battery reading its pip
    // and the Horizon pip show.
    property string clockSetting: "auto"
    property bool barHasClock: false
    property var calendarItems: []
    property var calendarOptions: ({})
    property bool eventTitles: false
    property bool idleHairline: true
    property var batteryReading: ({ present: false })
    // The face's mood from the island: "happy", "worried" or "".
    property string faceMood: ""
    // The battery banner: whether its gauge shows the percentage and the
    // status mark, and where its two halves meet. Over a camera cutout they
    // sit either side of the camera gap; otherwise they meet in the middle.
    property bool batteryPercent: true
    property bool batteryStatusIcons: true
    property bool hardwareNotch: false
    readonly property real bannerGap: hardwareNotch ? centreWidth : 0
    readonly property real bannerLeftEdge: (width - bannerGap) / 2 - tokens.medium
    readonly property real bannerRightEdge: (width + bannerGap) / 2 + tokens.medium
    // The centre of the body that stays empty: the idle notch's body.
    property real centreWidth: 0
    property bool coloredSpectrum: true
    property real batteryLevel: 0
    property string batteryLabel: ""
    readonly property var endpoint: coordinator ? coordinator.selectedEndpoint : null
    readonly property bool pinUnavailable: coordinator && coordinator.pinUnavailable === true
    readonly property string artworkPath: endpoint ? String(endpoint.artworkPath || "") : ""
    // The music glyph stands in only for art that is missing, or that has
    // not arrived artLoadGrace ms after it was asked for; art that is about
    // to load never flashes the glyph first.
    readonly property bool artworkLate: artworkPath !== "" && !wingArt.ready && !artLoadGrace.running && artLoadGrace.expired
    Timer {
        id: artLoadGrace
        property bool expired: false
        interval: 150
        onTriggered: expired = true
    }
    readonly property bool artWanted: leftContent === "art" && artworkPath !== ""
    function restartArtGrace() {
        artLoadGrace.expired = false;
        if (artWanted)
            artLoadGrace.restart();
        else
            artLoadGrace.stop();
    }
    onArtworkPathChanged: restartArtGrace()
    onArtWantedChanged: restartArtGrace()
    Component.onCompleted: restartArtGrace()
    readonly property bool playing: endpoint && endpoint.status === "Playing"
    // The bars take the glyph's place whenever the visualizer is on, motion
    // is not reduced and the binary has not been found missing; paused or
    // silent, they lie flat.
    // False on an island that is not under the pointer when every screen
    // shows one: only one island draws the live bars.
    property bool liveSpectrum: true
    readonly property bool spectrumSlot: coordinator && coordinator.visualizer === true
        && coordinator.spectrumState !== "unavailable" && liveSpectrum && !tokens.reducedMotion
    // Paused while the notch still holds the live row (the pause grace),
    // once the bars have fallen.
    readonly property bool pausedRest: rightContent === "spectrum" && !playing && !(spectrumSlot && closedBars.falling)
    readonly property real lengthSeconds: endpoint && endpoint.lengthSeconds > 0 ? endpoint.lengthSeconds : 0
    readonly property real progressFraction: lengthSeconds > 0 && coordinator
        ? Math.max(0, Math.min(1, Number(coordinator.positionSeconds) / lengthSeconds)) || 0 : 0
    readonly property real wingWidth: Math.max(0, (width - centreWidth) / 2)
    // The hairline takes a band at the bottom (its own height plus a gap and
    // a margin), and the wings centre in what is left. On the live bar-sized
    // notch (26 px) that leaves 20 px, so the art and the bars shrink to 16
    // rather than touch the hairline or the screen edge.
    readonly property real hairlineBand: hairline.visible ? tokens.hairlineHeight + 4 : 0
    readonly property real rowCentre: (height - hairlineBand) / 2
    readonly property real glyphSize: Math.max(tokens.spectrumMinBar,
        Math.min(tokens.wingArt, height - hairlineBand - 4))
    readonly property real spectrumBarSpan: Math.max(0, glyphSize - tokens.spectrumMinBar)
    readonly property string title: endpoint ? String(endpoint.presentation.title || endpoint.presentation.hostApp || "Player")
        : pinUnavailable ? "Source lost" : "Nookisle"
    readonly property string stateText: playing ? "Playing" : "Paused"
    // Music names its track and state, a banner its label, and idle what the
    // idle style shows (the glance's line), else "Nothing playing".
    readonly property string idleName: glanceLoader.item ? glanceLoader.item.Accessible.name : "Nothing playing"
    Accessible.role: Accessible.StaticText
    readonly property string activityName: leftContent === "recordingGlyph" && activities
        ? "Screen recording, " + activities.recordingElapsed
        : leftContent === "timerGlyph" && activities ? activities.timerLabel + ", " + activities.timerRemaining + " left" : ""
    Accessible.name: activityName !== "" ? activityName
        : leftContent === "art" || (endpoint && centreContent === "title") ? title + ". " + stateText
        : leftContent === "batteryLabel" ? batteryLabel
        : idleName
    Item {
        id: leftWing
        objectName: "leftWing"
        width: root.wingWidth
        height: root.height - root.hairlineBand
        // Paused (within the pause grace) the cover dims, as the open
        // player's does: one short tween per play-state change.
        opacity: root.leftContent === "art" && !root.playing ? root.tokens.pausedWingOpacity : 1
        Behavior on opacity {
            enabled: !root.tokens.reducedMotion
            NumberAnimation { duration: root.tokens.feedbackDuration }
        }
        Artwork {
            id: wingArt
            objectName: "pillArtwork"
            visible: root.leftContent === "art" && !!root.endpoint && root.artworkPath !== ""
            placeholder: false
            x: root.tokens.closedInset
            anchors.verticalCenter: parent.verticalCenter
            width: root.glyphSize
            height: root.glyphSize
            radius: root.tokens.wingArtRadius
            tokens: root.tokens
            artworkPath: root.artworkPath
        }
        IslandIcon {
            objectName: "pillMusicGlyph"
            visible: root.leftContent === "art" && (!root.endpoint || root.artworkPath === ""
                || root.artworkLate && !wingArt.showingPrevious)
            x: root.tokens.closedInset
            anchors.verticalCenter: parent.verticalCenter
            width: root.glyphSize
            height: root.glyphSize
            name: "music"
            ink: root.tokens.text
        }
        // The banner's label hugs the centre, as in boring.notch: its right
        // edge 12 px short of the camera gap, or of the body's middle.
        Text {
            objectName: "batteryLabel"
            visible: root.leftContent === "batteryLabel"
            anchors.verticalCenter: parent.verticalCenter
            x: root.bannerLeftEdge - width
            width: Math.max(0, root.bannerLeftEdge - root.tokens.closedInset)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: root.batteryLabel
            textFormat: Text.PlainText
            color: root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.weight: Font.Medium
        }
    }
    // An activity in the notch: its glyph on the left, its minutes on the
    // right, and its label in the centre when no camera cutout is there.
    Row {
        id: recordingGlyphRow
        objectName: "recordingGlyph"
        visible: root.leftContent === "recordingGlyph"
        x: root.tokens.closedInset
        y: root.rowCentre - height / 2
        spacing: root.tokens.small
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.tokens.recordingDot
            height: width
            radius: width / 2
            color: root.tokens.recordingInk
        }
        Text {
            objectName: "recordingGlyphText"
            anchors.verticalCenter: parent.verticalCenter
            text: "REC"
            textFormat: Text.PlainText
            color: root.tokens.recordingInk
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.weight: Font.DemiBold
        }
    }
    IslandIcon {
        objectName: "timerGlyph"
        visible: root.leftContent === "timerGlyph"
        x: root.tokens.closedInset
        y: root.rowCentre - height / 2
        width: root.tokens.minimalGlyph
        height: width
        name: "ring"
        level: root.activities ? root.activities.timerFraction : 0
        ink: root.tokens.accent
    }
    Text {
        id: activityValueText
        objectName: "activityValue"
        visible: root.rightContent === "recordingValue" || root.rightContent === "timerValue"
        x: root.width - width - root.rightInset
        y: root.rowCentre - height / 2
        text: !root.activities ? "" : root.rightContent === "recordingValue" ? root.activities.recordingElapsed
            : root.activities.timerRemaining
        textFormat: Text.PlainText
        color: root.rightContent === "recordingValue" ? root.tokens.recordingInk : root.tokens.text
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }
    Text {
        objectName: "activityLabel"
        visible: root.centreContent === "recordingLabel" || root.centreContent === "timerLabel"
        // Centred, clear of the glyph on the left and of the minutes (and a
        // minimal glyph) on the right.
        readonly property real side: Math.max(root.tokens.closedInset + recordingGlyphRow.width + root.tokens.gap, root.centreRight)
        readonly property real room: root.width - 2 * side
        x: (root.width - width) / 2
        y: root.rowCentre - height / 2
        width: Math.max(0, Math.min(implicitWidth, room))
        elide: Text.ElideRight
        text: !root.activities ? "" : root.centreContent === "recordingLabel" ? "Screen recording" : root.activities.timerLabel
        textFormat: Text.PlainText
        color: root.tokens.text
        font.family: root.tokens.fontFamily
        renderType: root.tokens.textRenderType
        font.pixelSize: root.tokens.captionSize
        font.weight: Font.Medium
        Accessible.ignored: true
    }
    // The second activity's glyph (minimalX).
    Item {
        objectName: "minimalActivity"
        visible: root.minimalContent !== "none"
        x: root.minimalX
        y: root.rowCentre - height / 2
        width: root.minimalWidth
        height: root.tokens.minimalGlyph
        Accessible.ignored: true
        Rectangle {
            objectName: "minimalRecording"
            visible: root.minimalContent === "recording"
            anchors.centerIn: parent
            width: root.tokens.recordingDot
            height: width
            radius: width / 2
            color: root.tokens.recordingInk
        }
        Artwork {
            objectName: "minimalArt"
            visible: root.minimalContent === "music" && root.artworkPath !== ""
            anchors.fill: parent
            placeholder: false
            radius: root.tokens.wingArtRadius
            tokens: root.tokens
            artworkPath: visible ? root.artworkPath : ""
        }
        IslandIcon {
            visible: root.minimalContent === "music" && root.artworkPath === ""
            anchors.fill: parent
            name: "music"
            ink: root.tokens.text
        }
        IslandIcon {
            objectName: "minimalTimer"
            visible: root.minimalContent === "timer"
            anchors.fill: parent
            name: "ring"
            level: root.activities ? root.activities.timerFraction : 0
            ink: root.tokens.accent
        }
        // Laid out by hand, not in a Row: its width sets the glyph's slot,
        // and a Row reports it only after its next polish.
        Item {
            id: sleepMinimal
            objectName: "minimalSleep"
            visible: root.minimalContent === "sleepTimer"
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: moon.width + 2 + sleepText.implicitWidth
            height: parent.height
            IslandIcon {
                id: moon
                anchors.verticalCenter: parent.verticalCenter
                width: root.tokens.minimalGlyph - 4
                height: width
                name: "moon"
                ink: root.tokens.secondary
            }
            Text {
                id: sleepText
                objectName: "minimalSleepText"
                x: moon.width + 2
                anchors.verticalCenter: parent.verticalCenter
                text: root.activities ? root.activities.sleepLabel : ""
                textFormat: Text.PlainText
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                renderType: root.tokens.textRenderType
                font.pixelSize: root.tokens.captionSize - 1
                font.features: { "tnum": 1 }
            }
        }
    }
    Item {
        id: rightWing
        objectName: "rightWing"
        x: root.width - width
        width: root.wingWidth
        height: root.height - root.hairlineBand
        Row {
            id: glyph
            objectName: "playStateGlyph"
            visible: root.rightContent === "spectrum" && !root.spectrumSlot && !root.pausedRest
            x: parent.width - width - root.rightInset
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: 3 * 3 + 2 * 2
            height: root.glyphSize
            Repeater {
                model: [0.45, 1, 0.7]
                Rectangle {
                    required property real modelData
                    anchors.bottom: parent.bottom
                    width: 3
                    radius: 1
                    color: root.coloredSpectrum ? root.tokens.tint : root.tokens.text
                    height: (root.playing ? modelData : 0.3) * parent.height
                    Behavior on height {
                        enabled: !root.tokens.reducedMotion
                        NumberAnimation { duration: root.tokens.feedbackDuration }
                    }
                }
            }
        }
        SpectrumBars {
            id: closedBars
            visible: root.rightContent === "spectrum" && root.spectrumSlot
            // Gone once a pause has let the bars fall flat: the pause glyph
            // takes their place for the rest of the grace.
            opacity: root.pausedRest ? 0 : 1
            Behavior on opacity {
                enabled: !root.tokens.reducedMotion
                NumberAnimation { duration: root.tokens.feedbackDuration }
            }
            x: parent.width - width - root.rightInset
            anchors.verticalCenter: parent.verticalCenter
            width: root.tokens.closedSpectrumWidth
            barGap: root.tokens.closedSpectrumGap
            height: maxHeight
            tokens: root.tokens
            ink: root.coloredSpectrum ? root.tokens.tint : root.tokens.text
            live: root.coordinator && root.coordinator.spectrumState === "running"
            playing: root.playing
            levels: root.coordinator && root.coordinator.spectrumLevels ? root.coordinator.spectrumLevels : []
            // From the notch's own height, so the bars peak level with the
            // art, clear of the hairline and inside the notch.
            maxHeight: root.glyphSize
        }
        // Paused within the grace: two short bars that say "paused", where
        // the bars (once fallen) or the play-state glyph were, instead of a
        // row of flat dots. Static; it fades in once, over 100 ms.
        Row {
            id: pauseGlyph
            objectName: "pauseGlyph"
            visible: opacity > 0
            opacity: root.pausedRest ? 1 : 0
            Behavior on opacity {
                enabled: !root.tokens.reducedMotion
                NumberAnimation { duration: root.tokens.feedbackDuration }
            }
            x: parent.width - width - root.rightInset
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: 2
                Rectangle {
                    width: 3
                    height: Math.round(root.glyphSize / 2)
                    radius: 1
                    color: root.coloredSpectrum ? root.tokens.tint : root.tokens.text
                }
            }
        }
        // The gauge from the open header, in its colours (green charging,
        // red low, amber power saver) with its status mark and percentage,
        // hugging the centre from the other side.
        BatteryGauge {
            objectName: "batteryIcon"
            visible: root.rightContent === "batteryIcon"
            anchors.verticalCenter: parent.verticalCenter
            x: root.bannerRightEdge - rightWing.x
            reading: root.batteryReading.present === true ? root.batteryReading
                : ({ present: true, onBattery: false, level: root.batteryLevel, state: "Unknown", powerSaver: false })
            showPercent: root.batteryPercent
            showStatusIcon: root.batteryStatusIcons
            textRenderType: root.tokens.textRenderType
            fontFamily: root.tokens.fontFamily
            fontSize: root.tokens.captionSize
        }
    }
    // Without a hardware notch the body's centre holds the track title,
    // between the cover and the bars. After a track change, while playing,
    // a title too long to fit scrolls through one Marquee pass and then
    // rests elided: the closed notch never loops a marquee.
    readonly property real titleLeft: tokens.closedInset + glyphSize + tokens.gap
    readonly property real titleRight: centreRight
    readonly property string trackTitle: endpoint && endpoint.presentation
        ? String(endpoint.presentation.title || endpoint.presentation.hostApp || "") : ""
    property bool titlePassing: false
    function startTitlePass() {
        titlePass.stop();
        titlePassing = false;
        if (centreContent === "title" && playing && !tokens.reducedMotion && trackTitle !== "" && titleMarquee.overflowing) {
            titlePassing = true;
            titlePass.restart();
        }
    }
    // Deferred, so the marquee has measured the new title first.
    onTrackTitleChanged: Qt.callLater(startTitlePass)
    onCentreContentChanged: Qt.callLater(startTitlePass)
    onPlayingChanged: Qt.callLater(startTitlePass)
    Timer {
        id: titlePass
        objectName: "titlePass"
        // The pause before the pass, the pass itself, and a frame's slack.
        interval: root.tokens.marqueeDelay
            + Math.ceil((titleMarquee.textWidth + titleMarquee.gap) / root.tokens.marqueeSpeed * 1000) + 100
        onTriggered: root.titlePassing = false
    }
    Item {
        id: centreSlot
        objectName: "centreSlot"
        x: root.titleLeft
        width: Math.max(0, root.width - root.titleLeft - root.titleRight)
        height: root.height - root.hairlineBand
        visible: root.centreContent === "title"
        Text {
            objectName: "closedTitle"
            visible: !root.titlePassing
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.trackTitle
            textFormat: Text.PlainText
            color: root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize
            font.weight: Font.Medium
            Accessible.ignored: true
        }
        Marquee {
            id: titleMarquee
            objectName: "closedTitleMarquee"
            visible: root.titlePassing
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            tokens: root.tokens
            text: root.trackTitle
            color: root.tokens.text
            pixelSize: root.tokens.captionSize
            weight: Font.Medium
            Accessible.ignored: true
        }
    }
    // Nothing playing: the idle style. The glance loads only while shown.
    Loader {
        id: glanceLoader
        objectName: "idleGlanceLoader"
        anchors.fill: parent
        active: root.centreContent === "glance" || root.leftContent === "glance"
        sourceComponent: IdleGlance {
            objectName: "idleGlance"
            tokens: root.tokens
            // In the wings, clear of the camera gap, over a hardware notch.
            gapWidth: root.leftContent === "glance" ? root.centreWidth : 0
            clockSetting: root.clockSetting
            barHasClock: root.barHasClock
            calendarItems: root.calendarItems
            calendarOptions: root.calendarOptions
            eventTitles: root.eventTitles
            batteryReading: root.batteryReading
            hairline: root.idleHairline
            // The privacy column's room apart from an activity glyph's: the
            // glance keeps its layout under the dots.
            privacyReserve: root.trailingEdge - root.tokens.closedInset
            trailingReserve: root.rightInset - root.trailingEdge
        }
    }
    // Horizon: one short accent line where the progress hairline sits, and
    // the battery pip when the battery needs a glance. Nothing else, and
    // nothing that moves.
    Item {
        objectName: "idleHorizon"
        anchors.fill: parent
        visible: root.centreContent === "horizon"
        Rectangle {
            objectName: "horizonLine"
            x: Math.round((parent.width - width) / 2)
            y: parent.height - root.tokens.hairlineHeight - 2
            width: root.tokens.horizonLine
            height: root.tokens.hairlineHeight
            radius: height / 2
            color: root.tokens.tint
        }
        BatteryPip {
            objectName: "horizonPip"
            visible: Idle.pipVisible(root.batteryReading)
            x: parent.width - width - root.rightInset
            y: (parent.height - root.tokens.hairlineHeight - 4 - height) / 2
            reading: root.batteryReading
        }
    }
    // The idle face: centred in the body, or in the right wing over a
    // camera cutout. It blinks only while shown.
    IdleFace {
        objectName: "closedIdleFace"
        visible: root.centreContent === "face" || root.rightContent === "face"
        x: root.rightContent === "face" ? rightWing.x + (rightWing.width - width) / 2 : (root.width - width) / 2
        y: (root.height - height) / 2
        height: root.glyphSize
        width: height * 1.5
        color: root.tokens.text
        reducedMotion: root.tokens.reducedMotion === true
        moodOverride: root.faceMood
        sleepsAtNight: true
    }
    // Track progress along the bottom edge while the music is live, inset by
    // the bottom radius so it never runs into the rounded corners. No
    // animation: it steps at most once a second while closed.
    Rectangle {
        id: hairline
        objectName: "progressHairline"
        visible: root.leftContent === "art" && root.lengthSeconds > 0
        x: Math.round(root.height / 2)
        y: root.height - root.tokens.hairlineHeight - 2
        width: root.width - 2 * x
        height: root.tokens.hairlineHeight
        radius: height / 2
        color: Qt.rgba(root.tokens.text.r, root.tokens.text.g, root.tokens.text.b, 0.16)
        Accessible.ignored: true
        Rectangle {
            objectName: "progressHairlineFill"
            width: Math.round(hairline.width * root.progressFraction)
            height: parent.height
            radius: parent.radius
            color: root.tokens.tint
        }
    }
}
