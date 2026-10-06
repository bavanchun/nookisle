pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../qml/Calendar.js" as Calendar
import "../qml/Idle.js" as Idle

// The idle notch's default style, filling the whole closed body: a lead dot
// in the accent, one line (the time and date, or the next event when the
// owner opted in), a battery pip that shows only when the battery needs a
// glance, and a hairline along the bottom that shows the day's progress or
// counts down to the coming event. The day's progress is a neutral, faint
// fill (notchMutedInk at dayHairlineOpacity), so it never reads as the
// track's tinted progress it takes over from; it fades in from nothing when
// the glance appears (one finite tween), so the handover never jumps. The
// countdown keeps the event's colour. The clock steps once a minute, and only
// while the glance is on screen: a single-shot timer re-armed to the next
// minute, so the idle notch redraws about once a minute and never loops.
// The row stays balanced: with the pip shown, the dot at the left inset
// mirrors it at the right; without it, the dot hugs the line and the two are
// centred as one group, so no empty wing weighs against the dot. The privacy
// dots at the trailing end never reflow the row: the group keeps its centre
// and its line only narrows (symmetrically) to stay clear of them.
// With `gapWidth` set (a hardware notch), nothing enters the camera gap:
// the line's first part ends 6 px short of it in the left wing, the dot
// starts 6 px past it in the right wing beside the pip, and the hairline,
// which would cross it, is left out.
Item {
    id: root
    required property var tokens
    // "auto", "time", "date" or "off" (the idleClock setting).
    property string clockSetting: "auto"
    property bool barHasClock: false
    // The calendar's window items, or [] unless the owner opted in to the
    // next event; titles only with their own opt-in.
    property var calendarItems: []
    property var calendarOptions: ({})
    property bool eventTitles: false
    property var batteryReading: ({ present: false })
    property bool hairline: true
    // Room kept free at the trailing end, for a minimal activity glyph.
    property real trailingReserve: 0
    // Room the privacy dots take at the very end. Unlike an activity glyph
    // they never move the row: the text only keeps clear of them.
    property real privacyReserve: 0
    // The camera gap's width in the body's centre, or 0 for none.
    property real gapWidth: 0
    readonly property bool wings: gapWidth > 0
    readonly property real gapLeft: (width - gapWidth) / 2
    readonly property real gapRight: (width + gapWidth) / 2
    readonly property bool showHairline: hairline && !wings
    // The hairline fill's entrance, 0 to 1 once, when the glance appears.
    property real hairlineReveal: tokens.reducedMotion ? 1 : 0
    NumberAnimation {
        id: reveal
        target: root
        property: "hairlineReveal"
        to: 1
        duration: root.tokens.hairlineRevealDuration
        easing.type: Easing.OutCubic
    }
    property var now: new Date()
    readonly property bool hostVisible: !root.Window.window || root.Window.window.visible
    readonly property bool ticking: visible && hostVisible
    readonly property var event: calendarItems.length > 0
        ? Calendar.nextUpcoming(calendarItems, now, calendarOptions, Idle.EVENT_HORIZON_MINUTES) : null
    readonly property var text: Idle.line(now, Idle.clockMode(clockSetting, barHasClock), event, eventTitles)
    readonly property color eventColour: event && /^#[0-9a-fA-F]{6}$/.test(String(event.item.color || "")) ? event.item.color : tokens.tint
    readonly property color leadColour: event ? eventColour : tokens.tint
    readonly property bool pip: Idle.pipVisible(batteryReading)
    // With no trailing glyph or pip, the dot and line centre as one group.
    // A trailing activity or privacy indicator instead mirrors the dot.
    readonly property bool grouped: !wings && !pip && trailingReserve <= 0
    readonly property real dotSpan: 6 + tokens.gap
    readonly property real lineWidth: primary.width + (secondary.visible ? secondary.width : 0)
    readonly property real groupLeft: Math.round((width - trailingReserve - dotSpan - lineWidth) / 2)
    // The same band the live progress hairline takes, so the row sits where
    // the live row does.
    readonly property real band: showHairline ? tokens.hairlineHeight + 4 : 0
    Accessible.role: Accessible.StaticText
    Accessible.name: Idle.accessibleName(text)

    function tick() {
        now = new Date();
        armTick();
    }
    function armTick() {
        minute.stop();
        if (!ticking) return;
        var current = new Date();
        minute.interval = Math.max(1000, 60000 - current.getSeconds() * 1000 - current.getMilliseconds() + 50);
        minute.start();
    }
    onTickingChanged: if (ticking) tick(); else minute.stop()
    Component.onCompleted: {
        armTick();
        if (!tokens.reducedMotion)
            reveal.start();
    }
    Timer {
        id: minute
        objectName: "glanceMinute"
        repeat: false
        onTriggered: root.tick()
    }

    Rectangle {
        objectName: "glanceDot"
        x: root.wings ? root.gapRight + 6 : root.grouped ? root.groupLeft : root.tokens.closedInset
        y: (root.height - root.band - height) / 2
        width: 6
        height: 6
        radius: 3
        color: root.leadColour
    }
    Row {
        id: line
        objectName: "glanceLine"
        readonly property real room: root.wings ? Math.max(0, root.gapLeft - 6 - root.tokens.closedInset)
            : root.grouped ? root.width - root.trailingReserve - 2 * (root.tokens.closedInset + root.privacyReserve) - root.dotSpan
            : root.width - 2 * (root.tokens.closedInset + 12 + root.tokens.gap) - root.trailingReserve - root.privacyReserve
        // Placed from the parts' own widths: a Row reports its width only
        // after it lays out. In the wings only the first part shows.
        x: root.wings ? root.gapLeft - 6 - primary.width
            : root.grouped ? root.groupLeft + root.dotSpan
            : Math.round((root.width - root.trailingReserve - root.lineWidth) / 2)
        y: (root.height - root.band - height) / 2
        Text {
            id: primary
            objectName: "glancePrimary"
            width: Math.min(implicitWidth, line.room)
            text: root.text.primary
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.text.soon ? root.eventColour : root.tokens.text
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize + 1
            font.weight: Font.Medium
            Accessible.ignored: true
        }
        Text {
            id: secondary
            objectName: "glanceSecondary"
            visible: !root.wings
            width: Math.min(implicitWidth, Math.max(0, line.room - primary.width))
            text: root.text.secondary
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.text.soon ? root.eventColour : root.tokens.secondary
            font.family: root.tokens.fontFamily
            renderType: root.tokens.textRenderType
            font.pixelSize: root.tokens.captionSize + 1
            Accessible.ignored: true
        }
    }
    BatteryPip {
        objectName: "glancePip"
        visible: root.pip
        x: root.width - width - root.tokens.closedInset - root.trailingReserve - root.privacyReserve
        y: (root.height - root.band - height) / 2
        reading: root.batteryReading
    }
    Rectangle {
        objectName: "glanceHairline"
        visible: root.showHairline
        x: Math.round(root.height / 2)
        y: root.height - root.tokens.hairlineHeight - 2
        width: root.width - 2 * x
        height: root.tokens.hairlineHeight
        radius: height / 2
        color: Qt.rgba(root.tokens.text.r, root.tokens.text.g, root.tokens.text.b, 0.16)
        Accessible.ignored: true
        Rectangle {
            objectName: "glanceHairlineFill"
            width: Math.round(parent.width * Idle.hairlineFraction(root.now, root.event))
            height: parent.height
            radius: parent.radius
            color: root.event ? root.eventColour
                : Qt.rgba(root.tokens.notchMutedInk.r, root.tokens.notchMutedInk.g, root.tokens.notchMutedInk.b,
                    root.tokens.dayHairlineOpacity)
            opacity: root.hairlineReveal
        }
    }
}
