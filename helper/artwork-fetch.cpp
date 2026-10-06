#include "artwork-fetch.h"
#include <QHash>
#include <QHostInfo>
#include <QNetworkProxy>
#include <QSslConfiguration>
#include <algorithm>
#include <utility>

namespace {
constexpr qsizetype InputLimit = Island::ArtworkInputLimit;
constexpr qsizetype HeaderLimit = Island::ArtworkHeaderLimit;
constexpr qsizetype WireLimit = Island::ArtworkWireLimit;
}

namespace Island {
bool publicArtworkAddress(const QHostAddress &address) {
    bool ipv4 = false;
    const quint32 number = address.toIPv4Address(&ipv4);
    if (ipv4) {
        const QHostAddress v4(number);
        for (const auto &subnet : {"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
                "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16",
                "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"})
            if (v4.isInSubnet(QHostAddress::parseSubnet(QString::fromLatin1(subnet)))) return false;
        return true;
    }
    if (address.protocol() != QAbstractSocket::IPv6Protocol || !address.scopeId().isEmpty()
        || !address.isInSubnet(QHostAddress::parseSubnet("2000::/3"))) return false;
    // Reject documentation, transition/tunnel and special-purpose prefixes;
    // accepting embedded private destinations through NAT64/6to4 is unsafe.
    for (const auto &subnet : {"2001::/23", "2001:db8::/32", "2002::/16", "3fff::/20"})
        if (address.isInSubnet(QHostAddress::parseSubnet(QString::fromLatin1(subnet)))) return false;
    return true;
}
bool validArtworkUrl(const QUrl &url) {
    if (!url.isValid() || url.scheme() != "https" || url.host().isEmpty() || url.port(443) < 1
        || url.port(443) > 65535 || url.authority().contains('@') || !url.userInfo().isEmpty()
        || url.toEncoded().size() > 4096 || url.host().contains('%')) return false;
    QHostAddress literal;
    if (literal.setAddress(url.host())) return publicArtworkAddress(literal);
    const auto host = url.host().toLower();
    return host.contains('.') && !host.endsWith('.') && !host.endsWith(".localhost")
        && !host.endsWith(".local") && !host.endsWith(".internal");
}
ArtworkResponse parseArtworkResponse(const QByteArray &response) {
    ArtworkResponse result;
    auto reject = [&](const char *code) { result.error = QString::fromLatin1(code); return result; };
    if (response.size() > WireLimit) return reject("art-wire-limit");
    const auto separator = response.indexOf("\r\n\r\n");
    if (separator < 0 || separator > HeaderLimit) return reject("art-header-limit");
    auto lines = response.left(separator).split('\n');
    auto status = lines.takeFirst().trimmed().split(' ');
    if (status.size() < 2 || (status[0] != "HTTP/1.1" && status[0] != "HTTP/1.0")) return reject("art-http");
    bool valid = false;
    const int code = status[1].toInt(&valid);
    if (!valid) return reject("art-http");
    QHash<QByteArray, QByteArray> headers;
    for (auto line : lines) {
        if (line.startsWith(' ') || line.startsWith('\t')) return reject("art-header");
        const auto colon = line.indexOf(':');
        if (colon <= 0) return reject("art-header");
        const auto key = line.left(colon).toLower();
        if (headers.contains(key)) return reject("art-header-duplicate");
        headers[key] = line.mid(colon + 1).trimmed();
    }
    if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
        result.redirect = QUrl::fromEncoded(headers.value("location"), QUrl::StrictMode);
        if (!result.redirect.isValid() || result.redirect.isEmpty()) return reject("art-redirect");
        return result;
    }
    if (code != 200) return reject("art-http-status");
    const auto encoding = headers.value("content-encoding").toLower();
    if (!encoding.isEmpty() && encoding != "identity") return reject("art-content-encoding");
    result.mime = headers.value("content-type").split(';').first().trimmed().toLower();
    if (result.mime != "image/png" && result.mime != "image/jpeg") return reject("art-mime");
    const auto body = response.mid(separator + 4);
    const auto transfer = headers.value("transfer-encoding").toLower();
    if (!transfer.isEmpty()) {
        if (transfer != "chunked" || headers.contains("content-length")) return reject("art-transfer-encoding");
        qsizetype offset = 0;
        while (offset < body.size()) {
            const auto end = body.indexOf("\r\n", offset);
            if (end < 0 || end - offset > 128) return reject("art-chunk");
            auto size = body.mid(offset, end - offset).split(';').first();
            if (size.isEmpty() || size.size() > 8) return reject("art-chunk");
            for (char ch : size) if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'))) return reject("art-chunk");
            const auto count = size.toULongLong(&valid, 16);
            if (!valid || count > quint64(InputLimit - result.bytes.size())) return reject("art-byte-limit");
            offset = end + 2;
            if (!count) {
                if (body.mid(offset) != "\r\n") return reject("art-chunk-trailer");
                return result;
            }
            if (count + 2 > quint64(body.size() - offset) || body.mid(offset + count, 2) != "\r\n") return reject("art-chunk");
            result.bytes.append(body.constData() + offset, count);
            offset += count + 2;
        }
        return reject("art-chunk");
    }
    if (body.size() > InputLimit) return reject("art-byte-limit");
    if (headers.contains("content-length")) {
        const auto count = headers["content-length"].toULongLong(&valid);
        if (!valid || count > quint64(InputLimit) || count != quint64(body.size())) return reject("art-content-length");
    }
    result.bytes = body;
    return result;
}

