pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import "../qml/Settings.js" as Settings
import "../qml/Calendar.js" as Calendar
import "../qml/Strings.js" as Strings

// One settings row generated from a schema entry: label, help text and the
// control its type calls for. Every edit goes through coordinator.configure,
// which validates against the schema; a refused edit snaps the control back
// to the stored value and says so.
Column {
    id: root
    required property var tokens
    required property var spec
    property var coordinator: null
    // The stored value; the settings pane binds it.
    property var value: spec ? spec.default : undefined
    // The connected screens' names, for a "screen" setting.
    property var screens: []
    property bool failed: false
    // What the failed edit's message says, from the coordinator's cause.
    property string errorText: ""
    // Why the row does nothing now, when another setting turns it off: the
    // row is dimmed and its control disabled, and the sentence says why.
    property string requirement: ""
    enabled: requirement === ""
    objectName: spec ? "settingControl-" + spec.key : ""
    spacing: tokens.small

    function commit(next) {
        var options = {};
        options[spec.key] = next;
        var saved = !!coordinator && coordinator.configure(options) === true;
        failed = !saved;
        var cause = !coordinator ? "unavailable" : String(coordinator.configureError || "");
        errorText = saved ? "" : Strings.settingErrorText(cause, spec);
        // A refused text keeps what was typed, so it can be corrected;
        // every other control snaps back to the stored value.
        if (!saved && !(spec.type === "string" && cause === "invalid"))
            sync();
    }
    // Controls hold their own state once touched, so a refused edit or an
    // outside change must be pushed back into them.
    readonly property bool inline: spec.type === "bool"
    readonly property Item input: inline ? inlineInput.item : blockInput.item
    function sync() {
        if (!input)
            return;
        if (spec.type === "bool")
            input.checked = value === true;
        else if (spec.type === "int" || spec.type === "real")
            input.value = value;
        else if (spec.type === "string")
            input.text = value;
        else if (spec.type === "list" && spec.itemType === "int")
            input.text = listOf(value).join(", ");
    }
    onValueChanged: sync()
    // A list as a plain JS array, whether it arrived as one or as a QML list.
    function listOf(items) {
        return items && items.length !== undefined && typeof items !== "string" ? Array.prototype.slice.call(items) : [];
    }

    Row {
        objectName: "settingRow-" + root.spec.key
        width: parent.width
        spacing: root.tokens.gap
        opacity: root.enabled ? 1 : 0.45
        Column {
            width: parent.width - (root.inline ? inlineInput.width + root.tokens.gap : 0)
            spacing: 2
            Text {
                width: parent.width
                text: root.spec.label
                textFormat: Text.PlainText
                color: root.tokens.text
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: root.spec.help
                textFormat: Text.PlainText
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.captionSize
                wrapMode: Text.WordWrap
            }
        }
        // Switches sit beside the label; every other control gets its own line.
        Loader {
            id: inlineInput
            active: root.inline
            objectName: active ? "settingInput-" + root.spec.key : ""
            onLoaded: root.sync()
            sourceComponent: switchInput
        }
    }
    Loader {
        id: blockInput
        active: !root.inline
        visible: active
        opacity: root.enabled ? 1 : 0.45
        objectName: active ? "settingInput-" + root.spec.key : ""
        width: root.width
        onLoaded: root.sync()
        sourceComponent: {
            switch (root.spec.type) {
            case "int":
            case "real": return sliderInput;
            case "enum": return enumInput;
            case "string": return root.spec.key === "preferredSource" ? preferredInput : textInput;
            case "list": return root.spec.key === "calendarSelection" ? calendarSelectionInput
                : root.spec.itemType === "int" ? numberListInput : listInput;
            case "sources": return sourceInput;
            case "screen": return screenInput;
            }
            return otherInput;
        }
    }
    Text {
        objectName: "settingRequirement-" + root.spec.key
        visible: root.requirement !== ""
        width: parent.width
        text: root.requirement
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.tokens.secondary
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
        font.italic: true
    }
    Text {
        objectName: "settingError-" + root.spec.key
        visible: root.failed
        width: parent.width
        text: root.errorText
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.tokens.error
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
    }

    // A choice among an enum's values or the screens: a segment that fills
    // with the primary colour while it holds the stored value.
    // Choices are one radio group: Tab reaches only the chosen one, and
    // the arrow keys choose and focus the next or previous choice.
    component Choice: SettingsButton {
        id: choice
        required property string modelData
        readonly property bool isChoice: true
        tokens: root.tokens
        checkable: true
        focusPolicy: checked ? Qt.StrongFocus : Qt.ClickFocus
        Accessible.role: Accessible.RadioButton
        Accessible.description: root.spec.help
        function step(delta) {
            var group = parent.children.filter(item => item.isChoice === true);
            var next = group[group.indexOf(choice) + delta];
            if (!next)
                return;
            next.clicked();
            next.forceActiveFocus(Qt.TabFocusReason);
        }
        Keys.onLeftPressed: step(-1)
        Keys.onUpPressed: step(-1)
        Keys.onRightPressed: step(1)
        Keys.onDownPressed: step(1)
    }
    Component {
        id: switchInput
        Controls.Switch {
            id: toggle
            Accessible.name: root.spec.label
            Accessible.description: root.spec.help
            onToggled: root.commit(checked)
            // On, the track fills with the primary colour and the knob moves
            // right; off, a plain track and a muted knob on the left.
            indicator: Rectangle {
                objectName: "settingSwitchTrack"
                implicitWidth: 40
                implicitHeight: 22
                x: toggle.leftPadding
                y: (toggle.height - height) / 2
                radius: height / 2
                color: toggle.checked ? root.tokens.primaryFill : root.tokens.track
                border.width: toggle.visualFocus ? root.tokens.focusWidth : 0
                border.color: root.tokens.accent
                Rectangle {
                    objectName: "settingSwitchKnob"
                    width: parent.height - 6
                    height: width
                    radius: width / 2
                    x: toggle.checked ? parent.width - width - 3 : 3
                    y: 3
                    color: toggle.checked ? root.tokens.primaryLabel : root.tokens.secondary
                    Behavior on x {
                        enabled: root.tokens.feedbackDuration > 0
                        NumberAnimation { duration: root.tokens.feedbackDuration }
                    }
                }
            }
            // The label sits beside the row, so the switch is its track alone.
            contentItem: Item {}
            implicitWidth: indicator.implicitWidth + leftPadding + rightPadding
            implicitHeight: Math.max(root.tokens.target, indicator.implicitHeight + topPadding + bottomPadding)
        }
    }
    // A number: a slider for the rough value and a field for the exact one.
    // A drag saves once on release. Keys (arrows, Page Up and Down, Home and
    // End) save once they rest for calmDelay, or when the slider loses the
    // keyboard, so holding a key writes the file once instead of per step.
    readonly property int calmDelay: 400
    Component {
        id: sliderInput
        Row {
            property alias value: slider.value
            spacing: root.tokens.gap
            function display(number) {
                return root.spec.type === "int" ? String(Math.round(number)) : Number(number).toFixed(2);
            }
            Controls.Slider {
                id: slider
                objectName: "settingSlider-" + root.spec.key
                width: parent.width - numberField.width - unitText.width - root.tokens.gap * 2
                from: root.spec.min !== undefined ? root.spec.min : 0
                to: root.spec.max !== undefined ? root.spec.max : 100
                stepSize: root.spec.type === "int" ? 1 : (to - from) / 100
                snapMode: Controls.Slider.SnapAlways
                Accessible.name: root.spec.label
                Accessible.description: root.spec.help
                // The island tokens, and a focus ring round the handle when
                // the slider is reached by keyboard.
                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + (slider.availableHeight - height) / 2
                    width: slider.availableWidth
                    height: 4
                    radius: 2
                    color: root.tokens.track
                    Rectangle {
                        width: slider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: root.tokens.primaryFill
                    }
                }
                handle: Rectangle {
                    objectName: "settingSliderHandle"
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + (slider.availableHeight - height) / 2
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: width / 2
                    color: slider.pressed ? root.tokens.primaryLabel : root.tokens.text
                    border.width: slider.visualFocus ? root.tokens.focusWidth : 0
                    border.color: root.tokens.accent
                    Rectangle {
                        visible: slider.visualFocus
                        anchors.centerIn: parent
                        width: parent.width + 2 * (root.tokens.focusWidth + 2)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: root.tokens.focusWidth
                        border.color: root.tokens.accent
                    }
                }
                function current() {
                    return root.spec.type === "int" ? Math.round(value) : value;
                }
                // A tenth of the range, never less than one step.
                readonly property real bigStep: Math.max(stepSize, root.spec.type === "int"
                    ? Math.round((to - from) / 10) : (to - from) / 10)
                function flush() {
                    if (!calm.running)
                        return;
                    calm.stop();
                    root.commit(current());
                }
                // The Slider also reports pressed while a key is held, so a
                // key press is marked here, before the Slider sees it, and
                // its release waits for the calm delay like any key step.
                property bool keyed: false
                // A key-moved value waiting for its save.
                readonly property bool calming: calm.running
                Keys.onPressed: event => {
                    keyed = true;
                    var next = event.key === Qt.Key_PageUp ? value + bigStep
                        : event.key === Qt.Key_PageDown ? value - bigStep
                        : event.key === Qt.Key_Home ? from : event.key === Qt.Key_End ? to : NaN;
                    if (isNaN(next))
                        return;
                    event.accepted = true;
                    value = Math.max(from, Math.min(to, next));
                    calm.restart();
                }
                onPressedChanged: {
                    if (pressed)
                        return;
                    if (keyed) {
                        keyed = false;
                        calm.restart();
                        return;
                    }
                    calm.stop();
                    root.commit(current());
                }
                onMoved: if (!pressed) calm.restart()
                onActiveFocusChanged: if (!activeFocus) flush()
                onValueChanged: if (!numberField.edited) numberField.text = parent.display(value)
                Component.onDestruction: flush()
                Timer {
                    id: calm
                    interval: root.calmDelay
                    onTriggered: root.commit(slider.current())
                }
            }
            // The exact value, typed. Enter or leaving the field saves it; a
            // number out of range stays in the field with the range named.
            SettingsField {
                id: numberField
                objectName: "settingNumber-" + root.spec.key
                tokens: root.tokens
                width: root.tokens.target * 2
                height: slider.height
                horizontalAlignment: TextInput.AlignRight
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                text: parent.display(slider.value)
                Accessible.name: root.spec.label + (root.spec.unit ? ", " + root.spec.unit : "")
                // Only typing makes the field's text the one to save; until
                // then it follows the value, including outside changes.
                property bool edited: false
                onTextEdited: edited = true
                onEditingFinished: {
                    if (!edited)
                        return;
                    edited = false;
                    var typed = Number(text.trim());
                    if (text.trim() === "" || !isFinite(typed)) {
                        text = parent.display(slider.value);
                        return;
                    }
                    var next = root.spec.type === "int" ? typed : Math.round(typed * 100) / 100;
                    if (next === slider.current())
                        return;
                    root.commit(next);
                    if (!root.failed)
                        slider.value = next;
                    else if (root.coordinator && root.coordinator.configureError === "invalid")
                        edited = true;
                    else
                        text = parent.display(slider.value);
                }
            }
            Text {
                id: unitText
                objectName: "settingUnit-" + root.spec.key
                width: root.spec.unit ? implicitWidth : 0
                height: slider.height
                verticalAlignment: Text.AlignVCenter
                text: root.spec.unit || ""
                textFormat: Text.PlainText
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
            }
        }
    }
    Component {
        id: enumInput
        Flow {
            spacing: root.tokens.small
            Repeater {
                model: root.spec.values
                Choice {
                    objectName: "settingChoice-" + root.spec.key + "-" + modelData
                    text: Settings.valueLabel(root.spec, modelData)
                    checked: root.value === modelData
                    Accessible.name: root.spec.label + " " + text
                    onClicked: {
                        checked = Qt.binding(function () { return root.value === modelData; });
                        root.commit(modelData);
                    }
                }
            }
        }
    }
    // The remembered player: its name and Forget, never a raw identity to
    // type. Forgetting returns the selection to plain Auto.
    Component {
        id: preferredInput
        Row {
            spacing: root.tokens.gap
            Text {
                objectName: "preferredSourceName"
                height: forget.height
                verticalAlignment: Text.AlignVCenter
                text: root.value ? Strings.appName(root.value) : "None: Auto follows whatever plays"
                textFormat: Text.PlainText
                color: root.value ? root.tokens.text : root.tokens.secondary
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
            }
            SettingsButton {
                id: forget
                objectName: "preferredSourceForget"
                visible: !!root.value
                tokens: root.tokens
                text: "Forget"
                Accessible.name: "Forget the preferred player"
                onClicked: {
                    if (root.coordinator && typeof root.coordinator.rememberSource === "function") {
                        root.failed = !root.coordinator.rememberSource(null);
                        root.errorText = root.failed ? Strings.settingErrorText(String(root.coordinator.configureError || ""), root.spec) : "";
                    } else {
                        root.commit("");
                    }
                }
            }
        }
    }
    Component {
        id: textInput
        SettingsField {
            tokens: root.tokens
            Accessible.name: root.spec.label
            Accessible.description: root.spec.help
            onEditingFinished: if (text !== root.value) root.commit(text)
        }
    }
    // Whole numbers typed as "5, 10, 25": saved when the whole list is
    // valid, otherwise put back as it was, with the reason shown.
    function parseNumbers(text) {
        var words = String(text).split(/[\s,]+/).filter(word => word !== "");
        var numbers = words.map(word => /^[0-9]+$/.test(word) ? parseInt(word, 10) : NaN);
        return numbers.some(number => isNaN(number)) ? null : numbers;
    }
    Component {
        id: numberListInput
        SettingsField {
            tokens: root.tokens
            Accessible.name: root.spec.label
            Accessible.description: root.spec.help
            onEditingFinished: {
                var next = root.parseNumbers(text);
                if (next === null || !Settings.validate(root.spec.key, next)) {
                    root.failed = true;
                    root.errorText = root.spec.help;
                    root.sync();
                    return;
                }
                if (JSON.stringify(next) !== JSON.stringify(root.listOf(root.value)))
                    root.commit(next);
            }
        }
    }
    Component {
        id: listInput
        SlotEditor {
            tokens: root.tokens
            value: root.listOf(root.value)
            palette: root.listOf(root.spec.values)
            labelOf: word => Settings.valueLabel(root.spec, word)
            defaultValue: root.listOf(root.spec.default)
            maxLength: root.spec.max !== undefined ? root.spec.max : palette.length
            onEdited: next => root.commit(next)
        }
    }
    function toggleCalendar(id) {
        var selected = listOf(value);
        if (selected.length === 0) {
            commit([id]);
            return;
        }
        var index = selected.indexOf(id);
        if (index >= 0)
            selected.splice(index, 1);
        else
            selected.push(id);
        commit(selected);
    }
    Component {
        id: calendarSelectionInput
        Flow {
            width: root.width
            spacing: root.tokens.small
            SettingsButton {
                objectName: "calendarFilterAll"
                tokens: root.tokens
                text: "All calendars"
                checkable: true
                checked: root.listOf(root.value).length === 0
                onClicked: {
                    checked = Qt.binding(function () { return root.listOf(root.value).length === 0; });
                    root.commit([]);
                }
            }
            Repeater {
                model: root.coordinator && root.coordinator.fileSettings
                    ? root.listOf(root.coordinator.fileSettings.calendarSources) : []
                SettingsButton {
                    required property var modelData
                    required property int index
                    tokens: root.tokens
                    readonly property string sourceId: Calendar.sourceId(modelData)
                    objectName: "calendarFilter-" + index
                    text: Calendar.describe(modelData)
                    checkable: true
                    checked: root.listOf(root.value).indexOf(sourceId) >= 0
                    Accessible.name: "Show " + text
                    onClicked: {
                        checked = Qt.binding(function () { return root.listOf(root.value).indexOf(sourceId) >= 0; });
                        root.toggleCalendar(sourceId);
                    }
                }
            }
        }
    }
    // A screen setting: Automatic (empty), each connected screen, and the
    // stored one when it is not connected, so it stays visible and kept.
    function screenChoices() {
        var names = listOf(screens);
        var choices = [""].concat(names);
        if (typeof value === "string" && value !== "" && names.indexOf(value) < 0)
            choices.push(value);
        return choices;
    }
    Component {
        id: screenInput
        Flow {
            spacing: root.tokens.small
            Repeater {
                model: root.screenChoices()
                Choice {
                    readonly property bool connected: modelData === "" || root.listOf(root.screens).indexOf(modelData) >= 0
                    objectName: "settingChoice-" + root.spec.key + "-" + (modelData || "automatic")
                    text: modelData === "" ? "Automatic" : connected ? modelData : modelData + " (not connected)"
                    checked: root.value === modelData
                    Accessible.name: root.spec.label + " " + text
                    onClicked: {
                        checked = Qt.binding(function () { return root.value === modelData; });
                        root.commit(modelData);
                    }
                }
            }
        }
    }
    Component {
        id: sourceInput
        CalendarSourceEditor {
            width: root.width
            tokens: root.tokens
            coordinator: root.coordinator
            source: root.coordinator && "calendarSource" in root.coordinator ? root.coordinator.calendarSource : null
        }
    }
    Component {
        id: otherInput
        Text {
            text: "Set up in its own editor"
            color: root.tokens.secondary
            font.family: root.tokens.fontFamily
            font.pixelSize: root.tokens.captionSize
        }
    }
}
