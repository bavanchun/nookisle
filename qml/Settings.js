.pragma library

// The one settings schema. configure() and the settings UI validate through
// it, and the source contract reads it as the only list of setting keys.
//
// Each entry: key, type (bool | int | real | enum | string | list | sources), default,
// optional min/max (bounds for numbers, length for strings and lists),
// values (the allowed words of an enum, or of each list item), section,
// label and help, and optionally unit (shown after a number's value).
// store says where the value lives: "shell" is the host's
// shell.json bar entry, where the eleven original booleans have always been;
// "file" is the plugin's own settings.json, for every later key.

// The settings window's sidebar, in order. Shortcuts and About hold fixed
// content rather than keys.
var SECTIONS = [
    { id: "general", label: "General" },
    { id: "appearance", label: "Appearance" },
    { id: "media", label: "Media" },
    { id: "calendar", label: "Calendar" },
    { id: "hud", label: "HUD" },
    { id: "battery", label: "Battery" },
    { id: "shelf", label: "Shelf" },
    { id: "shortcuts", label: "Shortcuts" },
    { id: "advanced", label: "Advanced" },
    { id: "about", label: "About" }
]

var SCHEMA = [
    { key: "autoShow", type: "bool", default: true, store: "shell", section: "general",
        label: "Show in the status bar", help: "Quick access from the bar" },
    { key: "reducedMotion", type: "bool", default: false, store: "shell", section: "appearance",
        label: "Reduce motion", help: "Turn off transition effects, and show a still glyph in place of the live spectrum" },
    { key: "highContrast", type: "bool", default: false, store: "shell", section: "appearance",
        label: "High contrast", help: "Opaque surfaces and clear borders" },
    { key: "remoteArtwork", type: "bool", default: false, store: "shell", section: "media",
        label: "Online artwork", help: "Download cover art from the web; a player's local cover file always shows" },
    { key: "island", type: "bool", default: true, store: "shell", section: "general",
        label: "Dynamic island", help: "Show the player as a pill over the bar centre" },
    { key: "hud", type: "bool", default: false, store: "shell", section: "hud",
        label: "Level readout", help: "Show volume and brightness changes in the island" },
    { key: "visualizer", type: "bool", default: true, store: "shell", section: "media",
        label: "Live spectrum", help: "Animate the island with the music that is playing" },
    { key: "peek", type: "bool", default: false, store: "shell", section: "media",
        label: "Track peek", help: "Briefly show the new track when it changes" },
    { key: "tint", type: "bool", default: true, store: "shell", section: "appearance",
        label: "Artwork colours", help: "Tint the island with the cover art's colour" },
    { key: "power", type: "bool", default: true, store: "shell", section: "battery",
        label: "Battery and charger", help: "Read the battery through UPower. Off hides the gauge and every power notification" },
    { key: "lyrics", type: "bool", default: false, store: "shell", section: "media",
        label: "Synced lyrics", help: "Look up lyrics on lrclib.net (sends title, artist, album and length)" },
    { key: "hoverDwell", type: "int", default: 300, min: 0, max: 1000, store: "file", unit: "ms", section: "general",
        label: "Open delay", help: "Milliseconds the pointer rests on the island before it opens" },
    { key: "openOnHover", type: "bool", default: true, store: "file", section: "general",
        label: "Open on hover", help: "Open the island after the pointer rests on it" },
    { key: "rememberLastTab", type: "bool", default: false, store: "file", section: "general",
        label: "Remember last tab", help: "Reopen on the tab used before closing" },
    { key: "displayMode", type: "enum", default: "follow", values: ["follow", "all", "fixed"], store: "file", section: "general",
        label: "Displays", help: "Follow the focused screen, show on every screen, or stay on one screen" },
    { key: "preferredDisplay", type: "screen", default: "", max: 128, store: "file", section: "general",
        label: "Screen", help: "The screen for Fixed, and the one that takes the keyboard summon with every screen" },
    { key: "leaveGrace", type: "int", default: 100, min: 0, max: 1000, store: "file", unit: "ms", section: "general",
        label: "Close delay", help: "Milliseconds the island stays open after the pointer leaves" },
    { key: "onboardingDone", type: "bool", default: false, store: "file", section: "advanced",
        label: "Welcome finished", help: "Turn off to show the welcome steps again at the next start" },
    { key: "backlightDevice", type: "string", default: "", max: 128, store: "file", section: "hud",
        label: "Display backlight device", help: "Leave empty to use the first available display backlight" },
    { key: "fullscreenBehavior", type: "enum", default: "nowPlayingOnly",
        values: ["always", "nowPlayingOnly", "never"], store: "file", section: "general",
        label: "Hide over fullscreen", help: "Always, only for the selected player's app, or never" },
    // Battery: the header gauge, and how a charger change is shown.
    { key: "showBatteryIndicator", type: "bool", default: true, store: "file", section: "battery",
        label: "Battery gauge", help: "Show the battery level in the open island's header" },
    { key: "showBatteryPercent", type: "bool", default: true, store: "file", section: "battery",
        label: "Battery percentage", help: "Show the percentage beside the battery gauge" },
    { key: "showPowerNotifications", type: "bool", default: true, store: "file", section: "battery",
        label: "Charger and battery alerts", help: "Show charger changes and low-battery warnings in the closed island; the gauge stays" },
    { key: "showPowerStatusIcons", type: "bool", default: true, store: "file", section: "battery",
        label: "Battery status icons", help: "Show charging, low-battery and power-saver marks in the gauge" },
    { key: "powerStyle", type: "enum", default: "banner", values: ["banner", "peek"], store: "file", section: "battery",
        label: "Charger and battery warnings", help: "A wide banner across the notch, or the smaller peek card, for charger changes and 20 % or 10 % battery" },
    // The open island: gestures, tabs, the Home player and the closed live activity.
    { key: "alwaysShowTabs", type: "bool", default: true, store: "file", section: "general",
        label: "Always show tabs", help: "Show the Home and Shelf tabs even while the shelf is empty" },
    { key: "followDesktopMotion", type: "bool", default: true, store: "file", section: "appearance",
        label: "Follow the desktop's motion", help: "Reduce motion too while Hyprland's animations are off" },
    { key: "showSettingsIcon", type: "bool", default: true, store: "file", section: "appearance",
        label: "Settings icon", help: "Show the settings gear in the island header" },
    { key: "uiFont", type: "enum", default: "sans", values: ["sans", "theme"], store: "file", section: "appearance",
        label: "Island font", help: "The system sans-serif face, or the Omarchy theme font, for text on the island" },
    { key: "openShelfByDefault", type: "bool", default: true, store: "file", section: "shelf",
        label: "Open shelf by default", help: "Reopen on Shelf when it contains items" },
    { key: "enableGestures", type: "bool", default: true, store: "file", section: "general",
        label: "Pull to open", help: "Pull the closed island down, or Shift and scroll, to open it" },
    { key: "closeGesture", type: "bool", default: true, store: "file", section: "general",
        label: "Push to close", help: "Push the open island up, or Shift and scroll, to close it" },
    { key: "gestureTravel", type: "int", default: 200, min: 100, max: 300, store: "file", unit: "px", section: "general",
        label: "Gesture distance", help: "Pixels a pull or push travels before the island opens or closes" },
    { key: "summonAutoClose", type: "int", default: 3000, min: 0, max: 10000, store: "file", unit: "ms", section: "general",
        label: "Summon auto-close", help: "Milliseconds before a shortcut-opened island closes by itself; 0 never" },
    { key: "lightingEffect", type: "bool", default: true, store: "file", section: "media",
        label: "Artwork glow", help: "Light the player with a soft glow of the cover while music plays" },
    { key: "sliderColor", type: "enum", default: "white", values: ["white", "albumArt", "accent"], store: "file", section: "media",
        label: "Progress colour", help: "White, the cover's colour, or the theme accent" },
    { key: "peekStyle", type: "enum", default: "standard", values: ["standard", "inline"], store: "file", section: "media",
        label: "Track peek style", help: "A compact card, or title and artist beside the closed notch" },
    { key: "musicControlSlots", type: "list", default: ["shuffle", "previous", "playPause", "next", "repeat"], min: 0, max: 5,
        values: ["shuffle", "previous", "playPause", "next", "repeat", "volume", "favorite", "back15", "forward15", "none"],
        store: "file", section: "media",
        label: "Player buttons", help: "Up to five buttons under the progress bar, in order" },
    { key: "musicControlSlotLimit", type: "int", default: 5, min: 3, max: 5, store: "file", section: "media",
        label: "Button count", help: "How many player buttons show at most" },
    { key: "pauseGrace", type: "int", default: 3000, min: 0, max: 10000, store: "file", unit: "ms", section: "media",
        label: "Media inactivity timeout", help: "Milliseconds after a pause before music becomes idle; 0 ends it immediately" },
    { key: "musicLiveActivity", type: "bool", default: true, store: "file", section: "media",
        label: "Music in the closed island", help: "Show the cover and the spectrum beside the closed island while music plays" },
    { key: "coloredSpectrogram", type: "bool", default: true, store: "file", section: "media",
        label: "Coloured spectrum", help: "Colour the closed island's spectrum with the cover's colour" },
    { key: "showCalendar", type: "bool", default: false, store: "file", section: "calendar",
        label: "Calendar on Home", help: "Show the calendar beside the player" },
    { key: "showMirror", type: "bool", default: false, store: "file", section: "media",
        label: "Mirror on Home", help: "Show the camera mirror beside the player" },
    { key: "hudStyle", type: "enum", default: "inline", values: ["inline", "below"],
        store: "file", section: "hud", label: "Closed level readout", help: "Show it in the notch wings or below the notch" },
    { key: "showOpenNotchHud", type: "bool", default: true, store: "file", section: "hud",
        label: "Open notch readout", help: "Show a level capsule in the open header" },
    { key: "hudPercentClosed", type: "bool", default: false, store: "file", section: "hud",
        label: "Closed readout percentage", help: "Show a percentage beside the closed readout bar" },
    { key: "hudPercentOpen", type: "bool", default: true, store: "file", section: "hud",
        label: "Open readout percentage", help: "Show a percentage beside the open header bar" },
    { key: "hudDuration", type: "int", default: 1500, min: 250, max: 5000, unit: "ms",
        store: "file", section: "hud", label: "Readout duration", help: "Milliseconds before the level readout closes" },
    { key: "hudAccent", type: "bool", default: false, store: "file", section: "hud",
        label: "Accent level bar", help: "Use the accent colour for the readout bar" },
    { key: "hudGradient", type: "bool", default: false, store: "file", section: "hud",
        label: "Gradient level bar", help: "Shade the filled part of the level bar" },
    { key: "hudGlow", type: "bool", default: false, store: "file", section: "hud",
        label: "Glowing level bar", help: "Add a soft halo around the filled bar" },
    { key: "shelfLimit", type: "int", default: 64, min: 1, max: 256, unit: "items", store: "file", section: "shelf",
        label: "Shelf size", help: "How many files, links and snippets the shelf holds" },
    { key: "shelfEnabled", type: "bool", default: true, store: "file", section: "shelf",
        label: "Enable shelf", help: "Show the Shelf tab and accept drops into it" },
    { key: "shelfPersist", type: "bool", default: false, store: "file", section: "shelf",
        label: "Keep the shelf", help: "Save shelved items in your state folder so they survive a restart" },
    { key: "copyOnDrag", type: "bool", default: false, store: "file", section: "shelf",
        label: "Copy when dragging out", help: "Drag shelved files out as copies rather than letting the target move them" },
    { key: "autoRemoveShelfItems", type: "bool", default: false, store: "file", section: "shelf",
        label: "Remove after dragging out", help: "Take items off the shelf once they are dropped somewhere" },
    { key: "shareProvider", type: "enum", default: "auto", values: ["auto", "localsend", "kdeconnect", "portal"],
        store: "file", section: "shelf",
        label: "Share with", help: "Auto uses LocalSend, then KDE Connect, then opens the folder" },
    { key: "calendarRefresh", type: "int", default: 15, min: 5, max: 1440, unit: "min", store: "file", section: "calendar",
        label: "Calendar refresh", help: "Minutes between remote calendar refreshes" },
    { key: "calendarSources", type: "sources", default: [], max: 32, store: "file", section: "calendar",
        label: "Calendar sources", help: "Local ICS files, vdir folders, ICS URLs or CalDAV accounts" },
    // The Home calendar panel's display rules.
    { key: "hideCompletedReminders", type: "bool", default: true, store: "file", section: "calendar",
        label: "Hide completed reminders", help: "Leave finished reminders out of the day's list" },
    { key: "hideAllDayEvents", type: "bool", default: false, store: "file", section: "calendar",
        label: "Hide all-day events", help: "Show only events with a time" },
    { key: "autoScrollToNextEvent", type: "bool", default: true, store: "file", section: "calendar",
        label: "Scroll to the next event", help: "Open today's list at the current or next event" },
    { key: "showFullEventTitles", type: "bool", default: false, store: "file", section: "calendar",
        label: "Full event titles", help: "Wrap long titles instead of shortening them" },
    // Internal, not shown in the settings window: the CalDAV accounts (url
    // and user only) whose keyring password is still to be deleted after
    // their source was removed, kept so the deletion survives a restart.
    { key: "calendarPendingClears", type: "sources", default: [], max: 32, store: "file", section: "calendar", internal: true,
        label: "Pending password deletions", help: "CalDAV accounts whose stored password is still to be deleted" },
    { key: "calendarSelection", type: "list", default: [], max: 32, store: "file", section: "calendar",
        label: "Calendars shown", help: "Source ids to show; none selected shows every calendar" },
    { key: "preferredSource", type: "string", default: "", max: 256, store: "file", section: "media",
        label: "Preferred player", help: "The player Auto follows whenever it is open; choose it in the welcome's Media step" },
    { key: "mirrorShape", type: "enum", default: "rectangle", values: ["rectangle", "circle"], store: "file", section: "media",
        label: "Mirror shape", help: "A rounded square or a circle" },
    { key: "deviceEvents", type: "enum", default: "audio", values: ["off", "audio", "all"], store: "file", section: "battery",
        label: "Device peeks", help: "Show Bluetooth connections and low device batteries in the island" },
    { key: "outputPeek", type: "bool", default: true, store: "file", section: "hud",
        label: "Sound output peek", help: "Show where sound plays when the output changes; needs the level readout" },
    { key: "timers", type: "bool", default: true, store: "file", section: "general",
        label: "Timers", help: "Start Omarchy reminders from the island and count them down in the closed notch" },
    { key: "timerPresets", type: "list", itemType: "int", itemMin: 1, itemMax: 1440, default: [5, 10, 25, 60], min: 0, max: 6,
        store: "file", section: "general",
        label: "Timer presets", help: "Up to six timers in minutes, 1 to 1440, separated by commas" },
    { key: "recordingActivity", type: "bool", default: true, store: "file", section: "general",
        label: "Screen recording", help: "Show a running Omarchy screen recording in the closed island, with Stop in the open one" },
    { key: "privacyIndicators", type: "bool", default: true, store: "file", section: "general",
        label: "Privacy indicators", help: "Dots in the closed island while an app uses the microphone, a camera or the screen" },
    { key: "hardwareNotch", type: "bool", default: false, store: "file", section: "appearance",
        label: "Hardware notch", help: "Keep the closed notch's centre empty, for a screen with a camera cutout behind it" },
    { key: "idleStyle", type: "enum", default: "glance", values: ["glance", "face", "horizon", "empty"], store: "file", section: "appearance",
        label: "Idle notch", help: "What the closed island shows while nothing plays" },
    { key: "idleClock", type: "enum", default: "auto", values: ["auto", "time", "date", "off"], store: "file", section: "appearance",
        label: "Idle clock", help: "The glance's time and date; Automatic shows only the date when the bar already has a clock" },
    { key: "idleHairline", type: "bool", default: true, store: "file", section: "appearance",
        label: "Idle hairline", help: "A hairline under the glance: the day's progress, or the countdown to a coming event" },
    { key: "idleNextEvent", type: "bool", default: false, store: "file", section: "calendar",
        label: "Next event in the closed island", help: "Show the next event within the hour in the idle glance; needs the calendar on" },
    { key: "idleEventTitles", type: "bool", default: false, store: "file", section: "calendar",
        label: "Event titles in the closed island", help: "Name the next event instead of saying Event; the closed island shows in every screenshot and screen share" },
    // Internal: the idle face's old switch. A settings file that predates
    // idleStyle reads it as idleStyle "face" (see resolve), and configure()
    // still takes it as an alias for the face style (see applyAliases).
    { key: "showIdleFace", type: "bool", default: false, store: "file", section: "appearance", internal: true,
        label: "Idle face", help: "Replaced by the idle notch style" },
    { key: "useCustomAccentColor", type: "bool", default: false, store: "file", section: "advanced",
        label: "Custom accent", help: "Use a chosen colour instead of the Omarchy theme accent" },
    { key: "customAccentColor", type: "string", default: "#a9c7ff", max: 7, store: "file", section: "advanced",
        label: "Accent colour", help: "A #RRGGBB colour used when Custom accent is on" },
    { key: "windowShadow", type: "bool", default: true, store: "file", section: "advanced",
        label: "Window shadow", help: "Draw the soft shadow beneath the open island when GPU effects are available" },
    { key: "extendHoverArea", type: "bool", default: false, store: "file", section: "advanced",
        label: "Extend hover area", help: "Add an 8 px hover strip below the closed island" },
    { key: "screenshotsToShelf", type: "bool", default: false, store: "file", section: "shelf",
        label: "Shelve screenshots", help: "Add each new Omarchy screenshot to the shelf" },
    { key: "screenshotDir", type: "string", default: "", max: 4096, store: "file", section: "shelf",
        label: "Screenshot folder", help: "Where screenshots are saved; empty follows Omarchy (OMARCHY_SCREENSHOT_DIR, else Pictures)" },
    { key: "recordingsToShelf", type: "bool", default: false, store: "file", section: "shelf",
        label: "Shelve screen recordings", help: "Add each saved Omarchy screen recording to the shelf; needs Screen recording on" },
    { key: "expandedDragDetection", type: "bool", default: true, store: "file", section: "shelf",
        label: "Catch drags near the notch", help: "A file dragged over the empty bar centre opens the shelf; that space then stops taking the bar's own clicks and drags" },
    { key: "dragCatchWidth", type: "int", default: 480, min: 120, max: 1600, unit: "px", store: "file", section: "shelf",
        label: "Catch width", help: "Pixels of bar centre that catch a drag, limited to the free centre" }
]

