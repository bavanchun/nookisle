#include "backlight-monitor.h"
#include <QtTest>

// The helper's own backlight watch: which uevents it reports, and that it
// opens udev's netlink socket itself, restartably.
class BacklightMonitorTest : public QObject {
    Q_OBJECT
private slots:
    void reportsOnlyBacklightChanges() {
        QVERIFY(Island::BacklightMonitor::relevant("change", "backlight", "intel_backlight"));
        QVERIFY(Island::BacklightMonitor::relevant("change", "backlight", "amdgpu_bl1"));
        QVERIFY(!Island::BacklightMonitor::relevant("add", "backlight", "intel_backlight"));
        QVERIFY(!Island::BacklightMonitor::relevant("change", "leds", "tpacpi::kbd_backlight"));
        QVERIFY(!Island::BacklightMonitor::relevant("change", "backlight", ""));
        QVERIFY(!Island::BacklightMonitor::relevant("change", "backlight", "../escape"));
        QVERIFY(!Island::BacklightMonitor::relevant("change", "backlight", QByteArray(65, 'a')));
    }
    void opensAndClosesTheNetlinkWatch() {
        Island::BacklightMonitor monitor;
        if (!monitor.start()) QSKIP("udev's netlink socket is unavailable in this environment");
        QVERIFY(monitor.running());
        QVERIFY(monitor.start());
        monitor.stop();
        QVERIFY(!monitor.running());
        QVERIFY(monitor.start());
    }
};

QTEST_GUILESS_MAIN(BacklightMonitorTest)
#include "backlight-monitor-test.moc"
