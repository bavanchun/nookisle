#pragma once
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQueue>
#include <QTimer>
#include <functional>

class ArtworkLoaderTest;
namespace Island {
// Freedesktop thumbnails for shelved local files. The caller names the cache
// entry (the MD5 of the URI, which QML computes with Qt.md5). Files are opened
// and checked here, but every image operation runs in the resource-limited
// decoder child: the shelved file streams to it as its standard input, and any
// existing cache entry (at most 1 MiB, read here) is re-encoded by it too,
// since other applications write that cache. The child also checks and writes
// Thumb::URI and Thumb::MTime; this process never decodes pixels. The child's 128 px result goes into the "normal"
// cache directory with Thumb::URI and Thumb::MTime, written to a private
// temporary file and renamed into place; only that file reaches the UI.
class ThumbnailService final : public QObject {
    Q_OBJECT
public:
    static constexpr int QueueLimit = 64;
    explicit ThumbnailService(QObject *parent = nullptr, const QString &decoderPath = {}, const QString &cacheRoot = {});
    ~ThumbnailService() override;
    // Answers every accepted id exactly once through finished().
    void request(const QString &id, const QString &uri, const QString &name);
    QString cacheDirectory() const { return root_.isEmpty() ? QString() : root_ + "/normal"; }
signals:
    // status is ready, unsupported, failed, busy or invalid; path is set only when ready.
    void finished(const QString &id, const QString &status, const QString &path);
private:
    friend class ::ArtworkLoaderTest;
    struct Job {
        QString id, uri, name, path;
    };
    QQueue<Job> queue_;
    Job current_;
    QPointer<QProcess> decoder_;
    QByteArray decoded_;
    qint64 mtime_ = 0;
    QTimer deadline_;
    QString decoderPath_, root_;
    bool active_ = false;
    int sourceFd_ = -1;
    void next();
    void finish(const QString &status, const QString &path = {});
    // The bytes of the first plausible cache entry (a regular file of at most
    // 1 MiB, never through a link), unparsed; empty for none.
    QByteArray cachedCandidate() const;
    void generate();
    // Runs the decoder child; done receives its finished PNG, or nothing.
    // A null input streams the open source file to the child instead.
    void decode(const QStringList &arguments, const QByteArray &input, std::function<void(QByteArray)> done);
    // Writes the child's PNG into the normal cache directory, atomically.
    bool store(const QByteArray &encoded, QString *path);
};
}
