#include "mpris-registry.h"
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVirtualObject>
#include <QSignalSpy>
#include <QUuid>
#include <QProcess>
#include <QtTest>
#include <memory>
#include <limits>
#include <vector>

// Every fixture owns a separate real connection on the isolated session bus.
class PlayerService : public QDBusVirtualObject {
public:
    const QString connectionName = QUuid::createUuid().toString();
    QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, connectionName);
    QString serviceName;
    int calls = 0;
    bool delay = false;
    bool fail = false;
    bool delayProperties = false;
    int propertyCalls = 0;
    QString title = "Track one";
    // Tri-state: -1 omits the property entirely, which is the common real case.
    int canRaise = -1;
    int shuffle = -1;
    QString loopStatus;
    qlonglong length = 120000000;
    QString artUrl;
    QList<QDBusMessage> pending;
    QList<QDBusMessage> propertyReplies;
    QStringList receivedMembers;
    QStringList receivedInterfaces;
    QList<QList<QVariant>> receivedArguments;
    explicit PlayerService(QString name) : serviceName(std::move(name)) {
        bus.registerVirtualObject("/org/mpris/MediaPlayer2", this);
    }
    ~PlayerService() override {
        bus.unregisterService(serviceName);
        bus.unregisterObject("/org/mpris/MediaPlayer2");
        QDBusConnection::disconnectFromBus(connectionName);
    }
    bool claim() { return bus.registerService(serviceName); }
    void release() { bus.unregisterService(serviceName); }
    // The Player interface's introspected access for the two toggles.
    QString shuffleAccess = "readwrite";
    QString loopAccess = "readwrite";
    QString introspect(const QString &) const override {
        return QString("<interface name=\"org.mpris.MediaPlayer2.Player\">"
            "<property name=\"Shuffle\" type=\"b\" access=\"%1\"/>"
            "<property name=\"LoopStatus\" type=\"s\" access=\"%2\"/>"
            "<property name=\"Volume\" type=\"d\" access=\"readwrite\"/>"
            "</interface>").arg(shuffleAccess, loopAccess);
    }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override {
        if (message.interface() == "org.example.IslandTest" && message.member() == "Barrier") {
            connection.send(message.createReply());
            return true;
        }
        if (message.interface() == "org.freedesktop.DBus.Properties" && message.member() == "GetAll") {
            ++propertyCalls;
            QVariantMap values;
            if (message.arguments().front().toString() == "org.mpris.MediaPlayer2") {
                values = {{"Identity", "Isolated test player"}, {"DesktopEntry", "test-player"}};
                if (canRaise >= 0) values["CanRaise"] = canRaise == 1;
            } else {
                values = {{"PlaybackStatus", "Paused"}, {"CanControl", true}, {"CanPlay", true},
                    {"CanPause", true}, {"CanSeek", true}, {"CanGoNext", true}, {"CanGoPrevious", true},
                    {"Position", qlonglong(1000000)}, {"Volume", 0.5}, {"Rate", 1.0},
                    {"Metadata", QVariantMap{{"mpris:trackid", QVariant::fromValue(QDBusObjectPath("/track/one"))},
                        {"mpris:length", length}, {"xesam:title", title}}}};
                if (!artUrl.isEmpty()) {
                    auto metadata = values["Metadata"].toMap();
                    metadata["mpris:artUrl"] = artUrl;
                    values["Metadata"] = metadata;
                }
                if (shuffle >= 0) values["Shuffle"] = shuffle == 1;
                if (!loopStatus.isEmpty()) values["LoopStatus"] = loopStatus;
            }
            const auto reply = message.createReply({QVariant::fromValue(values)});
            if (delayProperties) propertyReplies.append(reply);
            else connection.send(reply);
            return true;
        }
        if (message.interface() == "org.freedesktop.DBus.Properties" && message.member() == "Set") {
            ++calls;
            receivedMembers.append(message.member());
            receivedInterfaces.append(message.interface());
            receivedArguments.append(message.arguments());
            if (delay) pending.append(message);
            else connection.send(fail ? message.createErrorReply("org.mpris.MediaPlayer2.Error.Failed", "Test rejection") : message.createReply());
            return true;
        }
        // Raise lives on the root interface, so the fixture must answer both or a
        // correctly dispatched Raise comes back as a transport error.
        if (message.interface() != "org.mpris.MediaPlayer2.Player"
            && message.interface() != "org.mpris.MediaPlayer2") return false;
        ++calls;
        receivedMembers.append(message.member());
        receivedInterfaces.append(message.interface());
        receivedArguments.append(message.arguments());
        if (delay) pending.append(message);
        else connection.send(fail ? message.createErrorReply("org.mpris.MediaPlayer2.Error.Failed", "Test rejection") : message.createReply());
        return true;
    }
    void complete() {
        const auto replies = std::exchange(pending, {});
        for (const auto &message : replies) bus.send(message.createReply());
    }
    void completeProperties() {
        const auto replies = std::exchange(propertyReplies, {});
        for (const auto &reply : replies) bus.send(reply);
    }
    void seek(qlonglong microseconds) {
        auto signal = QDBusMessage::createSignal("/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Seeked");
        signal << microseconds;
        bus.send(signal);
    }
    void publish(const QVariantMap &values) {
        auto signal = QDBusMessage::createSignal("/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged");
        signal << QString("org.mpris.MediaPlayer2.Player") << values << QStringList{};
        bus.send(signal);
    }
    bool barrier() {
        // Same sender and destination as production GetAll: this reply proves
        // every earlier call to this unique owner reached its service object.
        auto call = QDBusMessage::createMethodCall(bus.baseService(), "/org/mpris/MediaPlayer2",
                                                  "org.example.IslandTest", "Barrier");
        QDBusPendingCallWatcher watcher(QDBusConnection::sessionBus().asyncCall(call, 1000));
        QSignalSpy finished(&watcher, &QDBusPendingCallWatcher::finished);
        if (!watcher.isFinished() && !finished.wait(1000)) return false;
        return !QDBusPendingReply<>(watcher).isError();
    }
};

