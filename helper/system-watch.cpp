#include "system-watch.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QRegularExpression>
#include <QStandardPaths>
#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

namespace Island {
namespace {
const QString RecordingMarker = QStringLiteral("omarchy-screenrecord-filename");

QString readSmall(const QString &path, qint64 limit) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    return QString::fromUtf8(file.read(limit)).trimmed();
}
}

SystemWatch::Paths SystemWatch::Paths::live() {
    Paths paths;
    const auto runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty()) paths.transient = runtime + QStringLiteral("/systemd/transient");
    paths.screenshots = qEnvironmentVariable("OMARCHY_SCREENSHOT_DIR");
    if (paths.screenshots.isEmpty())
        paths.screenshots = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    paths.shellPid = getppid();
    paths.selfPid = getpid();
    paths.uid = getuid();
    return paths;
}

SystemWatch::SystemWatch(Paths paths, QObject *parent) : QObject(parent), paths_(std::move(paths)) {
    cameraScan_.setSingleShot(true);
    reminderNotice_.setSingleShot(true);
    connect(&cameraScan_, &QTimer::timeout, this, &SystemWatch::scanCamera);
    connect(&reminderNotice_, &QTimer::timeout, this, [this] {
        emit event({{"kind", "reminders"}});
    });
}

SystemWatch::~SystemWatch() {
    notifier_.reset();
    if (fd_ >= 0) ::close(fd_);
}

bool SystemWatch::isVideoDevice(const QString &name) {
    static const QRegularExpression pattern(QStringLiteral("^video[0-9]{1,3}$"));
    return pattern.match(name).hasMatch();
}

bool SystemWatch::isScreenshotName(const QString &name) {
    static const QRegularExpression pattern(QStringLiteral("^screenshot-[^/]{1,200}\\.png$"));
    return pattern.match(name).hasMatch();
}

bool SystemWatch::isReminderUnit(const QString &name) {
    static const QRegularExpression pattern(QStringLiteral("^omarchy-reminder-[0-9]{1,5}m-[0-9]{1,12}\\.timer$"));
    return pattern.match(name).hasMatch();
}

QStringList SystemWatch::cameraHolders(const QString &procRoot, const QStringList &devices,
                                       const QList<pid_t> &excluded, uid_t uid) {
    QStringList names;
    if (devices.isEmpty()) return names;
    const auto entries = QDir(procRoot).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto &entry : entries) {
        bool numeric = false;
        const pid_t pid = entry.toInt(&numeric);
        if (!numeric || excluded.contains(pid)) continue;
        const QString base = procRoot + '/' + entry;
        struct stat st {};
        if (::stat(QFile::encodeName(base).constData(), &st) || st.st_uid != uid) continue;
        const auto fds = QDir(base + QStringLiteral("/fd")).entryList(QDir::AllEntries | QDir::System | QDir::Hidden | QDir::NoDotAndDotDot);
        bool holds = false;
        for (const auto &fd : fds) {
            const auto target = QFile::symLinkTarget(base + QStringLiteral("/fd/") + fd);
            if (devices.contains(target)) { holds = true; break; }
        }
        if (!holds) continue;
        const auto comm = readSmall(base + QStringLiteral("/comm"), 64);
        if (comm.isEmpty() || comm == QStringLiteral("pipewire") || comm == QStringLiteral("wireplumber")) continue;
        if (!names.contains(comm)) names.append(comm.left(HolderNameLimit));
    }
    std::sort(names.begin(), names.end());
    return names.mid(0, HolderLimit);
}

bool SystemWatch::processRunning(const QString &procRoot, const QString &commPrefix, uid_t uid) {
    const auto entries = QDir(procRoot).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto &entry : entries) {
        bool numeric = false;
        entry.toInt(&numeric);
        if (!numeric) continue;
        const QString base = procRoot + '/' + entry;
        struct stat st {};
        if (::stat(QFile::encodeName(base).constData(), &st) || st.st_uid != uid) continue;
        if (readSmall(base + QStringLiteral("/comm"), 64).startsWith(commPrefix)) return true;
    }
    return false;
}

