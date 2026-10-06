#include "mpris-registry.h"
#include "ipc-protocol.h"
#include <QDBusArgument>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSet>
#include <QUuid>
#include <QXmlStreamReader>
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
using Island::boundedText;
const QString Path = "/org/mpris/MediaPlayer2";
const QString Props = "org.freedesktop.DBus.Properties";
const QString PlayerInterface = "org.mpris.MediaPlayer2.Player";
const QString RootInterface = "org.mpris.MediaPlayer2";
constexpr int ReadLimit = 128;
QVariant unwrap(QVariant value) {
    if (value.metaType() == QMetaType::fromType<QDBusVariant>())
        return value.value<QDBusVariant>().variant();
    return value;
}
QVariantMap variantMap(QVariant value) {
    value = unwrap(value);
    if (value.metaType() == QMetaType::fromType<QDBusArgument>())
        return qdbus_cast<QVariantMap>(value);
    return value.toMap();
}
QString objectPath(QVariant value) {
    value = unwrap(value);
    return value.metaType() == QMetaType::fromType<QDBusObjectPath>()
        ? value.value<QDBusObjectPath>().path() : QString();
}
QVariantMap rootProperties(const QVariantMap &values) {
    QVariantMap result;
    for (const auto &key : {"DesktopEntry", "Identity"})
        if (values.contains(key)) result[key] = boundedText(values.value(key));
    // Separate branch on purpose: boundedText stringifies, and a "false" string
    // is truthy, so a player advertising CanRaise: false would be admitted.
    if (values.contains("CanRaise")) result["CanRaise"] = unwrap(values.value("CanRaise")).toBool();
    return result;
}
// The Player interface properties whose introspected access allows writes.
// A player may declare Shuffle or LoopStatus read-only (the spec makes them
// read/write, but a player that cannot honour them answers every Set with
// PropertyReadOnly), so presence alone never offers the control.
QSet<QString> writableProperties(const QString &xml) {
    QSet<QString> result;
    constexpr qsizetype XmlLimit = 256 * 1024;
    if (xml.size() > XmlLimit) return result;
    QXmlStreamReader reader(xml);
    bool player = false;
    while (!reader.atEnd()) {
        reader.readNext();
        if (reader.isStartElement() && reader.name() == u"interface")
            player = reader.attributes().value("name") == PlayerInterface;
        else if (reader.isEndElement() && reader.name() == u"interface")
            player = false;
        else if (player && reader.isStartElement() && reader.name() == u"property") {
            const auto access = reader.attributes().value("access");
            if (access == u"readwrite" || access == u"write")
                result.insert(reader.attributes().value("name").toString());
        }
    }
    return reader.hasError() ? QSet<QString>() : result;
}
QVariantMap playerProperties(const QVariantMap &values) {
    QVariantMap result;
    for (const auto &key : {"CanControl", "CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek"})
        if (values.contains(key)) result[key] = unwrap(values.value(key)).toBool();
    for (const auto &key : {"Rate", "Volume"}) {
        if (!values.contains(key)) continue;
        bool ok = false;
        const double number = unwrap(values.value(key)).toDouble(&ok);
        if (ok && std::isfinite(number)) result[key] = number;
    }
    if (values.contains("Shuffle") && unwrap(values.value("Shuffle")).metaType() == QMetaType::fromType<bool>())
        result["Shuffle"] = unwrap(values.value("Shuffle")).toBool();
    if (values.contains("LoopStatus")) {
        const auto status = unwrap(values.value("LoopStatus"));
        if (status.metaType() == QMetaType::fromType<QString>()
            && Island::validLoopStatus(QJsonValue(status.toString()))) result["LoopStatus"] = status.toString();
    }
    if (values.contains("Position")) result["Position"] = std::max<qint64>(0, unwrap(values.value("Position")).toLongLong());
    if (values.contains("PlaybackStatus")) {
        const auto status = unwrap(values.value("PlaybackStatus")).toString();
        result["PlaybackStatus"] = status == "Playing" || status == "Paused" ? status : QString("Stopped");
    }
    if (values.contains("Metadata")) {
        const auto input = variantMap(values.value("Metadata"));
        QVariantMap metadata;
        for (const auto &key : {"xesam:title", "xesam:album", "xesam:url", "mpris:artUrl"})
            if (input.contains(key)) metadata[key] = boundedText(input.value(key));
        const QString rawTrack = objectPath(input.value("mpris:trackid"));
        metadata["trackIdentityHash"] = QCryptographicHash::hash(rawTrack.toUtf8(), QCryptographicHash::Sha256);
        if (!rawTrack.isEmpty() && rawTrack.toUtf8().size() <= 4096)
            metadata["mpris:trackid"] = QVariant::fromValue(QDBusObjectPath(rawTrack));
        metadata["trackIdOversized"] = rawTrack.toUtf8().size() > 4096;
        const qint64 length = unwrap(input.value("mpris:length")).toLongLong();
        // Chromium exports the signed maximum when duration is not known.
        // It is not a seekable duration, even if CanSeek is advertised.
        metadata["mpris:length"] = length == std::numeric_limits<qint64>::max()
            ? qint64(0) : std::max<qint64>(0, length);
        QStringList artists;
        const auto rawArtists = unwrap(input.value("xesam:artist")).toStringList();
        for (int i = 0; i < std::min(16, int(rawArtists.size())); ++i) artists.append(boundedText(rawArtists[i]));
        metadata["xesam:artist"] = artists;
        result["Metadata"] = metadata;
    }
    return result;
}
QDBusMessage method(const QString &owner, const QString &interface, const QString &name) {
    return QDBusMessage::createMethodCall(owner, Path, interface, name);
}
}

