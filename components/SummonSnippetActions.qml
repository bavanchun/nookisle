import QtQuick
import "../qml/Strings.js" as Strings

// Below the summon line, in the settings window and the welcome: Copy puts
// the whole line on the clipboard, and a chord already bound to something
// else is named, so the line is not added over it unseen.
Column {
    id: root
    required property var tokens
    // The read-only TextArea or TextEdit holding Strings.summonBinding.
    property var snippet: null
    property string conflict: ""
    property bool copied: false
    spacing: tokens.small
    function copy() {
        if (!snippet)
            return;
        snippet.selectAll();
        snippet.copy();
        snippet.deselect();
        copied = true;
    }
    SettingsButton {
        objectName: "summonCopy"
        tokens: root.tokens
        text: root.copied ? "Copied" : "Copy"
        Accessible.name: "Copy the summon binding"
        onClicked: root.copy()
    }
    Text {
        objectName: "summonConflict"
        visible: root.conflict !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: Strings.summonChord + " is already bound to \u201c" + root.conflict
            + "\u201d. Change the chord in the line before adding it, or unbind the other one first."
        textFormat: Text.PlainText
        color: root.tokens.error
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.captionSize
    }
}
