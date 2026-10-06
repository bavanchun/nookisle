#include "calendar-parser.h"
#include "calendar-sources.h"
#include "calendar-service.h"
#include "ipc-protocol.h"
#include <QElapsedTimer>
#include <QFile>
#include <QJsonDocument>
#include <QPointer>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QTcpServer>
#include <QTcpSocket>
#include <QSignalSpy>
#include <QtTest>
#include <cstdio>
#include <cstring>

namespace {
QJsonArray fixtureWindow(const QString &name, const char *from = "2026-09-20T00:00:00Z", const char *until = "2026-10-10T00:00:00Z") {
    QFile file(QStringLiteral(FIXTURE_DIR) + "/" + name);
    if (!file.open(QIODevice::ReadOnly)) return {};
    auto parsed = Island::Calendar::parse(file.readAll());
    return Island::Calendar::window(parsed.entries, QDateTime::fromString(from, Qt::ISODate),
                                    QDateTime::fromString(until, Qt::ISODate), "fixture");
}
QList<QJsonObject> itemsFor(const QJsonArray &items, const QString &uid) {
    QList<QJsonObject> result;
    for (const auto &value : items) if (value.toObject().value("uid") == uid) result.append(value.toObject());
    return result;
}
// Sources load off the event loop; wait until every load has applied.
bool settled(Island::Calendar::Sources &sources) {
    return QTest::qWaitFor([&] { return !sources.loading(); }, 10000);
}
QStringList startsFor(const QJsonArray &items, const QString &uid) {
    QStringList result;
    for (const auto &item : itemsFor(items, uid))
        result.append(QDateTime::fromString(item.value("start").toString(), Qt::ISODate).toUTC().toString(Qt::ISODate));
    return result;
}
// Puts a fake secret-tool first on PATH. It records store input and clear
// calls, answers lookup with a password, and sleeps first when asked to.
struct FakeSecretTool {
    QTemporaryDir dir;
    QByteArray oldPath = qgetenv("PATH");
    explicit FakeSecretTool(int sleepSeconds = 0) {
        QFile fake(dir.filePath("secret-tool"));
        if (!fake.open(QIODevice::WriteOnly)) return;
        fake.write(("#!/bin/sh\nprintf '%s\\n' \"$*\" >>\"" + dir.filePath("argv-capture") + "\"\nsleep " + QString::number(sleepSeconds) + "\n"
            "if [ \"$1\" = lookup ]; then printf fixture-password; "
            "elif [ \"$1\" = store ]; then cat >\"" + dir.filePath("stdin-capture") + "\"; "
            "elif [ \"$1\" = clear ]; then printf cleared >\"" + dir.filePath("clear-capture") + "\"; fi\n").toUtf8());
        fake.close();
        fake.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        qputenv("PATH", (dir.path() + ":" + QString::fromUtf8(oldPath)).toUtf8());
    }
    ~FakeSecretTool() { qputenv("PATH", oldPath); }
    bool cleared() const { return QFile::exists(dir.filePath("clear-capture")); }
    // Every command line secret-tool was started with, one per line.
    QByteArray argv() const {
        QFile file(dir.filePath("argv-capture"));
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }
    QByteArray stored() const {
        QFile file(dir.filePath("stdin-capture"));
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }
};
}