class RegistryTest : public QObject {
    Q_OBJECT
    const QString name = "org.mpris.MediaPlayer2.island_test";
    static QJsonObject command(const QJsonObject &token, const QString &id, const QString &epoch = "unlocked") {
        return {{"requestId", id}, {"admissionEpoch", epoch}, {"endpointToken", token}, {"action", "PlayPause"}};
    }
    static bool ready(Island::MprisRegistry &registry) {
        const auto endpoints = registry.endpoints();
        return endpoints.size() == 1 && endpoints[0]["capabilities"].toObject()["CanControl"].toBool();
    }
private slots:
    // Player text is cut to 4096 UTF-8 bytes on a code-point boundary, in one
    // pass: long non-ASCII metadata costs microseconds, not a re-encode per
    // character removed.
    void boundedTextCutsOnceAtACodePoint() {
        const QString cjk(8000, QChar(0x4e2d));
        QElapsedTimer timer;
        timer.start();
        QString bounded;
        for (int i = 0; i < 20; ++i) bounded = Island::boundedText(cjk);
        QVERIFY2(timer.elapsed() < 50, QByteArray::number(timer.elapsed()));
        QCOMPARE(bounded.toUtf8().size(), 4095);
        QCOMPARE(bounded, QString(1365, QChar(0x4e2d)));
        const QString emoji = QString("a") + QString::fromUtf8("\xf0\x9f\x98\x80").repeated(1500);
        const auto cut = Island::boundedText(emoji);
        QVERIFY(cut.toUtf8().size() <= 4096);
        QVERIFY(!cut.back().isHighSurrogate());
        QCOMPARE(cut, emoji.left(cut.size()));
        QCOMPARE(Island::boundedText(QString("short")), QString("short"));
    }
    // The root property filter stringifies everything it admits, so a boolean
    // routed through it arrives as "true"/"false" - and "false" is truthy, which
    // would admit a player that explicitly refuses to be raised.
    void canRaiseIsABooleanAndDefaultsToFalse() {
        PlayerService player(name);
        player.canRaise = 1;
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QCOMPARE(registry.endpoints()[0]["presentation"].toObject()["desktopEntry"].toString(), "test-player");
        const auto raised = registry.endpoints()[0]["capabilities"].toObject()["CanRaise"];
        QVERIFY2(raised.isBool(), "CanRaise reached the wire as something other than a boolean");
        QVERIFY(raised.toBool());
    }
    void canRaiseFalseIsHonoured() {
        PlayerService player(name);
        player.canRaise = 0;
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QVERIFY(!registry.endpoints()[0]["capabilities"].toObject()["CanRaise"].toBool());
    }
    void absentCanRaiseMeansFalse() {
        PlayerService player(name);
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QVERIFY(!registry.endpoints()[0]["capabilities"].toObject()["CanRaise"].toBool());
    }
    void raiseDispatchesOnTheRootInterface() {
        PlayerService player(name);
        player.canRaise = 1;
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QString status;
        connect(&registry, &Island::MprisRegistry::result, this,
            [&status](const QString &, const QString &value) { status = value; });
        registry.setGate("epoch", true);
        registry.command({{"requestId", "r1"}, {"admissionEpoch", "epoch"},
            {"endpointToken", registry.endpoints()[0]["token"].toObject()}, {"action", "Raise"}});
        QTRY_VERIFY_WITH_TIMEOUT(!status.isEmpty(), 3000);
        QCOMPARE(status, QString("success"));
        QVERIFY2(player.receivedMembers.contains("Raise"), "Raise never reached the player");
        QCOMPARE(player.receivedInterfaces.at(player.receivedMembers.indexOf("Raise")),
                 QString("org.mpris.MediaPlayer2"));
    }
    void raiseIsRejectedWithoutTheCapability() {
        PlayerService player(name);
        player.canRaise = 0;
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QString status;
        connect(&registry, &Island::MprisRegistry::result, this,
            [&status](const QString &, const QString &value) { status = value; });
        registry.setGate("epoch", true);
        registry.command({{"requestId", "r2"}, {"admissionEpoch", "epoch"},
            {"endpointToken", registry.endpoints()[0]["token"].toObject()}, {"action", "Raise"}});
        QTRY_VERIFY_WITH_TIMEOUT(!status.isEmpty(), 3000);
        QCOMPARE(status, QString("unsupported"));
        QVERIFY(!player.receivedMembers.contains("Raise"));
    }
    void unknownDurationCannotSeek() {
        PlayerService player(name);
        player.length = std::numeric_limits<qlonglong>::max();
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto endpoint = registry.endpoints()[0];
        QCOMPARE(endpoint["lengthSeconds"].toDouble(), 0.0);
        QVERIFY(endpoint["capabilities"].toObject()["CanSeek"].toBool());
        QVERIFY(!endpoint["capabilities"].toObject()["CanSetPosition"].toBool());
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        auto request = command(endpoint["token"].toObject(), "unknown-duration");
        request["action"] = "SetPosition";
        request["trackToken"] = endpoint["trackToken"];
        request["value"] = 1.0;
        registry.command(request);
        QCOMPARE(results.size(), 1);
        QCOMPARE(results[0][1].toString(), "unsupported");
        QCOMPARE(player.calls, 0);
        request["action"] = "Seek";
        request["value"] = -15;
        registry.command(request);
        QTRY_COMPARE(results.size(), 2);
        QCOMPARE(results[1][1].toString(), "success");
        QCOMPARE(player.receivedMembers.last(), "Seek");
    }

