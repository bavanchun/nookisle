import QtQuick
import QtTest
import "../../components"
import "../../qml/Settings.js" as Settings
import "../../qml/Calendar.js" as Calendar
import "../../qml/Strings.js" as Strings

TestCase {
    id: test
    name: "SettingsWindow"
    width: 700
    height: 600
    when: windowShown
    visible: true

    DesignTokens {
        id: design
        reducedMotion: true
    }
    // Stores what configure() accepts the way the Service does: validated
    // against the schema, then split by store.
    QtObject {
        id: coordinator
        property var settings: ({})
        property var fileSettings: Settings.resolve(null)
        property var calls: []
        property bool refuse: false
        property string configureError: ""
        property var manifest: ({ version: "1.0.0", build: "source", schemaVersion: 1,
            repository: "https://github.com/bavanchun/nookisle" })
        property var calendarSource: null
        property int onboardingOpened: 0
        property string summonConflict: ""
        property int summonChecks: 0
        function checkSummonBinding() { summonChecks++ }
        property string settingsFilePath: "/home/me/.config/nookisle/settings.json"
        function openOnboarding() { onboardingOpened++; return true }
        function configure(options) {
            calls = calls.concat([options])
            configureError = refuse ? "save-failed" : Settings.validateBatch(options) ? "" : "invalid"
            if (configureError) return false
            var shell = Object.assign({}, settings), file = Object.assign({}, fileSettings)
            for (var key in options) {
                if (Settings.entry(key).store === "shell") shell[key] = options[key]
                else file[key] = options[key]
            }
            settings = shell
            fileSettings = Settings.resolve(file)
            return true
        }
    }
    SettingsPane {
        id: pane
        anchors.fill: parent
        tokens: design
        coordinator: coordinator
    }
    Component {
        id: recorderComponent
        QtObject {
            property var calls: []
            function configure(options) { calls = calls.concat([options]); return true }
        }
    }
    Component {
        id: controlComponent
        SettingsControls {
            width: 400
            tokens: design
        }
    }
    Component {
        id: slotComponent
        SlotEditor {
            // Its host always gives it a width, as the settings row does.
            width: 500
            tokens: design
            value: ["previous", "play", "next"]
            palette: ["previous", "play", "next", "shuffle", "repeat"]
            maxLength: 4
            property var edits: []
            onEdited: next => edits = edits.concat([next])
        }
    }

    function init() {
        coordinator.settings = {}
        coordinator.fileSettings = Settings.resolve(null)
        coordinator.calls = []
        coordinator.refuse = false
        coordinator.calendarSource = null
        coordinator.onboardingOpened = 0
        coordinator.summonConflict = ""
        coordinator.summonChecks = 0
        pane.query = ""
        pane.showSection("general")
    }
    // Scrolls the page so an item is fully in view, as a person would
    // before pointing at it, and returns the item.
    function reveal(item) {
        // Rows of a section just shown sit at provisional coordinates until
        // their nested Columns finish a layout pass; a rendered frame
        // completes it.
        waitForRendering(pane, 250)
        var page = findChild(pane, "settingsPage")
        var top = item.mapToItem(page.contentItem, 0, 0).y
        if (top < page.contentY || top + item.height > page.contentY + page.height)
            page.contentY = Math.max(0, Math.min(page.contentHeight - page.height, top - design.inset))
        return item
    }
    function input(key) {
        var loader = findChild(pane, "settingInput-" + key)
        verify(loader, "input loader for " + key)
        tryVerify(function () { return loader.item !== null }, 1000, key + " control loaded")
        return loader.item
    }

    function test_sidebar_lists_every_section() {
        var labels = []
        for (var i = 0; i < Settings.SECTIONS.length; ++i) {
            var entry = findChild(pane, "settingsSection-" + Settings.SECTIONS[i].id)
            verify(entry, "sidebar entry " + Settings.SECTIONS[i].id)
            labels.push(entry.text)
            compare(entry.width, pane.sidebarWidth - design.gap * 2)
        }
        compare(labels, ["General", "Appearance", "Media", "Calendar", "HUD", "Battery", "Shelf",
            "Shortcuts", "Advanced", "About"])
    }

    function test_every_schema_key_renders_a_control() {
        var rendered = []
        var sections = Settings.sections()
        for (var i = 0; i < sections.length; ++i) {
            mouseClick(findChild(pane, "settingsSection-" + sections[i].id))
            compare(pane.currentSection, sections[i].id)
            for (var j = 0; j < sections[i].keys.length; ++j) {
                var key = sections[i].keys[j]
                var row = findChild(pane, "settingControl-" + key)
                verify(row && row.visible, key + " has a visible row")
                verify(row.height > 0, key + " row has height")
                verify(input(key), key + " has a control")
                rendered.push(key)
            }
        }
        var visibleKeys = Settings.SCHEMA.filter(Settings.shownInWindow).map(function (spec) { return spec.key })
        compare(rendered.slice().sort(), visibleKeys.sort())
        verify(!findChild(pane, "settingControl-calendarPendingClears"), "internal password clear identifiers stay out of the window")
        pane.showSection("calendar")
        verify(findChild(pane, "calendarAdd") && findChild(pane, "calendarPathField"),
            "the calendar source key opens its add, remove and test editor")
        coordinator.calendarSource = ({ items: [] })
        compare(input("calendarSources").source, coordinator.calendarSource,
            "the editor uses the Service's active calendar source")
    }

    // WCAG relative luminance contrast, for the colours the tokens pick.
    function luminance(c) {
        function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }
    function contrast(a, b) {
        var la = luminance(a), lb = luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    // The selected section reads clearly: its label on its own fill, in the
    // island's primary pair, and the others stay plain.
    function test_selected_section_is_readable() {
        pane.showSection("general")
        var selected = findChild(pane, "settingsSection-general")
        var other = findChild(pane, "settingsSection-media")
        var fill = findChild(selected, "settingsSectionFill"), label = findChild(selected, "settingsSectionLabel")
        compare(fill.color, design.primaryFill)
        compare(label.color, design.primaryLabel)
        verify(contrast(label.color, fill.color) >= 4.5, "the selected label reads at 4.5:1 on its fill")
        compare(findChild(other, "settingsSectionLabel").color, design.text)
        compare(findChild(other, "settingsSectionFill").color, Qt.rgba(0, 0, 0, 0))
        mouseClick(reveal(other))
        compare(findChild(other, "settingsSectionFill").color, design.primaryFill)
        compare(findChild(selected, "settingsSectionLabel").color, design.text)
    }
    // Choices show people's words and fill the stored one; switches show
    // their state in the track and the knob.
    function test_choices_and_switches_show_their_state() {
        pane.showSection("general")
        // Section changes can leave new rows at provisional coordinates until
        // the Column completes its next layout pass.
        tryVerify(function () {
            var mode = findChild(pane, "settingControl-displayMode")
            var fullscreen = findChild(pane, "settingControl-fullscreenBehavior")
            return mode && fullscreen && fullscreen.mapToItem(pane, 0, 0).y > mode.mapToItem(pane, 0, 0).y
        }, 1000, "general settings rows laid out before pointer interaction")
        var follow = findChild(pane, "settingChoice-displayMode-follow")
        var all = findChild(pane, "settingChoice-displayMode-all")
        compare(follow.text, "Follow focus")
        compare(all.text, "Every screen")
        compare(findChild(pane, "settingChoice-fullscreenBehavior-nowPlayingOnly").text, "Player's app only")
        verify(follow.checked)
        compare(findChild(follow, "settingButtonFill").color, design.primaryFill)
        verify(contrast(follow.contentItem.color, design.primaryFill) >= 4.5)
        verify(findChild(all, "settingButtonFill").color !== design.primaryFill, "an unselected choice stays plain")
        compare(all.contentItem.color, design.text)
        mouseClick(reveal(all))
        waitForRendering(pane, 250)
        compare(coordinator.fileSettings.displayMode, "all")
        compare(findChild(all, "settingButtonFill").color, design.primaryFill)
        verify(!follow.checked)

        var toggle = input("island")
        var track = findChild(toggle, "settingSwitchTrack"), knob = findChild(toggle, "settingSwitchKnob")
        var row = findChild(pane, "settingControl-island")
        verify(track.mapToItem(row, track.width, 0).x <= row.width + 0.5, "the switch stays inside its row")
        verify(toggle.checked)
        compare(track.color, design.primaryFill)
        var onX = knob.x
        mouseClick(reveal(toggle))
        verify(!toggle.checked)
        compare(track.color, design.track)
        verify(knob.x < onX, "the knob moves to the off side")
    }

    // Timer presets are typed as whole minutes; a list that is not valid is
    // put back and explained, never half saved.
    function test_timerPresetsAreTypedMinutes() {
        pane.showSection("general")
        var field = input("timerPresets")
        compare(field.text, "5, 10, 25, 60")
        field.text = "7, 45 90"
        field.editingFinished()
        compare(coordinator.fileSettings.timerPresets, [7, 45, 90])
        compare(field.text, "7, 45, 90")
        field.text = "7, 2000"
        field.editingFinished()
        compare(coordinator.fileSettings.timerPresets, [7, 45, 90], "out of range: nothing saved")
        compare(field.text, "7, 45, 90", "and the field shows the saved list again")
        verify(findChild(pane, "settingControl-timerPresets").failed)
        field.text = "five"
        field.editingFinished()
        compare(coordinator.fileSettings.timerPresets, [7, 45, 90])
    }

    // The sidebar is one Tab stop, the first in the window; the arrows move
    // between sections, and the focused entry wears a ring.
    function test_sidebar_sections_by_keyboard() {
        pane.showSection("general")
        var sidebar = findChild(pane, "settingsSidebar")
        var general = findChild(pane, "settingsSection-general")
        pane.forceActiveFocus()
        keyClick(Qt.Key_Tab)
        verify(sidebar.activeFocus, "Tab lands on the sidebar first")
        compare(findChild(general, "settingsSectionFill").border.width, design.focusWidth,
            "the selected section wears the focus ring")
        keyClick(Qt.Key_Down)
        compare(pane.currentSection, "appearance")
        compare(findChild(findChild(pane, "settingsSection-appearance"), "settingsSectionFill").border.width, design.focusWidth,
            "the ring follows the section")
        compare(findChild(general, "settingsSectionFill").border.width, 0)
        keyClick(Qt.Key_End)
        compare(pane.currentSection, "about")
        keyClick(Qt.Key_Home)
        compare(pane.currentSection, "general")
        keyClick(Qt.Key_Up)
        compare(pane.currentSection, "general", "Up at the top stays")
        keyClick(Qt.Key_Tab)
        verify(!sidebar.activeFocus, "the next Tab leaves the sidebar for the page")
        verify(input("autoShow").activeFocus, "on the first control of the page")
        compare(findChild(general, "settingsSectionFill").border.width, 0, "and the ring goes with it")
        keyClick(Qt.Key_Backtab)
        verify(sidebar.activeFocus, "Shift+Tab comes back to the sidebar")
    }
    // Every focusable control on the page draws a focus ring in the island
    // accent when reached by keyboard.
    function test_every_control_shows_keyboard_focus() {
        pane.showSection("general")
        var toggle = input("island")
        toggle.forceActiveFocus(Qt.TabFocusReason)
        compare(findChild(toggle, "settingSwitchTrack").border.width, design.focusWidth)
        var slider = findChild(pane, "settingSlider-hoverDwell")
        slider.forceActiveFocus(Qt.TabFocusReason)
        compare(findChild(slider, "settingSliderHandle").border.width, design.focusWidth)
        var choice = findChild(pane, "settingChoice-displayMode-all")
        choice.forceActiveFocus(Qt.TabFocusReason)
        var fill = findChild(choice, "settingButtonFill")
        compare(fill.border.width, design.focusWidth)
        compare(fill.border.color, design.accent)
        pane.showSection("hud")
        var field = input("backlightDevice")
        field.forceActiveFocus(Qt.TabFocusReason)
        compare(findChild(field, "settingFieldFrame").border.width, design.focusWidth)
        pane.showSection("calendar")
        var remote = findChild(pane, "calendarKind-ics-url")
        mouseClick(reveal(remote))
        var allow = findChild(pane, "calendarAllowRemote")
        allow.forceActiveFocus(Qt.TabFocusReason)
        compare(findChild(allow, "settingCheckBox").border.width, design.focusWidth)
        var add = findChild(pane, "calendarAdd")
        verify(add.focusPolicy & Qt.TabFocus, "the calendar buttons take Tab focus too")
    }
    // The player-button chips work without a drag: Tab reaches them,
    // Ctrl+Left/Right moves a slot, Delete removes it, Return adds a palette
    // word, and the focus ring follows the word through each edit.
    function test_slot_chips_by_keyboard() {
        pane.showSection("media")
        var editor = input("musicControlSlots")
        function chip(word) {
            var rows = [findChild(editor, "slotRow"), findChild(editor, "slotPalette")]
            for (var r = 0; r < rows.length; ++r)
                for (var i = 0; i < rows[r].children.length; ++i)
                    if (rows[r].children[i].word === word) return rows[r].children[i]
            return null
        }
        var slots = function () { return coordinator.fileSettings.musicControlSlots }
        compare(slots(), ["shuffle", "previous", "playPause", "next", "repeat"])
        var first = chip("shuffle")
        verify(first.activeFocusOnTab, "a slot chip is a Tab stop")
        first.forceActiveFocus(Qt.TabFocusReason)
        compare(first.children[0].border.width, design.focusWidth, "with a focus ring")
        keyClick(Qt.Key_Right, Qt.ControlModifier)
        compare(slots(), ["previous", "shuffle", "playPause", "next", "repeat"])
        tryVerify(function () { return chip("shuffle").activeFocus }, 1000, "the focus follows the moved slot")
        keyClick(Qt.Key_Left, Qt.ControlModifier)
        keyClick(Qt.Key_Left, Qt.ControlModifier)
        compare(slots(), ["shuffle", "previous", "playPause", "next", "repeat"], "the first slot stays first")
        tryVerify(function () { return chip("shuffle").activeFocus }, 1000)
        keyClick(Qt.Key_Delete)
        compare(slots(), ["previous", "playPause", "next", "repeat"])
        tryVerify(function () { return chip("shuffle").activeFocus && chip("shuffle").fromSlot === -1 }, 1000,
            "a removed word keeps the focus in the palette")
        var volume = chip("volume")
        volume.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Return)
        compare(slots(), ["previous", "playPause", "next", "repeat", "volume"], "Return adds a palette word at the end")
        tryVerify(function () { return chip("volume").activeFocus && chip("volume").fromSlot === 4 }, 1000)
        chip("back15").forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Return)
        compare(slots(), ["previous", "playPause", "next", "repeat", "back15"], "a full list swaps its last slot")
    }
    function test_rejected_slot_moves_do_not_restore_focus_later() {
        pane.showSection("media")
        var editor = input("musicControlSlots")
        var row = findChild(editor, "slotRow")
        var sidebar = findChild(pane, "settingsSidebar")
        function slot(index) {
            for (var i = 0; i < row.children.length; ++i)
                if (row.children[i].fromSlot === index) return row.children[i]
            return null
        }
        var original = coordinator.fileSettings.musicControlSlots
        slot(0).forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Left, Qt.ControlModifier)
        compare(coordinator.fileSettings.musicControlSlots, original, "the first slot cannot move left")
        sidebar.forceActiveFocus(Qt.TabFocusReason)
        coordinator.fileSettings = Object.assign({}, coordinator.fileSettings,
            { musicControlSlots: ["previous", "shuffle", "playPause", "next", "repeat"] })
        wait(10)
        verify(sidebar.activeFocus, "an external refresh must not restore focus to the first slot")

        slot(4).forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Right, Qt.ControlModifier)
        compare(coordinator.fileSettings.musicControlSlots,
            ["previous", "shuffle", "playPause", "next", "repeat"], "the last slot cannot move right")
        sidebar.forceActiveFocus(Qt.TabFocusReason)
        coordinator.fileSettings = Object.assign({}, coordinator.fileSettings, { musicControlSlots: original })
        wait(10)
        verify(sidebar.activeFocus, "an external refresh must not restore focus to the last slot")
    }
    // No raw identifier reaches the window, and nothing is clipped or split.
    function test_labels_wrap_and_fit() {
        pane.showSection("media")
        var chips = ["playPause", "back15", "forward15"]
        var names = ["Play/Pause", "Back 15 seconds", "Forward 15 seconds"]
        var editor = input("musicControlSlots")
        for (var i = 0; i < chips.length; ++i)
            compare(editor.labelOf(chips[i]), names[i])
        var trash = findChild(editor, "slotTrash")
        verify(trash.mapToItem(editor, trash.width, 0).x <= editor.width + 0.5, "the trash stays in the window")
        compare(findChild(pane, "settingChoice-sliderColor-albumArt").text, "Album art")
        pane.showSection("shelf")
        compare(findChild(pane, "settingChoice-shareProvider-kdeconnect").text, "KDE Connect")
        compare(findChild(pane, "settingChoice-shareProvider-portal").text, "Open folder")
        pane.showSection("calendar")
        var kinds = findChild(pane, "calendarKinds")
        var ical = findChild(pane, "calendarKind-ics-url")
        verify(ical.mapToItem(kinds, ical.width, 0).x <= kinds.width + 0.5, "the iCal tab fits its row")
        verify(ical.contentItem.implicitWidth <= ical.availableWidth + 0.5, "and its label is not cut")
        pane.showSection("shortcuts")
        compare(findChild(pane, "summonSnippet").wrapMode, TextEdit.Wrap, "the snippet wraps only at spaces")
    }

    function test_fixed_sections_have_their_content() {
        pane.showSection("shortcuts")
        verify(findChild(pane, "settingsShortcuts").visible)
        verify(findChild(pane, "summonSnippet").text.indexOf("shell summon io.github.bavanchun.nookisle") >= 0)
        pane.showSection("about")
        verify(findChild(pane, "settingsAbout").visible)
        verify(!pane.showSection("nowhere"))
        compare(pane.currentSection, "about")
        compare(pane.repositoryUrl, coordinator.manifest.repository)
        compare(findChild(pane, "settingsBuildInfo").text, "Build: source · Manifest schema: 1")
        coordinator.manifest = Object.assign({}, coordinator.manifest, { build: "abcdef123456" })
        compare(findChild(pane, "settingsBuildInfo").text, "Build: abcdef123456 · Manifest schema: 1")
        verify(findChild(pane, "settingsProjectLink").visible)
    }

    function test_custom_accent_controls() {
        pane.showSection("advanced")
        var toggle = input("useCustomAccentColor")
        verify(!toggle.checked)
        var page = findChild(pane, "settingsPage")
        page.contentY = Math.max(0, page.contentY + toggle.mapToItem(page, 0, 0).y - 80)
        wait(20)
        mouseClick(reveal(toggle))
        compare(coordinator.fileSettings.useCustomAccentColor, true)
        var field = input("customAccentColor")
        field.text = "#ef1256"
        field.editingFinished()
        compare(coordinator.fileSettings.customAccentColor, "#ef1256")
        // A refused colour says what a colour looks like and keeps the
        // typing, so it can be corrected rather than retyped.
        field.text = "#abc"
        field.editingFinished()
        compare(coordinator.fileSettings.customAccentColor, "#ef1256")
        compare(field.text, "#abc")
        var error = findChild(pane, "settingError-customAccentColor")
        verify(error.visible)
        compare(error.text, "Use a colour written like #a9c7ff.")
        field.text = "#abcdef"
        field.editingFinished()
        compare(coordinator.fileSettings.customAccentColor, "#abcdef")
        verify(!error.visible)
    }

    // A row that another setting turns off is dimmed, its control disabled,
    // and it says which setting to turn on; turning that on restores it.
    function test_dependent_rows_follow_their_setting() {
        pane.showSection("general")
        var row = findChild(pane, "settingControl-hoverDwell")
        verify(row.enabled, "open delay is live while open on hover is on")
        verify(!findChild(pane, "settingRequirement-hoverDwell").visible)
        mouseClick(reveal(input("openOnHover")))
        compare(coordinator.fileSettings.openOnHover, false)
        verify(!row.enabled, "open delay dims once open on hover is off")
        verify(!findChild(pane, "settingSlider-hoverDwell").enabled)
        var why = findChild(pane, "settingRequirement-hoverDwell")
        verify(why.visible)
        compare(why.text, "Turn on Open on hover to use this.")
        compare(findChild(pane, "settingRow-hoverDwell").opacity, 0.45)
        mouseClick(reveal(input("openOnHover")))
        verify(row.enabled)
        // A condition over several keys holds when any of them does.
        coordinator.configure({ enableGestures: false })
        verify(findChild(pane, "settingControl-gestureTravel").enabled)
        coordinator.configure({ closeGesture: false })
        verify(!findChild(pane, "settingControl-gestureTravel").enabled)
        // Every condition must hold.
        pane.showSection("shelf")
        verify(findChild(pane, "settingControl-dragCatchWidth").enabled)
        coordinator.configure({ expandedDragDetection: false })
        compare(findChild(pane, "settingRequirement-dragCatchWidth").text,
            "Turn on Enable shelf and Catch drags near the notch to use this.")
        coordinator.configure({ expandedDragDetection: true, shelfEnabled: false })
        verify(!findChild(pane, "settingControl-dragCatchWidth").enabled)
        verify(!findChild(pane, "settingControl-shelfPersist").enabled)
        verify(findChild(pane, "settingControl-shelfEnabled").enabled)
    }
    // Every requirement names real keys and a sentence, so a renamed key
    // cannot leave a row dimmed for good.
    function test_requirements_name_real_settings() {
        for (var key in Settings.REQUIRES) {
            verify(Settings.entry(key), key + " is a setting")
            var rule = Settings.REQUIRES[key]
            verify(rule.why.length > 0, key + " says why")
            for (var i = 0; i < rule.when.length; ++i)
                for (var j = 0; j < rule.when[i].keys.length; ++j)
                    verify(Settings.entry(rule.when[i].keys[j]), key + " depends on a real setting")
            compare(Settings.requirementText(key, function (k) { return Settings.entry(k).default }) === "",
                key !== "preferredDisplay" && Settings.REQUIRES[key].when.every(function (c) {
                    return c.keys.some(function (k) { return c.values.indexOf(Settings.entry(k).default) >= 0 }) }),
                key + " at the defaults")
        }
    }
    // The page follows the keyboard: a control that takes the focus below
    // or above the visible part scrolls into view.
    function test_page_scrolls_to_the_focused_control() {
        pane.showSection("general")
        var page = findChild(pane, "settingsPage")
        compare(page.contentY, 0)
        tryVerify(function () { return page.contentHeight > page.height }, 1000, "General is longer than the window")
        var choice = findChild(pane, "settingChoice-fullscreenBehavior-nowPlayingOnly")
        choice.forceActiveFocus(Qt.TabFocusReason)
        var top = choice.mapToItem(page, 0, 0).y
        verify(page.contentY > 0, "the page scrolled")
        verify(top >= 0 && top + choice.height <= page.height, "the focused choice is in view")
        input("island").forceActiveFocus(Qt.TabFocusReason)
        var toggle = input("island")
        verify(toggle.mapToItem(page, 0, 0).y >= 0, "scrolling back up shows the switch")
    }
    // Choices are a radio group: Tab reaches only the chosen one, and the
    // arrows choose the neighbour and move the focus with it.
    function test_choices_are_a_radio_group() {
        pane.showSection("general")
        var follow = findChild(pane, "settingChoice-displayMode-follow")
        var all = findChild(pane, "settingChoice-displayMode-all")
        verify(follow.checked)
        compare(follow.Accessible.role, Accessible.RadioButton)
        verify(follow.focusPolicy & Qt.TabFocus)
        verify(!(all.focusPolicy & Qt.TabFocus), "an unchosen choice is not a Tab stop")
        follow.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Right)
        compare(coordinator.fileSettings.displayMode, "all")
        verify(all.activeFocus && all.checked)
        keyClick(Qt.Key_Left)
        compare(coordinator.fileSettings.displayMode, "follow")
        verify(follow.activeFocus)
        keyClick(Qt.Key_Left)
        compare(coordinator.fileSettings.displayMode, "follow", "no choice before the first")
    }
    // Screen readers hear each row's help with its control.
    function test_controls_carry_their_help() {
        compare(input("island").Accessible.description, Settings.entry("island").help)
        compare(findChild(pane, "settingSlider-hoverDwell").Accessible.description, Settings.entry("hoverDwell").help)
        compare(findChild(pane, "settingChoice-displayMode-all").Accessible.description, Settings.entry("displayMode").help)
    }
    // The search finds rows in every section by their words; clearing it
    // returns to the section.
    function test_search_finds_rows_across_sections() {
        compare(Settings.search("").length, 0)
        var found = Settings.search("battery gauge").map(function (r) { return r.key })
        verify(found.indexOf("showBatteryIndicator") >= 0)
        var field = findChild(pane, "settingsSearch")
        field.forceActiveFocus()
        "lyrics".split("").forEach(function (letter) { keyClick(letter) })
        verify(pane.searching)
        compare(findChild(pane, "settingsPageTitle").text, "Search")
        var row = findChild(pane, "settingControl-lyrics")
        verify(row && row.visible, "the lyrics row is found from General")
        verify(!findChild(pane, "settingControl-hoverDwell"), "rows that do not match are gone")
        mouseClick(reveal(input("lyrics")))
        compare(coordinator.settings.lyrics, true, "a found row is a working row")
        field.forceActiveFocus()
        field.selectAll()
        "zzz".split("").forEach(function (letter) { keyClick(letter) })
        verify(findChild(pane, "settingsNoResults").visible)
        keyClick(Qt.Key_Escape)
        compare(pane.query, "")
        verify(findChild(pane, "settingControl-hoverDwell"), "Escape returns to the section")
    }
    function test_find_shortcut_focuses_the_search() {
        input("island").forceActiveFocus()
        keySequence(StandardKey.Find)
        verify(findChild(pane, "settingsSearch").activeFocus)
    }
    // A section resets to its defaults after one confirmation, and never
    // clears the calendars the person added.
    function test_reset_section_asks_then_restores_defaults() {
        coordinator.configure({ hoverDwell: 700, island: false })
        var reset = findChild(pane, "settingsResetSection")
        mouseClick(reveal(reset))
        compare(coordinator.fileSettings.hoverDwell, 700, "nothing changes before the confirmation")
        mouseClick(reveal(findChild(pane, "settingsResetCancel")))
        verify(reset.visible)
        mouseClick(reveal(reset))
        mouseClick(reveal(findChild(pane, "settingsResetConfirm")))
        compare(coordinator.fileSettings.hoverDwell, 300)
        compare(coordinator.settings.island, true)
        var batch = Settings.resetValues("calendar")
        verify(!("calendarSources" in batch), "calendar sources are data and stay")
        compare(batch.showCalendar, false)
        coordinator.refuse = true
        mouseClick(reveal(reset))
        mouseClick(reveal(findChild(pane, "settingsResetConfirm")))
        verify(findChild(pane, "settingsResetError").visible)
    }
    // The welcome is offered again from About, in place of a "Welcome
    // finished" switch.
    function test_about_offers_the_welcome_and_the_file() {
        verify(!Settings.shownInWindow(Settings.entry("onboardingDone")))
        pane.showSection("advanced")
        verify(!findChild(pane, "settingControl-onboardingDone"))
        pane.showSection("about")
        var welcome = findChild(pane, "settingsShowWelcome")
        verify(welcome.visible)
        mouseClick(reveal(welcome))
        compare(coordinator.onboardingOpened, 1)
        verify(findChild(pane, "settingsOpenFile").visible)
    }
    // The remembered player shows as a name with Forget, not a text field.
    function test_preferred_player_row() {
        pane.showSection("media")
        compare(findChild(pane, "preferredSourceName").text, "None: Auto follows whatever plays")
        verify(!findChild(pane, "preferredSourceForget").visible)
        coordinator.configure({ preferredSource: "org.mpris.MediaPlayer2.spotify" })
        compare(findChild(pane, "preferredSourceName").text, "Spotify")
        mouseClick(reveal(findChild(pane, "preferredSourceForget")))
        compare(coordinator.fileSettings.preferredSource, "")
    }
    // Shortcuts shows the one summon line with Copy, checks the chord each
    // time it shows, and names a binding that already holds it.
    function test_shortcuts_copy_and_conflict() {
        pane.showSection("shortcuts")
        compare(coordinator.summonChecks, 1)
        compare(findChild(pane, "summonSnippet").text, Strings.summonBinding)
        verify(!findChild(pane, "summonConflict").visible)
        var copy = findChild(pane, "summonCopy")
        mouseClick(reveal(copy))
        compare(copy.text, "Copied")
        coordinator.summonConflict = "Shell: Toggle media controls"
        var warning = findChild(pane, "summonConflict")
        verify(warning.visible)
        verify(warning.text.indexOf("SUPER + M is already bound to \u201cShell: Toggle media controls\u201d") === 0)
        pane.showSection("general")
        pane.showSection("shortcuts")
        compare(coordinator.summonChecks, 2)
    }
    // The battery master switch says what it really governs, and every
    // battery row follows it: off, UPower is not read, so the gauge and the
    // alerts cannot show whatever their own switches say.
    function test_battery_rows_follow_the_master_switch() {
        pane.showSection("battery")
        compare(Settings.sections().filter(function (s) { return s.id === "battery" })[0].keys[0], "power")
        compare(Settings.entry("power").label, "Battery and charger")
        verify(Settings.entry("power").help.indexOf("hides the gauge") >= 0)
        var rows = ["showBatteryIndicator", "showBatteryPercent", "showPowerNotifications", "showPowerStatusIcons", "powerStyle"]
        rows.forEach(function (key) { verify(findChild(pane, "settingControl-" + key).enabled, key + " live by default") })
        mouseClick(reveal(input("power")))
        compare(coordinator.settings.power, false)
        rows.forEach(function (key) {
            verify(!findChild(pane, "settingControl-" + key).enabled, key + " dims with the master switch off")
        })
        mouseClick(reveal(input("power")))
        mouseClick(reveal(input("showBatteryIndicator")))
        verify(!findChild(pane, "settingControl-showBatteryPercent").enabled, "no gauge, no percentage")
        verify(findChild(pane, "settingControl-showPowerNotifications").enabled, "alerts do not need the gauge")
    }
    function test_idle_rows_follow_style_and_calendar_choices() {
        pane.showSection("appearance")
        verify(findChild(pane, "settingControl-idleClock").enabled)
        verify(findChild(pane, "settingControl-idleHairline").enabled)
        coordinator.configure({ idleStyle: "horizon" })
        verify(!findChild(pane, "settingControl-idleClock").enabled)
        verify(!findChild(pane, "settingControl-idleHairline").enabled)
        coordinator.configure({ idleStyle: "glance" })
        pane.showSection("calendar")
        verify(!findChild(pane, "settingControl-idleNextEvent").enabled,
            "an idle event needs Calendar on Home")
        coordinator.configure({ showCalendar: true })
        verify(findChild(pane, "settingControl-idleNextEvent").enabled)
        verify(!findChild(pane, "settingControl-idleEventTitles").enabled,
            "event titles need the idle event switch too")
        coordinator.configure({ idleNextEvent: true })
        verify(findChild(pane, "settingControl-idleEventTitles").enabled)
    }
    // Long sections read in named groups, and every key still appears once.
    function test_long_sections_have_sub_headings() {
        pane.showSection("general")
        var labels = ["Bar", "Opening", "Gestures", "Displays"]
        for (var i = 0; i < labels.length; ++i) {
            var heading = findChild(pane, "settingsGroup-" + labels[i])
            verify(heading && heading.visible, labels[i] + " heading")
        }
        var general = Settings.sections().filter(function (s) { return s.id === "general" })[0]
        compare(general.keys.slice(0, 3), ["autoShow", "island", "openOnHover"])
        var flat = []
        general.groups.forEach(function (g) { flat = flat.concat(g.keys) })
        compare(flat, general.keys)
        pane.showSection("battery")
        verify(!findChild(pane, "settingsGroup-Bar"), "a section without groups has no heading")
    }

    function test_switch_edit_writes_through_configure() {
        var toggle = input("island")
        verify(toggle.checked, "island shows its default, on")
        mouseClick(reveal(toggle))
        compare(coordinator.calls, [{ island: false }])
        compare(coordinator.settings.island, false)
        verify(!toggle.checked)
        verify(!findChild(pane, "settingError-island").visible)
    }

    // Keys move the slider at once but save once they rest: holding a key
    // writes the file one time, not once per step.
    function test_slider_keys_save_once_they_rest() {
        var slider = findChild(pane, "settingSlider-hoverDwell")
        verify(slider)
        compare(slider.value, 300)
        compare(findChild(pane, "settingNumber-hoverDwell").text, "300")
        compare(findChild(pane, "settingUnit-hoverDwell").text, "ms")
        slider.forceActiveFocus()
        for (var i = 0; i < 5; ++i) keyClick(Qt.Key_Right)
        compare(slider.value, 305)
        compare(findChild(pane, "settingNumber-hoverDwell").text, "305")
        compare(coordinator.calls, [], "nothing is saved while the keys are moving")
        verify(slider.calming)
        tryCompare(coordinator, "calls", [{ hoverDwell: 305 }], 1500)
        compare(coordinator.fileSettings.hoverDwell, 305)
        // Page Up and Down move a tenth of the range; Home and End the ends.
        keyClick(Qt.Key_PageUp)
        compare(slider.value, 405)
        keyClick(Qt.Key_End)
        compare(slider.value, 1000)
        keyClick(Qt.Key_Home)
        compare(slider.value, 0)
        // Leaving the slider saves at once.
        findChild(pane, "settingNumber-hoverDwell").forceActiveFocus()
        compare(coordinator.calls.length, 2)
        compare(coordinator.fileSettings.hoverDwell, 0)
        verify(!slider.calming)
    }
    // The exact value can be typed; out of range, the typing stays and the
    // row names the range.
    function test_slider_number_can_be_typed() {
        pane.showSection("general")
        var field = findChild(pane, "settingNumber-summonAutoClose")
        var slider = findChild(pane, "settingSlider-summonAutoClose")
        field.forceActiveFocus()
        field.selectAll()
        keyClick(Qt.Key_Delete)
        "4250".split("").forEach(function (digit) { keyClick(digit) })
        keyClick(Qt.Key_Return)
        compare(coordinator.calls, [{ summonAutoClose: 4250 }])
        compare(slider.value, 4250)
        field.selectAll()
        "20000".split("").forEach(function (digit) { keyClick(digit) })
        keyClick(Qt.Key_Return)
        compare(coordinator.fileSettings.summonAutoClose, 4250)
        compare(field.text, "20000", "an out-of-range number stays to be corrected")
        compare(findChild(pane, "settingError-summonAutoClose").text, "Enter a number from 0 to 10000.")
        field.selectAll()
        "abc".split("").forEach(function (letter) { keyClick(letter) })
        keyClick(Qt.Key_Return)
        compare(field.text, "4250", "text that is not a number goes back to the value")
        compare(coordinator.calls.length, 2)
        // An outside change reaches the focused field, and leaving it then
        // saves nothing, since nothing was typed.
        coordinator.configure({ summonAutoClose: 1200 })
        compare(field.text, "1200")
        findChild(pane, "settingSlider-summonAutoClose").forceActiveFocus()
        compare(coordinator.calls.length, 3)
        compare(coordinator.fileSettings.summonAutoClose, 1200)
    }
    // Every number with a unit shows it.
    function test_numbers_name_their_unit() {
        var units = { hudDuration: "ms", shelfLimit: "items", calendarRefresh: "min", dragCatchWidth: "px" }
        for (var key in units) compare(Settings.entry(key).unit, units[key], key)
    }

    function test_refused_edit_reverts_and_says_so() {
        coordinator.refuse = true
        var toggle = input("island")
        mouseClick(reveal(toggle))
        compare(coordinator.calls.length, 1)
        verify(toggle.checked, "the switch snaps back to the stored value")
        verify(findChild(pane, "settingError-island").visible)
        compare(findChild(pane, "settingError-island").text,
            "Not saved: settings.json could not be written. Check that ~/.config/nookisle is writable.",
            "a failed save says so, rather than blaming the value")
        coordinator.refuse = false
        mouseClick(reveal(toggle))
        verify(!findChild(pane, "settingError-island").visible)
    }

    function test_outside_changes_reach_the_controls() {
        pane.showSection("media")
        var toggle = input("lyrics")
        verify(!toggle.checked)
        coordinator.settings = { lyrics: true }
        verify(toggle.checked)
        coordinator.fileSettings = Settings.resolve({ hoverDwell: 700 })
        pane.showSection("general")
        compare(findChild(pane, "settingSlider-hoverDwell").value, 700)
    }

    function test_enum_string_and_list_controls() {
        var recorder = createTemporaryObject(recorderComponent, test)
        var choice = createTemporaryObject(controlComponent, test, { coordinator: recorder,
            spec: { key: "sliderColor", type: "enum", values: ["white", "albumArt", "accent"], default: "white",
                label: "Slider colour", help: "Colour of the scrubber" }, value: "white" })
        var accent = findChild(choice, "settingChoice-sliderColor-accent")
        verify(accent && !accent.checked)
        verify(findChild(choice, "settingChoice-sliderColor-white").checked)
        mouseClick(reveal(accent))
        compare(recorder.calls, [{ sliderColor: "accent" }])

        var text = createTemporaryObject(controlComponent, test, { coordinator: recorder,
            spec: { key: "backlightDevice", type: "string", default: "", max: 64,
                label: "Backlight", help: "Device name" }, value: "" })
        var field = text.input
        field.forceActiveFocus()
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_Return)
        compare(recorder.calls[1], { backlightDevice: "a" })

        var list = createTemporaryObject(controlComponent, test, { coordinator: recorder,
            spec: { key: "musicControlSlots", type: "list", values: ["previous", "play", "next"], max: 3,
                default: [], label: "Controls", help: "Toolbar slots" }, value: ["play", "next"] })
        list.input.moveSlot(0, 1)
        compare(recorder.calls[2], { musicControlSlots: ["next", "play"] })

        var other = createTemporaryObject(controlComponent, test, { coordinator: recorder,
            spec: { key: "calendarSources", type: "sources", default: [], label: "Sources", help: "Calendars" } })
        verify(other.input && findChild(other.input, "calendarAdd"),
            "the sources type hosts the calendar source editor")
        compare(other.input.coordinator, recorder, "which writes through the same coordinator")
    }
    function test_calendarSelectionUsesConfiguredSources() {
        var local = { kind: "file", path: "/home/me/work.ics" }
        var remote = { kind: "ics-url", url: "https://calendar.example/private-feed.ics" }
        coordinator.fileSettings = Settings.resolve({ showCalendar: true, calendarSources: [local, remote] })
        pane.showSection("calendar")
        var control = input("calendarSelection")
        var all = findChild(control, "calendarFilterAll")
        var first = findChild(control, "calendarFilter-0")
        var second = findChild(control, "calendarFilter-1")
        verify(all && first && second)
        verify(all.checked)
        compare(second.text, "calendar.example (link hidden)", "a private URL is not displayed")
        mouseClick(reveal(first))
        compare(coordinator.fileSettings.calendarSelection, [Calendar.sourceId(local)])
        verify(first.checked && !all.checked)
        mouseClick(reveal(second))
        compare(coordinator.fileSettings.calendarSelection, [Calendar.sourceId(local), Calendar.sourceId(remote)])
        mouseClick(reveal(first))
        compare(coordinator.fileSettings.calendarSelection, [Calendar.sourceId(remote)])
        mouseClick(reveal(all))
        compare(coordinator.fileSettings.calendarSelection, [])
        verify(all.checked)
        coordinator.refuse = true
        mouseClick(reveal(second))
        compare(coordinator.fileSettings.calendarSelection, [], "refused filter is not applied")
        verify(findChild(pane, "settingError-calendarSelection").visible)
    }
    function test_toolbar_reset_uses_the_schema_default() {
        pane.showSection("media")
        coordinator.fileSettings = Settings.resolve({ musicControlSlots: ["previous", "playPause", "next"] })
        var reset = findChild(pane, "slotReset")
        verify(reset && reset.visible && reset.enabled)
        mouseClick(reveal(reset))
        compare(coordinator.fileSettings.musicControlSlots,
            ["shuffle", "previous", "playPause", "next", "repeat"])
        verify(!reset.enabled)
    }
    // Every button in the window draws with the island tokens and wears the
    // accent focus ring, the reset, the project link and the calendar
    // filters included.
    function test_every_settings_button_uses_the_island_tokens() {
        function checkButton(button, name) {
            verify(button, name + " exists")
            var fill = findChild(button, "settingButtonFill")
            verify(fill, name + " draws the island button fill")
            button.forceActiveFocus(Qt.TabFocusReason)
            compare(fill.border.width, design.focusWidth, name + " shows the focus ring")
            compare(fill.border.color, button.checked ? design.primaryLabel : design.accent)
        }
        pane.showSection("media")
        coordinator.fileSettings = Settings.resolve({ musicControlSlots: ["previous", "playPause", "next"] })
        checkButton(findChild(pane, "slotReset"), "reset")
        var manifest = coordinator.manifest
        coordinator.manifest = ({ version: "1.0.0", repository: "https://github.com/bavanchun/nookisle" })
        pane.showSection("about")
        var link = findChild(pane, "settingsProjectLink")
        verify(link.visible)
        checkButton(link, "project link")
        coordinator.manifest = manifest
        coordinator.fileSettings = Settings.resolve({ showCalendar: true, calendarSources: [{ kind: "file", path: "/home/me/work.ics" }] })
        pane.showSection("calendar")
        var control = input("calendarSelection")
        checkButton(findChild(control, "calendarFilterAll"), "all calendars")
        checkButton(findChild(control, "calendarFilter-0"), "a calendar filter")
    }

    // A screen setting offers Automatic, the connected screens, and the
    // stored screen when it is not connected, marked as such.
    function test_screen_control_offers_the_connected_screens() {
        var recorder = createTemporaryObject(recorderComponent, test)
        var control = createTemporaryObject(controlComponent, test, { coordinator: recorder,
            spec: Settings.entry("preferredDisplay"), value: "HDMI-A-1", screens: ["eDP-1", "DP-2"] })
        var automatic = findChild(control, "settingChoice-preferredDisplay-automatic")
        var laptop = findChild(control, "settingChoice-preferredDisplay-eDP-1")
        var stored = findChild(control, "settingChoice-preferredDisplay-HDMI-A-1")
        verify(automatic && laptop && findChild(control, "settingChoice-preferredDisplay-DP-2"))
        compare(automatic.text, "Automatic")
        compare(stored.text, "HDMI-A-1 (not connected)")
        verify(stored.checked, "the stored screen stays selected while it is away")
        mouseClick(laptop)
        compare(recorder.calls, [{ preferredDisplay: "eDP-1" }])
        mouseClick(automatic)
        compare(recorder.calls[1], { preferredDisplay: "" })
    }
    function test_slot_editor_api() {
        var editor = createTemporaryObject(slotComponent, test)
        editor.moveSlot(0, 2)
        compare(editor.edits[0], ["play", "next", "previous"])
        editor.moveSlot(1, 1)
        editor.moveSlot(0, 3)
        compare(editor.edits.length, 1, "no-op and out-of-range moves emit nothing")
        editor.insertItem("shuffle", 1)
        compare(editor.edits[1], ["previous", "shuffle", "play", "next"])
        editor.insertItem("play", 0)
        editor.insertItem("bogus", 0)
        compare(editor.edits.length, 2, "a used or unknown word is not inserted")
        editor.value = ["previous", "shuffle", "play", "next"]
        editor.insertItem("repeat", 3)
        compare(editor.edits[2], ["previous", "shuffle", "play", "repeat"], "a full list replaces")
        editor.insertItem("repeat", 4)
        compare(editor.edits.length, 3, "a full list cannot append")
        editor.removeAt(1)
        compare(editor.edits[3], ["previous", "play", "next"])
        compare(editor.unused, ["repeat"])
    }

    function dragOnto(editor, sourceName, targetName) {
        var source = findChild(editor, sourceName)
        var target = findChild(editor, targetName)
        verify(source && target, sourceName + " and " + targetName)
        var from = source.mapToItem(test, source.width / 2, source.height / 2)
        var to = target.mapToItem(test, target.width / 2, target.height / 2)
        mousePress(test, from.x, from.y)
        var steps = 8
        for (var i = 1; i <= steps; ++i)
            mouseMove(test, from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps)
        mouseRelease(test, to.x, to.y)
    }

    function test_slot_editor_drag_reorders_inserts_and_trashes() {
        var editor = createTemporaryObject(slotComponent, test, { y: 200 })
        waitForRendering(editor)
        dragOnto(editor, "slotChip-0", "slotChip-2")
        compare(editor.edits[0], ["play", "next", "previous"], "a slot dropped on another moves there")
        verify(findChild(editor, "slotChip-0").x === 0, "the dragged chip returns to its slot")
        dragOnto(editor, "paletteChip-shuffle", "slotTail")
        compare(editor.edits[1], ["previous", "play", "next", "shuffle"], "a palette word dropped at the end appends")
        dragOnto(editor, "slotChip-1", "slotTrash")
        compare(editor.edits[2], ["previous", "next"], "a slot dropped on the trash is removed")
    }
}
