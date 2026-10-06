#include "ipc-protocol.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QtTest>
#include <fcntl.h>
#include <unistd.h>

class ProtocolTest : public QObject {
    Q_OBJECT
private slots:
    // With the queue filled by replaceable output up to its reserve, a
    // method result as large as a frame (a full calendar page) still fits,
    // instead of being refused and ending the helper with backpressure.
    void replaceableOutputLeavesRoomForAWholeReply() {
        int pipeFds[2];
        QVERIFY(::pipe2(pipeFds, O_CLOEXEC | O_NONBLOCK) == 0);
        const int savedStdout = ::dup(STDOUT_FILENO);
        QVERIFY(savedStdout >= 0);
        // Restored on every return, so a failure still reaches the test log.
        const auto restore = qScopeGuard([&] {
            ::dup2(savedStdout, STDOUT_FILENO);
            ::close(savedStdout);
            ::close(pipeFds[0]);
            ::close(pipeFds[1]);
        });
        QVERIFY(::dup2(pipeFds[1], STDOUT_FILENO) >= 0);
        {
            Island::StdioChannel channel;
            QByteArray entry(Island::EntryLimit - 1, 'x');
            entry += '\n';
            int sent = 0;
            while (channel.send(entry, Island::ReplyReserve)) ++sent;
            QVERIFY(sent > 0);
            QByteArray reply(Island::FrameLimit - 1, 'y');
            reply += '\n';
            QVERIFY(channel.send(reply));
        }
    }
    void transportValueBounds() {
        for (const auto &value : {"None", "Playlist", "Track"}) QVERIFY(Island::validLoopStatus(value));
        QVERIFY(!Island::validLoopStatus("Loop"));
        QVERIFY(!Island::validLoopStatus(1));
        QVERIFY(Island::validSeekOffset(-3600));
        QVERIFY(Island::validSeekOffset(3600));
        QVERIFY(Island::validSeekOffset(-15.25));
        QVERIFY(!Island::validSeekOffset(-3600.01));
        QVERIFY(!Island::validSeekOffset(3600.01));
        QVERIFY(!Island::validSeekOffset("15"));
        QVERIFY(!Island::validSeekOffset(QJsonValue()));
    }
    void fragmentedUtf8AndMultipleFrames() {
        Island::JsonLines parser;
        QSignalSpy messages(&parser, &Island::JsonLines::message);
        QSignalSpy errors(&parser, &Island::JsonLines::error);
        const QJsonObject expected{{"title", QString::fromUtf8("音楽 🎵 tiếng Việt")},
                                   {"escaped", "\"\\\n\r\t"}};
        // Exercise raw multibyte input even when the producer escapes Unicode.
        const auto frame = QJsonDocument(expected).toJson(QJsonDocument::Compact) + '\n';
        for (int i = 0; i < frame.size() - 1; ++i) {
            parser.feed(frame.mid(i, 1));
            QCOMPARE(messages.size(), 0);
        }
        parser.feed(frame.right(1) + frame + frame);
        QCOMPARE(messages.size(), 3);
        QCOMPARE(errors.size(), 0);
        for (const auto &message : messages)
            QCOMPARE(message[0].value<QJsonObject>(), expected);
    }
    void encodedUnicodeIsAsciiAndRoundTrips() {
        const QJsonObject expected{{"title", QString::fromUtf8("音楽 🎵 tiếng Việt")}};
        const auto frame = Island::encodeFrame(expected);
        for (unsigned char byte : frame) QVERIFY(byte < 128);
        QCOMPARE(QJsonDocument::fromJson(frame).object(), expected);
    }

    void invalidFrames_data() {
        QTest::addColumn<QByteArray>("frame");
        QTest::newRow("syntax") << QByteArray("{nope}\n");
        QTest::newRow("array") << QByteArray("[]\n");
        QTest::newRow("scalar") << QByteArray("null\n");
        QTest::newRow("blank") << QByteArray("\n");
        QTest::newRow("invalid-utf8") << QByteArray("{\"x\":\"") + QByteArray::fromHex("c328") + "\"}\n";
    }
    void invalidFrames() {
        QFETCH(QByteArray, frame);
        Island::JsonLines parser;
        QSignalSpy messages(&parser, &Island::JsonLines::message);
        QSignalSpy errors(&parser, &Island::JsonLines::error);
        parser.feed(frame);
        QVERIFY(parser.failed());
        QCOMPARE(errors.size(), 1);
        QCOMPARE(errors[0][0].toString(), "invalid-json");
        parser.feed("{\"valid\":true}\n");
        QCOMPARE(messages.size(), 0);
        QCOMPARE(errors.size(), 1);
    }

