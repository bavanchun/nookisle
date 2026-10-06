#pragma once
#include <QObject>
#include <QJsonObject>
#include <QHash>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QTimer>
#include <QUrl>

namespace Island {
class BrowserRegistry final : public QObject {
    Q_OBJECT
public:
    explicit BrowserRegistry(QString busEpoch, QObject *parent = nullptr);
    ~BrowserRegistry() override;
    bool start(const QString &runtime, const QString &sessionHash);
    QVector<QJsonObject> endpoints() const;
    void setGate(const QString &epoch, bool enabled);
    void command(const QJsonObject &request);
    void subscribe(const QJsonObject &token, bool visible, int cadence);
    QUrl artworkUrl(const QJsonObject &token) const;
    void setArtwork(const QJsonObject &token, const QJsonObject &track, const QString &path);
    void clearArtwork();
signals:
    void changed();
    void result(const QString &requestId, const QString &status);
    void progress(const QJsonObject &sample);
private:
    struct Pending { QJsonObject token; QString gate; QPointer<QTimer> timer; };
    QLocalServer server_;
    QPointer<QLocalSocket> peer_;
    QTimer handshake_;
    QByteArray input_;
    QString busEpoch_, session_, secret_, directory_, authPath_, gate_;
    bool authenticated_ = false, enabled_ = false;
    QHash<QString, QJsonObject> endpoints_;
    QHash<QString, QString> artworkUrls_;
    QHash<QString, Pending> pending_;
    QJsonObject subscribed_;
    void receive();
    void message(const QJsonObject &frame);
    bool send(QJsonObject frame);
    void drop();
    QString key(const QJsonObject &token) const;
    QJsonObject resolve(const QJsonObject &token) const;
};
}
