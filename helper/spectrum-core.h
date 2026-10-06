#pragma once
#include <array>
#include <complex>
#include <cstddef>
#include <string>
#include <vector>

namespace Island::Spectrum {
constexpr int Bands = 12, FftSize = 1024, MaxFps = 30;

// FFT bin index boundaries: band b covers bins [bins[b], bins[b + 1]).
struct BandEdges {
    std::array<int, Bands + 1> bins;
};
BandEdges bandEdges(double sampleRate, double fMin = 50.0, double fMax = 16000.0);

// Pure analysis: mono float samples in, formatted level lines out. No audio
// server, no Qt, no clock; the sample count alone paces the frames.
class Analyzer {
public:
    // Throws std::invalid_argument for a rate outside 1 kHz..768 kHz. fps is
    // clamped to 1..MaxFps.
    explicit Analyzer(double sampleRate, int fps = MaxFps);
    // Feeds mono samples. Returns every frame completed by this call:
    // one line per hop of ceil(sampleRate / fps) samples.
    std::vector<std::string> push(const float *samples, std::size_t count);

private:
    std::string finishHop();
    std::array<int, Bands> analyse();

    double sampleRate_;
    std::size_t hop_;
    BandEdges edges_;
    std::array<double, Bands> tilt_{};
    std::array<float, FftSize> ring_{};
    std::size_t ringPos_ = 0;
    std::size_t hopFill_ = 0;
    double hopEnergy_ = 0;
    std::array<double, FftSize> window_{};
    double windowSum_ = 0;
    std::vector<std::complex<double>> twiddles_;
    std::array<int, FftSize> reversed_{};
    std::vector<std::complex<double>> work_;
    std::array<double, Bands> smoothed_{};
    int quiet_ = 0;
    bool armed_ = false;
};

std::string formatLine(const std::array<int, Bands> &levels); // "l0 l1 ... l11\n"
}