ArtworkResponse parseLyricsResponse(const QByteArray &response) {
    ArtworkResponse result;
    auto reject = [&](const char *code) { result.error = QString::fromLatin1(code); return result; };
    if (response.size() > LyricsWireLimit) return reject("too-large");
    const auto separator = response.indexOf("\r\n\r\n");
    if (separator < 0 || separator > ArtworkHeaderLimit) return reject("network");
    auto lines = response.left(separator).split('\n');
    auto status = lines.takeFirst().trimmed().split(' ');
    if (status.size() < 2 || (status[0] != "HTTP/1.1" && status[0] != "HTTP/1.0")) return reject("network");
    bool valid = false;
    const int code = status[1].toInt(&valid);
    if (!valid) return reject("network");
    QHash<QByteArray, QByteArray> headers;
    for (auto line : lines) {
        if (line.startsWith(' ') || line.startsWith('\t')) return reject("network");
        const auto colon = line.indexOf(':');
        if (colon <= 0) return reject("network");
        const auto key = line.left(colon).toLower();
        if (headers.contains(key)) return reject("network");
        headers[key] = line.mid(colon + 1).trimmed();
    }
    if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
        result.redirect = QUrl::fromEncoded(headers.value("location"), QUrl::StrictMode);
        if (!result.redirect.isValid() || result.redirect.isEmpty()) return reject("network");
        return result;
    }
    if (code != 200 && code != 404) return reject("network");
    const auto encoding = headers.value("content-encoding").toLower();
    if (!encoding.isEmpty() && encoding != "identity") return reject("network");
    if (code == 200) {
        const auto mime = headers.value("content-type").split(';').first().trimmed().toLower();
        if (mime != "application/json") return reject("network");
    }
    result.mime = QByteArray::number(code);
    const auto body = response.mid(separator + 4);
    const auto transfer = headers.value("transfer-encoding").toLower();
    if (!transfer.isEmpty()) {
        if (transfer != "chunked" || headers.contains("content-length")) return reject("network");
        qsizetype offset = 0;
        while (offset < body.size()) {
            const auto end = body.indexOf("\r\n", offset);
            if (end < 0 || end - offset > 128) return reject("network");
            auto size = body.mid(offset, end - offset).split(';').first();
            if (size.isEmpty() || size.size() > 8) return reject("network");
            for (char ch : size) if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'))) return reject("network");
            const auto count = size.toULongLong(&valid, 16);
            if (!valid || count > quint64(LyricsInputLimit - result.bytes.size())) return reject("too-large");
            offset = end + 2;
            if (!count) {
                if (body.mid(offset) != "\r\n") return reject("network");
                return result;
            }
            if (count + 2 > quint64(body.size() - offset) || body.mid(offset + count, 2) != "\r\n") return reject("network");
            result.bytes.append(body.constData() + offset, count);
            offset += count + 2;
        }
        return reject("network");
    }
    if (body.size() > LyricsInputLimit) return reject("too-large");
    if (headers.contains("content-length")) {
        const auto count = headers["content-length"].toULongLong(&valid);
        if (!valid || count > quint64(LyricsInputLimit)) return reject("too-large");
        if (count != quint64(body.size())) return reject("network");
    }
    result.bytes = body;
    return result;
}

