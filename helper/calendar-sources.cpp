#include "calendar-sources.h"
#include "artwork-fetch.h"
#include "ipc-protocol.h"
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QtConcurrent/QtConcurrentRun>
#include <QHostAddress>
#include <QHostInfo>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkProxy>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTimeZone>
#include <QXmlStreamReader>
#include <algorithm>
#include <memory>

namespace Island::Calendar {
bool isLocalAddress(const QHostAddress &address) {
    return !publicArtworkAddress(address);
}
QNetworkRequest pinnedRequest(const QUrl &url, const QHostAddress &address, qint64 timeoutMs) {
    QUrl pinned(url);
    pinned.setHost(address.toString());
    QNetworkRequest req(pinned);
    req.setRawHeader("Host", url.host().toUtf8() + (url.port() > 0 ? ":" + QByteArray::number(url.port()) : QByteArray()));
    req.setPeerVerifyName(url.host());
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    req.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    req.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    req.setTransferTimeout(qMax<qint64>(1, timeoutMs));
    return req;
}

namespace {
int effectivePort(const QUrl &url) {
    return url.port(url.scheme().compare(QLatin1String("https"), Qt::CaseInsensitive) == 0 ? 443 : 80);
}

bool isSameOrigin(const QUrl &a, const QUrl &b) {
    return a.scheme().compare(b.scheme(), Qt::CaseInsensitive) == 0
        && a.host().compare(b.host(), Qt::CaseInsensitive) == 0
        && effectivePort(a) == effectivePort(b);
}

QString idFor(const QJsonObject &definition) {
    auto text = definition.value("kind").toString() + "\n" + definition.value("path").toString()
        + "\n" + definition.value("url").toString() + "\n" + definition.value("user").toString();
    return QString::fromLatin1(QCryptographicHash::hash(text.toUtf8(), QCryptographicHash::Sha256).toHex().left(16));
}
// A user name or password before the host (scheme://user:pass@host). Such a
// URL is never a source and never reaches secret-tool's command line, where
// any local process could read it; the same rule as Settings.hasUserinfo.
bool hasUserInfo(const QString &url) {
    static const QRegularExpression userinfo(R"(^\s*[a-z][a-z0-9+.-]*://[^/?#]*@)",
                                             QRegularExpression::CaseInsensitiveOption);
    return userinfo.match(url).hasMatch() || !QUrl(url).userInfo().isEmpty();
}
QString checkUrl(const QUrl &url) {
    if (!url.isValid() || url.host().isEmpty() || !url.userInfo().isEmpty()
        || (url.scheme() != "https" && !(url.scheme() == "http" && url.host() == "localhost"))) return "invalid-url";
    return {};
}
QString secretOutput(QByteArray value) {
    if (value.endsWith('\n')) value.chop(1);
    if (value.endsWith('\r')) value.chop(1);
    return QString::fromUtf8(value);
}
QStringList memberHrefs(const QByteArray &xml) {
    QXmlStreamReader reader(xml);
    QStringList hrefs;
    while (!reader.atEnd()) {
        reader.readNext();
        if (reader.isStartElement() && reader.name() == "href") hrefs.append(reader.readElementText());
    }
    return reader.hasError() ? QStringList() : hrefs;
}
struct CalendarMember { QString href, etag; QByteArray data; };
QVector<CalendarMember> calendarMembers(const QByteArray &xml) {
    QXmlStreamReader reader(xml);
    QVector<CalendarMember> result;
    CalendarMember current;
    bool response = false;
    while (!reader.atEnd()) {
        reader.readNext();
        if (reader.isStartElement() && reader.name() == "response") { response = true; current = {}; }
        else if (reader.isEndElement() && reader.name() == "response") {
            if (response && !current.data.isEmpty() && !current.href.isEmpty()) result.append(current);
            response = false;
        } else if (response && reader.isStartElement()) {
            if (reader.name() == "getetag") current.etag = reader.readElementText();
            else if (reader.name() == "calendar-data") current.data = reader.readElementText().toUtf8();
            else if (reader.name() == "href") current.href = reader.readElementText();
        }
    }
    return reader.hasError() ? QVector<CalendarMember>() : result;
}
// Rewrites STATUS and COMPLETED in every VTODO with this UID. Lines are
// unfolded for matching; untouched lines keep their original folding.
QByteArray rewriteTodo(const QByteArray &raw, const QString &uid, bool completed) {
    struct Line { QString text; QStringList physical; };
    QVector<Line> lines;
    for (const QString &line : QString::fromUtf8(raw).split(QRegularExpression("\r\n|\n|\r"))) {
        if ((line.startsWith(' ') || line.startsWith('\t')) && !lines.isEmpty()) {
            lines.last().text += line.mid(1);
            lines.last().physical.append(line);
        } else lines.append({line, {line}});
    }
    auto opens = [](const QString &text) { return text.startsWith("BEGIN:", Qt::CaseInsensitive); };
    auto closes = [](const QString &text) { return text.startsWith("END:", Qt::CaseInsensitive); };
    QVector<Line> out;
    bool changed = false;
    for (int i = 0; i < lines.size();) {
        if (lines[i].text != "BEGIN:VTODO") { out.append(lines[i++]); continue; }
        int end = i + 1, depth = 0;
        bool match = false;
        for (; end < lines.size(); ++end) {
            const QString &text = lines[end].text;
            if (depth == 0 && text == "END:VTODO") break;
            if (opens(text)) ++depth;
            else if (closes(text)) { if (depth) --depth; }
            else if (depth == 0) {
                auto [name, value] = property(text);
                if (name == "UID" && value.left(1024) == uid) match = true;
            }
        }
        if (end >= lines.size() || !match) {
            for (int k = i; k < qMin(end + 1, int(lines.size())); ++k) out.append(lines[k]);
            i = end + 1;
            continue;
        }
        changed = true;
        out.append(lines[i]);
        // Properties precede sub-components such as VALARM.
        int insertAt = -1;
        depth = 0;
        for (int k = i + 1; k < end; ++k) {
            const QString &text = lines[k].text;
            if (opens(text)) { if (depth++ == 0 && insertAt < 0) insertAt = out.size(); }
            else if (closes(text)) { if (depth) --depth; }
            else if (depth == 0) {
                QString name = property(text).first;
                if (name == "STATUS" || name == "COMPLETED") continue;
            }
            out.append(lines[k]);
        }
        if (insertAt < 0) insertAt = out.size();
        QVector<Line> added{{completed ? "STATUS:COMPLETED" : "STATUS:NEEDS-ACTION", {}}};
        if (completed) {
            QString stamp = "COMPLETED:" + QDateTime::currentDateTimeUtc().toString("yyyyMMdd'T'HHmmss'Z'");
            added.append({stamp, {}});
        }
        for (auto &line : added) line.physical = {line.text};
        out.insert(insertAt, added.size(), Line{});
        std::copy(added.begin(), added.end(), out.begin() + insertAt);
        out.append(lines[end]);
        i = end + 1;
    }
    if (!changed) return {};
    QStringList physical;
    for (const auto &line : out) physical += line.physical;
    return physical.join("\r\n").toUtf8();
}
// Detects a vdir file replaced or edited since it was read.
// A lookup that found no password is an authentication error; a keyring that
// stayed locked, or no secret-tool at all, keeps its own code.
QString passwordError(const QString &error) {
    return error == "secret-service-locked" || error == "secret-service-unavailable" ? error : QString("auth-error");
}
QString fileStamp(const QString &path) {
    QFileInfo info(path);
    if (!info.exists()) return {};
    return QString::number(info.lastModified().toMSecsSinceEpoch()) + ':' + QString::number(info.size());
}
}

Sources::Sources(QObject *parent) : QObject(parent) {
    network_.setProxy(QNetworkProxy::NoProxy);
    // Connected first, so the window is stale before any listener re-reads it.
    connect(this, &Sources::changed, this, [this] { cache_.valid = false; });
    refresh_.setInterval(15 * 60000);
    connect(&refresh_, &QTimer::timeout, this, [this] {
        for (const auto &id : sources_.keys()) if (sources_[id].kind == "ics-url" || sources_[id].kind == "caldav") refreshRemote(id);
    });
    // A sync tool rewrites many files at once; their events coalesce into one
    // reload per source after the burst settles, not one full re-read each.
    reload_.setSingleShot(true);
    reload_.setInterval(300);
    connect(&reload_, &QTimer::timeout, this, [this] {
        const auto ids = std::exchange(pendingReload_, {});
        for (const auto &id : ids) if (sources_.contains(id)) loadLocal(sources_[id]);
    });
    auto reload = [this](const QString &path) {
        for (auto it = sources_.begin(); it != sources_.end(); ++it) {
            if (it->path == path || (it->kind == "vdir" && path.startsWith(it->path + '/'))) pendingReload_.insert(it->id);
        }
        if (!pendingReload_.isEmpty()) reload_.start();
        // Qt drops the watch of a file that was replaced or removed. Forget it
        // either way, and watch it again at once when it still exists; a
        // removed file is watched again by the reload that finds it recreated.
        if (!watcher_.files().contains(path) && !watcher_.directories().contains(path)) {
            watched_.remove(path);
            if (QFile::exists(path)) watch(path);
        }
    };
    connect(&watcher_, &QFileSystemWatcher::fileChanged, this, reload);
    connect(&watcher_, &QFileSystemWatcher::directoryChanged, this, reload);
}

void Sources::watch(const QString &path) {
    if (watched_.contains(path)) return;
    watcher_.addPath(path);
    watched_.insert(path);
}

void Sources::secretTool(const QStringList &arguments, const QByteArray &input, bool lookup,
                         const std::function<void(QString, QByteArray)> &done) {
    auto *process = new QProcess(this);
    if (lookup) lookups_.insert(process);
    auto settled = std::make_shared<bool>(false);
    auto timedOut = std::make_shared<bool>(false);
    auto finish = [this, process, done, settled](QString error) {
        if (*settled) return;
        *settled = true;
        lookups_.remove(process);
        QByteArray output = error.isEmpty() ? process->readAllStandardOutput() : QByteArray();
        process->deleteLater();
        done(error, output);
    };
    connect(process, &QProcess::finished, this, [finish, timedOut](int code, QProcess::ExitStatus status) {
        finish(*timedOut ? QString("secret-service-locked")
               : code == 0 && status == QProcess::NormalExit ? QString() : QString("secret-service-error"));
    });
    connect(process, &QProcess::errorOccurred, this, [finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) finish("secret-service-unavailable");
    });
    if (!lookup) {
        connect(process, &QProcess::started, process, [process, input] {
            process->write(input);
            process->closeWriteChannel();
        });
    }
    process->start("secret-tool", arguments);
    // A locked keyring shows an unlock prompt first, so the user has time to
    // answer it; a prompt left unanswered is a locked keyring, not a bad password.
    QTimer::singleShot(secretTimeoutMs_, process, [process, timedOut] {
        if (process->state() == QProcess::NotRunning) return;
        *timedOut = true;
        process->kill();
    });
}