    void exactFrameBoundary() {
        Island::JsonLines parser;
        QSignalSpy messages(&parser, &Island::JsonLines::message);
        const QByteArray frame = "{\"x\":\"" + QByteArray(Island::FrameLimit - 9, 'a') + "\"}\n";
        QCOMPARE(frame.size(), Island::FrameLimit);
        parser.feed(frame);
        QVERIFY(!parser.failed());
        QCOMPARE(messages.size(), 1);
    }
    void oversizedPartialFrame() {
        Island::JsonLines parser;
        QSignalSpy errors(&parser, &Island::JsonLines::error);
        parser.feed(QByteArray(Island::FrameLimit - 1, 'a'));
        QVERIFY(!parser.failed());
        parser.feed("a");
        QVERIFY(parser.failed());
        QCOMPARE(errors[0][0].toString(), "frame-too-large");
    }

    void allLongEscapedEndpointsRemainRoutable() {
        QVector<QJsonObject> endpoints;
        QJsonArray artists;
        for (int i = 0; i < 16; ++i) artists.append(QString(4096, QChar('\n')));
        for (int i = 0; i < Island::EndpointLimit; ++i) {
            QJsonObject token{{"busEpoch", "bus"}, {"wellKnownName", QString("org.mpris.MediaPlayer2.test%1").arg(i)},
                              {"uniqueOwner", QString(":1.%1").arg(i)}, {"endpointGeneration", QString::number(i)}};
            QJsonObject track{{"endpointToken", token}, {"trackGeneration", "9007199254740993"},
                              {"rawTrackId", "/" + QString(4095, 't')}};
            endpoints.append({{"token", token}, {"trackToken", track},
                {"capabilities", QJsonObject{{"CanControl", true}, {"CanSeek", true}}},
                {"presentation", QJsonObject{{"title", QString(4096, QChar('"'))},
                     {"album", QString(4096, QChar('\\'))}, {"artists", artists},
                     {"hostApp", QString(4096, QChar('\t'))}, {"platform", "browser"}}}});
        }
        const auto frames = Island::snapshotFrames(endpoints, "connection", "9007199254740993", "bus");
        QCOMPARE(frames.size(), Island::EndpointLimit + 2);
        qsizetype bytes = 0;
        for (const auto &frame : frames) bytes += frame.size();
        QVERIFY(bytes <= Island::SnapshotLimit);
        QCOMPARE(QJsonDocument::fromJson(frames.front()).object()["count"].toInt(), Island::EndpointLimit);
        QCOMPARE(QJsonDocument::fromJson(frames.back()).object()["count"].toInt(), Island::EndpointLimit);
        Island::JsonLines parser;
        QSignalSpy messages(&parser, &Island::JsonLines::message);
        for (int i = 0; i < frames.size(); ++i) {
            QVERIFY(frames[i].size() <= Island::EntryLimit);
            parser.feed(frames[i]);
            if (i == 0 || i == frames.size() - 1) continue;
            const auto object = QJsonDocument::fromJson(frames[i]).object();
            QCOMPARE(object["index"].toInt(), i - 1);
            QCOMPARE(object["sequence"].toString(), "9007199254740993");
            const auto endpoint = object["endpoint"].toObject();
            QCOMPARE(endpoint["token"], endpoints[i - 1]["token"]);
            QCOMPARE(endpoint["trackToken"], endpoints[i - 1]["trackToken"]);
            QCOMPARE(endpoint["capabilities"], endpoints[i - 1]["capabilities"]);
            QVERIFY(endpoint["presentationTruncated"].toBool());
        }
        QCOMPARE(messages.size(), frames.size());
        QVERIFY(!parser.failed());
    }
    void impossibleIdentityDoesNotRemoveHealthyPeers() {
        const QJsonObject healthy{{"token", QJsonObject{{"uniqueOwner", ":1.42"}}}};
        const QJsonObject oversized{{"token", QJsonObject{{"uniqueOwner", QString(Island::EntryLimit, 'x')}}}};
        const auto frames = Island::snapshotFrames({oversized, healthy}, "connection", "1", "bus");
        QCOMPARE(frames.size(), 3);
        QCOMPARE(QJsonDocument::fromJson(frames[1]).object()["endpoint"].toObject(), healthy);
    }
};
QTEST_GUILESS_MAIN(ProtocolTest)
#include "ipc-protocol-test.moc"