ArtworkFetch::ArtworkFetch(Mode mode, QObject *parent) : QObject(parent), mode_(mode) {
    deadline_.setSingleShot(true);
    deadline_.setTimerType(Qt::PreciseTimer);
    // A backstop only: the helper's own job deadline kills this child first.
    deadline_.setInterval(6000);
    connect(&deadline_, &QTimer::timeout, this, [this] {
        fail(mode_ == Mode::Lyrics ? "timeout" : "art-timeout");
    });
}
ArtworkFetch::~ArtworkFetch() { stopTransport(); }
void ArtworkFetch::start(const QUrl &url) {
    stopTransport();
    ++serial_;
    active_ = true;
    redirects_ = 0;
    url_ = url.adjusted(QUrl::RemoveFragment);
    deadline_.start();
    resolveUrl();
}
void ArtworkFetch::stopTransport() {
    if (lookup_ >= 0) QHostInfo::abortHostLookup(std::exchange(lookup_, -1));
    if (socket_) {
        socket_->disconnect(this);
        socket_->abort();
        socket_->deleteLater();
        socket_ = nullptr;
    }
    response_.clear();
}
void ArtworkFetch::fail(const QString &code) {
    if (!active_) return;
    active_ = false;
    ++serial_;
    deadline_.stop();
    stopTransport();
    emit failed(code);
}
void ArtworkFetch::publish(const QByteArray &bytes, const QByteArray &mime) {
    active_ = false;
    deadline_.stop();
    emit fetched(bytes, mime);
}
void ArtworkFetch::resolveUrl() {
    if (!validArtworkUrl(url_)) { fail(mode_ == Mode::Lyrics ? "network" : "art-url-policy"); return; }
    QHostAddress literal;
    if (literal.setAddress(url_.host())) { connectAddress(literal); return; }
    const auto serial = serial_;
    lookup_ = QHostInfo::lookupHost(url_.host(), this, [this, serial](const QHostInfo &info) {
        if (serial != serial_ || !busy()) return;
        lookup_ = -1;
        if (info.error() != QHostInfo::NoError || info.addresses().isEmpty()) {
            fail(mode_ == Mode::Lyrics ? "network" : "art-dns");
            return;
        }
        // Mixed public/private answers are rejected in their entirety.
        for (const auto &address : info.addresses())
            if (!publicArtworkAddress(address)) {
                fail(mode_ == Mode::Lyrics ? "network" : "art-address-policy");
                return;
            }
        connectAddress(info.addresses().first());
    });
}
void ArtworkFetch::connectAddress(const QHostAddress &address) {
    if (!publicArtworkAddress(address)) { fail(mode_ == Mode::Lyrics ? "network" : "art-address-policy"); return; }
    pinned_ = address;
    auto *socket = new QSslSocket(this);
    socket_ = socket;
    socket->setProxy(QNetworkProxy::NoProxy);
    socket->setReadBufferSize(16 * 1024);
    socket->setPeerVerifyMode(QSslSocket::VerifyPeer);
    auto ssl = socket->sslConfiguration();
    ssl.setProtocol(QSsl::TlsV1_2OrLater);
    socket->setSslConfiguration(ssl);
    connect(socket, &QSslSocket::encrypted, this, [this, socket] {
        if (socket != socket_ || !publicArtworkAddress(socket->peerAddress()) || socket->peerAddress() != pinned_) {
            fail(mode_ == Mode::Lyrics ? "network" : "art-peer-policy"); return;
        }
        const auto host = url_.host(QUrl::FullyEncoded).toUtf8();
        QByteArray authority = host.contains(':') ? "[" + host + "]" : host;
        if (url_.port(443) != 443) authority += ':' + QByteArray::number(url_.port());
        auto target = url_.path(QUrl::FullyEncoded).toUtf8();
        if (target.isEmpty()) target = "/";
        if (url_.hasQuery()) target += '?' + url_.query(QUrl::FullyEncoded).toUtf8();
        if (mode_ == Mode::Lyrics) {
            socket->write("GET " + target + " HTTP/1.1\r\nHost: " + authority
                + "\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nLrclib-Client: Nookisle (https://github.com/bavanchun/nookisle)\r\nConnection: close\r\n\r\n");
        } else {
            socket->write("GET " + target + " HTTP/1.1\r\nHost: " + authority
                + "\r\nAccept: image/png, image/jpeg\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n");
        }
    });
    connect(socket, &QSslSocket::readyRead, this, &ArtworkFetch::consume);
    connect(socket, &QSslSocket::disconnected, this, &ArtworkFetch::finishResponse);
    connect(socket, &QSslSocket::errorOccurred, this, [this](QAbstractSocket::SocketError error) {
        if (error != QAbstractSocket::RemoteHostClosedError) fail(mode_ == Mode::Lyrics ? "network" : "art-network");
    });
    connect(socket, &QSslSocket::sslErrors, this, [this] { fail(mode_ == Mode::Lyrics ? "network" : "art-tls"); });
    // Numeric connection target prevents a second DNS resolution. sslPeerName
    // retains hostname certificate verification and SNI for the original host.
    socket->connectToHostEncrypted(address.toString(), quint16(url_.port(443)), url_.host());
}
void ArtworkFetch::consume() {
    if (!socket_ || !busy()) return;
    const auto maxWire = wireLimit();
    const auto maxInput = inputLimit();
    const auto remaining = maxWire - response_.size();
    response_ += socket_->read(std::min<qint64>(16 * 1024, remaining + 1));
    if (response_.size() > maxWire) {
        fail(mode_ == Mode::Lyrics ? "too-large" : "art-wire-limit");
        return;
    }
    const auto header = response_.indexOf("\r\n\r\n");
    if ((header < 0 && response_.size() > ArtworkHeaderLimit) || header > ArtworkHeaderLimit) {
        fail(mode_ == Mode::Lyrics ? "network" : "art-header-limit");
        return;
    }
    if (header >= 0) {
        bool chunked = false;
        for (const auto &line : response_.left(header).split('\n')) {
            const auto lower = line.toLower();
            if (lower.startsWith("content-length:")) {
                bool ok = false;
                const auto length = lower.mid(15).trimmed().toULongLong(&ok);
                if (!ok || length > quint64(maxInput)) {
                    fail(mode_ == Mode::Lyrics ? "too-large" : "art-byte-limit");
                    return;
                }
            }
            if (lower.startsWith("transfer-encoding:")) chunked = true;
        }
        if (!chunked && response_.size() - header - 4 > maxInput) {
            fail(mode_ == Mode::Lyrics ? "too-large" : "art-byte-limit");
            return;
        }
        if (chunked) {
            const auto err = (mode_ == Mode::Lyrics)
                ? parseLyricsResponse(response_).error
                : parseArtworkResponse(response_).error;
            if (err == (mode_ == Mode::Lyrics ? "too-large" : "art-byte-limit")) {
                fail(err);
                return;
            }
        }
    }
    if (socket_->bytesAvailable()) QTimer::singleShot(0, this, &ArtworkFetch::consume);
}
void ArtworkFetch::finishResponse() {
    if (!busy() || !socket_) return;
    while (socket_ && socket_->bytesAvailable()) consume();
    if (!busy()) return;
    const auto result = (mode_ == Mode::Lyrics) ? parseLyricsResponse(response_) : parseArtworkResponse(response_);
    stopTransport();
    if (!result.error.isEmpty()) { fail(result.error); return; }
    if (!result.redirect.isEmpty()) {
        if (++redirects_ > 2) {
            fail(mode_ == Mode::Lyrics ? "network" : "art-redirect-limit");
            return;
        }
        url_ = url_.resolved(result.redirect).adjusted(QUrl::RemoveFragment);
        resolveUrl();
        return;
    }
    publish(result.bytes, result.mime);
}
}
