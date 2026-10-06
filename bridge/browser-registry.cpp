#include "browser-registry.h"
#include "ipc-protocol.h"
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QUuid>
#include <algorithm>
#include <cmath>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr qsizetype FrameLimit = 65536, QueueLimit = 131072;
bool privateDirectory(const QString &path) {
    const auto bytes = QFile::encodeName(path);
    struct stat info {};
    return !lstat(bytes.constData(), &info) && S_ISDIR(info.st_mode) && info.st_uid == getuid() && !(info.st_mode & 0077);
}
bool sameUser(QLocalSocket *socket) {
    ucred credentials {}; socklen_t size = sizeof credentials;
    return !getsockopt(socket->socketDescriptor(), SOL_SOCKET, SO_PEERCRED, &credentials, &size) && credentials.uid == getuid();
}
bool shortString(QJsonValue value) { return value.isString() && !value.toString().isEmpty() && value.toString().size() <= 128; }
}
namespace Island {
BrowserRegistry::BrowserRegistry(QString epoch, QObject *parent) : QObject(parent), busEpoch_(std::move(epoch)) {
    handshake_.setSingleShot(true); handshake_.setInterval(3000);
    connect(&handshake_, &QTimer::timeout, this, &BrowserRegistry::drop);
    connect(&server_, &QLocalServer::newConnection, this, [this] {
        while (server_.hasPendingConnections()) {
            auto *socket = server_.nextPendingConnection();
            if (peer_ || !sameUser(socket)) { socket->abort(); socket->deleteLater(); continue; }
            peer_ = socket; socket->setReadBufferSize(FrameLimit + 1);
            connect(socket, &QLocalSocket::readyRead, this, &BrowserRegistry::receive);
            connect(socket, &QLocalSocket::disconnected, this, &BrowserRegistry::drop);
            handshake_.start();
        }
    });
}
BrowserRegistry::~BrowserRegistry() {
    drop(); server_.close();
    if (!authPath_.isEmpty()) QFile::remove(authPath_);
    if (!directory_.isEmpty()) QDir().rmdir(directory_);
}
bool BrowserRegistry::start(const QString &runtime, const QString &sessionHash) {
    if (!privateDirectory(runtime) || sessionHash.size() != 16) return false;
    directory_ = runtime + "/nookisle-" + sessionHash;
    if (::mkdir(QFile::encodeName(directory_).constData(), 0700) && !privateDirectory(directory_)) return false;
    if (!privateDirectory(directory_)) return false;
    const auto path = directory_ + "/browser.sock";
    // Caller holds the core process lease before this cleanup/listen.
    QLocalServer::removeServer(path);
    server_.setSocketOptions(QLocalServer::UserAccessOption);
    server_.setMaxPendingConnections(1);
    if (!server_.listen(path)) return false;
    secret_ = QUuid::createUuid().toString(QUuid::WithoutBraces);
    authPath_ = directory_ + "/browser.json";
    QSaveFile auth(authPath_);
    if (!auth.open(QIODevice::WriteOnly)) return false;
    auth.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    const auto bytes = QJsonDocument(QJsonObject{{"protocolVersion", 1}, {"socket", path}, {"secret", secret_}}).toJson(QJsonDocument::Compact);
    return auth.write(bytes) == bytes.size() && auth.commit();
}
void BrowserRegistry::drop() {
    handshake_.stop(); authenticated_ = false; input_.clear(); session_.clear(); subscribed_ = {};
    auto socket = peer_; peer_ = nullptr;
    if (socket) { socket->disconnect(this); socket->abort(); socket->deleteLater(); }
    auto pending = pending_; pending_.clear();
    for (auto it = pending.begin(); it != pending.end(); ++it) {
        if (it->timer) { it->timer->stop(); it->timer->deleteLater(); }
        if (enabled_ && it->gate == gate_) emit result(it.key(), "target-gone");
    }
    artworkUrls_.clear();
    if (!endpoints_.isEmpty()) { endpoints_.clear(); emit changed(); }
}
bool BrowserRegistry::send(QJsonObject frame) {
    if (!peer_) return false;
    frame["protocolVersion"] = 1; frame["bridgeSession"] = session_;
    auto bytes = QJsonDocument(frame).toJson(QJsonDocument::Compact) + '\n';
    if (bytes.size() > FrameLimit || peer_->bytesToWrite() + bytes.size() > QueueLimit) { drop(); return false; }
    return peer_->write(bytes) == bytes.size();
}
void BrowserRegistry::receive() {
    if (!peer_) return;
    input_ += peer_->readAll();
    while (peer_) {
        auto newline = input_.indexOf('\n');
        if (newline < 0) { if (input_.size() >= FrameLimit) drop(); return; }
        if (newline + 1 > FrameLimit) { drop(); return; }
        auto parsed = QJsonDocument::fromJson(input_.first(newline)); input_.remove(0, newline + 1);
        if (!parsed.isObject()) { drop(); return; }
        message(parsed.object());
    }
}
QString BrowserRegistry::key(const QJsonObject &token) const { return QString::number(token["tabId"].toInt(-1)) + ':' + token["documentId"].toString(); }
QJsonObject BrowserRegistry::resolve(const QJsonObject &token) const {
    const auto endpoint = endpoints_.value(key(token));
    return endpoint["token"].toObject() == token ? endpoint : QJsonObject();
}
void BrowserRegistry::message(const QJsonObject &frame) {
    if (frame["protocolVersion"].toInt() != 1) { drop(); return; }
    if (!authenticated_) {
        if (frame["type"] != "bridgeAuth" || frame["secret"].toString() != secret_) { drop(); return; }
        authenticated_ = true; handshake_.stop(); session_ = QUuid::createUuid().toString(QUuid::WithoutBraces);
        send({{"type", "bridgeHello"}, {"busEpoch", busEpoch_}}); return;
    }
    if (frame["bridgeSession"].toString() != session_) return;
    const auto type = frame["type"].toString();
    if (type == "browserState") {
        if (QJsonDocument(frame).toJson(QJsonDocument::Compact).size() > 8192) { drop(); return; }
        auto token = frame["endpointToken"].toObject();
        const double tab = token["tabId"].toDouble(-1);
        if (token["transport"] != "extension" || token["busEpoch"].toString() != busEpoch_ || token["bridgeSession"].toString() != session_
            || tab < 0 || tab > 2147483647 || tab != std::floor(tab) || token["frameId"].toInt(-1) != 0
            || !shortString(token["documentId"]) || !shortString(token["mediaGeneration"])) { drop(); return; }
        auto state = frame["state"].toObject();
        const auto platform = state["platform"].toString();
        if (!QStringList{"YouTube", "YouTube Music", "Spotify"}.contains(platform) || state["mediaGeneration"] != token["mediaGeneration"]
            || !shortString(state["trackGeneration"])) { drop(); return; }
        QJsonObject caps;
        for (const auto &name : {"CanControl", "CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek", "CanSetVolume",
                                 "CanFavorite", "CanShuffle", "CanLoop"}) caps[name] = state["capabilities"].toObject()[name].toBool();
        caps["CanSetPosition"] = caps["CanSeek"];
        caps["CanFavorite"] = caps["CanFavorite"].toBool() && state["liked"].isBool();
        caps["CanShuffle"] = caps["CanShuffle"].toBool() && state["shuffle"].isBool();
        caps["CanLoop"] = caps["CanLoop"].toBool() && validLoopStatus(state["loopStatus"]);
        // Authored here, not copied from the page. Raising is a property of this
        // transport: the extension worker activates the tab, and the document
        // itself neither knows nor can perform it.
        caps["CanRaise"] = true;
        auto track = QJsonObject{{"endpointToken", token}, {"trackGeneration", state["trackGeneration"]}, {"rawTrackId", state["trackGeneration"]}};
        QJsonArray artists;
        for (const auto &artist : state["artists"].toArray()) {
            if (artists.size() == 16) break;
            if (artist.isString()) artists.append(artist.toString().left(512));
        }
        const auto number = [&state](const char *name, double maximum) {
            const double value = state[name].toDouble();
            return std::isfinite(value) ? std::clamp(value, 0.0, maximum) : 0.0;
        };
        const auto status = state["status"].toString();
        QJsonObject presentation{{"hostApp", "Google Chrome"}, {"browserClass", "google-chrome"},
            {"platform", platform}, {"title", state["title"].toString().left(512)},
            {"artists", artists}, {"controlScope", "document"}, {"evidence", "extension-document"}, {"confidence", "direct"}};
        auto endpoint = QJsonObject{{"token", token}, {"trackToken", track}, {"presentation", presentation}, {"capabilities", caps},
            {"status", QStringList{"Playing", "Paused", "Stopped"}.contains(status) ? status : "Stopped"},
            {"positionSeconds", number("positionSeconds", 1e12)}, {"lengthSeconds", number("lengthSeconds", 1e12)}, {"volume", number("volume", 1)},
            {"liked", caps["CanFavorite"].toBool() && state["liked"].isBool() ? state["liked"] : QJsonValue()},
            {"shuffle", caps["CanShuffle"].toBool() && state["shuffle"].isBool() ? state["shuffle"] : QJsonValue()},
            {"loopStatus", caps["CanLoop"].toBool() && validLoopStatus(state["loopStatus"]) ? state["loopStatus"] : QJsonValue()}};
        const auto id = key(token);
        if (!endpoints_.contains(id) && endpoints_.size() >= 64) return;
        auto before = endpoints_.value(id);
        auto artUrl = state["artworkUrl"].toString();
        if (artUrl.size() > 2048 || !artUrl.startsWith("https://")) artUrl.clear();
        const bool artworkChanged = artworkUrls_.value(id) != artUrl;
        artworkUrls_[id] = artUrl;
        endpoint["artworkPath"] = !artworkChanged && before["trackToken"].toObject() == track ? before["artworkPath"] : QJsonValue("");
        endpoints_[id] = endpoint;
        if (enabled_ && subscribed_ == token && (endpoint["status"] == "Playing" || state["positionEvent"].toBool()))
            emit progress({{"endpointToken", token}, {"trackToken", track}, {"positionSeconds", endpoint["positionSeconds"]}});
        // Position alone does not republish while progress carries it, but a
        // seek does: progress runs only while a subscribed source plays.
        before.remove("positionSeconds"); endpoint.remove("positionSeconds");
        if (before != endpoint || artworkChanged || state["positionEvent"].toBool()) emit changed();
    } else if (type == "browserGone") {
        artworkUrls_.remove(key(frame));
        if (endpoints_.remove(key(frame))) emit changed();
    } else if (type == "browserResult") {
        const auto id = frame["requestId"].toString();
        if (!pending_.contains(id)) return;
        auto pending = pending_.take(id); if (pending.timer) { pending.timer->stop(); pending.timer->deleteLater(); }
        if (!enabled_ || pending.gate != gate_) return;
        const auto status = frame["status"].toString();
        emit result(id, resolve(pending.token).isEmpty() ? "target-gone" :
            QStringList{"success", "target-gone", "unsupported", "stale-track", "busy", "invalid-value", "timeout", "error"}.contains(status) ? status : "error");
    } else { drop(); }
}
QVector<QJsonObject> BrowserRegistry::endpoints() const {
    QVector<QJsonObject> result; auto keys = endpoints_.keys(); std::sort(keys.begin(), keys.end());
    for (const auto &id : keys) result.append(endpoints_[id]);
    return result;
}
void BrowserRegistry::setGate(const QString &epoch, bool enabled) {
    if (epoch != gate_ || !enabled) {
        for (const auto &pending : pending_) if (pending.timer) { pending.timer->stop(); pending.timer->deleteLater(); }
        pending_.clear();
    }
    gate_ = epoch; enabled_ = enabled;
    if (!enabled_ && !subscribed_.isEmpty()) subscribe(subscribed_, false, 1000);
}
QUrl BrowserRegistry::artworkUrl(const QJsonObject &token) const {
    return resolve(token).isEmpty() ? QUrl() : QUrl(artworkUrls_.value(key(token)));
}
void BrowserRegistry::setArtwork(const QJsonObject &token, const QJsonObject &track, const QString &path) {
    auto endpoint = resolve(token);
    if (endpoint.isEmpty() || endpoint["trackToken"].toObject() != track || endpoint["artworkPath"].toString() == path) return;
    endpoint["artworkPath"] = path; endpoints_[key(token)] = endpoint; emit changed();
}
void BrowserRegistry::clearArtwork() {
    bool updated = false;
    for (auto &endpoint : endpoints_) if (!endpoint["artworkPath"].toString().isEmpty()) {
        endpoint["artworkPath"] = ""; updated = true;
    }
    if (updated) emit changed();
}
void BrowserRegistry::subscribe(const QJsonObject &token, bool visible, int cadence) {
    const auto captured = token;
    if (!subscribed_.isEmpty() && subscribed_ != token)
        send({{"type", "browserSubscribe"}, {"endpointToken", subscribed_}, {"visible", false}});
    const bool active = visible && enabled_ && !resolve(token).isEmpty();
    subscribed_ = active ? token : QJsonObject();
    send({{"type", "browserSubscribe"}, {"endpointToken", captured}, {"visible", active}, {"cadenceMs", cadence <= 250 ? std::clamp(cadence, 100, 250) : 1000}});
}
void BrowserRegistry::command(const QJsonObject &request) {
    const auto id = request["requestId"].toString();
    const auto token = request["endpointToken"].toObject(); const auto endpoint = resolve(token);
    if (!enabled_ || request["admissionEpoch"].toString() != gate_) { emit result(id, "closed"); return; }
    if (!authenticated_ || endpoint.isEmpty()) { emit result(id, "target-gone"); return; }
    if (pending_.size() >= 16 || pending_.contains(id)) { emit result(id, "busy"); return; }
    for (const auto &pending : pending_) if (pending.token == token) { emit result(id, "busy"); return; }
    const auto action = request["action"].toString();
    QHash<QString, QString> required{{"Play", "CanPlay"}, {"Pause", "CanPause"}, {"PlayPause", endpoint["status"] == "Playing" ? "CanPause" : "CanPlay"},
        {"Next", "CanGoNext"}, {"Previous", "CanGoPrevious"}, {"SetPosition", "CanSetPosition"}, {"SetVolume", "CanSetVolume"},
        {"Seek", "CanSeek"}, {"SetShuffle", "CanShuffle"}, {"SetLoopStatus", "CanLoop"},
        {"Favorite", "CanFavorite"}, {"Raise", "CanRaise"}};
    auto caps = endpoint["capabilities"].toObject();
    // Raise is not a playback control, so it does not require CanControl.
    const bool requiresControl = action != QStringLiteral("Raise");
    if ((requiresControl && !caps["CanControl"].toBool()) || !required.contains(action)
        || !caps[required.value(action)].toBool()) { emit result(id, "unsupported"); return; }
    if ((action == "SetPosition" || action == "Favorite")
        && request["trackToken"].toObject() != endpoint["trackToken"].toObject()) {
        emit result(id, "stale-track"); return;
    }
    if (action == "SetPosition" || action == "SetVolume") {
        const double value = request["value"].toDouble(-1), maximum = action == "SetVolume" ? 1 : endpoint["lengthSeconds"].toDouble();
        if (!std::isfinite(value) || value < 0 || value > maximum) { emit result(id, "invalid-value"); return; }
    }
    if (action == "Seek" && !validSeekOffset(request["value"])) { emit result(id, "invalid-value"); return; }
    if (action == "SetShuffle" && !request["value"].isBool()) { emit result(id, "invalid-value"); return; }
    if (action == "SetLoopStatus" && !validLoopStatus(request["value"])) { emit result(id, "invalid-value"); return; }
    auto *timer = new QTimer(this); timer->setSingleShot(true); timer->setInterval(3000);
    pending_[id] = {token, gate_, timer};
    connect(timer, &QTimer::timeout, this, [this, id, timer] {
        auto pending = pending_.take(id); timer->deleteLater();
        if (enabled_ && pending.gate == gate_) emit result(id, "timeout");
    }); timer->start();
    auto frame = request; frame["type"] = "browserCommand";
    send(frame);
}
}
