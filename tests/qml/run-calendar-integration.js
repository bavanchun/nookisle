#!/usr/bin/env node
import {mkdtempSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {dirname, join, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const calendarTests = process.argv[2];
const qmlRunner = process.argv[3];
if (!calendarTests || !qmlRunner) throw new Error("Expected calendar test binary and qmltestrunner");

// The native parser produces the same window items the helper sends to Home.
const window = spawnSync(calendarTests, ["--ui-window-fixture"],
    {encoding: "utf8", timeout: 15000});
if (window.error) throw window.error;
if (window.status !== 0) throw new Error(`Calendar fixture failed: ${window.stderr}`);
const items = JSON.parse(window.stdout);

const directory = mkdtempSync(join(tmpdir(), "nookisle-calendar-ui-"));
try {
    const input = join(directory, "tst-calendar-integration.qml");
    writeFileSync(input, `import QtQuick
import QtTest
import "file:${join(repository, "components")}"

TestCase {
    id: test
    name: "CalendarParserToHome"
    width: 480
    height: 400
    visible: true
    when: windowShown
    DesignTokens { id: design; reducedMotion: true }
    QtObject { id: fixtureSource; property var items: ${JSON.stringify(items)}; property var errors: [] }
    Component {
        id: panelFactory
        CalendarPanel {
            tokens: design
            source: fixtureSource
            now: new Date(2026, 8, 28, 12)
            options: ({ autoScrollToNextEvent: false, calendarSelection: [] })
        }
    }
    function test_recurrenceWindowReachesRowsAndMarker() {
        var panel = createTemporaryObject(panelFactory, test)
        compare(panel.rows.length, 2, "both series reach Home on the selected day")
        compare(panel.rows[0].uid, "supported", "WKST and BYMONTH expand into the window")
        compare(panel.rows[1].uid, "unsupported", "the limited rule keeps its first instance")
        var first = findChild(panel, "calendarRow-0")
        var second = findChild(panel, "calendarRow-1")
        verify(first && second, "both rows are rendered")
        verify(!findChild(first, "calendarUnsupported").visible, "supported recurrence has no warning")
        verify(findChild(second, "calendarUnsupported").visible, "unsupported RRULE shows its warning")
    }
}
`);
    const environment = {...process.env, TZ: "UTC", QT_QPA_PLATFORM: "offscreen",
        QT_QUICK_BACKEND: "software", QT_QPA_PLATFORMTHEME: "generic",
        NO_AT_BRIDGE: "1", QML_DISABLE_DISK_CACHE: "1"};
    delete environment.DISPLAY;
    delete environment.WAYLAND_DISPLAY;
    const result = spawnSync("dbus-run-session", [
        "--config-file=" + join(repository, "tests/qml/session-bus.conf"),
        "--", qmlRunner, "-input", input],
    {env: environment, encoding: "utf8", timeout: 20000});
    process.stdout.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    if (result.error) throw result.error;
    process.exitCode = result.status === 0 && !/Binding loop|TypeError|ReferenceError/.test(
        (result.stdout || "") + (result.stderr || "")) ? 0 : 1;
} finally {
    rmSync(directory, {recursive: true, force: true});
}
