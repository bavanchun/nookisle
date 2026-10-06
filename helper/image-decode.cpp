#include "image-decode.h"
#include <QBuffer>
#include <QImageReader>
#include <QTransform>
#include <QtEndian>
#include <algorithm>
#include <cstring>
#include <limits>

namespace {
// Remote artwork is small by nature. Local shelf thumbnails come from photos,
// so they accept larger inputs but produce a smaller image; both decode only
// in the resource-limited child.
struct DecodeLimits {
    qsizetype input;
    int side;
    qint64 pixels;
    int output;
    int allocationMiB;
};
constexpr DecodeLimits ArtworkLimits{Island::ArtworkInputLimit, 2048, 1048576, 256, 8};
constexpr DecodeLimits ThumbnailLimits{Island::ThumbnailInputLimit, 8192, 16 * 1024 * 1024, 128, 80};
constexpr DecodeLimits LocalArtworkLimits{Island::ThumbnailInputLimit, 8192, 16 * 1024 * 1024, 256, 80};
bool sizeAllowed(const QSize &size, const DecodeLimits &limits = ArtworkLimits) {
    return size.width() > 0 && size.height() > 0 && size.width() <= limits.side && size.height() <= limits.side
        && qint64(size.width()) * size.height() <= limits.pixels;
}
quint32 be32(const QByteArray &bytes, qsizetype offset) {
    return qFromBigEndian<quint32>(reinterpret_cast<const uchar *>(bytes.constData() + offset));
}
// Discard attacker-controlled compressed metadata before any image plugin
// sees it. Never allow animation, embedded image collections, or trailing data.
QByteArray cleanPng(const QByteArray &bytes, const DecodeLimits &limits) {
    const QByteArray signature = QByteArray::fromHex("89504e470d0a1a0a");
    if (!bytes.startsWith(signature)) return {};
    QByteArray clean = signature;
    bool header = false, data = false;
    qsizetype offset = 8;
    while (offset + 12 <= bytes.size()) {
        const quint32 length = be32(bytes, offset);
        if (length > quint32(bytes.size() - offset - 12)) return {};
        const QByteArray type = bytes.mid(offset + 4, 4);
        if (!header) {
            if (type != "IHDR" || length != 13) return {};
            const quint32 width = be32(bytes, offset + 8), height = be32(bytes, offset + 12);
            if (width > quint32(limits.side) || height > quint32(limits.side)
                || !sizeAllowed(QSize(int(width), int(height)), limits)) return {};
            header = true;
        } else if (type == "IHDR") return {};
        if (type == "acTL" || type == "fcTL" || type == "fdAT") return {};
        if (type == "IDAT") data = true;
        if (type == "IHDR" || type == "PLTE" || type == "tRNS" || type == "IDAT" || type == "IEND")
            clean.append(bytes.constData() + offset, length + 12);
        else if (!(type[0] & 0x20)) return {}; // Unknown critical chunk.
        offset += length + 12;
        if (type == "IEND") return length == 0 && data && offset == bytes.size() ? clean : QByteArray();
    }
    return {};
}
QByteArray cleanJpeg(const QByteArray &bytes, const DecodeLimits &limits) {
    if (!bytes.startsWith(QByteArray::fromHex("ffd8"))) return {};
    QByteArray clean = bytes.left(2);
    qsizetype offset = 2;
    bool dimensions = false, scan = false;
    while (offset < bytes.size()) {
        if (uchar(bytes[offset++]) != 0xff) return {};
        while (offset < bytes.size() && uchar(bytes[offset]) == 0xff) ++offset;
        if (offset >= bytes.size()) return {};
        const uchar marker = uchar(bytes[offset++]);
        if (marker == 0xd9) {
            clean.append(QByteArray::fromHex("ffd9"));
            return dimensions && scan && offset == bytes.size() ? clean : QByteArray();
        }
        if (marker == 0 || marker == 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker == 1) return {};
        if (offset + 2 > bytes.size()) return {};
        const auto length = qFromBigEndian<quint16>(reinterpret_cast<const uchar *>(bytes.constData() + offset));
        if (length < 2 || length > bytes.size() - offset) return {};
        if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
            if (dimensions || length < 8 || uchar(bytes[offset + 2]) != 8) return {};
            const int height = qFromBigEndian<quint16>(reinterpret_cast<const uchar *>(bytes.constData() + offset + 3));
            const int width = qFromBigEndian<quint16>(reinterpret_cast<const uchar *>(bytes.constData() + offset + 5));
            if (!sizeAllowed(QSize(width, height), limits)) return {};
            dimensions = true;
        } else if (marker >= 0xc0 && marker <= 0xcf && marker != 0xc4) return {};
        if (marker == 0xe2 && bytes.mid(offset + 2, 4) == QByteArray("MPF\0", 4)) return {};
        if (!(marker >= 0xe0 && marker <= 0xef) && marker != 0xfe) {
            clean.append(char(0xff)); clean.append(char(marker));
            clean.append(bytes.constData() + offset, length);
        }
        offset += length;
        if (marker == 0xda) {
            if (!dimensions) return {};
            scan = true;
            const qsizetype start = offset;
            while (offset < bytes.size()) {
                if (uchar(bytes[offset]) != 0xff) { ++offset; continue; }
                if (offset + 1 >= bytes.size()) return {};
                const uchar next = uchar(bytes[offset + 1]);
                if (next == 0 || (next >= 0xd0 && next <= 0xd7)) { offset += 2; continue; }
                break;
            }
            clean.append(bytes.constData() + start, offset - start);
        }
    }
    return {};
}
// Read only the bounded TIFF orientation tag before cleanJpeg removes APP1.
// The image plugin never receives the rest of the untrusted EXIF payload.
int jpegOrientation(const QByteArray &bytes) {
    qsizetype offset = 2;
    while (offset + 4 <= bytes.size() && uchar(bytes[offset++]) == 0xff) {
        while (offset < bytes.size() && uchar(bytes[offset]) == 0xff) ++offset;
        if (offset >= bytes.size()) break;
        const uchar marker = uchar(bytes[offset++]);
        if (marker == 0xda || marker == 0xd9 || offset + 2 > bytes.size()) break;
        const auto length = qFromBigEndian<quint16>(reinterpret_cast<const uchar *>(bytes.constData() + offset));
        if (length < 2 || length > bytes.size() - offset) break;
        if (marker == 0xe1 && length >= 16 && bytes.mid(offset + 2, 6) == QByteArray("Exif\0\0", 6)) {
            const auto tiff = bytes.mid(offset + 8, length - 8);
            if (tiff.size() < 8) return 1;
            const bool little = tiff.startsWith("II");
            if (!little && !tiff.startsWith("MM")) return 1;
            auto read16 = [&](qsizetype at) -> quint16 {
                const auto *p = reinterpret_cast<const uchar *>(tiff.constData() + at);
                return little ? qFromLittleEndian<quint16>(p) : qFromBigEndian<quint16>(p);
            };
            auto read32 = [&](qsizetype at) -> quint32 {
                const auto *p = reinterpret_cast<const uchar *>(tiff.constData() + at);
                return little ? qFromLittleEndian<quint32>(p) : qFromBigEndian<quint32>(p);
            };
            if (read16(2) != 42) return 1;
            const auto ifd = read32(4);
            if (ifd > quint32(tiff.size() - 2)) return 1;
            const auto count = read16(ifd);
            if (count > 256 || count > (tiff.size() - ifd - 2) / 12) return 1;
            for (quint16 i = 0; i < count; ++i) {
                const qsizetype entry = ifd + 2 + qsizetype(i) * 12;
                if (read16(entry) == 0x0112 && read16(entry + 2) == 3 && read32(entry + 4) == 1) {
                    const auto orientation = read16(entry + 8);
                    return orientation >= 1 && orientation <= 8 ? orientation : 1;
                }
            }
            return 1;
        }
        offset += length;
    }
    return 1;
}
QTransform orientationTransform(int orientation) {
    switch (orientation) {
    case 2: return QTransform(-1, 0, 0, 1, 0, 0);
    case 3: return QTransform(-1, 0, 0, -1, 0, 0);
    case 4: return QTransform(1, 0, 0, -1, 0, 0);
    case 5: return QTransform(0, 1, 1, 0, 0, 0);
    case 6: return QTransform(0, 1, -1, 0, 0, 0);
    case 7: return QTransform(0, -1, -1, 0, 0, 0);
    case 8: return QTransform(0, -1, 1, 0, 0, 0);
    default: return {};
    }
}
}

