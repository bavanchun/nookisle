#include "backlight-monitor.h"
#include <QRegularExpression>
#ifdef NOOKISLE_UDEV
#include <libudev.h>
#endif

namespace Island {
BacklightMonitor::BacklightMonitor(QObject *parent) : QObject(parent) {}
BacklightMonitor::~BacklightMonitor() { stop(); }
bool BacklightMonitor::relevant(const QByteArray &action, const QByteArray &subsystem, const QByteArray &name) {
    static const QRegularExpression valid("^[A-Za-z0-9_.:-]{1,64}$");
    return action == "change" && subsystem == "backlight" && valid.match(QString::fromLatin1(name)).hasMatch();
}
#ifdef NOOKISLE_UDEV
bool BacklightMonitor::start() {
    if (monitor_) return true;
    udev_ = udev_new();
    // "udev" events are the ones udevd re-broadcasts after its rules ran, the
    // same stream `udevadm monitor --udev` prints.
    monitor_ = udev_ ? udev_monitor_new_from_netlink(udev_, "udev") : nullptr;
    if (!monitor_ || udev_monitor_filter_add_match_subsystem_devtype(monitor_, "backlight", nullptr) < 0
        || udev_monitor_enable_receiving(monitor_) < 0) {
        stop();
        return false;
    }
    const int fd = udev_monitor_get_fd(monitor_);
    if (fd < 0) { stop(); return false; }
    notifier_ = std::make_unique<QSocketNotifier>(fd, QSocketNotifier::Read);
    connect(notifier_.get(), &QSocketNotifier::activated, this, &BacklightMonitor::receive);
    return true;
}
void BacklightMonitor::stop() {
    notifier_.reset();
    if (monitor_) monitor_ = udev_monitor_unref(monitor_);
    if (udev_) udev_ = udev_unref(udev_);
}
void BacklightMonitor::receive() {
    // The socket is nonblocking; drain what is queued, bounded per wakeup.
    for (int i = 0; monitor_ && i < 64; ++i) {
        udev_device *device = udev_monitor_receive_device(monitor_);
        if (!device) return;
        const QByteArray action = udev_device_get_action(device);
        const QByteArray subsystem = udev_device_get_subsystem(device);
        const QByteArray name = udev_device_get_sysname(device);
        udev_device_unref(device);
        if (relevant(action, subsystem, name)) emit changed(QString::fromLatin1(name));
    }
}
#else
bool BacklightMonitor::start() { return false; }
void BacklightMonitor::stop() {}
void BacklightMonitor::receive() {}
#endif
}
