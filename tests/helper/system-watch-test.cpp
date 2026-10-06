#include "system-watch.h"
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>
#include <sys/stat.h>
#include <unistd.h>

using Island::SystemWatch;

class SystemWatchTest : public QObject {
    Q_OBJECT
    QTemporaryDir root;
    QString dev, proc, tmp, shots, transient;

    static void write(const QString &path, const QByteArray &bytes) {
        QDir().mkpath(QFileInfo(path).path());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(bytes);
    }
    // A process in the fake /proc: its comm and, optionally, an open fd.
    void process(int pid, const QByteArray &comm, const QString &holds = {}) {
        const QString base = proc + '/' + QString::number(pid);
        QDir().mkpath(base + "/fd");
        write(base + "/comm", comm + "\n");
        if (!holds.isEmpty()) QVERIFY(QFile::link(holds, base + "/fd/3"));
    }
    SystemWatch::Paths paths() const {
        SystemWatch::Paths value;
        value.dev = dev; value.proc = proc; value.tmp = tmp; value.transient = transient;
        value.screenshots = shots; value.shellPid = 111; value.selfPid = 112; value.uid = getuid();
        return value;
    }
    static QList<QJsonObject> of(const QSignalSpy &spy, const QString &kind) {
        QList<QJsonObject> events;
        for (const auto &args : spy) {
            const auto object = args.at(0).toJsonObject();
            if (object.value("kind") == kind) events.append(object);
        }
        return events;
    }
private slots:
    void init() {
        QVERIFY(root.isValid());
        const QString base = root.path() + '/' + QString::number(QRandomGenerator::global()->generate());
        dev = base + "/dev"; proc = base + "/proc"; tmp = base + "/tmp"; shots = base + "/shots";
        transient = base + "/transient";
        for (const auto &path : {dev, proc, tmp, shots, transient}) QVERIFY(QDir().mkpath(path));
    }
    void names() {
        QVERIFY(SystemWatch::isVideoDevice("video0"));
        QVERIFY(SystemWatch::isVideoDevice("video12"));
        QVERIFY(!SystemWatch::isVideoDevice("video"));
        QVERIFY(!SystemWatch::isVideoDevice("videox"));
        QVERIFY(!SystemWatch::isVideoDevice("media0"));
        QVERIFY(SystemWatch::isScreenshotName("screenshot-2026-09-27_16-06-37.png"));
        QVERIFY(!SystemWatch::isScreenshotName("screenshot-.png"));
        QVERIFY(!SystemWatch::isScreenshotName("photo-2026.png"));
        QVERIFY(!SystemWatch::isScreenshotName("screenshot-2026.png.tmp"));
        QVERIFY(SystemWatch::isReminderUnit("omarchy-reminder-5m-1790500000.timer"));
        QVERIFY(!SystemWatch::isReminderUnit("omarchy-reminder-5m-1790500000.service"));
        QVERIFY(!SystemWatch::isReminderUnit("omarchy-reminder-x.timer"));
        QVERIFY(!SystemWatch::isReminderUnit("app-Hyprland-foo.scope"));
    }
    // Holders are this uid's processes with the device open, except the
    // shell hosting the island, the helper, and PipeWire's own daemons.
    void holderScan() {
        write(dev + "/video0", "");
        write(dev + "/video1", "");
        const QStringList devices{dev + "/video0", dev + "/video1"};
        process(200, "chromium", dev + "/video0");
        process(201, "obs", dev + "/video1");
        process(202, "chromium", dev + "/video1");
        process(111, "quickshell", dev + "/video0");
        process(112, "nookisle-helper", dev + "/video0");
        process(203, "pipewire", dev + "/video0");
        process(204, "wireplumber", dev + "/video0");
        process(205, "firefox");
        QDir().mkpath(proc + "/self");
        const auto holders = SystemWatch::cameraHolders(proc, devices, {111, 112}, getuid());
        QCOMPARE(holders, (QStringList{"chromium", "obs"}));
        QVERIFY(SystemWatch::cameraHolders(proc, {}, {}, getuid()).isEmpty());
        QVERIFY(SystemWatch::cameraHolders(proc, devices, {}, getuid() + 1).isEmpty());
    }
    // Opening a device triggers one debounced scan: a burst of opens and
    // closes becomes a single event, sent only when the holders change.
    void cameraEvents() {
        write(dev + "/video0", "");
        SystemWatch watch(paths());
        watch.cameraDebounceMs = 150;
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"cameraDevices", true}}));
        QCOMPARE(of(spy, "camera").size(), 1);
        QCOMPARE(of(spy, "camera").last().value("holders").toArray().size(), 0);
        process(300, "zoom", dev + "/video0");
        for (int i = 0; i < 5; ++i) {
            QFile device(dev + "/video0");
            QVERIFY(device.open(QIODevice::ReadOnly));
        }
        QTRY_COMPARE(of(spy, "camera").size(), 2);
        QCOMPARE(of(spy, "camera").last().value("holders").toArray(), QJsonArray({"zoom"}));
        QTest::qWait(300);
        QCOMPARE(of(spy, "camera").size(), 2);
        QFile device(dev + "/video0");
        QVERIFY(device.open(QIODevice::ReadOnly));
        device.close();
        QTest::qWait(300);
        QCOMPARE(of(spy, "camera").size(), 2);
    }
    void cameraHotplug() {
        SystemWatch watch(paths());
        watch.cameraDebounceMs = 50;
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"cameraDevices", true}}));
        write(dev + "/video4", "");
        process(301, "cheese", dev + "/video4");
        QTRY_COMPARE(of(spy, "camera").size(), 2);
        QCOMPARE(of(spy, "camera").last().value("holders").toArray(), QJsonArray({"cheese"}));
        QFile::remove(proc + "/301/fd/3");
        QFile device(dev + "/video4");
        QVERIFY(device.open(QIODevice::ReadOnly));
        device.close();
        QTRY_COMPARE(of(spy, "camera").size(), 3);
        QVERIFY(of(spy, "camera").last().value("holders").toArray().isEmpty());
    }
    void recordingStartAndStop() {
        SystemWatch watch(paths());
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"recording", true}}));
        QCOMPARE(of(spy, "recording").size(), 1);
        QCOMPARE(of(spy, "recording").last().value("active").toBool(), false);
        write(tmp + "/unrelated", "x");
        write(tmp + "/omarchy-screenrecord-filename", "/home/me/Videos/screenrecording-1.mp4\n");
        QTRY_COMPARE(of(spy, "recording").size(), 2);
        const auto started = of(spy, "recording").last();
        QVERIFY(started.value("active").toBool());
        QCOMPARE(started.value("path").toString(), QStringLiteral("/home/me/Videos/screenrecording-1.mp4"));
        const double mtime = QFileInfo(tmp + "/omarchy-screenrecord-filename").lastModified().toMSecsSinceEpoch();
        QCOMPARE(started.value("startedAt").toDouble(), mtime);
        QFile::remove(tmp + "/omarchy-screenrecord-filename");
        QTRY_COMPARE(of(spy, "recording").size(), 3);
        const auto stopped = of(spy, "recording").last();
        QVERIFY(!stopped.value("active").toBool());
        // The stop names the saved file.
        QCOMPARE(stopped.value("path").toString(), QStringLiteral("/home/me/Videos/screenrecording-1.mp4"));
        QCOMPARE(spy.size(), 3);
    }
    // A marker left by a crash does not count unless the recorder runs.
    void staleMarkerAtStart() {
        write(tmp + "/omarchy-screenrecord-filename", "/home/me/Videos/old.mp4");
        {
            SystemWatch watch(paths());
            QSignalSpy spy(&watch, &SystemWatch::event);
            QVERIFY(watch.configure({{"recording", true}}));
            QCOMPARE(of(spy, "recording").last().value("active").toBool(), false);
        }
        process(400, "gpu-screen-reco");
        SystemWatch watch(paths());
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"recording", true}}));
        QVERIFY(of(spy, "recording").last().value("active").toBool());
    }
    // The recording marker in /tmp must be a regular file owned by the user's UID.
    void recordingSymlinkAndUidRejection() {
        process(400, "gpu-screen-reco");
        write(tmp + "/target.mp4", "/home/me/Videos/real.mp4");
        QVERIFY(QFile::link(tmp + "/target.mp4", tmp + "/omarchy-screenrecord-filename"));
        {
            SystemWatch watch(paths());
            QSignalSpy spy(&watch, &SystemWatch::event);
            QVERIFY(watch.configure({{"recording", true}}));
            QCOMPARE(of(spy, "recording").last().value("active").toBool(), false);
        }
        QFile::remove(tmp + "/omarchy-screenrecord-filename");
        write(tmp + "/omarchy-screenrecord-filename", "/home/me/Videos/regular.mp4");
        {
            auto foreignPaths = paths();
            foreignPaths.uid = getuid() + 1;
            SystemWatch watch(foreignPaths);
            QSignalSpy spy(&watch, &SystemWatch::event);
            QVERIFY(watch.configure({{"recording", true}}));
            QCOMPARE(of(spy, "recording").last().value("active").toBool(), false);
        }
    }
    // A FIFO at the marker path must not block and must be ignored.
    void recordingFifoIgnored() {
        process(400, "gpu-screen-reco");
        const auto fifoPath = QFile::encodeName(tmp + "/omarchy-screenrecord-filename");
        QCOMPARE(::mkfifo(fifoPath.constData(), 0600), 0);
        {
            SystemWatch watch(paths());
            QSignalSpy spy(&watch, &SystemWatch::event);
            QVERIFY(watch.configure({{"recording", true}}));
            QCOMPARE(of(spy, "recording").last().value("active").toBool(), false);
        }
        QFile::remove(tmp + "/omarchy-screenrecord-filename");
    }
    void screenshots() {
        SystemWatch watch(paths());
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"screenshots", true}}));
        write(shots + "/notes.png", "x");
        write(shots + "/screenshot-2026-09-27_16-06-37.png", "png");
        QTRY_COMPARE(of(spy, "screenshot").size(), 1);
        QCOMPARE(of(spy, "screenshot").last().value("path").toString(), shots + "/screenshot-2026-09-27_16-06-37.png");
        write(tmp + "/screenshot-2026-09-27_16-07-00.png", "png");
        QVERIFY(QFile::rename(tmp + "/screenshot-2026-09-27_16-07-00.png", shots + "/screenshot-2026-09-27_16-07-00.png"));
        QTRY_COMPARE(of(spy, "screenshot").size(), 2);
        QVERIFY(watch.configure({}));
        write(shots + "/screenshot-2026-09-27_16-08-00.png", "png");
        QTest::qWait(100);
        QCOMPARE(of(spy, "screenshot").size(), 2);
    }
    void screenshotOverrideAndRateLimit() {
        const QString other = shots + "/other";
        QVERIFY(QDir().mkpath(other));
        SystemWatch watch(paths());
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"screenshots", true}, {"screenshotDir", other}}));
        for (int i = 0; i < SystemWatch::ScreenshotRateLimit + 5; ++i)
            write(other + QStringLiteral("/screenshot-%1.png").arg(i), "png");
        QTest::qWait(150);
        QCOMPARE(of(spy, "screenshot").size(), SystemWatch::ScreenshotRateLimit);
    }
    void reminders() {
        SystemWatch watch(paths());
        watch.reminderDebounceMs = 30;
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"reminders", true}}));
        write(transient + "/app-Hyprland-foo.scope", "");
        write(transient + "/omarchy-reminder-5m-1790500000.timer", "");
        write(transient + "/omarchy-reminder-5m-1790500000.service", "");
        QTRY_COMPARE(of(spy, "reminders").size(), 1);
        QTest::qWait(100);
        QCOMPARE(of(spy, "reminders").size(), 1);
        QFile::remove(transient + "/omarchy-reminder-5m-1790500000.timer");
        QTRY_COMPARE(of(spy, "reminders").size(), 2);
    }
    void missingTransientDirectory() {
        auto missing = paths();
        missing.transient = root.path() + "/absent";
        SystemWatch watch(missing);
        QSignalSpy spy(&watch, &SystemWatch::event);
        QVERIFY(watch.configure({{"reminders", true}}));
        QCOMPARE(of(spy, "reminders").size(), 1);
        QVERIFY(of(spy, "reminders").last().value("unavailable").toBool());
    }
    void invalidRequests() {
        SystemWatch watch(paths());
        QVERIFY(!watch.configure({{"cameraDevices", "yes"}}));
        QVERIFY(!watch.configure({{"screenshots", true}, {"screenshotDir", "relative/dir"}}));
        QVERIFY(!watch.configure({{"screenshots", true}, {"screenshotDir", root.path() + "/absent"}}));
        QVERIFY(!watch.configure({{"screenshotDir", 5}}));
        QVERIFY(!watch.configure({{"screenshotDir", QString(SystemWatch::PathLimit + 1, 'a')}}));
        QVERIFY(watch.configure({{"screenshotDir", ""}}));
    }
};

QTEST_GUILESS_MAIN(SystemWatchTest)
#include "system-watch-test.moc"
