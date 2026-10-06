pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../qml/CatchZone.js" as CatchZone
import "../qml/Timers.js" as Timers
import "../qml/IslandKeys.js" as IslandKeys
import "../qml/Motion.js" as Motion
import "../qml/Settings.js" as Settings
import "../qml/Tint.js" as Tint

// The notch-shaped island: a hover-driven closed notch that springs open into
// a wide panel with Home and Shelf tabs in its header; Lyrics is a sub-view
// of Home (only while the opt-in setting is on). Pure QtQuick, no Quickshell
// import, so qmltestrunner can load and drive it offscreen; the window that
// hosts it (Panel.qml) owns layer-shell placement and the mask.
Item {
    id: root
    required property var tokens
    property var coordinator: null
    // Height of the closed notch: the bar size. The window itself is always
    // mapped at its full open size plus shadow room (tokens.notchWindowWidth
    // and notchWindowHeight); only the notch geometry inside it morphs.
    property real pillHeight: tokens ? tokens.pillMinHeight * 2 + tokens.small : 56
    readonly property real spectrumBarSpan: pill.spectrumBarSpan
    // The screen's width less a gap on each side, from the host. Every notch
    // width is clamped to it; a bare host leaves it unbounded.
    property real availableWidth: Infinity
    // True while the host requested an explicit (keyboard-reachable) open.
    // A hover leave must not collapse an explicit expansion.
    property bool explicitOpen: false
    // The level readout (HudModel). Panel.qml passes its one model; a bare
    // host gets a model of its own.
    property var hudModel: null
    HudModel {
        id: localHud
        tokens: root.tokens
    }
    readonly property var hud: hudModel || localHud
    // True while this island's own HUD bar is held. With an island on every
    // screen the model is shared, and a drag on one island must not latch or
    // defer another; a hold that names no owner applies here too.
    readonly property bool hudHeldHere: hud.held && (!hud.heldBy || contains(hud.heldBy))
    function contains(item) {
        for (var node = item; node; node = node.parent)
            if (node === root)
                return true;
        return false;
    }
    readonly property bool hudActive: hud.active
    readonly property string hudKind: hud.kind
    readonly property real hudLevel: hud.level
    readonly property bool hudMuted: hud.muted
    // The closed readout's style: inside a wider notch ("inline") or as a
    // pill under it ("below").
    readonly property string hudStyle: settings.hudStyle === "below" ? "below" : "inline"
    // A drag on a HUD bar asks for this level: "volume", "brightness" or
    // "keyboard", 0..1. Panel.qml routes it to the sink or the backlight.
    signal hudLevelRequested(string kind, real value)
    // The header battery gauge's reading, and whether Omarchy's power
    // controls exist for the popover's button.
    property var batteryReading: ({ present: false, onBattery: false, level: 0, state: "Unknown",
        timeToEmpty: 0, timeToFull: 0, health: -1, powerSaver: false })
    property bool batteryPowerAvailable: false
    // PrivacySource's state ({ mic, camera, screen, micMuted, any }), or
    // null while the indicators are off.
    property var privacy: null
    property bool batteryPopoverOpen: false
    signal batteryPowerRequested
    // A peek from Panel.qml's PeekModel: `peekKind` is "track" or "power",
    // and `powerKind`/`powerLevel` describe a power peek.
    property bool peekActive: false
    property string peekKind: "track"
    // An event peek's content (PeekModel.event).
    property var peekEvent: null
    property string powerKind: "plugged"
    property real powerLevel: 0
    // False over fullscreen unless opened explicitly: no hover, no tap.
    property bool interactive: true
    // The drop-in and drag-out capability constants Panel.qml passes down
    // from the native-probe decision (results.md): G4/G5 were not performed,
    // and the recorded decision keeps both enabled rather than hiding them.
    property bool dropInSupported: true
    property bool dragOutSupported: true
    property bool bodyDropHandoff: false
    property bool catchDropHandoff: false
    property real catchHandoffWidth: 0
    // True while a drag-out is in progress on the loaded shelf view, so a
    // passing drag never collapses the card mid-gesture.
    // A drag out of the shelf, or a drag over its strip, keeps the island
    // open: neither reports a hover.
    readonly property bool shelfDragActive: shelfViewLoader.item
        ? shelfViewLoader.item.dragActive === true || shelfViewLoader.item.dropActive === true : false
    property bool expanded: false
    property string view: "home"
    // The tabs in header order: the one list both the header and the Tab
    // key read. "lyrics" and "timers" are sub-views of home, shown only while
    // the opt-in `lyrics` or the `timers` setting is on; home stays the
    // selected tab under them.
    readonly property var views: settings.shelfEnabled ? ["home", "shelf"] : ["home"]
    readonly property bool lyricsAvailable: !!coordinator && coordinator.lyrics === true
    readonly property bool timersAvailable: !!coordinator && coordinator.timersEnabled === true
    readonly property bool subView: view === "lyrics" || view === "timers"
    // Only a known view is ever shown: "player", the name home had before,
    // becomes "home", and lyrics falls back to home while it is off.
    function resolveView(name) {
        if (name === "player")
            return "home";
        if (name === "lyrics")
            return lyricsAvailable ? "lyrics" : "home";
        if (name === "timers")
            return timersAvailable ? "timers" : "home";
        return views.indexOf(name) >= 0 ? name : "home";
    }
    onViewChanged: if (resolveView(view) !== view)
        view = resolveView(view)
    onViewsChanged: if (resolveView(view) !== view)
        view = resolveView(view)
    onLyricsAvailableChanged: if (!lyricsAvailable && view === "lyrics")
        view = "home"
    onTimersAvailableChanged: if (!timersAvailable && view === "timers")
        view = "home"
    // The typed settings this surface reads: the coordinator's file
    // settings, each checked against the schema, or its default.
    readonly property var settings: Settings.resolve(coordinator ? coordinator.fileSettings : null)
    readonly property int hoverDwell: settings.hoverDwell
    readonly property int leaveGrace: settings.leaveGrace
    // Panel.qml's LyricsSource, handed to the Lyrics view and Home's lyric
    // line.
    property var lyricsSource: null
    // The source app's icon for the player's badge; empty hides it.
    property string appIcon: ""
    readonly property alias hitShape: hitShape
    readonly property alias catchZone: catchZone
    // True when the host bar's centre holds anything besides this island's
    // spacer (Panel.qml reads the bar layout); the catch zone then stays off.
    property bool barCentreShared: false
    // True when the host bar shows a clock module (Panel.qml reads the bar
    // layout); the idle glance's automatic clock then shows only the date.
    property bool barHasClock: false
    // The empty bar width centred on the notch between the host's left and
    // right module rows, measured by the spacer BarWidget; -1 while unknown,
    // which keeps the catch zone off.
    property real barCentreSpan: -1
    readonly property bool pointerActive: pointerInside || expanded
    // The pointer is over this island itself (open or not), for choosing the
    // one island that draws the live spectrum.
    readonly property bool pointerInside: hover.hovered || extensionHover.hovered || header.overflowHovered
    // True while any control inside the loaded player view is mid-gesture; a
    // hover leave must not cut a slider drag short.
    readonly property bool interacting: (homeLoader.item ? homeLoader.item.interacting : false) || shelfDragActive
    // Home (player, calendar, camera tile) is built the first time the island
    // is approached, hovered, opened or summoned, and then kept: a closed
    // island that was never opened holds none of it, and the hover dwell
    // covers building it before the first open.
    readonly property bool homeWanted: pointerInside || expanded || explicitOpen
    property bool homeBuilt: homeWanted
    onHomeWantedChanged: if (homeWanted) homeBuilt = true
    // A capture source for Home's camera tile, for hosts and tests that must
    // not open the real camera; null uses the real one.
    property Component cameraSource: null
    signal collapseRequested
    // A wheel step on the collapsed pill, as a fraction of full output
    // volume. Panel.qml passes it to VolumeSource, whose sample then shows
    // the level readout; with `hud:false` nothing listens and the wheel is
    // inert.
    signal volumeStepRequested(real delta)
    // G7 (native-probe results.md) proved per-corner Rectangle radii render a
    // square top and a rounded bottom under the software renderer offscreen.
    // Recorded here as the plan's fallback switch: the filler-rectangle
    // technique is the documented alternative if a future Qt regresses this.
    readonly property bool perCornerRadii: true
    // A passing drag (a button held down while the pointer crosses the pill)
    // must not open the island. Extracted to a pure function because the
    // offscreen QTest synthetic mouse-move pipeline does not carry a pressed
    // button through a passively observed HoverHandler point, so this is what
    // tst-island-surface.qml exercises directly; the handler wiring below
    // still reads the real pointer state.
    function allowsHoverExpand(pressedButtons, position) {
        return settings.openOnHover && pressedButtons === Qt.NoButton && !(position && inHud(position.x, position.y));
    }
    // The active closed HUD's input rectangle, in this item's coordinates,
    // or null. Computed from the resting geometry, never the springing
    // notch, so the input region changes once per state and never per
    // frame. Only a readout with a bar to drag takes input.
    readonly property var hudHitRect: {
        if (!interactive || expanded || !hud.active || !hud.hasBar)
            return null;
        if (hudStyle === "below")
            return { x: Math.round((width - hudBelow.width) / 2), y: pillHeight + hudBelow.notchGap,
                width: hudBelow.width, height: hudBelow.height };
        if (closedStateModel.state !== "hudInline")
            return null;
        var body = closedStateModel.width - 2 * flareClosed;
        return { x: Math.round((width - body) / 2), y: 0, width: body, height: pillHeight };
    }
    // Whether a point in this item's coordinates falls on the active HUD.
    function inHud(x, y) {
        var r = hudHitRect;
        return !!r && x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height;
    }
    // True while the pointer rests on the active HUD. The closed body's tap
    // and pull handlers sit above the inline readout, and either would take
    // a press from its bar where the two overlap, so both stand aside here;
    // a pointer always reaches a point before it presses there.
    readonly property bool pointerOnHud: {
        if (!hover.hovered)
            return false;
        var p = hitShape.mapToItem(root, hover.point.position.x, hover.point.position.y);
        return inHud(p.x, p.y);
    }
    // Extracted for the same reason allowsHoverExpand() is: QtTest's DropArea
    // signal is strongly typed (QQuickDragEvent*), so a synthetic JS drop
    // object cannot be passed through the real `dropped` signal from a test.
    // The real `onDropped` handler below calls this directly, so
    // tst-island-surface.qml exercises the actual wiring rather than a
    // facade shortcut (code review L6).
    function handleDrop(dropEvent) {
        if (!settings.shelfEnabled || !dropInSupported || !coordinator
                || !(dropEvent.supportedActions & Qt.CopyAction)) {
            dropEvent.accepted = false;
            bodyDropHandoff = false;
            catchDropHandoff = false;
            return false;
        }
        var added = dropEvent.hasUrls ? coordinator.shelfAdd(dropEvent.urls.map(String))
            : dropEvent.hasText && typeof coordinator.shelfAddDrop === "function"
                ? coordinator.shelfAddDrop([], dropEvent.text) : 0;
        if (added <= 0) {
            dropEvent.accepted = false;
            bodyDropHandoff = false;
            catchDropHandoff = false;
            return false;
        }
        dropEvent.accept(Qt.CopyAction);
        bodyDropHandoff = false;
        catchDropHandoff = false;
        return true;
    }
    // While a HUD bar is held, an open waits for the release, so nothing
    // takes the bar from under the pointer mid-drag. A summon's auto-close
    // waits with it (ms, 0 none).
    property string pendingOpen: ""
    property int pendingAutoClose: 0
    // A drag entering the catch zone opens the Shelf tab. Extracted for the
    // same reason handleDrop() is; the zone's DropArea calls it directly.
    function handleCatchEnter(drag) {
        if (!root.settings.shelfEnabled || !root.dropInSupported || !(drag.hasUrls || drag.hasText)
                || !(drag.supportedActions & Qt.CopyAction)) {
            drag.accepted = false;
            return false;
        }
        catchHandoffWidth = catchWidth;
        catchDropHandoff = true;
        drag.accept(Qt.CopyAction);
        expandTo("shelf");
        return true;
    }
    // A drag leaving the catch zone without dropping (it passed through the
    // bar centre, or was cancelled) gives the island back to the leave
    // grace, as the body's drop area does: a drag sends no hover events, so
    // nothing else would ever close the island it opened.
    function handleCatchExit() {
        catchDropHandoff = false;
        if (expanded && !pointerInside)
            grace.restart();
    }
    function handleBodyEnter(drag) {
        if (!settings.shelfEnabled || !dropInSupported || !drag.hasUrls
                || !(drag.supportedActions & Qt.CopyAction)) {
            drag.accepted = false;
            return false;
        }
        bodyDropHandoff = true;
        drag.accept(Qt.CopyAction);
        expandTo("shelf");
        return true;
    }
    function expandTo(target) {
        if (!expanded && hudHeldHere) {
            pendingOpen = resolveView(target);
            return;
        }
        var closeAfter = pendingOpen !== "" ? pendingAutoClose : 0;
        pendingOpen = "";
        pendingAutoClose = 0;
        view = resolveView(target);
        expanded = true;
        if (closeAfter > 0)
            scheduleAutoClose(closeAfter);
    }
    // Every user and timer collapse path goes through here, and none closes
    // the island while a menu, picker or share action holds it busy. Only
    // Escape passes force; the host's resets use resetForHost(). Returns
    // whether it closed.
    // A held HUD bar (the open header's capsule) holds it open too.
    function collapse(force) {
        if (force !== true && (busyCount > 0 || hudHeldHere))
            return false;
        pendingOpen = "";
        pendingAutoClose = 0;
        autoClose.stop();
        expanded = false;
        var count = coordinator && Array.isArray(coordinator.shelfEntries) ? coordinator.shelfEntries.length
            : coordinator && Array.isArray(coordinator.shelfItems) ? coordinator.shelfItems.length : 0;
        if (settings.shelfEnabled && settings.openShelfByDefault && count > 0)
            view = "shelf";
        else if (!settings.rememberLastTab || subView)
            view = "home";
        collapseRequested();
        return true;
    }
    // The close guard. Each beginBusy() holds the island open until its
    // endBusy(), or at most busyTimeout ms, so a lost endBusy() can never
    // keep it open for good.
    property int busyTimeout: 2000
    property var busyDeadlines: []
    readonly property int busyCount: busyDeadlines.length
    function beginBusy() {
        busyDeadlines = busyDeadlines.concat([Date.now() + busyTimeout]).sort(function (a, b) { return a - b; });
        scheduleBusyExpiry();
    }
    // The host's safety resets: the lock screen or a panel disallow, leaving
    // island mode, a screen change and fullscreen. They bypass the close
    // guard and drop every hold, so the island never shows over a lock
    // screen or carries a menu's busy state into another mode or screen.
    function resetForHost() {
        bodyDropHandoff = false;
        catchDropHandoff = false;
        busyDeadlines = [];
        busyExpiry.stop();
        endHudHold();
        return collapse(true);
    }
    // Ends a hold one of this island's readouts took. Its release may never
    // come (the reset moved or hid the window under the pointer), so the
    // readout is dismissed: each bar then ends its drag and its view gives up
    // the hold, the same path a release takes. A hold owned elsewhere (an
    // island on another screen) is left to its owner.
    function endHudHold() {
        if (!hud.held)
            return;
        for (var owner = hud.heldBy; owner; owner = owner.parent) {
            if (owner === root) {
                hud.active = false;
                return;
            }
        }
    }
    function endBusy() {
        if (busyDeadlines.length)
            busyDeadlines = busyDeadlines.slice(1);
        scheduleBusyExpiry();
    }
    function scheduleBusyExpiry() {
        busyExpiry.stop();
        var now = Date.now();
        var live = busyDeadlines.filter(function (deadline) { return deadline > now; });
        if (live.length !== busyDeadlines.length)
            busyDeadlines = live;
        if (live.length) {
            busyExpiry.interval = Math.max(1, live[0] - now);
            busyExpiry.start();
        }
    }
    // A summon may ask to close again by itself after `ms`; any pointer or
    // key interaction cancels that. 0 never closes.
    function scheduleAutoClose(ms) {
        autoClose.stop();
        if (!expanded && pendingOpen !== "") {
            pendingAutoClose = ms > 0 ? ms : 0;
            return;
        }
        if (ms > 0 && expanded) {
            autoClose.interval = ms;
            autoClose.start();
        }
    }
    function cancelAutoClose() {
        autoClose.stop();
        pendingAutoClose = 0;
    }
    readonly property bool autoClosePending: autoClose.running
    // Steps into the loaded view: Return on the focused surface root lands
    // here. Focus goes to a control, not the bare view root: Qt Quick runs
    // Tab traversal from the first item in the key's path that takes Tab
    // focus, and the view roots do not, so Tab from a view root would
    // restart at the window's first control. The player view picks its own
    // control; the shelf takes its first. Keys still bubble from the control
    // up through the view to the root's Escape ladder (Home's overlay, then
    // Lyrics, then collapse). Lyrics focuses Try
    // again when it shows, or its own root.
    function focusContent() {
        if (view === "timers") {
            if (timersViewLoader.item)
                timersViewLoader.item.focusControls();
            else
                root.forceActiveFocus();
            return;
        }
        if (view === "lyrics") {
            if (lyricsViewLoader.item)
                lyricsViewLoader.item.focusControls();
            else
                root.forceActiveFocus();
            return;
        }
        if (view === "home") {
            // With nothing to focus (no source yet), the keys stay on the
            // root.
            var home = homeLoader.item;
            if (!home) {
                root.forceActiveFocus();
                return;
            }
            home.forceActiveFocus();
            if (!home.focusControls())
                root.forceActiveFocus();
            return;
        }
        var shelf = shelfViewLoader.item;
        if (!shelf) {
            root.forceActiveFocus();
            return;
        }
        if (!shelf.focusControls())
            root.forceActiveFocus();
    }
    // A keyboard summon focuses the surface root, where the shortcut keys and
    // the view switch live (see Keys.onPressed below).
    function focusKeys() {
        root.forceActiveFocus();
    }
    // A collapse gives back the focus the island held, on its root or on a
    // control inside a view. Kept, it would come back with the next opening:
    // a hover open would wear the root's focus ring, and focus left on a
    // control would take Tab from the view switch.
    function releaseKeys() {
        for (var node = Window.activeFocusItem; node; node = node.parent)
            if (node === root) {
                root.forceActiveFocus();
                break;
            }
        root.focus = false;
    }
    readonly property bool keysFocused: activeFocus && Window.activeFocusItem === root
    // The Qt constants IslandKeys.resolve() compares against.
    readonly property var keyCodes: ({
        space: Qt.Key_Space, left: Qt.Key_Left, right: Qt.Key_Right, up: Qt.Key_Up, down: Qt.Key_Down,
        n: Qt.Key_N, p: Qt.Key_P, tab: Qt.Key_Tab, backtab: Qt.Key_Backtab,
        returnKey: Qt.Key_Return, enter: Qt.Key_Enter,
        shift: Qt.ShiftModifier, blocked: Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier
    })
    // The selected source as the expanded controls see it: nothing while the
    // panel or the UI is not allowed, so no key or gesture can reach it.
    function playbackState() {
        var c = root.coordinator;
        var endpoint = c && c.panelAllowed === true && c.uiAllowed === true ? c.selectedEndpoint : null;
        return {
            capabilities: endpoint && endpoint.capabilities ? endpoint.capabilities : {},
            playing: !!endpoint && endpoint.status === "Playing",
            positionSeconds: c ? Number(c.positionSeconds) || 0 : 0,
            lengthSeconds: endpoint ? Number(endpoint.lengthSeconds) || 0 : 0,
            volume: endpoint ? Number(endpoint.volume) || 0 : 0,
            views: root.views,
            // A sub-view steps as its tab does.
            view: root.subView ? "home" : root.view
        };
    }
    // One command through a freshly captured intent. Nothing is sent while
    // another command is pending: the Service would only answer "busy".
    function dispatch(action, value) {
        var c = root.coordinator;
        if (!c || c.pendingAction)
            return false;
        var intent = c.captureIntent();
        if (!intent)
            return false;
        c.invoke(action, intent, value);
        return true;
    }
    function handleKey(event) {
        cancelAutoClose();
        if (event.key === Qt.Key_Escape) {
            // The battery popover closes first.
            if (root.batteryPopoverOpen) {
                root.batteryPopoverOpen = false;
                return true;
            }
            // Escape closes Home's settings or source overlay first, then
            // leaves a sub-view, then closes the island, busy or not.
            if (root.expanded && root.view === "home" && homeLoader.item && homeLoader.item.closeOverlay())
                return true;
            if (root.expanded && root.subView)
                root.view = "home";
            else
                collapse(true);
            return true;
        }
        if (!root.expanded)
            return false;
        var r = IslandKeys.resolve(event.key, event.modifiers, root.keysFocused, playbackState(), keyCodes);
        if (!r)
            return false;
        if (r.view)
            root.view = r.view;
        else if (r.enter)
            focusContent();
        // A held Space, N or P toggles or skips once, not at the key repeat
        // rate; held arrows keep stepping.
        else if (!(event.isAutoRepeat && r.value === undefined))
            dispatch(r.invoke, r.value);
        return true;
    }
    // Wheel on the collapsed pill. Whichever axis dominates an event counts.
    // Vertical: 2 % of output volume per 120 units (one mouse notch), with
    // touchpad fractions carried over. Horizontal: a swipe that adds up to
    // 240 units within one gesture skips once; the gesture ends after 300 ms
    // without a wheel event, and a new one may skip again. `inverted` is the
    // event's own flag for natural (content-follows-finger) scrolling: the
    // deltas are flipped back, so the same finger or wheel direction raises
    // the volume, and picks the same skip, whatever the touchpad setting, as
    // Qt's own sliders do. A separate function, like allowsHoverExpand(), so
    // tests can feed exact deltas.
    readonly property int wheelNotch: 120
    readonly property real volumeStep: 0.02
    readonly property int swipeThreshold: 240
    // Negative x skips forward. The one constant to flip if the live
    // touchpad direction feels inverted.
    readonly property int swipeSign: 1
    property real volumeAccum: 0
    property real swipeAccum: 0
    property bool swipeFired: false
    function handleWheel(dx, dy, inverted, modifiers) {
        if (!root.interactive)
            return;
        cancelAutoClose();
        // Shift turns the wheel into the pull gesture, on either axis: some
        // stacks deliver a Shift-wheel as horizontal.
        if (modifiers !== undefined && (modifiers & Qt.ShiftModifier)) {
            handlePullWheel(Math.abs(dy) >= Math.abs(dx) ? dy : dx, inverted);
            return;
        }
        if (root.expanded)
            return;
        if (inverted === true) {
            dx = -dx;
            dy = -dy;
        }
        // Scrolling on the pill is a volume or skip gesture, never a hover
        // that should open the card under it.
        dwell.stop();
        swipeEnd.restart();
        if (Math.abs(dy) >= Math.abs(dx)) {
            volumeAccum += dy;
            while (Math.abs(volumeAccum) >= wheelNotch) {
                var sign = volumeAccum > 0 ? 1 : -1;
                volumeAccum -= sign * wheelNotch;
                volumeStepRequested(sign * volumeStep);
            }
            return;
        }
        swipeAccum += dx;
        if (swipeFired || Math.abs(swipeAccum) < swipeThreshold)
            return;
        swipeFired = true;
        var action = swipeAccum * swipeSign < 0 ? "Next" : "Previous";
        if (IslandKeys.canInvoke(action, playbackState()) && dispatch(action))
            nudge(action === "Next" ? -1 : 1);
    }
    // A skip nudges the pill (or the peek) a few pixels the way the track
    // went, then springs it back: a finite acknowledgement, skipped under
    // reduced motion.
    property real swipeNudge: 0
    readonly property real nudgeDistance: 6
    function nudge(direction) {
        nudgeMotion.stop();
        swipeNudge = 0;
        if (!tokens || tokens.reducedMotion || tokens.feedbackDuration <= 0)
            return;
        nudgeOut.to = direction * nudgeDistance;
        nudgeMotion.start();
    }
    // Opens on the open spring and closes on the close spring, always from
    // the current value: a reversal mid-flight carries on from where the
    // notch is, with no jump. Reduced motion sets the value at once.
    function springTo(driver, current, target) {
        driver.stop();
        if (!tokens || tokens.reducedMotion)
            return target;
        if (current !== target) {
            if (target > current)
                driver.run(current, target, tokens.openResponse, tokens.openDamping, tokens.openDuration);
            else
                driver.run(current, target, tokens.closeResponse, tokens.closeDamping, tokens.closeDuration);
        }
        return current;
    }
    // The pull gesture, after boring.notch: while closed, a downward drag
    // (or a Shift-wheel) pulls the notch open; while open, an upward one
    // pushes it closed. `pullTravel` is the travel so far in px, positive
    // downward. Past a small dead zone, so a tap never moves the notch, the
    // progress is travel / gestureTravel * 20, the notch stretches to
    // pullScale(progress) about its top, and at gestureTravel it opens or
    // closes once, latched until the gesture ends.
    readonly property int gestureTravel: settings.gestureTravel
    readonly property bool gesturesAllowed: interactive && settings.enableGestures
        && (!expanded || settings.closeGesture)
    readonly property real pullDeadZone: 8
    // One wheel notch (120 units) pulls this far.
    readonly property real wheelPullStep: 40
    property real pullTravel: 0
    property bool pullLatched: false
    property bool pullActive: false
    property real gestureProgress: 0
    function pullProgress(travel, distance) {
        return travel / distance * 20;
    }
    function pullScale(progress) {
        return Math.max(0.6, 1 + progress * 0.01);
    }
    // Content dims while the open notch is pushed.
    function pullDim(progress) {
        return Math.min(Math.abs(progress) * 0.1, 0.3);
    }
    function updatePull(travel) {
        if (!gesturesAllowed || pullLatched)
            return;
        cancelAutoClose();
        pullActive = true;
        pullTravel = travel;
        dwell.stop();
        var along = expanded ? -travel : travel;
        if (along < pullDeadZone) {
            gestureProgress = 0;
            return;
        }
        gestureProgress = pullProgress(travel, gestureTravel);
        if (along >= gestureTravel) {
            pullLatched = true;
            gestureProgress = 0;
            if (expanded)
                collapse();
            else
                expandTo(view);
        }
    }
    function endPull() {
        pullEnd.stop();
        pullActive = false;
        pullLatched = false;
        pullTravel = 0;
        gestureProgress = 0;
    }
    // A Shift-wheel step: down pulls, up pushes. The gesture ends 300 ms
    // after the last step, as the wheel has no release.
    function handlePullWheel(delta, inverted) {
        if (!gesturesAllowed)
            return;
        if (inverted === true)
            delta = -delta;
        updatePull(pullTravel - delta / wheelNotch * wheelPullStep);
        pullEnd.restart();
    }
    function settleOrAnimate() {
        expansion = springTo(morph, expansion, expanded ? 1 : 0);
    }
    property real expansion: 0
    // Whether the host's window is shown. The host may hide it while the
    // island stays expanded (autoShow off, for one), and a hidden window
    // leaves its items' own visible flags untouched.
    property bool hostVisible: true
    // With an island on every screen: whether this one draws the live
    // spectrum (only the one under the pointer does), and whether it may run
    // the camera (only the one opened last may).
    property bool liveSpectrum: true
    property bool cameraAllowed: true
    // Open, shown and at rest: the open spring has finished. The camera waits
    // for this, so opening its device never stalls the spring, and it stops
    // when the host hides the window.
    readonly property bool openSettled: hostVisible && expanded && !morph.running && clampedExpansion >= 1
    // The header's camera toggle hides the mirror until the shell reloads.
    property bool mirrorHidden: false
    readonly property real restHeight: tokens ? tokens.openHeight : 190
    readonly property real openWidth: Math.min(tokens ? tokens.openWidth : 640, availableWidth)
    // The closed notch's state, width and wings: idle, live music, the
    // inline HUD, a battery event or a peek (ClosedModel). The width springs
    // between states; the flares overhang the bar spacer, which reserves the
    // live width.
    property bool batteryActive: false
    property real batteryLevel: 0
    property string batteryLabel: ""
    // The banner's kind ("plugged", "unplugged", "low", "critical").
    property string batteryKind: ""
    // The idle face's mood for faceMoodDuration after a banner ends: happy
    // after a plug-in, worried after a low or critical warning.
    property string faceMood: ""
    onBatteryActiveChanged: {
        if (batteryActive)
            return;
        var mood = batteryKind === "plugged" ? "happy" : batteryKind === "low" || batteryKind === "critical" ? "worried" : "";
        faceMood = mood;
        if (mood !== "")
            faceMoodTimer.restart();
    }
    Timer {
        id: faceMoodTimer
        interval: root.tokens ? root.tokens.faceMoodDuration : 3000
        onTriggered: root.faceMood = ""
    }
    // The closed notch's activities (ActivityModel): what fills the notch
    // and what shrinks to its trailing glyph. Its minute labels step only
    // while the island's window is on screen.
    readonly property var activities: activityModel
    ActivityModel {
        id: activityModel
        musicLive: closedStateModel.live
        sleepTimer: root.coordinator && root.coordinator.sleepDeadline > 0
            ? ({ endsAt: root.coordinator.sleepDeadline }) : null
        recording: root.coordinator && root.coordinator.recordingShown === true
            ? ({ startedAt: root.coordinator.recordingState.startedAt, path: root.coordinator.recordingState.path }) : null
        timer: root.coordinator && Array.isArray(root.coordinator.timerList)
            ? Timers.soonest(root.coordinator.timerList, now) : null
        ticking: !!root.Window.window && root.Window.window.visible === true
    }
    Component {
        id: activityChipsComponent
        ActivityChips {
            tokens: root.ink
            privacy: root.privacy
            activities: activityModel
            onStopRecordingRequested: {
                root.cancelAutoClose();
                if (root.coordinator)
                    root.coordinator.stopRecording();
            }
            onTimersRequested: {
                root.cancelAutoClose();
                root.view = "timers";
            }
        }
    }
    readonly property var closedModel: closedStateModel
    ClosedModel {
        id: closedStateModel
        tokens: root.tokens
        playback: {
            var endpoint = root.coordinator ? root.coordinator.selectedEndpoint : null;
            return { identity: endpoint ? JSON.stringify([endpoint.token, endpoint.trackToken]) : "",
                hasTrack: !!endpoint, playing: !!endpoint && endpoint.status === "Playing" };
        }
        liveActivity: root.settings.musicLiveActivity
        pauseGrace: root.settings.pauseGrace
        hudActive: root.hudActive
        hudStyle: root.hudStyle
        batteryActive: root.batteryActive
        peekActive: root.peekShowing
        activity: activityModel.primary === "music" ? "" : activityModel.primary
        minimalActivity: activityModel.minimal
        idleStyle: root.settings.idleStyle
        hardwareNotch: root.settings.hardwareNotch === true
        availableWidth: root.availableWidth
    }
    readonly property real closedTarget: closedStateModel.restWidth
    property real closedWidth: 0
    // Where the current width move started, for the content's readiness.
    onClosedTargetChanged: {
        closedFrom = closedWidth;
        closedMorph.moveTo(closedTarget, tokens ? tokens.openResponse : 0.42,
            tokens ? tokens.openDamping : 0.8, !tokens || tokens.reducedMotion);
    }
    SpringDriver {
        id: closedMorph
        // Set once: a binding here would jump with the state before the
        // spring could move.
        Component.onCompleted: settle(root.closedTarget)
        onStepped: value => root.closedWidth = value
    }
    // What the wings show lags the model, after the Dynamic Island's compact
    // choreography: the shape moves first. A change fades the old content out
    // (closedFadeOut ms) while the width already springs, so the content
    // leaves as the notch shrinks rather than a frame before it; the new
    // content then fades in (closedFadeIn ms) and, while the width is still
    // moving, shows only over the last 30 % of the move, once there is room.
    // Content that draws nothing in the wings (idle, the inline HUD) swaps at
    // once. Finite tweens only; reduced motion swaps at once.
    readonly property string modelLeft: closedStateModel.state === "peek"
        ? closedStateModel.contentOf(closedStateModel.restState).left : closedStateModel.leftContent
    readonly property string modelRight: closedStateModel.state === "peek"
        ? closedStateModel.contentOf(closedStateModel.restState).right : closedStateModel.rightContent
    readonly property string modelCentre: closedStateModel.state === "peek"
        ? closedStateModel.contentOf(closedStateModel.restState).centre : closedStateModel.centreContent
    readonly property string modelMinimal: closedStateModel.minimalOf(closedStateModel.restState)
    // Set once at start, then only by swapClosedContent: never bound.
    property string shownLeft: "none"
    property string shownRight: "none"
    property string shownCentre: "none"
    property string shownMinimal: "none"
    property real closedFrom: 0
    property real contentFade: 1
    readonly property real closedReady: {
        var span = closedTarget - closedFrom;
        if (Math.abs(span) < 0.5)
            return 1;
        var progress = (closedWidth - closedFrom) / span;
        return Math.max(0, Math.min(1, (progress - 0.7) / 0.3));
    }
    // The resting width for the model's current state, read from the state
    // itself: a change handler may run before closedTarget's binding does.
    function restingWidth() {
        var model = closedStateModel;
        return model.widthOf(model.restState);
    }
    function drawsNothing(left, right, centre) {
        var blank = ["none", "hudIcon", "hudLevel"];
        return blank.indexOf(left) >= 0 && blank.indexOf(right) >= 0 && blank.indexOf(centre) >= 0;
    }
    function updateClosedContent() {
        if (modelLeft === shownLeft && modelRight === shownRight && modelCentre === shownCentre
            && modelMinimal === shownMinimal) {
            if (contentOut.running) {
                contentOut.stop();
                contentIn.restart();
            }
            return;
        }
        if (!tokens || tokens.reducedMotion || drawsNothing(shownLeft, shownRight, shownCentre) || contentFade <= 0
            || drawsNothing(modelLeft, modelRight, modelCentre) && restingWidth() >= closedWidth) {
            swapClosedContent();
            return;
        }
        contentIn.stop();
        if (!contentOut.running)
            contentOut.restart();
    }
    function swapClosedContent() {
        contentOut.stop();
        shownLeft = modelLeft;
        shownRight = modelRight;
        shownCentre = modelCentre;
        shownMinimal = modelMinimal;
        if (!tokens || tokens.reducedMotion) {
            contentIn.stop();
            contentFade = 1;
        } else {
            contentFade = 0;
            contentIn.restart();
        }
    }
    onModelLeftChanged: updateClosedContent()
    onModelRightChanged: updateClosedContent()
    onModelCentreChanged: updateClosedContent()
    onModelMinimalChanged: updateClosedContent()
    NumberAnimation {
        id: contentOut
        target: root
        property: "contentFade"
        to: 0
        duration: root.tokens ? root.tokens.closedFadeOut : 90
        easing.type: Easing.InCubic
        onFinished: root.swapClosedContent()
    }
    NumberAnimation {
        id: contentIn
        target: root
        property: "contentFade"
        to: 1
        duration: root.tokens ? root.tokens.closedFadeIn : 130
        easing.type: Easing.OutCubic
    }
    // The closed input region: the body at rest, jumping with the state and
    // never wider than the live notch the bar spacer reserves, so a wider
    // transient state draws over the bar without taking its clicks.
    // A notch narrower than the base notch (the Horizon idle style) keeps
    // the base notch's region, over the bar centre the spacer reserves, so
    // it stays as easy to hover.
    readonly property real closedHitWidth: Math.min(Math.max(closedTarget, tokens ? tokens.idleWidth : 185),
        Math.min(tokens ? tokens.liveWidth : 280, availableWidth))
    readonly property real flareClosed: tokens ? tokens.flareClosed : 6
    readonly property real flareOpen: tokens ? tokens.flareOpen : 19
    // Clamped to 0..1 for everything but the notch's own height, so the open
    // spring's overshoot never clips width, flare, radius or content opacity.
    readonly property real clampedExpansion: Math.max(0, Math.min(1, expansion))
    onExpandedChanged: {
        settleOrAnimate();
        if (!expanded) {
            batteryPopoverOpen = false;
            header.overflowMenu.close();
            releaseKeys();
        }
    }
    Component.onCompleted: {
        expansion = expanded ? 1 : 0;
        peekAmount = peekShowing ? 1 : 0;
        shownLeft = modelLeft;
        shownRight = modelRight;
        shownCentre = modelCentre;
    }
    // The peek bloom. A peek never outlives an expansion, whoever owns the
    // model: the expanded card already shows everything the peek would.
    readonly property bool peekShowing: peekActive && !expanded
    property real peekAmount: 0
    // Clamped like clampedExpansion: only the card height takes the raw
    // overshoot, into the slack below.
    readonly property real peekClamped: Math.max(0, Math.min(1, peekAmount))
    onPeekShowingChanged: settlePeek()
    function settlePeek() {
        peekAmount = springTo(peekMorph, peekAmount, peekShowing ? 1 : 0);
    }
    // The shape the peek blooms into: the tall track card, or a closed-high
    // row for power. A power peek that replaces a showing track peek eases
    // between the two instead of snapping; a fresh peek starts from the pill,
    // so nothing eases while the peek is fully gone.
    readonly property bool inlineTrackPeek: peekKind === "track" && settings.peekStyle === "inline"
    readonly property real peekTargetHeight: peekKind === "track" && !inlineTrackPeek && tokens ? tokens.peekHeight : pillHeight
    readonly property real peekTargetRadius: peekKind === "track" && !inlineTrackPeek && tokens ? tokens.peekRadius : bottomRadiusClosed
    readonly property real bottomRadiusClosed: tokens ? tokens.bottomRadiusClosed : 14
    property real peekShapeHeight: peekTargetHeight
    property real peekShapeRadius: peekTargetRadius
    Behavior on peekShapeHeight {
        enabled: root.peekAmount > 0 && !!root.tokens && !root.tokens.reducedMotion
        NumberAnimation { duration: root.tokens ? root.tokens.peekInDuration : 280; easing.type: Easing.OutCubic }
    }
    Behavior on peekShapeRadius {
        enabled: root.peekAmount > 0 && !!root.tokens && !root.tokens.reducedMotion
        NumberAnimation { duration: root.tokens ? root.tokens.peekInDuration : 280; easing.type: Easing.OutCubic }
    }
    // The resting closed shape: the closed notch, or the notch part-way into
    // its peek. The expansion morph starts from here, so expanding mid-peek
    // grows on from the peek instead of jumping back to the closed notch.
    // Widths include the flares.
    readonly property real peekWidth: Math.min(tokens ? (inlineTrackPeek ? tokens.hudInlineWidth : tokens.peekWidth) : 300, availableWidth)
    readonly property real baseWidth: closedWidth + (peekWidth - closedWidth) * peekClamped
    readonly property real baseHeight: pillHeight + (peekShapeHeight - pillHeight) * peekAmount
    readonly property real baseRadius: bottomRadiusClosed + (peekShapeRadius - bottomRadiusClosed) * peekClamped
    // The pill's own fade as the card expands, shared by the peek.
    readonly property real fadeHandover: tokens ? tokens.pillFadeEnd : 0.4
    readonly property real collapsedFade: 1 - Math.min(1, clampedExpansion / fadeHandover)
    // A slider gesture ending while the pointer has already left must restart
    // the leave grace instead of leaving the card open forever.
    onInteractingChanged: if (expanded && !interacting && !pointerInside && !drop.containsDrag)
        grace.restart()
    // A busy guard that ends after the pointer left restarts the grace, so
    // the island does not stay open for good.
    onBusyCountChanged: if (busyCount === 0 && expanded && !pointerInside && !drop.containsDrag)
        grace.restart()
    // The header gear opens the settings window in one click; the legacy
    // panel keeps the inline settings view. Returns whether it opened.
    // The header gear opened (or raised) the settings window: the host
    // lends it the keyboard, even when the window was already open.
    signal settingsOpened()
    function openSettings() {
        cancelAutoClose();
        var opened = !!coordinator && typeof coordinator.openSettings === "function"
            && coordinator.openSettings("") === true;
        if (opened)
            settingsOpened();
        return opened;
    }
    // Keys reach the root when it holds focus (a keyboard summon) or when the
    // focused control inside a view did not accept them: a QML key event
    // bubbles from the focused item upward and stops at the first handler
    // that accepts it. So a focused button keeps Space, a focused slider
    // keeps its arrows, and the source list keeps Tab. Escape here closes
    // Home's overlay, then Lyrics, then the island.
    Keys.onPressed: event => {
        event.accepted = root.handleKey(event);
    }
    // A key that a control inside a view took still moved the focus there,
    // which is an interaction too. The summon's own focus on the root is not.
    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true
        function onActiveFocusItemChanged() {
            if (root.expanded && root.Window.activeFocusItem !== root)
                root.cancelAutoClose();
        }
    }
    SpringDriver {
        id: morph
        onStepped: value => root.expansion = value
    }
    SpringDriver {
        id: peekMorph
        onStepped: value => root.peekAmount = value
    }
    Timer {
        id: swipeEnd
        interval: 300
        repeat: false
        onTriggered: {
            root.swipeAccum = 0;
            root.volumeAccum = 0;
            root.swipeFired = false;
        }
    }
    SequentialAnimation {
        id: nudgeMotion
        NumberAnimation {
            id: nudgeOut
            target: root
            property: "swipeNudge"
            duration: root.tokens ? root.tokens.feedbackDuration : 100
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "swipeNudge"
            to: 0
            duration: root.tokens ? root.tokens.feedbackDuration * 3 : 300
            easing.type: Easing.OutBack
            easing.overshoot: 2
        }
    }
    Timer {
        id: dwell
        interval: root.hoverDwell
        repeat: false
        onTriggered: if (root.pointerInside && root.settings.openOnHover)
            root.expandTo(root.view)
    }
    Timer {
        id: pullEnd
        interval: 300
        repeat: false
        onTriggered: root.endPull()
    }
    Timer {
        id: autoClose
        repeat: false
        onTriggered: root.collapse()
    }
    Timer {
        id: busyExpiry
        repeat: false
        onTriggered: root.scheduleBusyExpiry()
    }
    // A released pull springs back rather than snapping.
    Behavior on gestureProgress {
        enabled: !root.pullActive && !!root.tokens && root.tokens.feedbackDuration > 0
        NumberAnimation { duration: root.tokens ? root.tokens.feedbackDuration * 3 : 300; easing.type: Easing.OutCubic }
    }
    Timer {
        id: grace
        interval: root.leaveGrace
        repeat: false
        onTriggered: if (root.expanded && !(root.pointerInside || drop.containsDrag || root.explicitOpen || root.interacting))
            root.collapse()
    }
    readonly property bool gpuEffects: !!tokens && tokens.gpuEffects === true
    // Everything drawn over the notch takes its colours from `ink`: the
    // host's tokens re-based on the always-black notch. Text is always the
    // neutral notch ink, whatever the theme's text colour, so every view on
    // the notch shares one white. A theme accent or error that already reads
    // on black is kept; one that does not falls back to the dark-surface
    // default. Sizes, radius and the artwork tint carry over; the tint then
    // reaches only graphics (neutralChrome). The legacy panel keeps the
    // host's own tokens.
    // The island's sans faces, most preferred first. None is a dependency:
    // the first one installed wins, and sans-serif stands in for all.
    readonly property var uiFontFamilies: ["Inter", "Roboto", "Noto Sans"]
    readonly property var installedFonts: Qt.fontFamilies()
    function preferredSans(installed) {
        for (var i = 0; i < uiFontFamilies.length; ++i)
            if (installed.indexOf(uiFontFamilies[i]) >= 0)
                return uiFontFamilies[i];
        return "sans-serif";
    }
    readonly property var inkTheme: {
        var theme = tokens && tokens.theme ? tokens.theme : {};
        var ink = {};
        for (var key in theme)
            ink[key] = theme[key];
        ink.surface = tokens ? tokens.notchColor : "#000000";
        // A proportional face reads as an interface rather than a terminal:
        // the first installed of uiFontFamilies, or fontconfig's sans-serif.
        if (root.settings.uiFont !== "theme")
            ink.fontFamily = root.preferredSans(root.installedFonts);
        if (!tokens)
            return ink;
        if (tokens.customAccent !== "") {
            ink.accent = tokens.accent;
            ink.onAccent = tokens.accentLabel;
        }
        var black = { r: 0, g: 0, b: 0 };
        ink.text = String(tokens.notchInk);
        delete ink.stroke;
        if (Tint.contrast(tokens.rgb(tokens.accent), black) < Tint.GRAPHIC_CONTRAST) {
            delete ink.accent;
            delete ink.onAccent;
        }
        if (Tint.contrast(tokens.rgb(tokens.error), black) < Tint.TEXT_CONTRAST)
            delete ink.error;
        return ink;
    }
    readonly property alias ink: inkTokens
    DesignTokens {
        id: inkTokens
        theme: root.inkTheme
        light: false
        highContrast: !!root.tokens && root.tokens.highContrast
        reducedMotion: !root.tokens || root.tokens.reducedMotion
        tintEnabled: !root.tokens || root.tokens.tintEnabled
        artColor: root.tokens ? root.tokens.artColor : "transparent"
        neutralChrome: true
        gpuEffects: root.gpuEffects
    }
    // The notch: its outline, the shadow under it, and the body that holds
    // the content. Centred in the window and flush with its top edge.
    Item {
        id: card
        objectName: "islandCard"
        // Whole pixels, so an odd width (the 185 px idle notch) keeps sharp
        // edges.
        x: Math.round((root.width - width) / 2)
        y: 0
        width: root.baseWidth + (root.openWidth - root.baseWidth) * root.clampedExpansion
        // Height alone uses the raw (unclamped) expansion and peek amounts,
        // so either overshoot goes only downward, into the slack below
        // restHeight.
        height: root.baseHeight + (root.restHeight - root.baseHeight) * root.expansion
        // A pull stretches the notch about its top.
        transform: Scale {
            objectName: "pullScale"
            origin.y: 0
            yScale: root.pullScale(root.gestureProgress)
        }
        readonly property real flare: root.flareClosed + (root.flareOpen - root.flareClosed) * root.clampedExpansion
        readonly property real bottomRadius: root.baseRadius + ((root.tokens ? root.tokens.bottomRadiusOpen : 24) - root.baseRadius) * root.clampedExpansion
        // The shadow shows only while the notch is open or peeking.
        Loader {
            objectName: "notchShadowLoader"
            x: shape.bodyLeft
            width: shape.bodyWidth
            height: parent.height
            active: root.gpuEffects
            visible: root.settings.windowShadow !== false && (root.clampedExpansion > 0 || root.peekClamped > 0)
            sourceComponent: RectangularShadow {
                objectName: "notchShadow"
                color: root.tokens.shadowColor
                blur: root.tokens.shadowBlur
                spread: 0
                offset: Qt.vector2d(0, root.tokens.shadowOffset)
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: shape.radius
                bottomRightRadius: shape.radius
            }
        }
        NotchShape {
            id: shape
            objectName: "notchShape"
            anchors.fill: parent
            flare: card.flare
            bottomRadius: card.bottomRadius
            fillColor: root.tokens ? root.tokens.notchColor : "#000000"
            // The hairline edge is the software fallback for the shadow.
            edgeColor: root.gpuEffects || !root.tokens ? "transparent" : root.ink.stroke
            edgeWidth: root.tokens && root.tokens.highContrast ? root.tokens.focusWidth : 1
        }
        // The shape's body as a mask texture, for the GPU clip below. Only
        // while the notch is open, moving or peeking: the settled closed
        // notch takes the rectangle clip instead, so its live content (the
        // spectrum, the hairline) never re-renders through an offscreen
        // layer.
        Loader {
            id: bodyMask
            active: root.gpuEffects && (root.clampedExpansion > 0 || root.peekClamped > 0)
            sourceComponent: ShaderEffectSource {
                width: shape.bodyWidth
                height: shape.height
                sourceItem: shape
                sourceRect: Qt.rect(shape.bodyLeft, 0, shape.bodyWidth, shape.height)
                hideSource: false
                visible: false
            }
        }
        // The content box: the body between the flares. With GPU effects the
        // open, moving or peeking content is masked by the shape itself;
        // otherwise, and on the settled closed notch, a per-corner rectangle
        // clip stands in, and the flares stay free of content.
        Rectangle {
            id: body
            objectName: "notchBody"
            x: shape.bodyLeft
            y: 0
            width: shape.bodyWidth
            height: parent.height
            color: "transparent"
            clip: !layer.enabled
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: shape.radius
            bottomRightRadius: shape.radius
            layer.enabled: root.gpuEffects && !!bodyMask.item
            layer.effect: MultiEffect {
                maskEnabled: true
                // Auto padding would grow the layer and offset the mask.
                autoPaddingEnabled: false
                maskSource: bodyMask.item
            }
            ClosedNotch {
                id: pill
                objectName: "islandPill"
                liveSpectrum: root.liveSpectrum
                // Closed-high, so its wings hold still while the notch grows
                // under them.
                width: parent.width
                height: Math.min(parent.height, root.pillHeight)
                // Hands over to the peek at the same point it hands over to the
                // expanded card: gone by pillFadeEnd, where the peek content
                // starts, so the two rows never show through each other.
                opacity: (1 - Math.min(1, root.peekClamped / root.fadeHandover)) * root.collapsedFade
                    * root.contentFade * root.closedReady
                visible: opacity > 0
                tokens: root.ink
                coordinator: root.coordinator
                leftContent: root.shownLeft
                rightContent: root.shownRight
                centreContent: root.shownCentre
                minimalContent: root.shownMinimal
                activities: activityModel
                privacy: root.privacy
                clockSetting: root.settings.idleClock
                barHasClock: root.barHasClock
                // The next event only with the calendar and its idle opt-in on.
                calendarItems: root.settings.showCalendar === true && root.settings.idleNextEvent === true
                    && root.coordinator && root.coordinator.calendarSource
                    && Array.isArray(root.coordinator.calendarSource.items) ? root.coordinator.calendarSource.items : []
                calendarOptions: root.settings
                eventTitles: root.settings.idleEventTitles === true
                idleHairline: root.settings.idleHairline !== false
                batteryReading: root.batteryReading
                faceMood: root.faceMood
                batteryPercent: root.settings.showBatteryPercent !== false
                batteryStatusIcons: root.settings.showPowerStatusIcons !== false
                hardwareNotch: root.settings.hardwareNotch === true
                centreWidth: (root.tokens ? root.tokens.idleWidth : 185) - 2 * root.flareClosed
                coloredSpectrum: root.settings.coloredSpectrogram
                batteryLevel: root.batteryLevel
                batteryLabel: root.batteryLabel
                transform: Translate { x: root.swipeNudge }
            }
            // The inline readout across the widened closed notch: its icon
            // and label in the left wing, its bar in the right.
            HudInline {
                id: hudInline
                objectName: "hudInline"
                width: parent.width
                height: Math.min(parent.height, root.pillHeight)
                visible: active && closedStateModel.state === "hudInline"
                opacity: root.collapsedFade
                tokens: root.ink
                model: root.hud
                // Over a camera cutout the readout keeps clear of the notch's
                // centre; without one it sits as one centred row.
                centerGap: root.settings.hardwareNotch === true
                    ? (root.tokens ? root.tokens.idleWidth : 185) - 2 * root.flareClosed
                    : (root.tokens ? root.tokens.medium : 12)
                showPercent: root.settings.hudPercentClosed === true
                accent: root.settings.hudAccent === true
                gradientEnabled: root.settings.hudGradient === true
                glowEnabled: root.settings.hudGlow === true
                onSetLevel: (kind, value) => root.hudLevelRequested(kind, value)
            }
            Item {
                id: expandedColumn
                objectName: "expandedColumn"
                anchors.fill: parent
                readonly property real fadeStart: root.tokens ? root.tokens.contentFadeStart : 0.35
                readonly property real scaleFrom: root.tokens ? root.tokens.openScaleFrom : 0.8
                readonly property real entrance: Math.max(0, (root.clampedExpansion - fadeStart) / (1 - fadeStart))
                opacity: entrance * (1 - (root.expanded ? root.pullDim(root.gestureProgress) : 0))
                visible: root.clampedExpansion > 0
                scale: scaleFrom + (1 - scaleFrom) * root.clampedExpansion
                transformOrigin: Item.Top
                // With GPU effects the content also sharpens as it fades in. The
                // layer exists only while the blur shows, so a settled notch
                // renders its content directly.
                readonly property real entranceBlur: 1 - entrance
                layer.enabled: root.gpuEffects && visible && entranceBlur > 0
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: root.tokens.entranceBlur
                    blur: expandedColumn.entranceBlur
                }
                NotchHeader {
                    id: header
                    objectName: "notchHeader"
                    // Clear of the notch's top edge, which meets the screen
                    // edge: a capsule flush against it reads as cut off.
                    y: root.tokens ? root.tokens.small : 4
                    x: root.tokens ? root.tokens.medium : 12
                    width: parent.width - (root.tokens ? root.tokens.medium * 2 : 24)
                    height: root.tokens ? root.tokens.bandSwitcher - root.tokens.small : 32
                    tokens: root.ink
                    views: root.views
                    view: root.view
                    shelfCount: root.coordinator && Array.isArray(root.coordinator.shelfEntries) ? root.coordinator.shelfEntries.length
                        : root.coordinator && root.coordinator.shelfItems ? root.coordinator.shelfItems.length : 0
                    alwaysShowTabs: root.settings.alwaysShowTabs
                    settingsVisible: root.settings.showSettingsIcon !== false
                    // The closed notch's body, less the header's own inset.
                    centreWidth: Math.min(root.tokens ? root.tokens.liveWidth : 280, root.availableWidth) - 2 * root.flareClosed
                    centreComponent: root.settings.hardwareNotch === true ? null : activityChipsComponent
                    onTabRequested: name => {
                        root.cancelAutoClose();
                        root.view = name;
                    }
                    onBackRequested: {
                        root.cancelAutoClose();
                        root.view = "home";
                    }
                    onSettingsRequested: root.openSettings()
                    timersVisible: root.timersAvailable
                    timerName: activityModel.timerLabel
                    timerRemaining: activityModel.timerRemaining
                    recordingStopVisible: root.settings.hardwareNotch === true && !!activityModel.recording
                    onStopRecordingRequested: {
                        root.cancelAutoClose();
                        if (root.coordinator)
                            root.coordinator.stopRecording();
                    }
                    onTimersRequested: {
                        root.cancelAutoClose();
                        root.view = root.view === "timers" ? "home" : "timers";
                    }
                    cameraVisible: root.settings.showMirror === true
                    cameraOn: !root.mirrorHidden
                    onCameraToggled: {
                        root.cancelAutoClose();
                        root.mirrorHidden = !root.mirrorHidden;
                    }
                    batteryVisible: root.settings.showBatteryIndicator !== false && root.batteryReading.present === true
                    batteryReading: root.batteryReading
                    batteryPercent: root.settings.showBatteryPercent !== false
                    batteryStatusIcons: root.settings.showPowerStatusIcons !== false
                    onBatteryRequested: {
                        root.cancelAutoClose();
                        root.batteryPopoverOpen = !root.batteryPopoverOpen;
                    }
                    hudModel: root.hud
                    hudVisible: root.expanded && root.settings.showOpenNotchHud !== false && root.hud.active
                    hudPercent: root.settings.hudPercentOpen !== false
                    hudAccent: root.settings.hudAccent === true
                    hudGradient: root.settings.hudGradient === true
                    hudGlow: root.settings.hudGlow === true
                    onHudLevelRequested: (kind, value) => root.hudLevelRequested(kind, value)
                    // Push the open notch up by its header, the one band with
                    // no sliders or lists a vertical drag belongs to, to close
                    // it. On the header itself, so a tap still reaches the
                    // tabs until the drag passes its threshold.
                    DragHandler {
                        objectName: "pushCloseDrag"
                        target: null
                        enabled: root.gesturesAllowed && root.expanded
                        xAxis.enabled: false
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen | PointerDevice.TouchPad | PointerDevice.Stylus
                        onActiveTranslationChanged: if (active) root.updatePull(activeTranslation.y)
                        onActiveChanged: if (!active) root.endPull()
                    }
                }
                // While the summoned root holds focus, the tabs wear the
                // focus ring: Tab switches them, and Return steps into the
                // view shown.
                Rectangle {
                    objectName: "keyFocusRing"
                    x: header.x - (root.tokens ? root.tokens.focusWidth : 2)
                    y: header.y
                    width: header.sideWidth + 2 * (root.tokens ? root.tokens.focusWidth : 2)
                    height: header.height
                    radius: height / 2
                    color: "transparent"
                    border.width: root.tokens ? root.tokens.focusWidth : 2
                    border.color: root.ink.accent
                    visible: root.keysFocused && root.expanded
                }
                // The battery popover, under the header gauge, over Home.
                Loader {
                    id: batteryPopoverLoader
                    objectName: "batteryPopoverLoader"
                    z: 2
                    active: root.expanded && root.batteryPopoverOpen
                    x: header.x + header.width - width
                    y: header.y + header.height + (root.tokens ? root.tokens.small : 4)
                    sourceComponent: BatteryPopover {
                        objectName: "batteryPopover"
                        tokens: root.ink
                        reading: root.batteryReading
                        powerAvailable: root.batteryPowerAvailable
                        maximumHeight: Math.max(0, root.restHeight - batteryPopoverLoader.y)
                        onPowerSettingsRequested: root.batteryPowerRequested()
                    }
                }
                Loader {
                    id: homeLoader
                    objectName: "homeViewLoader"
                    x: root.tokens ? root.tokens.medium : 12
                    y: root.tokens ? root.tokens.bandSwitcher : 36
                    width: parent.width - 2 * x
                    // The open body under the header, less a bottom inset.
                    height: root.restHeight - y - (root.tokens ? root.tokens.medium : 12)
                    visible: root.view === "home"
                    active: root.homeBuilt
                    sourceComponent: HomeView {
                        objectName: "homeView"
                        tokens: root.ink
                        coordinator: root.coordinator
                        settings: root.settings
                        lyricsSource: root.lyricsSource
                        appIcon: root.appIcon
                        cameraSource: root.cameraSource
                        islandOpen: root.openSettled && root.cameraAllowed
                        onHome: root.view === "home"
                        mirrorHidden: root.mirrorHidden
                        cameraCoveredByOverlay: root.batteryPopoverOpen
                        onLyricsRequested: {
                            root.cancelAutoClose();
                            root.view = "lyrics";
                        }
                    }
                }
                Loader {
                    id: shelfViewLoader
                    objectName: "shelfViewLoader"
                    y: root.tokens ? root.tokens.bandSwitcher : 36
                    x: root.tokens ? root.tokens.medium : 12
                    width: parent.width - 2 * x
                    // The open body under the header: room for the 105 px
                    // strip and the refusal notice under it.
                    height: root.restHeight - y
                    active: root.settings.shelfEnabled && root.expanded && root.view === "shelf"
                    sourceComponent: ShelfView {
                        objectName: "shelfView"
                        tokens: root.ink
                        coordinator: root.coordinator
                        actions: root.coordinator ? root.coordinator.shelfActions : null
                        busyGuard: root
                        menuBounds: hitShape
                        hostOverlayOpen: root.batteryPopoverOpen
                        onCollapseRequested: root.collapse(true)
                    }
                }
                Loader {
                    id: lyricsViewLoader
                    objectName: "lyricsViewLoader"
                    y: root.tokens ? root.tokens.bandSwitcher : 36
                    width: parent.width
                    // The open body under the switcher, at rest: the view
                    // lays out once, not on every morph frame.
                    height: root.restHeight - y
                    active: root.expanded && root.view === "lyrics"
                    sourceComponent: IslandLyrics {
                        tokens: root.ink
                        coordinator: root.coordinator
                        source: root.lyricsSource
                    }
                }
                Loader {
                    id: timersViewLoader
                    objectName: "timersViewLoader"
                    y: root.tokens ? root.tokens.bandSwitcher : 36
                    width: parent.width
                    height: root.restHeight - y
                    active: root.expanded && root.view === "timers"
                    sourceComponent: TimersView {
                        tokens: root.ink
                        coordinator: root.coordinator
                        presets: root.settings.timerPresets
                        now: activityModel.now
                    }
                }
            }
            // Declared after the expanded column, so tests that look up the
            // hero art and glow by name find those first.
            IslandPeek {
                id: peek
                objectName: "islandPeek"
                liveSpectrum: root.liveSpectrum
                // At the peek's final body size and centred, so the notch reveals
                // it as it grows rather than squeezing it.
                x: Math.round((parent.width - width) / 2)
                y: 0
                width: root.peekWidth - 2 * root.flareClosed
                height: root.peekShapeHeight
                tokens: root.ink
                coordinator: root.coordinator
                kind: root.peekKind
                event: root.peekEvent
                inlineTrack: root.inlineTrackPeek
                powerKind: root.powerKind
                powerLevel: root.powerLevel
                showing: visible
                opacity: Math.max(0, (root.peekClamped - root.fadeHandover) / (1 - root.fadeHandover)) * root.collapsedFade
                visible: opacity > 0
                scale: (root.tokens ? root.tokens.contentScaleFrom : 0.96)
                    + (1 - (root.tokens ? root.tokens.contentScaleFrom : 0.96)) * root.peekClamped
                transformOrigin: Item.Top
                transform: Translate { x: root.swipeNudge }
            }
            // Above the closed row, the inline HUD and the peek, so capture
            // stays visible in every closed state; open, the header's chip
            // names the apps instead.
            PrivacyDots {
                tokens: root.ink
                privacy: root.privacy
                rowCentre: pill.rowCentre
                opacity: root.collapsedFade
                transform: Translate { x: root.swipeNudge }
            }
        }
    }
    // The readout's pill under the closed notch, when hudStyle is "below".
    HudBelow {
        id: hudBelow
        objectName: "hudBelow"
        x: Math.round((root.width - width) / 2)
        y: root.pillHeight + notchGap
        visible: active && root.hudStyle === "below" && !root.expanded
        opacity: root.collapsedFade
        tokens: root.ink
        model: root.hud
        notchWidth: root.closedWidth
        notchHeight: root.pillHeight
        showPercent: root.settings.hudPercentClosed === true
        accent: root.settings.hudAccent === true
        gradientEnabled: root.settings.hudGradient === true
        glowEnabled: root.settings.hudGlow === true
        onSetLevel: (kind, value) => root.hudLevelRequested(kind, value)
    }
    // The active HUD's input rectangle. Panel.qml unions it with hitShape
    // in the window mask while a readout has a bar, jumping once as it
    // comes and goes (tests/source-contract.py names it).
    Item {
        id: hudHitShape
        objectName: "islandHudHitShape"
        readonly property bool present: !!root.hudHitRect
        x: present ? root.hudHitRect.x : 0
        y: present ? root.hudHitRect.y : 0
        width: present ? root.hudHitRect.width : 0
        height: present ? root.hudHitRect.height : 0
    }
    readonly property alias hudHitShape: hudHitShape
    // Entering the active HUD stops a hover dwell already running; leaving
    // it for the notch body starts the dwell as usual.
    // What a hover move over the closed notch does to the dwell: "stop" on
    // the HUD or with a button held (a drag passing over the notch is not a
    // request to open it), otherwise "start" when none runs, or "keep".
    // Extracted like allowsHoverExpand(): the offscreen pipeline cannot
    // carry a held button through the hover handler, so tests drive this.
    function dwellStep(position, pressedButtons, running) {
        var p = hitShape.mapToItem(root, position.x, position.y);
        if (!allowsHoverExpand(pressedButtons === undefined ? Qt.NoButton : pressedButtons, p))
            return "stop";
        return running ? "keep" : "start";
    }
    function trackHoverPoint(position, pressedButtons) {
        if (!hover.hovered || expanded)
            return;
        var step = dwellStep(position, pressedButtons, dwell.running);
        if (step === "stop")
            dwell.stop();
        else if (step === "start")
            dwell.restart();
    }
    onHudHitRectChanged: if (hover.hovered && !expanded && hudHitRect)
        trackHoverPoint(hover.point.position, hover.point.pressedButtons)
    // Leaving the header's overflow menu for somewhere outside the island
    // starts the leave grace, as leaving the island itself does.
    Connections {
        target: header
        function onOverflowHoveredChanged() {
            // Read from the handlers: pointerInside may not have caught up
            // with this change yet.
            if (!header.overflowHovered && root.expanded && !hover.hovered && !extensionHover.hovered && !drop.containsDrag)
                grace.restart();
            else if (header.overflowHovered)
                grace.stop();
        }
    }
    // A released bar lets a waiting open through, or, open, restarts the
    // grace a held capsule deferred.
    Connections {
        target: root
        function onHudHeldHereChanged() {
            if (root.hudHeldHere)
                return;
            if (root.pendingOpen !== "") {
                root.expandTo(root.pendingOpen);
            } else if (root.expanded && !root.pointerInside && !drop.containsDrag && !root.explicitOpen && !root.interacting)
                grace.restart();
        }
    }
    // The catch zone: while closed, a bar-high drop region over the empty bar
    // centre, wider than the body. Panel.qml unions it with hitShape into the
    // input region, so it jumps once when the island opens or closes and is
    // never resized per frame. It holds only a DropArea: no hover, tap, wheel
    // or pull, so pointer use of the empty bar is not turned into island
    // gestures. Zero wide, it adds nothing to the input region.
    readonly property real catchWidth: CatchZone.width({
        enabled: settings.shelfEnabled && settings.expandedDragDetection,
        expanded: expanded,
        interactive: interactive,
        dropIn: dropInSupported,
        shared: barCentreShared,
        requested: settings.dragCatchWidth,
        body: hitShape.width,
        limit: barCentreSpan >= 0 ? Math.min(barCentreSpan, availableWidth, openWidth - 2 * flareOpen) : -1
    })
    Item {
        id: catchZone
        objectName: "islandCatchZone"
        z: root.catchDropHandoff ? 3 : 0
        x: (root.width - width) / 2
        y: 0
        width: root.catchDropHandoff ? root.catchHandoffWidth : root.catchWidth
        height: root.pillHeight
        DropArea {
            objectName: "islandCatchDropArea"
            anchors.fill: parent
            enabled: parent.width > 0
            keys: ["text/uri-list", "text/plain"]
            onEntered: drag => root.handleCatchEnter(drag)
            onDropped: event => root.handleDrop(event)
            onExited: root.handleCatchExit()
        }
    }
    Item {
        id: hitShape
        objectName: "islandHitShape"
        // The body alone, closed or open: never the flares, the overshoot
        // slack or the shadow room around it. No Behavior: the mask must
        // jump to the target region in one frame, never resize the layer
        // window's input region per animation frame. A peek never grows it:
        // the peek appears without user action, so a wider region would take
        // clicks, and start the hover dwell, meant for the window beneath it.
        // Beyond the closed body, the peek is visual only.
        x: (root.width - width) / 2
        y: 0
        width: root.expanded ? root.openWidth - 2 * root.flareOpen : root.closedHitWidth - 2 * root.flareClosed
        height: root.expanded ? root.restHeight : root.pillHeight
        HoverHandler {
            id: hover
            enabled: root.interactive
            onPointChanged: if (hovered) root.trackHoverPoint(point.position, point.pressedButtons)
            onHoveredChanged: {
                if (hovered) {
                    root.cancelAutoClose();
                    grace.stop();
                    if (root.allowsHoverExpand(point.pressedButtons, hitShape.mapToItem(root, point.position.x, point.position.y)))
                        dwell.restart();
                } else {
                    // Moving into the hover strip enters it before this
                    // leave arrives; its dwell must keep running.
                    if (!extensionHover.hovered)
                        dwell.stop();
                    if (!drop.containsDrag)
                        grace.restart();
                }
            }
        }
        // A press on the HUD bar is the bar's, never a tap that opens.
        TapHandler {
            enabled: root.interactive && !root.expanded && !root.pointerOnHud
            onTapped: (eventPoint) => {
                var p = hitShape.mapToItem(root, eventPoint.position.x, eventPoint.position.y);
                if (!root.inHud(p.x, p.y))
                    root.expandTo(root.view);
            }
        }
        // Any press on the open notch is an interaction that cancels a
        // summon's auto-close; it never takes the press from the controls.
        PointHandler {
            enabled: root.interactive && root.expanded
            acceptedButtons: Qt.AllButtons
            onActiveChanged: if (active) root.cancelAutoClose()
        }
        // Pull the closed notch down to open it.
        DragHandler {
            objectName: "pullOpenDrag"
            target: null
            enabled: root.gesturesAllowed && !root.expanded && !root.pointerOnHud
            xAxis.enabled: false
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen | PointerDevice.TouchPad | PointerDevice.Stylus
            // A drag that starts on the HUD bar is the bar's.
            property bool onHud: false
            onActiveChanged: {
                if (active) {
                    var p = hitShape.mapToItem(root, centroid.pressPosition.x, centroid.pressPosition.y);
                    onHud = root.inHud(p.x, p.y);
                } else {
                    onHud = false;
                    root.endPull();
                }
            }
            onActiveTranslationChanged: if (active && !onHud) root.updatePull(activeTranslation.y)
        }

        // Report only: with no target, a handler never moves or scales an
        // item. A WheelHandler takes only events on its own axis, so there
        // is one per axis; each passes on only the events its axis dominates,
        // so a diagonal event is counted once. The expanded card has its own
        // scrolling lists and sliders, so both stop while it shows.
        WheelHandler {
            target: null
            orientation: Qt.Vertical
            enabled: root.interactive && !root.expanded
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                var p = hitShape.mapToItem(root, point.position.x, point.position.y);
                if (root.inHud(p.x, p.y))
                    return;
                if (Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x))
                    root.handleWheel(event.angleDelta.x, event.angleDelta.y, event.inverted, event.modifiers);
            }
        }
        WheelHandler {
            target: null
            orientation: Qt.Horizontal
            enabled: root.interactive && !root.expanded
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                var p = hitShape.mapToItem(root, point.position.x, point.position.y);
                if (root.inHud(p.x, p.y))
                    return;
                if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y))
                    root.handleWheel(event.angleDelta.x, event.angleDelta.y, event.inverted, event.modifiers);
            }
        }
        // While open, only a Shift-wheel is the island's: it pushes the
        // notch closed. A plain wheel stays with the lists and sliders.
        WheelHandler {
            target: null
            enabled: root.interactive && root.expanded
            acceptedModifiers: Qt.ShiftModifier
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => root.handleWheel(event.angleDelta.x, event.angleDelta.y, event.inverted, event.modifiers)
        }
        DropArea {
            id: drop
            objectName: "islandDropArea"
            anchors.fill: parent
            // On the Shelf tab the strip takes the drop, with its own notice
            // and text support; this area sits above it and would shadow it.
            enabled: root.settings.shelfEnabled
                && (!(root.expanded && root.view === "shelf") || root.bodyDropHandoff)
            keys: root.dropInSupported ? ["text/uri-list"] : []
            onEntered: drag => root.handleBodyEnter(drag)
            onDropped: dropEvent => root.handleDrop(dropEvent)
            onExited: root.bodyDropHandoff = false
            onContainsDragChanged: if (!containsDrag && !root.pointerInside)
                grace.restart()
        }
    }
    // An optional strip beneath the closed body enlarges hover acquisition
    // without making that space a notch tap, wheel or pull target. Wayland's
    // input mask still intercepts clicks there while the strip is enabled.
    Item {
        id: hoverExtension
        objectName: "islandHoverExtension"
        x: hitShape.x
        y: root.pillHeight
        width: hitShape.width
        height: root.settings.extendHoverArea && !root.expanded ? 8 : 0
        HoverHandler {
            id: extensionHover
            enabled: root.interactive && hoverExtension.height > 0
            onHoveredChanged: {
                if (hovered) {
                    grace.stop();
                    var p = hoverExtension.mapToItem(root, point.position.x, point.position.y);
                    if (root.allowsHoverExpand(point.pressedButtons, p))
                        dwell.restart();
                } else {
                    // Moving into the pill enters it before this leave
                    // arrives; the dwell it restarted must keep running.
                    if (!hover.hovered)
                        dwell.stop();
                    if (!hover.hovered && !drop.containsDrag)
                        grace.restart();
                }
            }
            onPointChanged: if (hovered && !root.expanded) {
                var p = hoverExtension.mapToItem(root, point.position.x, point.position.y);
                if (!root.allowsHoverExpand(point.pressedButtons, p))
                    dwell.stop();
                else if (!dwell.running)
                    dwell.restart();
            }
        }
    }
    readonly property alias hoverExtension: hoverExtension
}
