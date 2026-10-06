#pragma once
#include <QtGlobal>

// Byte limits shared by the helper (Qt Core only) and the decoder child.
namespace Island {
// Remote artwork: at most 1 MiB of PNG or JPEG.
inline constexpr qsizetype ArtworkInputLimit = 1024 * 1024;
// Local files for the shelf: larger inputs, a 128 px result.
inline constexpr qsizetype ThumbnailInputLimit = 32 * 1024 * 1024;
// A freedesktop cache entry: a PNG of at most 1 MiB and 256 px a side.
inline constexpr qsizetype CachedThumbnailLimit = 1024 * 1024;
}
