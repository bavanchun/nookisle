#include "browser-registry.h"
#include <QFile>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>
#include <memory>
using Island::BrowserRegistry;
class BrowserRegistryTest : public QObject {
    Q_OBJECT
    std::unique_ptr<QTemporaryDir> runtime;
    std::unique_ptr<BrowserRegistry> registry;
    std::unique_ptr<QLocalSocket> peer;
    QByteArray input;
    QList<QJsonObject> messages;
    QString session;
    void send(QJsonObject frame) {
        frame["protocolVersion"] = 1;
        if (!frame.contains("bridgeSession")) frame["bridgeSession"] = session;
        const auto bytes = QJsonDocument(frame).toJson(QJsonDocument::Compact) + '\n';
        peer->write(bytes); peer->flush();
    }
    QJsonObject token(int tab = 1, QString generation = "media-a") const {
        return {{"busEpoch", "epoch"}, {"transport", "extension"}, {"bridgeSession", session}, {"tabId", tab},
            {"documentId", "doc"}, {"frameId", 0}, {"mediaGeneration", generation}};
    }
    void state(const QJsonObject &endpoint, double position = 0, QString status = "Playing", QString track = "track-a", bool favorite = false,
               bool positionEvent = false) {
        QJsonObject caps{{"CanControl", true}, {"CanPlay", true}, {"CanPause", true}, {"CanSeek", true}, {"CanSetVolume", true},
                         {"CanFavorite", favorite}, {"CanShuffle", false}, {"CanLoop", false}};
        QJsonObject body{{"platform", "YouTube"},
            {"mediaGeneration", endpoint["mediaGeneration"]}, {"trackGeneration", track}, {"title", "Fixture"}, {"status", status}, {"capabilities", caps},
            {"positionSeconds", position}, {"lengthSeconds", 120}, {"volume", 0.5}, {"liked", false}, {"artworkUrl", "https://example.test/art.png"}};
        if (positionEvent) body["positionEvent"] = true;
        send({{"type", "browserState"}, {"endpointToken", endpoint}, {"state", body}});
    }
    QJsonObject command(QString id, QJsonObject endpoint) {
        return {{"requestId", id}, {"endpointToken", endpoint}, {"admissionEpoch", "gate"}, {"action", "Play"}};
    }
private slots:
    void init() {
        input.clear(); messages.clear(); session.clear(); runtime = std::make_unique<QTemporaryDir>();
        QVERIFY(runtime->isValid()); registry = std::make_unique<BrowserRegistry>("epoch");
        QVERIFY(registry->start(runtime->path(), "1234567890abcdef"));
        QFile auth(runtime->path() + "/nookisle-1234567890abcdef/browser.json"); QVERIFY(auth.open(QIODevice::ReadOnly));
        auto config = QJsonDocument::fromJson(auth.readAll()).object();
        peer = std::make_unique<QLocalSocket>();
        connect(peer.get(), &QLocalSocket::readyRead, this, [this] {
            input += peer->readAll();
            while (input.contains('\n')) {
                const auto end = input.indexOf('\n'); messages.append(QJsonDocument::fromJson(input.first(end)).object()); input.remove(0, end + 1);
            }
        });
        peer->connectToServer(config["socket"].toString());
        QTRY_COMPARE(peer->state(), QLocalSocket::ConnectedState);
        send({{"type", "bridgeAuth"}, {"secret", config["secret"]}});
        QTRY_COMPARE(messages.size(), 1); QCOMPARE(messages.first()["type"], "bridgeHello");
        session = messages.first()["bridgeSession"].toString(); QVERIFY(!session.isEmpty());
        registry->setGate("gate", true);
    }
    void cleanup() { peer.reset(); registry.reset(); runtime.reset(); }
    void exactTokenAndNavigation() {
        QSignalSpy results(registry.get(), &BrowserRegistry::result);
        const auto old = token(); state(old); QTRY_COMPARE(registry->endpoints().size(), 1);
        auto wrong = old; wrong["documentId"] = "other-document";
        registry->command(command("wrong", wrong)); QCOMPARE(results.takeFirst().at(1).toString(), "target-gone");
        auto fresh = token(1, "media-b"); state(fresh);
        QTRY_COMPARE(registry->endpoints().first()["token"].toObject(), fresh);
        registry->command(command("old", old)); QCOMPARE(results.takeFirst().at(1).toString(), "target-gone");
        registry->command(command("new", fresh));
        QTRY_VERIFY(messages.last()["type"] == "browserCommand");
        QCOMPARE(messages.last()["endpointToken"].toObject(), fresh);
        send({{"type", "browserResult"}, {"requestId", "new"}, {"status", "success"}});
        QTRY_COMPARE(results.size(), 1); QCOMPARE(results.first().at(1).toString(), "success");
    }
    void favoriteAndRelativeSeekAreCapabilityGated() {
        QSignalSpy results(registry.get(), &BrowserRegistry::result);
        state(token()); QTRY_COMPARE(registry->endpoints().size(), 1);
        auto caps = registry->endpoints().first()["capabilities"].toObject();
        QVERIFY(!caps["CanFavorite"].toBool());
        QVERIFY(!caps["CanShuffle"].toBool());
        QVERIFY(!caps["CanLoop"].toBool());
        auto favorite = command("favorite", token()); favorite["action"] = "Favorite";
        registry->command(favorite); QCOMPARE(results.takeFirst().at(1).toString(), "unsupported");
        state(token(), 0, "Playing", "track-a", true);
        QTRY_VERIFY(registry->endpoints().first()["capabilities"].toObject()["CanFavorite"].toBool());
        QCOMPARE(registry->endpoints().first()["presentation"].toObject()["browserClass"].toString(), "google-chrome");
        QCOMPARE(registry->endpoints().first()["liked"].toBool(), false);
        favorite["trackToken"] = registry->endpoints().first()["trackToken"];
        registry->command(favorite); QTRY_COMPARE(messages.last()["action"].toString(), "Favorite");
        send({{"type", "browserResult"}, {"requestId", "favorite"}, {"status", "success"}});
        QTRY_COMPARE(results.size(), 1); QCOMPARE(results.takeFirst().at(1).toString(), "success");
        QCOMPARE(registry->endpoints().first()["liked"].toBool(), false);
        auto seek = command("seek", token()); seek["action"] = "Seek"; seek["value"] = -15;
        registry->command(seek); QTRY_COMPARE(messages.last()["action"].toString(), "Seek");
        send({{"type", "browserResult"}, {"requestId", "seek"}, {"status", "success"}});
        QTRY_COMPARE(results.size(), 1); QCOMPARE(results.takeFirst().at(1).toString(), "success");
        seek["value"] = -3601;
        registry->command(seek); QCOMPARE(results.takeFirst().at(1).toString(), "invalid-value");
    }
    void progressDoesNotPublishSnapshotsAndClosedGateStopsSubscription() {
        QSignalSpy changes(registry.get(), &BrowserRegistry::changed), progress(registry.get(), &BrowserRegistry::progress);
        state(token()); QTRY_COMPARE(changes.size(), 1);
        registry->subscribe(token(), true, 250); state(token(), 10);
        QTRY_COMPARE(progress.size(), 1); QCOMPARE(changes.size(), 1);
        QCOMPARE(registry->endpoints().first()["positionSeconds"].toDouble(), 10.0);
        state(token(), 11, "Paused"); QTRY_COMPARE(changes.size(), 2); QCOMPARE(progress.size(), 1);
        registry->setGate("locked", false);
        QTRY_VERIFY(messages.last()["type"] == "browserSubscribe" && messages.last()["visible"] == false);
        QCOMPARE(messages.last()["endpointToken"].toObject(), token());
        state(token(), 12); QTRY_COMPARE(changes.size(), 3); QCOMPARE(progress.size(), 1);
    }
    // A seek while paused (no progress subscription) republishes at once
    // with the new position; an unchanged paused frame does not.
    void pausedSeekPublishesItsPosition() {
        QSignalSpy changes(registry.get(), &BrowserRegistry::changed);
        state(token(), 10, "Paused"); QTRY_COMPARE(changes.size(), 1);
        state(token(), 10, "Paused"); QTest::qWait(100); QCOMPARE(changes.size(), 1);
        state(token(), 100, "Paused", "track-a", false, true);
        QTRY_COMPARE(changes.size(), 2);
        QCOMPARE(registry->endpoints().first()["positionSeconds"].toDouble(), 100.0);
    }
    void gateClearsPendingCreditsAndDropsStaleCompletion() {
        QSignalSpy results(registry.get(), &BrowserRegistry::result);
        state(token()); QTRY_COMPARE(registry->endpoints().size(), 1);
        registry->command(command("old", token()));
        QTRY_VERIFY(messages.last()["requestId"] == "old");
        registry->setGate("closed", false); registry->setGate("gate", true);
        registry->command(command("new", token()));
        QTRY_VERIFY(messages.last()["requestId"] == "new");
        send({{"type", "browserResult"}, {"requestId", "old"}, {"status", "success"}});
        send({{"type", "browserResult"}, {"requestId", "new"}, {"status", "success"}});
        QTRY_COMPARE(results.size(), 1); QCOMPARE(results.first().at(0).toString(), "new");
    }
    void disconnectDropsEndpointsAndCommands() {
        QSignalSpy results(registry.get(), &BrowserRegistry::result);
        state(token()); QTRY_COMPARE(registry->endpoints().size(), 1);
        registry->command(command("pending", token())); peer->abort();
        QTRY_VERIFY(registry->endpoints().isEmpty());
        QTRY_COMPARE(results.size(), 1); QCOMPARE(results.first().at(1).toString(), "target-gone");
    }
    void boundedEndpointsAndInvalidFrameDisconnect() {
        for (int i = 0; i < 65; ++i) state(token(i));
        QTRY_COMPARE(registry->endpoints().size(), 64);
        send({{"type", "browserState"}, {"endpointToken", token()}, {"state", QJsonObject{{"title", QString(9000, 'x')}}}});
        QTRY_VERIFY(registry->endpoints().isEmpty()); QTRY_COMPARE(peer->state(), QLocalSocket::UnconnectedState);
    }
    void staleArtworkNeverAttachesToNewTrack() {
        state(token(), 0, "Playing", "track-a", true); QTRY_COMPARE(registry->endpoints().size(), 1);
        const auto before = registry->endpoints().first();
        QCOMPARE(registry->artworkUrl(token()), QUrl("https://example.test/art.png"));
        state(token(), 0, "Playing", "track-b", true); QTRY_VERIFY(registry->endpoints().first()["trackToken"] != before["trackToken"]);
        QCOMPARE(registry->endpoints().first()["token"], before["token"]);
        QSignalSpy results(registry.get(), &BrowserRegistry::result);
        auto seek = command("stale-seek", token()); seek["action"] = "SetPosition"; seek["value"] = 10; seek["trackToken"] = before["trackToken"];
        registry->command(seek); QCOMPARE(results.takeFirst().at(1).toString(), "stale-track");
        const auto forwarded = messages.size();
        auto favorite = command("stale-favorite", token()); favorite["action"] = "Favorite";
        favorite["trackToken"] = before["trackToken"];
        registry->command(favorite);
        QCOMPARE(results.size(), 1);
        QCOMPARE(results.takeFirst().at(1).toString(), "stale-track");
        QCOMPARE(messages.size(), forwarded);
        registry->setArtwork(token(), before["trackToken"].toObject(), "/fixture/stale.png");
        QVERIFY(registry->endpoints().first()["artworkPath"].toString().isEmpty());
        const auto current = registry->endpoints().first();
        registry->setArtwork(current["token"].toObject(), current["trackToken"].toObject(), "/fixture/current.png");
        QCOMPARE(registry->endpoints().first()["artworkPath"].toString(), "/fixture/current.png");
        registry->clearArtwork(); QVERIFY(registry->endpoints().first()["artworkPath"].toString().isEmpty());
    }
};
QTEST_GUILESS_MAIN(BrowserRegistryTest)
#include "browser-registry-test.moc"
