#pragma once
#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QPointer>
#include <QDBusPendingCallWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include "artwork-loader.h"

class RegistryTest;

namespace Island {
// A player's text, at most 4096 UTF-8 bytes, cut on a code-point boundary.
QString boundedText(const QVariant &value);
class MprisRegistry final : public QObject {
    Q_OBJECT
public:
    explicit MprisRegistry(const QDBusConnection &bus, QObject *parent = nullptr);
    void start();
    QVector<QJsonObject> endpoints() const;
    QString busEpoch() const { return epoch_; }
    void setGate(const QString &epoch, bool enabled);
    void command(const QJsonObject &request);
    void subscribe(const QJsonObject &token, bool visible, int cadence);
    void setRemoteArtworkEnabled(bool enabled);
    void selectArtwork(const QJsonObject &token, bool visible);
    void selectExternalArtwork(const QJsonObject &endpointToken, const QJsonObject &trackToken, const QUrl &url, bool visible);
    void retainArtwork(const QStringList &paths);
signals:
    void changed();
    void result(const QString &requestId, const QString &status);
    void progress(const QJsonObject &sample);
    void busLost();
    void externalArtworkReady(const QJsonObject &endpointToken, const QJsonObject &trackToken, const QString &path);
    // Every advertised artwork path is withdrawn, the browser endpoints' too:
    // the selection moved, was cancelled or hidden, so the cached files may
    // be evicted.
    void artworkCleared();
private slots:
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void propertiesChanged(const QString &interface, const QVariantMap &changed,
                           const QStringList &invalidated, const QDBusMessage &message);
    void seeked(qlonglong position, const QDBusMessage &message);
    void disconnected();
private:
    friend class ::RegistryTest;
    void clearArtworkPaths();
    struct Player {
        QString name, owner, generation;
        QVariantMap root, props;
        qint64 basePosition = 0, sampledAt = 0;
        qint64 lastResync = 0;
        quint64 trackGeneration = 0;
        QByteArray trackIdentity;
        QString artworkPath;
        quint64 rootRevision = 0, propertyRevision = 0;
        QPointer<QDBusPendingCallWatcher> rootCall, propertyCall;
        bool rootWanted = false, propertiesWanted = false;
        // The one introspection per owner: waiting for a read slot, or sent.
        bool accessWanted = false, accessSent = false;
        // From the player's introspection: whether Shuffle and LoopStatus
        // take writes. False until the reply says so.
        bool shuffleWritable = false, loopWritable = false;
    };
    QDBusConnection bus_;
    QHash<QString, Player> players_;
    QHash<QString, QPointer<QDBusPendingCallWatcher>> bootstrap_;
    QHash<QString, QString> pending_;
    QElapsedTimer clock_;
    QTimer progressTimer_;
    ArtworkLoader artwork_;
    QString epoch_, admissionEpoch_;
    bool enabled_ = false, started_ = false;
    quint64 serial_ = 0;
    int activeReads_ = 0;
    QJsonObject subscribed_;
    QJsonObject artworkSelected_;
    QJsonObject externalArtworkEndpoint_, externalArtworkTrack_;
    QUrl externalArtworkUrl_;
    QString artworkGeneration_;
    // Remote consent governs network fetches only; a player's local cover
    // file (artworkLocal_) loads without it.
    bool remoteArtworkEnabled_ = false, artworkVisible_ = false, artworkLocal_ = false;
    bool externalArtwork_ = false;
    void adopt(const QString &name, const QString &owner);
    void readProperties(const QString &name, const QString &owner, bool root);
    void readAccess(const QString &name, const QString &owner);
    void drainReads();
    void update(Player &player, const QVariantMap &properties);
    QJsonObject token(const Player &player) const;
    QJsonObject trackToken(const Player &player) const;
    QJsonObject wire(const Player &player) const;
    Player *resolve(const QJsonObject &token);
    double position(const Player &player) const;
    void tick();
    void reconcileArtwork();
};
}