namespace Island {
QString boundedText(const QVariant &value) {
    auto text = unwrap(value).toString();
    if (text.size() > 4096) text.truncate(4096);
    if (!text.isEmpty() && text.back().isHighSurrogate()) text.chop(1);
    const auto utf8 = text.toUtf8();
    if (utf8.size() <= 4096) return text;
    // Back off continuation bytes so the cut lands on a code-point start.
    qsizetype cut = 4096;
    while (cut > 0 && (uchar(utf8[cut]) & 0xC0) == 0x80) --cut;
    return QString::fromUtf8(utf8.left(cut));
}
MprisRegistry::MprisRegistry(const QDBusConnection &bus, QObject *parent)
    : QObject(parent), bus_(bus), epoch_(QUuid::createUuid().toString(QUuid::WithoutBraces)) {
    clock_.start();
    connect(&progressTimer_, &QTimer::timeout, this, &MprisRegistry::tick);
    connect(&artwork_, &ArtworkLoader::ready, this, [this](const QString &generation, const QString &path) {
        if (generation != artworkGeneration_ || !enabled_ || (!remoteArtworkEnabled_ && !artworkLocal_) || !artworkVisible_) return;
        if (externalArtwork_) {
            emit externalArtworkReady(externalArtworkEndpoint_, externalArtworkTrack_, path);
            return;
        }
        auto *player = resolve(artworkSelected_);
        if (!player) return;
        player->artworkPath = path;
        emit changed();
    });
}
void MprisRegistry::start() {
    if (started_) return;
    started_ = true;
    bus_.connect("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                 "NameOwnerChanged", this, SLOT(ownerChanged(QString,QString,QString)));
    bus_.connect({}, Path, Props, "PropertiesChanged", this,
                 SLOT(propertiesChanged(QString,QVariantMap,QStringList,QDBusMessage)));
    bus_.connect({}, Path, PlayerInterface, "Seeked", this, SLOT(seeked(qlonglong,QDBusMessage)));
    bus_.connect({}, "/org/freedesktop/DBus/Local", "org.freedesktop.DBus.Local",
                 "Disconnected", this, SLOT(disconnected()));
    auto call = QDBusMessage::createMethodCall("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                             "org.freedesktop.DBus", "ListNames");
    auto *watcher = new QDBusPendingCallWatcher(bus_.asyncCall(call, 3000), this);
    ++activeReads_;
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        --activeReads_;
        QDBusPendingReply<QStringList> reply = *watcher;
        watcher->deleteLater();
        if (reply.isError()) { emit busLost(); return; }
        for (const QString &name : reply.value()) {
            if (!name.startsWith("org.mpris.MediaPlayer2.") || name == "org.mpris.MediaPlayer2.playerctld") continue;
            if (players_.contains(name)) continue;
            if (bootstrap_.size() + players_.size() >= EndpointLimit) break;
            bootstrap_.insert(name, nullptr);
        }
        drainReads();
    });
}
void MprisRegistry::ownerChanged(const QString &name, const QString &, const QString &newOwner) {
    if (!name.startsWith("org.mpris.MediaPlayer2.") || name == "org.mpris.MediaPlayer2.playerctld") return;
    // Invalidate bootstrap without retaining a history of vanished names.
    bootstrap_.remove(name);
    adopt(name, newOwner);
}
void MprisRegistry::adopt(const QString &name, const QString &owner) {
    if (players_.contains(name) && players_[name].owner == owner) return;
    if (players_.contains(name)) {
        // Watcher destruction does not cancel Qt's retained D-Bus call. Keep
        // stale calls accounted for until reply/timeout; never refill on churn.
        players_.remove(name);
    }
    if (!owner.isEmpty() && owner.startsWith(':') && players_.size() < EndpointLimit) {
        Player player;
        player.name = name;
        player.owner = owner;
        player.generation = QString::number(++serial_);
        players_.insert(name, player);
        // Introspect first: replies from one peer keep their order, so the
        // toggles' access is known by the time the Player properties land.
        readAccess(name, owner);
        readProperties(name, owner, true);
        readProperties(name, owner, false);
    }
    if (!resolve(subscribed_)) progressTimer_.stop();
    reconcileArtwork();
    emit changed();
}
void MprisRegistry::readProperties(const QString &name, const QString &owner, bool root) {
    if (!players_.contains(name) || players_[name].owner != owner) return;
    const auto generation = players_[name].generation;
    auto &player = players_[name];
    if (root ? bool(player.rootCall) : bool(player.propertyCall)) return;
    if (activeReads_ >= ReadLimit) {
        if (root) player.rootWanted = true;
        else player.propertiesWanted = true;
        return;
    }
    if (root) player.rootWanted = false;
    else player.propertiesWanted = false;
    const auto revision = root ? player.rootRevision : player.propertyRevision;
    auto call = method(owner, Props, "GetAll");
    call << (root ? RootInterface : PlayerInterface);
    auto *watcher = new QDBusPendingCallWatcher(bus_.asyncCall(call, 3000), this);
    ++activeReads_;
    if (root) player.rootCall = watcher;
    else player.propertyCall = watcher;
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, watcher, name, owner, generation, root, revision] {
        --activeReads_;
        QTimer::singleShot(0, this, &MprisRegistry::drainReads);
        QDBusPendingReply<QVariantMap> reply = *watcher;
        watcher->deleteLater();
        auto it = players_.find(name);
        if (it == players_.end() || it->owner != owner || it->generation != generation) return;
        if (root) it->rootCall = nullptr;
        else it->propertyCall = nullptr;
        if (revision != (root ? it->rootRevision : it->propertyRevision)) {
            // Never let an older GetAll response overwrite a newer signal/Seeked.
            readProperties(name, owner, root);
            return;
        }
        if (reply.isError()) return;
        if (root) it->root = rootProperties(reply.value());
        else update(it.value(), reply.value());
        emit changed();
    });
}
// One introspection per adopted owner: the access attributes do not change
// while the owner lives, and a new owner is a new Player. It takes a read
// slot like GetAll, so owner churn cannot grow the calls outstanding.
void MprisRegistry::readAccess(const QString &name, const QString &owner) {
    auto &player = players_[name];
    if (player.accessSent) return;
    if (activeReads_ >= ReadLimit) { player.accessWanted = true; return; }
    player.accessWanted = false;
    player.accessSent = true;
    const auto generation = player.generation;
    auto call = method(owner, "org.freedesktop.DBus.Introspectable", "Introspect");
    auto *watcher = new QDBusPendingCallWatcher(bus_.asyncCall(call, 3000), this);
    ++activeReads_;
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, name, owner, generation] {
        --activeReads_;
        QTimer::singleShot(0, this, &MprisRegistry::drainReads);
        QDBusPendingReply<QString> reply = *watcher;
        watcher->deleteLater();
        auto it = players_.find(name);
        if (it == players_.end() || it->owner != owner || it->generation != generation || reply.isError()) return;
        const auto writable = writableProperties(reply.value());
        it->shuffleWritable = writable.contains("Shuffle");
        it->loopWritable = writable.contains("LoopStatus");
        emit changed();
    });
}
void MprisRegistry::drainReads() {
    for (auto it = players_.begin(); it != players_.end() && activeReads_ < ReadLimit; ++it) {
        if (it->accessWanted) readAccess(it->name, it->owner);
        if (it->rootWanted) readProperties(it->name, it->owner, true);
        if (it->propertiesWanted) readProperties(it->name, it->owner, false);
    }
    for (auto it = bootstrap_.begin(); it != bootstrap_.end() && activeReads_ < ReadLimit; ++it) {
        if (it.value()) continue;
        const auto name = it.key();
        auto call = QDBusMessage::createMethodCall("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                                 "org.freedesktop.DBus", "GetNameOwner");
        call << name;
        auto *owner = new QDBusPendingCallWatcher(bus_.asyncCall(call, 3000), this);
        ++activeReads_;
        it.value() = owner;
        connect(owner, &QDBusPendingCallWatcher::finished, this, [this, owner, name] {
            --activeReads_;
            QTimer::singleShot(0, this, &MprisRegistry::drainReads);
            QDBusPendingReply<QString> answer = *owner;
            owner->deleteLater();
            if (bootstrap_.value(name) != owner) return;
            bootstrap_.remove(name);
            if (!answer.isError()) adopt(name, answer.value());
        });
    }
}
void MprisRegistry::update(Player &player, const QVariantMap &values) {
    // Capture elapsed position using the old status/rate before applying a change.
    player.basePosition = qint64(position(player) * 1000000.0);
    player.sampledAt = clock_.elapsed();
    const auto clean = playerProperties(values);
    if (values.contains("Shuffle") && !clean.contains("Shuffle")) player.props.remove("Shuffle");
    if (values.contains("LoopStatus") && !clean.contains("LoopStatus")) player.props.remove("LoopStatus");
    for (auto it = clean.begin(); it != clean.end(); ++it) player.props[it.key()] = it.value();
    if (clean.contains("Position")) player.basePosition = clean.value("Position").toLongLong();
    const auto metadata = variantMap(player.props.value("Metadata"));
    const auto identity = QJsonDocument(QJsonArray{
        QString::fromLatin1(metadata.value("trackIdentityHash").toByteArray().toHex()), boundedText(metadata.value("xesam:title")),
        QJsonArray::fromStringList(metadata.value("xesam:artist").toStringList())
    }).toJson(QJsonDocument::Compact);
    if (player.trackIdentity != identity) {
        player.trackIdentity = identity;
        ++player.trackGeneration;
        if (!values.contains("Position")) player.basePosition = 0;
    }
    reconcileArtwork();
}
void MprisRegistry::propertiesChanged(const QString &interface, const QVariantMap &values,
                                      const QStringList &invalidated, const QDBusMessage &message) {
    if (interface != PlayerInterface && interface != RootInterface) return;
    for (auto it = players_.begin(); it != players_.end(); ++it) {
        if (it->owner != message.service()) continue;
        if (interface == PlayerInterface) {
            ++it->propertyRevision;
            update(it.value(), values);
        } else {
            ++it->rootRevision;
            const auto clean = rootProperties(values);
            for (auto field = clean.begin(); field != clean.end(); ++field) it->root[field.key()] = field.value();
        }
        for (const auto &key : invalidated) {
            if (interface == PlayerInterface) it->props.remove(key);
            else it->root.remove(key);
        }
        if (!invalidated.isEmpty()) readProperties(it->name, it->owner, interface == RootInterface);
    }
    tick();
    reconcileArtwork();
    emit changed();
}
// A seek is published at once as a new snapshot, not only through progress:
// progress runs only while a subscribed source plays, so a seek while paused
// would otherwise stay invisible until playback resumed.
void MprisRegistry::seeked(qlonglong positionValue, const QDBusMessage &message) {
    bool moved = false;
    for (auto &player : players_) {
        if (player.owner == message.service()) {
            ++player.propertyRevision;
            player.basePosition = std::max<qint64>(0, positionValue);
            player.sampledAt = clock_.elapsed();
            moved = true;
        }
    }
    tick();
    if (moved) emit changed();
}
void MprisRegistry::disconnected() {
    enabled_ = false;
    progressTimer_.stop();
    players_.clear();
    artwork_.clear();
    artworkGeneration_.clear();
    emit busLost();
}
QJsonObject MprisRegistry::token(const Player &p) const {
    return {{"busEpoch", epoch_}, {"wellKnownName", p.name}, {"uniqueOwner", p.owner},
            {"endpointGeneration", p.generation}};
}
QJsonObject MprisRegistry::trackToken(const Player &p) const {
    const auto raw = objectPath(variantMap(p.props.value("Metadata")).value("mpris:trackid"));
    return {{"endpointToken", token(p)}, {"trackGeneration", QString::number(p.trackGeneration)},
            {"rawTrackId", raw.toUtf8().size() <= 4096 ? raw : QString()}};
}
double MprisRegistry::position(const Player &p) const {
    double value = p.basePosition / 1000000.0;
    const double rate = p.props.value("Rate", 1.0).toDouble();
    if (p.props.value("PlaybackStatus").toString() == "Playing" && std::isfinite(rate))
        value += (clock_.elapsed() - p.sampledAt) / 1000.0 * rate;
    const auto length = variantMap(p.props.value("Metadata")).value("mpris:length").toLongLong() / 1000000.0;
    if (length > 0) value = std::min(value, length);
    return std::max(0.0, value);
}
QJsonObject MprisRegistry::wire(const Player &p) const {
    auto metadata = variantMap(p.props.value("Metadata"));
    QJsonArray artists;
    const auto names = unwrap(metadata.value("xesam:artist")).toStringList();
    for (int i = 0; i < std::min(16, int(names.size())); ++i) artists.append(boundedText(names[i]));
    const QString desktop = boundedText(p.root.value("DesktopEntry"));
    const bool spotify = desktop == "spotify" || p.name == "org.mpris.MediaPlayer2.spotify";
    const bool browser = p.name.startsWith("org.mpris.MediaPlayer2.chromium.")
        || p.name.startsWith("org.mpris.MediaPlayer2.chrome.")
        || desktop == "google-chrome" || desktop == "chromium";
    const QString browserClass = !browser ? QString() : !desktop.isEmpty() ? desktop
        : p.name.startsWith("org.mpris.MediaPlayer2.chromium.") ? QStringLiteral("chromium")
        : QStringLiteral("google-chrome");
    const QString scope = spotify ? "application" : browser ? "browser" : "endpoint";
    auto track = trackToken(p);
    const double length = std::max(0.0, unwrap(metadata.value("mpris:length")).toLongLong() / 1000000.0);
    QJsonObject capabilities;
    for (const auto &key : {"CanControl", "CanPlay", "CanPause", "CanGoNext", "CanGoPrevious", "CanSeek"})
        capabilities[key] = p.props.value(key).toBool();
    const bool positionAvailable = !track.value("rawTrackId").toString().isEmpty()
        && track.value("rawTrackId").toString() != "/org/mpris/MediaPlayer2/TrackList/NoTrack" && length > 0;
    capabilities["CanSetPosition"] = capabilities.value("CanSeek").toBool() && positionAvailable;
    // MPRIS Volume is read/write by spec, but absent/invalid properties are not fabricated.
    capabilities["CanSetVolume"] = p.props.contains("Volume") && p.props.value("CanControl").toBool();
    // Shuffle and LoopStatus are offered only when present and introspected
    // as writable. Spotify desktop 1.2.96.518-3 declares them writable and
    // acknowledges the Properties.Set writes, but neither changes the values
    // nor emits PropertiesChanged, so its controls cannot honestly claim
    // support either.
    capabilities["CanShuffle"] = !spotify && p.shuffleWritable && p.props.contains("Shuffle")
        && p.props.value("CanControl").toBool();
    capabilities["CanLoop"] = !spotify && p.loopWritable && p.props.contains("LoopStatus")
        && p.props.value("CanControl").toBool();
    capabilities["CanFavorite"] = false;
    // Root-interface capability, absent means false. Independent of CanControl:
    // MPRIS lets a player be raisable without being controllable.
    capabilities["CanRaise"] = p.root.value("CanRaise").toBool();
    QJsonObject presentation{{"hostApp", spotify ? "Spotify" : boundedText(p.root.value("Identity"))},
                             {"platform", spotify ? "Spotify" : ""}, {"controlScope", scope},
                             {"desktopEntry", desktop}, {"browserClass", browserClass},
                             {"evidence", spotify ? "mpris-app-identity" : browser ? "mpris-browser-endpoint" : "unclassified-mpris"},
                             {"title", boundedText(metadata.value("xesam:title"))},
                             {"album", boundedText(metadata.value("xesam:album"))}, {"artists", artists}};
    return {{"token", token(p)}, {"trackToken", track}, {"presentation", presentation},
            {"status", p.props.value("PlaybackStatus", "Stopped").toString()},
            {"capabilities", capabilities}, {"positionSeconds", position(p)},
            {"lengthSeconds", length}, {"volume", p.props.value("Volume").toDouble()},
            {"shuffle", p.props.contains("Shuffle") ? QJsonValue(p.props.value("Shuffle").toBool()) : QJsonValue()},
            {"loopStatus", p.props.contains("LoopStatus") ? QJsonValue(p.props.value("LoopStatus").toString()) : QJsonValue()},
            {"artworkPath", p.artworkPath},
            {"seekUnavailableReason", metadata.value("trackIdOversized").toBool() ? "track-id-oversized" : ""}};
}
QVector<QJsonObject> MprisRegistry::endpoints() const {
    QVector<QJsonObject> result;
    auto names = players_.keys();
    std::sort(names.begin(), names.end());
    for (const auto &name : names) result.append(wire(players_[name]));
    return result;
}
MprisRegistry::Player *MprisRegistry::resolve(const QJsonObject &expected) {
    auto it = players_.find(expected.value("wellKnownName").toString());
    return it != players_.end() && token(it.value()) == expected ? &it.value() : nullptr;
}
void MprisRegistry::setGate(const QString &epoch, bool enabled) {
    admissionEpoch_ = epoch;
    enabled_ = enabled;
    if (!enabled_) { progressTimer_.stop(); subscribed_ = {}; }
    reconcileArtwork();
}
void MprisRegistry::setRemoteArtworkEnabled(bool enabled) {
    if (remoteArtworkEnabled_ == enabled) return;
    remoteArtworkEnabled_ = enabled;
    if (!enabled) {
        artwork_.clear();
        clearArtworkPaths();
    }
    artworkGeneration_.clear();
    reconcileArtwork();
}
void MprisRegistry::selectArtwork(const QJsonObject &expected, bool visible) {
    externalArtwork_ = false;
    artworkSelected_ = expected;
    artworkVisible_ = visible;
    reconcileArtwork();
}
void MprisRegistry::selectExternalArtwork(const QJsonObject &endpointToken, const QJsonObject &track,
                                        const QUrl &url, bool visible) {
    externalArtwork_ = true;
    externalArtworkEndpoint_ = endpointToken;
    externalArtworkTrack_ = track;
    externalArtworkUrl_ = url;
    artworkVisible_ = visible;
    reconcileArtwork();
}
void MprisRegistry::retainArtwork(const QStringList &paths) { artwork_.retain(paths); }
// Withdraws every advertised path, native and browser: once the selection
// moves or is cancelled or hidden, the island retains no path, and a file
// the loader then evicts must not stay advertised.
void MprisRegistry::clearArtworkPaths() {
    for (auto &entry : players_) entry.artworkPath.clear();
    emit artworkCleared();
    emit changed();
}
void MprisRegistry::reconcileArtwork() {
    auto *player = resolve(artworkSelected_);
    const bool selected = externalArtwork_ ? !externalArtworkEndpoint_.isEmpty() && !externalArtworkTrack_.isEmpty() : !!player;
    const auto url = !selected ? QString() : externalArtwork_ ? externalArtworkUrl_.toString()
        : variantMap(player->props.value("Metadata")).value("mpris:artUrl").toString();
    // Browser artwork is always fetched from the network; a native player's
    // file:// cover is read locally and needs no remote consent.
    const bool local = !externalArtwork_ && localArtworkUrl(QUrl(url, QUrl::StrictMode));
    if (!selected || !enabled_ || (!remoteArtworkEnabled_ && !local) || !artworkVisible_) {
        artwork_.cancel();
        const bool published = !artworkGeneration_.isEmpty();
        artworkGeneration_.clear();
        if (published) clearArtworkPaths();
        return;
    }
    artworkLocal_ = local;
    const auto endpoint = externalArtwork_ ? externalArtworkEndpoint_ : token(*player);
    const auto track = externalArtwork_ ? externalArtworkTrack_ : trackToken(*player);
    const auto identity = QJsonDocument(QJsonArray{externalArtwork_, endpoint, track, url}).toJson(QJsonDocument::Compact);
    const auto generation = QString::fromLatin1(QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex());
    if (generation == artworkGeneration_) return;
    artworkGeneration_ = generation;
    // Only the selected source publishes a path. An old endpoint must never
    // advertise a cache entry after it has become eligible for eviction.
    clearArtworkPaths();
    artwork_.request(QUrl(url, QUrl::StrictMode), generation);
}
void MprisRegistry::command(const QJsonObject &request) {
    const auto id = request.value("requestId").toString();
    if (!enabled_ || request.value("admissionEpoch").toString() != admissionEpoch_) {
        emit result(id, "closed"); return;
    }
    auto *player = resolve(request.value("endpointToken").toObject());
    if (!player) { emit result(id, "target-gone"); return; }
    if (pending_.size() >= 16 || pending_.contains(player->name)) { emit result(id, "busy"); return; }
    const auto action = request.value("action").toString();
    const QHash<QString, QString> required{{"PlayPause", player->props.value("PlaybackStatus").toString() == "Playing" ? "CanPause" : "CanPlay"},
        {"Play", "CanPlay"}, {"Pause", "CanPause"}, {"Next", "CanGoNext"}, {"Previous", "CanGoPrevious"},
        {"SetPosition", "CanSetPosition"}, {"Seek", "CanSeek"}, {"SetVolume", "CanSetVolume"},
        {"SetShuffle", "CanShuffle"}, {"SetLoopStatus", "CanLoop"}, {"Raise", "CanRaise"}};
    const auto state = wire(*player);
    const auto caps = state.value("capabilities").toObject();
    // Raise lives on the root interface and is not a playback control, so it is
    // deliberately exempt from the CanControl gate that every transport action
    // passes through.
    const bool requiresControl = action != "Raise";
    if (!required.contains(action) || (requiresControl && !caps.value("CanControl").toBool())
        || !caps.value(required.value(action)).toBool()) {
        emit result(id, "unsupported"); return;
    }
    auto call = method(player->owner, action == "Raise" ? RootInterface : PlayerInterface, action);
    if (action == "SetPosition") {
        const auto track = state.value("trackToken").toObject();
        if (request.value("trackToken").toObject() != track) { emit result(id, "stale-track"); return; }
        const double value = request.value("value").toDouble(-1);
        const double length = state.value("lengthSeconds").toDouble();
        if (!std::isfinite(value) || value < 0 || value > length || value > 9e12) { emit result(id, "invalid-value"); return; }
        call << QVariant::fromValue(QDBusObjectPath(track.value("rawTrackId").toString()))
             << QVariant::fromValue(qlonglong(value * 1000000.0));
    } else if (action == "SetVolume") {
        const double value = request.value("value").toDouble(-1);
        if (!std::isfinite(value) || value < 0 || value > 1) { emit result(id, "invalid-value"); return; }
        call = method(player->owner, Props, "Set");
        call << PlayerInterface << QString("Volume") << QVariant::fromValue(QDBusVariant(value));
    } else if (action == "SetShuffle") {
        if (!request.value("value").isBool()) { emit result(id, "invalid-value"); return; }
        call = method(player->owner, Props, "Set");
        call << PlayerInterface << QString("Shuffle") << QVariant::fromValue(QDBusVariant(request.value("value").toBool()));
    } else if (action == "SetLoopStatus") {
        if (!validLoopStatus(request.value("value"))) { emit result(id, "invalid-value"); return; }
        call = method(player->owner, Props, "Set");
        call << PlayerInterface << QString("LoopStatus") << QVariant::fromValue(QDBusVariant(request.value("value").toString()));
    } else if (action == "Seek") {
        if (!validSeekOffset(request.value("value"))) { emit result(id, "invalid-value"); return; }
        call << QVariant::fromValue(qlonglong(request.value("value").toDouble() * 1000000.0));
    }
    const auto captured = token(*player);
    const auto name = player->name;
    const auto gate = admissionEpoch_;
    pending_[name] = id;
    // Destination is captured unique owner. No name re-resolution or fallback is permitted.
    auto *watcher = new QDBusPendingCallWatcher(bus_.asyncCall(call, 3000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, id, name, captured, gate] {
        const QDBusPendingReply<> reply = *watcher;
        watcher->deleteLater();
        if (pending_.value(name) == id) pending_.remove(name);
        if (!enabled_ || gate != admissionEpoch_) return;
        if (!resolve(captured)) { emit result(id, "target-gone"); return; }
        const QString status = !reply.isError() ? "success"
            : reply.error().type() == QDBusError::NoReply ? "timeout" : "error";
        emit result(id, status);
    });
}
void MprisRegistry::subscribe(const QJsonObject &expected, bool visible, int cadence) {
    subscribed_ = visible && enabled_ ? expected : QJsonObject();
    progressTimer_.setInterval(cadence <= 250 ? std::clamp(cadence, 100, 250) : 1000);
    auto *player = resolve(subscribed_);
    if (player && player->props.value("PlaybackStatus").toString() == "Playing") {
        readProperties(player->name, player->owner, false);
        progressTimer_.start();
    } else progressTimer_.stop();
    tick();
}
void MprisRegistry::tick() {
    auto *player = resolve(subscribed_);
    if (!enabled_ || !player) { progressTimer_.stop(); return; }
    emit progress({{"endpointToken", token(*player)}, {"trackToken", trackToken(*player)},
                   {"positionSeconds", position(*player)}});
    if (player->props.value("PlaybackStatus").toString() != "Playing") { progressTimer_.stop(); return; }
    if (!progressTimer_.isActive()) progressTimer_.start();
    if (clock_.elapsed() - player->lastResync >= 5000) {
        player->lastResync = clock_.elapsed();
        readProperties(player->name, player->owner, false);
    }
}
}
