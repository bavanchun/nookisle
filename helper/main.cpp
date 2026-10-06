#include "artwork-loader.h"
#include "backlight-monitor.h"
#include "ipc-protocol.h"
#include "mpris-registry.h"
#include "browser-registry.h"
#include "thumbnail-cache.h"
#include "system-watch.h"
#ifdef NOOKISLE_CALENDAR
#include "calendar-service.h"
#endif
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QScopeGuard>
#include <QSocketNotifier>
#include <QTimer>
#include <QUuid>
#include <csignal>
#include <memory>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
// SIGTERM (the Service's stop) ends the event loop like closed stdin, so
// the destructors remove the socket and the artwork cache. The handler only
// writes to a pipe; the event loop does the rest.
int terminationPipe[2] = {-1, -1};
void onTerminate(int) {
    const char byte = 1;
    [[maybe_unused]] auto written = ::write(terminationPipe[1], &byte, 1);
}
}

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    app.setApplicationName("nookisle-helper");
    app.setApplicationVersion(ISLAND_BUILD_VERSION);
    if (app.arguments().contains("--version")) { fprintf(stdout, "nookisle-helper %s\n", ISLAND_BUILD_VERSION); return 0; }
    std::signal(SIGPIPE, SIG_IGN);
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    struct stat st {};
    const auto runtimeBytes = QFile::encodeName(runtime);
    if (runtime.isEmpty() || lstat(runtimeBytes.constData(), &st) || !S_ISDIR(st.st_mode)
        || st.st_uid != getuid() || (st.st_mode & 0077)) {
        fprintf(stderr, "unsafe-runtime-directory\n"); return 2;
    }
    // Include the session bus identity; multiple independent sessions may coexist.
    auto session = QCryptographicHash::hash(qgetenv("DBUS_SESSION_BUS_ADDRESS"), QCryptographicHash::Sha256).toHex().left(16);
    const auto leasePath = QFile::encodeName(runtime + "/nookisle-" + session + ".lock");
    const int lease = open(leasePath.constData(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (lease < 0 || fstat(lease, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid()
        || (st.st_mode & 0077) || flock(lease, LOCK_EX | LOCK_NB)) {
        fprintf(stderr, "lease-unavailable\n"); if (lease >= 0) close(lease); return 73;
    }
    // Never unlink a lease inode while another contender may hold it open.
    const auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) { close(lease); fprintf(stderr, "bus-unavailable\n"); return 3; }
    // Socket/art cleanup must finish before a replacement may acquire the lease.
    const auto releaseLease = qScopeGuard([lease] { close(lease); });
    // Holding the lease, this is the session's only helper: any cache an
    // earlier one left when it was killed is stale.
    Island::setArtworkSession(QString::fromLatin1(session));
    Island::sweepStaleArtworkDirectories(runtime, QString::fromLatin1(session));
    std::unique_ptr<QSocketNotifier> termination;
    if (::pipe2(terminationPipe, O_CLOEXEC | O_NONBLOCK) == 0) {
        termination = std::make_unique<QSocketNotifier>(terminationPipe[0], QSocketNotifier::Read);
        QObject::connect(termination.get(), &QSocketNotifier::activated, &app, [&app] { app.exit(0); });
        struct sigaction action {};
        action.sa_handler = onTerminate;
        sigemptyset(&action.sa_mask);
        sigaction(SIGTERM, &action, nullptr);
    }
    Island::StdioChannel channel;
    Island::MprisRegistry registry(bus);
    Island::BrowserRegistry browser(registry.busEpoch());
#ifdef NOOKISLE_CALENDAR
    Island::Calendar::Service calendar;
#endif
    if (!browser.start(runtime, QString::fromLatin1(session))) {
        fprintf(stderr, "browser-bridge-unavailable\n"); return 5;
    }
    const auto generation = QUuid::createUuid().toString(QUuid::WithoutBraces);
    quint64 sequence = 0;
    QVector<QByteArray> snapshot;
    qsizetype snapshotIndex = 0;
    bool dirty = true;
    bool terminating = false;
    QJsonObject selectedArtwork;
    bool artworkVisible = false;
    QTimer publish;
    publish.setSingleShot(true);
    publish.setInterval(16);
#ifdef NOOKISLE_CALENDAR
    QTimer calendarNotify;
    calendarNotify.setSingleShot(true);
    calendarNotify.setInterval(50);
#endif
    auto envelope = [&](QString type, QJsonObject fields) {
        fields["type"] = type;
        fields["protocolVersion"] = 1;
        fields["connectionGeneration"] = generation;
        return Island::encodeFrame(fields);
    };
    auto terminate = [&](int code) {
        terminating = true;
        registry.setGate({}, false);
        browser.setGate({}, false);
        publish.stop();
#ifdef NOOKISLE_CALENDAR
        calendarNotify.stop();
#endif
        app.exit(code);
    };
    auto send = [&](const QByteArray &frame) {
        if (!channel.send(frame)) { fprintf(stderr, "output-backpressure\n"); terminate(4); }
    };
#ifdef NOOKISLE_CALENDAR
    QObject::connect(&calendar, &Island::Calendar::Service::changed, &app, [&] {
        if (!calendarNotify.isActive()) calendarNotify.start();
    });
    QObject::connect(&calendarNotify, &QTimer::timeout, &app, [&] { send(envelope("calendarChanged", {})); });
#endif
    auto pump = [&] {
        while (snapshotIndex < snapshot.size()) {
            // Leave room for a whole method result or admission ACK.
            if (!channel.send(snapshot[snapshotIndex], Island::ReplyReserve)) return;
            ++snapshotIndex;
        }
        snapshot.clear(); snapshotIndex = 0;
        if (dirty && !publish.isActive()) publish.start();
    };
    QObject::connect(&publish, &QTimer::timeout, &app, [&] {
        if (!snapshot.isEmpty()) return;
        dirty = false;
        auto endpoints = registry.endpoints();
        endpoints += browser.endpoints();
        snapshot = Island::snapshotFrames(endpoints, generation, QString::number(++sequence), registry.busEpoch());
        pump();
    });
    QObject::connect(&channel, &Island::StdioChannel::drained, &app, pump);
    QObject::connect(&registry, &Island::MprisRegistry::changed, &app, [&] { dirty = true; if (!publish.isActive()) publish.start(); });
    auto selectBrowserArtwork = [&] {
        QJsonObject track;
        for (const auto &endpoint : browser.endpoints())
            if (endpoint.value("token").toObject() == selectedArtwork) track = endpoint.value("trackToken").toObject();
        registry.selectExternalArtwork(selectedArtwork, track, browser.artworkUrl(selectedArtwork), artworkVisible && !track.isEmpty());
    };
    QObject::connect(&browser, &Island::BrowserRegistry::changed, &app, [&] {
        dirty = true; if (!publish.isActive()) publish.start();
        if (selectedArtwork.value("transport") == "extension") selectBrowserArtwork();
    });
    QObject::connect(&registry, &Island::MprisRegistry::externalArtworkReady, &browser, &Island::BrowserRegistry::setArtwork);
    QObject::connect(&registry, &Island::MprisRegistry::artworkCleared, &browser, &Island::BrowserRegistry::clearArtwork);
    QObject::connect(&channel, &Island::StdioChannel::closed, &app, [&] { terminate(0); });
    QObject::connect(&channel, &Island::StdioChannel::error, &app, [&](const QString &code) {
        fprintf(stderr, "%s\n", qPrintable(code)); terminate(4);
    });
    QObject::connect(&registry, &Island::MprisRegistry::busLost, &app, [&] { terminate(3); });
    // Local desktop signals (camera use, recording, screenshots, reminders),
    // each off until the Service's watch request turns it on. Replaceable
    // under backpressure, like progress.
    Island::SystemWatch systemWatch(Island::SystemWatch::Paths::live());
    QObject::connect(&systemWatch, &Island::SystemWatch::event, &app, [&](const QJsonObject &fields) {
        channel.send(envelope("systemEvent", fields), Island::ReplyReserve);
    });
    Island::BacklightMonitor backlight;
    QObject::connect(&backlight, &Island::BacklightMonitor::changed, &app, [&](const QString &device) {
        // Replaceable like progress: a refused event is dropped, never fatal.
        channel.send(envelope("backlightChanged", {{"device", device}}), Island::ReplyReserve);
    });
    Island::ThumbnailService thumbnails;
    QObject::connect(&thumbnails, &Island::ThumbnailService::finished, &app,
        [&](const QString &id, const QString &status, const QString &path) {
        send(envelope("thumbnailResult", {{"requestId", id}, {"status", status}, {"path", path}}));
    });
    QObject::connect(&registry, &Island::MprisRegistry::result, &app, [&](const QString &id, const QString &status) {
        send(envelope("result", {{"requestId", id}, {"status", status}}));
    });
    QObject::connect(&browser, &Island::BrowserRegistry::result, &app, [&](const QString &id, const QString &status) {
        send(envelope("result", {{"requestId", id}, {"status", status}}));
    });
    QObject::connect(&registry, &Island::MprisRegistry::progress, &app, [&](QJsonObject sample) {
        sample["sequence"] = QString::number(++sequence);
        // Progress is replaceable; backpressure must not disconnect a valid snapshot.
        channel.send(envelope("progress", sample), Island::ReplyReserve);
    });
    QObject::connect(&browser, &Island::BrowserRegistry::progress, &app, [&](QJsonObject sample) {
        sample["sequence"] = QString::number(++sequence);
        channel.send(envelope("progress", sample), Island::ReplyReserve);
    });
    QObject::connect(&channel, &Island::StdioChannel::message, &app, [&](const QJsonObject &request) {
        if (terminating) return;
        if (request.value("protocolVersion").toInt() != 1 || request.value("connectionGeneration").toString() != generation) {
            fprintf(stderr, "protocol-mismatch\n"); terminate(4); return;
        }
        const QString type = request.value("type").toString();
        if (type == "controlGate") {
            const QString epoch = request.value("admissionEpoch").toString();
            if (epoch.isEmpty() || epoch.size() > 128 || !request.value("enabled").isBool()) { terminate(4); return; }
            registry.setGate(epoch, request.value("enabled").toBool());
            browser.setGate(epoch, request.value("enabled").toBool());
            send(envelope("controlGateAck", {{"admissionEpoch", epoch}, {"enabled", request.value("enabled")}}));
        } else if (type == "command") {
            const auto id = request.value("requestId").toString();
            if (id.isEmpty() || id.size() > 128) { terminate(4); return; }
            if (request.value("endpointToken").toObject().value("transport") == "extension") browser.command(request);
            else registry.command(request);
        } else if (type == "subscribe") {
            const auto token = request.value("endpointToken").toObject();
            const bool extension = token.value("transport") == "extension";
            registry.subscribe(token, !extension && request.value("visible").toBool(), request.value("cadenceMs").toInt(1000));
            browser.subscribe(token, extension && request.value("visible").toBool(), request.value("cadenceMs").toInt(1000));
            send(envelope("requestAck", {{"requestId", request.value("requestId")}}));
        } else if (type == "backlightWatch") {
            const auto id = request.value("requestId").toString();
            if (id.isEmpty() || id.size() > 128 || !request.value("enabled").isBool()) { terminate(4); return; }
            bool watching = false;
            if (request.value("enabled").toBool()) watching = backlight.start();
            else backlight.stop();
            send(envelope("requestAck", {{"requestId", id},
                {"status", watching || !request.value("enabled").toBool() ? "ok" : "unavailable"}}));
        } else if (type == "refresh") {
            dirty = true; publish.start();
            send(envelope("requestAck", {{"requestId", request.value("requestId")}}));
        } else if (type == "artworkPolicy") {
            registry.setRemoteArtworkEnabled(request.value("enabled").toBool());
            if (!request.value("enabled").toBool()) browser.clearArtwork();
            send(envelope("requestAck", {{"requestId", request.value("requestId")}}));
        } else if (type == "artworkSelect") {
            selectedArtwork = request.value("endpointToken").toObject();
            artworkVisible = request.value("visible").toBool();
            if (selectedArtwork.value("transport") == "extension") selectBrowserArtwork();
            else registry.selectArtwork(selectedArtwork, artworkVisible);
            send(envelope("requestAck", {{"requestId", request.value("requestId")}}));
        } else if (type == "artworkRetain") {
            const auto paths = request.value("paths").toArray();
            if (paths.size() > 2) { terminate(4); return; }
            QStringList retained;
            for (const auto &path : paths) {
                if (!path.isString() || path.toString().size() > 4096) { terminate(4); return; }
                retained.append(path.toString());
            }
            registry.retainArtwork(retained);
            send(envelope("requestAck", {{"requestId", request.value("requestId")}}));
        } else if (type == "watch") {
            const auto id = request.value("requestId").toString();
            if (id.isEmpty() || id.size() > 128) { terminate(4); return; }
            const bool accepted = systemWatch.configure(request);
            send(envelope("requestAck", {{"requestId", id}, {"status", accepted ? "ok" : "invalid"}}));
        } else if (type == "thumbnail") {
            const auto id = request.value("requestId").toString();
            if (id.isEmpty() || id.size() > 128 || !request.value("uri").isString() || !request.value("name").isString()) {
                terminate(4); return;
            }
            send(envelope("requestAck", {{"requestId", id}}));
            thumbnails.request(id, request.value("uri").toString(), request.value("name").toString());
        }
#ifdef NOOKISLE_CALENDAR
        else if (type.startsWith("calendar")) {
            calendar.handle(request, [&](QJsonObject response) {
                const auto responseType = response.take("type").toString();
                send(envelope(responseType, response));
            });
        }
#endif
        else { fprintf(stderr, "unknown-message\n"); terminate(4); }
    });
    send(envelope("hello", {{"helperBuild", ISLAND_BUILD_VERSION},
#ifdef NOOKISLE_CALENDAR
                            {"calendarSupported", true}
#else
                            {"calendarSupported", false}
#endif
    }));
    registry.start();
    publish.start();
    const int result = app.exec();
    // Destructors retire sockets/art and may emit changed. Their callbacks
    // capture stack-owned schedulers, so disconnect before those locals unwind.
    publish.stop();
#ifdef NOOKISLE_CALENDAR
    calendarNotify.stop();
    QObject::disconnect(&calendar, nullptr, &app, nullptr);
#endif
    QObject::disconnect(&systemWatch, nullptr, &app, nullptr);
    QObject::disconnect(&browser, nullptr, &app, nullptr);
    QObject::disconnect(&registry, nullptr, &app, nullptr);
    QObject::disconnect(&channel, nullptr, &app, nullptr);
    return result;
}
