#pragma once

#include "calendar-parser.h"
#include <QFileSystemWatcher>
#include <QHash>
#include <QHostAddress>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QProcess>
#include <QSet>
#include <QTimer>

namespace Island::Calendar {
// Loopback, RFC 1918, link-local, unspecified and IPv6 ULA addresses,
// including their IPv4-mapped forms.
bool isLocalAddress(const QHostAddress &address);
// A request to `url` connected to the checked `address`, keeping the host's
// identity: the Host header and the TLS peer name carry the real host name.
// HTTP/2 is off, because Qt's HTTP/2 sends `:authority` from the request URL
// (the pinned address) and drops a Host header.
QNetworkRequest pinnedRequest(const QUrl &url, const QHostAddress &address, qint64 timeoutMs);

struct Source {
    QString id, kind, path, url, user, color;
    bool allowLocalNetwork = false;
    QString error;
    // By UID: the CalDAV member URL and ETag, or the vdir file path and its
    // modification stamp when it was read.
    struct Member { QString url, etag; QByteArray raw; };
    QHash<QString, Member> members;
    QVector<Entry> entries;
    // Bumped by every local load; only the newest load's result is applied.
    quint64 loadSerial = 0;
};

// What one source load produced, built on a worker thread: reading and
// parsing never run on the helper's event loop, so IPC and media control
// stay responsive while a large calendar loads.
struct Loaded {
    QString error;
    QVector<Entry> entries;
    QHash<QString, Source::Member> members;
    // Local paths to watch once the result is applied.
    QStringList watch;
};

class Sources : public QObject {
    Q_OBJECT
public:
    explicit Sources(QObject *parent = nullptr);
    void configure(const QJsonArray &definitions, bool enabled, int refreshMinutes);
    QJsonObject page(const QDateTime &from, const QDateTime &until, int offset) const;
    void setCompleted(const QString &sourceId, const QString &uid, bool completed,
                      const std::function<void(QString)> &done);
    // Stores or clears a CalDAV password through secret-tool without
    // blocking; store writes the password to its standard input.
    void credential(const QString &verb, const QString &url, const QString &user,
                    const QByteArray &password, const std::function<void(QString)> &done);
    // Loads one source afresh and reports its error code, empty on success,
    // once that load completes; a test during a load waits for that load.
    void test(const QString &sourceId, const std::function<void(QString)> &done);
    // How long secret-tool may run, unlock prompt included; tests shorten it.
    void setSecretTimeout(int ms) { secretTimeoutMs_ = ms; }
    // Whether any source load (local read or remote fetch and parse) is in flight.
    bool loading() const { return !loading_.isEmpty(); }
    // How many times the window has been expanded; pages slice one expansion.
    quint64 windowBuilds() const { return windowBuilds_; }
signals:
    void changed();
private:
    void loadLocal(Source &source);
    // Runs work on the thread pool and apply on this thread afterwards,
    // unless this object is gone by then.
    void offload(std::function<Loaded()> work, std::function<void(const Loaded &)> apply);
    // Watches a path once, tracked in watched_ so a reload never copies the watch list.
    void watch(const QString &path);
    void refreshRemote(const QString &id);
    void refreshRemoteWithPassword(const QString &id, const QString &password);
    void completeLoad(const QString &id);
    void refetchAccount(const QString &url, const QString &user);
    void request(const QString &id, const QString &method, const QUrl &url, const QByteArray &body,
                 const QMap<QByteArray, QByteArray> &headers,
                 const std::function<void(QString, QByteArray, QByteArray)> &done, int redirects = 0,
                 qint64 deadline = 0);
    void secretTool(const QStringList &arguments, const QByteArray &input, bool lookup,
                    const std::function<void(QString, QByteArray)> &done);
    void lookupPassword(const QString &url, const QString &user,
                        const std::function<void(QString, QString)> &done);
    void buildWindow(const QDateTime &from, const QDateTime &until) const;
    QHash<QString, Source> sources_;
    QFileSystemWatcher watcher_;
    QSet<QString> watched_;
    QTimer reload_;
    QSet<QString> pendingReload_;
    QNetworkAccessManager network_;
    QTimer refresh_;
    bool enabled_ = false;
    int secretTimeoutMs_ = 60000;
    quint64 generation_ = 0;
    QSet<QNetworkReply *> replies_;
    QSet<QProcess *> lookups_;
    // Remote sources with a load in flight, and what waits for each load.
    QSet<QString> loading_;
    QHash<QString, QVector<std::function<void(QString)>>> loadWaiters_;
    struct WindowCache {
        bool valid = false;
        QDateTime from, until;
        QVector<QJsonObject> items;
        QVector<int> sizes;
        QSet<QString> limited;
        // Sources cut by the window's aggregate item or byte bound.
        QSet<QString> windowLimited;
    };
    mutable WindowCache cache_;
    mutable quint64 windowBuilds_ = 0;
};
}