// How the settings window names the words of an enum or a list, by setting
// key. Kept beside the schema, not inside it: schema entries stay flat
// object literals.
var VALUE_LABELS = {
    displayMode: { follow: "Follow focus", all: "Every screen", fixed: "One screen" },
    fullscreenBehavior: { always: "Always", nowPlayingOnly: "Player's app only", never: "Never" },
    powerStyle: { banner: "Banner", peek: "Peek" },
    deviceEvents: { off: "Off", audio: "Audio devices", all: "All devices" },
    peekStyle: { standard: "Standard", inline: "Inline" },
    sliderColor: { white: "White", albumArt: "Album art", accent: "Accent" },
    uiFont: { sans: "Sans-serif", theme: "Theme font" },
    musicControlSlots: { shuffle: "Shuffle", previous: "Previous", playPause: "Play/Pause", next: "Next",
        repeat: "Repeat", volume: "Volume", favorite: "Favorite", back15: "Back 15 seconds",
        forward15: "Forward 15 seconds", none: "Empty" },
    hudStyle: { inline: "In the notch", below: "Below the notch" },
    shareProvider: { auto: "Automatic", localsend: "LocalSend", kdeconnect: "KDE Connect", portal: "Open folder" },
    mirrorShape: { rectangle: "Rectangle", circle: "Circle" },
    idleStyle: { glance: "Glance", face: "Face", horizon: "Horizon", empty: "Empty" },
    idleClock: { auto: "Automatic", time: "Time and date", date: "Date only", off: "Off" }
}

