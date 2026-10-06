pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as Controls
import "../qml/Settings.js" as Settings
import "../qml/Strings.js" as Strings

// The settings window's content: a 200 px sidebar of Settings.sections() and
// the selected section's rows, each generated from the schema. SettingsWindow
// hosts it in a FloatingWindow; the tests load it directly.
Rectangle {
    id: root
    required property var tokens
    property var coordinator: null
    // The connected screens' names, offered by a "screen" setting.
    property var screens: []
    readonly property var sections: Settings.sections()
    property string currentSection: sections[0].id
    readonly property var currentKeys: {
        for (var i = 0; i < sections.length; ++i)
            if (sections[i].id === currentSection) return sections[i].keys;
        return [];
    }
    readonly property var currentGroups: {
        for (var i = 0; i < sections.length; ++i)
            if (sections[i].id === currentSection) return sections[i].groups;
        return [];
    }
    readonly property int sidebarWidth: 200
    // The search across every section: while it holds text, the page lists
    // the matching rows instead of the selected section.
    property string query: ""
    readonly property bool searching: query.trim() !== ""
    readonly property var results: Settings.search(query)
    // A section reset asks once before it writes.
    property bool confirmingReset: false
    property string resetError: ""
    onCurrentSectionChanged: { confirmingReset = false; resetError = "" }
    function resetSection() {
        var saved = !!coordinator && coordinator.configure(Settings.resetValues(currentSection)) === true;
        confirmingReset = false;
        resetError = saved ? "" : Strings.settingErrorText(coordinator ? String(coordinator.configureError || "") : "unavailable", null);
        return saved;
    }
    function focusSearch() {
        searchField.forceActiveFocus(Qt.ShortcutFocusReason);
        searchField.selectAll();
    }
    Shortcut {
        sequence: StandardKey.Find
        onActivated: root.focusSearch()
    }
    readonly property string repositoryUrl: coordinator && coordinator.manifest
        && /^https:\/\/github\.com\/bavanchun\/nookisle\/?$/.test(String(coordinator.manifest.repository || ""))
        ? String(coordinator.manifest.repository) : ""
    color: tokens.surface

    // What the row shows: the shell's stored boolean or the schema default
    // for the eleven original keys, the resolved file value for the rest.
    function valueOf(key) {
        return Settings.storedValue(coordinator, key);
    }
    // Keeps the keyboard's control in view: when Tab or a click moves the
    // focus to a control on the page, the page scrolls just enough to show
    // it whole, with a margin.
    readonly property Item focusedItem: Window.activeFocusItem
    onFocusedItemChanged: if (focusedItem && inPage(focusedItem)) reveal(focusedItem)
    function inPage(item) {
        for (var node = item; node; node = node.parent)
            if (node === pageColumn)
                return true;
        return false;
    }
    function reveal(item) {
        var top = item.mapToItem(page.contentItem, 0, 0).y - tokens.gap;
        var bottom = top + item.height + tokens.gap * 2;
        var limit = Math.max(0, page.contentHeight - page.height);
        if (top < page.contentY)
            page.contentY = Math.max(0, top);
        else if (bottom > page.contentY + page.height)
            page.contentY = Math.min(limit, bottom - page.height);
    }
    function showSection(id) {
        for (var i = 0; i < sections.length; ++i)
            if (sections[i].id === id) {
                query = "";
                currentSection = id;
                page.contentY = 0;
                return true;
            }
        return false;
    }

    Rectangle {
        id: sidebar
        objectName: "settingsSidebar"
        // One Tab stop for the whole sidebar, the first in the window. While
        // it holds the keyboard the selected section wears the focus ring,
        // and Up, Down, Home and End move between sections.
        activeFocusOnTab: true
        Accessible.role: Accessible.PageTabList
        Accessible.name: "Settings sections"
        Keys.onPressed: event => {
            var index = root.sections.findIndex(section => section.id === root.currentSection);
            var last = root.sections.length - 1;
            var next = event.key === Qt.Key_Up ? index - 1 : event.key === Qt.Key_Down ? index + 1
                : event.key === Qt.Key_Home ? 0 : event.key === Qt.Key_End ? last : -2;
            if (next === -2)
                return;
            event.accepted = true;
            root.showSection(root.sections[Math.max(0, Math.min(last, next))].id);
        }
        width: root.sidebarWidth
        height: parent.height
        color: root.tokens.surfaceSunken
        Column {
            y: searchField.y + searchField.height + root.tokens.gap
            width: parent.width
            spacing: 2
            Repeater {
                model: root.sections
                // Drawn with the island tokens: the Basic style fills a
                // highlighted delegate with its own palette colour, not the
                // highlight, which left the selected label unreadable.
                Controls.ItemDelegate {
                    id: sectionEntry
                    required property var modelData
                    objectName: "settingsSection-" + modelData.id
                    x: root.tokens.gap
                    width: sidebar.width - root.tokens.gap * 2
                    height: root.tokens.target
                    highlighted: !root.searching && root.currentSection === modelData.id
                    hoverEnabled: true
                    text: modelData.label
                    // The sidebar holds the keyboard for its entries.
                    focusPolicy: Qt.NoFocus
                    Accessible.role: Accessible.PageTab
                    Accessible.checked: highlighted
                    onClicked: root.showSection(modelData.id)
                    background: Rectangle {
                        objectName: "settingsSectionFill"
                        radius: root.tokens.rowRadius
                        color: sectionEntry.highlighted ? root.tokens.primaryFill
                            : sectionEntry.hovered || sectionEntry.down ? root.tokens.hover : "transparent"
                        border.width: sectionEntry.highlighted && sidebar.activeFocus ? root.tokens.focusWidth : 0
                        border.color: sectionEntry.highlighted ? root.tokens.primaryLabel : root.tokens.accent
                    }
                    contentItem: Text {
                        objectName: "settingsSectionLabel"
                        leftPadding: root.tokens.gap
                        verticalAlignment: Text.AlignVCenter
                        text: sectionEntry.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: sectionEntry.highlighted ? root.tokens.primaryLabel : root.tokens.text
                        font.family: root.tokens.fontFamily
                        font.pixelSize: root.tokens.bodySize
                        font.weight: sectionEntry.highlighted ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }
    Flickable {
        id: page
        objectName: "settingsPage"
        x: sidebar.width
        width: parent.width - sidebar.width
        height: parent.height
        contentHeight: pageColumn.implicitHeight + root.tokens.inset * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar {}
        Column {
            id: pageColumn
            x: root.tokens.inset
            y: root.tokens.inset
            width: page.width - root.tokens.inset * 2
            spacing: root.tokens.medium
            Text {
                objectName: "settingsPageTitle"
                text: root.searching ? "Search" : root.sections.filter(section => section.id === root.currentSection)[0].label
                textFormat: Text.PlainText
                color: root.tokens.text
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.titleSize + 4
                font.weight: Font.DemiBold
            }
            // Each group under its sub-heading; a row whose setting another
            // one turns off is dimmed and says which.
            // Search results: each matching row under its section's name.
            Repeater {
                model: root.searching ? root.results : []
                Column {
                    id: result
                    required property var modelData
                    width: pageColumn.width
                    spacing: 2
                    Text {
                        text: result.modelData.sectionLabel
                        textFormat: Text.PlainText
                        color: root.tokens.secondary
                        font.family: root.tokens.fontFamily
                        font.pixelSize: root.tokens.captionSize
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                    }
                    SettingsControls {
                        width: pageColumn.width
                        tokens: root.tokens
                        coordinator: root.coordinator
                        spec: Settings.entry(result.modelData.key)
                        value: root.valueOf(result.modelData.key)
                        requirement: Settings.requirementText(result.modelData.key, root.valueOf)
                        screens: root.screens
                    }
                }
            }
            Text {
                objectName: "settingsNoResults"
                visible: root.searching && root.results.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: "No setting matches \u201c" + root.query.trim() + "\u201d."
                textFormat: Text.PlainText
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
            }
            Repeater {
                model: root.searching ? [] : root.currentGroups
                Column {
                    id: group
                    required property var modelData
                    width: pageColumn.width
                    spacing: root.tokens.medium
                    Text {
                        objectName: "settingsGroup-" + group.modelData.label
                        visible: group.modelData.label !== ""
                        topPadding: root.tokens.small
                        text: group.modelData.label
                        textFormat: Text.PlainText
                        color: root.tokens.secondary
                        font.family: root.tokens.fontFamily
                        font.pixelSize: root.tokens.captionSize
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        Accessible.role: Accessible.Heading
                        Accessible.name: group.modelData.label
                    }
                    Repeater {
                        model: group.modelData.keys
                        SettingsControls {
                            required property string modelData
                            width: pageColumn.width
                            tokens: root.tokens
                            coordinator: root.coordinator
                            spec: Settings.entry(modelData)
                            value: root.valueOf(modelData)
                            requirement: Settings.requirementText(modelData, root.valueOf)
                            screens: root.screens
                        }
                    }
                }
            }
            // Puts this section's rows back to their defaults, after asking.
            // Calendar sources are data, not preferences, and are kept.
            Column {
                objectName: "settingsReset"
                visible: !root.searching && root.currentKeys.length > 0
                width: parent.width
                spacing: root.tokens.small
                topPadding: root.tokens.medium
                SettingsButton {
                    objectName: "settingsResetSection"
                    visible: !root.confirmingReset
                    tokens: root.tokens
                    text: "Reset " + root.sections.filter(section => section.id === root.currentSection)[0].label + " to defaults"
                    onClicked: root.confirmingReset = true
                }
                Text {
                    visible: root.confirmingReset
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: "Put every setting on this page back to its default?"
                        + (root.currentSection === "calendar" ? " Your calendars are kept." : "")
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.bodySize
                }
                Row {
                    visible: root.confirmingReset
                    spacing: root.tokens.gap
                    SettingsButton {
                        objectName: "settingsResetConfirm"
                        tokens: root.tokens
                        text: "Reset"
                        onClicked: root.resetSection()
                    }
                    SettingsButton {
                        objectName: "settingsResetCancel"
                        tokens: root.tokens
                        text: "Cancel"
                        onClicked: root.confirmingReset = false
                    }
                }
                Text {
                    objectName: "settingsResetError"
                    visible: root.resetError !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.resetError
                    textFormat: Text.PlainText
                    color: root.tokens.error
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
            }
            Text {
                visible: !root.searching && root.currentKeys.length === 0 && root.currentSection !== "shortcuts"
                    && root.currentSection !== "about"
                width: parent.width
                text: "Nothing to set here yet."
                textFormat: Text.PlainText
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
            }
            Column {
                objectName: "settingsShortcuts"
                visible: !root.searching && root.currentSection === "shortcuts"
                // Read-only: what already holds the chord, asked each time
                // the section shows.
                onVisibleChanged: if (visible && root.coordinator && typeof root.coordinator.checkSummonBinding === "function")
                    root.coordinator.checkSummonBinding()
                width: parent.width
                spacing: root.tokens.gap
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Open the island from a key by adding a binding to ~/.config/hypr/bindings.lua:"
                    textFormat: Text.PlainText
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.bodySize
                }
                // Wraps at spaces only, so no name or command is split.
                Controls.TextArea {
                    id: snippet
                    objectName: "summonSnippet"
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    text: Strings.summonBinding
                    color: root.tokens.text
                    selectionColor: root.tokens.primaryFill
                    selectedTextColor: root.tokens.primaryLabel
                    font.family: "monospace"
                    font.pixelSize: root.tokens.captionSize
                    background: Rectangle {
                        color: root.tokens.surfaceSunken
                        radius: root.tokens.small
                        border.width: snippet.activeFocus ? root.tokens.focusWidth : 0
                        border.color: root.tokens.accent
                    }
                }
                SummonSnippetActions {
                    width: parent.width
                    tokens: root.tokens
                    snippet: snippet
                    conflict: root.coordinator ? String(root.coordinator.summonConflict || "") : ""
                }
            }
            Column {
                objectName: "settingsAbout"
                visible: !root.searching && root.currentSection === "about"
                width: parent.width
                spacing: root.tokens.small
                Text {
                    text: "Nookisle" + (root.coordinator && root.coordinator.manifest && root.coordinator.manifest.version
                        ? " " + root.coordinator.manifest.version : "")
                    textFormat: Text.PlainText
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.bodySize
                    font.weight: Font.DemiBold
                }
                Text {
                    objectName: "settingsBuildInfo"
                    text: "Build: " + (root.coordinator && root.coordinator.manifest
                        ? String(root.coordinator.manifest.build || "unknown") : "unknown")
                        + " · Manifest schema: " + (root.coordinator && root.coordinator.manifest
                            ? String(root.coordinator.manifest.schemaVersion || "unknown") : "unknown")
                    textFormat: Text.PlainText
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
                SettingsButton {
                    objectName: "settingsShowWelcome"
                    tokens: root.tokens
                    text: "Show welcome again"
                    visible: !!root.coordinator && typeof root.coordinator.openOnboarding === "function"
                    onClicked: root.coordinator.openOnboarding()
                }
                SettingsButton {
                    objectName: "settingsOpenFile"
                    tokens: root.tokens
                    text: "Open settings file"
                    visible: !!root.coordinator && !!root.coordinator.settingsFilePath
                    onClicked: Qt.openUrlExternally("file://" + encodeURI(root.coordinator.settingsFilePath))
                }
                SettingsButton {
                    objectName: "settingsProjectLink"
                    tokens: root.tokens
                    text: "Project on GitHub"
                    visible: root.repositoryUrl !== ""
                    onClicked: Qt.openUrlExternally(root.repositoryUrl)
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "A media island for the Omarchy bar. Settings are saved as you change them."
                    color: root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
            }
        }
    }
    // Drawn above the sections but outside the sidebar's key handler, so Up
    // and Down stay with the text; declared last, so Tab still goes sidebar,
    // page, then search. Ctrl+F reaches it directly, and Escape clears it.
    SettingsField {
        id: searchField
        objectName: "settingsSearch"
        x: root.tokens.gap
        y: root.tokens.inset
        width: root.sidebarWidth - root.tokens.gap * 2
        tokens: root.tokens
        placeholderText: "Search settings"
        text: root.query
        onTextEdited: root.query = text
        Accessible.name: "Search settings"
        Keys.onEscapePressed: event => {
            event.accepted = root.query !== "";
            root.query = "";
        }
    }
}
