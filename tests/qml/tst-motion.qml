import QtQuick
import QtTest
import "../../qml/Motion.js" as Motion
import "../../components"

TestCase {
    id: test
    name: "Motion"
    DesignTokens { id: design }
    Component { id: driverComponent; SpringDriver {} }

    function test_openAndCloseDriversUseFixedTimings() {
        compare(design.openDuration, 420)
        compare(design.closeDuration, 450)
        var driver = createTemporaryObject(driverComponent, test)
        driver.run(0, 1, design.openResponse, design.openDamping, design.openDuration)
        compare(driver.animation.duration, 420)
        driver.run(driver.value, 0, design.closeResponse, design.closeDamping, design.closeDuration)
        compare(driver.animation.duration, 450)
        design.reducedMotion = true
        compare(design.openDuration, 0)
        compare(design.closeDuration, 0)
        design.reducedMotion = false
    }

    function samples(response, damping, until, steps) {
        var values = []
        for (var i = 0; i <= steps; ++i) values.push(Motion.springStep(until * i / steps, response, damping))
        return values
    }

    // Integrates x'' = w^2 (1 - x) - 2 z w x' with fourth-order Runge-Kutta,
    // independently of the closed form.
    function integrated(t, response, damping) {
        var w = 2 * Math.PI / response, z = damping
        var x = 0, v = 0, steps = 4000, h = t / steps
        function acceleration(px, pv) { return w * w * (1 - px) - 2 * z * w * pv }
        for (var i = 0; i < steps; ++i) {
            var k1x = v, k1v = acceleration(x, v)
            var k2x = v + h / 2 * k1v, k2v = acceleration(x + h / 2 * k1x, v + h / 2 * k1v)
            var k3x = v + h / 2 * k2v, k3v = acceleration(x + h / 2 * k2x, v + h / 2 * k2v)
            var k4x = v + h * k3v, k4v = acceleration(x + h * k3x, v + h * k3v)
            x += h / 6 * (k1x + 2 * k2x + 2 * k3x + k4x)
            v += h / 6 * (k1v + 2 * k2v + 2 * k3v + k4v)
        }
        return x
    }

    function test_closed_form_matches_integration_data() {
        return [
            { tag: "under-damped", response: 0.42, damping: 0.8 },
            { tag: "critical", response: 0.45, damping: 1.0 },
            { tag: "over-damped", response: 0.35, damping: 1.6 },
            { tag: "bouncy", response: 0.3, damping: 0.3 }
        ]
    }
    function test_closed_form_matches_integration(data) {
        for (var t = 0.05; t <= 0.8; t += 0.05)
            fuzzyCompare(Motion.springStep(t, data.response, data.damping),
                integrated(t, data.response, data.damping), 1e-6)
    }

    function test_starts_at_rest() {
        compare(Motion.springStep(0, 0.42, 0.8), 0)
        compare(Motion.springStep(-1, 0.42, 0.8), 0)
        verify(Motion.springStep(1e-4, 0.42, 1.5) < 1e-4)
    }

    function test_open_spring_overshoots_one_and_a_half_percent() {
        var peak = Math.max.apply(null, samples(0.42, 0.8, 1, 4000))
        verify(peak >= 1.013 && peak <= 1.017, "peak " + peak)
    }

    function test_critical_and_over_damped_never_overshoot_data() {
        return [{ tag: "critical", damping: 1.0 }, { tag: "over-damped", damping: 1.4 }]
    }
    function test_critical_and_over_damped_never_overshoot(data) {
        var values = samples(0.45, data.damping, 2, 4000)
        for (var i = 1; i < values.length; ++i) {
            verify(values[i] >= values[i - 1], "monotone at sample " + i)
            verify(values[i] <= 1, "no overshoot at sample " + i)
        }
    }

    function test_duration_is_where_the_envelope_settles() {
        var open = Motion.springDuration(0.42, 0.8)
        fuzzyCompare(Motion.envelope(open, 0.42, 0.8), Motion.SETTLE, 1e-9)
        var close = Motion.springDuration(0.45, 1.0)
        verify(close > 0 && close < Motion.MAX_DURATION)
        fuzzyCompare(1 - Motion.springStep(close, 0.45, 1.0), Motion.SETTLE, 1e-6)
        var over = Motion.springDuration(0.2, 1.5)
        fuzzyCompare(1 - Motion.springStep(over, 0.2, 1.5), Motion.SETTLE, 1e-6)
    }

    function test_duration_is_capped() {
        compare(Motion.springDuration(0.3, 0.3), Motion.MAX_DURATION)
        compare(Motion.springDuration(0.42, 0), Motion.MAX_DURATION)
        compare(Motion.springDuration(2, 1.0), Motion.MAX_DURATION)
    }

    function test_normalised_ends_exactly_at_one_data() {
        return [
            { tag: "open", response: 0.42, damping: 0.8, duration: 0.42 },
            { tag: "close", response: 0.45, damping: 1.0, duration: 0.45 },
            { tag: "press", response: 0.3, damping: 0.3, duration: 0.3 },
            { tag: "settled", response: 0.42, damping: 0.8, duration: Motion.springDuration(0.42, 0.8) }
        ]
    }
    function test_normalised_ends_exactly_at_one(data) {
        compare(Motion.normalised(0, data.response, data.damping, data.duration), 0)
        verify(Motion.normalised(data.duration, data.response, data.damping, data.duration) === 1)
        verify(Motion.normalised(data.duration * 2, data.response, data.damping, data.duration) === 1)
        var before = data.duration * (1 - 1e-9)
        fuzzyCompare(Motion.normalised(before, data.response, data.damping, data.duration), 1, 1e-6)
        compare(Motion.normalised(0.1, data.response, data.damping, 0), 1)
    }
    // Hyprland without animations reads as a wish for reduced motion.
    function test_desktopReducesMotionFromHyprland() {
        compare(Motion.desktopReducesMotion('{"option":"animations:enabled","int":0,"set":true}'), true)
        compare(Motion.desktopReducesMotion('{"option":"animations:enabled","int":1,"set":true}'), false)
        compare(Motion.desktopReducesMotion(""), false)
        compare(Motion.desktopReducesMotion("no such option"), false)
        compare(Motion.desktopReducesMotion("null"), false)
    }
}