    void shuffleAndLoopPropertiesFollowSignals() {
        PlayerService player(name);
        player.shuffle = 1; player.loopStatus = "Playlist";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QTRY_VERIFY(registry.endpoints()[0]["capabilities"].toObject()["CanShuffle"].toBool());
        auto endpoint = registry.endpoints()[0];
        QVERIFY(endpoint["shuffle"].toBool());
        QCOMPARE(endpoint["loopStatus"].toString(), "Playlist");
        QVERIFY(endpoint["capabilities"].toObject()["CanLoop"].toBool());
        QVERIFY(!endpoint["capabilities"].toObject()["CanFavorite"].toBool());
        player.publish({{"Shuffle", false}, {"LoopStatus", "Track"}});
        QTRY_COMPARE(registry.endpoints()[0]["loopStatus"].toString(), "Track");
        QVERIFY(!registry.endpoints()[0]["shuffle"].toBool());
        player.publish({{"Shuffle", "false"}, {"LoopStatus", "Bogus"}});
        QTRY_VERIFY(!registry.endpoints()[0]["capabilities"].toObject()["CanLoop"].toBool());
        QVERIFY(!registry.endpoints()[0]["capabilities"].toObject()["CanShuffle"].toBool());
        QVERIFY(registry.endpoints()[0]["loopStatus"].isNull());
    }

