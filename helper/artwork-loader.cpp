#include "artwork-loader.h"
#include <QCryptographicHash>
#include <QCoreApplication>
#include <QtConcurrent>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QSet>
#include <QUuid>
#include <QtEndian>
#include <algorithm>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits>
#include <utility>

namespace {
constexpr qsizetype InputLimit = Island::ArtworkInputLimit;
// The fetch child's answer: one status line, then at most a whole body.
constexpr qsizetype FetchOutputLimit = Island::ArtworkInputLimit + 256;
constexpr qint64 CacheLimit = 4 * 1024 * 1024;
constexpr qint64 FileLimit = 8 * 1024 * 1024;
constexpr qint64 Ttl = 5 * 60 * 1000;
}

namespace Island {

bool localArtworkUrl(const QUrl &url) {
    return url.isValid() && url.scheme() == "file" && (url.host().isEmpty() || url.host() == "localhost")
        && url.userInfo().isEmpty() && !url.hasQuery() && url.toEncoded().size() <= 4096
        && url.toLocalFile().startsWith('/');
}

ArtworkLoader::ArtworkLoader(QObject *parent, const QString &decoderPath, const QString &fetchPath) : QObject(parent),
    decoderPath_(decoderPath.isEmpty() ? QCoreApplication::applicationDirPath() + "/nookisle-artwork-decoder" : decoderPath),
    fetchPath_(fetchPath.isEmpty() ? QCoreApplication::applicationDirPath() + "/nookisle-artwork-fetch" : fetchPath) {
    clock_.start();
    deadline_.setSingleShot(true);
    deadline_.setTimerType(Qt::PreciseTimer);
    deadline_.setInterval(5000);
    connect(&deadline_, &QTimer::timeout, this, [this] { fail("art-timeout"); });
    expiry_.setSingleShot(true);
    expiry_.setTimerType(Qt::PreciseTimer);
    connect(&expiry_, &QTimer::timeout, this, [this] { evict(); });
}
ArtworkLoader::~ArtworkLoader() {
    clear();
    if (directoryFd_ >= 0) ::close(directoryFd_);
    if (!directory_.isEmpty()) ::rmdir(QFile::encodeName(directory_).constData());
}
void ArtworkLoader::stopTransport() {
    if (auto *process = fetch_.data()) {
        fetch_ = nullptr;
        process->disconnect(this);
        if (process->state() == QProcess::NotRunning) process->deleteLater();
        else {
            connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), process, &QObject::deleteLater);
            process->kill();
        }
    }
    if (localWatcher_) {
        localWatcher_->disconnect(this);
        localWatcher_->deleteLater();
        localWatcher_ = nullptr;
    }
    fetched_.clear();
}
// The HTTPS fetch runs in its own short-lived child (ArtworkFetch), so the
// TLS stack and its certificate store never stay resident in the helper.
void ArtworkLoader::startFetch() {
    auto *process = new QProcess(this);
    fetch_ = process;
    fetched_.clear();
    process->setProgram(fetchPath_);
    process->setArguments(QStringList{QString::fromLatin1(url_.toEncoded())} + fetchArguments_);
    process->setProcessChannelMode(QProcess::SeparateChannels);
    process->setStandardInputFile(QProcess::nullDevice());
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process] {
        if (fetch_ != process) return;
        fetched_ += process->read(FetchOutputLimit + 1 - fetched_.size());
        if (fetched_.size() > FetchOutputLimit) fail("art-byte-limit");
    });
    connect(process, &QProcess::readyReadStandardError, this, [process] { process->readAllStandardError(); });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError) {
        if (fetch_ == process && process->state() == QProcess::NotRunning) finishFetch(false);
    });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this, process](int code, QProcess::ExitStatus status) {
        if (fetch_ != process) return;
        fetched_ += process->read(FetchOutputLimit + 1 - fetched_.size());
        finishFetch(code == 0 && status == QProcess::NormalExit);
    });
    process->start();
}
void ArtworkLoader::finishFetch(bool exited) {
    auto *process = fetch_.data();
    fetch_ = nullptr;
    if (process) { process->disconnect(this); process->deleteLater(); }
    const auto output = std::exchange(fetched_, {});
    const auto newline = output.indexOf('\n');
    if (!exited || newline < 0 || output.size() > FetchOutputLimit) { fail("art-fetch"); return; }
    const auto status = output.left(newline).split(' ');
    if (status.size() == 2 && status[0] == "error" && status[1].startsWith("art-")) { fail(QString::fromLatin1(status[1])); return; }
    if (status.size() != 2 || status[0] != "ok" || (status[1] != "image/png" && status[1] != "image/jpeg")) { fail("art-fetch"); return; }
    publish(output.mid(newline + 1), status[1]);
}
void ArtworkLoader::cancel() {
    ++serial_;
    waitingForDecoder_ = false;
    stopTransport();
    deadline_.stop();
    if (decoder_) {
        decoder_->disconnect(this);
        decoder_->kill();
        // Retain one process slot until the OS reaps the old child. A new
        // request reports busy instead of creating overlapping decode jobs.
        auto *old = decoder_.data();
        connect(old, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, old] {
            if (decoder_ == old) decoder_ = nullptr;
            old->deleteLater();
            if (waitingForDecoder_ && busy()) {
                waitingForDecoder_ = false;
                if (localArtworkUrl(url_)) readLocal();
                else startFetch();
            }
        });
        if (old->state() == QProcess::NotRunning) { decoder_ = nullptr; old->deleteLater(); }
    }
    decoded_.clear();
    generation_.clear();
    url_ = QUrl();
}
void ArtworkLoader::fail(const QString &code) {
    const auto generation = generation_;
    cancel();
    if (!generation.isEmpty()) emit failed(generation, code);
}
void ArtworkLoader::request(const QUrl &url, const QString &generation) {
    cancel();
    if (generation.isEmpty()) return;
    generation_ = generation;
    const bool local = localArtworkUrl(url);
    if (!local && !validArtworkUrl(url)) { fail("art-url-policy"); return; }
    url_ = url.adjusted(QUrl::RemoveFragment);
    QByteArray identity = url_.toEncoded();
    // Players can rewrite the same cover path for each track.
    if (local) {
        struct stat st {};
        if (::stat(QFile::encodeName(url_.toLocalFile()).constData(), &st)) { fail("art-local-read"); return; }
        if (!S_ISREG(st.st_mode)) { fail("art-local-file"); return; }
        identity += '\n' + QByteArray::number(qint64(st.st_size)) + ':' + QByteArray::number(qint64(st.st_mtim.tv_sec))
            + '.' + QByteArray::number(qint64(st.st_mtim.tv_nsec));
    }
    cacheKey_ = QCryptographicHash::hash(identity, QCryptographicHash::Sha256);
    evict();
    auto it = cache_.find(cacheKey_);
    if (it != cache_.end()) {
        it->used = clock_.elapsed();
        it->released = it->used;
        const auto path = it->path;
        cancel();
        emit ready(generation, path);
        return;
    }
    elapsed_.start();
    deadline_.start();
    // Cancellation can take one event-loop turn to reap the child. Keep only
    // this newest request while waiting, under the same total job deadline.
    if (decoder_) { waitingForDecoder_ = true; return; }
    if (local) readLocal();
    else startFetch();
}
ArtworkLoader::LocalReadResult ArtworkLoader::readLocalCoverFile(const QString &localPath) {
    LocalReadResult result;
    const auto path = QFile::encodeName(localPath);
    struct stat preStat {};
    if (::stat(path.constData(), &preStat)) {
        result.status = LocalReadResult::Status::ReadError;
        return result;
    }
    if (!S_ISREG(preStat.st_mode) || preStat.st_size <= 0 || preStat.st_size > Island::ThumbnailInputLimit) {
        result.status = LocalReadResult::Status::FileError;
        return result;
    }
    const int fd = ::open(path.constData(), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOCTTY | O_NOFOLLOW);
    if (fd < 0) {
        result.status = LocalReadResult::Status::ReadError;
        return result;
    }
    struct stat st {};
    if (::fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > Island::ThumbnailInputLimit) {
        ::close(fd);
        result.status = LocalReadResult::Status::FileError;
        return result;
    }
    QByteArray bytes(qsizetype(st.st_size), Qt::Uninitialized);
    qsizetype done = 0;
    while (done < bytes.size()) {
        const auto count = ::read(fd, bytes.data() + done, bytes.size() - done);
        if (count <= 0) break;
        done += count;
    }
    ::close(fd);
    if (done != bytes.size()) {
        result.status = LocalReadResult::Status::ReadError;
        return result;
    }
    const QByteArray mime = bytes.startsWith(QByteArray::fromHex("89504e470d0a1a0a")) ? "image/png"
        : bytes.startsWith(QByteArray::fromHex("ffd8ff")) ? "image/jpeg" : QByteArray();
    if (mime.isEmpty()) {
        result.status = LocalReadResult::Status::MimeError;
        return result;
    }
    result.status = LocalReadResult::Status::Success;
    result.bytes = std::move(bytes);
    result.mime = mime;
    return result;
}
// A regular file only, bounded before any byte is read. Sniff its bytes
// in a worker thread instead of blocking the main thread, then decode in the isolated child.
void ArtworkLoader::readLocal() {
    stopTransport();
    const auto path = url_.toLocalFile();
    const auto currentSerial = serial_;
    auto *watcher = new QFutureWatcher<LocalReadResult>(this);
    localWatcher_ = watcher;
    connect(watcher, &QFutureWatcher<LocalReadResult>::finished, this, [this, watcher, currentSerial] {
        const auto result = watcher->result();
        watcher->deleteLater();
        if (localWatcher_ == watcher) localWatcher_ = nullptr;
        if (serial_ != currentSerial || !busy()) return;
        switch (result.status) {
        case LocalReadResult::Status::FileError:
            fail("art-local-file");
            break;
        case LocalReadResult::Status::ReadError:
            fail("art-local-read");
            break;
        case LocalReadResult::Status::MimeError:
            fail("art-mime");
            break;
        case LocalReadResult::Status::Success:
            publish(result.bytes, result.mime, true);
            break;
        }
    });
    watcher->setFuture(QtConcurrent::run(&ArtworkLoader::readLocalCoverFile, path));
}
namespace {
QString artworkSession;
// A direct, real directory the user owns: its plain files are unlinked, and
// it is removed only once empty. Nothing is followed through a link.
bool removeCacheDirectory(const QString &path) {
    const auto bytes = QFile::encodeName(path);
    struct stat st {};
    if (::lstat(bytes.constData(), &st) || !S_ISDIR(st.st_mode) || st.st_uid != ::getuid()) return false;
    const int fd = ::open(bytes.constData(), O_DIRECTORY | O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return false;
    const auto names = QDir(path).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
    for (const auto &name : names) {
        const auto entry = QFile::encodeName(name);
        struct stat file {};
        if (!::fstatat(fd, entry.constData(), &file, AT_SYMLINK_NOFOLLOW) && !S_ISDIR(file.st_mode))
            ::unlinkat(fd, entry.constData(), 0);
    }
    ::close(fd);
    return ::rmdir(bytes.constData()) == 0;
}
}
void setArtworkSession(const QString &session) { artworkSession = session; }
// Only this session's tagged caches: the caller holds the session's lease,
// so no live helper owns them. An untagged cache from an older build names no
// session, and its helper may still run under another one; it is left for the
// runtime directory's own cleanup at logout.
int sweepStaleArtworkDirectories(const QString &runtime, const QString &session) {
    if (session.isEmpty()) return 0;
    const QString tagged = "nookisle-art-" + session + "-";
    int removed = 0;
    const auto names = QDir(runtime).entryList({tagged + "*"}, QDir::AllEntries | QDir::Hidden | QDir::System);
    for (const auto &name : names)
        removed += removeCacheDirectory(runtime + '/' + name) ? 1 : 0;
    return removed;
}
bool ArtworkLoader::ensureDirectory() {
    if (directoryFd_ >= 0) return true;
    const auto runtime = QFile::encodeName(qEnvironmentVariable("XDG_RUNTIME_DIR"));
    struct stat st {};
    if (runtime.isEmpty() || ::lstat(runtime.constData(), &st) || !S_ISDIR(st.st_mode)
        || st.st_uid != ::getuid() || (st.st_mode & 0077)) return false;
    QByteArray path = runtime + "/nookisle-art-" + (artworkSession.isEmpty() ? QByteArray() : artworkSession.toLatin1() + '-') + "XXXXXX";
    if (!::mkdtemp(path.data())) return false;
    directory_ = QFile::decodeName(path);
    directoryFd_ = ::open(path.constData(), O_DIRECTORY | O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    return directoryFd_ >= 0;
}
QSize pngSize(const QByteArray &png) {
    // Signature, then IHDR: length, type, width and height, big-endian.
    if (png.size() < 33 || !png.startsWith(QByteArray::fromHex("89504e470d0a1a0a")) || png.mid(12, 4) != "IHDR") return {};
    const auto *data = reinterpret_cast<const uchar *>(png.constData());
    const quint32 width = qFromBigEndian<quint32>(data + 16), height = qFromBigEndian<quint32>(data + 20);
    if (!width || !height || width > 0x7fffffff || height > 0x7fffffff) return {};
    return QSize(int(width), int(height));
}
QSize decodedPngSize(const QByteArray &png) {
    const auto size = pngSize(png);
    return size.width() <= 256 && size.height() <= 256 ? size : QSize();
}
void ArtworkLoader::publish(const QByteArray &bytes, const QByteArray &mime, bool local) {
    if (bytes.size() > (local ? ThumbnailInputLimit : InputLimit) || decoder_) { fail("art-decoder-busy"); return; }
    auto *process = new QProcess(this);
    decoder_ = process;
    decoded_.clear();
    process->setProgram(decoderPath_);
    process->setArguments(local ? QStringList{QString::fromLatin1(mime), "--local"}
                                : QStringList{QString::fromLatin1(mime)});
    process->setProcessChannelMode(QProcess::SeparateChannels);
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process] {
        if (decoder_ != process) return;
        decoded_ += process->read(512 * 1024 + 1 - decoded_.size());
        if (decoded_.size() > 512 * 1024) fail("art-output-limit");
    });
    connect(process, &QProcess::readyReadStandardError, this, [process] { process->readAllStandardError(); });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError) {
        if (decoder_ == process) fail("art-decoder");
    });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this, process](int code, QProcess::ExitStatus status) {
        if (decoder_ != process) return;
        decoded_ += process->read(512 * 1024 + 1 - decoded_.size());
        decoder_ = nullptr;
        process->deleteLater();
        if (code || status != QProcess::NormalExit || decoded_.size() > 512 * 1024) { fail("art-decode"); return; }
        // This is the bounded, metadata-free PNG our own decoder produced,
        // never the original remote image. It is published as it is: the
        // helper checks its header and never decodes or holds its pixels.
        const auto size = decodedPngSize(decoded_);
        if (size.isEmpty()) { fail("art-decoder-output"); return; }
        const auto encoded = std::exchange(decoded_, {});
        publishImage(encoded, size);
    });
    process->start();
    process->write(bytes);
    process->closeWriteChannel();
}
void ArtworkLoader::publishImage(const QByteArray &encoded, const QSize &size) {
    if (elapsed_.isValid() && elapsed_.elapsed() >= 5000) { fail("art-timeout"); return; }
    if (!ensureDirectory()) { fail("art-runtime"); return; }
    evict(true);
    qint64 memory = 0, files = 0;
    const qint64 pixels = qint64(size.width()) * size.height() * 4;
    for (const auto &entry : cache_) { memory += entry.pixelBytes; files += entry.bytes; }
    if (cache_.size() >= 8 || memory + pixels > CacheLimit) { fail("art-cache-limit"); return; }
    if (encoded.size() > 512 * 1024 || files + encoded.size() > FileLimit) { fail("art-output-limit"); return; }
    const auto name = QUuid::createUuid().toString(QUuid::WithoutBraces) + ".png";
    const auto temporary = QFile::encodeName(name + ".tmp"), finalName = QFile::encodeName(name);
    const int fd = ::openat(directoryFd_, temporary.constData(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) { fail("art-write"); return; }
    qsizetype written = 0;
    while (written < encoded.size()) {
        const auto count = ::write(fd, encoded.constData() + written, encoded.size() - written);
        if (count <= 0) break;
        written += count;
    }
    ::close(fd);
    if (written != encoded.size() || ::renameat(directoryFd_, temporary.constData(), directoryFd_, finalName.constData())) {
        ::unlinkat(directoryFd_, temporary.constData(), 0); fail("art-write"); return;
    }
    const auto path = QUrl::fromLocalFile(directory_ + '/' + name).toString();
    cache_.insert(cacheKey_, Entry{name, path, pixels, clock_.elapsed(), clock_.elapsed(), encoded.size(), false});
    evict();
    const auto generation = generation_;
    cancel();
    emit ready(generation, path);
}
void ArtworkLoader::removeEntry(const QByteArray &key) {
    auto it = cache_.find(key);
    if (it == cache_.end()) return;
    if (directoryFd_ >= 0) ::unlinkat(directoryFd_, QFile::encodeName(it->name).constData(), 0);
    cache_.erase(it);
}
void ArtworkLoader::evict(bool makeRoom) {
    const auto keys = cache_.keys();
    for (const auto &key : keys) if (!cache_[key].referenced && clock_.elapsed() - cache_[key].released >= Ttl) removeEntry(key);
    if (makeRoom && cache_.size() >= 8) {
        QByteArray oldest;
        qint64 used = std::numeric_limits<qint64>::max();
        for (auto it = cache_.cbegin(); it != cache_.cend(); ++it)
            if (!it->referenced && it->used < used) { oldest = it.key(); used = it->used; }
        if (!oldest.isEmpty()) removeEntry(oldest);
    }
    qint64 next = std::numeric_limits<qint64>::max();
    for (const auto &entry : cache_)
        if (!entry.referenced) next = std::min(next, entry.released + Ttl - clock_.elapsed());
    if (next == std::numeric_limits<qint64>::max()) expiry_.stop();
    else expiry_.start(int(std::max<qint64>(1, next)));
}
void ArtworkLoader::retain(const QStringList &paths) {
    // Unknown paths never authorize filesystem access. The UI may retain only
    // the two images participating in its current transition.
    const QSet<QString> retained(paths.cbegin(), paths.cbegin() + std::min<qsizetype>(2, paths.size()));
    for (auto &entry : cache_) {
        const bool referenced = retained.contains(entry.path);
        if (entry.referenced && !referenced) entry.released = clock_.elapsed();
        entry.referenced = referenced;
        if (referenced) entry.used = clock_.elapsed();
    }
    evict();
}
void ArtworkLoader::clear() {
    cancel();
    const auto keys = cache_.keys();
    for (const auto &key : keys) removeEntry(key);
    expiry_.stop();
}
}