// Rows that only matter while another setting allows them. Each entry is a
// list of conditions that must all hold; a condition holds when any of its
// keys has one of its values. `why` is what the dimmed row says instead.
// Kept beside the schema, like VALUE_LABELS, so schema entries stay flat.
var REQUIRES = {
    hoverDwell: { when: [{ keys: ["openOnHover"], values: [true] }], why: "Turn on Open on hover to use this." },
    preferredDisplay: { when: [{ keys: ["displayMode"], values: ["fixed", "all"] }],
        why: "Used with One screen or Every screen." },
    gestureTravel: { when: [{ keys: ["enableGestures", "closeGesture"], values: [true] }],
        why: "Turn on Pull to open or Push to close to use this." },
    peekStyle: { when: [{ keys: ["peek"], values: [true] }], why: "Turn on Track peek to use this." },
    mirrorShape: { when: [{ keys: ["showMirror"], values: [true] }], why: "Turn on Mirror on Home to use this." },
    customAccentColor: { when: [{ keys: ["useCustomAccentColor"], values: [true] }],
        why: "Turn on Custom accent to use this." },
    showBatteryIndicator: { when: [{ keys: ["power"], values: [true] }], why: "Turn on Battery and charger to use this." },
    showBatteryPercent: { when: [{ keys: ["power"], values: [true] }, { keys: ["showBatteryIndicator"], values: [true] }],
        why: "Turn on Battery and charger and Battery gauge to use this." },
    showPowerStatusIcons: { when: [{ keys: ["power"], values: [true] }, { keys: ["showBatteryIndicator"], values: [true] }],
        why: "Turn on Battery and charger and Battery gauge to use this." },
    showPowerNotifications: { when: [{ keys: ["power"], values: [true] }], why: "Turn on Battery and charger to use this." },
    powerStyle: { when: [{ keys: ["power"], values: [true] }, { keys: ["showPowerNotifications"], values: [true] }],
        why: "Turn on Battery and charger and Charger and battery alerts to use this." },
    hudStyle: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    showOpenNotchHud: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    hudPercentClosed: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    hudPercentOpen: { when: [{ keys: ["hud"], values: [true] }, { keys: ["showOpenNotchHud"], values: [true] }],
        why: "Turn on Level readout and Open notch readout to use this." },
    hudDuration: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    hudAccent: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    hudGradient: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    hudGlow: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    calendarRefresh: { when: [{ keys: ["showCalendar"], values: [true] }], why: "Turn on Calendar on Home to use this." },
    calendarSelection: { when: [{ keys: ["showCalendar"], values: [true] }], why: "Turn on Calendar on Home to use this." },
    hideCompletedReminders: { when: [{ keys: ["showCalendar"], values: [true] }], why: "Turn on Calendar on Home to use this." },
    hideAllDayEvents: { when: [{ keys: ["showCalendar"], values: [true] }], why: "Turn on Calendar on Home to use this." },
    autoScrollToNextEvent: { when: [{ keys: ["showCalendar"], values: [true] }], why: "Turn on Calendar on Home to use this." },
    showFullEventTitles: { when: [{ keys: ["showCalendar"], values: [true] }], why: "Turn on Calendar on Home to use this." },
    idleClock: { when: [{ keys: ["idleStyle"], values: ["glance"] }], why: "Choose Glance for the idle notch to use this." },
    idleHairline: { when: [{ keys: ["idleStyle"], values: ["glance"] }], why: "Choose Glance for the idle notch to use this." },
    idleNextEvent: { when: [{ keys: ["showCalendar"], values: [true] }, { keys: ["idleStyle"], values: ["glance"] }],
        why: "Turn on Calendar on Home and choose Glance to use this." },
    idleEventTitles: { when: [{ keys: ["showCalendar"], values: [true] }, { keys: ["idleNextEvent"], values: [true] },
        { keys: ["idleStyle"], values: ["glance"] }],
        why: "Turn on Calendar on Home and Next event, and choose Glance to use this." },
    openShelfByDefault: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    shelfLimit: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    shelfPersist: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    copyOnDrag: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    autoRemoveShelfItems: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    shareProvider: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    expandedDragDetection: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    dragCatchWidth: { when: [{ keys: ["shelfEnabled"], values: [true] }, { keys: ["expandedDragDetection"], values: [true] }],
        why: "Turn on Enable shelf and Catch drags near the notch to use this." },
    outputPeek: { when: [{ keys: ["hud"], values: [true] }], why: "Turn on Level readout to use this." },
    timerPresets: { when: [{ keys: ["timers"], values: [true] }], why: "Turn on Timers to use this." },
    screenshotsToShelf: { when: [{ keys: ["shelfEnabled"], values: [true] }], why: "Turn on Enable shelf to use this." },
    screenshotDir: { when: [{ keys: ["shelfEnabled"], values: [true] }, { keys: ["screenshotsToShelf"], values: [true] }],
        why: "Turn on Enable shelf and Shelve screenshots to use this." },
    recordingsToShelf: { when: [{ keys: ["shelfEnabled"], values: [true] }, { keys: ["recordingActivity"], values: [true] }],
        why: "Turn on Enable shelf and Screen recording to use this." }
}

