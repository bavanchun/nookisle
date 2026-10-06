pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import "../qml/Strings.js" as Strings

Item {
    id: root
    required property var tokens
    property var coordinator: null
    signal dismissed
    readonly property string sleepUnavailableReason: !coordinator || !coordinator.selectedEndpoint
        ? "Choose a source first" : "This source cannot be paused"
    // Scroll the smallest distance that brings a focused row fully into view.
    function reveal(item) {
        var flick = scroller.contentItem;
        var top = item.mapToItem(settingsColumn, 0, 0).y;
        var bottom = top + item.height;
        if (top < flick.contentY) flick.contentY = top;
        else if (bottom > flick.contentY + flick.height) flick.contentY = bottom - flick.height;
    }
    Component.onCompleted: backButton.forceActiveFocus(Qt.TabFocusReason)
    Text {
        x: root.tokens.inset
        y: root.tokens.inset
        width: parent.width - root.tokens.inset * 3 - root.tokens.target
        height: root.tokens.target
        elide: Text.ElideRight
        text: "Settings"
        color: root.tokens.text
        font.family: root.tokens.fontFamily
        font.pixelSize: root.tokens.titleSize
        font.weight: Font.DemiBold
        verticalAlignment: Text.AlignVCenter
    }
    IslandButton {
        id: backButton
        objectName: "settingsBackButton"
        x: parent.width - width - root.tokens.inset
        y: root.tokens.inset
        tokens: root.tokens
        iconName: "back"
        accessibleLabel: Strings.backToPlayer
        onActivated: root.dismissed()
    }
    // Scrolls rather than clips: four switches, the sleep timer and the footnote
    // outgrow panelHeight(width) at the largest shell fonts, and a view that
    // runs off the card hides controls without saying so. Tab focus scrolls the
    // focused row into view, so nothing is keyboard-reachable yet invisible.
    Controls.ScrollView {
        id: scroller
        objectName: "settingsScroller"
        x: root.tokens.inset
        y: root.tokens.heroArtSize
        width: parent.width - root.tokens.inset * 2
        height: parent.height - y - root.tokens.small
        clip: true
        contentWidth: availableWidth
        contentHeight: settingsColumn.implicitHeight
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        // Always drawn when there is more below, so a clipped view reads as
        // scrollable in a still frame rather than as complete.
        Controls.ScrollBar.vertical.policy: contentHeight > height
            ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AsNeeded
        Column {
            id: settingsColumn
            objectName: "settingsColumn"
            // Leave the scroll bar its own lane so it never covers a switch.
            width: scroller.availableWidth - (scroller.effectiveScrollBarWidth > 0
                ? scroller.effectiveScrollBarWidth + root.tokens.small : 0)
            spacing: root.tokens.gap
            ColumnLayout {
                id: optionColumn
                width: parent.width
                spacing: 0
                Repeater {
                    model: [
                        {
                            key: "remoteArtwork",
                            label: "Online artwork",
                            description: "Download cover art from the current source"
                        },
                        {
                            key: "reducedMotion",
                            label: "Reduce motion",
                            description: "Turn off transition effects"
                        },
                        {
                            key: "highContrast",
                            label: "High contrast",
                            description: "Opaque surfaces and clear borders"
                        },
                        {
                            key: "autoShow",
                            label: "Show in the status bar",
                            description: "Quick access from the bar"
                        },
                        {
                            key: "island",
                            label: "Dynamic island",
                            description: "Show the player as a pill over the bar centre"
                        },
                        {
                            key: "hud",
                            label: "Level readout",
                            description: "Show volume and brightness changes in the island"
                        },
                        {
                            key: "visualizer",
                            label: "Live spectrum",
                            description: "Animate the island with the music that is playing"
                        },
                        {
                            key: "peek",
                            label: "Track peek",
                            description: "Briefly show the new track when it changes"
                        },
                        {
                            key: "power",
                            label: "Battery and charger",
                            description: "Read the battery through UPower. Off hides the gauge and every power notification"
                        },
                        {
                            key: "tint",
                            label: "Artwork colours",
                            description: "Tint the island with the cover art's colour"
                        },
                        {
                            key: "lyrics",
                            label: "Synced lyrics",
                            description: "Look up lyrics on lrclib.net (sends title, artist, album and length)"
                        }
                    ]
                    delegate: Controls.Switch {
                        id: option
                        required property var modelData
                        objectName: "setting-" + modelData.key
                        Layout.fillWidth: true
                        // Grows past one row when the description wraps.
                        Layout.preferredHeight: Math.max(root.tokens.rowHeight, implicitHeight)
                        text: modelData.label
                        checked: !!root.coordinator && root.coordinator[modelData.key] === true
                        focusPolicy: Qt.StrongFocus
                        hoverEnabled: true
                        Accessible.name: text
                        Accessible.description: modelData.description
                        onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        onToggled: {
                            var settings = {};
                            settings[modelData.key] = checked;
                            if (root.coordinator)
                                root.coordinator.configure(settings);
                            checked = Qt.binding(function () {
                                return !!root.coordinator && root.coordinator[modelData.key] === true;
                            });
                        }
                        contentItem: Column {
                            spacing: root.tokens.small
                            Text {
                                width: option.width - root.tokens.target - root.tokens.inset
                                text: option.text
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.tokens.text
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.bodySize
                                font.weight: Font.Medium
                            }
                            // Wrapped, never elided: the lyrics row's text is
                            // the disclosure of what leaves the machine, and
                            // an ellipsis would hide the fields it lists.
                            Text {
                                objectName: "settingDescription-" + option.modelData.key
                                width: option.width - root.tokens.target - root.tokens.inset
                                text: option.modelData.description
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: root.tokens.secondary
                                font.family: root.tokens.fontFamily
                                font.pixelSize: root.tokens.captionSize
                            }
                        }
                        indicator: Rectangle {
                            x: option.width - width
                            y: (option.height - height) / 2
                            width: root.tokens.target
                            height: root.tokens.inset + root.tokens.small
                            radius: height / 2
                            color: option.checked ? root.tokens.primaryFill : root.tokens.track
                            Rectangle {
                                x: option.checked ? parent.width - width - 2 : 2
                                y: 2
                                width: 16
                                height: 16
                                radius: 8
                                color: root.tokens.surface
                            }
                        }
                        background: Rectangle {
                            radius: root.tokens.rowRadius
                            color: option.hovered ? root.tokens.hover : "transparent"
                            border.color: root.tokens.accent
                            border.width: option.visualFocus ? root.tokens.focusWidth : 0
                            Behavior on color {
                                enabled: root.tokens.feedbackDuration > 0
                                ColorAnimation { duration: root.tokens.feedbackDuration }
                            }
                            Rectangle {
                                width: parent.width
                                height: 1
                                y: parent.height - 1
                                color: root.tokens.hairline
                                visible: option.modelData.key !== "lyrics"
                            }
                        }
                    }
                }
            }
            // The sleep timer is runtime state, not a persisted boolean, so it
            // does not go through configure() - which accepts only the
            // settings schema's keys and would reject it anyway.
            Column {
                id: sleepSection
                width: parent.width
                spacing: root.tokens.small
                Text {
                    text: "Sleep timer"
                    color: root.tokens.text
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.bodySize
                    font.weight: Font.Medium
                }
                Row {
                    spacing: root.tokens.small
                    Repeater {
                        model: [{label: "Off", minutes: 0}, {label: "15m", minutes: 15},
                            {label: "30m", minutes: 30}, {label: "60m", minutes: 60}]
                        delegate: IslandButton {
                            required property var modelData
                            objectName: "sleepOption" + modelData.minutes
                            tokens: root.tokens
                            text: modelData.label
                            width: root.tokens.primaryTarget + root.tokens.gap
                            actionEnabled: modelData.minutes === 0
                                || (!!root.coordinator && root.coordinator.sleepArmable === true)
                            disabledReason: root.sleepUnavailableReason
                            onActiveFocusChanged: if (activeFocus) root.reveal(this)
                            onActivated: {
                                if (!root.coordinator) return;
                                if (modelData.minutes === 0) root.coordinator.cancelSleepTimer();
                                else root.coordinator.armSleepTimer(modelData.minutes);
                            }
                        }
                    }
                }
                Text {
                    objectName: "sleepStatus"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    color: root.coordinator && root.coordinator.sleepFailure ? root.tokens.error : root.tokens.secondary
                    font.family: root.tokens.fontFamily
                    font.pixelSize: root.tokens.captionSize
                    // Absolute wall-clock time, computed once per arm. A
                    // countdown would repaint every second for up to an hour and
                    // tell the user nothing more.
                    text: {
                        if (!root.coordinator) return "";
                        if (root.coordinator.sleepFailure) return Strings.sleepFailureText(root.coordinator.sleepFailure);
                        if (!root.coordinator.sleepDeadline) return "Playback keeps going until you stop it.";
                        return Strings.sleepUntil(root.coordinator.sleepDeadline) + ". "
                            + (root.coordinator.sleepLockVerified
                                ? "Locking the screen cancels it."
                                : "The screen lock cannot be seen here, so it keeps running if you lock.");
                    }
                }
            }
            // Every other setting lives in the settings window.
            Controls.Button {
                id: allSettingsButton
                objectName: "openSettingsWindow"
                visible: !!root.coordinator && typeof root.coordinator.openSettings === "function"
                text: "All settings…"
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.bodySize
                onClicked: root.coordinator.openSettings("")
                onActiveFocusChanged: if (activeFocus) root.reveal(allSettingsButton)
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Settings are saved automatically."
                color: root.tokens.secondary
                font.family: root.tokens.fontFamily
                font.pixelSize: root.tokens.captionSize
            }
        }
    }
}
