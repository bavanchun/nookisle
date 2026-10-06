#pragma once
#include <QByteArray>
#include <QObject>
#include <QSocketNotifier>
#include <memory>

struct udev;
struct udev_monitor;

namespace Island {
// Display backlight change events, read from udev's netlink socket inside the
// helper rather than from a `udevadm monitor` child. Only "change" events of
// the backlight subsystem are reported, by device name. LED (keyboard)
// brightness changes emit no uevent, so they are not watched here.
class BacklightMonitor final : public QObject {
    Q_OBJECT
public:
    explicit BacklightMonitor(QObject *parent = nullptr);
    ~BacklightMonitor() override;
    // True once watching; false when udev is unavailable to this process.
    bool start();
    void stop();
    bool running() const { return monitor_ != nullptr; }
    // Whether a uevent with this action, subsystem and device name is reported.
    static bool relevant(const QByteArray &action, const QByteArray &subsystem, const QByteArray &name);
signals:
    void changed(const QString &device);
private:
    udev *udev_ = nullptr;
    udev_monitor *monitor_ = nullptr;
    std::unique_ptr<QSocketNotifier> notifier_;
    void receive();
};
}