// Sub-headings inside the longer sections, in display order. A key a
// section has but no group names follows the named groups, unheaded.
var GROUPS = {
    general: [
        { label: "Bar", keys: ["autoShow", "island"] },
        { label: "Opening", keys: ["openOnHover", "hoverDwell", "leaveGrace", "summonAutoClose", "rememberLastTab", "alwaysShowTabs"] },
        { label: "Gestures", keys: ["enableGestures", "closeGesture", "gestureTravel"] },
        { label: "Displays", keys: ["displayMode", "preferredDisplay", "fullscreenBehavior"] },
        { label: "Activities", keys: ["timers", "timerPresets", "recordingActivity", "privacyIndicators"] }
    ],
    appearance: [
        { label: "Idle notch", keys: ["hardwareNotch", "idleStyle", "idleClock", "idleHairline"] }
    ],
    media: [
        { label: "Player", keys: ["preferredSource", "remoteArtwork", "musicControlSlots", "musicControlSlotLimit", "sliderColor", "lightingEffect"] },
        { label: "Closed island", keys: ["musicLiveActivity", "visualizer", "coloredSpectrogram", "pauseGrace"] },
        { label: "Track peek", keys: ["peek", "peekStyle"] },
        { label: "Lyrics", keys: ["lyrics"] },
        { label: "Mirror", keys: ["showMirror", "mirrorShape"] }
    ],
    calendar: [
        { label: "Calendar", keys: ["showCalendar", "calendarRefresh", "calendarSources", "hideCompletedReminders",
            "hideAllDayEvents", "autoScrollToNextEvent", "showFullEventTitles", "calendarSelection"] },
        { label: "Closed island", keys: ["idleNextEvent", "idleEventTitles"] }
    ]
}

