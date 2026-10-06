#pragma once
#include "calendar-sources.h"
#include <QJsonObject>

namespace Island::Calendar {
class Service : public QObject {
    Q_OBJECT
public:
    explicit Service(QObject *parent = nullptr);
    void handle(const QJsonObject &message, const std::function<void(QJsonObject)> &reply);
signals:
    void changed();
private:
    Sources sources_;
};
}