namespace Island {
static QImage decodeImage(const QByteArray &bytes, const QByteArray &mime, QString *error, const DecodeLimits &limits,
                          bool thumbnail = false) {
    auto reject = [&](const char *code) { if (error) *error = QString::fromLatin1(code); return QImage(); };
    if (bytes.isEmpty() || bytes.size() > limits.input) return reject("art-byte-limit");
    const QByteArray format = mime == "image/png" ? "png" : mime == "image/jpeg" ? "jpeg" : "";
    if (format.isEmpty()) return reject("art-mime");
    const int orientation = thumbnail && format == "jpeg" ? jpegOrientation(bytes) : 1;
    QByteArray clean = format == "png" ? cleanPng(bytes, limits) : cleanJpeg(bytes, limits);
    if (clean.isEmpty()) return reject("art-image-header");
    // Enforce the decoder setting rather than trusting the environment's value.
    QImageReader::setAllocationLimit(limits.allocationMiB);
    if (QImageReader::allocationLimit() <= 0 || QImageReader::allocationLimit() > limits.allocationMiB)
        return reject("art-decoder-limit");
    QBuffer input(&clean);
    input.open(QIODevice::ReadOnly);
    QImageReader reader(&input, format);
    reader.setAutoDetectImageFormat(false);
    reader.setDecideFormatFromContent(false);
    reader.setAutoTransform(false);
    const auto size = reader.size();
    if (!sizeAllowed(size, limits) || reader.supportsAnimation() || reader.imageCount() != 1) return reject("art-dimensions");
    reader.setScaledSize(size.width() > limits.output || size.height() > limits.output
        ? size.scaled(limits.output, limits.output, Qt::KeepAspectRatio) : size);
    auto image = reader.read();
    if (image.isNull() || image.width() > limits.output || image.height() > limits.output || image.sizeInBytes() > 512 * 1024)
        return reject("art-decode");
    if (orientation != 1) image = image.transformed(orientationTransform(orientation), Qt::FastTransformation);
    image = image.convertToFormat(QImage::Format_ARGB32);
    QImage sanitized(image.size(), QImage::Format_ARGB32);
    for (int y = 0; y < image.height(); ++y) std::memcpy(sanitized.scanLine(y), image.constScanLine(y), image.width() * 4);
    if (error) error->clear();
    return sanitized;
}
QImage decodeArtwork(const QByteArray &bytes, const QByteArray &mime, QString *error) {
    return decodeImage(bytes, mime, error, ArtworkLimits);
}
QImage decodeThumbnail(const QByteArray &bytes, const QByteArray &mime, QString *error) {
    return decodeImage(bytes, mime, error, ThumbnailLimits, true);
}
QImage decodeLocalArtwork(const QByteArray &bytes, const QByteArray &mime, QString *error) {
    return decodeImage(bytes, mime, error, LocalArtworkLimits, true);
}
QImage sanitizeCachedThumbnail(const QByteArray &bytes, QString *error) {
    auto reject = [&](const char *code) { if (error) *error = QString::fromLatin1(code); return QImage(); };
    if (bytes.isEmpty() || bytes.size() > CachedThumbnailLimit) return reject("thumb-byte-limit");
    if (!bytes.startsWith(QByteArray::fromHex("89504e470d0a1a0a"))) return reject("thumb-format");
    QImageReader::setAllocationLimit(16);
    QByteArray copy = bytes;
    QBuffer input(&copy);
    input.open(QIODevice::ReadOnly);
    QImageReader reader(&input, "png");
    reader.setAutoDetectImageFormat(false);
    reader.setDecideFormatFromContent(false);
    reader.setAutoTransform(false);
    const auto size = reader.size();
    if (size.width() <= 0 || size.height() <= 0 || size.width() > 256 || size.height() > 256
        || reader.supportsAnimation() || reader.imageCount() > 1) return reject("thumb-dimensions");
    auto image = reader.read();
    if (image.isNull() || image.size() != size) return reject("thumb-decode");
    const auto uri = image.text("Thumb::URI"), mtime = image.text("Thumb::MTime");
    if (uri.isEmpty() || uri.size() > 4096 || mtime.isEmpty() || mtime.size() > 32) return reject("thumb-metadata");
    if (image.width() > 128 || image.height() > 128)
        image = image.scaled(QSize(128, 128), Qt::KeepAspectRatio, Qt::SmoothTransformation);
    image = image.convertToFormat(QImage::Format_ARGB32);
    // Fresh pixels only: no chunk, profile or text of the input survives
    // but the two keys the helper checks.
    QImage clean(image.size(), QImage::Format_ARGB32);
    for (int y = 0; y < image.height(); ++y) std::memcpy(clean.scanLine(y), image.constScanLine(y), image.width() * 4);
    clean.setText("Thumb::URI", uri);
    clean.setText("Thumb::MTime", mtime);
    if (error) error->clear();
    return clean;
}
}
