#include "spectrum-core.h"
#include <algorithm>
#include <cmath>
#include <numbers>
#include <stdexcept>

namespace Island::Spectrum {
namespace {
constexpr double FloorDb = -70.0, CeilingDb = -10.0, GateDb = -65.0;
constexpr double TiltPerOctave = 3.0, Decay = 0.82;
// Quiet hops before the single all-zero line; the hops before it carry the
// decay tail so the bars fall instead of vanishing.
constexpr int QuietHops = 10;
constexpr int FftBits = 10;
static_assert(1 << FftBits == FftSize);

double decibels(double value) { return 20.0 * std::log10(value + 1e-12); }

double checkedRate(double sampleRate) {
    if (!std::isfinite(sampleRate) || sampleRate < 1000.0 || sampleRate > 768000.0)
        throw std::invalid_argument("unsupported sample rate");
    return sampleRate;
}
}

BandEdges bandEdges(double sampleRate, double fMin, double fMax) {
    const double top = std::min(fMax, 0.45 * sampleRate);
    BandEdges edges{};
    for (int k = 0; k <= Bands; ++k) {
        const double frequency = fMin * std::pow(top / fMin, double(k) / Bands);
        edges.bins[k] = int(std::lround(frequency * FftSize / sampleRate));
    }
    // Bin 0 is DC. Merge crowded low bands forward so each keeps at least one
    // bin, then clamp the top edge to Nyquist and pull any collision back down.
    edges.bins[0] = std::max(edges.bins[0], 1);
    for (int k = 1; k <= Bands; ++k) edges.bins[k] = std::max(edges.bins[k], edges.bins[k - 1] + 1);
    edges.bins[Bands] = std::min(edges.bins[Bands], FftSize / 2);
    for (int k = Bands; k-- > 0;) edges.bins[k] = std::min(edges.bins[k], edges.bins[k + 1] - 1);
    return edges;
}

Analyzer::Analyzer(double sampleRate, int fps)
    : sampleRate_(checkedRate(sampleRate)), edges_(bandEdges(sampleRate_)), twiddles_(FftSize / 2),
      work_(FftSize) {
    fps = std::clamp(fps, 1, MaxFps);
    hop_ = std::size_t(std::ceil(sampleRate / fps));
    for (int n = 0; n < FftSize; ++n) {
        // Periodic Hann window, the usual choice for overlapping spectral frames.
        window_[n] = 0.5 * (1.0 - std::cos(2.0 * std::numbers::pi * n / FftSize));
        windowSum_ += window_[n];
        int reversed = 0;
        for (int bit = 0; bit < FftBits; ++bit) reversed |= ((n >> bit) & 1) << (FftBits - 1 - bit);
        reversed_[n] = reversed;
    }
    for (int k = 0; k < FftSize / 2; ++k) twiddles_[k] = std::polar(1.0, -2.0 * std::numbers::pi * k / FftSize);
    for (int b = 0; b < Bands; ++b) {
        const double low = edges_.bins[b] * sampleRate / FftSize;
        const double high = edges_.bins[b + 1] * sampleRate / FftSize;
        // Music falls off with frequency; the tilt makes a typical mix read flat.
        tilt_[b] = TiltPerOctave * std::log2(std::sqrt(low * high) / 1000.0);
    }
}

std::vector<std::string> Analyzer::push(const float *samples, std::size_t count) {
    std::vector<std::string> lines;
    if (!samples) return lines;
    for (std::size_t i = 0; i < count; ++i) {
        // A non-finite sample would poison the FFT and every later frame.
        const float sample = std::isfinite(samples[i]) ? samples[i] : 0.0f;
        ring_[ringPos_] = sample;
        ringPos_ = (ringPos_ + 1) % FftSize;
        hopEnergy_ += double(sample) * sample;
        if (++hopFill_ == hop_) {
            auto line = finishHop();
            if (!line.empty()) lines.push_back(std::move(line));
        }
    }
    return lines;
}

std::string Analyzer::finishHop() {
    const double rms = std::sqrt(hopEnergy_ / double(hop_));
    hopEnergy_ = 0;
    hopFill_ = 0;
    if (decibels(rms) >= GateDb) {
        quiet_ = 0;
        armed_ = true;
        return formatLine(analyse());
    }
    if (quiet_ >= QuietHops) return {};  // The zero line has already been sent.
    if (++quiet_ == QuietHops) {
        armed_ = false;
        smoothed_.fill(0.0);
        return formatLine({});
    }
    // Only a tail after emitted music; a stream that starts silent stays quiet.
    return armed_ ? formatLine(analyse()) : std::string();
}

std::array<int, Bands> Analyzer::analyse() {
    // ringPos_ is the oldest sample, so the window runs in time order.
    for (int n = 0; n < FftSize; ++n)
        work_[reversed_[n]] = ring_[(ringPos_ + n) % FftSize] * window_[n];
    for (int size = 2; size <= FftSize; size <<= 1) {
        const int half = size / 2, step = FftSize / size;
        for (int start = 0; start < FftSize; start += size) {
            for (int k = 0; k < half; ++k) {
                const auto twisted = twiddles_[k * step] * work_[start + k + half];
                work_[start + k + half] = work_[start + k] - twisted;
                work_[start + k] += twisted;
            }
        }
    }
    std::array<int, Bands> levels{};
    for (int b = 0; b < Bands; ++b) {
        // The peak, not the mean, so a narrow tone in a wide band stays visible.
        double peak = 0;
        for (int k = edges_.bins[b]; k < edges_.bins[b + 1]; ++k) peak = std::max(peak, std::abs(work_[k]));
        // 2/sum(w) scales a full-scale sine to 0 dB.
        const double db = decibels(2.0 * peak / windowSum_) + tilt_[b];
        const double level = std::clamp((db - FloorDb) / (CeilingDb - FloorDb) * 99.0, 0.0, 99.0);
        // Instant attack, exponential fall: the bars need no QML animation.
        smoothed_[b] = std::max(level, smoothed_[b] * Decay);
        levels[b] = int(std::lround(smoothed_[b]));
    }
    return levels;
}

std::string formatLine(const std::array<int, Bands> &levels) {
    std::string line;
    line.reserve(Bands * 3);
    for (int b = 0; b < Bands; ++b) {
        if (b) line += ' ';
        line += std::to_string(std::clamp(levels[b], 0, 99));
    }
    line += '\n';
    return line;
}
}