void Sources::lookupPassword(const QString &url, const QString &user,
                             const std::function<void(QString, QString)> &done) {
    if (hasUserInfo(url)) { done("invalid-url", {}); return; }
    secretTool({"lookup", "service", "nookisle", "caldav", url, "user", user}, {}, true,
        [done](QString error, QByteArray output) { done(error, error.isEmpty() ? secretOutput(output) : QString()); });
}

void Sources::credential(const QString &verb, const QString &url, const QString &user,
                         const QByteArray &password, const std::function<void(QString)> &done) {
    if (verb != "store" && verb != "clear") { done("invalid-verb"); return; }
    if (hasUserInfo(url)) { done("invalid-url"); return; }
    QStringList arguments;
    if (verb == "store") arguments << "store" << "--label=Nookisle CalDAV";
    else arguments << "clear";
    arguments << "service" << "nookisle" << "caldav" << url << "user" << user;
    const bool store = verb == "store";
    secretTool(arguments, password, false, [this, done, store, url, user](QString error, QByteArray) {
        done(error.isEmpty() ? QString("ok") : error);
        if (error.isEmpty() && store) refetchAccount(url, user);
    });
}

// Reloads every CalDAV source of this account with the new password, then
// announces the change once all of them have finished.
void Sources::refetchAccount(const QString &url, const QString &user) {
    QStringList ids;
    for (const auto &source : std::as_const(sources_))
        if (source.kind == "caldav" && source.url == url && source.user == user) ids.append(source.id);
    if (ids.isEmpty()) return;
    auto remaining = std::make_shared<int>(ids.size());
    const quint64 generation = generation_;
    auto finished = [this, remaining, generation](QString) {
        if (--*remaining == 0 && generation == generation_) emit changed();
    };
    for (const auto &id : ids) {
        // A load already running may have read the old password: reload after it.
        if (loading_.contains(id)) {
            loadWaiters_[id].append([this, id, finished, generation](QString) {
                if (generation != generation_) return;
                loadWaiters_[id].append(finished);
                refreshRemote(id);
            });
        } else {
            loadWaiters_[id].append(finished);
            refreshRemote(id);
        }
    }
}