class CalendarTest : public QObject {
    Q_OBJECT
private slots:
    void parserAndWindow() {
        QFile file(QStringLiteral(FIXTURE_DIR) + "/calendar.ics");
        QVERIFY(file.open(QIODevice::ReadOnly));
        auto parsed = Island::Calendar::parse(file.readAll());
        QVERIFY(parsed.error.isEmpty());
        QCOMPARE(parsed.entries.size(), 4);
        QCOMPARE(parsed.entries[0].title, "Team, planning");
        QCOMPARE(parsed.entries[2].title, "A very longfolded title");
        QVERIFY(parsed.entries[2].allDay);
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-10T00:00:00Z", Qt::ISODate);
        auto items = Island::Calendar::window(parsed.entries, from, until, "fixture");
        int weekly = 0, nth = 0, todos = 0;
        for (const auto &value : items) {
            auto item = value.toObject();
            if (item.value("uid") == "weekly") ++weekly;
            if (item.value("uid") == "nth") ++nth;
            if (item.value("todo").toBool()) ++todos;
        }
        QCOMPARE(weekly, 3);
        QCOMPARE(nth, 1);
        QCOMPARE(todos, 1);
    }
    void boundedMalformedInput() {
        auto big = Island::Calendar::parse(QByteArray(Island::Calendar::SourceLimit + 1, 'x'));
        QCOMPARE(big.error, "too-large");
        QCOMPARE(Island::Calendar::parse("bad").error, "invalid-calendar");
        QByteArray many = "BEGIN:VCALENDAR\n";
        for (int i = 0; i <= Island::Calendar::ComponentLimit; ++i) many += "BEGIN:VEVENT\nEND:VEVENT\n";
        QCOMPARE(Island::Calendar::parse(many).error, "too-many-components");
    }
    // A hostile source repeats one unknown, slash-heavy TZID on thousands of
    // exclusion dates: it resolves once, stays floating, and an overlong TZID
    // is never searched at all.
    void hostileTimeZonesParseQuickly() {
        QByteArray tzid;
        for (int i = 0; i < 4000; ++i) tzid += "X/";
        QByteArray dates;
        for (int i = 0; i < 2000; ++i) dates += (i ? "," : "") + QByteArray("20260101T000000");
        QByteArray ics = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:hostile\nDTSTART;TZID=" + tzid + ":20260928T100000\n"
            "EXDATE;TZID=" + tzid + ":" + dates + "\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:overlong\nDTSTART;TZID=" + QByteArray(300, 'Y') + "/Europe/Berlin:20260928T100000\nEND:VEVENT\n"
            "END:VCALENDAR\n";
        QElapsedTimer timer;
        timer.start();
        auto parsed = Island::Calendar::parse(ics);
        QVERIFY2(timer.elapsed() < 500, QByteArray::number(timer.elapsed()));
        QCOMPARE(parsed.entries.size(), 2);
        for (const auto &entry : parsed.entries) {
            QCOMPARE(entry.start, QDateTime(QDate(2026, 9, 28), QTime(10, 0), QTimeZone::systemTimeZone()));
            QVERIFY(entry.unsupported.contains("TZID"));
        }
    }
    // Exclusions per entry are bounded; the cut is reported, not silent.
    void exclusionListsAreBounded() {
        QByteArray dates;
        for (int i = 0; i < Island::Calendar::ExclusionLimit + 10; ++i)
            dates += (i ? "," : "") + QDateTime(QDate(2020, 1, 1), QTime(0, 0), QTimeZone::UTC).addSecs(60LL * i)
                .toString("yyyyMMdd'T'HHmmss'Z'").toLatin1();
        auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:many\nDTSTART:20260928T100000Z\nEXDATE:"
            + dates + "\nEND:VEVENT\nEND:VCALENDAR\n");
        QCOMPARE(parsed.entries.size(), 1);
        QCOMPARE(parsed.entries[0].exdateInstants.size(), Island::Calendar::ExclusionLimit);
        QVERIFY(parsed.entries[0].unsupported.contains("EXDATE"));
    }
    void recurrenceBoundsAndUnsupportedRules() {
        QByteArray data = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:until\nDTSTART:20260926T090000Z\nDURATION:PT90M\nRRULE:FREQ=DAILY;UNTIL=20260928T090000Z\nSUMMARY:Daily\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:capped\nDTSTART:20260101T090000Z\nRRULE:FREQ=DAILY\nSUMMARY:Many\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:unsupported\nDTSTART:20260926T090000Z\nRRULE:FREQ=MONTHLY;BYSETPOS=1\nSUMMARY:Unusual\nX-EXTRA:ignored\nEND:VEVENT\nEND:VCALENDAR\n";
        auto parsed = Island::Calendar::parse(data);
        QVERIFY(parsed.error.isEmpty());
        auto from = QDateTime::fromString("2026-01-01T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2028-01-01T00:00:00Z", Qt::ISODate);
        auto items = Island::Calendar::window(parsed.entries, from, until, "fixture");
        int untilCount = 0, capCount = 0, unsupportedCount = 0;
        for (const auto &value : items) {
            auto item = value.toObject();
            if (item.value("uid") == "until") {
                ++untilCount;
                QCOMPARE(QDateTime::fromString(item.value("start").toString(), Qt::ISODate).secsTo(
                    QDateTime::fromString(item.value("end").toString(), Qt::ISODate)), 5400);
            } else if (item.value("uid") == "capped") ++capCount;
            else if (item.value("uid") == "unsupported") {
                ++unsupportedCount;
                QVERIFY(item.value("unsupported").toArray().contains("RRULE"));
            }
        }
        QCOMPARE(untilCount, 3);
        QCOMPARE(capCount, Island::Calendar::InstanceLimit);
        QCOMPARE(unsupportedCount, 1);
    }
    // Starts (UTC) of one series' instances in a window.
    static QStringList starts(const QByteArray &rule, const char *dtstart, const char *from, const char *until) {
        auto parsed = Island::Calendar::parse(QByteArray("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:r\nDTSTART:") + dtstart
            + "\nRRULE:" + rule + "\nSUMMARY:R\nEND:VEVENT\nEND:VCALENDAR\n");
        auto items = Island::Calendar::window(parsed.entries, QDateTime::fromString(from, Qt::ISODate),
            QDateTime::fromString(until, Qt::ISODate), "fixture");
        QStringList out;
        for (const auto &value : items) {
            auto item = value.toObject();
            out.append(QDateTime::fromString(item.value("start").toString(), Qt::ISODate).toUTC().toString("yyyy-MM-dd")
                + (item.contains("unsupported") ? "!" : ""));
        }
        return out;
    }
    // WKST and BYMONTH are common in exports; a series using them must
    // expand, never vanish.
    void weekStartAndMonthRules() {
        // A weekly meeting exported with WKST: identical to the rule without.
        auto plain = starts("FREQ=WEEKLY;BYDAY=MO,WE", "20250106T090000Z", "2026-09-21T00:00:00Z", "2026-10-12T00:00:00Z");
        QCOMPARE(plain.size(), 6);
        QCOMPARE(starts("FREQ=WEEKLY;WKST=SU;BYDAY=MO,WE", "20250106T090000Z", "2026-09-21T00:00:00Z", "2026-10-12T00:00:00Z"), plain);
        // RFC 5545's example: with INTERVAL=2 the week start decides the weeks.
        QCOMPARE(starts("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=MO", "19970805T090000Z", "1997-08-01T00:00:00Z", "1997-10-01T00:00:00Z"),
            QStringList({"1997-08-05", "1997-08-10", "1997-08-19", "1997-08-24"}));
        QCOMPARE(starts("FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=TU,SU;WKST=SU", "19970805T090000Z", "1997-08-01T00:00:00Z", "1997-10-01T00:00:00Z"),
            QStringList({"1997-08-05", "1997-08-17", "1997-08-19", "1997-08-31"}));
        // An Outlook yearly event.
        QCOMPARE(starts("FREQ=YEARLY;BYMONTH=9;BYMONTHDAY=28", "20200928T090000Z", "2026-09-20T00:00:00Z", "2026-10-10T00:00:00Z"),
            QStringList({"2026-09-28"}));
        // RFC 5545: every other year in January, February and March.
        QCOMPARE(starts("FREQ=YEARLY;INTERVAL=2;COUNT=10;BYMONTH=1,2,3", "19970310T090000Z", "1997-01-01T00:00:00Z", "2004-01-01T00:00:00Z"),
            QStringList({"1997-03-10", "1999-01-10", "1999-02-10", "1999-03-10", "2001-01-10", "2001-02-10", "2001-03-10",
                "2003-01-10", "2003-02-10", "2003-03-10"}));
        // The same series seen from a window years later skips ahead correctly.
        QCOMPARE(starts("FREQ=YEARLY;INTERVAL=2;COUNT=10;BYMONTH=1,2,3", "19970310T090000Z", "2003-02-01T00:00:00Z", "2030-01-01T00:00:00Z"),
            QStringList({"2003-02-10", "2003-03-10"}));
        // An ordinal weekday within BYMONTH: the second Sunday of March.
        QCOMPARE(starts("FREQ=YEARLY;BYMONTH=3;BYDAY=2SU", "20260308T090000Z", "2027-01-01T00:00:00Z", "2029-01-01T00:00:00Z"),
            QStringList({"2027-03-14", "2028-03-12"}));
        // BYMONTH limits the other frequencies.
        QCOMPARE(starts("FREQ=MONTHLY;BYMONTH=9,11;BYMONTHDAY=1", "20260101T090000Z", "2026-08-01T00:00:00Z", "2026-12-31T00:00:00Z"),
            QStringList({"2026-09-01", "2026-11-01"}));
        QCOMPARE(starts("FREQ=DAILY;BYMONTH=1", "20260130T090000Z", "2026-01-29T00:00:00Z", "2027-01-03T00:00:00Z"),
            QStringList({"2026-01-30", "2026-01-31", "2027-01-01", "2027-01-02"}));
        QCOMPARE(starts("FREQ=WEEKLY;BYMONTH=10;BYDAY=TH", "20260903T090000Z", "2026-09-20T00:00:00Z", "2026-10-20T00:00:00Z"),
            QStringList({"2026-10-01", "2026-10-08", "2026-10-15"}));
        // A malformed month or week start is not guessed at.
        QCOMPARE(starts("FREQ=YEARLY;BYMONTH=13", "20260926T090000Z", "2026-09-20T00:00:00Z", "2026-10-10T00:00:00Z"),
            QStringList({"2026-09-26!"}));
        QCOMPARE(starts("FREQ=WEEKLY;WKST=XX", "20260926T090000Z", "2026-09-20T00:00:00Z", "2026-10-10T00:00:00Z"),
            QStringList({"2026-09-26!"}));
    }
    // A rule outside the subset still shows its first instance, with the
    // RRULE marker, even when that instance falls before the window.
    void unsupportedRuleNeverVanishes() {
        QCOMPARE(starts("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", "20250131T090000Z", "2026-09-20T00:00:00Z", "2026-10-10T00:00:00Z"),
            QStringList({"2025-01-31!"}));
        // A first instance after the window waits for its window.
        QCOMPARE(starts("FREQ=MONTHLY;BYSETPOS=1", "20261126T090000Z", "2026-09-20T00:00:00Z", "2026-10-10T00:00:00Z"),
            QStringList());
    }
    // Tasks apps write a reminder due on a date as DUE;VALUE=DATE with no
    // DTSTART: it is all-day, not due at midnight. A timed DUE stays timed,
    // and a DTSTART still decides for a reminder that has one.
    void dateOnlyDueIsAllDay() {
        auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\n"
            "BEGIN:VTODO\nUID:rent\nDUE;VALUE=DATE:20260927\nSUMMARY:Pay rent\nEND:VTODO\n"
            "BEGIN:VTODO\nUID:bare\nDUE:20260928\nSUMMARY:Bare date\nEND:VTODO\n"
            "BEGIN:VTODO\nUID:timed\nDUE:20260927T180000Z\nSUMMARY:Timed\nEND:VTODO\n"
            "BEGIN:VTODO\nUID:started\nDTSTART:20260927T090000Z\nDUE;VALUE=DATE:20260929\nSUMMARY:Started\nEND:VTODO\n"
            "END:VCALENDAR\n");
        QVERIFY(parsed.error.isEmpty());
        auto items = Island::Calendar::window(parsed.entries, QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
            QDateTime::fromString("2026-10-10T00:00:00Z", Qt::ISODate), "fixture");
        auto find = [&](const char *uid) {
            for (const auto &value : items) if (value.toObject().value("uid") == uid) return value.toObject();
            return QJsonObject();
        };
        QCOMPARE(find("rent").value("allDay").toBool(), true);
        QVERIFY(find("rent").value("due").toString().startsWith("2026-09-27T00:00:00"));
        QCOMPARE(find("bare").value("allDay").toBool(), true);
        QCOMPARE(find("timed").value("allDay").toBool(), false);
        QCOMPARE(find("started").value("allDay").toBool(), false);
        for (const char *uid : {"rent", "bare", "timed", "started"}) QVERIFY2(find(uid).value("todo").toBool(), uid);
    }
    void recurrenceOverrideAndMonthday() {
        auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:monthday\nDTSTART:20260905T090000Z\nRRULE:FREQ=MONTHLY;COUNT=3;BYMONTHDAY=5\nSUMMARY:Base\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:monthday\nRECURRENCE-ID:20261005T090000Z\nDTSTART:20261006T090000Z\nSUMMARY:Moved\nEND:VEVENT\nEND:VCALENDAR\n");
        QVERIFY(parsed.error.isEmpty());
        auto from = QDateTime::fromString("2026-09-01T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-12-01T00:00:00Z", Qt::ISODate);
        auto items = Island::Calendar::window(parsed.entries, from, until, "fixture");
        QCOMPARE(items.size(), 3);
        QCOMPARE(items[1].toObject().value("title"), QJsonValue("Moved"));
        QVERIFY(items[1].toObject().value("instanceStart").toString().startsWith("2026-10-05"));
        QVERIFY(items[1].toObject().value("start").toString().startsWith("2026-10-06"));
    }
    void spanningEventAndMalformedDuration() {
        auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:span\nDTSTART:20260919T090000Z\nDURATION:P3D\nSUMMARY:Trip\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:huge\nDTSTART:20260921T090000Z\nDURATION:P999999999999999999W\nSUMMARY:Bounded\nEND:VEVENT\nEND:VCALENDAR\n");
        QVERIFY(parsed.error.isEmpty());
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-09-23T00:00:00Z", Qt::ISODate);
        auto items = Island::Calendar::window(parsed.entries, from, until, "fixture");
        QCOMPARE(items.size(), 2);
        QCOMPARE(items[0].toObject().value("uid"), QJsonValue("span"));
        QVERIFY(items[0].toObject().value("start").toString().startsWith("2026-09-19"));
    }
    void invalidMonthDatesAreSkipped() {
        auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:month-end\nDTSTART:20260131T090000Z\nRRULE:FREQ=MONTHLY;COUNT=3\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:leap\nDTSTART:20240229T090000Z\nRRULE:FREQ=YEARLY;COUNT=2\nEND:VEVENT\nEND:VCALENDAR\n");
        QVERIFY(parsed.error.isEmpty());
        auto from = QDateTime::fromString("2024-01-01T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2029-01-01T00:00:00Z", Qt::ISODate);
        auto items = Island::Calendar::window(parsed.entries, from, until, "fixture");
        QStringList monthDates, leapDates;
        for (const auto &value : items) {
            auto item = value.toObject();
            if (item.value("uid") == "month-end") monthDates.append(item.value("start").toString().left(10));
            if (item.value("uid") == "leap") leapDates.append(item.value("start").toString().left(10));
        }
        QCOMPARE(monthDates, QStringList({"2026-01-31", "2026-03-31", "2026-05-31"}));
        QCOMPARE(leapDates, QStringList({"2024-02-29", "2028-02-29"}));
    }
    void vdirCompletion() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath("task.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:task\nDUE:20260927T100000Z\nSTATUS:NEEDS-ACTION\nEND:VTODO\nEND:VCALENDAR\n");
        file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "vdir"}, {"path", dir.path()}}}, true, 15);
        QVERIFY(settled(sources));
        auto page = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                 QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate), 0);
        auto items = page.value("items").toArray();
        QCOMPARE(items.size(), 1);
        QString status;
        sources.setCompleted(items[0].toObject().value("sourceId").toString(), "task", true,
                             [&](QString result) { status = result; });
        QCOMPARE(status, "ok");
        QVERIFY(file.open(QIODevice::ReadOnly));
        auto content = file.readAll();
        QVERIFY(content.contains("STATUS:COMPLETED"));
        QVERIFY(content.contains("COMPLETED:"));
    }
    // A remote request connects to the checked address but keeps the host's
    // identity, and never negotiates HTTP/2: Qt's HTTP/2 would send the
    // pinned address as `:authority` and drop the Host header, so a server
    // that picks its site by name would answer the wrong site.
    void pinnedRequestKeepsHostIdentity() {
        auto request = Island::Calendar::pinnedRequest(QUrl("https://calendar.example.com:8443/cal/basic.ics?x=1"),
            QHostAddress("93.184.216.34"), 5000);
        QCOMPARE(request.url().host(), QString("93.184.216.34"));
        QCOMPARE(request.url().path(), QString("/cal/basic.ics"));
        QCOMPARE(request.rawHeader("Host"), QByteArray("calendar.example.com:8443"));
        QCOMPARE(request.peerVerifyName(), QString("calendar.example.com"));
        // Read with Qt's own default (allowed), so only an explicit refusal passes.
        QCOMPARE(request.attribute(QNetworkRequest::Http2AllowedAttribute, true).toBool(), false);
        QCOMPARE(request.attribute(QNetworkRequest::RedirectPolicyAttribute).toInt(), int(QNetworkRequest::ManualRedirectPolicy));
        QCOMPARE(request.transferTimeout(), 5000);
        QCOMPARE(Island::Calendar::pinnedRequest(QUrl("https://calendar.google.com/x.ics"), QHostAddress("142.250.1.1"), 100)
            .rawHeader("Host"), QByteArray("calendar.google.com"));
    }

    void remoteRulesAndBounds() {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        QByteArray response;
        QByteArray received;
        bool hold = false;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &response, &hold, &received] {
                QByteArray request = socket->readAll();
                received += request;
                // A TLS handshake record: this plain fixture cannot answer it.
                if (request.startsWith('\x16')) { socket->disconnectFromHost(); return; }
                if (!request.contains("\r\n\r\n") || hold) return;
                socket->write(response); socket->flush(); socket->disconnectFromHost();
            });
        });
        QString url = QString("http://localhost:%1/feed.ics").arg(server.serverPort());
        Island::Calendar::Sources sources;
        auto definition = QJsonObject{{"kind", "ics-url"}, {"url", url}, {"allowLocalNetwork", true}};
        response = "HTTP/1.1 200 OK\r\nContent-Type: text/calendar\r\nConnection: close\r\n\r\n"
            "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:remote\nDTSTART:20260926T100000Z\nSUMMARY:Remote\nEND:VEVENT\nEND:VCALENDAR\n";
        sources.configure(QJsonArray{definition}, true, 5);
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto errorCode = [&] {
            auto errors = sources.page(from, until, 0).value("errors").toArray();
            return errors.isEmpty() ? QString() : errors.first().toObject().value("code").toString();
        };
        QTRY_COMPARE_WITH_TIMEOUT(sources.page(from, until, 0).value("items").toArray().size(), 1, 3000);
        // Sent to the pinned loopback address, over HTTP/1.1, naming the host.
        QVERIFY2(received.startsWith("GET /feed.ics HTTP/1.1\r\n"), received.left(80).constData());
        QVERIFY(received.contains(QByteArray("\r\nHost: localhost:") + QByteArray::number(server.serverPort()) + "\r\n"));
        response = "HTTP/1.1 302 Found\r\nLocation: https://example.com/feed.ics\r\nConnection: close\r\n\r\n";
        sources.configure(QJsonArray{definition}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "redirect-refused", 3000);
        response = "HTTP/1.1 200 OK\r\nContent-Length: 4194305\r\nConnection: close\r\n\r\n";
        sources.configure(QJsonArray{definition}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "too-large", 3000);
        for (int code : {401, 403}) {
            response = QByteArray("HTTP/1.1 ") + QByteArray::number(code) + " Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
            sources.configure(QJsonArray{definition}, true, 5);
            QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "auth-error", 3000);
        }
        hold = true;
        sources.configure(QJsonArray{definition}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "timeout", 9000);
        hold = false;
        // Loopback needs the per-source opt-in, localhost included.
        sources.configure(QJsonArray{QJsonObject{{"kind", "ics-url"}, {"url", url}}}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "private-address", 3000);
        auto privateSource = QJsonObject{{"kind", "ics-url"}, {"url", QString("https://127.0.0.1:%1/private").arg(server.serverPort())}};
        sources.configure(QJsonArray{privateSource}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "private-address", 3000);
        // With the opt-in the request goes out; the plain-TCP fixture then
        // fails the TLS handshake instead of being refused.
        privateSource.insert("allowLocalNetwork", true);
        sources.configure(QJsonArray{privateSource}, true, 5);
        QTRY_VERIFY_WITH_TIMEOUT(!errorCode().isEmpty(), 9000);
        QVERIFY(errorCode() != "private-address");
        for (const QString &host : {"100.64.0.1", "198.18.0.1", "224.0.0.1", "240.0.0.1", "[2002::1]", "[2001::1]", "[64:ff9b::1]"}) {
            auto src = QJsonObject{{"kind", "ics-url"}, {"url", QString("https://%1:9999/feed.ics").arg(host)}};
            sources.configure(QJsonArray{src}, true, 5);
            QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "private-address", 3000);
        }
        auto localAllowed = QJsonObject{{"kind", "ics-url"}, {"url", "https://100.64.0.1:9999/feed.ics"}, {"allowLocalNetwork", true}};
        sources.configure(QJsonArray{localAllowed}, true, 5);
        QTRY_VERIFY_WITH_TIMEOUT(!errorCode().isEmpty(), 9000);
        QVERIFY(errorCode() != "private-address");
        sources.configure({}, false, 5);
    }
    void paginationFitsAsciiFrame() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath("many.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("BEGIN:VCALENDAR\n");
        for (int i = 0; i < 200; ++i) {
            file.write("BEGIN:VEVENT\nUID:" + QByteArray::number(i) + "\nDTSTART:20260926T090000Z\nSUMMARY:");
            file.write(QString(2000, QChar(0x4e2d)).toUtf8());
            file.write("\nEND:VEVENT\n");
        }
        file.write("END:VCALENDAR\n"); file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "file"}, {"path", file.fileName()}}}, true, 15);
        QVERIFY(settled(sources));
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        int offset = 0, count = 0;
        for (int pageNumber = 0; pageNumber < 100; ++pageNumber) {
            auto page = sources.page(from, until, offset);
            QVERIFY(Island::encodeFrame(page).size() < Island::FrameLimit);
            count += page.value("items").toArray().size();
            int next = page.value("nextOffset").toInt();
            if (next < 0) break;
            QVERIFY(next > offset);
            offset = next;
        }
        QCOMPARE(count, 200);
        QCOMPARE(sources.windowBuilds(), quint64(1));
        sources.configure(QJsonArray{QJsonObject{{"kind", "file"}, {"path", file.fileName()}}}, true, 15);
        QVERIFY(settled(sources));
        sources.page(from, until, 0);
        sources.page(from, until, 1);
        QCOMPARE(sources.windowBuilds(), quint64(2));
    }
    // Each source is bounded on its own, but a window over many accepted
    // sources must stay bounded too: past the aggregate item or byte limit
    // it keeps what fits, and every source it cut reports window-limit.
    void windowIsBoundedAcrossSources() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        auto writeSource = [&](const QString &name, int events, int titleChars) {
            QFile file(dir.filePath(name));
            if (!file.open(QIODevice::WriteOnly)) return QString();
            file.write("BEGIN:VCALENDAR\n");
            for (int i = 0; i < events; ++i) {
                file.write("BEGIN:VEVENT\nUID:" + name.toUtf8() + "-" + QByteArray::number(i)
                    + "\nDTSTART:20260926T090000Z\nSUMMARY:" + QByteArray(titleChars, 'x') + "\nEND:VEVENT\n");
            }
            file.write("END:VCALENDAR\n");
            return file.fileName();
        };
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto collect = [&](Island::Calendar::Sources &sources, QJsonArray *errors) {
            int count = 0, offset = 0;
            qint64 bytes = 0;
            for (int pageNumber = 0; pageNumber < 10000; ++pageNumber) {
                auto page = sources.page(from, until, offset);
                if (pageNumber == 0) *errors = page.value("errors").toArray();
                for (const auto &item : page.value("items").toArray()) bytes += Island::encodeFrame(item.toObject()).size();
                count += page.value("items").toArray().size();
                int next = page.value("nextOffset").toInt();
                if (next < 0) break;
                offset = next;
            }
            return qMakePair(count, bytes);
        };
        // Eight sources of 1000 events each: more items than the window keeps.
        QJsonArray definitions;
        for (int i = 0; i < 8; ++i) {
            const QString path = writeSource(QString("many-%1.ics").arg(i), 1000, 20);
            QVERIFY(!path.isEmpty());
            definitions.append(QJsonObject{{"kind", "file"}, {"path", path}});
        }
        Island::Calendar::Sources many;
        many.configure(definitions, true, 15);
        QVERIFY(settled(many));
        QJsonArray errors;
        auto [count, bytes] = collect(many, &errors);
        QCOMPARE(count, Island::Calendar::WindowItemLimit);
        QVERIFY(bytes <= Island::Calendar::WindowByteLimit);
        QVERIFY(!errors.isEmpty());
        for (const auto &error : errors) QCOMPARE(error.toObject().value("code"), QJsonValue("window-limit"));
        // Fewer but larger items: the byte bound holds the window instead.
        QJsonArray large;
        for (int i = 0; i < 6; ++i) {
            const QString path = writeSource(QString("large-%1.ics").arg(i), 400, 3000);
            QVERIFY(!path.isEmpty());
            large.append(QJsonObject{{"kind", "file"}, {"path", path}});
        }
        Island::Calendar::Sources heavy;
        heavy.configure(large, true, 15);
        QVERIFY(settled(heavy));
        auto [heavyCount, heavyBytes] = collect(heavy, &errors);
        QVERIFY(heavyCount < 2400);
        QVERIFY(heavyBytes <= Island::Calendar::WindowByteLimit);
        QVERIFY(!errors.isEmpty());
        QCOMPARE(errors.last().toObject().value("code"), QJsonValue("window-limit"));
    }
    void serviceVerbs() {
        Island::Calendar::Service service;
        QJsonObject answer;
        auto reply = [&](QJsonObject frame) { answer = frame; };
        QString path = QStringLiteral(FIXTURE_DIR) + "/calendar.ics";
        service.handle({{"type", "calendarConfigure"}, {"requestId", "1"}, {"enabled", true},
                        {"sources", QJsonArray{QJsonObject{{"kind", "file"}, {"path", path}}}}, {"refreshMinutes", 15}}, reply);
        QCOMPARE(answer.value("status"), QJsonValue("ok"));
        service.handle({{"type", "calendarWindow"}, {"requestId", "2"}, {"offset", 0}}, reply);
        QCOMPARE(answer.value("type"), QJsonValue("calendarWindowResult"));
        QVERIFY(answer.value("items").isArray());
        service.handle({{"type", "calendarSetCompleted"}, {"requestId", "3"},
                        {"sourceId", "missing"}, {"uid", "weekly"}, {"completed", true}}, reply);
        QCOMPARE(answer.value("status"), QJsonValue("unavailable"));
        service.handle({{"type", "calendarTest"}, {"requestId", "5"}, {"sourceId", "missing"}}, reply);
        QCOMPARE(answer.value("type"), QJsonValue("calendarResult"));
        QCOMPARE(answer.value("ok"), QJsonValue(false));
        QCOMPARE(answer.value("error"), QJsonValue("not-found"));
        service.handle({{"type", "calendarUnknown"}, {"requestId", "4"}}, reply);
        QCOMPARE(answer.value("status"), QJsonValue("invalid-request"));
    }
    // A URL with a user name or password is never a source and never reaches
    // secret-tool's command line, where any local process could read it.
    void userinfoUrlsNeverReachSecretTool() {
        FakeSecretTool secrets;
        QVERIFY(secrets.dir.isValid());
        Island::Calendar::Sources sources;
        const QString secretUrl = "https://me:fixture-secret@calendar.example/dav/";
        QString stored;
        sources.credential("store", secretUrl, "me", "fixture-password", [&](QString result) { stored = result; });
        QTRY_COMPARE_WITH_TIMEOUT(stored, QString("invalid-url"), 3000);
        QString cleared;
        sources.credential("clear", "https://me@calendar.example/dav/", "me", {}, [&](QString result) { cleared = result; });
        QTRY_COMPARE_WITH_TIMEOUT(cleared, QString("invalid-url"), 3000);
        sources.configure(QJsonArray{
            QJsonObject{{"kind", "caldav"}, {"url", secretUrl}, {"user", "me"}},
            QJsonObject{{"kind", "ics-url"}, {"url", "https://token-secret@calendar.example/basic.ics"}}}, true, 5);
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        QTest::qWait(300);
        auto page = sources.page(from, until, 0);
        QVERIFY2(page.value("items").toArray().isEmpty() && page.value("errors").toArray().isEmpty(),
            "neither source is kept, so neither is fetched or reported");
        QVERIFY2(!secrets.argv().contains("fixture-secret") && !secrets.argv().contains("token-secret"),
            "no secret-tool command line carries the URL's credential");
        QVERIFY2(secrets.argv().isEmpty(), "secret-tool was never started");
        sources.configure({}, false, 5);
    }
    void caldavFallbackAndConflict() {
        FakeSecretTool secrets;
        QVERIFY(secrets.dir.isValid());
        Island::Calendar::Sources sources;
        QString stored;
        sources.credential("store", "https://calendar.example", "fixture", "fixture-password", [&](QString result) { stored = result; });
        QTRY_COMPARE_WITH_TIMEOUT(stored, "ok", 3000);
        QCOMPARE(secrets.stored(), QByteArray("fixture-password"));
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        int reportCount = 0;
        bool put = false;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &reportCount, &put] {
                QByteArray request = socket->readAll();
                if (!request.contains("\r\n\r\n")) return;
                QByteArray response;
                if (request.startsWith("PUT ")) {
                    put = request.contains("If-Match: \"one\"");
                    response = "HTTP/1.1 412 Precondition Failed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                } else if (request.startsWith("PROPFIND ")) {
                    response = "HTTP/1.1 207 Multi-Status\r\nConnection: close\r\n\r\n<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/calendar/</d:href></d:response><d:response><d:href>/calendar/task.ics</d:href></d:response></d:multistatus>";
                } else if (++reportCount == 1) {
                    response = "HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                } else {
                    response = "HTTP/1.1 207 Multi-Status\r\nConnection: close\r\n\r\n<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:href>/calendar/task.ics</d:href><d:propstat><d:prop><d:getetag>\"one\"</d:getetag><c:calendar-data>BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:task\nDUE:20260927T100000Z\nSTATUS:NEEDS-ACTION\nEND:VTODO\nEND:VCALENDAR</c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>";
                }
                socket->write(response); socket->flush(); socket->disconnectFromHost();
            });
        });
        QString url = QString("http://localhost:%1/calendar/").arg(server.serverPort());
        auto account = QJsonObject{{"kind", "caldav"}, {"url", url}, {"user", "fixture"}, {"allowLocalNetwork", true}};
        sources.configure(QJsonArray{account}, true, 5);
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        QTRY_COMPARE_WITH_TIMEOUT(sources.page(from, until, 0).value("items").toArray().size(), 1, 3000);
        QVERIFY(reportCount >= 2);
        QString status;
        auto item = sources.page(from, until, 0).value("items").toArray().first().toObject();
        sources.setCompleted(item.value("sourceId").toString(), "task", true, [&](QString result) { status = result; });
        QTRY_COMPARE_WITH_TIMEOUT(status, "conflict", 3000);
        QVERIFY(put);
        // Reconfiguring, even to an empty list, never touches the keyring;
        // only the explicit clear request does.
        sources.configure({}, true, 5);
        sources.configure(QJsonArray{account}, true, 5);
        sources.configure({}, false, 5);
        QTest::qWait(200);
        QVERIFY(!secrets.cleared());
        QString clearStatus;
        sources.credential("clear", url, "fixture", {}, [&](QString result) { clearStatus = result; });
        QTRY_COMPARE_WITH_TIMEOUT(clearStatus, "ok", 3000);
        QVERIFY(secrets.cleared());
    }
    void oldCountSeriesExpandQuickly() {
        QByteArray data = "BEGIN:VCALENDAR\n";
        for (int i = 0; i < 1000; ++i) {
            data += "BEGIN:VEVENT\nUID:daily" + QByteArray::number(i) + "\nDTSTART:19000101T090000Z\nRRULE:FREQ=DAILY;COUNT=999999\nEND:VEVENT\n";
            data += "BEGIN:VEVENT\nUID:weekly" + QByteArray::number(i) + "\nDTSTART:20210104T090000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=900\nEND:VEVENT\n";
        }
        data += "BEGIN:VEVENT\nUID:ended\nDTSTART:20200101T090000Z\nRRULE:FREQ=DAILY;COUNT=10\nEND:VEVENT\nEND:VCALENDAR\n";
        auto parsed = Island::Calendar::parse(data);
        QVERIFY(parsed.error.isEmpty());
        QElapsedTimer timer;
        timer.start();
        Island::Calendar::WindowStats stats;
        int daily = 0, weekly = 0, ended = 0;
        Island::Calendar::visitWindow(parsed.entries, QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
            QDateTime::fromString("2026-10-10T00:00:00Z", Qt::ISODate), "fixture", {}, [&](const QJsonObject &item) {
                QString uid = item.value("uid").toString();
                if (uid.startsWith("daily")) ++daily;
                else if (uid.startsWith("weekly")) ++weekly;
                else ++ended;
                return true;
            }, &stats);
        QVERIFY2(timer.elapsed() < 5000, qPrintable(QString("expansion took %1 ms").arg(timer.elapsed())));
        QVERIFY(!stats.limited);
        QCOMPARE(daily, 1000 * 20);
        QCOMPARE(weekly, 1000 * 6);
        QCOMPARE(ended, 0);
        // COUNT arithmetic: the 900th Monday-or-Wednesday from 2021-01-04 is
        // 2029-08-15, the last instance before the series ends.
        auto last = Island::Calendar::window(Island::Calendar::parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:w\nDTSTART:20210104T090000Z\n"
            "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=900\nEND:VEVENT\nEND:VCALENDAR\n").entries,
            QDateTime::fromString("2029-08-12T00:00:00Z", Qt::ISODate), QDateTime::fromString("2029-09-01T00:00:00Z", Qt::ISODate), "fixture");
        QCOMPARE(startsFor(last, "w"), QStringList({"2029-08-13T09:00:00Z", "2029-08-15T09:00:00Z"}));
    }
    void longRuleListsAreBoundedBeforeExpansion() {
        auto expand = [](const QByteArray &rule, const QString &from, const QString &until,
                         Island::Calendar::WindowStats &stats, QStringList &starts) {
            auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:lists\nDTSTART:" + rule
                + "\nEND:VEVENT\nEND:VCALENDAR\n");
            QVERIFY(parsed.error.isEmpty());
            Island::Calendar::visitWindow(parsed.entries, QDateTime::fromString(from, Qt::ISODate),
                QDateTime::fromString(until, Qt::ISODate), "fixture", {}, [&](const QJsonObject &item) {
                    starts.append(QDateTime::fromString(item.value("start").toString(), Qt::ISODate).toString(Qt::ISODate));
                    return true;
                }, &stats);
        };
        // A 10,000-fold repeat of one month day and one weekday is still
        // "Mondays that fall on the 1st": it expands fast and correctly.
        QByteArray repeated = "20260101T090000Z\nRRULE:FREQ=YEARLY;BYMONTH=1,2,3,4,5,6,7,8,9,10,11,12;BYMONTHDAY=1";
        for (int i = 1; i < 10000; ++i) repeated += ",1";
        repeated += ";BYDAY=MO";
        for (int i = 1; i < 10000; ++i) repeated += ",MO";
        QElapsedTimer timer;
        timer.start();
        Island::Calendar::WindowStats stats;
        QStringList starts;
        expand(repeated, "2026-01-01T00:00:00Z", "2028-01-01T00:00:00Z", stats, starts);
        QVERIFY2(timer.elapsed() < 1000, qPrintable(QString("expansion took %1 ms").arg(timer.elapsed())));
        QVERIFY(!stats.limited);
        QVERIFY2(Island::Calendar::StepBudget - stats.budget < 1000,
            qPrintable(QString("spent %1 steps").arg(Island::Calendar::StepBudget - stats.budget)));
        QCOMPARE(starts, QStringList({"2026-06-01T09:00:00Z", "2027-02-01T09:00:00Z",
            "2027-03-01T09:00:00Z", "2027-11-01T09:00:00Z"}));
        // Every distinct value at once, walked from year 1000 by COUNT: each
        // year costs 12 x 62 x 77 checks up front, so the budget ends after a
        // few years instead of the helper spending seconds on it.
        QByteArray widest = "10000101T090000Z\nRRULE:FREQ=YEARLY;COUNT=999999;BYMONTH=1,2,3,4,5,6,7,8,9,10,11,12;BYMONTHDAY=";
        QByteArrayList days, weekdays;
        for (int d = 1; d <= 31; ++d) days << QByteArray::number(d) << QByteArray::number(-d);
        for (const char *name : {"MO", "TU", "WE", "TH", "FR", "SA", "SU"}) {
            weekdays << name;
            for (int n = 1; n <= 5; ++n) weekdays << QByteArray::number(n) + name << QByteArray::number(-n) + name;
        }
        widest += days.join(',') + ";BYDAY=" + weekdays.join(',');
        timer.restart();
        Island::Calendar::WindowStats widestStats;
        starts.clear();
        expand(widest, "2026-09-20T00:00:00Z", "2026-10-10T00:00:00Z", widestStats, starts);
        QVERIFY2(timer.elapsed() < 1000, qPrintable(QString("expansion took %1 ms").arg(timer.elapsed())));
        QVERIFY(widestStats.limited);
        QVERIFY(starts.isEmpty());
    }
    void futureSeriesCostNothing() {
        // Series that start after the window expand no period, so however
        // costly their rules, they neither spend the budget nor report a limit.
        QByteArray days, weekdays;
        for (int d = 1; d <= 31; ++d) days += QByteArray(d > 1 ? "," : "") + QByteArray::number(d) + "," + QByteArray::number(-d);
        for (const char *name : {"MO", "TU", "WE", "TH", "FR", "SA", "SU"}) {
            weekdays += QByteArray(weekdays.isEmpty() ? "" : ",") + name;
            for (int n = 1; n <= 5; ++n) weekdays += "," + QByteArray::number(n) + name + ",-" + QByteArray::number(n) + name;
        }
        QByteArray data = "BEGIN:VCALENDAR\n";
        for (int i = 0; i < 9; ++i)
            data += "BEGIN:VEVENT\nUID:future" + QByteArray::number(i) + "\nDTSTART:20990101T090000Z\n"
                "RRULE:FREQ=YEARLY;BYMONTH=1,2,3,4,5,6,7,8,9,10,11,12;BYMONTHDAY=" + days + ";BYDAY=" + weekdays + "\nEND:VEVENT\n";
        data += "END:VCALENDAR\n";
        auto parsed = Island::Calendar::parse(data);
        QVERIFY(parsed.error.isEmpty());
        Island::Calendar::WindowStats stats;
        int items = 0;
        Island::Calendar::visitWindow(parsed.entries, QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
            QDateTime::fromString("2026-10-10T00:00:00Z", Qt::ISODate), "fixture", {},
            [&](const QJsonObject &) { ++items; return true; }, &stats);
        QCOMPARE(items, 0);
        QVERIFY(!stats.limited);
        QCOMPARE(stats.budget, Island::Calendar::StepBudget);
        // The same file as a source reports no recurrence-limit error.
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath("future.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(data);
        file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "file"}, {"path", file.fileName()}}}, true, 15);
        QVERIFY(settled(sources));
        auto page = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                 QDateTime::fromString("2026-10-10T00:00:00Z", Qt::ISODate), 0);
        QCOMPARE(page.value("errors").toArray().size(), 0);
        QCOMPARE(page.value("items").toArray().size(), 0);
    }
    void recurrenceBudgetLimitsSource() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath("heavy.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:plain\nDTSTART:20260925T090000Z\nSUMMARY:Plain\nEND:VEVENT\n");
        for (int i = 0; i < 500; ++i)
            file.write("BEGIN:VEVENT\nUID:heavy" + QByteArray::number(i) + "\nDTSTART:10000101T090000Z\nRRULE:FREQ=MONTHLY;BYMONTHDAY=1,2;COUNT=999999\nEND:VEVENT\n");
        file.write("END:VCALENDAR\n");
        file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "file"}, {"path", file.fileName()}}}, true, 15);
        QVERIFY(settled(sources));
        QElapsedTimer timer;
        timer.start();
        auto page = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                 QDateTime::fromString("2026-10-10T00:00:00Z", Qt::ISODate), 0);
        QVERIFY2(timer.elapsed() < 5000, qPrintable(QString("expansion took %1 ms").arg(timer.elapsed())));
        auto errors = page.value("errors").toArray();
        QCOMPARE(errors.size(), 1);
        QCOMPARE(errors[0].toObject().value("code"), QJsonValue("recurrence-limit"));
        QCOMPARE(itemsFor(page.value("items").toArray(), "plain").size(), 1);
    }
    void alarmPropertiesStayInAlarm() {
        auto items = fixtureWindow("alarms.ics");
        auto event = itemsFor(items, "dentist");
        QCOMPARE(event.size(), 1);
        QCOMPARE(event[0].value("title"), QJsonValue("Dentist"));
        QCOMPARE(QDateTime::fromString(event[0].value("start").toString(), Qt::ISODate).secsTo(
            QDateTime::fromString(event[0].value("end").toString(), Qt::ISODate)), 3600);
        QVERIFY(!event[0].contains("unsupported"));
        auto todo = itemsFor(items, "call");
        QCOMPARE(todo.size(), 1);
        QCOMPARE(todo[0].value("title"), QJsonValue("Call back"));
    }
    void multiWeekIntervalsAlignToWeekStart() {
        QCOMPARE(startsFor(fixtureWindow("recurrence-edges.ics"), "biweekly"),
                 QStringList({"2026-09-23T09:00:00Z", "2026-10-05T09:00:00Z", "2026-10-07T09:00:00Z"}));
    }
    void exclusionsAndOverridesMatchByInstant() {
        auto berlin = itemsFor(fixtureWindow("recurrence-edges.ics"), "berlin");
        QCOMPARE(berlin.size(), 2);
        QCOMPARE(berlin[0].value("start"), QJsonValue("2026-09-21T10:00:00.000+02:00"));
        QCOMPARE(berlin[1].value("title"), QJsonValue("Berlin moved"));
        QCOMPARE(berlin[1].value("start"), QJsonValue("2026-10-05T15:00:00.000+02:00"));
        QCOMPARE(berlin[1].value("instanceStart"), QJsonValue("2026-10-05T10:00:00.000+02:00"));
    }
    void timeZoneIdentifierForms() {
        auto items = fixtureWindow("timezones.ics");
        for (const char *uid : {"quoted", "windows", "prefixed", "colon"}) {
            auto item = itemsFor(items, uid);
            QVERIFY2(item.size() == 1, uid);
            QCOMPARE(item[0].value("start"), QJsonValue("2026-09-28T10:00:00.000+02:00"));
            QVERIFY2(!item[0].contains("unsupported"), uid);
        }
        auto unknown = itemsFor(items, "unknown");
        QCOMPARE(unknown.size(), 1);
        QCOMPARE(QDateTime::fromString(unknown[0].value("start").toString(), Qt::ISODate),
                 QDateTime(QDate(2026, 9, 28), QTime(10, 0), QTimeZone::systemTimeZone()));
        QVERIFY(unknown[0].value("unsupported").toArray().contains("TZID"));
        auto explicitTime = itemsFor(items, "date-time");
        QCOMPARE(explicitTime.size(), 1);
        QCOMPARE(explicitTime[0].value("allDay"), QJsonValue(false));
        QCOMPARE(explicitTime[0].value("start"), QJsonValue("2026-09-28T10:00:00.000Z"));
    }
    // Pins the documented subset: cancelled instances are hidden, an override
    // moved in from outside the window is shown, and YEARLY with BYDAY stays
    // in the month of DTSTART.
    void cancelledMovedAndYearlyInstances() {
        auto items = fixtureWindow("recurrence-edges.ics");
        QCOMPARE(startsFor(items, "cancel-one"), QStringList({"2026-09-22T09:00:00Z", "2026-10-06T09:00:00Z"}));
        QVERIFY(itemsFor(items, "cancelled").isEmpty());
        auto moved = itemsFor(items, "moved-in");
        QCOMPARE(moved.size(), 1);
        QCOMPARE(moved[0].value("title"), QJsonValue("Moved into the window"));
        QVERIFY(moved[0].value("instanceStart").toString().startsWith("2026-09-08"));
        QCOMPARE(startsFor(items, "yearly-byday"), QStringList({"2026-09-21T09:00:00Z", "2026-09-28T09:00:00Z"}));
    }
    void localAddressRanges() {
        using Island::Calendar::isLocalAddress;
        for (const char *address : {"127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1",
                                    "169.254.10.10", "0.0.0.0", "::1", "::", "fe80::1", "fc00::1", "fd12:3456::1",
                                    "::ffff:10.0.0.1", "::ffff:127.0.0.1",
                                    "100.64.0.1", "100.127.255.254", "198.18.0.1", "198.19.255.254",
                                    "224.0.0.1", "239.255.255.255", "240.0.0.1", "255.255.255.255",
                                    "2002::1", "2001::1", "2001:db8::1", "64:ff9b::1",
                                    "::ffff:100.64.0.1", "::ffff:198.18.0.1"})
            QVERIFY2(isLocalAddress(QHostAddress(QString::fromLatin1(address))), address);
        for (const char *address : {"8.8.8.8", "172.32.0.1", "172.15.255.255", "192.169.0.1", "1.1.1.1",
                                    "2001:4860:4860::8888", "::ffff:8.8.8.8"})
            QVERIFY2(!isLocalAddress(QHostAddress(QString::fromLatin1(address))), address);
    }
    void cookieIsolationBetweenSources() {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        QByteArray received1, received2;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &received1, &received2] {
                QByteArray req = socket->readAll();
                if (!req.contains("\r\n\r\n")) return;
                if (req.contains("GET /first.ics")) {
                    received1 += req;
                    socket->write("HTTP/1.1 200 OK\r\nSet-Cookie: session=secret123\r\nContent-Type: text/calendar\r\nConnection: close\r\n\r\n"
                                  "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:1\nDTSTART:20260926T100000Z\nSUMMARY:One\nEND:VEVENT\nEND:VCALENDAR\n");
                } else {
                    received2 += req;
                    socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/calendar\r\nConnection: close\r\n\r\n"
                                  "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:2\nDTSTART:20260926T110000Z\nSUMMARY:Two\nEND:VEVENT\nEND:VCALENDAR\n");
                }
                socket->flush();
                socket->disconnectFromHost();
            });
        });

        Island::Calendar::Sources sources;
        QString url1 = QString("http://localhost:%1/first.ics").arg(server.serverPort());
        QString url2 = QString("http://localhost:%1/second.ics").arg(server.serverPort());
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);

        sources.configure(QJsonArray{QJsonObject{{"kind", "ics-url"}, {"url", url1}, {"allowLocalNetwork", true}}}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(sources.page(from, until, 0).value("items").toArray().size(), 1, 3000);
        QVERIFY(received1.contains("GET /first.ics"));

        sources.configure(QJsonArray{QJsonObject{{"kind", "ics-url"}, {"url", url2}, {"allowLocalNetwork", true}}}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(sources.page(from, until, 0).value("items").toArray().size(), 1, 3000);
        QVERIFY(received2.contains("GET /second.ics"));
        QVERIFY(!received2.contains("session=secret123"));
        QVERIFY(!received2.contains("Cookie:"));
    }
    void crossPortRedirectRefused() {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &server] {
                QByteArray req = socket->readAll();
                if (!req.contains("\r\n\r\n")) return;
                int otherPort = server.serverPort() + 1;
                QByteArray redirect = "HTTP/1.1 302 Found\r\nLocation: http://localhost:" + QByteArray::number(otherPort) + "/redirected.ics\r\nConnection: close\r\n\r\n";
                socket->write(redirect);
                socket->flush();
                socket->disconnectFromHost();
            });
        });

        Island::Calendar::Sources sources;
        QString url = QString("http://localhost:%1/feed.ics").arg(server.serverPort());
        auto definition = QJsonObject{{"kind", "ics-url"}, {"url", url}, {"allowLocalNetwork", true}};
        sources.configure(QJsonArray{definition}, true, 5);

        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto errorCode = [&] {
            auto errors = sources.page(from, until, 0).value("errors").toArray();
            return errors.isEmpty() ? QString() : errors.first().toObject().value("code").toString();
        };

        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "redirect-refused", 3000);
    }
    void completionRewritesUnfoldedTodos() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QString uid = "folded-uid-" + QString(80, 'x');
        QFile file(dir.filePath("task.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID;X-ORIGIN=test:folded-uid-" + QByteArray(40, 'x') + "\r\n " + QByteArray(40, 'x')
            + "\r\nDUE:20260927T100000Z\r\nSTATUS:NEEDS-ACTION\r\nSUMMARY:A long\r\n  folded summary\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\nEND:VALARM\r\nEND:VTODO\r\n"
            "BEGIN:VTODO\r\nUID;X-ORIGIN=test:folded-uid-" + QByteArray(80, 'x') + "\r\nRECURRENCE-ID:20261004T100000Z\r\nDUE:20261004T100000Z\r\nSTATUS:NEEDS-ACTION\r\nEND:VTODO\r\nEND:VCALENDAR\r\n");
        file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "vdir"}, {"path", dir.path()}}}, true, 15);
        QVERIFY(settled(sources));
        auto item = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                 QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate), 0).value("items").toArray().first().toObject();
        QCOMPARE(item.value("uid").toString(), uid);
        QString status;
        sources.setCompleted(item.value("sourceId").toString(), uid, true, [&](QString result) { status = result; });
        QCOMPARE(status, "ok");
        QVERIFY(file.open(QIODevice::ReadOnly));
        QString content = QString::fromUtf8(file.readAll());
        file.close();
        QCOMPARE(content.count("STATUS:COMPLETED"), 2);
        QVERIFY(!content.contains("NEEDS-ACTION"));
        QVERIFY(content.contains("SUMMARY:A long\r\n  folded summary"));
        QVERIFY(content.indexOf("STATUS:COMPLETED") < content.indexOf("BEGIN:VALARM"));
        QVERIFY(content.indexOf("COMPLETED:2") < content.indexOf("BEGIN:VALARM"));
    }
    void vdirCompletionRefusesChangedFile() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath("task.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:task\nDUE:20260927T100000Z\nSTATUS:NEEDS-ACTION\nEND:VTODO\nEND:VCALENDAR\n");
        file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "vdir"}, {"path", dir.path()}}}, true, 15);
        QVERIFY(settled(sources));
        auto sourceId = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                     QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate), 0)
                            .value("items").toArray().first().toObject().value("sourceId").toString();
        // A sync tool rewrites the file before the watcher reloads it.
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write("BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:task\nDUE:20260927T100000Z\nSTATUS:NEEDS-ACTION\nSUMMARY:Edited elsewhere\nEND:VTODO\nEND:VCALENDAR\n");
        file.close();
        QString status;
        sources.setCompleted(sourceId, "task", true, [&](QString result) { status = result; });
        QCOMPARE(status, "conflict");
        QVERIFY(file.open(QIODevice::ReadOnly));
        QVERIFY(!file.readAll().contains("STATUS:COMPLETED"));
    }
    void credentialCallsDoNotBlock() {
        FakeSecretTool secrets(1);
        QVERIFY(secrets.dir.isValid());
        Island::Calendar::Sources sources;
        QString status;
        QElapsedTimer timer;
        timer.start();
        sources.credential("store", "https://calendar.example", "fixture", "fixture-password", [&](QString result) { status = result; });
        QVERIFY(timer.elapsed() < 500);
        QVERIFY(status.isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(status, "ok", 3000);
        QCOMPARE(secrets.stored(), QByteArray("fixture-password"));
    }
    // An unlock prompt can take longer than a few seconds: a slow secret-tool
    // still succeeds, and one that outlasts the timeout is reported as a locked
    // keyring rather than as a refused password.
    void slowKeyringUnlockIsNotAnAuthError() {
        {
            FakeSecretTool secrets(4);
            QVERIFY(secrets.dir.isValid());
            Island::Calendar::Sources sources;
            QString status;
            sources.credential("store", "https://calendar.example", "fixture", "fixture-password", [&](QString result) { status = result; });
            QTRY_COMPARE_WITH_TIMEOUT(status, "ok", 8000);
        }
        FakeSecretTool secrets(3);
        QVERIFY(secrets.dir.isValid());
        Island::Calendar::Sources sources;
        sources.setSecretTimeout(500);
        sources.configure(QJsonArray{QJsonObject{{"kind", "caldav"}, {"user", "fixture"}, {"allowLocalNetwork", true},
            {"url", "http://localhost:9/calendar/"}}}, true, 5);
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto errorCode = [&] {
            auto errors = sources.page(from, until, 0).value("errors").toArray();
            return errors.isEmpty() ? QString() : errors.first().toObject().value("code").toString();
        };
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "secret-service-locked", 3000);
    }
    void pendingWriteSettlesWhenReconfigured() {
        FakeSecretTool secrets;
        QVERIFY(secrets.dir.isValid());
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        int putsSeen = 0;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &putsSeen] {
                QByteArray request = socket->readAll();
                if (request.startsWith("PUT ")) { ++putsSeen; return; }
                if (!request.contains("</c:calendar-query>")) return;
                socket->write("HTTP/1.1 207 Multi-Status\r\nConnection: close\r\n\r\n<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">");
                // Only the reminder query has a member.
                if (request.contains("name=\"VTODO\"")) socket->write("<d:response><d:href>/calendar/task.ics</d:href><d:propstat><d:prop><d:getetag>\"one\"</d:getetag><c:calendar-data>"
                    "BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:task\nDUE:20260927T100000Z\nEND:VTODO\nEND:VCALENDAR</c:calendar-data></d:prop></d:propstat></d:response>");
                socket->write("</d:multistatus>");
                socket->flush(); socket->disconnectFromHost();
            });
        });
        auto account = QJsonObject{{"kind", "caldav"}, {"url", QString("http://localhost:%1/calendar/").arg(server.serverPort())},
                                   {"user", "fixture"}, {"allowLocalNetwork", true}};
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{account}, true, 5);
        auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        QTRY_COMPARE_WITH_TIMEOUT(sources.page(from, until, 0).value("items").toArray().size(), 1, 3000);
        QTest::qWait(200);
        QCOMPARE(sources.page(from, until, 0).value("items").toArray().size(), 1);
        auto sourceId = sources.page(from, until, 0).value("items").toArray().first().toObject().value("sourceId").toString();
        // More writes than the six connections per host, so most wait queued.
        QStringList statuses(32);
        for (int i = 0; i < statuses.size(); ++i)
            sources.setCompleted(sourceId, "task", true, [&statuses, i](QString result) { statuses[i] = result; });
        QTRY_VERIFY_WITH_TIMEOUT(putsSeen >= 6, 3000);
        QTest::qWait(300);
        QCOMPARE(statuses.count(QString()), 32);
        // Every held write answers before configure() returns.
        sources.configure({}, false, 5);
        QCOMPARE(statuses.count("cancelled"), 32);
    }
    void reconfigureAbortsEveryRequest() {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        int open = 0, opened = 0;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            ++open; ++opened;
            connect(socket, &QTcpSocket::disconnected, socket, [&open, socket] { --open; socket->deleteLater(); });
        });
        QJsonArray feeds;
        for (int i = 0; i < 32; ++i)
            feeds.append(QJsonObject{{"kind", "ics-url"}, {"allowLocalNetwork", true},
                                     {"url", QString("http://localhost:%1/feed-%2.ics").arg(server.serverPort()).arg(i)}});
        Island::Calendar::Sources sources;
        sources.configure(feeds, true, 5);
        QTRY_VERIFY_WITH_TIMEOUT(opened >= 6, 3000);
        sources.configure({}, false, 5);
        QTRY_COMPARE_WITH_TIMEOUT(open, 0, 1000);
        QTest::qWait(300);
        QCOMPARE(open, 0);
    }
    void testReportsFreshLoadResult() {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        QByteArray response;
        bool hold = false;
        int requests = 0;
        QList<QPointer<QTcpSocket>> held;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &response, &hold, &requests, &held] {
                if (!socket->peek(65536).contains("\r\n\r\n")) return;
                socket->readAll();
                ++requests;
                if (hold) { held.append(socket); return; }
                socket->write(response); socket->flush(); socket->disconnectFromHost();
            });
        });
        const QByteArray ok = "HTTP/1.1 200 OK\r\nContent-Type: text/calendar\r\nConnection: close\r\n\r\n"
            "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:remote\nDTSTART:20260926T100000Z\nSUMMARY:Remote\nEND:VEVENT\nEND:VCALENDAR\n";
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto feed = QJsonObject{{"kind", "ics-url"}, {"allowLocalNetwork", true},
                                {"url", QString("http://localhost:%1/feed.ics").arg(server.serverPort())}};
        Island::Calendar::Sources sources;
        response = ok;
        sources.configure(QJsonArray{feed}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(sources.page(from, until, 0).value("items").toArray().size(), 1, 3000);
        const QString id = sources.page(from, until, 0).value("items").toArray().first().toObject().value("sourceId").toString();
        QString result = "unset";
        auto run = [&] { result = "unset"; sources.test(id, [&](QString error) { result = error; }); };

        // Success: a new request goes out even though the window is cached.
        int before = requests;
        run();
        QCOMPARE(result, "unset");
        QTRY_COMPARE_WITH_TIMEOUT(result, QString(), 3000);
        QCOMPARE(requests, before + 1);

        response = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        run();
        QTRY_COMPARE_WITH_TIMEOUT(result, "auth-error", 3000);

        hold = true;
        run();
        QTRY_COMPARE_WITH_TIMEOUT(result, "timeout", 9500);

        // While loading: a second test joins the running load instead of
        // starting another, and both answer when that load completes.
        held.clear();
        response = ok;
        before = requests;
        QString first = "unset", second = "unset";
        sources.test(id, [&](QString error) { first = error; });
        QTRY_COMPARE_WITH_TIMEOUT(requests, before + 1, 3000);
        sources.test(id, [&](QString error) { second = error; });
        QTest::qWait(200);
        QCOMPARE(first, "unset");
        QCOMPARE(second, "unset");
        QCOMPARE(requests, before + 1);
        for (const auto &socket : held) if (socket) { socket->write(ok); socket->flush(); socket->disconnectFromHost(); }
        QTRY_COMPARE_WITH_TIMEOUT(first, QString(), 3000);
        QCOMPARE(second, QString());
        QCOMPARE(requests, before + 1);
        hold = false;

        QString unknown = "unset";
        sources.test("no-such-source", [&](QString error) { unknown = error; });
        QCOMPARE(unknown, "not-found");

        // Reconfiguring answers a waiting test instead of dropping it.
        hold = true;
        run();
        QTRY_VERIFY_WITH_TIMEOUT(requests > before + 1, 3000);
        sources.configure({}, false, 5);
        QCOMPARE(result, "cancelled");
    }
    void testReloadsLocalSource() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath("local.ics"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:a\nDTSTART:20260926T100000Z\nEND:VEVENT\nEND:VCALENDAR\n");
        file.close();
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "file"}, {"path", file.fileName()}}}, true, 15);
        QVERIFY(settled(sources));
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        const QString id = sources.page(from, until, 0).value("items").toArray().first().toObject().value("sourceId").toString();
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write("not a calendar");
        file.close();
        QString result = "unset";
        sources.test(id, [&](QString error) { result = error; });
        QTRY_COMPARE(result, "invalid-calendar");
        QCOMPARE(sources.page(from, until, 0).value("items").toArray().size(), 0);
    }
    // A sync that rewrites every file of a vdir coalesces into a few reloads,
    // not one full re-read per changed file, and the last content wins.
    void vdirSyncReloadsOnce() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        auto write = [&](int i, const char *title) {
            QFile file(dir.filePath(QString("e%1.ics").arg(i)));
            if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
            file.write("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:e" + QByteArray::number(i) + "\nSUMMARY:" + title
                + "\nDTSTART:20260926T100000Z\nEND:VEVENT\nEND:VCALENDAR\n");
            return true;
        };
        for (int i = 0; i < 200; ++i) QVERIFY(write(i, "before"));
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "vdir"}, {"path", dir.path()}}}, true, 15);
        QVERIFY(settled(sources));
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto all = [&] {
            QJsonArray items;
            for (int offset = 0; offset >= 0;) {
                auto page = sources.page(from, until, offset);
                for (const auto &item : page.value("items").toArray()) items.append(item);
                offset = page.value("nextOffset").toInt();
            }
            return items;
        };
        QCOMPARE(all().size(), 200);
        QSignalSpy changed(&sources, &Island::Calendar::Sources::changed);
        for (int i = 0; i < 200; ++i) QVERIFY(write(i, "after"));
        QTRY_VERIFY(changed.size() >= 1);
        QTest::qWait(1000);
        QVERIFY2(changed.size() <= 3, QByteArray::number(changed.size()));
        const auto items = all();
        QCOMPARE(items.size(), 200);
        for (const auto &item : items) QCOMPARE(item.toObject().value("title"), QJsonValue("after"));
    }
    // A vdir member that is deleted and recreated is watched again, so an
    // in-place edit after that still reloads.
    void vdirMemberRecreatedIsWatchedAgain() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath("member.ics");
        auto write = [&](const char *title) {
            QFile file(path);
            if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
            file.write(QByteArray("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:member\nSUMMARY:") + title
                + "\nDTSTART:20260926T100000Z\nEND:VEVENT\nEND:VCALENDAR\n");
            return true;
        };
        QVERIFY(write("one"));
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "vdir"}, {"path", dir.path()}}}, true, 15);
        QVERIFY(settled(sources));
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto title = [&] {
            const auto items = sources.page(from, until, 0).value("items").toArray();
            return items.isEmpty() ? QString("<none>") : items.first().toObject().value("title").toString();
        };
        QCOMPARE(title(), "one");
        QVERIFY(QFile::remove(path));
        QTRY_COMPARE_WITH_TIMEOUT(title(), "<none>", 5000);
        QVERIFY(write("two"));
        QTRY_COMPARE_WITH_TIMEOUT(title(), "two", 5000);
        QTest::qWait(400);
        QVERIFY(write("three"));
        QTRY_COMPARE_WITH_TIMEOUT(title(), "three", 5000);
    }
    // Reading and parsing a large source runs off the helper's event loop:
    // configure() returns at once, and other work (IPC, media control) keeps
    // running while the source parses.
    void largeSourceParsesOffTheEventLoop() {
        QTemporaryFile file(QDir::tempPath() + "/nookisle-large-XXXXXX.ics");
        QVERIFY(file.open());
        file.write("BEGIN:VCALENDAR\n");
        for (int event = 0; event < 55; ++event) {
            QByteArray dates;
            for (int i = 0; i < 3900; ++i)
                dates += (i ? "," : "") + QDateTime(QDate(2020, 1, 1), QTime(0, 0), QTimeZone::UTC).addSecs(3600LL * i)
                    .toString("yyyyMMdd'T'HHmmss'Z'").toLatin1();
            file.write("BEGIN:VEVENT\nUID:e" + QByteArray::number(event) + "\nDTSTART:20260926T100000Z\nEXDATE:"
                + dates + "\nEND:VEVENT\n");
        }
        file.write("END:VCALENDAR\n");
        file.close();
        QVERIFY(file.size() > 3 * 1024 * 1024);
        Island::Calendar::Sources sources;
        QElapsedTimer timer;
        timer.start();
        sources.configure(QJsonArray{QJsonObject{{"kind", "file"}, {"path", file.fileName()}}}, true, 15);
        QVERIFY2(timer.elapsed() < 100, QByteArray::number(timer.elapsed()));
        QVERIFY(sources.loading());
        bool ranWhileLoading = false, ran = false;
        QTimer::singleShot(0, &sources, [&] { ran = true; ranWhileLoading = sources.loading(); });
        QTRY_VERIFY(ran);
        QVERIFY2(ranWhileLoading, "a queued zero-delay task waited for the parse");
        QVERIFY(settled(sources));
        const auto page = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                       QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate), 0);
        QCOMPARE(page.value("errors").toArray().size(), 0);
        int total = page.value("items").toArray().size();
        QCOMPARE(total, 55);
    }
    // Reconfiguring a CalDAV account while its reminder response still parses
    // must discard that whole superseded load: its events never reappear in
    // the new configuration's (here empty) result, and the new load settles.
    void reconfigureDuringParseDiscardsTheOldLoad() {
        FakeSecretTool secrets;
        QVERIFY(secrets.dir.isValid());
        QByteArray todos;
        for (int todo = 0; todo < 50; ++todo) {
            QByteArray dates;
            for (int i = 0; i < 3900; ++i)
                dates += (i ? "," : "") + QDateTime(QDate(2020, 1, 1), QTime(0, 0), QTimeZone::UTC).addSecs(3600LL * i)
                    .toString("yyyyMMdd'T'HHmmss'Z'").toLatin1();
            todos += "BEGIN:VTODO\nUID:t" + QByteArray::number(todo) + "\nDTSTART:20260926T100000Z\nEXDATE:" + dates + "\nEND:VTODO\n";
        }
        bool stale = true, todoAnswered = false;
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                if (!socket->peek(65536).contains("</c:calendar-query>")) return;
                const bool todo = socket->readAll().contains("name=\"VTODO\"");
                QByteArray body = "<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">";
                if (stale) {
                    body += "<d:response><d:href>/calendar/" + QByteArray(todo ? "todos" : "old") + ".ics</d:href><d:propstat><d:prop>"
                        "<d:getetag>\"1\"</d:getetag><c:calendar-data>BEGIN:VCALENDAR\n"
                        + (todo ? todos : QByteArray("BEGIN:VEVENT\nUID:old\nSUMMARY:Removed\nDTSTART:20260926T100000Z\nEND:VEVENT\n"))
                        + "END:VCALENDAR\n</c:calendar-data></d:prop></d:propstat></d:response>";
                    if (todo) todoAnswered = true;
                }
                body += "</d:multistatus>";
                socket->write("HTTP/1.1 207 Multi-Status\r\nConnection: close\r\nContent-Length: "
                              + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->flush(); socket->disconnectFromHost();
            });
        });
        const QJsonArray account{QJsonObject{{"kind", "caldav"}, {"user", "fixture"}, {"allowLocalNetwork", true},
            {"url", QString("http://localhost:%1/calendar/").arg(server.serverPort())}}};
        Island::Calendar::Sources sources;
        sources.configure(account, true, 5);
        QTRY_VERIFY_WITH_TIMEOUT(todoAnswered, 5000);
        QTest::qWait(50);
        QVERIFY2(sources.loading(), "the reminder response is still parsing");
        stale = false;
        sources.configure(account, true, 5);
        QVERIFY(settled(sources));
        QTest::qWait(2000);
        const auto page = sources.page(QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate),
                                       QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate), 0);
        QCOMPARE(page.value("items").toArray().size(), 0);
        QCOMPARE(page.value("errors").toArray().size(), 0);
        QVERIFY(!sources.loading());
    }
    void testReportsCaldavEventParseError() {
        FakeSecretTool secrets;
        QVERIFY(secrets.dir.isValid());
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        int todoQueries = 0;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &todoQueries] {
                if (!socket->peek(65536).contains("</c:calendar-query>")) return;
                QByteArray request = socket->readAll();
                socket->write("HTTP/1.1 207 Multi-Status\r\nConnection: close\r\n\r\n<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">");
                // The event member is malformed; the reminder query succeeds empty.
                if (request.contains("name=\"VTODO\"")) ++todoQueries;
                else socket->write("<d:response><d:href>/calendar/bad.ics</d:href><d:propstat><d:prop><d:getetag>\"1\"</d:getetag>"
                                   "<c:calendar-data>not a calendar</c:calendar-data></d:prop></d:propstat></d:response>");
                socket->write("</d:multistatus>");
                socket->flush(); socket->disconnectFromHost();
            });
        });
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{QJsonObject{{"kind", "caldav"}, {"user", "fixture"}, {"allowLocalNetwork", true},
            {"url", QString("http://localhost:%1/calendar/").arg(server.serverPort())}}}, true, 5);
        const auto from = QDateTime::fromString("2026-09-20T00:00:00Z", Qt::ISODate);
        const auto until = QDateTime::fromString("2026-10-01T00:00:00Z", Qt::ISODate);
        auto errorCode = [&] {
            auto errors = sources.page(from, until, 0).value("errors").toArray();
            return errors.isEmpty() ? QString() : errors.first().toObject().value("code").toString();
        };
        QTRY_COMPARE_WITH_TIMEOUT(errorCode(), "invalid-calendar", 3000);
        const QString id = sources.page(from, until, 0).value("errors").toArray().first().toObject().value("sourceId").toString();
        QString result = "unset";
        sources.test(id, [&](QString error) { result = error; });
        QTRY_VERIFY_WITH_TIMEOUT(result != "unset", 3000);
        QCOMPARE(result, "invalid-calendar");
        QTest::qWait(200);
        QCOMPARE(errorCode(), "invalid-calendar");
    }
    void credentialStoreRefetchesMatchingAccounts() {
        FakeSecretTool secrets;
        QVERIFY(secrets.dir.isValid());
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        QHash<QByteArray, int> reports;
        bool holdA = false;
        QList<QPointer<QTcpSocket>> held;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket, &reports, &holdA, &held] {
                if (!socket->peek(65536).contains("</c:calendar-query>")) return;
                QByteArray request = socket->readAll();
                QByteArray path = request.split(' ').value(1);
                ++reports[path];
                if (holdA && path == "/a/") { held.append(socket); return; }
                socket->write("HTTP/1.1 207 Multi-Status\r\nConnection: close\r\n\r\n<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>");
                socket->flush(); socket->disconnectFromHost();
            });
        });
        auto account = [&](const char *path, const char *user) {
            return QJsonObject{{"kind", "caldav"}, {"user", user}, {"allowLocalNetwork", true},
                               {"url", QString("http://localhost:%1%2").arg(server.serverPort()).arg(path)}};
        };
        Island::Calendar::Sources sources;
        sources.configure(QJsonArray{account("/a/", "fixture"), account("/b/", "other")}, true, 5);
        // Each load is an event query followed by a reminder query.
        QTRY_VERIFY_WITH_TIMEOUT(reports.value("/a/") == 2 && reports.value("/b/") == 2, 3000);
        QList<int> reportsAtChange;
        connect(&sources, &Island::Calendar::Sources::changed, this, [&] { reportsAtChange.append(reports.value("/a/")); });
        QString stored;
        sources.credential("store", QString("http://localhost:%1/a/").arg(server.serverPort()), "fixture", "new-password",
                           [&](QString result) { stored = result; });
        QTRY_COMPARE_WITH_TIMEOUT(stored, "ok", 3000);
        QTRY_COMPARE_WITH_TIMEOUT(reports.value("/a/"), 4, 3000);
        QTRY_VERIFY_WITH_TIMEOUT(!reportsAtChange.isEmpty() && reportsAtChange.last() == 4, 3000);
        QTest::qWait(200);
        QCOMPARE(reports.value("/b/"), 2);
        QCOMPARE(secrets.stored(), QByteArray("new-password"));

        // A store while that account is loading reloads it once the running
        // load, which may have read the old password, has finished.
        holdA = true;
        sources.configure(QJsonArray{account("/a/", "fixture"), account("/b/", "other")}, true, 5);
        QTRY_COMPARE_WITH_TIMEOUT(reports.value("/a/"), 5, 3000);
        stored.clear();
        sources.credential("store", QString("http://localhost:%1/a/").arg(server.serverPort()), "fixture", "newer-password",
                           [&](QString result) { stored = result; });
        QTRY_COMPARE_WITH_TIMEOUT(stored, "ok", 3000);
        QTest::qWait(200);
        QCOMPARE(reports.value("/a/"), 5);
        holdA = false;
        for (const auto &socket : held) if (socket) {
            socket->write("HTTP/1.1 207 Multi-Status\r\nConnection: close\r\n\r\n<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>");
            socket->flush(); socket->disconnectFromHost();
        }
        // The running load finishes its reminder query, then the reload runs both.
        QTRY_COMPARE_WITH_TIMEOUT(reports.value("/a/"), 8, 3000);
        sources.configure({}, false, 5);
    }
};
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc == 2 && std::strcmp(argv[1], "--ui-window-fixture") == 0) {
        auto parsed = Island::Calendar::parse("BEGIN:VCALENDAR\n"
            "BEGIN:VEVENT\nUID:supported\nDTSTART:20260921T090000Z\n"
            "RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=MO;BYMONTH=9;COUNT=2\n"
            "SUMMARY:Scheduled series\nEND:VEVENT\n"
            "BEGIN:VEVENT\nUID:unsupported\nDTSTART:20260928T110000Z\n"
            "RRULE:FREQ=MONTHLY;BYSETPOS=1\n"
            "SUMMARY:Limited series\nEND:VEVENT\nEND:VCALENDAR\n");
        if (!parsed.error.isEmpty()) return 2;
        auto items = Island::Calendar::window(parsed.entries,
            QDateTime::fromString("2026-09-28T00:00:00Z", Qt::ISODate),
            QDateTime::fromString("2026-09-29T00:00:00Z", Qt::ISODate), "fixture");
        auto json = QJsonDocument(items).toJson(QJsonDocument::Compact);
        return std::fwrite(json.constData(), 1, size_t(json.size()), stdout) == size_t(json.size()) ? 0 : 3;
    }
    CalendarTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "calendar-test.moc"
