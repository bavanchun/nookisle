#include "ipc-protocol.h"
#include <QCryptographicHash>
#include <QDir>
#include <QJsonDocument>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>

class HelperProcess : public QProcess {
public:
    explicit HelperProcess(const QString &runtime, const QString &bus = {}) {
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert("XDG_RUNTIME_DIR", runtime);
        if (!bus.isEmpty()) environment.insert("DBUS_SESSION_BUS_ADDRESS", bus);
        setProcessEnvironment(environment);
        setProgram(HELPER_PATH);
    }
    ~HelperProcess() override {
        if (state() == NotRunning) return;
        closeWriteChannel();
        if (!waitForFinished(1000)) {
            terminate();
            if (!waitForFinished(1000)) { kill(); waitForFinished(1000); }
        }
    }
};

class LifecycleTest : public QObject {
    Q_OBJECT
    static QJsonObject hello(HelperProcess &process) {
        QByteArray output;
        QElapsedTimer deadline;
        deadline.start();
        while (deadline.elapsed() < 3000) {
            process.waitForReadyRead(100);
            output += process.readAllStandardOutput();
            const auto newline = output.indexOf('\n');
            if (newline >= 0) return QJsonDocument::fromJson(output.first(newline)).object();
            if (process.state() == QProcess::NotRunning) return {};
        }
        return {};
    }
private slots:
    void eofExitsAndRestartChangesGeneration() {
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        HelperProcess first(runtime.path());
        first.start();
        QVERIFY(first.waitForStarted());
        const auto firstHello = hello(first);
        QCOMPARE(firstHello["type"].toString(), "hello");
        QVERIFY(!firstHello["connectionGeneration"].toString().isEmpty());
        first.closeWriteChannel();
        QVERIFY(first.waitForFinished(2000));
        QCOMPARE(first.exitStatus(), QProcess::NormalExit);
        QCOMPARE(first.exitCode(), 0);
        HelperProcess second(runtime.path());
        second.start();
        QVERIFY(second.waitForStarted());
        const auto secondHello = hello(second);
        QCOMPARE(secondHello["type"].toString(), "hello");
        QVERIFY(secondHello["connectionGeneration"] != firstHello["connectionGeneration"]);
    }

    void singletonLeaseAndHandoff() {
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        HelperProcess owner(runtime.path());
        owner.start();
        QVERIFY(owner.waitForStarted());
        QCOMPARE(hello(owner)["type"].toString(), "hello");
        HelperProcess contender(runtime.path());
        contender.start();
        QVERIFY(contender.waitForStarted());
        QVERIFY(contender.waitForFinished(2000));
        QCOMPARE(contender.exitCode(), 73);
        QVERIFY(contender.readAllStandardError().contains("lease-unavailable"));
        QVERIFY(contender.readAllStandardOutput().isEmpty());
        QCOMPARE(owner.state(), QProcess::Running);
        owner.closeWriteChannel();
        QVERIFY(owner.waitForFinished(2000));
        QCOMPARE(owner.exitCode(), 0);
        HelperProcess successor(runtime.path());
        successor.start();
        QVERIFY(successor.waitForStarted());
        QCOMPARE(hello(successor)["type"].toString(), "hello");
    }

    // The Service stops the helper with SIGTERM: that is a clean exit that
    // releases the lease, like closing stdin.
    void sigtermExitsCleanly() {
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        HelperProcess helper(runtime.path());
        helper.start();
        QVERIFY(helper.waitForStarted());
        QCOMPARE(hello(helper)["type"].toString(), "hello");
        helper.terminate();
        QVERIFY(helper.waitForFinished(2000));
        QCOMPARE(helper.exitStatus(), QProcess::NormalExit);
        QCOMPARE(helper.exitCode(), 0);
        HelperProcess successor(runtime.path());
        successor.start();
        QVERIFY(successor.waitForStarted());
        QCOMPARE(hello(successor)["type"].toString(), "hello");
    }