void Sources::configure(const QJsonArray &definitions, bool enabled, int refreshMinutes) {
    ++generation_;
    enabled_ = enabled;
    refresh_.stop();
    // abort() emits finished synchronously, and that handler edits replies_.
    const auto replies = std::exchange(replies_, {});
    for (auto *reply : replies) reply->abort();
    // No pooled connection outlives the sources that opened it.
    network_.clearConnectionCache();
    for (auto *process : lookups_) process->kill();
    loading_.clear();
    const auto waiters = std::exchange(loadWaiters_, {});
    for (const auto &list : waiters) for (const auto &waiter : list) waiter("cancelled");
    reload_.stop();
    pendingReload_.clear();
    for (const auto &path : watcher_.files()) watcher_.removePath(path);
    for (const auto &path : watcher_.directories()) watcher_.removePath(path);
    watched_.clear();
    sources_.clear();
    if (!enabled_) { emit changed(); return; }
    int sourceIndex = 0;
    for (const auto &value : definitions) {
        if (sourceIndex++ >= 32) break;
        auto item = value.toObject();
        Source s;
        s.id = idFor(item); s.kind = item.value("kind").toString(); s.path = item.value("path").toString();
        s.url = item.value("url").toString(); s.user = item.value("user").toString();
        s.color = item.value("color").toString(); s.allowLocalNetwork = item.value("allowLocalNetwork").toBool();
        if (!QStringList{"file", "vdir", "ics-url", "caldav"}.contains(s.kind)) continue;
        if ((s.kind == "ics-url" || s.kind == "caldav") && hasUserInfo(s.url)) continue;
        sources_.insert(s.id, s);
        if (s.kind == "file" || s.kind == "vdir") loadLocal(sources_[s.id]);
        else refreshRemote(s.id);
    }
    refresh_.setInterval(qMax(5, refreshMinutes) * 60000);
    refresh_.start(); emit changed();
}