    // A player that declares the toggles read-only answers every Set with
    // PropertyReadOnly, so present values alone never offer the controls.
    void readOnlyTogglePropertiesStayUnavailable() {
        PlayerService player(name);
        player.shuffle = 1; player.loopStatus = "Playlist";
        player.shuffleAccess = "read";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QTRY_VERIFY(registry.endpoints()[0]["capabilities"].toObject()["CanLoop"].toBool());
        const auto endpoint = registry.endpoints()[0];
        QVERIFY(!endpoint["capabilities"].toObject()["CanShuffle"].toBool());
        QVERIFY(endpoint["shuffle"].toBool());
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        auto request = command(endpoint["token"].toObject(), "read-only");
        request["action"] = "SetShuffle"; request["value"] = false;
        registry.command(request);
        QCOMPARE(results.takeFirst()[1].toString(), "unsupported");
        QCOMPARE(player.calls, 0);

        PlayerService other("org.mpris.MediaPlayer2.readonly");
        other.shuffle = 0; other.loopStatus = "None";
        other.shuffleAccess = "read"; other.loopAccess = "read";
        QVERIFY(other.claim());
        QTRY_COMPARE(registry.endpoints().size(), 2);
        QTest::qWait(200);
        for (const auto &entry : registry.endpoints()) {
            if (entry["token"].toObject()["wellKnownName"].toString() != other.serviceName) continue;
            QVERIFY(!entry["capabilities"].toObject()["CanShuffle"].toBool());
            QVERIFY(!entry["capabilities"].toObject()["CanLoop"].toBool());
        }
    }

