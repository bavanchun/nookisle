#include "thumbnail-cache.h"
#include "artwork-loader.h"
#include <QCoreApplication>
#include <QFile>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace {
constexpr int DeadlineMs = 10000;
constexpr qsizetype OutputLimit = 512 * 1024;

QString defaultCacheRoot() {
    QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
    if (!cache.startsWith('/')) {
        const QString home = qEnvironmentVariable("HOME");
        cache = home.startsWith('/') ? home + "/.cache" : QString();
    }
    return cache.isEmpty() ? QString() : cache + "/thumbnails";
}
// A private directory we own, created if missing. Never follows a link.
bool ensurePrivateDirectory(const QString &path) {
    const auto bytes = QFile::encodeName(path);
    if (::mkdir(bytes.constData(), 0700) && errno != EEXIST) return false;
    struct stat st {};
    return !::lstat(bytes.constData(), &st) && S_ISDIR(st.st_mode) && st.st_uid == ::getuid();
}
QByteArray sniffMime(const QByteArray &bytes) {
    if (bytes.startsWith(QByteArray::fromHex("89504e470d0a1a0a"))) return "image/png";
    if (bytes.startsWith(QByteArray::fromHex("ffd8ff"))) return "image/jpeg";
    return {};
}
}

namespace Island {
ThumbnailService::ThumbnailService(QObject *parent, const QString &decoderPath, const QString &cacheRoot)
    : QObject(parent),
      decoderPath_(decoderPath.isEmpty() ? QCoreApplication::applicationDirPath() + "/nookisle-artwork-decoder" : decoderPath),
      root_(cacheRoot.isEmpty() ? defaultCacheRoot() : cacheRoot) {
    deadline_.setSingleShot(true);
    deadline_.setInterval(DeadlineMs);
    connect(&deadline_, &QTimer::timeout, this, [this] { finish("failed"); });
}
ThumbnailService::~ThumbnailService() {
    if (decoder_) {
        decoder_->disconnect(this);
        decoder_->kill();
        decoder_->waitForFinished(1000);
    }
}
void ThumbnailService::request(const QString &id, const QString &uri, const QString &name) {
    static const QRegularExpression cacheName("^[0-9a-f]{32}\\.png$");
    const QUrl url(uri, QUrl::StrictMode);
    if (!cacheName.match(name).hasMatch() || !uri.startsWith("file:///") || uri.size() > 4096
        || uri.contains(QRegularExpression("[\\x00-\\x1f\\x7f]")) || !url.isValid() || !url.isLocalFile()) {
        emit finished(id, "invalid", {});
        return;
    }
    if (queue_.size() >= QueueLimit) { emit finished(id, "busy", {}); return; }
    queue_.enqueue({id, uri, name, url.toLocalFile()});
    if (!active_) next();
}
void ThumbnailService::next() {
    while (!active_ && !queue_.isEmpty()) {
        current_ = queue_.dequeue();
        active_ = true;
        const auto path = QFile::encodeName(current_.path);
        // Checked before opening too, so a device node or FIFO is never opened.
        struct stat before {};
        if (::stat(path.constData(), &before) || !S_ISREG(before.st_mode)) { finish("unsupported"); continue; }
        const int fd = ::open(path.constData(), O_RDONLY | O_CLOEXEC | O_NOCTTY | O_NONBLOCK);
        struct stat st {};
        if (fd < 0 || ::fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > ThumbnailInputLimit) {
            if (fd >= 0) ::close(fd);
            finish("unsupported");
            continue;
        }
        mtime_ = st.st_mtim.tv_sec;
        sourceFd_ = fd;
        deadline_.start();
        const auto cached = cachedCandidate();
        if (cached.isEmpty()) { generate(); continue; }
        // A matching entry is used only as the child re-encodes it; anything
        // it rejects, or a key that does not match, regenerates from the file.
        decode({"image/png", "--cached-thumbnail", current_.uri, QString::number(mtime_)}, cached,
            [this](const QByteArray &png) {
            QString stored;
            if (!png.isEmpty() && store(png, &stored)) {
                finish("ready", stored);
                return;
            }
            generate();
        });
    }
}
// The checked descriptor becomes the child's standard input, so the file
// (up to ThumbnailInputLimit) streams from disk into the decoder and never
// through this process's memory or event loop.
void ThumbnailService::generate() {
    QByteArray magic(8, '\0');
    const auto count = sourceFd_ >= 0 ? ::pread(sourceFd_, magic.data(), magic.size(), 0) : -1;
    if (count < 0) { finish("failed"); return; }
    magic.truncate(count);
    const auto mime = sniffMime(magic);
    if (mime.isEmpty()) { finish("unsupported"); return; }
    decode({QString::fromLatin1(mime), "--thumbnail", current_.uri, QString::number(mtime_)}, {},
        [this](const QByteArray &png) {
        QString stored;
        if (!png.isEmpty() && store(png, &stored)) finish("ready", stored);
        else finish("failed");
    });
}
void ThumbnailService::decode(const QStringList &arguments, const QByteArray &input, std::function<void(QByteArray)> done) {
    auto *process = new QProcess(this);
    decoder_ = process;
    decoded_.clear();
    process->setProgram(decoderPath_);
    process->setArguments(arguments);
    process->setProcessChannelMode(QProcess::SeparateChannels);
    const int source = input.isNull() ? sourceFd_ : -1;
    if (source >= 0) {
        process->setStandardInputFile(QProcess::nullDevice());
        // Runs in the child between fork and exec: only async-signal-safe calls.
        process->setChildProcessModifier([source] {
            if (::lseek(source, 0, SEEK_SET) != 0 || ::dup2(source, STDIN_FILENO) < 0) ::_exit(127);
        });
    }
    auto settle = [this, process, done](bool ok) {
        if (decoder_ != process) return;
        decoder_ = nullptr;
        process->disconnect(this);
        if (process->state() == QProcess::NotRunning) process->deleteLater();
        else {
            connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), process, &QObject::deleteLater);
            process->kill();
        }
        // The child's finished PNG, keys included; only its header is read
        // here, to hold it to the 128 px thumbnail size.
        QByteArray png = std::exchange(decoded_, {});
        const auto size = pngSize(png);
        if (!ok || png.size() > OutputLimit || size.isEmpty() || size.width() > 128 || size.height() > 128) png.clear();
        done(png);
    };
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, settle] {
        if (decoder_ != process) return;
        decoded_ += process->read(OutputLimit + 1 - decoded_.size());
        if (decoded_.size() > OutputLimit) settle(false);
    });
    connect(process, &QProcess::readyReadStandardError, this, [process] { process->readAllStandardError(); });
    connect(process, &QProcess::errorOccurred, this, [process, settle](QProcess::ProcessError) {
        if (process->state() == QProcess::NotRunning) settle(false);
    });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this, process, settle](int code, QProcess::ExitStatus status) {
        if (decoder_ != process) return;
        decoded_ += process->read(OutputLimit + 1 - decoded_.size());
        settle(code == 0 && status == QProcess::NormalExit);
    });
    process->start();
    if (source >= 0) return;
    process->write(input);
    process->closeWriteChannel();
}
QByteArray ThumbnailService::cachedCandidate() const {
    for (const auto &size : {QStringLiteral("normal"), QStringLiteral("large")}) {
        const auto encoded = QFile::encodeName(root_ + "/" + size + "/" + current_.name);
        const int fd = ::open(encoded.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
        if (fd < 0) continue;
        struct stat st {};
        if (::fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > CachedThumbnailLimit) {
            ::close(fd);
            continue;
        }
        QFile file;
        QByteArray bytes;
        if (file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) bytes = file.read(CachedThumbnailLimit + 1);
        else ::close(fd);
        if (bytes.size() == st.st_size) return bytes;
    }
    return {};
}
void ThumbnailService::finish(const QString &status, const QString &path) {
    if (!active_) return;
    deadline_.stop();
    if (auto *process = decoder_.data()) {
        decoder_ = nullptr;
        process->disconnect(this);
        process->kill();
        connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), process, &QObject::deleteLater);
        if (process->state() == QProcess::NotRunning) process->deleteLater();
    }
    decoded_.clear();
    if (sourceFd_ >= 0) ::close(std::exchange(sourceFd_, -1));
    const auto id = current_.id;
    current_ = {};
    active_ = false;
    emit finished(id, status, path);
    // A queued job starts on the next turn, so a slot that re-enters request()
    // from finished() never recurses into next().
    if (!queue_.isEmpty()) QMetaObject::invokeMethod(this, [this] { next(); }, Qt::QueuedConnection);
}
bool ThumbnailService::store(const QByteArray &encoded, QString *path) {
    const auto directory = cacheDirectory();
    // The cache home itself may not exist yet on a fresh account.
    const auto home = root_.left(root_.lastIndexOf('/'));
    if (directory.isEmpty() || home.isEmpty() || (::mkdir(QFile::encodeName(home).constData(), 0700) && errno != EEXIST)
        || !ensurePrivateDirectory(root_) || !ensurePrivateDirectory(directory)) return false;
    if (encoded.size() > OutputLimit) return false;
    const auto finalPath = directory + "/" + current_.name;
    const auto temporary = QFile::encodeName(finalPath + "." + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".tmp");
    const int fd = ::open(temporary.constData(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return false;
    qsizetype written = 0;
    while (written < encoded.size()) {
        const auto count = ::write(fd, encoded.constData() + written, encoded.size() - written);
        if (count <= 0) break;
        written += count;
    }
    const bool complete = written == encoded.size();
    if (::close(fd) || !complete || ::rename(temporary.constData(), QFile::encodeName(finalPath).constData())) {
        ::unlink(temporary.constData());
        return false;
    }
    *path = finalPath;
    return true;
}
}