void Sources::offload(std::function<Loaded()> work, std::function<void(const Loaded &)> apply) {
    auto *watcher = new QFutureWatcher<Loaded>(this);
    connect(watcher, &QFutureWatcher<Loaded>::finished, this, [watcher, apply] {
        watcher->deleteLater();
        apply(watcher->result());
    });
    watcher->setFuture(QtConcurrent::run(std::move(work)));
}

namespace {
// Reads and parses one local source. Runs on a worker thread: it touches no
// Sources state, only its arguments.
Loaded readLocal(const QString &kind, const QString &path) {
    Loaded result;
    QStringList files;
    if (kind == "file") {
        if (!path.endsWith(".ics", Qt::CaseInsensitive)) { result.error = "invalid-source"; return result; }
        files << path;
    } else {
        if (!QDir(path).exists()) { result.error = "missing-source"; return result; }
        QDirIterator it(path, {"*.ics"}, QDir::Files);
        while (it.hasNext() && files.size() <= ComponentLimit) files.append(it.next());
        if (files.size() > ComponentLimit) { result.error = "too-many-components"; return result; }
        result.watch << path;
    }
    int count = 0;
    for (const auto &file : files) {
        QFile input(file);
        if (!input.open(QIODevice::ReadOnly)) { result.error = "unreadable-source"; continue; }
        auto parsed = parse(input.read(SourceLimit + 1));
        if (!parsed.error.isEmpty()) { result.error = parsed.error; continue; }
        count += parsed.entries.size();
        if (count > ComponentLimit) { result.entries.clear(); result.error = "too-many-components"; break; }
        result.entries += parsed.entries;
        if (kind == "vdir") {
            const QString stamp = fileStamp(file);
            for (const auto &entry : parsed.entries) result.members.insert(entry.uid, {file, stamp, {}});
        }
        result.watch << file;
    }
    return result;
}
}

// Loads a local source off the event loop. The newest load of a source wins;
// a reconfiguration or a newer load discards an older result.
void Sources::loadLocal(Source &source) {
    const auto serial = ++source.loadSerial;
    const auto id = source.id, kind = source.kind, path = source.path;
    const auto generation = generation_;
    loading_.insert(id);
    offload([kind, path] { return readLocal(kind, path); }, [this, id, serial, generation](const Loaded &loaded) {
        if (generation != generation_ || !sources_.contains(id) || sources_[id].loadSerial != serial) return;
        auto &source = sources_[id];
        source.error = loaded.error;
        source.entries = loaded.entries;
        source.members = loaded.members;
        for (const auto &path : loaded.watch) watch(path);
        emit changed();
        completeLoad(id);
    });
}