    // A seek while paused has no progress subscription to carry it, so it
    // republishes the endpoints with the new position at once.
    void pausedSeekPublishesItsPosition() {
        PlayerService player(name); QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        QCOMPARE(registry.endpoints()[0]["status"].toString(), "Paused");
        QTest::qWait(100);
        QSignalSpy changes(&registry, &Island::MprisRegistry::changed);
        player.seek(100000000);
        QTRY_VERIFY(changes.size() >= 1);
        QCOMPARE(registry.endpoints()[0]["positionSeconds"].toDouble(), 100.0);
    }
    // Once the artwork selection is hidden or cancelled nothing retains the
    // cached file, and the loader may evict it: no endpoint may keep
    // advertising its path, and the browser endpoints are told to drop
    // theirs too.
    void artworkPathIsWithdrawnWhenSelectionEnds() {
        PlayerService player(name);
        player.artUrl = "https://art.example.test/cover.png";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        registry.setGate("unlocked", true);
        registry.setRemoteArtworkEnabled(true);
        const auto token = registry.endpoints()[0]["token"].toObject();
        auto publish = [&] {
            registry.selectArtwork(token, true);
            QVERIFY(!registry.artworkGeneration_.isEmpty());
            emit registry.artwork_.ready(registry.artworkGeneration_, "/run/user/test/nookisle-art-x/cover.png");
            QCOMPARE(registry.endpoints()[0]["artworkPath"].toString(), QString("/run/user/test/nookisle-art-x/cover.png"));
        };
        QSignalSpy cleared(&registry, &Island::MprisRegistry::artworkCleared);
        publish();
        cleared.clear();
        registry.selectArtwork(token, false);
        // Hidden: the path is withdrawn.
        QCOMPARE(registry.endpoints()[0]["artworkPath"].toString(), QString());
        QCOMPARE(cleared.size(), 1);
        publish();
        cleared.clear();
        registry.selectArtwork({}, true);
        // Cancelled: the path is withdrawn.
        QCOMPARE(registry.endpoints()[0]["artworkPath"].toString(), QString());
        QCOMPARE(cleared.size(), 1);
        registry.selectArtwork({}, false);
        // Nothing published, nothing to withdraw.
        QCOMPARE(cleared.size(), 1);
    }
    // Remote consent governs network fetches only: a player's file:// cover
    // loads with it off, while an https cover waits for it.
    void localCoverNeedsNoRemoteConsent() {
        PlayerService player(name);
        player.artUrl = "file:///run/user/test/player-cover.png";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        registry.setGate("unlocked", true);
        registry.setRemoteArtworkEnabled(false);
        const auto token = registry.endpoints()[0]["token"].toObject();
        registry.selectArtwork(token, true);
        QVERIFY(!registry.artworkGeneration_.isEmpty());
        emit registry.artwork_.ready(registry.artworkGeneration_, "/run/user/test/nookisle-art-x/local.png");
        QCOMPARE(registry.endpoints()[0]["artworkPath"].toString(), QString("/run/user/test/nookisle-art-x/local.png"));
    }
    void networkCoverWaitsForRemoteConsent() {
        PlayerService player(name);
        player.artUrl = "https://art.example.test/cover.png";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        registry.setGate("unlocked", true);
        registry.setRemoteArtworkEnabled(false);
        registry.selectArtwork(registry.endpoints()[0]["token"].toObject(), true);
        QVERIFY(registry.artworkGeneration_.isEmpty());
        emit registry.artwork_.ready(QStringLiteral("any"), "/run/user/test/nookisle-art-x/cover.png");
        QCOMPARE(registry.endpoints()[0]["artworkPath"].toString(), QString());
        registry.setRemoteArtworkEnabled(true);
        QVERIFY(!registry.artworkGeneration_.isEmpty());
    }
    void absentTogglePropertiesStayUnavailable() {
        PlayerService player(name); QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        auto caps = registry.endpoints()[0]["capabilities"].toObject();
        QVERIFY(!caps["CanShuffle"].toBool()); QVERIFY(!caps["CanLoop"].toBool());
        QVERIFY(registry.endpoints()[0]["shuffle"].isNull());
        QVERIFY(registry.endpoints()[0]["loopStatus"].isNull());
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        auto request = command(registry.endpoints()[0]["token"].toObject(), "absent");
        request["action"] = "SetShuffle"; request["value"] = true;
        registry.command(request);
        QCOMPARE(results.takeFirst()[1].toString(), "unsupported");
        QCOMPARE(player.calls, 0);
    }

    void spotifyDesktopDoesNotAdvertiseIgnoredToggleWrites() {
        PlayerService player("org.mpris.MediaPlayer2.spotify");
        player.shuffle = 0; player.loopStatus = "None";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto endpoint = registry.endpoints()[0];
        QVERIFY(!endpoint["capabilities"].toObject()["CanShuffle"].toBool());
        QVERIFY(!endpoint["capabilities"].toObject()["CanLoop"].toBool());
        QCOMPARE(endpoint["shuffle"].toBool(), false);
        QCOMPARE(endpoint["loopStatus"].toString(), "None");
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        auto request = command(endpoint["token"].toObject(), "spotify-shuffle");
        request["action"] = "SetShuffle"; request["value"] = true;
        registry.command(request); QCOMPARE(results.takeFirst()[1].toString(), "unsupported");
        request["action"] = "SetLoopStatus"; request["value"] = "Playlist";
        registry.command(request); QCOMPARE(results.takeFirst()[1].toString(), "unsupported");
        QCOMPARE(player.calls, 0);
    }