// What a settings row shows for a key: the shell's stored boolean or the
// schema default for the eleven original keys, the resolved file value for
// the rest. Shared by the settings window and the welcome.
function storedValue(coordinator, key) {
    var spec = entry(key)
    if (!spec) return undefined
    if (!coordinator) return copy(spec.default)
    if (spec.store === "shell") {
        var stored = coordinator.settings ? coordinator.settings[key] : undefined
        return typeof stored === "boolean" ? stored : spec.default
    }
    return coordinator.fileSettings && key in coordinator.fileSettings ? coordinator.fileSettings[key] : spec.default
}

// Keys the settings window leaves out although they are not internal:
// onboardingDone is offered as About's "Show welcome again" instead.
var WINDOW_HIDDEN = ["onboardingDone"]

// Whether the settings window shows a row for this entry.
function shownInWindow(spec) {
    return !!spec && !spec.internal && WINDOW_HIDDEN.indexOf(spec.key) < 0
}

// The window's rows matching a search, in section order: every word of the
// query must appear in the label, the help, the section's name or the
// group's heading, ignoring case.
function search(query) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (word) { return word !== "" })
    if (!words.length) return []
    var found = []
    var all = sections()
    for (var i = 0; i < all.length; ++i)
        for (var g = 0; g < all[i].groups.length; ++g)
            for (var k = 0; k < all[i].groups[g].keys.length; ++k) {
                var spec = entry(all[i].groups[g].keys[k])
                var text = [spec.label, spec.help, all[i].label, all[i].groups[g].label].join(" ").toLowerCase()
                if (words.every(function (word) { return text.indexOf(word) >= 0 }))
                    found.push({ key: spec.key, section: all[i].id, sectionLabel: all[i].label })
            }
    return found
}

