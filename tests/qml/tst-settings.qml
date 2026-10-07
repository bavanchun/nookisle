import QtQuick
import QtTest
import "../../qml/Settings.js" as Settings

TestCase {
    name: "Settings"

    readonly property var legacyKeys: ["autoShow", "reducedMotion", "highContrast", "remoteArtwork",
        "hud", "visualizer", "peek", "tint", "power", "lyrics"]

    function test_every_entry_is_complete() {
        var seen = {}
        var sectionIds = Settings.SECTIONS.map(function (section) { return section.id })
        for (var i = 0; i < Settings.SCHEMA.length; ++i) {
            var spec = Settings.SCHEMA[i]
            verify(!seen[spec.key], "unique key " + spec.key)
            seen[spec.key] = true
            verify(Settings.TYPES.indexOf(spec.type) >= 0, spec.key + " has a known type")
            verify(spec.store === "shell" || spec.store === "file", spec.key + " has a store")
            verify(sectionIds.indexOf(spec.section) >= 0, spec.key + " has a known section")
            verify(typeof spec.label === "string" && spec.label.length > 0, spec.key + " has a label")
            verify(typeof spec.help === "string" && spec.help.length > 0, spec.key + " has help")
            verify(Settings.check(spec, spec.default), spec.key + " default is valid")
            if (spec.type === "enum" || (spec.type === "list" && Array.isArray(spec.values))) {
                verify(Array.isArray(spec.values) && spec.values.length > 0, spec.key + " lists its values")
                for (var j = 0; j < spec.values.length; ++j) {
                    var shown = Settings.valueLabel(spec, spec.values[j])
                    var labels = Settings.VALUE_LABELS[spec.key]
                    verify(labels && labels[spec.values[j]] === shown && shown.length > 0,
                        spec.key + " names " + spec.values[j] + " for people")
                }
            }
        }
    }

    function test_legacy_keys_stay_booleans_in_the_shell_store() {
        compare(Settings.keys("shell"), legacyKeys)
        for (var i = 0; i < legacyKeys.length; ++i)
            compare(Settings.entry(legacyKeys[i]).type, "bool")
        var fileKeys = Settings.keys("file")
        compare(Settings.keys(), legacyKeys.concat(fileKeys))
    }

    function test_defaults() {
        var all = Settings.defaults()
        compare(Object.keys(all), Settings.keys())
        compare(Settings.entry("island"), null, "the removed island toggle is not a setting")
        compare(all.hud, false)
        compare(all.lyrics, false)
        compare(all.remoteArtwork, false)
        compare(all.peek, false)
        compare(all.hoverDwell, 300)
        compare(all.openOnHover, true)
        compare(all.rememberLastTab, false)
        compare(all.leaveGrace, 100)
        compare(all.backlightDevice, "")
        compare(all.fullscreenBehavior, "nowPlayingOnly")
        compare(all.showBatteryIndicator, true)
        compare(all.showBatteryPercent, true)
        compare(all.showPowerNotifications, true)
        compare(all.showPowerStatusIcons, true)
        compare(all.powerStyle, "banner")
        compare(all.alwaysShowTabs, true)
        compare(all.showSettingsIcon, true)
        compare(all.useCustomAccentColor, false)
        compare(all.customAccentColor, "#a9c7ff")
        compare(all.windowShadow, true)
        compare(all.extendHoverArea, false)
        compare(all.openShelfByDefault, true)
        compare(all.shelfEnabled, true)
        compare(all.enableGestures, true)
        compare(all.closeGesture, true)
        compare(all.gestureTravel, 200)
        compare(all.summonAutoClose, 3000)
        compare(all.sliderColor, "albumArt")
        compare(all.peekStyle, "standard")
        compare(all.pauseGrace, 3000)
        compare(Settings.entry("pauseGrace").label, "Media inactivity timeout")
        compare(all.hudStyle, "inline")
        compare(all.showOpenNotchHud, true)
        compare(all.hudPercentClosed, false)
        compare(all.hudPercentOpen, true)
        compare(all.hudDuration, 1500)
        compare(all.hudAccent, false)
        compare(all.hudGradient, false)
        compare(all.hudGlow, false)
        compare(all.showCalendar, false)
        compare(all.calendarRefresh, 15)
        compare(all.calendarSources, [])
        compare(all.showMirror, false)
        compare(all.mirrorShape, "rectangle")
        compare(all.showIdleFace, false)
        compare(all.idleStyle, "glance")
        compare(all.idleClock, "auto")
        compare(all.idleHairline, true)
        compare(all.idleNextEvent, false, "the next event in the closed notch is opt-in")
        compare(all.idleEventTitles, false, "and so are its titles")
        compare(all.hardwareNotch, false)
        compare(all.privacyIndicators, true, "privacy indicators are local only, and on by default")
        compare(all.deviceEvents, "audio", "audio devices peek by default; a mouse reconnecting does not")
        compare(all.outputPeek, true)
        compare(all.timers, true)
        compare(all.recordingActivity, true)
        compare(all.recordingsToShelf, false, "shelving recordings is opt-in")
        compare(all.screenshotsToShelf, false, "and so is shelving screenshots")
        compare(all.screenshotDir, "")
        verify(Settings.validate("screenshotDir", "/home/me/Shots"))
        verify(!Settings.validate("screenshotDir", "Shots"), "a folder must be absolute")
        compare(all.timerPresets, [5, 10, 25, 60])
        verify(Settings.validate("timerPresets", [7, 1, 1440]), "any whole minutes from 1 to 1440")
        verify(Settings.validate("timerPresets", []))
        verify(!Settings.validate("timerPresets", [0]))
        verify(!Settings.validate("timerPresets", [1441]))
        verify(!Settings.validate("timerPresets", [2.5]))
        verify(!Settings.validate("timerPresets", ["5"]), "numbers, not words")
        verify(!Settings.validate("timerPresets", [1, 2, 3, 4, 5, 6, 7]), "at most six")
        compare(Object.keys(Settings.defaults("file")), Settings.keys("file"))
        compare(Object.keys(Settings.defaults("shell")), legacyKeys)
    }

    function test_validate_known_keys() {
        verify(!Settings.validate("island", false), "the removed island toggle is rejected by configure")
        verify(Settings.validate("autoShow", false))
        verify(!Settings.validate("autoShow", "false"))
        verify(Settings.validate("hoverDwell", 0))
        verify(Settings.validate("hoverDwell", 1000))
        verify(!Settings.validate("hoverDwell", -1))
        verify(!Settings.validate("hoverDwell", 1001))
        verify(!Settings.validate("hoverDwell", 12.5))
        verify(!Settings.validate("hoverDwell", "300"))
        verify(!Settings.validate("hoverDwell", NaN))
        verify(Settings.validate("backlightDevice", "intel_backlight"))
        verify(!Settings.validate("backlightDevice", "../other"))
        verify(!Settings.validate("backlightDevice", ".."))
        verify(Settings.validate("fullscreenBehavior", "always"))
        verify(Settings.validate("fullscreenBehavior", "never"))
        verify(!Settings.validate("fullscreenBehavior", "sometimes"))
        verify(Settings.validate("showBatteryIndicator", true))
        verify(Settings.validate("showBatteryIndicator", false))
        verify(!Settings.validate("showBatteryIndicator", "true"))
        verify(Settings.validate("showBatteryPercent", true))
        verify(Settings.validate("showBatteryPercent", false))
        verify(!Settings.validate("showBatteryPercent", 1))
        verify(Settings.validate("powerStyle", "banner"))
        verify(Settings.validate("powerStyle", "peek"))
        verify(!Settings.validate("powerStyle", "inline"))
        verify(!Settings.validate("powerStyle", true))
        verify(Settings.validate("customAccentColor", "#12aBcD"))
        verify(!Settings.validate("customAccentColor", "red"))
        verify(!Settings.validate("customAccentColor", "#1234"))
        verify(Settings.validate("gestureTravel", 100))
        verify(Settings.validate("gestureTravel", 300))
        verify(!Settings.validate("gestureTravel", 99))
        verify(!Settings.validate("gestureTravel", 301))
        verify(Settings.validate("summonAutoClose", 0), "0 means never")
        verify(Settings.validate("peekStyle", "inline"))
        verify(!Settings.validate("peekStyle", "compact"))
        verify(Settings.validate("pauseGrace", 0))
        verify(!Settings.validate("pauseGrace", 10001))
        verify(!Settings.validate("mediaInactivityTimeout", 3000))
        verify(!Settings.validate("summonAutoClose", -1))
        verify(!Settings.validate("alwaysShowTabs", 1))
        verify(Settings.validate("hudStyle", "below"))
        verify(!Settings.validate("hudStyle", "above"))
        verify(Settings.validate("hudDuration", 250))
        verify(Settings.validate("hudDuration", 5000))
        verify(!Settings.validate("hudDuration", 249))
        verify(!Settings.validate("hudDuration", 5001))
        verify(Settings.validate("mirrorShape", "circle"))
        verify(Settings.validate("mirrorShape", "rectangle"))
        verify(!Settings.validate("mirrorShape", "square"))
        verify(Settings.validate("idleStyle", "horizon"))
        verify(!Settings.validate("idleStyle", "clock"))
        verify(Settings.validate("idleClock", "off"))
        verify(!Settings.validate("idleClock", "seconds"))
        verify(Settings.validate("showIdleFace", true))
        verify(!Settings.validate("showIdleFace", "true"))
        verify(Settings.validate("dragCatchWidth", 120))
        verify(!Settings.validate("dragCatchWidth", 119))
        verify(!Settings.validate("dragCatchWidth", 1601))
        verify(Settings.validate("expandedDragDetection", false))
        verify(!Settings.validate("unknown", true))
        verify(!Settings.validate("constructor", true))
    }

    function test_check_every_type() {
        var real = { type: "real", min: 0, max: 1 }
        verify(Settings.check(real, 0.5))
        verify(!Settings.check(real, 1.5))
        verify(!Settings.check(real, Infinity))
        var choice = { type: "enum", values: ["white", "albumArt", "accent"] }
        verify(Settings.check(choice, "albumArt"))
        verify(!Settings.check(choice, "red"))
        verify(!Settings.check(choice, 1))
        var text = { type: "string", max: 4 }
        verify(Settings.check(text, ""))
        verify(Settings.check(text, "abcd"))
        verify(!Settings.check(text, "abcde"))
        verify(!Settings.check(text, null))
        var slots = { type: "list", min: 1, max: 3, values: ["previous", "play", "next"] }
        verify(Settings.check(slots, ["play"]))
        verify(Settings.check(slots, ["previous", "play", "next"]))
        verify(!Settings.check(slots, []))
        verify(!Settings.check(slots, ["previous", "play", "next", "play"]))
        verify(!Settings.check(slots, ["shuffle"]))
        verify(!Settings.check(slots, [1]))
        verify(!Settings.check(slots, "play"))
        verify(Settings.check({ type: "list" }, ["anything"]))
        verify(!Settings.check({ type: "colour" }, "red"))
        verify(!Settings.check(null, true))
    }

    function test_batches_are_all_or_nothing() {
        verify(Settings.validateBatch({}))
        verify(Settings.validateBatch({ autoShow: true, hoverDwell: 450 }))
        verify(!Settings.validateBatch({ autoShow: true, hoverDwell: "x" }))
        verify(!Settings.validateBatch({ autoShow: true, unknown: 1 }))
        verify(!Settings.validateBatch({ hud: "x", leaveGrace: 10 }))
        verify(!Settings.validateBatch(null))
        verify(!Settings.validateBatch([true]))
        verify(!Settings.validateBatch("island"))
    }

    function test_file_load_ignores_stored_island_values_and_keeps_other_keys() {
        compare(Settings.resolve(null), Settings.defaults("file"))
        compare(Settings.resolve([1, 2]), Settings.defaults("file"))
        for (var i = 0; i < 2; ++i) {
            var stored = { hoverDwell: 700, leaveGrace: 80, island: i === 0 }
            var text = JSON.stringify({ version: 1, values: stored })
            var parsed = Settings.parseFile(text)
            compare(parsed.island, i === 0, "the old file itself is valid JSON")
            var notes = []
            var resolved = Settings.resolve(parsed, notes)
            compare(resolved.hoverDwell, 700, "a neighboring valid value survives the removed key")
            compare(resolved.leaveGrace, 80)
            compare(Object.keys(resolved), Settings.keys("file"))
            verify(resolved.island === undefined, "stored island:" + (i === 0) + " is ignored")
            compare(notes, [], "a retired key is ignored without treating the file as corrupt")
            var saved = JSON.parse(Settings.serialise(parsed)).values
            compare(saved.hoverDwell, 700)
            compare(saved.leaveGrace, 80)
            verify(saved.island === undefined, "the next save drops the retired key")
        }
    }

    // Displays: follow by default; a screen setting holds a connector name.
    function test_display_settings() {
        compare(Settings.defaults().displayMode, "follow")
        compare(Settings.entry("displayMode").section, "general")
        compare(Settings.entry("preferredDisplay").section, "general")
        verify(Settings.validate("displayMode", "all"))
        verify(Settings.validate("displayMode", "fixed"))
        verify(!Settings.validate("displayMode", "mirror"))
        verify(Settings.validate("preferredDisplay", ""))
        verify(Settings.validate("preferredDisplay", "eDP-1"))
        verify(Settings.validate("preferredDisplay", "HDMI-A-1"))
        verify(!Settings.validate("preferredDisplay", "../eDP-1"))
        verify(!Settings.validate("preferredDisplay", "DP 2"))
        verify(!Settings.validate("preferredDisplay", 1))
    }
    // A settings file from before idleStyle keeps its idle face; a file
    // that names a style keeps that style, and the old switch is not shown.
    function test_idle_face_migrates_to_the_face_style() {
        compare(Settings.resolve({ showIdleFace: true }).idleStyle, "face")
        compare(Settings.resolve({ showIdleFace: false }).idleStyle, "glance")
        compare(Settings.resolve({}).idleStyle, "glance")
        compare(Settings.resolve({ showIdleFace: true, idleStyle: "horizon" }).idleStyle, "horizon")
        compare(Settings.entry("showIdleFace").internal, true)
        verify(!("showIdleFace" in Settings.publicValues(Settings.defaults("file"))), "and status() leaves it out")
    }
    // configure() still takes the old switch, against settings that already
    // name a style: on selects the face, off returns the face to the glance
    // and leaves any other style alone, and an explicit idleStyle wins.
    function test_show_idle_face_is_a_configure_alias() {
        var current = Settings.defaults("file")
        var on = Settings.applyAliases({ showIdleFace: true }, current)
        compare(on.idleStyle, "face")
        compare(Settings.resolve(Object.assign({}, current, on)).idleStyle, "face")
        var face = Settings.resolve(Object.assign({}, current, on))
        compare(Settings.applyAliases({ showIdleFace: false }, face).idleStyle, "glance")
        var horizon = Object.assign({}, current, { idleStyle: "horizon" })
        compare(Settings.applyAliases({ showIdleFace: false }, horizon).idleStyle, undefined, "another style stays")
        compare(Settings.applyAliases({ showIdleFace: true, idleStyle: "horizon" }, current).idleStyle, "horizon")
        compare(Settings.applyAliases({ hoverDwell: 400 }, current).idleStyle, undefined)
    }
    function test_file_round_trip() {
        var text = Settings.serialise({ hoverDwell: 450, bogus: 1 })
        compare(JSON.parse(text), { version: 1, values: { hoverDwell: 450, openOnHover: true, rememberLastTab: false,
            displayMode: "follow", preferredDisplay: "", leaveGrace: 100,
            onboardingDone: false, backlightDevice: "", fullscreenBehavior: "nowPlayingOnly",
            showBatteryIndicator: true, showBatteryPercent: true, showPowerNotifications: true,
            showPowerStatusIcons: true, powerStyle: "banner",
            alwaysShowTabs: true, followDesktopMotion: true, showSettingsIcon: true,
            uiFont: "sans", openShelfByDefault: true,
            enableGestures: true, closeGesture: true, gestureTravel: 200,
            summonAutoClose: 3000, lightingEffect: true, sliderColor: "albumArt",
            peekStyle: "standard",
            musicControlSlots: ["shuffle", "previous", "playPause", "next", "repeat"],
            musicControlSlotLimit: 5, pauseGrace: 3000, musicLiveActivity: true,
            coloredSpectrogram: true, showCalendar: false, showMirror: false,
            calendarRefresh: 15, calendarSources: [], hideCompletedReminders: true,
            hideAllDayEvents: false, autoScrollToNextEvent: true, showFullEventTitles: false,
            calendarPendingClears: [], calendarSelection: [],
            hudStyle: "inline", showOpenNotchHud: true, hudPercentClosed: false,
            hudPercentOpen: true, hudDuration: 1500, hudAccent: false, hudGradient: false, hudGlow: false,
            shelfLimit: 64, shelfEnabled: true, shelfPersist: false, copyOnDrag: false,
            autoRemoveShelfItems: false, shareProvider: "auto",
            preferredSource: "", mirrorShape: "rectangle", deviceEvents: "audio", outputPeek: true, timers: true,
            timerPresets: [5, 10, 25, 60], recordingActivity: true, privacyIndicators: true, hardwareNotch: false,
            idleStyle: "glance", idleClock: "auto",
            idleHairline: true, idleNextEvent: false, idleEventTitles: false, showIdleFace: false,
            useCustomAccentColor: false, customAccentColor: "#a9c7ff", windowShadow: true,
            extendHoverArea: false, screenshotsToShelf: false, screenshotDir: "", recordingsToShelf: false,
            expandedDragDetection: true, dragCatchWidth: 480 } })
        compare(Object.keys(JSON.parse(text).values), Settings.keys("file"))
        compare(Settings.resolve(Settings.parseFile(text)).hoverDwell, 450)
        compare(Settings.parseFile("{ not json"), null)
        compare(Settings.parseFile(JSON.stringify({ version: 2, values: { hoverDwell: 1 } })), null)
        compare(Settings.parseFile("null"), null)
        compare(Settings.resolve(Settings.parseFile("{ not json")), Settings.defaults("file"))
    }

    function test_calendar_sources_are_bounded_and_redacted() {
        var sources = [{ kind: "file", path: "/tmp/calendar.ics" },
                       { kind: "vdir", path: "/tmp/calendar" },
                       { kind: "ics-url", url: "https://example.com/private.ics" },
                       { kind: "caldav", url: "https://example.com/dav/", user: "person" }]
        verify(Settings.validate("calendarSources", sources))
        verify(!Settings.validate("calendarSources", [{ kind: "caldav", url: "https://example.com/dav/" }]))
        verify(!Settings.validate("calendarSources", [{ kind: "file", path: "relative.ics" }]))
        verify(!Settings.validate("calendarSources", [{ kind: "ics-url", url: "http://example.com/private.ics" }]))
        verify(!Settings.validate("calendarSources", [{ kind: "caldav", url: "https://example.com", user: "x", password: "never" }]))
        var values = Settings.resolve({ calendarSources: sources })
        compare(values.calendarSources, sources)
        compare(Settings.publicValues(values).calendarSources, undefined)
        sources[0].path = "/changed"
        compare(values.calendarSources[0].path, "/tmp/calendar.ics")
    }

    // A user name or password inside a source URL would put a credential in
    // the settings file. configure() refuses it whole; a hand-edited file
    // loses only that source, with a note that never repeats the URL.
    function test_calendar_source_urls_never_carry_userinfo() {
        var good = { kind: "file", path: "/tmp/calendar.ics" }
        var account = { kind: "caldav", url: "https://me:fixture-secret@cloud.example.com/dav/", user: "me" }
        var link = { kind: "ics-url", url: "https://token-secret@calendar.example/basic.ics" }
        verify(!Settings.validate("calendarSources", [account]), "configure() refuses a password in the URL")
        verify(!Settings.validate("calendarSources", [link]), "and a bare user name")
        verify(!Settings.validateBatch({ calendarSources: [good, account] }))
        verify(Settings.validate("calendarSources",
            [{ kind: "ics-url", url: "https://calendar.example/basic.ics?a=b@c" }]), "an @ after the host is fine")
        var notes = []
        var values = Settings.resolve({ calendarSources: [good, account, link], hoverDwell: 400 }, notes)
        compare(values.calendarSources, [good], "a hand-edited file keeps its other sources")
        compare(values.hoverDwell, 400)
        compare(notes.length, 1)
        compare(notes[0].key, "calendarSources")
        compare(notes[0].dropped, 2)
        var text = Settings.noteText(notes)
        verify(text.indexOf("2 calendar sources") >= 0, text)
        verify(text.indexOf("password field") >= 0, text)
        var serialised = JSON.stringify(notes) + text
        verify(serialised.indexOf("fixture-secret") < 0 && serialised.indexOf("token-secret") < 0
            && serialised.indexOf("cloud.example.com") < 0, "the note never repeats a URL")
        compare(Settings.serialise({ calendarSources: [good, account] }).indexOf("fixture-secret"), -1,
            "the next save rewrites the file without it")
        compare(Settings.resolve({ calendarSources: [good] }, []).calendarSources, [good])
        compare(Settings.noteText([]), "")
    }

    function test_sections_cover_every_key_once() {
        var sections = Settings.sections()
        compare(sections.map(function (section) { return section.id }),
            Settings.SECTIONS.map(function (section) { return section.id }))
        var listed = []
        for (var i = 0; i < sections.length; ++i) {
            verify(sections[i].label.length > 0)
            listed = listed.concat(sections[i].keys)
        }
        var shown = Settings.SCHEMA.filter(function (spec) { return !spec.internal && spec.key !== "onboardingDone" })
            .map(function (spec) { return spec.key })
        compare(listed.slice().sort(), shown.sort(), "every key but the internal ones and the welcome's flag")
        var calendar = sections.filter(function (section) { return section.id === "calendar" })[0]
        compare(calendar.keys, ["showCalendar", "calendarRefresh", "calendarSources",
            "hideCompletedReminders", "hideAllDayEvents", "autoScrollToNextEvent",
            "showFullEventTitles", "calendarSelection", "idleNextEvent", "idleEventTitles"])
    }

    function test_pending_clears_are_internal_identifiers() {
        var spec = Settings.entry("calendarPendingClears")
        verify(spec && spec.internal === true && spec.store === "file")
        compare(spec.default, [])
        verify(Settings.validate("calendarPendingClears", [{ kind: "caldav", url: "https://cloud.example.com/dav/", user: "me" }]))
        verify(!Settings.validate("calendarPendingClears", [{ kind: "caldav", url: "https://cloud.example.com/dav/", user: "me", password: "x" }]),
            "no field beyond a source's identifiers, so never a password")
        verify(!("calendarPendingClears" in Settings.publicValues(Settings.defaults("file"))), "and never in status()")
        verify(Settings.sections().every(function (section) { return section.keys.indexOf("calendarPendingClears") < 0 }))
    }
}