    void toggleAndRelativeSeekValidateAndWaitForSignals() {
        PlayerService player(name); player.shuffle = 0; player.loopStatus = "None";
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start(); QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto token = registry.endpoints()[0]["token"].toObject();
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        auto request = command(token, "closed"); request["action"] = "SetShuffle"; request["value"] = true;
        registry.command(request); QCOMPARE(results.takeFirst()[1].toString(), "closed");
        registry.setGate("unlocked", true);
        request["requestId"] = "invalid"; request["value"] = "true";
        registry.command(request); QCOMPARE(results.takeFirst()[1].toString(), "invalid-value");
        request["requestId"] = "shuffle"; request["value"] = true; player.delay = true;
        registry.command(request); QTRY_COMPARE(player.calls, 1);
        QCOMPARE(player.receivedInterfaces.last(), "org.freedesktop.DBus.Properties");
        QCOMPARE(player.receivedArguments.last()[1].toString(), "Shuffle");
        QVERIFY(!registry.endpoints()[0]["shuffle"].toBool());
        request["requestId"] = "busy"; registry.command(request);
        QCOMPARE(results.takeFirst()[1].toString(), "busy");
        player.complete(); QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results.takeFirst()[1].toString(), "success");
        QVERIFY(!registry.endpoints()[0]["shuffle"].toBool());
        player.publish({{"Shuffle", true}}); QTRY_VERIFY(registry.endpoints()[0]["shuffle"].toBool());
        player.delay = false;
        request["action"] = "SetLoopStatus"; request["value"] = "Invalid";
        registry.command(request); QCOMPARE(results.takeFirst()[1].toString(), "invalid-value");
        request["value"] = "Playlist"; registry.command(request);
        QTRY_COMPARE(results.size(), 1); QCOMPARE(results.takeFirst()[1].toString(), "success");
        QCOMPARE(player.receivedArguments.last()[1].toString(), "LoopStatus");
        QCOMPARE(registry.endpoints()[0]["loopStatus"].toString(), "None");
        request["action"] = "Seek"; request["value"] = -15.25;
        registry.command(request); QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results.takeFirst()[1].toString(), "success");
        QCOMPARE(player.receivedMembers.last(), "Seek");
        QCOMPARE(player.receivedArguments.last()[0].toLongLong(), qlonglong(-15250000));
        request["value"] = 3601;
        registry.command(request); QCOMPARE(results.takeFirst()[1].toString(), "invalid-value");
        QCOMPARE(player.calls, 3);
    }

    void asyncSuccessErrorBusyAndGate() {
        PlayerService player(name);
        QVERIFY(player.bus.isConnected());
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto token = registry.endpoints()[0]["token"].toObject();
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        registry.command(command(token, "closed"));
        QCOMPARE(results.takeFirst()[1].toString(), "closed");
        registry.setGate("unlocked", true);
        registry.command(command(token, "stale", "previous"));
        QCOMPARE(results.takeFirst()[1].toString(), "closed");
        QCOMPARE(player.calls, 0);
        player.delay = true;
        registry.command(command(token, "first"));
        QCOMPARE(results.size(), 0);
        QTRY_COMPARE(player.calls, 1);
        QCOMPARE(results.size(), 0);
        registry.command(command(token, "second"));
        QCOMPARE(results.takeFirst()[1].toString(), "busy");
        player.complete();
        QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results[0][0].toString(), "first");
        QCOMPARE(results.takeFirst()[1].toString(), "success");
        QCOMPARE(player.receivedMembers, QStringList{"PlayPause"});
        player.delay = false;
        player.fail = true;
        registry.command(command(token, "failure"));
        QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results.takeFirst()[1].toString(), "error");
        QCOMPARE(player.calls, 2);
    }

    void replacementNeverReceivesOldToken() {
        PlayerService oldPlayer(name), replacement(name);
        QVERIFY(oldPlayer.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto oldToken = registry.endpoints()[0]["token"].toObject();
        QCOMPARE(oldToken["uniqueOwner"].toString(), oldPlayer.bus.baseService());
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        oldPlayer.release();
        QVERIFY(replacement.claim());
        // The registry may or may not have observed replacement here. Either
        // rejection or delivery to the captured old owner is safe.
        registry.command(command(oldToken, "racing"));
        QTRY_COMPARE(results.size(), 1);
        QVERIFY(results[0][1] == "success" || results[0][1] == "target-gone");
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry) && registry.endpoints()[0]["token"].toObject()["uniqueOwner"].toString() == replacement.bus.baseService(), 3000);
        const auto newToken = registry.endpoints()[0]["token"].toObject();
        QVERIFY(newToken != oldToken);
        QCOMPARE(replacement.calls, 0);
        results.clear();
        registry.command(command(oldToken, "obsolete"));
        QCOMPARE(results.takeFirst()[1].toString(), "target-gone");
        auto staleShuffle = command(oldToken, "stale-shuffle");
        staleShuffle["action"] = "SetShuffle"; staleShuffle["value"] = true;
        registry.command(staleShuffle);
        QCOMPARE(results.takeFirst()[1].toString(), "target-gone");
        QCOMPARE(replacement.calls, 0);
        registry.command(command(newToken, "current"));
        QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results.takeFirst()[1].toString(), "success");
        QCOMPARE(replacement.calls, 1);
        qInfo().noquote() << "owner-route:" << oldToken["uniqueOwner"].toString()
                          << "->" << newToken["uniqueOwner"].toString()
                          << "old-token replacement deliveries: 0; current-token deliveries:" << replacement.calls;
    }

    void pendingReplyAfterGateClosureIsDiscarded() {
        PlayerService player(name);
        QVERIFY(player.claim());
        player.delay = true;
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto token = registry.endpoints()[0]["token"].toObject();
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        registry.command(command(token, "already-dispatched"));
        QTRY_COMPARE(player.calls, 1);
        registry.setGate("locked", false);
        player.complete();
        QTest::qWait(100);
        QCOMPARE(results.size(), 0);
        registry.command(command(token, "after-barrier"));
        QCOMPARE(results.takeFirst()[1].toString(), "closed");
        registry.setGate("new-unlock", true);
        registry.command(command(token, "old-epoch"));
        QCOMPARE(results.takeFirst()[1].toString(), "closed");
        player.delay = false;
        registry.command(command(token, "new-epoch", "new-unlock"));
        QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results.takeFirst()[1].toString(), "success");
        QCOMPARE(player.calls, 2);
    }

    void oldOwnerCompletionCannotSucceedForReplacement() {
        PlayerService oldPlayer(name), replacement(name);
        QVERIFY(oldPlayer.claim());
        oldPlayer.delay = true;
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        const auto oldToken = registry.endpoints()[0]["token"].toObject();
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        registry.command(command(oldToken, "old-pending"));
        QTRY_COMPARE(oldPlayer.calls, 1);
        oldPlayer.release();
        QVERIFY(replacement.claim());
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry) && registry.endpoints()[0]["token"].toObject()["uniqueOwner"].toString() == replacement.bus.baseService(), 3000);
        oldPlayer.complete();
        QTRY_COMPARE(results.size(), 1);
        QCOMPARE(results[0][0].toString(), "old-pending");
        QCOMPARE(results[0][1].toString(), "target-gone");
        QCOMPARE(replacement.calls, 0);
    }

    void timeoutHasOneResultAndNoRetry() {
        PlayerService player(name);
        QVERIFY(player.claim());
        player.delay = true;
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QTRY_VERIFY_WITH_TIMEOUT(ready(registry), 3000);
        registry.setGate("unlocked", true);
        QSignalSpy results(&registry, &Island::MprisRegistry::result);
        registry.command(command(registry.endpoints()[0]["token"].toObject(), "timeout"));
        QTRY_COMPARE_WITH_TIMEOUT(results.size(), 1, 4500);
        QCOMPARE(results[0][1].toString(), "timeout");
        QCOMPARE(player.calls, 1);
        player.complete();
        QTest::qWait(100);
        QCOMPARE(results.size(), 1);
    }

    // A peer that keeps re-taking an MPRIS name and never answers must not
    // grow the registry's outstanding calls past its read limit: the
    // introspection each new owner gets counts against the same budget as
    // its property reads.
    void silentOwnerChurnKeepsEveryCallBounded() {
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        registry.start();
        QProcess peer;
        peer.start("python3", {QStringLiteral(SILENT_OWNER), "org.mpris.MediaPlayer2.silentchurn", "200"});
        QVERIFY(peer.waitForStarted());
        QTRY_VERIFY_WITH_TIMEOUT(peer.canReadLine(), 6000);
        const auto counts = QString::fromLatin1(peer.readLine()).split(' ');
        QCOMPARE(counts.size(), 2);
        const int introspections = counts[0].toInt(), reads = counts[1].toInt();
        QVERIFY2(introspections + reads <= 128,
                 qPrintable(QString("%1 introspections and %2 reads outstanding").arg(introspections).arg(reads)));
        QVERIFY(introspections > 0);
        QVERIFY(registry.activeReads_ <= 128);
        peer.closeWriteChannel();
        QVERIFY(peer.waitForFinished(5000));
    }
    void ownerChurnKeepsOutstandingPropertyCallsBounded() {
        std::vector<std::unique_ptr<PlayerService>> owners;
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        QSignalSpy changes(&registry, &Island::MprisRegistry::changed);
        registry.start();
        QElapsedTimer elapsed;
        elapsed.start();
        int requests = 0;
        for (int i = 0; i < 72; ++i) {
            if (!owners.empty()) owners.back()->release();
            owners.push_back(std::make_unique<PlayerService>(name));
            auto &player = *owners.back();
            player.delayProperties = true;
            player.title = QString("Owner %1").arg(i);
            QVERIFY(player.bus.isConnected());
            QVERIFY(player.claim());
            const auto adopted = [&] {
                const auto endpoints = registry.endpoints();
                return endpoints.size() == 1 && endpoints[0]["token"].toObject()["uniqueOwner"].toString() == player.bus.baseService();
            };
            while (!adopted()) QVERIFY(changes.wait(1000));
            QVERIFY(player.barrier());
            requests += player.propertyCalls;
            // No property reply has been released, and owners remain alive.
            QVERIFY2(requests <= 128, qPrintable(QString("%1 GetAll calls still outstanding after %2 owners").arg(requests).arg(i + 1)));
        }
        // Keep the run below the production deadline so timeout cannot release
        // credits and make an unbounded implementation appear bounded.
        QVERIFY2(elapsed.elapsed() < 2500, "Owner churn exceeded the pre-timeout observation window");
        // Introspections share the read budget and are answered at once, so
        // once their replies are processed every slot holds a delayed GetAll.
        const auto pendingReads = [&] {
            int total = 0;
            for (const auto &player : owners) total += player->propertyCalls;
            return total;
        };
        QTRY_COMPARE_WITH_TIMEOUT(pendingReads(), 128, 500);
        QCOMPARE(registry.activeReads_, 128);
        QCOMPARE(owners.back()->propertyCalls, 0);
        QVERIFY(!ready(registry));
        for (auto &player : owners) {
            QVERIFY(player->bus.isConnected());
            player->delayProperties = false;
            player->completeProperties();
        }
        while (!ready(registry)) QVERIFY(changes.wait(1000));
        QCOMPARE(owners.back()->propertyCalls, 2);
        QCOMPARE(registry.endpoints()[0]["presentation"].toObject()["title"].toString(), "Owner 71");
        qInfo() << "owner-churn: 72 live connections; peak pending GetAll requests:" << requests
                << "; current owner resumed with" << owners.back()->propertyCalls << "reads";
    }

    void delayedGetAllCannotOverwriteNewerMetadataSignal() {
        PlayerService player(name);
        player.delayProperties = true;
        QVERIFY(player.claim());
        Island::MprisRegistry registry(QDBusConnection::sessionBus());
        QSignalSpy changes(&registry, &Island::MprisRegistry::changed);
        registry.start();
        while (registry.endpoints().isEmpty()) QVERIFY(changes.wait(1000));
        QVERIFY(player.barrier());
        QCOMPARE(player.propertyCalls, 2);
        player.title = "Newer signal title";
        auto signal = QDBusMessage::createSignal("/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged");
        signal << QString("org.mpris.MediaPlayer2.Player")
               << QVariantMap{{"Metadata", QVariantMap{{"xesam:title", player.title}}}}
               << QStringList{};
        QVERIFY(player.bus.send(signal));
        const auto currentTitle = [&] { return registry.endpoints()[0]["presentation"].toObject()["title"].toString(); };
        while (currentTitle() != player.title) QVERIFY(changes.wait(1000));
        bool rolledBack = false;
        const auto observe = connect(&registry, &Island::MprisRegistry::changed, this, [&] {
            if (currentTitle() != player.title) rolledBack = true;
        });
        player.delayProperties = false;
        player.completeProperties();
        while (!ready(registry)) QVERIFY(changes.wait(1000));
        disconnect(observe);
        QVERIFY(!rolledBack);
        QCOMPARE(currentTitle(), player.title);
        QCOMPARE(player.propertyCalls, 3);
    }
};
QTEST_GUILESS_MAIN(RegistryTest)
#include "mpris-registry-test.moc"