// A configure() batch that puts one section's rows back to their defaults.
// Source lists are data the person entered, not preferences, so a reset
// never clears them.
function resetValues(sectionId) {
    var values = {}
    var all = sections()
    for (var i = 0; i < all.length; ++i) {
        if (all[i].id !== sectionId) continue
        for (var k = 0; k < all[i].keys.length; ++k) {
            var spec = entry(all[i].keys[k])
            if (spec.type !== "sources") values[spec.key] = copy(spec.default)
        }
    }
    return values
}

// "" when the row's setting is in effect, else the sentence the dimmed row
// shows. valueOf(key) returns the stored value of any setting.
function requirementText(key, valueOf) {
    var rule = REQUIRES[key]
    if (!rule) return ""
    for (var i = 0; i < rule.when.length; ++i) {
        var condition = rule.when[i], held = false
        for (var j = 0; j < condition.keys.length && !held; ++j)
            held = condition.values.indexOf(valueOf(condition.keys[j])) >= 0
        if (!held) return rule.why
    }
    return ""
}

var TYPES = ["bool", "int", "real", "enum", "string", "list", "sources", "screen"]
var SOURCE_KINDS = ["file", "vdir", "ics-url", "caldav"]
var SOURCE_FIELDS = ["kind", "path", "url", "user", "allowLocalNetwork", "color"]