void Sources::request(const QString &id, const QString &method, const QUrl &url, const QByteArray &body,
                      const QMap<QByteArray, QByteArray> &headers,
                      const std::function<void(QString, QByteArray, QByteArray)> &done, int redirects, qint64 deadline) {
    if (!enabled_ || !sources_.contains(id)) { done("disabled", {}, {}); return; }
    const Source source = sources_.value(id);
    QString check = checkUrl(url);
    if (!check.isEmpty()) { done(check, {}, {}); return; }
    if (!deadline) deadline = QDateTime::currentMSecsSinceEpoch() + 8000;
    const quint64 generation = generation_;
    struct Pending { bool settled = false; int lookupId = -1; QPointer<QNetworkReply> reply; };
    auto pending = std::make_shared<Pending>();
    QTimer::singleShot(qMax<qint64>(1, deadline - QDateTime::currentMSecsSinceEpoch()), this,
        [this, pending, done, generation] {
            if (pending->settled) return;
            pending->settled = true;
            if (pending->lookupId >= 0) QHostInfo::abortHostLookup(pending->lookupId);
            if (pending->reply) pending->reply->abort();
            done(generation != generation_ ? "cancelled" : "timeout", {}, {});
        });
    pending->lookupId = QHostInfo::lookupHost(url.host(), this,
        [this, pending, id, method, url, body, headers, done, redirects, deadline, generation, source](const QHostInfo &host) {
            if (pending->settled) return;
            pending->lookupId = -1;
            if (generation != generation_ || !enabled_ || !sources_.contains(id)) { pending->settled = true; done("cancelled", {}, {}); return; }
            auto addresses = host.addresses();
            if (host.error() != QHostInfo::NoError || addresses.isEmpty()) { pending->settled = true; done("dns-error", {}, {}); return; }
            for (const auto &address : addresses) {
                if (url.scheme() == "http" && url.host() == "localhost" && !address.isLoopback()) {
                    pending->settled = true; done("invalid-url", {}, {}); return;
                }
                if (isLocalAddress(address) && !source.allowLocalNetwork) {
                    pending->settled = true; done("private-address", {}, {}); return;
                }
            }
            // Connect to this checked address, preserving the original Host
            // header and TLS identity even when DNS changes later.
            QHostAddress address = addresses.first();
            for (const auto &candidate : addresses)
                if (candidate.protocol() == QAbstractSocket::IPv4Protocol) { address = candidate; break; }
            QNetworkRequest req = pinnedRequest(url, address, deadline - QDateTime::currentMSecsSinceEpoch());
            for (auto it = headers.begin(); it != headers.end(); ++it) req.setRawHeader(it.key(), it.value());
            auto *reply = network_.sendCustomRequest(req, method.toUtf8(), body);
            reply->setReadBufferSize(SourceLimit + 1);
            pending->reply = reply;
            replies_.insert(reply);
            connect(reply, &QNetworkReply::metaDataChanged, this, [reply] {
                if (reply->header(QNetworkRequest::ContentLengthHeader).toLongLong() > SourceLimit) {
                    reply->setProperty("calendarTooLarge", true); reply->abort();
                }
            });
            connect(reply, &QNetworkReply::readyRead, this, [reply] {
                if (reply->bytesAvailable() > SourceLimit) { reply->setProperty("calendarTooLarge", true); reply->abort(); }
            });
            connect(reply, &QNetworkReply::finished, this,
                [this, reply, pending, id, method, url, body, headers, done, redirects, deadline, generation] {
                    replies_.remove(reply);
                    reply->deleteLater();
                    if (pending->settled) return;
                    pending->settled = true;
                    if (generation != generation_ || !enabled_ || !sources_.contains(id)) { done("cancelled", {}, {}); return; }
                    int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    if (status >= 300 && status < 400) {
                        QUrl next = url.resolved(reply->header(QNetworkRequest::LocationHeader).toUrl());
                        if (redirects >= 3 || !isSameOrigin(next, url)) { done("redirect-refused", {}, {}); return; }
                        request(id, method, next, body, headers, done, redirects + 1, deadline); return;
                    }
                    if (status == 401 || status == 403) { done("auth-error", {}, {}); return; }
                    if (status == 412) { done("conflict", {}, {}); return; }
                    if (status == 501) { done("not-implemented", {}, {}); return; }
                    if (reply->property("calendarTooLarge").toBool()) { done("too-large", {}, {}); return; }
                    if (reply->error() != QNetworkReply::NoError || status < 200 || status >= 300) {
                        done(reply->error() == QNetworkReply::TimeoutError ? "timeout" : "network-error", {}, {}); return;
                    }
                    QByteArray bytes = reply->readAll();
                    if (bytes.size() > SourceLimit) { done("too-large", {}, {}); return; }
                    done({}, bytes, reply->rawHeader("ETag"));
                });
        });
}

