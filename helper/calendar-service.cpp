#include "calendar-service.h"
#include <QDate>
#include <QTimeZone>

namespace Island::Calendar {
Service::Service(QObject *parent) : QObject(parent) {
    connect(&sources_, &Sources::changed, this, &Service::changed);
}

void Service::handle(const QJsonObject &message, const std::function<void(QJsonObject)> &reply) {
    QString type = message.value("type").toString();
    QString id = message.value("requestId").toString();
    if (id.isEmpty() || id.size() > 128) { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "invalid-request"}}); return; }
    if (type == "calendarConfigure") {
        if (!message.value("enabled").isBool() || !message.value("sources").isArray()) { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "invalid-request"}}); return; }
        sources_.configure(message.value("sources").toArray(), message.value("enabled").toBool(), message.value("refreshMinutes").toInt(15));
        reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "ok"}});
    } else if (type == "calendarWindow") {
        QDate today = QDate::currentDate();
        QTimeZone zone = QTimeZone::systemTimeZone();
        QDateTime from(today.addDays(-7), QTime(0, 0), zone);
        QDateTime until(today.addDays(15), QTime(0, 0), zone);
        auto page = sources_.page(from, until, message.value("offset").toInt());
        page.insert("type", "calendarWindowResult"); page.insert("requestId", id);
        reply(page);
    } else if (type == "calendarSetCompleted") {
        if (!message.value("completed").isBool()) { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "invalid-request"}}); return; }
        sources_.setCompleted(message.value("sourceId").toString(), message.value("uid").toString(), message.value("completed").toBool(),
            [reply, id](QString status) { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", status}}); });
    } else if (type == "calendarTest") {
        sources_.test(message.value("sourceId").toString(), [reply, id](QString error) {
            reply({{"type", "calendarResult"}, {"requestId", id}, {"ok", error.isEmpty()}, {"error", error},
                   {"status", error.isEmpty() ? QString("ok") : error}});
        });
    } else if (type == "calendarCredential") {
        QString action = message.value("action").toString();
        if (action != "store" && action != "clear") { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "invalid-request"}}); return; }
        QString url = message.value("url").toString(), user = message.value("user").toString();
        if (url.size() > 2048 || user.size() > 256 || url.isEmpty() || user.isEmpty()) { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "invalid-request"}}); return; }
        sources_.credential(action, url, user, message.value("password").toString().toUtf8(),
            [reply, id](QString status) { reply({{"type", "calendarResult"}, {"requestId", id}, {"status", status}}); });
    } else reply({{"type", "calendarResult"}, {"requestId", id}, {"status", "invalid-request"}});
}
}