    // A killed helper leaves its artwork cache behind. The next lease holder
    // removes its own session's leftovers and the untagged ones of older
    // builds, and nothing else; a contender without the lease removes nothing.
    void staleArtworkIsSweptOnceLeaseHeld() {
        QTemporaryDir runtime, outside;
        QVERIFY(runtime.isValid() && outside.isValid());
        QFile::setPermissions(runtime.path(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        const auto session = QString::fromLatin1(QCryptographicHash::hash(qgetenv("DBUS_SESSION_BUS_ADDRESS"),
            QCryptographicHash::Sha256).toHex().left(16));
        const QDir root(runtime.path());
        auto cache = [&](const QString &name) {
            QVERIFY(root.mkdir(name));
            QFile file(root.filePath(name + "/cover.png"));
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("art");
        };
        cache("nookisle-art-" + session + "-Ab12Cd");
        cache("nookisle-art-Xy34Zw");
        cache("nookisle-art-ffffffffffffffff-Qq11Rr");
        cache("nookisle-other");
        QFile kept(outside.filePath("keep.png"));
        QVERIFY(kept.open(QIODevice::WriteOnly));
        kept.close();
        QVERIFY(QFile::link(outside.path(), root.filePath("nookisle-art-" + session + "-Link00")));
        HelperProcess owner(runtime.path());
        owner.start();
        QVERIFY(owner.waitForStarted());
        QCOMPARE(hello(owner)["type"].toString(), "hello");
        QVERIFY(!root.exists("nookisle-art-" + session + "-Ab12Cd"));
        QVERIFY2(root.exists("nookisle-art-Xy34Zw/cover.png"), "an untagged older-build cache names no session and stays");
        QVERIFY2(root.exists("nookisle-art-ffffffffffffffff-Qq11Rr/cover.png"), "another session's cache stays");
        QVERIFY(root.exists("nookisle-other/cover.png"));
        QVERIFY2(QFileInfo(root.filePath("nookisle-art-" + session + "-Link00")).isSymLink(), "a link is never followed or removed");
        QVERIFY(QFile::exists(outside.filePath("keep.png")));
        // The owner's live cache survives a contender that cannot take the lease.
        cache("nookisle-art-" + session + "-Live00");
        HelperProcess contender(runtime.path());
        contender.start();
        QVERIFY(contender.waitForStarted());
        QVERIFY(contender.waitForFinished(2000));
        QCOMPARE(contender.exitCode(), 73);
        QVERIFY(root.exists("nookisle-art-" + session + "-Live00/cover.png"));
    }

    void anotherSessionsLiveCachesSurviveTheSweep() {
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        QFile::setPermissions(runtime.path(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        auto sessionOf = [](const QByteArray &address) {
            return QString::fromLatin1(QCryptographicHash::hash(address, QCryptographicHash::Sha256).toHex().left(16));
        };
        const QDir root(runtime.path());
        auto cache = [&](const QString &name) {
            QVERIFY(root.mkdir(name));
            QFile file(root.filePath(name + "/cover.png"));
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write("art");
        };
        // A second D-Bus session for the same user and runtime directory.
        QProcess otherBus;
        otherBus.start("dbus-daemon", {"--session", "--nofork", "--print-address=1"});
        QVERIFY(otherBus.waitForStarted());
        const auto stopBus = qScopeGuard([&otherBus] { otherBus.terminate(); otherBus.waitForFinished(2000); });
        QVERIFY(otherBus.waitForReadyRead(3000));
        const auto otherAddress = otherBus.readLine().trimmed();
        QVERIFY(!otherAddress.isEmpty());
        HelperProcess other(runtime.path(), QString::fromUtf8(otherAddress));
        other.start();
        QVERIFY(other.waitForStarted());
        QCOMPARE(hello(other)["type"].toString(), "hello");
        // Caches that session's helper may be using: a tagged one, and the
        // untagged name an older build gives its cache.
        cache("nookisle-art-" + sessionOf(otherAddress) + "-Ab12Cd");
        cache("nookisle-art-Xy34Zw");
        const auto session = sessionOf(qgetenv("DBUS_SESSION_BUS_ADDRESS"));
        QVERIFY(session != sessionOf(otherAddress));
        cache("nookisle-art-" + session + "-Old000");
        HelperProcess owner(runtime.path());
        owner.start();
        QVERIFY(owner.waitForStarted());
        QCOMPARE(hello(owner)["type"].toString(), "hello");
        QVERIFY2(!root.exists("nookisle-art-" + session + "-Old000"), "this session's stale cache is swept");
        QVERIFY2(root.exists("nookisle-art-" + sessionOf(otherAddress) + "-Ab12Cd/cover.png"),
            "the other session's tagged cache stays");
        QVERIFY2(root.exists("nookisle-art-Xy34Zw/cover.png"), "an untagged cache of a possibly live helper stays");
        QCOMPARE(other.state(), QProcess::Running);
    }

    void badInput_data() {
        QTest::addColumn<QByteArray>("input");
        QTest::addColumn<QByteArray>("diagnostic");
        QTest::newRow("malformed") << QByteArray("{broken}\n") << QByteArray("invalid-json");
        QTest::newRow("oversized") << QByteArray(Island::FrameLimit + 1, 'x') << QByteArray("frame-too-large");
        QTest::newRow("wrong-version") << QByteArray("{\"protocolVersion\":99,\"connectionGeneration\":\"wrong\"}\n") << QByteArray("protocol-mismatch");
    }
    void badInput() {
        QFETCH(QByteArray, input);
        QFETCH(QByteArray, diagnostic);
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        HelperProcess helper(runtime.path());
        helper.start();
        QVERIFY(helper.waitForStarted());
        QCOMPARE(hello(helper)["type"].toString(), "hello");
        QCOMPARE(helper.write(input), input.size());
        QVERIFY(helper.waitForFinished(2000));
        QCOMPARE(helper.exitStatus(), QProcess::NormalExit);
        QCOMPARE(helper.exitCode(), 4);
        QVERIFY(helper.readAllStandardError().contains(diagnostic));
    }
    void protocolFailureStopsLaterFramesInSameChunk() {
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        HelperProcess helper(runtime.path());
        helper.start();
        QVERIFY(helper.waitForStarted());
        const auto greeting = hello(helper);
        QCOMPARE(greeting["type"].toString(), "hello");
        const auto generation = greeting["connectionGeneration"].toString();
        const auto invalid = Island::encodeFrame({{"protocolVersion", 99}, {"connectionGeneration", generation}, {"type", "refresh"}});
        const auto gate = Island::encodeFrame({{"protocolVersion", 1}, {"connectionGeneration", generation},
            {"type", "controlGate"}, {"enabled", true}, {"admissionEpoch", "must-not-open"}});
        const auto command = Island::encodeFrame({{"protocolVersion", 1}, {"connectionGeneration", generation},
            {"type", "command"}, {"requestId", "must-not-run"}, {"admissionEpoch", "must-not-open"}, {"action", "PlayPause"}});
        const auto chunk = invalid + gate + command;
        QCOMPARE(helper.write(chunk), chunk.size());
        QVERIFY(helper.waitForFinished(2000));
        QCOMPARE(helper.exitCode(), 4);
        const auto output = helper.readAllStandardOutput();
        QVERIFY(!output.contains("controlGateAck"));
        QVERIFY(!output.contains("must-not-run"));
        QVERIFY(helper.readAllStandardError().contains("protocol-mismatch"));
    }
    // A watch request is acknowledged with its status; a malformed one
    // changes nothing and does not end the connection.
    void watchRequestsAreAcknowledged() {
        QTemporaryDir runtime;
        QVERIFY(runtime.isValid());
        HelperProcess helper(runtime.path());
        helper.start();
        QVERIFY(helper.waitForStarted());
        const auto greeting = hello(helper);
        const auto generation = greeting["connectionGeneration"].toString();
        auto frame = [&](const QString &id, QJsonObject fields) {
            fields["protocolVersion"] = 1;
            fields["connectionGeneration"] = generation;
            fields["type"] = "watch";
            fields["requestId"] = id;
            return Island::encodeFrame(fields);
        };
        const auto chunk = frame("bad", {{"screenshots", true}, {"screenshotDir", "relative"}})
            + frame("good", {{"reminders", false}});
        QCOMPARE(helper.write(chunk), chunk.size());
        QByteArray output;
        QElapsedTimer deadline;
        deadline.start();
        while (deadline.elapsed() < 3000 && output.count('\n') < 2) {
            helper.waitForReadyRead(100);
            output += helper.readAllStandardOutput();
        }
        QList<QJsonObject> acks;
        for (const auto &line : output.split('\n')) {
            const auto object = QJsonDocument::fromJson(line).object();
            if (object["type"] == "requestAck") acks.append(object);
        }
        QCOMPARE(acks.size(), 2);
        QCOMPARE(acks[0]["requestId"].toString(), QStringLiteral("bad"));
        QCOMPARE(acks[0]["status"].toString(), QStringLiteral("invalid"));
        QCOMPARE(acks[1]["requestId"].toString(), QStringLiteral("good"));
        QCOMPARE(acks[1]["status"].toString(), QStringLiteral("ok"));
        QCOMPARE(helper.state(), QProcess::Running);
    }
};
QTEST_GUILESS_MAIN(LifecycleTest)
#include "lifecycle-test.moc"
