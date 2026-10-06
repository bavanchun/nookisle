import QtQuick
import QtTest
import "../../qml/FullscreenPolicy.js" as FullscreenPolicy

TestCase {
    name: "FullscreenPolicy"

    function test_modes() {
        var spotify = { presentation: { desktopEntry: "spotify.desktop", controlScope: "application" } }
        compare(FullscreenPolicy.shouldHide("always", false, "spotify", spotify), false)
        compare(FullscreenPolicy.shouldHide("always", true, "other", null), true)
        compare(FullscreenPolicy.shouldHide("never", true, "spotify", spotify), false)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "Spotify", spotify), true)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "other", spotify), false)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "spotify", null), false)
    }

    function test_browserClassAndUnknownIdentity() {
        var chrome = { presentation: { controlScope: "document", browserClass: "google-chrome",
            desktopEntry: "spotify" } }
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "Google-Chrome", chrome), true)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "spotify", chrome), false)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "google-chrome-beta", chrome), false)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "", chrome), false)
        compare(FullscreenPolicy.shouldHide("nowPlayingOnly", true, "spotify", { presentation: {} }), false)
        compare(FullscreenPolicy.shouldHide("bogus", true, "spotify", { presentation: { desktopEntry: "spotify" } }), false)
    }
}
