#pragma once
#include <QByteArray>
#include <QHostAddress>
#include <QObject>
#include <QPointer>
#include <QSslSocket>
#include <QTimer>
#include <QUrl>
#include "image-limits.h"

namespace Island {
// Remote artwork policy and the HTTPS fetch itself. The fetch runs only in
// the short-lived nookisle-artwork-fetch child, so the TLS stack, its
// certificate store and the resolver thread die with each job instead of
// staying resident in the helper.
inline constexpr qsizetype ArtworkHeaderLimit = 16 * 1024;
inline constexpr qsizetype ArtworkWireLimit = ArtworkInputLimit + 64 * 1024;
inline constexpr qsizetype LyricsInputLimit = 262144;
inline constexpr qsizetype LyricsWireLimit = LyricsInputLimit + 64 * 1024;
// Shared production parsers are independently testable without opening a
// private-network exception in the downloader.
struct ArtworkResponse {
    QByteArray bytes, mime;
    QUrl redirect;
    QString error;
};
ArtworkResponse parseArtworkResponse(const QByteArray &response);
ArtworkResponse parseLyricsResponse(const QByteArray &response);
bool publicArtworkAddress(const QHostAddress &address);
bool validArtworkUrl(const QUrl &url);

// One fetch: resolve, refuse non-public answers, connect to the checked
// address with TLS verified for the original host, follow at most two
// redirects under the same policy, and bound the headers and body.
class ArtworkFetch final : public QObject {
    Q_OBJECT
public:
    enum class Mode { Artwork, Lyrics };
    explicit ArtworkFetch(Mode mode = Mode::Artwork, QObject *parent = nullptr);
    ~ArtworkFetch() override;
    void start(const QUrl &url);
signals:
    void fetched(const QByteArray &bytes, const QByteArray &mime);
    void failed(const QString &code);
private:
    Mode mode_ = Mode::Artwork;
    QPointer<QSslSocket> socket_;
    QTimer deadline_;
    QByteArray response_;
    QUrl url_;
    QHostAddress pinned_;
    quint64 serial_ = 0;
    int lookup_ = -1, redirects_ = 0;
    bool active_ = false;
    bool busy() const { return active_; }
    qsizetype inputLimit() const { return mode_ == Mode::Lyrics ? LyricsInputLimit : ArtworkInputLimit; }
    qsizetype wireLimit() const { return mode_ == Mode::Lyrics ? LyricsWireLimit : ArtworkWireLimit; }
    void resolveUrl();
    void connectAddress(const QHostAddress &address);
    void consume();
    void finishResponse();
    void stopTransport();
    void fail(const QString &code);
    void publish(const QByteArray &bytes, const QByteArray &mime);
};
}
