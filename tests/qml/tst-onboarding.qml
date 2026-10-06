import QtQuick
import QtTest
import "../../components"
import "../../qml/Onboarding.js" as Onboarding
import "../../qml/Settings.js" as Settings
import "../../qml/Strings.js" as Strings

TestCase {
    id: test
    name: "Onboarding"
    width: 400
    height: 600
    when: windowShown
    visible: true

    DesignTokens {
        id: design
        reducedMotion: true
    }
    QtObject {
        id: fakeCoordinator
        property var endpoints: []
        property string selectionMode: "auto"
        property var selectedEndpoint: null
        property var opened: []
        property bool windowsAllowed: true
        property var settings: ({})
        property var fileSettings: Settings.resolve(null)
        property string configureError: ""
        property var calls: []
        property string preferredSource: ""
        property var remembered: []
        property string summonConflict: ""
        property int summonChecks: 0
        property bool islandOffCentre: false
        property bool refuseRemember: false
        function selectAuto() {}
        function selectSource(token) {}
        function openSettings(section) { opened = opened.concat([section]); return true }
        function configure(options) {
            calls = calls.concat([options])
            if (!Settings.validateBatch(options)) { configureError = "invalid"; return false }
            configureError = ""
            var shell = Object.assign({}, settings), file = Object.assign({}, fileSettings)
            for (var key in options) {
                if (Settings.entry(key).store === "shell") shell[key] = options[key]
                else file[key] = options[key]
            }
            settings = shell
            fileSettings = Settings.resolve(file)
            return true
        }
        function rememberSource(token) {
            remembered = remembered.concat([token])
            if (refuseRemember) { configureError = "save-failed"; return false }
            configureError = ""
            preferredSource = token ? "org.mpris.MediaPlayer2." + token.name : ""
            return true
        }
        function checkSummonBinding() { summonChecks++ }
    }
    function init() {
        fakeCoordinator.settings = {}
        fakeCoordinator.fileSettings = Settings.resolve(null)
        fakeCoordinator.calls = []
        fakeCoordinator.opened = []
        fakeCoordinator.remembered = []
        fakeCoordinator.preferredSource = ""
        fakeCoordinator.endpoints = []
        fakeCoordinator.summonConflict = ""
        fakeCoordinator.summonChecks = 0
        fakeCoordinator.islandOffCentre = false
        fakeCoordinator.refuseRemember = false
        fakeCoordinator.configureError = ""
    }
    Component {
        id: viewComponent
        OnboardingView {
            anchors.fill: parent
            tokens: design
            coordinator: fakeCoordinator
            property var result: null
            onFinished: skipped => result = skipped
        }
    }
    // A stand-in for the capture source that counts how many are alive, so a
    // test can prove the camera opens and closes without a real device.
    property int liveSources: 0
    property int sourcesCreated: 0
    property bool fakeUnavailable: false
    Component {
        id: fakeCameraSource
        Item {
            property bool unavailable: test.fakeUnavailable
            Component.onCompleted: { test.liveSources++; test.sourcesCreated++ }
            Component.onDestruction: test.liveSources--
        }
    }
    Component {
        id: cameraViewComponent
        OnboardingView {
            anchors.fill: parent
            tokens: design
            coordinator: fakeCoordinator
            cameraSourceComponent: fakeCameraSource
        }
    }
    function cameraStepView() {
        liveSources = 0
        sourcesCreated = 0
        fakeUnavailable = false
        fakeCoordinator.windowsAllowed = true
        var view = createTemporaryObject(cameraViewComponent, test)
        for (var i = 0; i < 4; ++i) mouseClick(findChild(view, "onboardingNext"))
        compare(view.step.id, "camera")
        return view
    }
    function pressTest(view) {
        mouseClick(findChild(view, "onboardingCameraTest"))
        tryCompare(test, "liveSources", 1)
    }
    function test_camera_opens_only_after_the_test_press() {
        var view = cameraStepView()
        wait(50)
        compare(liveSources, 0, "reaching the step opens nothing")
        verify(findChild(view, "onboardingCameraHint").visible)
        compare(findChild(view, "onboardingCameraTest").text, "Test camera")
        pressTest(view)
        compare(findChild(view, "onboardingCameraTest").text, "Stop test")
        verify(!findChild(view, "onboardingCameraHint").visible)
        mouseClick(findChild(view, "onboardingCameraTest"))
        tryCompare(test, "liveSources", 0, 1000, "Stop test closes it")
    }
    function test_leaving_or_skipping_the_step_closes_the_camera_data() {
        return [{ tag: "next", button: "onboardingNext" }, { tag: "back", button: "onboardingBack" },
            { tag: "skip", button: "onboardingSkip" }, { tag: "skip all", button: "onboardingSkipAll" }]
    }
    function test_leaving_or_skipping_the_step_closes_the_camera(data) {
        var view = cameraStepView()
        pressTest(view)
        mouseClick(findChild(view, data.button))
        tryCompare(test, "liveSources", 0, 1000)
        verify(!view.cameraTestRequested, "the press is withdrawn")
        if (data.tag === "back" || data.tag === "next") {
            mouseClick(findChild(view, data.tag === "back" ? "onboardingNext" : "onboardingBack"))
            compare(view.step.id, "camera")
            wait(50)
            compare(liveSources, 0, "coming back does not reopen the camera")
            compare(sourcesCreated, 1)
        }
    }
    function test_hidden_window_or_lock_closes_the_camera_data() {
        return [{ tag: "window hidden" }, { tag: "lock" }]
    }
    function test_hidden_window_or_lock_closes_the_camera(data) {
        var view = cameraStepView()
        pressTest(view)
        if (data.tag === "lock") fakeCoordinator.windowsAllowed = false
        else view.hostVisible = false
        tryCompare(test, "liveSources", 0, 1000)
        verify(!view.cameraTestRequested)
        verify(!findChild(view, "onboardingCameraTest").enabled, "the test cannot start while not allowed")
        if (data.tag === "lock") fakeCoordinator.windowsAllowed = true
        else view.hostVisible = true
        wait(50)
        compare(liveSources, 0, "allowing it again does not reopen the camera")
    }
    function test_destroying_the_view_closes_the_camera() {
        var view = cameraStepView()
        pressTest(view)
        view.destroy()
        tryCompare(test, "liveSources", 0, 1000, "closing the window destroys the source")
    }
    function test_camera_error_shows_unavailable() {
        var view = cameraStepView()
        fakeUnavailable = true
        pressTest(view)
        tryVerify(function() { return findChild(view, "cameraUnavailableText").visible })
        compare(findChild(view, "cameraUnavailableText").text, "Camera unavailable")
        verify(findChild(view, "cameraCautionIcon").visible)
    }
    Component {
        id: faceComponent
        IdleFace {
            width: 80
            height: 70
        }
    }

    function ids(state) { return Onboarding.STEPS[state.index].id }

    function test_steps_in_order() {
        compare(Onboarding.STEPS.map(function (step) { return step.id }),
            ["welcome", "look", "media", "calendar", "camera", "shortcuts", "done"])
    }

    function test_next_and_back() {
        var state = Onboarding.start()
        compare(ids(state), "welcome")
        compare(Onboarding.back(state), state, "back on the first step stays")
        state = Onboarding.next(state)
        compare(ids(state), "look")
        compare(state.direction, 1)
        state = Onboarding.back(state)
        compare(ids(state), "welcome")
        compare(state.direction, -1)
        for (var i = 0; i < 6; ++i) state = Onboarding.next(state)
        compare(ids(state), "done")
        verify(Onboarding.isLast(state) && !state.finished)
        state = Onboarding.next(state)
        verify(state.finished)
        compare(Onboarding.next(state), state, "a finished flow does not move")
        compare(Onboarding.back(state), state)
    }

    function test_every_step_can_be_skipped() {
        var state = Onboarding.start()
        for (var i = 0; i < Onboarding.STEPS.length - 1; ++i) {
            var before = ids(state)
            state = Onboarding.skip(state)
            verify(state.skipped.indexOf(before) >= 0, before + " recorded as skipped")
        }
        compare(ids(state), "done")
        state = Onboarding.skip(state)
        verify(state.finished, "skipping Done finishes")
        compare(state.skipped, ["welcome", "look", "media", "calendar", "camera", "shortcuts"])
    }

    function test_skip_all_goes_to_done() {
        var state = Onboarding.next(Onboarding.next(Onboarding.next(Onboarding.start())))
        state = Onboarding.skipAll(state)
        compare(ids(state), "done")
        compare(state.skipped, ["calendar", "camera", "shortcuts"])
        verify(!state.finished)
        var closed = Onboarding.close(Onboarding.next(Onboarding.start()))
        verify(closed.finished, "closing finishes")
        compare(closed.skipped, ["look", "media", "calendar", "camera", "shortcuts"])
    }

    function test_view_walks_the_steps() {
        var view = createTemporaryObject(viewComponent, test)
        compare(findChild(view, "onboardingTitle").text, "Welcome")
        verify(findChild(view, "onboardingFace"), "the welcome shows the idle face")
        verify(!findChild(view, "onboardingBack").enabled)
        mouseClick(findChild(view, "onboardingNext"))
        compare(view.step.id, "look")
        verify(findChild(view, "onboardingIdlePreview"), "the look step previews the idle notch")
        mouseClick(findChild(view, "onboardingNext"))
        compare(findChild(view, "onboardingTitle").text, "Media")
        verify(findChild(view, "autoSourceButton"), "the media step shows the source picker")
        mouseClick(findChild(view, "onboardingSkip"))
        compare(view.step.id, "calendar")
        mouseClick(findChild(view, "onboardingCalendarSettings"))
        compare(fakeCoordinator.opened, ["calendar"])
        mouseClick(findChild(view, "onboardingNext"))
        verify(findChild(view, "onboardingCameraPanel"), "the camera step shows the camera test")
        mouseClick(findChild(view, "onboardingBack"))
        compare(view.step.id, "calendar")
        mouseClick(findChild(view, "onboardingSkipAll"))
        compare(view.step.id, "done")
        verify(!findChild(view, "onboardingSkip").visible)
        compare(findChild(view, "onboardingNext").text, "Finish")
        mouseClick(findChild(view, "onboardingOpenSettings"))
        compare(fakeCoordinator.opened, ["calendar", ""], "Done offers the settings window")
        compare(view.result, null)
        mouseClick(findChild(view, "onboardingNext"))
        compare(view.result, ["media", "calendar", "camera", "shortcuts"])
        compare(fakeCoordinator.calls, [], "walking through changes no setting")
    }
    // Each step offers its settings as working rows; only a pick writes.
    function test_steps_offer_real_choices() {
        var view = createTemporaryObject(viewComponent, test)
        mouseClick(findChild(view, "onboardingNext"))
        var face = findChild(view, "onboardingIdleFace")
        verify(!face.visible, "the preview starts with Glance")
        verify(findChild(view, "onboardingIdleGlance").visible)
        mouseClick(findChild(view, "settingChoice-idleStyle-face"))
        compare(fakeCoordinator.calls, [{ idleStyle: "face" }])
        verify(face.visible, "the preview follows the pick")
        verify(!findChild(view, "settingControl-showIdleFace"), "the retired switch is not offered")
        verify(findChild(view, "settingControl-remoteArtwork"), "online artwork is offered with the look")
        mouseClick(findChild(view, "onboardingNext"))
        verify(findChild(view, "settingControl-lyrics") && findChild(view, "settingControl-peek"))
        mouseClick(findChild(view, "onboardingNext"))
        mouseClick(findChild(view, "settingInput-showCalendar").item)
        compare(fakeCoordinator.fileSettings.showCalendar, true)
        mouseClick(findChild(view, "onboardingNext"))
        mouseClick(findChild(view, "settingInput-showMirror").item)
        compare(fakeCoordinator.fileSettings.showMirror, true)
        compare(fakeCoordinator.calls.length, 3)
        for (var key in Onboarding.STEP_SETTINGS)
            Onboarding.STEP_SETTINGS[key].forEach(function (name) {
                if (Settings.entry(name)) compare(Settings.entry(name).default, Settings.defaults()[name])
            })
    }
    function test_idle_style_preview_follows_each_pick() {
        var view = createTemporaryObject(viewComponent, test)
        mouseClick(findChild(view, "onboardingNext"))
        var preview = findChild(view, "onboardingIdlePreview")
        compare(preview.width, design.liveWidth)
        verify(findChild(view, "onboardingIdleGlance").visible)
        mouseClick(findChild(view, "settingChoice-idleStyle-horizon"))
        compare(preview.width, design.horizonWidth)
        verify(findChild(view, "onboardingIdleHorizon").visible)
        verify(!findChild(view, "onboardingIdleGlance").visible)
        mouseClick(findChild(view, "settingChoice-idleStyle-empty"))
        compare(preview.width, design.idleWidth)
        verify(!findChild(view, "onboardingIdleHorizon").visible)
        mouseClick(findChild(view, "settingChoice-idleStyle-glance"))
        compare(preview.width, design.liveWidth)
        verify(findChild(view, "onboardingIdleGlance").visible)
        compare(fakeCoordinator.calls, [{ idleStyle: "horizon" }, { idleStyle: "empty" }, { idleStyle: "glance" }])
    }
    // The media step remembers the chosen player across restarts.
    function test_media_step_remembers_the_player() {
        fakeCoordinator.endpoints = [{ token: { name: "spotify" }, status: "Paused",
            presentation: { hostApp: "Spotify", controlScope: "application" } }]
        var view = createTemporaryObject(viewComponent, test)
        mouseClick(findChild(view, "onboardingNext"))
        mouseClick(findChild(view, "onboardingNext"))
        var list = findChild(view, "sourceList")
        tryVerify(function () { return list.itemAtIndex(0) !== null })
        mouseClick(list.itemAtIndex(0))
        compare(fakeCoordinator.remembered, [{ name: "spotify" }])
        mouseClick(findChild(view, "autoSourceButton"))
        compare(fakeCoordinator.remembered[1], null, "Auto forgets the remembered player")
    }
    // A choice that cannot be saved keeps the picker open and says why,
    // since it would otherwise look remembered.
    Component {
        id: rememberingPicker
        SourcePicker {
            width: 360
            height: 220
            overlay: true
            remember: true
            tokens: design
            coordinator: fakeCoordinator
            property int closes: 0
            onDismissed: closes++
        }
    }
    function test_refused_remember_keeps_the_picker_open() {
        fakeCoordinator.endpoints = [{ token: { name: "spotify" }, status: "Paused",
            presentation: { hostApp: "Spotify", controlScope: "application" } }]
        fakeCoordinator.refuseRemember = true
        var picker = createTemporaryObject(rememberingPicker, test)
        var list = findChild(picker, "sourceList")
        tryVerify(function () { return list.itemAtIndex(0) !== null })
        mouseClick(list.itemAtIndex(0))
        compare(fakeCoordinator.remembered.length, 1)
        compare(picker.closes, 0, "the picker stays open")
        var error = findChild(picker, "sourceRememberError")
        verify(error.visible)
        compare(error.text, Strings.settingErrorText("save-failed", null))
        verify(!picker.isChosen(fakeCoordinator.endpoints[0]), "nothing looks remembered")
        mouseClick(findChild(picker, "autoSourceButton"))
        compare(picker.closes, 0, "Auto cannot forget either while saving fails")
        fakeCoordinator.refuseRemember = false
        mouseClick(list.itemAtIndex(0))
        compare(picker.closes, 1, "a saved choice closes it")
        verify(!error.visible)
    }
    // Keyboard: Next holds the focus, Return moves on or presses the focused
    // button, Escape closes with the rest counted as skipped.
    function test_keyboard_moves_and_closes() {
        var view = createTemporaryObject(viewComponent, test)
        var next = findChild(view, "onboardingNext")
        verify(next.activeFocus, "Next has the focus")
        keyClick(Qt.Key_Return)
        compare(view.step.id, "look")
        verify(next.activeFocus, "and keeps it on the next step")
        findChild(view, "onboardingBack").forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(view.step.id, "welcome", "Return presses the focused Back")
        next.forceActiveFocus()
        keyClick(Qt.Key_Enter)
        compare(view.step.id, "look")
        keyClick(Qt.Key_Escape)
        compare(view.result, ["look", "media", "calendar", "camera", "shortcuts"])
    }
    // The welcome's buttons are the island's own, Next and Finish filled.
    function test_buttons_use_the_island_tokens() {
        var view = createTemporaryObject(viewComponent, test)
        var next = findChild(view, "onboardingNext"), skip = findChild(view, "onboardingSkip")
        compare(findChild(next, "settingButtonFill").color, design.primaryFill)
        compare(next.contentItem.color, design.primaryLabel)
        compare(findChild(skip, "settingButtonFill").color, design.surfaceRaised)
    }
    // Keys and placement: the one summon line with Copy and a conflict
    // check, and how to fix an island that is not the centre anchor.
    function test_keys_step_checks_the_chord_and_placement() {
        var view = createTemporaryObject(viewComponent, test)
        for (var i = 0; i < 5; ++i) mouseClick(findChild(view, "onboardingNext"))
        compare(view.step.id, "shortcuts")
        compare(fakeCoordinator.summonChecks, 1)
        compare(findChild(view, "onboardingSummonSnippet").text, Strings.summonBinding)
        verify(findChild(view, "summonCopy"))
        verify(!findChild(view, "onboardingPlacement").visible)
        fakeCoordinator.summonConflict = "Shell: Toggle media controls"
        verify(findChild(view, "summonConflict").visible)
        fakeCoordinator.islandOffCentre = true
        verify(findChild(view, "onboardingPlacement").visible)
        compare(findChild(view, "onboardingPlacementCommand").text, Strings.centrePlacement)
    }

    function test_steps_fade_and_slide() {
        design.reducedMotion = false
        var view = createTemporaryObject(viewComponent, test)
        var stage = findChild(view, "onboardingStage")
        mouseClick(findChild(view, "onboardingNext"))
        verify(stage.opacity < 1 && stage.offset > 0, "the next step starts faded and to the right")
        tryCompare(stage, "opacity", 1, 1500)
        tryCompare(stage, "offset", 0, 500)
        mouseClick(findChild(view, "onboardingBack"))
        verify(stage.offset < 0, "going back slides from the left")
        tryCompare(stage, "offset", 0, 1500)
        design.reducedMotion = true
    }

    // A face at midday, whatever the real clock says: at night it sleeps
    // and does not blink.
    function dayFace() {
        var face = createTemporaryObject(faceComponent, test)
        face.now = new Date(2026, 8, 27, 12, 0)
        return face
    }
    function test_idle_face_blinks_only_while_visible() {
        var face = dayFace()
        verify(face.blinking, "a visible face runs its blink loop")
        tryVerify(function () { return face.blink > 0.5 }, 7500, "the eyes close within one wait of 3 to 7 s")
        tryVerify(function () { return face.blink === 0 }, 1000, "and open again")
        face.visible = false
        verify(!face.blinking, "a hidden face stops its loop")
        compare(face.blink, 0)
        face.visible = true
        face.now = new Date(2026, 8, 27, 12, 0)
        verify(face.blinking)
        face.reducedMotion = true
        verify(!face.blinking, "reduced motion stops the blink")
        compare(findChild(face, "idleEye0").width, 4)
    }
    // A blink is four steps (half shut, shut, half shut, open), each a
    // whole-pixel eye height: four redraws, never a tween, and a 3 to 7 s
    // wait between blinks, always through a single-shot timer.
    function test_idle_face_blink_is_four_steps() {
        var face = dayFace()
        var timer = findChild(face, "idleBlink")
        verify(!timer.repeat, "never a repeating timer")
        verify(timer.interval >= 3000 && timer.interval < 7000)
        var steps = []
        face.blinkChanged.connect(function () { steps.push(face.blink) })
        tryVerify(function () { return steps.length >= 4 }, 8000)
        compare(steps.slice(0, 4), [2 / 3, 1, 2 / 3, 0])
        var lid = findChild(findChild(face, "idleEye0"), "idleEyeLid")
        face.blink = 2 / 3
        compare(lid.height, 2, "half shut is a whole pixel height")
        verify(timer.interval >= 3000 && timer.interval < 7000, "then waits again")
    }
    function test_idle_face_moods() {
        var face = dayFace()
        compare(face.mood, "neutral")
        face.now = new Date(2026, 8, 27, 23, 30)
        compare(face.mood, "neutral", "only the closed notch's face sleeps")
        face.sleepsAtNight = true
        face.now = new Date(2026, 8, 27, 23, 30)
        compare(face.mood, "sleepy", "late at night it is sleepy")
        verify(!face.blinking, "and does not blink")
        compare(findChild(findChild(face, "idleEye0"), "idleEyeLid").height, 1)
        face.now = new Date(2026, 8, 27, 5, 59)
        compare(face.mood, "sleepy")
        face.now = new Date(2026, 8, 27, 6, 0)
        compare(face.mood, "neutral")
        face.moodOverride = "happy"
        compare(face.mood, "happy")
        verify(findChild(findChild(face, "idleEye0"), "idleEyeSquint").visible, "happy squints")
        verify(!findChild(findChild(face, "idleEye0"), "idleEyeLid").visible)
        verify(!face.blinking)
        face.moodOverride = "worried"
        verify(findChild(face, "idleMouthO").visible, "worried drops the smile to an o")
        verify(!findChild(face, "idleSmile").visible)
        face.moodOverride = ""
        compare(face.mood, "neutral")
        verify(face.blinking)
    }
}
