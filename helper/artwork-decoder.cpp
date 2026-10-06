#include "image-decode.h"
#include <QBuffer>
#include <QCoreApplication>
#include <QFile>
#include <QRegularExpression>
#include <algorithm>
#include <csignal>
#include <sys/resource.h>
#include <unistd.h>

int main(int argc, char **argv) {
    // No network or filesystem input is accepted. The parent supplies bounded
    // bytes on stdin and kills this process at its total artwork-job deadline.
    const rlimit addressLimit{256 * 1024 * 1024, 256 * 1024 * 1024};
    const rlimit cpuLimit{2, 2};
    const rlimit coreLimit{0, 0};
    if (setrlimit(RLIMIT_AS, &addressLimit) || setrlimit(RLIMIT_CPU, &cpuLimit)
        || setrlimit(RLIMIT_CORE, &coreLimit)) return 2;
    std::signal(SIGPIPE, SIG_IGN);
    // Qt image scaling uses its own GUI pool, not QThreadPool::globalInstance.
    // Its worker stacks/allocator arenas can exhaust the address-space cap and
    // leave scaling waiting for work that could not start. Decode serially in
    // this already isolated child; never relax the process resource limits.
    qputenv("QT_NO_GUI_THREADPOOL", "1");
    QCoreApplication app(argc, argv);
    // "<mime>" decodes remote artwork; "<mime> --local" decodes a player's
    // local cover at artwork size; "<mime> --thumbnail <uri> <mtime>"
    // decodes a local shelf file with the thumbnail limits and stamps the
    // freedesktop keys; "image/png --cached-thumbnail <uri> <mtime>" checks
    // and re-encodes a shared cache entry whose keys must match; "--measure"
    // reports resource use. The helper decodes nothing itself: this child's
    // PNG is the finished thumbnail.
    const auto arguments = app.arguments();
    const bool measure = arguments.size() == 3 && arguments[2] == "--measure";
    const bool thumbnail = arguments.size() == 5 && arguments[2] == "--thumbnail";
    const bool cached = arguments.size() == 5 && arguments[2] == "--cached-thumbnail";
    const bool local = arguments.size() == 3 && arguments[2] == "--local";
    if (arguments.size() != 2 && !measure && !thumbnail && !cached && !local) return 2;
    const QString uri = thumbnail || cached ? arguments[3] : QString();
    const QString mtime = thumbnail || cached ? arguments[4] : QString();
    static const QRegularExpression digits("^[0-9]{1,20}$");
    if ((thumbnail || cached) && (uri.isEmpty() || uri.size() > 4096 || !digits.match(mtime).hasMatch())) return 2;
    const qsizetype inputLimit = thumbnail || local ? Island::ThumbnailInputLimit
        : cached ? Island::CachedThumbnailLimit : Island::ArtworkInputLimit;
    QFile input;
    if (!input.open(STDIN_FILENO, QIODevice::ReadOnly)) return 2;
    QByteArray bytes;
    while (true) {
        const auto chunk = input.read(std::min<qint64>(1024 * 1024, inputLimit + 1 - bytes.size()));
        if (chunk.isEmpty()) break;
        bytes += chunk;
        if (bytes.size() > inputLimit) return 3;
    }
    QString error;
    const auto mime = app.arguments()[1].toLatin1();
    auto image = cached ? (mime == "image/png" ? Island::sanitizeCachedThumbnail(bytes, &error) : QImage())
        : thumbnail ? Island::decodeThumbnail(bytes, mime, &error)
        : local ? Island::decodeLocalArtwork(bytes, mime, &error) : Island::decodeArtwork(bytes, mime, &error);
    if (image.isNull()) { fprintf(stderr, "%s\n", qPrintable(error)); return 3; }
    if (cached && (image.text("Thumb::URI") != uri || image.text("Thumb::MTime") != mtime)) {
        fprintf(stderr, "thumb-stale\n");
        return 3;
    }
    if (thumbnail) {
        image.setText("Thumb::URI", uri);
        image.setText("Thumb::MTime", mtime);
    }
    QByteArray encoded;
    QBuffer buffer(&encoded);
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "PNG") || encoded.size() > 512 * 1024) return 3;
    QFile output;
    if (!output.open(STDOUT_FILENO, QIODevice::WriteOnly) || output.write(encoded) != encoded.size() || !output.flush()) return 4;
    if (measure) {
        rusage usage {};
        if (::getrusage(RUSAGE_SELF, &usage)) return 4;
        fprintf(stderr, "decoder-resource peak-rss-kib=%ld user-us=%ld system-us=%ld\n",
            usage.ru_maxrss, usage.ru_utime.tv_sec * 1000000 + usage.ru_utime.tv_usec,
            usage.ru_stime.tv_sec * 1000000 + usage.ru_stime.tv_usec);
    }
    return 0;
}