bool SystemWatch::configure(const QJsonObject &request) {
    static const char *flags[] = {"cameraDevices", "recording", "reminders", "screenshots"};
    for (const auto *flag : flags)
        if (request.contains(QLatin1String(flag)) && !request.value(QLatin1String(flag)).isBool()) return false;
    const auto dirValue = request.value("screenshotDir");
    if (!dirValue.isUndefined() && !dirValue.isString()) return false;
    const QString dirOverride = dirValue.toString();
    if (dirOverride.size() > PathLimit || (!dirOverride.isEmpty() && (!QDir::isAbsolutePath(dirOverride)
        || !QFileInfo(dirOverride).isDir())))
        return false;
    if (fd_ < 0) {
        fd_ = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (fd_ < 0) return false;
        notifier_ = std::make_unique<QSocketNotifier>(fd_, QSocketNotifier::Read);
        connect(notifier_.get(), &QSocketNotifier::activated, this, &SystemWatch::readEvents);
    }
    const bool camera = request.value("cameraDevices").toBool();
    const bool recording = request.value("recording").toBool();
    const bool reminders = request.value("reminders").toBool();
    const QString screenshots = request.value("screenshots").toBool()
        ? (dirOverride.isEmpty() ? paths_.screenshots : dirOverride) : QString();

    if (camera != camera_) {
        camera_ = camera;
        removeKind(Kind::VideoDevice);
        removeKind(Kind::Dev);
        holders_.clear();
        holdersSent_ = false;
        cameraScan_.stop();
        if (camera_) {
            addWatch(paths_.dev, IN_CREATE | IN_DELETE, Kind::Dev);
            watchVideoDevices();
            scanCamera();
        }
    }
    if (recording != recording_) {
        recording_ = recording;
        removeKind(Kind::Tmp);
        recordingState_ = {};
        if (recording_) {
            addWatch(paths_.tmp, IN_CLOSE_WRITE | IN_MOVED_TO | IN_DELETE | IN_MOVED_FROM, Kind::Tmp);
            readRecording(true);
        }
    }
    if (reminders != reminders_) {
        reminders_ = reminders;
        removeKind(Kind::Transient);
        reminderNotice_.stop();
        if (reminders_ && addWatch(paths_.transient, IN_CREATE | IN_DELETE | IN_MOVED_TO | IN_MOVED_FROM, Kind::Transient) < 0)
            emit event({{"kind", "reminders"}, {"unavailable", true}});
    }
    if (screenshots != screenshotDir_) {
        screenshotDir_ = screenshots;
        removeKind(Kind::Screenshots);
        if (!screenshotDir_.isEmpty()) addWatch(screenshotDir_, IN_CLOSE_WRITE | IN_MOVED_TO, Kind::Screenshots);
    }
    return true;
}

int SystemWatch::addWatch(const QString &path, uint32_t mask, Kind kind) {
    if (fd_ < 0 || path.isEmpty()) return -1;
    const int wd = inotify_add_watch(fd_, QFile::encodeName(path).constData(), mask);
    if (wd < 0) return -1;
    kinds_.insert(wd, kind);
    watchedPaths_.insert(wd, path);
    return wd;
}

void SystemWatch::removeWatch(int wd) {
    if (fd_ >= 0) inotify_rm_watch(fd_, wd);
    kinds_.remove(wd);
    watchedPaths_.remove(wd);
}

void SystemWatch::removeKind(Kind kind) {
    const auto descriptors = kinds_.keys(kind);
    for (int wd : descriptors) removeWatch(wd);
}

QStringList SystemWatch::videoDevices() const {
    QStringList devices;
    const auto names = QDir(paths_.dev).entryList(QDir::AllEntries | QDir::System | QDir::NoDotAndDotDot);
    for (const auto &name : names)
        if (isVideoDevice(name)) devices.append(paths_.dev + '/' + name);
    return devices;
}