void Sources::refreshRemote(const QString &id) {
    if (!enabled_ || !sources_.contains(id) || loading_.contains(id)) return;
    loading_.insert(id);
    Source source = sources_.value(id);
    if (source.kind == "ics-url") { refreshRemoteWithPassword(id, {}); return; }
    const quint64 generation = generation_;
    lookupPassword(source.url, source.user, [this, id, generation](QString error, QString password) {
        if (generation != generation_ || !enabled_ || !sources_.contains(id)) return;
        if (!error.isEmpty() || password.isEmpty()) { sources_[id].error = passwordError(error); emit changed(); completeLoad(id); return; }
        refreshRemoteWithPassword(id, password);
    });
}

void Sources::refreshRemoteWithPassword(const QString &id, const QString &password) {
    if (!enabled_ || !sources_.contains(id)) return;
    Source source = sources_.value(id);
    QMap<QByteArray, QByteArray> headers;
    if (source.kind == "caldav") {
        headers.insert("Authorization", "Basic " + (source.user + ":" + password).toUtf8().toBase64());
        headers.insert("Content-Type", "application/xml; charset=utf-8");
    }
    // Parses a response on the worker pool, applies it here, then continues
    // the chain. A load belongs to the configuration generation that started
    // it: once a reconfiguration supersedes it, the whole chain stops, at
    // entry and again after the off-loop parse, so no continuation of an old
    // load ever reads or changes the new configuration's source of the same ID.
    const quint64 generation = generation_;
    auto accept = [this, id, generation](QString error, QByteArray bytes, std::function<void()> then) {
        if (generation != generation_) return;
        if (error == "cancelled" || !sources_.contains(id)) { then(); return; }
        const QString kind = sources_[id].kind, url = sources_[id].url;
        offload([error, bytes, kind, url] {
            Loaded result;
            result.error = error;
            if (!error.isEmpty()) return result;
            if (kind != "caldav") {
                auto parsed = parse(bytes);
                result.error = parsed.error;
                if (parsed.error.isEmpty()) result.entries = parsed.entries;
                return result;
            }
            for (const auto &member : calendarMembers(bytes)) {
                auto parsed = parse(member.data);
                if (!parsed.error.isEmpty()) { result.error = parsed.error; break; }
                auto memberUrl = QUrl(url).resolved(QUrl(member.href));
                if (!isSameOrigin(memberUrl, QUrl(url))) { result.error = "redirect-refused"; break; }
                for (const auto &entry : parsed.entries) {
                    result.entries.append(entry);
                    result.members.insert(entry.uid, {memberUrl.toString(), member.etag, member.data});
                }
            }
            if (result.entries.size() > ComponentLimit) result.error = "too-many-components";
            if (!result.error.isEmpty()) { result.entries.clear(); result.members.clear(); }
            return result;
        }, [this, id, generation, then](const Loaded &loaded) {
            if (generation != generation_) return;
            if (!sources_.contains(id)) { then(); return; }
            auto &source = sources_[id];
            source.error = loaded.error;
            if (loaded.error.isEmpty()) {
                source.entries = loaded.entries;
                if (source.kind == "caldav") source.members = loaded.members;
            }
            emit changed();
            then();
        });
    };
    // Every chain below ends in settle(), or in finish() after its last accept.
    auto finish = [this, id, generation] { if (generation == generation_) completeLoad(id); };
    auto settle = [accept, finish](QString error, QByteArray bytes, QByteArray) { accept(error, bytes, finish); };
    if (source.kind == "ics-url") { request(id, "GET", QUrl(source.url), {}, {}, settle); return; }
    QDate today = QDate::currentDate();
    QTimeZone zone = QTimeZone::systemTimeZone();
    QByteArray rangeStart = QDateTime(today.addDays(-7), QTime(0, 0), zone).toUTC().toString("yyyyMMdd'T'HHmmss'Z'").toUtf8();
    QByteArray rangeEnd = QDateTime(today.addDays(15), QTime(0, 0), zone).toUTC().toString("yyyyMMdd'T'HHmmss'Z'").toUtf8();
    QByteArray query = "<?xml version=\"1.0\"?><c:calendar-query xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:d=\"DAV:\"><d:prop><d:getetag/><c:calendar-data/></d:prop><c:filter><c:comp-filter name=\"VCALENDAR\"><c:comp-filter name=\"VEVENT\"><c:time-range start=\""
        + rangeStart + "\" end=\"" + rangeEnd + "\"/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>";
    headers.insert("Depth", "1");
    request(id, "REPORT", QUrl(source.url), query, headers,
        [this, id, generation, headers, accept, settle, finish, query](QString error, QByteArray bytes, QByteArray etag) {
            if (generation != generation_) return;
            if (error.isEmpty()) {
                accept(error, bytes, [this, id, generation, headers, accept, finish, query] {
                    if (generation != generation_ || !sources_.contains(id)) return;
                    // A malformed event member fails the load; the reminder query
                    // must not overwrite that error with its own success.
                    if (!sources_[id].error.isEmpty()) { finish(); return; }
                    auto events = sources_[id].entries;
                    auto members = sources_[id].members;
                    QByteArray todos = query;
                    todos.replace("VEVENT", "VTODO");
                    request(id, "REPORT", QUrl(sources_[id].url), todos, headers,
                        [this, id, generation, accept, finish, events, members](QString todoError, QByteArray todoBytes, QByteArray) {
                            if (generation != generation_) return;
                            accept(todoError, todoError.isEmpty() ? todoBytes : QByteArray(), [this, id, generation, finish, events, members, todoError] {
                                if (generation != generation_) return;
                                if (todoError.isEmpty() && sources_.contains(id) && sources_[id].error.isEmpty()) {
                                    sources_[id].entries += events;
                                    for (auto it = members.begin(); it != members.end(); ++it) sources_[id].members.insert(it.key(), it.value());
                                    emit changed();
                                }
                                finish();
                            });
                        });
                });
                return;
            }
            if (error != "not-implemented") { settle(error, bytes, etag); return; }
            auto next = headers; next.insert("Depth", "1");
            request(id, "PROPFIND", QUrl(sources_.value(id).url), "<d:propfind xmlns:d=\"DAV:\"><d:prop><d:getetag/></d:prop></d:propfind>", next,
                [this, id, generation, headers, settle](QString propError, QByteArray list, QByteArray) {
                    if (generation != generation_) return;
                    if (!propError.isEmpty()) { settle(propError, {}, {}); return; }
                    QStringList hrefs = memberHrefs(list);
                    QByteArray multi = "<c:calendar-multiget xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:d=\"DAV:\"><d:prop><d:getetag/><c:calendar-data/></d:prop>";
                    for (const auto &href : hrefs) {
                        if (href.endsWith('/')) continue;
                        multi += "<d:href>" + href.toHtmlEscaped().toUtf8() + "</d:href>";
                    }
                    if (!multi.contains("<d:href>")) { settle("invalid-response", {}, {}); return; }
                    multi += "</c:calendar-multiget>";
                    request(id, "REPORT", QUrl(sources_.value(id).url), multi, headers, settle);
                });
        });
}

