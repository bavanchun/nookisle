#!/usr/bin/env node
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, resolve, dirname} from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const source = readFileSync(join(repository, "Panel.qml"), "utf8");
function section(start, end) {
    const begin = source.indexOf(start), finish = source.indexOf(end, begin);
    if (begin < 0 || finish < 0) throw new Error("Production Panel power contract not found");
    return source.slice(begin, finish);
}
// Run Panel's real notification bindings and sample handler with an in-memory
// power source. No UPower service or compositor window is needed.
const models = section("    PeekModel {\n        id: peekModel", "    Binding {\n        target: peekModel");
const sampleHandler = section("    Connections {\n        target: powerLoader.item", "    // trackToken changes");
const directory = mkdtempSync(join(tmpdir(), "nookisle-power-test-"));
try {
    const path = join(directory, "tst-power.qml");
    writeFileSync(path, `import QtQuick
import QtTest
import "file:${join(repository, "components")}"
TestCase {
    id: test
    name: "ProductionPanelPower"
    width: 320
    height: 120
    when: windowShown
    visible: true
    Component {
        id: panelComponent
        Item {
            id: root
            width: 320
            height: 120
            property bool islandMode: true
            property var coordinator: ({ power: true, peek: false })
            property alias settings: surfaceObject.settings
            property alias battery: batteryModel
            property alias peek: peekModel
            property alias gauge: gauge
            property alias powerSource: sampleSource
            DesignTokens { id: palette; reducedMotion: true }
            // Panel reads the island surface as root.surface.
            readonly property var surface: surfaceObject
            QtObject {
                id: surfaceObject
                property var settings: ({ showPowerNotifications: false, powerStyle: "banner" })
            }
            QtObject {
                id: sampleSource
                property var reading: ({ present: false, onBattery: true, level: 0 })
                signal sample(bool present, bool onBattery, real level)
                function emitReading(next) {
                    reading = next;
                    sample(next.present, next.onBattery, next.level);
                }
            }
            QtObject { id: powerLoader; property var item: sampleSource }
${models}
${sampleHandler}
            BatteryGauge {
                id: gauge
                reading: powerLoader.item ? powerLoader.item.reading : batteryModel.reading
            }
        }
    }
    function reading(onBattery, level) {
        return { present: true, onBattery: onBattery, level: level,
            state: onBattery ? "Discharging" : "Charging", powerSaver: false };
    }
    function test_notificationsOffStillUpdatesGauge_data() {
        return [{ tag: "banner", style: "banner" }, { tag: "peek", style: "peek" }];
    }
    function test_notificationsOffStillUpdatesGauge(data) {
        var panel = createTemporaryObject(panelComponent, test);
        panel.settings = { showPowerNotifications: false, powerStyle: data.style };
        panel.powerSource.emitReading(reading(true, 0.54));
        panel.powerSource.emitReading(reading(false, 0.72));
        compare(panel.battery.bannerActive, false, "no charger banner");
        compare(panel.peek.active, false, "no charger peek");
        compare(panel.gauge.reading.level, 0.72, "header gauge still follows the sample");
        compare(findChild(panel.gauge, "batteryPercent").text, "72%");
        panel.settings = { showPowerNotifications: true, powerStyle: data.style };
        panel.powerSource.emitReading(reading(true, 0.70));
        compare(data.style === "banner" ? panel.battery.bannerActive : panel.peek.active, true,
            "the same charger event announces when notifications are enabled");
    }
}
`);
    const environment = {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
        QT_QPA_PLATFORMTHEME: "generic", NO_AT_BRIDGE: "1", QML_DISABLE_DISK_CACHE: "1"};
    delete environment.DISPLAY;
    delete environment.WAYLAND_DISPLAY;
    const result = spawnSync("dbus-run-session", ["--config-file=" + join(repository, "tests/qml/session-bus.conf"),
        "--", process.argv[2] || "/usr/lib/qt6/bin/qmltestrunner", "-input", path],
        {env: environment, encoding: "utf8", timeout: 15000});
    process.stdout.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    if (result.error) throw result.error;
    process.exitCode = result.status === 0 && !/Binding loop|TypeError|ReferenceError/.test(
        (result.stdout || "") + (result.stderr || "")) ? 0 : 1;
} finally {
    rmSync(directory, {recursive: true, force: true});
}