void SystemWatch::watchVideoDevices() {
    removeKind(Kind::VideoDevice);
    for (const auto &device : videoDevices())
        addWatch(device, IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE, Kind::VideoDevice);
}

void SystemWatch::scanCamera() {
    if (!camera_) return;
    const auto next = cameraHolders(paths_.proc, videoDevices(), {paths_.shellPid, paths_.selfPid}, paths_.uid);
    if (holdersSent_ && next == holders_) return;
    holders_ = next;
    holdersSent_ = true;
    emit event({{"kind", "camera"}, {"holders", QJsonArray::fromStringList(holders_)}});
}

void SystemWatch::readRecording(bool atStart) {
    const QString marker = paths_.tmp + '/' + RecordingMarker;
    bool active = false;
    double startedAt = 0;
    QString path;

    const int fd = ::open(QFile::encodeName(marker).constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd >= 0) {
        struct stat st {};
        if (::fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == paths_.uid) {
            active = true;
            startedAt = double(qint64(st.st_mtim.tv_sec) * 1000 + (st.st_mtim.tv_nsec / 1000000));
            QByteArray bytes;
            bytes.resize(PathLimit);
            const ssize_t n = ::read(fd, bytes.data(), PathLimit);
            if (n > 0) {
                bytes.truncate(n);
                path = QString::fromUtf8(bytes).trimmed();
            }
        }
        ::close(fd);
    }

    // A marker left behind by a crash is stale: at start, a recording counts
    // only while the recorder runs.
    if (active && atStart) active = processRunning(paths_.proc, QStringLiteral("gpu-screen-reco"), paths_.uid);
    QJsonObject next{{"kind", "recording"}, {"active", active}};
    if (active) {
        next["startedAt"] = startedAt;
        next["path"] = path;
    } else if (recordingState_.value("active").toBool()) {
        // The saved file of the recording that just ended.
        next["path"] = recordingState_.value("path");
    }
    if (!atStart && next == recordingState_) return;
    recordingState_ = next;
    emit event(next);
}

void SystemWatch::noteScreenshot(const QString &path) {
    if (!screenshotWindow_.isValid() || screenshotWindow_.elapsed() >= 1000) {
        screenshotWindow_.start();
        screenshotCount_ = 0;
    }
    if (++screenshotCount_ > ScreenshotRateLimit || path.size() > PathLimit) return;
    emit event({{"kind", "screenshot"}, {"path", path}});
}

void SystemWatch::readEvents() {
    alignas(inotify_event) char buffer[16 * 1024];
    bool rewatch = false;
    for (;;) {
        const ssize_t length = ::read(fd_, buffer, sizeof buffer);
        if (length <= 0) break;
        for (char *cursor = buffer; cursor < buffer + length;) {
            const auto *item = reinterpret_cast<const inotify_event *>(cursor);
            cursor += sizeof(inotify_event) + item->len;
            const auto kind = kinds_.constFind(item->wd);
            if (item->mask & IN_IGNORED) { kinds_.remove(item->wd); watchedPaths_.remove(item->wd); continue; }
            if (kind == kinds_.constEnd()) continue;
            const QString name = item->len ? QFile::decodeName(item->name) : QString();
            switch (kind.value()) {
            case Kind::VideoDevice:
                cameraScan_.start(cameraDebounceMs);
                break;
            case Kind::Dev:
                if (isVideoDevice(name)) { rewatch = true; cameraScan_.start(cameraDebounceMs); }
                break;
            case Kind::Tmp:
                if (name == RecordingMarker) readRecording(false);
                break;
            case Kind::Screenshots:
                if (isScreenshotName(name)) noteScreenshot(watchedPaths_.value(item->wd) + '/' + name);
                break;
            case Kind::Transient:
                if (isReminderUnit(name)) reminderNotice_.start(reminderDebounceMs);
                break;
            }
        }
    }
    if (rewatch && camera_) watchVideoDevices();
}
}