void Sources::completeLoad(const QString &id) {
    loading_.remove(id);
    const auto waiters = loadWaiters_.take(id);
    const QString error = sources_.value(id).error;
    for (const auto &waiter : waiters) waiter(error);
}

void Sources::test(const QString &sourceId, const std::function<void(QString)> &done) {
    if (!enabled_ || !sources_.contains(sourceId)) { done("not-found"); return; }
    auto &source = sources_[sourceId];
    if (source.kind == "file" || source.kind == "vdir") { loadWaiters_[sourceId].append(done); loadLocal(source); return; }
    loadWaiters_[sourceId].append(done);
    refreshRemote(sourceId);
}

void Sources::buildWindow(const QDateTime &from, const QDateTime &until) const {
    cache_ = {};
    cache_.valid = true;
    cache_.from = from;
    cache_.until = until;
    ++windowBuilds_;
    auto ids = sources_.keys();
    std::sort(ids.begin(), ids.end());
    // One bound across every source, so many accepted sources cannot make a
    // window larger than one frame-paged view needs. The source whose item
    // crossed it, and every source after it, report window-limit.
    qint64 bytes = 0;
    bool full = false;
    for (const auto &id : ids) {
        if (full) { cache_.windowLimited.insert(id); continue; }
        const auto &source = sources_[id];
        WindowStats stats;
        visitWindow(source.entries, from, until, source.id, source.color, [&](const QJsonObject &item) {
            int size = Island::encodeFrame(item).size();
            if (size > 48000) return true;
            if (cache_.items.size() >= WindowItemLimit || bytes + size > WindowByteLimit) {
                full = true;
                return false;
            }
            cache_.items.append(item);
            cache_.sizes.append(size);
            bytes += size;
            return true;
        }, &stats);
        if (stats.limited) cache_.limited.insert(id);
        if (full) cache_.windowLimited.insert(id);
    }
}

