#pragma once
#include "artwork-fetch.h"
#include "image-limits.h"
#include <QByteArray>
#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QHash>
#include <QSize>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <QUrl>

class ArtworkLoaderTest;
class ArtworkNetworkTest;
namespace Island {
// The size a PNG declares in its IHDR header; empty when it is not a PNG.
// The helper checks its children's output with this, never decoding pixels.
QSize pngSize(const QByteArray &png);
// The same for artwork decoder output: empty unless at most 256 px a side.
QSize decodedPngSize(const QByteArray &png);
bool validArtworkUrl(const QUrl &url);
// A local cover file uses the decoder child without starting a network fetch.
bool localArtworkUrl(const QUrl &url);
// Each helper's artwork cache is `nookisle-art-<session>-XXXXXX` under
// the runtime directory, tagged with the D-Bus session its lease guards.
// The lease holder removes only what earlier helpers of its own session left
// behind when they were killed: holding the lease proves none of them runs.
// It never touches another session's cache, the untagged
// `nookisle-art-XXXXXX` directories of older builds (their helper may
// still run under another session), or anything but a real directory the
// user owns. Returns how many directories it removed.
void setArtworkSession(const QString &session);
int sweepStaleArtworkDirectories(const QString &runtime, const QString &session);

class ArtworkLoader final : public QObject {
    Q_OBJECT
public:
    explicit ArtworkLoader(QObject *parent = nullptr, const QString &decoderPath = {}, const QString &fetchPath = {});
    ~ArtworkLoader() override;
    void request(const QUrl &url, const QString &generation);
    void cancel();
    void retain(const QStringList &paths);
    void clear();
    bool busy() const { return !generation_.isEmpty(); }
signals:
    void ready(const QString &generation, const QString &path);
    void failed(const QString &generation, const QString &code);
private:
    friend class ::ArtworkLoaderTest;
    friend class ::ArtworkNetworkTest;
    struct Entry {
        QString name, path;
        // The published image's pixel footprint (width x height x 4), counted
        // against CacheLimit; the helper itself never holds those pixels.
        qint64 pixelBytes = 0;
        qint64 used = 0, released = 0, bytes = 0;
        bool referenced = false;
    };
    struct LocalReadResult {
        enum class Status { Success, FileError, ReadError, MimeError };
        Status status = Status::ReadError;
        QByteArray bytes;
        QByteArray mime;
    };
    QHash<QByteArray, Entry> cache_;
    // The fetch child (see ArtworkFetch) and the decoder child.
    QPointer<QProcess> fetch_, decoder_;
    QPointer<QFutureWatcher<LocalReadResult>> localWatcher_;
    QTimer deadline_, expiry_;
    QElapsedTimer clock_, elapsed_;
    QByteArray fetched_, cacheKey_, decoded_;
    QString generation_, directory_, decoderPath_, fetchPath_;
    // Extra fetch-child arguments; only the isolated network tests set them.
    QStringList fetchArguments_;
    QUrl url_;
    quint64 serial_ = 0;
    int directoryFd_ = -1;
    bool waitingForDecoder_ = false;
    void startFetch();
    void finishFetch(bool exited);
    void fail(const QString &code);
    void stopTransport();
    void readLocal();
    static LocalReadResult readLocalCoverFile(const QString &localPath);
    void publish(const QByteArray &bytes, const QByteArray &mime, bool local = false);
    void publishImage(const QByteArray &encoded, const QSize &size);
    bool ensureDirectory();
    void evict(bool makeRoom = false);
    void removeEntry(const QByteArray &key);
};
}
