#pragma once

#include <QJsonObject>
#include <QObject>
#include <QQueue>
#include <QSocketNotifier>
#include <QVector>

namespace Island {
inline constexpr qsizetype FrameLimit = 64 * 1024;
inline constexpr qsizetype QueueLimit = 128 * 1024;
// Replaceable output (snapshot frames, progress) leaves this much of the queue
// free, so any one method result or acknowledgement, up to a whole frame such
// as a full calendar page, always fits behind it.
inline constexpr qsizetype ReplyReserve = FrameLimit;
inline constexpr qsizetype EntryLimit = 8 * 1024;
inline constexpr qsizetype SnapshotLimit = 512 * 1024;
inline constexpr int EndpointLimit = 64;

QByteArray encodeFrame(const QJsonObject &object);
// Mandatory fields are never truncated. An empty result means unrepresentable identity.
QJsonObject boundedEndpoint(QJsonObject endpoint);
bool validLoopStatus(const QJsonValue &value);
bool validSeekOffset(const QJsonValue &value);
QVector<QByteArray> snapshotFrames(const QVector<QJsonObject> &endpoints,
                                 const QString &connection, const QString &sequence,
                                 const QString &busEpoch);

class JsonLines final : public QObject {
    Q_OBJECT
public:
    explicit JsonLines(QObject *parent = nullptr);
    void feed(const QByteArray &bytes);
    bool failed() const { return failed_; }
signals:
    void message(const QJsonObject &object);
    void error(const QString &code);
private:
    QByteArray pending_;
    bool failed_ = false;
    void fail(const QString &code);
};

// Nonblocking stdio. Queue admission is bounded; caller resumes after drained().
class StdioChannel final : public QObject {
    Q_OBJECT
public:
    explicit StdioChannel(QObject *parent = nullptr);
    bool send(const QByteArray &frame, qsizetype reserveBytes = 0);
    qsizetype queuedBytes() const { return queue_.size(); }
signals:
    void message(const QJsonObject &object);
    void closed();
    void error(const QString &code);
    void drained();
private:
    JsonLines parser_;
    QSocketNotifier input_;
    QSocketNotifier output_;
    QByteArray queue_;
    bool closed_ = false;
    void readReady();
    void writeReady();
    void fail(const QString &code);
};
}
