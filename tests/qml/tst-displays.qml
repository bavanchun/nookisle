import QtQuick
import QtTest
import "../../qml/Displays.js" as Displays

TestCase {
    name: "Displays"
    readonly property var two: ["eDP-1", "DP-2"]
    // Follow is the behaviour from before the setting: the focused screen,
    // or the first one.
    function test_follow() {
        compare(Displays.primaryScreen("follow", "", two, "DP-2"), "DP-2")
        compare(Displays.primaryScreen("follow", "DP-2", two, "eDP-1"), "eDP-1", "follow ignores preferredDisplay")
        compare(Displays.primaryScreen("follow", "", two, ""), "eDP-1", "no focus: the first screen")
        compare(Displays.primaryScreen("follow", "", two, "HDMI-A-1"), "eDP-1", "a focus not in the list: the first screen")
        compare(Displays.primaryScreen("follow", "", [], "eDP-1"), "")
        compare(Displays.extraScreens("follow", two, "eDP-1"), [])
    }
    function test_unknownModeIsFollow() {
        compare(Displays.mode("bogus"), "follow")
        compare(Displays.mode(undefined), "follow")
        compare(Displays.primaryScreen("bogus", "DP-2", two, "eDP-1"), "eDP-1")
    }
    // Fixed stays on its screen whatever has focus, and falls back to follow
    // while that screen is missing.
    function test_fixed() {
        compare(Displays.primaryScreen("fixed", "DP-2", two, "eDP-1"), "DP-2")
        compare(Displays.primaryScreen("fixed", "DP-2", ["eDP-1"], "eDP-1"), "eDP-1", "a missing screen falls back to follow")
        compare(Displays.primaryScreen("fixed", "", two, "DP-2"), "DP-2", "no preferred screen: follow")
        compare(Displays.extraScreens("fixed", two, "DP-2"), [])
    }
    // All: a primary that never moves with focus, and a window for every
    // other screen.
    function test_all() {
        compare(Displays.primaryScreen("all", "", two, "DP-2"), "eDP-1", "the first screen, not the focused one")
        compare(Displays.primaryScreen("all", "DP-2", two, "eDP-1"), "DP-2", "or preferredDisplay when connected")
        compare(Displays.primaryScreen("all", "HDMI-A-1", two, "DP-2"), "eDP-1")
        compare(Displays.extraScreens("all", two, "eDP-1"), ["DP-2"])
        compare(Displays.extraScreens("all", ["eDP-1"], "eDP-1"), [], "one screen: no extra window")
        compare(Displays.extraScreens("all", ["eDP-1", "DP-2", "HDMI-A-1"], "DP-2"), ["eDP-1", "HDMI-A-1"])
    }
    // The island under the pointer draws the live spectrum, whatever has
    // keyboard focus; with the pointer on none, the primary does. Exactly
    // one island draws it either way.
    function test_spectrumOnlyUnderThePointer() {
        var pointerOnExtra = [{ name: "eDP-1", visible: true, hovered: false }, { name: "DP-2", visible: true, hovered: true }]
        compare(Displays.spectrumOwner("eDP-1", pointerOnExtra), "DP-2", "the pointer's island, not the focused one")
        var nowhere = [{ name: "eDP-1", visible: true, hovered: false }, { name: "DP-2", visible: true, hovered: false }]
        compare(Displays.spectrumOwner("eDP-1", nowhere), "eDP-1", "no pointer: the primary")
        compare(Displays.spectrumOwner("", []), "")
        verify(Displays.spectrumLive("follow", "eDP-1", "DP-2"), "one island always draws it")
        verify(Displays.spectrumLive("all", "DP-2", "DP-2"))
        verify(!Displays.spectrumLive("all", "eDP-1", "DP-2"))
        var owner = Displays.spectrumOwner("eDP-1", nowhere)
        compare(["eDP-1", "DP-2"].filter(name => Displays.spectrumLive("all", name, owner)), ["eDP-1"],
            "one island, not every one")
    }
    // The spectrum owner is always a visible island: a primary hidden over
    // fullscreen hands it to the first visible one.
    function test_spectrumOwnerSkipsHiddenIslands() {
        compare(Displays.spectrumOwner("eDP-1", [{ name: "eDP-1", visible: false, hovered: false },
            { name: "DP-2", visible: true, hovered: false }]), "DP-2", "hidden primary, visible extra, no hover")
        compare(Displays.spectrumOwner("eDP-1", [{ name: "eDP-1", visible: true, hovered: false },
            { name: "DP-2", visible: false, hovered: true }]), "eDP-1", "a hidden island is never the owner")
        compare(Displays.spectrumOwner("eDP-1", [{ name: "eDP-1", visible: false, hovered: false },
            { name: "DP-2", visible: false, hovered: false }]), "eDP-1", "none visible: the primary")
    }
    // Lines pause only while the island drawing them is open: a closed
    // owner keeps its bars live while another island is open.
    function test_spectrumPausedFollowsTheOwner() {
        var closedOwnerOtherOpen = [{ name: "eDP-1", visible: true, expanded: false },
            { name: "DP-2", visible: true, expanded: true }]
        compare(Displays.spectrumPaused("eDP-1", closedOwnerOtherOpen), false)
        compare(Displays.spectrumPaused("DP-2", closedOwnerOtherOpen), true)
        compare(Displays.spectrumPaused("eDP-1", [{ name: "eDP-1", visible: false, expanded: true }]), false,
            "a hidden island draws nothing to pause")
    }
    // The island the pointer is on, for the bars' centre-peek suppression:
    // a hovered visible island first, then an open visible one, primary
    // first; "" for none.
    function test_pointerIsland() {
        compare(Displays.pointerIsland([{ name: "eDP-1", visible: false, hovered: false, expanded: false },
            { name: "DP-2", visible: true, hovered: true, expanded: false }]), "DP-2", "hidden primary, hovered extra")
        compare(Displays.pointerIsland([{ name: "eDP-1", visible: true, hovered: false, expanded: true },
            { name: "DP-2", visible: true, hovered: true, expanded: false }]), "DP-2", "the hovered island, not just an open one")
        compare(Displays.pointerIsland([{ name: "eDP-1", visible: true, hovered: false, expanded: false },
            { name: "DP-2", visible: true, hovered: false, expanded: true }]), "DP-2")
        compare(Displays.pointerIsland([{ name: "eDP-1", visible: true, hovered: true, expanded: false }]), "eDP-1")
        compare(Displays.pointerIsland([{ name: "eDP-1", visible: false, hovered: true, expanded: true }]), "",
            "a hidden island has no pointer")
        compare(Displays.pointerIsland([{ name: "eDP-1", visible: true, hovered: false, expanded: false }]), "")
    }
    // The Service's view state covers every visible window: fullscreen on
    // the primary must not report the island hidden while another is open.
    function test_viewStateAcrossWindows() {
        compare(Displays.viewState({ visible: false, expanded: false }, [{ visible: true, expanded: true }]),
            { visible: true, expanded: true }, "fullscreen primary, open extra")
        compare(Displays.viewState({ visible: true, expanded: true }, []), { visible: true, expanded: true })
        compare(Displays.viewState({ visible: false, expanded: true }, []), { visible: false, expanded: false })
        compare(Displays.viewState({ visible: true, expanded: false }, [{ visible: false, expanded: true }]),
            { visible: true, expanded: false }, "a hidden extra does not count")
    }
    // The shared readout and peeks are suppressed only when no window can
    // show them; with no extra window this is exactly the primary's rule.
    function test_readoutAndPeekSuppressionAcrossWindows() {
        compare(Displays.readoutSuppressed(true, [], false), true)
        compare(Displays.readoutSuppressed(false, [], false), false)
        compare(Displays.readoutSuppressed(true, [{ visible: true, expanded: false }], false), false,
            "fullscreen primary, closed extra shows it")
        compare(Displays.readoutSuppressed(true, [{ visible: true, expanded: true }], false), true,
            "an open extra without the open readout")
        compare(Displays.readoutSuppressed(true, [{ visible: true, expanded: true }], true), false)
        compare(Displays.readoutSuppressed(true, [{ visible: false, expanded: false }], true), true,
            "a hidden extra shows nothing")
        compare(Displays.peekSuppressed(true, []), true)
        compare(Displays.peekSuppressed(false, []), false)
        compare(Displays.peekSuppressed(true, [{ visible: true, expanded: false }]), false)
        compare(Displays.peekSuppressed(true, [{ visible: true, expanded: true }]), true)
    }
    function test_oneCamera() {
        verify(Displays.cameraAllowed("follow", "eDP-1", "DP-2"))
        verify(Displays.cameraAllowed("all", "eDP-1", ""), "no island opened yet")
        verify(Displays.cameraAllowed("all", "DP-2", "DP-2"))
        verify(!Displays.cameraAllowed("all", "eDP-1", "DP-2"), "only the island opened last")
    }
    // The camera follows the islands open: the last opened owns it, and when
    // it closes the island opened before takes it back, or nobody.
    function test_cameraOwnerIsHandedBack() {
        var order = Displays.cameraOpenOrder([], "eDP-1", true)
        compare(Displays.cameraOwnerOf(order), "eDP-1")
        order = Displays.cameraOpenOrder(order, "DP-2", true)
        compare(Displays.cameraOwnerOf(order), "DP-2", "the island opened last takes it")
        verify(!Displays.cameraAllowed("all", "eDP-1", Displays.cameraOwnerOf(order)))
        order = Displays.cameraOpenOrder(order, "DP-2", false)
        compare(Displays.cameraOwnerOf(order), "eDP-1", "closing it hands the camera back to the island still open")
        verify(Displays.cameraAllowed("all", "eDP-1", Displays.cameraOwnerOf(order)))
        order = Displays.cameraOpenOrder(order, "eDP-1", true)
        compare(order, ["eDP-1"], "reopening does not duplicate")
        order = Displays.cameraOpenOrder(order, "eDP-1", false)
        compare(Displays.cameraOwnerOf(order), "", "nobody open, nobody owns it")
    }
    // A second screen unplugged while its island is open sends no close. Its
    // entry is pruned when the screens change, so reconnecting that screen
    // (a new island, closed) leaves the camera with the island still open.
    function test_unpluggedIslandNeverKeepsTheCamera() {
        var order = Displays.cameraOpenOrder([], "eDP-1", true)
        order = Displays.cameraOpenOrder(order, "HDMI-A-1", true)
        compare(Displays.cameraOwnerOf(order), "HDMI-A-1")
        order = Displays.pruneCameraOrder(order, ["eDP-1"])
        compare(order, ["eDP-1"], "unplugging drops the vanished island")
        compare(Displays.cameraOwnerOf(order), "eDP-1", "the open primary takes the camera")
        order = Displays.pruneCameraOrder(order, ["eDP-1", "HDMI-A-1"])
        compare(Displays.cameraOwnerOf(order), "eDP-1", "reconnecting does not hand it to the new, closed island")
        verify(Displays.cameraAllowed("all", "eDP-1", Displays.cameraOwnerOf(order)))
        verify(!Displays.cameraAllowed("all", "HDMI-A-1", Displays.cameraOwnerOf(order)))
        order = Displays.cameraOpenOrder(order, "HDMI-A-1", true)
        compare(Displays.cameraOwnerOf(order), "HDMI-A-1", "until it opens again")
        compare(Displays.pruneCameraOrder(order, []), [], "no screens, no owner")
    }
}
