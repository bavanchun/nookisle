#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QSocketNotifier>
#include <QStringList>
#include <QTimer>
#include <memory>
#include <sys/types.h>

namespace Island {

// Local desktop signals for the island's activities and privacy indicators,
// from one inotify descriptor inside the helper, so no watcher process runs
// beside it. Every watch is off until the Service asks for it:
//  - camera: open and close on /dev/videoN (and hotplug in /dev) trigger one
//    debounced scan of /proc/*/fd for the processes holding a camera;
//  - recording: Omarchy writes /tmp/omarchy-screenrecord-filename once a
//    recording produces output and deletes it after saving;
//  - screenshots: Omarchy's screenshot-*.png files, closed after writing;
//  - reminders: omarchy-reminder's transient systemd timer units.
// Nothing is polled, and nothing leaves the machine.
class SystemWatch final : public QObject {
    Q_OBJECT
public:
    struct Paths {
        QString dev = QStringLiteral("/dev");
        QString proc = QStringLiteral("/proc");
        QString tmp = QStringLiteral("/tmp");
        QString transient;
        // Resolved from OMARCHY_SCREENSHOT_DIR, then the Pictures folder.
        QString screenshots;
        pid_t shellPid = 0;
        pid_t selfPid = 0;
        uid_t uid = 0;
        static Paths live();
    };
    static constexpr int HolderLimit = 16;
    static constexpr int HolderNameLimit = 64;
    static constexpr int PathLimit = 4096;
    static constexpr int ScreenshotRateLimit = 20;

    explicit SystemWatch(Paths paths, QObject *parent = nullptr);
    ~SystemWatch() override;
    // { cameraDevices, recording, reminders, screenshots: bool,
    //   screenshotDir: string }. Absent fields are off. False on a malformed
    // request, which changes nothing.
    bool configure(const QJsonObject &request);
    int cameraDebounceMs = 300;
    int reminderDebounceMs = 100;

    static bool isVideoDevice(const QString &name);
    static bool isScreenshotName(const QString &name);
    static bool isReminderUnit(const QString &name);
    // The comm names of this uid's processes holding any of `devices` open,
    // except the excluded pids and PipeWire's own daemons; sorted, unique,
    // at most HolderLimit.
    static QStringList cameraHolders(const QString &procRoot, const QStringList &devices,
                                     const QList<pid_t> &excluded, uid_t uid);
    static bool processRunning(const QString &procRoot, const QString &commPrefix, uid_t uid);
signals:
    void event(const QJsonObject &fields);
private:
    enum class Kind { VideoDevice, Dev, Tmp, Screenshots, Transient };
    Paths paths_;
    int fd_ = -1;
    std::unique_ptr<QSocketNotifier> notifier_;
    QHash<int, Kind> kinds_;
    QHash<int, QString> watchedPaths_;
    bool camera_ = false, recording_ = false, reminders_ = false;
    QString screenshotDir_;
    QStringList holders_;
    bool holdersSent_ = false;
    QJsonObject recordingState_;
    QTimer cameraScan_, reminderNotice_;
    QElapsedTimer screenshotWindow_;
    int screenshotCount_ = 0;

    int addWatch(const QString &path, uint32_t mask, Kind kind);
    void removeKind(Kind kind);
    void removeWatch(int wd);
    void watchVideoDevices();
    QStringList videoDevices() const;
    void readEvents();
    void scanCamera();
    void readRecording(bool atStart);
    void noteScreenshot(const QString &path);
};
}
