#pragma once
#include <QByteArray>
#include <QImage>
#include <QString>
#include "image-limits.h"

// The image decoders the artwork decoder child runs. They need only Qt Core
// and Gui, so the child links nothing else (no network or D-Bus stack).
namespace Island {
// Remote artwork: a 256 px result.
QImage decodeArtwork(const QByteArray &bytes, const QByteArray &mime, QString *error);
// Local files for the shelf: larger inputs, a 128 px result.
QImage decodeThumbnail(const QByteArray &bytes, const QByteArray &mime, QString *error);
// A player's local cover accepts a full-size scan but keeps artwork output size.
QImage decodeLocalArtwork(const QByteArray &bytes, const QByteArray &mime, QString *error);
// A freedesktop cache entry, which other applications may have written: a
// PNG of at most 1 MiB and 256 px a side. Runs only in the decoder child.
// Returns fresh pixels at most 128 px a side carrying only Thumb::URI and
// Thumb::MTime, or a null image.
QImage sanitizeCachedThumbnail(const QByteArray &bytes, QString *error);
}
