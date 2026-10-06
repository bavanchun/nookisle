import QtQuick
import QtTest
import "../../components"

TestCase {
    id: test
    name: "IslandControls"
    width: 384
    height: 208
    when: windowShown
    visible: true
    DesignTokens {
        id: design
        reducedMotion: true
    }
    QtObject {
        id: facade
        property bool uiAllowed: true
        property var selectedEndpoint: ({
                token: {
                    owner: "a"
                },
                trackToken: {
                    id: "first"
                }
            })
        property var calls: []
        property int captures: 0
        function captureIntent() {
            captures++;
            return JSON.parse(JSON.stringify({
                endpointToken: selectedEndpoint.token,
                trackToken: selectedEndpoint.trackToken
            }));
        }
        function invoke(action, intent, value) {
            calls = calls.concat([
                {
                    action: action,
                    intent: intent,
                    value: value
                }
            ]);
        }
    }
    Component {
        id: sliderComponent
        IntentSlider {
            tokens: design
            coordinator: facade
            width: 240
            height: 32
            sample: 10
            maximum: 100
            step: 5
        }
    }
    Component {
        id: coveredStage
        Item {
            width: 300
            height: 120
            property alias slider: coveredSlider
            property alias button: coveredButton
            IntentSlider {
                id: coveredSlider
                tokens: design
                coordinator: facade
                width: 240
                height: 32
                sample: 10
                maximum: 100
                step: 5
            }
            IslandButton {
                id: coveredButton
                y: 40
                tokens: design
                coordinator: facade
                actionName: "PlayPause"
                iconName: "play"
                accessibleLabel: "Play"
                width: 40
                height: 40
            }
        }
    }
    Component {
        id: buttonComponent
        IslandButton {
            tokens: design
            coordinator: facade
            actionName: "PlayPause"
            iconName: "play"
            accessibleLabel: "Play"
            width: 40
            height: 40
        }
    }
    function init() {
        facade.uiAllowed = true;
        facade.calls = [];
        facade.captures = 0;
        facade.selectedEndpoint = {
            token: {
                owner: "a"
            },
            trackToken: {
                id: "first"
            }
        };
    }
    function test_seekCapturedOnceAndCommittedOnce() {
        var control = createTemporaryObject(sliderComponent, test);
        verify(control.beginGesture());
        for (var i = 0; i < 20; ++i)
            control.updateGesture(i);
        compare(facade.captures, 1);
        compare(facade.calls.length, 0);
        control.commitGesture();
        control.commitGesture();
        compare(facade.calls.length, 1);
        compare(facade.calls[0].value, 19);
        compare(facade.calls[0].intent.endpointToken.owner, "a");
    }
    function test_trackChangeCancelsSeek() {
        var control = createTemporaryObject(sliderComponent, test);
        control.beginGesture();
        control.updateGesture(40);
        facade.selectedEndpoint = {
            token: {
                owner: "a"
            },
            trackToken: {
                id: "second"
            }
        };
        verify(!control.gesturing);
        control.commitGesture();
        compare(facade.calls.length, 0);
    }
    function test_lockAndHideCancel() {
        var control = createTemporaryObject(sliderComponent, test);
        control.beginGesture();
        facade.uiAllowed = false;
        control.commitGesture();
        compare(facade.calls.length, 0);
        facade.uiAllowed = true;
        control.beginGesture();
        control.visible = false;
        control.commitGesture();
        compare(facade.calls.length, 0);
    }
    function test_disabledAndUnknownLengthDoNotDispatch() {
        var control = createTemporaryObject(sliderComponent, test, {
            actionEnabled: false
        });
        verify(!control.beginGesture());
        control.keyboardStep(5);
        compare(facade.calls.length, 0);
    }
    function test_volumeCapturesAndClamps() {
        var control = createTemporaryObject(sliderComponent, test, {
            action: "SetVolume",
            sample: 0.4,
            maximum: 1,
            step: 0.05
        });
        control.beginGesture();
        control.updateGesture(2);
        control.commitGesture();
        compare(facade.calls[0].action, "SetVolume");
        compare(facade.calls[0].value, 1);
        compare(facade.captures, 1);
    }
    function test_keyboardSeekSingleRelease() {
        var control = createTemporaryObject(sliderComponent, test);
        var slider = findChild(control, "intentSlider");
        slider.forceActiveFocus();
        keyPress(Qt.Key_Right);
        compare(facade.calls.length, 0);
        keyRelease(Qt.Key_Right);
        compare(facade.calls.length, 1);
        compare(facade.calls[0].value, 15);
        keyPress(Qt.Key_Right);
        keyClick(Qt.Key_Escape);
        keyRelease(Qt.Key_Right);
        compare(facade.calls.length, 1);
    }
    function test_pointerSeekSingleRelease() {
        var control = createTemporaryObject(sliderComponent, test);
        mousePress(control, 40, 16);
        mouseMove(control, 180, 16);
        compare(facade.calls.length, 0);
        mouseRelease(control, 180, 16);
        compare(facade.calls.length, 1);
        compare(facade.captures, 1);
    }
    function test_keyboardFocusLossCancelsUnsentSeek() {
        var control = createTemporaryObject(sliderComponent, test);
        var other = createTemporaryObject(buttonComponent, test, { y: 80 });
        var slider = findChild(control, "intentSlider");
        slider.forceActiveFocus(Qt.TabFocusReason);
        keyPress(Qt.Key_Right);
        verify(control.gesturing);
        compare(control.displayValue, 15);
        compare(facade.calls.length, 0);
        other.forceActiveFocus(Qt.TabFocusReason);
        verify(!slider.activeFocus);
        verify(!control.gesturing);
        compare(control.capturedIntent, null);
        compare(control.displayValue, control.sample);
        keyRelease(Qt.Key_Right);
        control.commitGesture();
        compare(facade.calls.length, 0);
        slider.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Right);
        compare(facade.calls.length, 1);
        compare(facade.calls[0].value, 15);
        compare(facade.captures, 2);
    }
    function test_buttonSourceSwitchDoesNotDispatch() {
        var control = createTemporaryObject(buttonComponent, test);
        mousePress(control, 20, 20);
        facade.selectedEndpoint = {
            token: {
                owner: "b"
            },
            trackToken: {
                id: "second"
            }
        };
        mouseRelease(control, 20, 20);
        compare(facade.calls.length, 0);
    }
    function test_buttonDisabledAndPending() {
        var control = createTemporaryObject(buttonComponent, test, {
            actionEnabled: false
        });
        mouseClick(control, 20, 20);
        compare(facade.calls.length, 0);
        control.actionEnabled = true;
        control.pending = true;
        mouseClick(control, 20, 20);
        compare(facade.calls.length, 0);
        control.pending = false;
        mouseClick(control, 20, 20);
        compare(facade.calls.length, 1);
    }
    function test_buttonTooltipShowsDisabledAndPendingReason() {
        var control = createTemporaryObject(buttonComponent, test, {
            actionEnabled: false,
            disabledReason: "This source does not support playback"
        });
        var tooltip = findChild(control, "buttonToolTip");
        verify(tooltip);
        control.forceActiveFocus(Qt.TabFocusReason);
        tryCompare(tooltip, "visible", true);
        compare(tooltip.contentItem.text, control.disabledReason);
        control.actionEnabled = true;
        control.pending = true;
        compare(tooltip.contentItem.text, "Sending command");
        compare(facade.calls.length, 0);
    }

    // The overlay keeps the player visible and turns it inert. Effective-enabled
    // propagates from the ancestor and fires neither onActionEnabledChanged nor
    // onVisibleChanged, so without an explicit handler an in-flight gesture
    // would survive - or worse, commit - behind an opaque surface.
    function test_ancestorDisableCancelsSliderGestureWithoutCommitting() {
        var stage = createTemporaryObject(coveredStage, test);
        var control = stage.slider;
        verify(control.beginGesture());
        control.updateGesture(60);
        verify(control.gesturing);
        stage.enabled = false;
        verify(!control.gesturing, "the gesture survived the stage going inert");
        compare(facade.calls.length, 0, "the gesture committed while inert");
        control.commitGesture();
        compare(facade.calls.length, 0, "a commit after the stage went inert still dispatched");
    }
    function test_commitRefusesWhileDisabledRegardlessOfBindingOrder() {
        var stage = createTemporaryObject(coveredStage, test);
        var control = stage.slider;
        control.beginGesture();
        control.updateGesture(40);
        // Simulate the race directly: the ancestor goes inert and a commit
        // arrives anyway, which is what an ungrab-driven onPressedChanged does.
        stage.enabled = false;
        control.commitGesture();
        compare(facade.calls.length, 0);
    }
    function test_ancestorDisableClearsCapturedButtonIntent() {
        var stage = createTemporaryObject(coveredStage, test);
        var control = stage.button;
        control.capturedIntent = facade.captureIntent();
        verify(control.capturedIntent);
        stage.enabled = false;
        verify(!control.capturedIntent, "a captured press outlived the stage going inert");
    }
}
