pragma ComponentBehavior: Bound

import QtQuick

// A list setting edited like boring.notch's music slot view: the current
// slots in order, a palette of the words not yet used, and a trash target.
// Drag a slot onto another slot to move it there, a palette word onto a slot
// to insert it (or replace it when the list is full) or onto the end to
// append it, and a slot onto the trash to remove it. Every change is emitted
// as a whole new list; the owner validates and stores it.
Column {
    id: root
    required property var tokens
    property var value: []
    property var palette: []
    property var defaultValue: []
    property int maxLength: palette.length
    // How a word is shown; the stored word itself by default.
    property var labelOf: word => word
    signal edited(var next)
    readonly property var unused: palette.filter(word => value.indexOf(word) < 0)
    readonly property string dragKey: "nookisle-slot"
    spacing: tokens.gap

    function moveSlot(from, to) {
        if (from < 0 || from >= value.length || to < 0 || to >= value.length || from === to)
            return;
        var next = value.slice();
        var moving = next.splice(from, 1)[0];
        next.splice(to, 0, moving);
        edited(next);
    }
    function insertItem(word, index) {
        if (palette.indexOf(word) < 0 || value.indexOf(word) >= 0)
            return;
        var next = value.slice();
        var at = Math.max(0, Math.min(index, next.length));
        if (next.length < maxLength)
            next.splice(at, 0, word);
        else if (at < next.length)
            next[at] = word;
        else
            return;
        edited(next);
    }
    function removeAt(index) {
        if (index < 0 || index >= value.length)
            return;
        var next = value.slice();
        next.splice(index, 1);
        edited(next);
    }
    function resetToDefault() {
        if (defaultValue.length)
            edited(defaultValue.slice());
    }

    // The keyboard follows a word across an edit: the rows rebuild their
    // chips, so the chip now carrying it takes the focus back.
    property string focusWord: ""
    onValueChanged: if (focusWord) Qt.callLater(restoreFocus)
    function restoreFocus() {
        var word = focusWord;
        focusWord = "";
        var rows = [slotRow, slotPalette];
        for (var r = 0; r < rows.length; ++r)
            for (var i = 0; i < rows[r].children.length; ++i)
                if (rows[r].children[i].word === word) {
                    rows[r].children[i].forceActiveFocus(Qt.TabFocusReason);
                    return;
                }
    }
    // Keys, for the drags: Ctrl+Left/Right moves a slot, Delete removes it,
    // and Return or Space adds a palette word at the end (replacing the last
    // slot when the list is full).
    function chipKey(chip, event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        var index = chip.fromSlot;
        if (index >= 0 && ctrl && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            index += event.key === Qt.Key_Left ? -1 : 1;
            if (index < 0 || index >= value.length)
                return true;
        } else if (index >= 0 && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace))
            index = -2;
        else if (index < 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space))
            index = value.length < maxLength ? value.length : value.length - 1;
        else
            return false;
        if (chip.fromSlot < 0 && index < 0)
            return true;
        focusWord = chip.word;
        if (index === -2)
            removeAt(chip.fromSlot);
        else if (chip.fromSlot >= 0)
            moveSlot(chip.fromSlot, index);
        else
            insertItem(chip.word, index);
        return true;
    }

    component Chip: Item {
        id: chip
        required property string word
        // The slot this chip sits in, or -1 for a palette word.
        property int fromSlot: -1
        width: Math.max(root.tokens.target * 2, label.implicitWidth + root.tokens.gap * 2)
        height: root.tokens.target
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.labelOf(word) + (fromSlot >= 0 ? ", slot " + (fromSlot + 1) : ", not used")
        Keys.onPressed: event => { event.accepted = root.chipKey(chip, event); }
        Rectangle {
            id: body
            objectName: chip.fromSlot >= 0 ? "slotChip-" + chip.fromSlot : "paletteChip-" + chip.word
            property string word: chip.word
            property int fromSlot: chip.fromSlot
            width: chip.width
            height: chip.height
            radius: height / 2
            color: root.tokens.surfaceRaised
            border.color: dragArea.drag.active || chip.activeFocus ? root.tokens.accent : root.tokens.hairline
            border.width: chip.activeFocus ? root.tokens.focusWidth : 1
            Drag.active: dragArea.drag.active
            Drag.keys: [root.dragKey]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            z: dragArea.drag.active ? 1 : 0
            Text {
                id: label
                anchors.centerIn: parent
                text: root.labelOf(chip.word)
                textFormat: Text.PlainText
                color: root.tokens.text
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.captionSize
            }
            MouseArea {
                id: dragArea
                anchors.fill: parent
                drag.target: body
                onReleased: {
                    body.Drag.drop();
                    body.x = 0;
                    body.y = 0;
                }
            }
        }
    }

    Text {
        width: root.width
        wrapMode: Text.WordWrap
        text: "Drag to reorder; drop on the trash to remove. Keys: Ctrl+Left/Right moves, Delete removes, Return adds"
        textFormat: Text.PlainText
        color: root.tokens.secondary
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
    }
    // Both rows wrap, so a long label never pushes a chip or the trash out
    // of the window.
    Flow {
        id: slotRow
        objectName: "slotRow"
        width: root.width
        spacing: root.tokens.small
        Repeater {
            model: root.value
            Chip {
                id: slot
                required property int index
                required property string modelData
                word: modelData
                fromSlot: index
                DropArea {
                    anchors.fill: parent
                    keys: [root.dragKey]
                    onDropped: drop => {
                        if (drop.source.fromSlot >= 0)
                            root.moveSlot(drop.source.fromSlot, slot.index);
                        else
                            root.insertItem(drop.source.word, slot.index);
                    }
                }
            }
        }
        // Dropping a palette word here appends it.
        Rectangle {
            objectName: "slotTail"
            visible: root.value.length < root.maxLength
            width: root.tokens.target * 2
            height: root.tokens.target
            radius: height / 2
            color: "transparent"
            border.color: tailDrop.containsDrag ? root.tokens.accent : root.tokens.hairline
            DropArea {
                id: tailDrop
                anchors.fill: parent
                keys: [root.dragKey]
                onDropped: drop => {
                    if (drop.source.fromSlot < 0)
                        root.insertItem(drop.source.word, root.value.length);
                }
            }
        }
    }
    Flow {
        id: slotPalette
        objectName: "slotPalette"
        width: root.width
        spacing: root.tokens.small
        Repeater {
            model: root.unused
            Chip {
                required property string modelData
                word: modelData
            }
        }
        Rectangle {
            objectName: "slotTrash"
            width: root.tokens.target * 2
            height: root.tokens.target
            radius: height / 2
            color: trashDrop.containsDrag ? root.tokens.error : "transparent"
            border.color: root.tokens.error
            Text {
                anchors.centerIn: parent
                text: "Remove"
                color: trashDrop.containsDrag ? root.tokens.surface : root.tokens.error
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.captionSize
            }
            DropArea {
                id: trashDrop
                anchors.fill: parent
                keys: [root.dragKey]
                onDropped: drop => {
                    if (drop.source.fromSlot >= 0)
                        root.removeAt(drop.source.fromSlot);
                }
            }
        }
    }
    SettingsButton {
        objectName: "slotReset"
        tokens: root.tokens
        visible: root.defaultValue.length > 0
        text: "Reset to Defaults"
        enabled: root.value.join("\u0000") !== root.defaultValue.join("\u0000")
        onClicked: root.resetToDefault()
    }
}
