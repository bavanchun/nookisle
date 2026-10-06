pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Calendar.js" as Calendar

// The editor for the calendarSources setting, hosted by the settings window
// for that key's type. It lists the configured sources without printing a
// secret, adds an ICS file, a vdir folder, an iCal link (Google's secret
// address) or a CalDAV account, removes one, and tests one.
//
// Sources are written through coordinator.configure. A remote source needs
// an explicit "may contact" confirmation, and local-network access its own,
// both off by default. A CalDAV password goes only to the helper's
// calendarCredential verb through `source` (a CalendarSource); the helper
// hands it to the desktop keyring on standard input. The field is cleared as
// soon as it is handed over, and nothing here stores it.
Column {
    id: root
    required property var tokens
    property var coordinator: null
    // The CalendarSource, present only while the calendar is on and the
    // island shows; testing and passwords need it.
    property var source: null
    readonly property var sources: coordinator && coordinator.fileSettings
        && Array.isArray(coordinator.fileSettings.calendarSources) ? coordinator.fileSettings.calendarSources : []
    property string kind: "file"
    readonly property bool remoteKind: Calendar.isRemote(kind)
    property bool remoteAllowed: false
    property bool localNetworkAllowed: false
    readonly property var draft: Calendar.makeSource(kind, {
        path: pathField.text, url: urlField.text, user: userField.text,
        allowLocalNetwork: localNetworkAllowed }, remoteAllowed)
    // An account whose old password the helper is deleting right now needs
    // its password again, or it would be left without one.
    readonly property bool passwordBeingCleared: kind === "caldav" && draft !== null && !!coordinator
        && typeof coordinator.calendarClearPending === "function" && coordinator.calendarClearPending(draft.url, draft.user)
    readonly property bool canAdd: draft !== null && sources.length < 32
        && !(kind === "caldav" && passwordField.text.length > 0 && !source)
        && !(passwordBeingCleared && passwordField.text.length === 0)
    property string notice: ""
    property bool noticeIsError: false
    // Test results by source id: "testing", "ok" or a helper error code.
    property var results: ({})
    // Requests awaiting the helper, by request id.
    property var tests: ({})
    property var stores: ({})
    // CalDAV accounts removed while this editor is open, by url and user,
    // whose password deletion is still to be reported.
    property var removedAccounts: ({})
    spacing: tokens.gap

    function say(text, isError) {
        notice = text;
        noticeIsError = isError === true;
    }
    function resultFor(definition) {
        return results[Calendar.sourceId(definition)] || "";
    }
    function withEntry(map, key, value) {
        var next = Object.assign({}, map);
        if (value === undefined) delete next[key];
        else next[key] = value;
        return next;
    }
    // Whether another source than `index` signs in as the same account; its
    // keyring entry is shared and must stay.
    function add() {
        if (!canAdd)
            return false;
        var definition = draft;
        var password = passwordField.text;
        passwordField.text = "";
        if (!coordinator.configure({ calendarSources: sources.concat([definition]) })) {
            say("Not saved: the source was refused", true);
            return false;
        }
        pathField.text = "";
        urlField.text = "";
        userField.text = "";
        remoteAllowed = false;
        localNetworkAllowed = false;
        say("Added " + Calendar.describe(definition));
        if (definition.kind === "caldav" && password.length > 0) {
            var id = source.storeCredential(definition.url, definition.user, password);
            if (id) stores = withEntry(stores, id, definition);
            else say("Added " + Calendar.describe(definition) + ", but its password was not saved", true);
        }
        return true;
    }
    // Removal is the Service's transaction (removeCalendarSource): it saves
    // the list without the source and, when no remaining source uses a CalDAV
    // account, deletes that account's password even if this editor closes or
    // the island hides. The editor reports the outcome while it is open.
    function remove(index) {
        if (!coordinator || typeof coordinator.removeCalendarSource !== "function" || index < 0 || index >= sources.length)
            return false;
        var definition = sources[index];
        if (!coordinator.removeCalendarSource(definition)) {
            say("Not saved: the change was refused", true);
            return false;
        }
        var id = Calendar.sourceId(definition);
        if (sources.every(entry => Calendar.sourceId(entry) !== id))
            results = withEntry(results, id, undefined);
        if (definition.kind === "caldav")
            removedAccounts = withEntry(removedAccounts, definition.url + "\n" + definition.user, definition);
        say("Removed " + Calendar.describe(definition));
        return true;
    }
    // A fresh load of that one source; the result shows once it finishes.
    function test(index) {
        if (!source || index < 0 || index >= sources.length)
            return false;
        var id = Calendar.sourceId(sources[index]);
        if (results[id] === "testing")
            return false;
        var requestId = source.testSource(id);
        if (!requestId)
            return false;
        tests = withEntry(tests, requestId, id);
        results = withEntry(results, id, "testing");
        return true;
    }
    Connections {
        target: root.source
        ignoreUnknownSignals: true
        function onTestFinished(requestId, sourceId, ok, error) {
            var id = root.tests[requestId];
            if (id === undefined) return;
            root.tests = root.withEntry(root.tests, requestId, undefined);
            root.results = root.withEntry(root.results, id, ok ? "ok" : error);
        }
        function onCredentialFinished(requestId, action, ok, error) {
            var stored = root.stores[requestId];
            if (stored !== undefined) {
                root.stores = root.withEntry(root.stores, requestId, undefined);
                root.say(ok ? "Saved the password for " + Calendar.describe(stored)
                    : "The password for " + Calendar.describe(stored) + " was not saved: " + Calendar.errorText(error), !ok);
                return;
            }
        }
    }
    Connections {
        target: root.coordinator
        ignoreUnknownSignals: true
        function onCalendarClearFinished(url, user, ok, error) {
            var key = url + "\n" + user;
            var removed = root.removedAccounts[key];
            if (removed === undefined) return;
            root.removedAccounts = root.withEntry(root.removedAccounts, key, undefined);
            if (!ok)
                root.say("Removed " + Calendar.describe(removed) + ", but its password could not be deleted from the keyring ("
                    + Calendar.errorText(error) + ").", true);
        }
    }

    component Caption: Text {
        width: root.width
        wrapMode: Text.WordWrap
        color: root.tokens.secondary
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
        textFormat: Text.PlainText
    }

    Repeater {
        model: root.sources
        Row {
            id: sourceRow
            required property var modelData
            required property int index
            objectName: "calendarSourceRow-" + index
            width: root.width
            spacing: root.tokens.gap
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: sourceRow.modelData.color || root.tokens.accent
            }
            Column {
                width: parent.width - 10 - testButton.width - removeButton.width - root.tokens.gap * 3
                Text {
                    objectName: "calendarSourceLabel"
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: Calendar.describe(sourceRow.modelData)
                    textFormat: Text.PlainText
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.bodySize
                }
                Text {
                    objectName: "calendarSourceStatus"
                    width: parent.width
                    elide: Text.ElideRight
                    readonly property string result: root.resultFor(sourceRow.modelData)
                    text: Calendar.KINDS.filter(entry => entry.kind === sourceRow.modelData.kind)[0].label
                        + (result === "testing" ? " · Testing…" : result === "ok" ? " · Connected"
                            : result ? " · " + Calendar.errorText(result) : "")
                    textFormat: Text.PlainText
                    color: result && result !== "ok" && result !== "testing" ? root.tokens.error : root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                }
            }
            SettingsButton {
                tokens: root.tokens
                id: testButton
                objectName: "calendarSourceTest-" + sourceRow.index
                text: "Test"
                enabled: !!root.source
                onClicked: root.test(sourceRow.index)
            }
            SettingsButton {
                tokens: root.tokens
                id: removeButton
                objectName: "calendarSourceRemove-" + sourceRow.index
                text: "Remove"
                onClicked: root.remove(sourceRow.index)
            }
        }
    }
    Caption {
        visible: root.sources.length === 0
        text: "No calendars yet."
    }
    Caption {
        objectName: "calendarTestHint"
        visible: !root.source && root.sources.length > 0
        text: "Turn on the calendar and open the island to test a source."
    }

    // Wraps rather than clipping the long iCal link label at a narrow width.
    Flow {
        objectName: "calendarKinds"
        width: root.width
        spacing: root.tokens.small
        Repeater {
            model: Calendar.KINDS
            SettingsButton {
                tokens: root.tokens
                required property var modelData
                objectName: "calendarKind-" + modelData.kind
                text: modelData.label
                checkable: true
                checked: root.kind === modelData.kind
                onClicked: {
                    root.kind = modelData.kind;
                    root.remoteAllowed = false;
                    root.localNetworkAllowed = false;
                }
            }
        }
    }
    SettingsField {
        tokens: root.tokens
        id: pathField
        objectName: "calendarPathField"
        visible: !root.remoteKind
        width: root.width
        placeholderText: root.kind === "vdir" ? "/home/you/.local/share/calendars/personal" : "/home/you/calendar.ics"
    }
    SettingsField {
        tokens: root.tokens
        id: urlField
        objectName: "calendarUrlField"
        visible: root.remoteKind
        width: root.width
        placeholderText: root.kind === "caldav" ? "https://cloud.example.com/remote.php/dav/calendars/you/personal/"
            : "https://calendar.google.com/calendar/ical/…/basic.ics"
    }
    Caption {
        objectName: "calendarUserinfoHint"
        visible: root.remoteKind && Calendar.hasUserinfo(urlField.text)
        text: root.kind === "caldav"
            ? "Remove the user name and password from the link: put the user name in its own field and the password in the password field, which keeps it in your keyring."
            : "Remove the user name and password from the link; a link that needs a password cannot be saved here. For a CalDAV account, use the password field."
        color: root.tokens.error
    }
    Caption {
        visible: root.kind === "ics-url"
        text: "For Google Calendar, use the calendar's \"Secret address in iCal format\". Anyone with that link can read the calendar, so it is kept only in your settings file and never shown in full here."
    }
    SettingsField {
        tokens: root.tokens
        id: userField
        objectName: "calendarUserField"
        visible: root.kind === "caldav"
        width: root.width
        placeholderText: "User name"
    }
    SettingsField {
        tokens: root.tokens
        id: passwordField
        objectName: "calendarPasswordField"
        visible: root.kind === "caldav"
        width: root.width
        echoMode: TextInput.Password
        placeholderText: "Password or app password (kept in the keyring)"
    }
    Caption {
        visible: root.kind === "caldav"
        text: "Google Calendar does not accept passwords over CalDAV; add it as an iCal link instead."
    }
    SettingsCheckBox {
        tokens: root.tokens
        objectName: "calendarAllowRemote"
        visible: root.remoteKind
        text: "Allow Nookisle to contact this server"
        checked: root.remoteAllowed
        onToggled: root.remoteAllowed = checked
    }
    SettingsCheckBox {
        tokens: root.tokens
        objectName: "calendarAllowLocal"
        visible: root.remoteKind
        text: "It is on my local network (Nextcloud or Radicale at home)"
        checked: root.localNetworkAllowed
        onToggled: root.localNetworkAllowed = checked
    }
    Caption {
        objectName: "calendarReaddHint"
        visible: root.passwordBeingCleared && passwordField.text.length === 0
        text: "This account's saved password is being deleted; enter it again to add the account back."
        color: root.tokens.error
    }
    Caption {
        objectName: "calendarPasswordHint"
        visible: root.kind === "caldav" && passwordField.text.length > 0 && !root.source
        text: "Turn on the calendar and open the island to save a password."
        color: root.tokens.error
    }
    SettingsButton {
        tokens: root.tokens
        objectName: "calendarAdd"
        text: "Add calendar"
        enabled: root.canAdd
        onClicked: root.add()
    }
    Caption {
        objectName: "calendarNotice"
        visible: text.length > 0
        text: root.notice
        color: root.noticeIsError ? root.tokens.error : root.tokens.secondary
    }
}