QJsonObject Sources::page(const QDateTime &from, const QDateTime &until, int offset) const {
    if (!cache_.valid || cache_.from != from || cache_.until != until) buildWindow(from, until);
    QJsonArray selected, errors;
    auto ids = sources_.keys();
    std::sort(ids.begin(), ids.end());
    for (const auto &id : ids) {
        QString code = sources_[id].error;
        if (code.isEmpty() && cache_.limited.contains(id)) code = "recurrence-limit";
        if (code.isEmpty() && cache_.windowLimited.contains(id)) code = "window-limit";
        if (!code.isEmpty()) errors.append(QJsonObject{{"sourceId", id}, {"code", code}});
    }
    // Leave headroom for JSON escaping and the envelope under the 64 KiB cap.
    int cursor = qMax(0, offset), bytes = 0;
    for (; cursor < cache_.items.size(); ++cursor) {
        if (!selected.isEmpty() && bytes + cache_.sizes[cursor] > 48000) break;
        selected.append(cache_.items[cursor]);
        bytes += cache_.sizes[cursor];
    }
    return {{"items", selected}, {"errors", errors}, {"nextOffset", cursor < cache_.items.size() ? cursor : -1}};
}

void Sources::setCompleted(const QString &sourceId, const QString &uid, bool completed,
                           const std::function<void(QString)> &done) {
    if (!enabled_ || !sources_.contains(sourceId)) { done("unavailable"); return; }
    auto &source = sources_[sourceId];
    if (source.kind == "file" || source.kind == "ics-url") { done("read-only"); return; }
    auto member = source.members.value(uid);
    if (source.kind == "vdir") {
        if (member.url.isEmpty()) { done("not-found"); return; }
        QFile file(member.url);
        if (!file.open(QIODevice::ReadOnly)) { done("not-found"); return; }
        QByteArray raw = file.read(SourceLimit + 1);
        file.close();
        if (raw.size() > SourceLimit) { done("too-large"); return; }
        // Refuse to overwrite an edit made after the window was read.
        if (fileStamp(member.url) != member.etag) { done("conflict"); return; }
        QByteArray updated = rewriteTodo(raw, uid, completed);
        if (updated.isEmpty()) { done("not-found"); return; }
        QSaveFile out(member.url);
        if (!out.open(QIODevice::WriteOnly) || out.write(updated) != updated.size()) { done("write-error"); return; }
        if (fileStamp(member.url) != member.etag) { out.cancelWriting(); done("conflict"); return; }
        if (!out.commit()) { done("write-error"); return; }
        loadLocal(source); done("ok"); return;
    }
    if (member.etag.isEmpty()) { done("conflict"); return; }
    // The ETag guards against overwriting a concurrent CalDAV edit.
    QByteArray updated = rewriteTodo(member.raw, uid, completed);
    if (updated.isEmpty()) { done("not-found"); return; }
    const quint64 generation = generation_;
    lookupPassword(source.url, source.user,
        [this, sourceId, member, updated, done, generation](QString error, QString password) {
            if (generation != generation_ || !enabled_ || !sources_.contains(sourceId)) { done("cancelled"); return; }
            if (!error.isEmpty() || password.isEmpty()) { done(passwordError(error)); return; }
            const auto &source = sources_[sourceId];
            QMap<QByteArray, QByteArray> headers{{"If-Match", member.etag.toUtf8()}, {"Content-Type", "text/calendar"},
                {"Authorization", "Basic " + (source.user + ":" + password).toUtf8().toBase64()}};
            request(sourceId, "PUT", QUrl(member.url), updated, headers,
                [this, sourceId, done, generation](QString error, QByteArray, QByteArray) {
                    // A write that lands after a reconfiguration still reports
                    // its result, but never refreshes the new configuration.
                    if (error.isEmpty() && generation == generation_) refreshRemote(sourceId);
                    done(error.isEmpty() ? "ok" : error);
                });
        });
}
}
