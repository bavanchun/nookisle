pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

// The shelf's context menu, built from Shelf.menuEntries. It holds the busy
// guard for as long as it is open, so the island does not collapse under it,
// and reports the chosen entry through actionTriggered(action, argument).
Menu {
    id: menu
    property var entries: []
    property var ink: null
    property var busyGuard: null
    signal actionTriggered(string action, var argument)
    // Menu items created for the current entries, destroyed on rebuild.
    property var built: []

    ShelfBusyHold {
        guard: menu.busyGuard
        active: menu.opened || menu.visible
    }

    onEntriesChanged: rebuild()
    Component.onCompleted: rebuild()
    function rebuild() {
        for (var i = built.length - 1; i >= 0; --i) {
            var old = built[i]
            if (old.isMenu) menu.removeMenu(old.object)
            else menu.removeItem(old.object)
            old.object.destroy()
        }
        var next = []
        for (var j = 0; j < entries.length; ++j) {
            var entry = entries[j]
            if (entry.separator) {
                var separator = separatorComponent.createObject(null)
                menu.addItem(separator)
                next.push({ object: separator, isMenu: false })
            } else if (Array.isArray(entry.entries)) {
                var sub = subMenuComponent.createObject(null, { title: entry.label, entries: entry.entries })
                menu.addMenu(sub)
                next.push({ object: sub, isMenu: true })
            } else {
                var item = itemComponent.createObject(null, { text: entry.label, entryAction: entry.action, argument: entry.argument })
                menu.addItem(item)
                next.push({ object: item, isMenu: false })
            }
        }
        built = next
    }

    background: Rectangle {
        implicitWidth: 200
        radius: 12
        color: menu.ink.raised
        border.width: 1
        border.color: menu.ink.raisedStroke
    }

    Component {
        id: itemComponent
        MenuItem {
            id: entryItem
            property string entryAction: ""
            property var argument: undefined
            objectName: "shelfMenu_" + entryAction + (typeof argument === "string" ? "_" + argument : "")
            onTriggered: menu.actionTriggered(entryAction, argument)
            contentItem: Text {
                text: entryItem.text
                color: menu.ink.ink
                font.family: menu.ink.fontFamily
                renderType: menu.ink.textRenderType
                font.pixelSize: menu.ink.bodySize
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }
            background: Rectangle {
                radius: 8
                color: entryItem.highlighted ? menu.ink.selectedFill : "transparent"
            }
        }
    }
    Component {
        id: separatorComponent
        MenuSeparator {
            contentItem: Rectangle {
                implicitHeight: 1
                color: menu.ink.inkFaint
            }
        }
    }
    Component {
        id: subMenuComponent
        Menu {
            id: sub
            property var entries: []
            objectName: "shelfSubMenu_" + title
            // A cascade stays inside the same input region as its parent.
            topMargin: menu.topMargin
            bottomMargin: menu.bottomMargin
            leftMargin: menu.leftMargin
            rightMargin: menu.rightMargin
            background: Rectangle {
                implicitWidth: 160
                radius: 12
                color: menu.ink.raised
                border.width: 1
                border.color: menu.ink.raisedStroke
            }
            Repeater {
                model: sub.entries
                delegate: MenuItem {
                    id: subItem
                    required property var modelData
                    text: modelData.label
                    objectName: "shelfMenu_" + modelData.action + "_" + (typeof modelData.argument === "string" ? modelData.argument : modelData.label)
                    onTriggered: menu.actionTriggered(modelData.action, modelData.argument)
                    contentItem: Text {
                        text: subItem.text
                        color: menu.ink.ink
                        font.family: menu.ink.fontFamily
                        renderType: menu.ink.textRenderType
                        font.pixelSize: menu.ink.bodySize
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                    }
                    background: Rectangle {
                        radius: 8
                        color: subItem.highlighted ? menu.ink.selectedFill : "transparent"
                    }
                }
            }
        }
    }
}