// How the settings window names one of an enum's or a list's words.
function valueLabel(spec, value) {
    var labels = spec ? VALUE_LABELS[spec.key] : null
    return labels && typeof labels[value] === "string" ? labels[value] : String(value)
}
function entry(key) {
    for (var i = 0; i < SCHEMA.length; ++i)
        if (SCHEMA[i].key === key) return SCHEMA[i]
    return null
}

// Keys in schema order, optionally only those of one store.
function keys(store) {
    var result = []
    for (var i = 0; i < SCHEMA.length; ++i)
        if (store === undefined || SCHEMA[i].store === store) result.push(SCHEMA[i].key)
    return result
}

function withinBounds(spec, size) {
    return (spec.min === undefined || size >= spec.min) && (spec.max === undefined || size <= spec.max)
}

// Whether a URL names a user or password before its host
// (scheme://user:pass@host). Such a URL would put a credential in the
// settings file; a CalDAV password belongs in the keyring instead.
function hasUserinfo(url) {
    return /^\s*[a-z][a-z0-9+.-]*:\/\/[^\/?#]*@/i.test(String(url || ""))
}

function checkSource(source) {
    if (!source || typeof source !== "object" || Array.isArray(source)
        || SOURCE_KINDS.indexOf(source.kind) < 0) return false
    for (var field in source)
        if (SOURCE_FIELDS.indexOf(field) < 0) return false
    if (source.kind === "file" || source.kind === "vdir") {
        if (typeof source.path !== "string" || source.path.charAt(0) !== "/" || source.path.length > 4096) return false
    } else {
        if (typeof source.url !== "string" || source.url.length > 2048 || hasUserinfo(source.url)
            || (!/^https:\/\//.test(source.url) && !/^http:\/\/localhost(?::[0-9]+)?\//.test(source.url))) return false
        if (source.kind === "caldav" && (typeof source.user !== "string" || !source.user || source.user.length > 256)) return false
    }
    if (source.allowLocalNetwork !== undefined && typeof source.allowLocalNetwork !== "boolean") return false
    return source.color === undefined
        || (typeof source.color === "string" && /^#[0-9a-fA-F]{6}$/.test(source.color))
}

// Whether value is acceptable for one schema entry.
function check(spec, value) {
    if (!spec) return false
    switch (spec.type) {
    case "bool":
        return typeof value === "boolean"
    case "int":
        return typeof value === "number" && Number.isInteger(value) && withinBounds(spec, value)
    case "real":
        return typeof value === "number" && isFinite(value) && withinBounds(spec, value)
    case "enum":
        return typeof value === "string" && Array.isArray(spec.values) && spec.values.indexOf(value) >= 0
    case "string":
        return typeof value === "string" && withinBounds(spec, value.length)
            && (spec.key !== "backlightDevice" || value === ""
                || (/^[A-Za-z0-9_][A-Za-z0-9_.:-]*$/.test(value) && value !== ".."))
            && (spec.key !== "customAccentColor" || /^#[0-9a-fA-F]{6}$/.test(value))
            && (spec.key !== "screenshotDir" || value === "" || value.charAt(0) === "/")
    case "list":
        if (!Array.isArray(value) || !withinBounds(spec, value.length)) return false
        // A list of whole numbers within itemMin..itemMax (timer minutes).
        if (spec.itemType === "int") {
            for (var n = 0; n < value.length; ++n)
                if (typeof value[n] !== "number" || !Number.isInteger(value[n]) || value[n] < spec.itemMin || value[n] > spec.itemMax)
                    return false
            return true
        }
        for (var i = 0; i < value.length; ++i)
            if (typeof value[i] !== "string" || (Array.isArray(spec.values) && spec.values.indexOf(value[i]) < 0))
                return false
        return true
    // A screen's connector name ("eDP-1", "HDMI-A-1"), or "" for none.
    case "screen":
        return typeof value === "string" && withinBounds(spec, value.length)
            && (value === "" || /^[A-Za-z0-9_][A-Za-z0-9_.:-]*$/.test(value))
    case "sources":
        if (!Array.isArray(value) || !withinBounds(spec, value.length)) return false
        for (var j = 0; j < value.length; ++j)
            if (!checkSource(value[j])) return false
        return true
    }
    return false
}

function validate(key, value) {
    return check(entry(key), value)
}

// The retired showIdleFace switch still works through configure(): true
// selects the face style, and false leaves the face for the default glance
// (any other style stays). A batch that names idleStyle itself wins.
function applyAliases(options, current) {
    if (!options || typeof options.showIdleFace !== "boolean"
        || Object.prototype.hasOwnProperty.call(options, "idleStyle")) return options
    var style = options.showIdleFace ? "face"
        : current && current.idleStyle === "face" ? entry("idleStyle").default : null
    return style ? Object.assign({}, options, { idleStyle: style }) : options
}

// A configure() batch is accepted whole or not at all: a plain object whose
// every key is in the schema with a valid value.
function validateBatch(options) {
    if (options === null || typeof options !== "object" || Array.isArray(options)) return false
    for (var key in options)
        if (!validate(key, options[key])) return false
    return true
}

function copy(value) {
    return Array.isArray(value) ? JSON.parse(JSON.stringify(value)) : value
}

// What status() reports: every value but the calendar source definitions
// and the internal keys.
function publicValues(values) {
    var result = Object.assign({}, values)
    delete result.calendarSources
    delete result.calendarPendingClears
    for (var i = 0; i < SCHEMA.length; ++i)
        if (SCHEMA[i].internal) delete result[SCHEMA[i].key]
    return result
}

// Defaults of every key, or of one store's keys.
function defaults(store) {
    var result = {}
    for (var i = 0; i < SCHEMA.length; ++i)
        if (store === undefined || SCHEMA[i].store === store) result[SCHEMA[i].key] = copy(SCHEMA[i].default)
    return result
}

// Exactly the file-store keys: a valid stored value is kept, anything else
// (missing, invalid, or not an object at all) falls back to its default, and
// keys outside the schema are dropped. A source list loses only its invalid
// sources, so one bad hand-edited entry (a URL carrying a password, for one)
// does not take the others with it; each such drop is added to `notes`, when
// given, as { key, dropped, userinfo } without the values themselves.
function resolve(values, notes) {
    var stored = values !== null && typeof values === "object" && !Array.isArray(values) ? values : {}
    var result = {}
    for (var i = 0; i < SCHEMA.length; ++i) {
        var spec = SCHEMA[i]
        if (spec.store !== "file") continue
        var has = Object.prototype.hasOwnProperty.call(stored, spec.key)
        var value = has ? stored[spec.key] : undefined
        if (has && spec.type === "sources" && Array.isArray(value)) {
            var kept = value.filter(checkSource)
            if (kept.length < value.length && Array.isArray(notes))
                notes.push({ key: spec.key, dropped: value.length - kept.length,
                    userinfo: value.some(function (source) { return !!source && hasUserinfo(source.url) }) })
            value = kept
        }
        result[spec.key] = copy(has && check(spec, value) ? value : spec.default)
    }
    // A file from before idleStyle that had the idle face on keeps the face.
    if (!Object.prototype.hasOwnProperty.call(stored, "idleStyle") && stored.showIdleFace === true)
        result.idleStyle = "face"
    return result
}

// One log line for resolve()'s notes, or "" when there are none. It names the
// key and a count, never a dropped value.
function noteText(notes) {
    var parts = []
    for (var i = 0; i < (notes || []).length; ++i) {
        var note = notes[i]
        var what = note.dropped === 1 ? "1 calendar source" : note.dropped + " calendar sources"
        parts.push("nookisle: ignored " + what + " in settings.json that "
            + (note.dropped === 1 ? "is" : "are") + " not valid"
            + (note.userinfo ? "; a URL may not hold a user name or password, use the password field instead" : ""))
    }
    return parts.join("\n")
}

// The stored values of a settings file's text, {version: 1, values: {...}},
// or null for text that is not such a document; resolve() turns either into
// the full, valid set.
var FILE_VERSION = 1
function parseFile(text) {
    try {
        var data = JSON.parse(text)
        if (data && typeof data === "object" && data.version === FILE_VERSION
            && data.values && typeof data.values === "object" && !Array.isArray(data.values)) return data.values
    } catch (error) {
    }
    return null
}

function serialise(values) {
    return JSON.stringify({ version: FILE_VERSION, values: resolve(values) }, null, 2) + "\n"
}

// Sections in display order. Each has its visible keys and those keys in
// groups: a section's GROUPS in order, then any key they do not name, in
// schema order, in a last group without a label. `keys` is the groups'
// keys in display order. Internal keys are never shown.
function sections() {
    var result = []
    for (var i = 0; i < SECTIONS.length; ++i) {
        var sectionKeys = []
        for (var j = 0; j < SCHEMA.length; ++j)
            if (SCHEMA[j].section === SECTIONS[i].id && shownInWindow(SCHEMA[j])) sectionKeys.push(SCHEMA[j].key)
        var groups = [], named = []
        var declared = GROUPS[SECTIONS[i].id] || []
        for (var g = 0; g < declared.length; ++g) {
            var groupKeys = declared[g].keys.filter(function (key) { return sectionKeys.indexOf(key) >= 0 })
            if (!groupKeys.length) continue
            groups.push({ label: declared[g].label, keys: groupKeys })
            named = named.concat(groupKeys)
        }
        var rest = sectionKeys.filter(function (key) { return named.indexOf(key) < 0 })
        if (rest.length) groups.push({ label: "", keys: rest })
        var ordered = []
        for (var k = 0; k < groups.length; ++k) ordered = ordered.concat(groups[k].keys)
        result.push({ id: SECTIONS[i].id, label: SECTIONS[i].label, keys: ordered, groups: groups })
    }
    return result
}
