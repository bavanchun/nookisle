#include "spectrum-core.h"
#include <QtTest>
#include <cmath>
#include <numbers>

using namespace Island::Spectrum;

namespace {
std::vector<float> sine(double rate, double frequency, double dbfs, double seconds) {
    const double amplitude = std::pow(10.0, dbfs / 20.0);
    std::vector<float> samples(std::size_t(std::lround(rate * seconds)));
    for (std::size_t n = 0; n < samples.size(); ++n)
        samples[n] = float(amplitude * std::sin(2.0 * std::numbers::pi * frequency * double(n) / rate));
    return samples;
}

std::vector<float> square(double rate, double frequency, double seconds) {
    auto samples = sine(rate, frequency, 0.0, seconds);
    for (auto &sample : samples) sample = sample >= 0 ? 1.0f : -1.0f;
    return samples;
}

// Feed in PipeWire-sized quanta so frames that straddle a call are exercised.
std::vector<std::string> feed(Analyzer &analyzer, const std::vector<float> &samples, std::size_t quantum = 480) {
    std::vector<std::string> lines;
    for (std::size_t at = 0; at < samples.size(); at += quantum) {
        auto more = analyzer.push(samples.data() + at, std::min(quantum, samples.size() - at));
        lines.insert(lines.end(), more.begin(), more.end());
    }
    return lines;
}

QList<int> levels(const std::string &line) {
    QList<int> values;
    for (const auto &field : QString::fromStdString(line).trimmed().split(' ')) values << field.toInt();
    return values;
}

int loudestBand(const std::string &line) {
    const auto values = levels(line);
    return int(std::max_element(values.begin(), values.end()) - values.begin());
}

int bandOf(double rate, double frequency) {
    const auto edges = bandEdges(rate);
    const int bin = int(std::lround(frequency * FftSize / rate));
    for (int b = 0; b < Bands; ++b)
        if (bin >= edges.bins[b] && bin < edges.bins[b + 1]) return b;
    return -1;
}

const std::string ZeroLine = "0 0 0 0 0 0 0 0 0 0 0 0\n";
}

class SpectrumTest : public QObject {
    Q_OBJECT
private slots:
    void bandEdgesStrictlyIncreasing_data() {
        QTest::addColumn<double>("rate");
        QTest::newRow("44.1k") << 44100.0;
        QTest::newRow("48k") << 48000.0;
        QTest::newRow("96k") << 96000.0;
    }
    void bandEdgesStrictlyIncreasing() {
        QFETCH(double, rate);
        const auto edges = bandEdges(rate);
        QVERIFY(edges.bins[0] >= int(std::lround(50.0 * FftSize / rate)));
        QVERIFY(edges.bins[0] >= 1);
        QVERIFY(edges.bins[Bands] <= FftSize / 2);
        for (int b = 0; b < Bands; ++b) QVERIFY2(edges.bins[b + 1] > edges.bins[b], qPrintable(QString::number(b)));
    }

    void sineLightsItsBand() {
        const double rate = 48000;
        const int kiloBand = bandOf(rate, 1000);
        QVERIFY(kiloBand >= 0);
        Analyzer kilo(rate);
        const auto kiloLines = feed(kilo, sine(rate, 1000, -12, 0.5));
        QVERIFY(!kiloLines.empty());
        QCOMPARE(loudestBand(kiloLines.back()), kiloBand);
        QVERIFY(levels(kiloLines.back())[kiloBand] > 80);

        Analyzer low(rate);
        const auto lowLines = feed(low, sine(rate, 100, -12, 0.5));
        QVERIFY(!lowLines.empty());
        QCOMPARE(loudestBand(lowLines.back()), bandOf(rate, 100));
        QVERIFY(loudestBand(lowLines.back()) < kiloBand);
    }

    void hopCapsFrameRate_data() {
        QTest::addColumn<double>("rate");
        QTest::newRow("48k") << 48000.0;
        QTest::newRow("44.1k") << 44100.0;
    }
    void hopCapsFrameRate() {
        QFETCH(double, rate);
        Analyzer analyzer(rate);
        QCOMPARE(feed(analyzer, sine(rate, 440, -6, 1.0)).size(), std::size_t(30));
        Analyzer slower(rate, 20);
        QCOMPARE(feed(slower, sine(rate, 440, -6, 1.0)).size(), std::size_t(20));
    }

    void silenceEmitsOneZeroLine() {
        Analyzer analyzer(48000);
        const auto lines = feed(analyzer, std::vector<float>(96000, 0.0f));
        QCOMPARE(lines.size(), std::size_t(1));
        QCOMPARE(lines[0], ZeroLine);
    }

    void musicThenSilenceEmitsTailThenZero() {
        Analyzer analyzer(48000);
        const auto loud = feed(analyzer, sine(48000, 1000, -6, 1.0));
        QCOMPARE(loud.size(), std::size_t(30));
        const int peak = levels(loud.back())[bandOf(48000, 1000)];
        QVERIFY(peak > 80);
        const auto quiet = feed(analyzer, std::vector<float>(96000, 0.0f));
        QCOMPARE(quiet.size(), std::size_t(10));
        int previous = peak;
        for (int i = 0; i < 9; ++i) {
            const int level = levels(quiet[i])[bandOf(48000, 1000)];
            QVERIFY2(level < previous && level > 0, qPrintable(QString::number(i)));
            previous = level;
        }
        QCOMPARE(quiet[9], ZeroLine);
        QVERIFY(feed(analyzer, std::vector<float>(48000, 0.0f)).empty());
    }

    void signalAfterSilenceResumesImmediately() {
        Analyzer analyzer(48000);
        QCOMPARE(feed(analyzer, std::vector<float>(96000, 0.0f)).size(), std::size_t(1));
        // Exactly one hop of signal must produce exactly one line.
        const auto lines = feed(analyzer, sine(48000, 1000, -12, 1600.0 / 48000));
        QCOMPARE(lines.size(), std::size_t(1));
        QVERIFY(levels(lines[0])[bandOf(48000, 1000)] > 80);
    }

    void levelsClampAndFormat() {
        Analyzer analyzer(48000);
        const auto lines = feed(analyzer, square(48000, 220, 0.5));
        QVERIFY(!lines.empty());
        for (const auto &line : lines) {
            QVERIFY(line.size() <= 64);
            QCOMPARE(line.back(), '\n');
            QVERIFY(line.find("  ") == std::string::npos);
            QCOMPARE(line.front() == ' ', false);
            const auto fields = QString::fromStdString(line).chopped(1).split(' ');
            QCOMPARE(fields.size(), Bands);
            for (const auto &field : fields) {
                bool ok = false;
                const int value = field.toInt(&ok);
                QVERIFY(ok && value >= 0 && value <= 99);
            }
        }
        QVERIFY(levels(lines.back()).contains(99));
        std::array<int, Bands> wild{};
        wild[0] = -5;
        wild[1] = 250;
        QCOMPARE(formatLine(wild), std::string("0 99 0 0 0 0 0 0 0 0 0 0\n"));
    }

    void decaySmoothsFall() {
        Analyzer analyzer(48000);
        const auto loud = feed(analyzer, sine(48000, 1000, -6, 1600.0 / 48000));
        QCOMPARE(loud.size(), std::size_t(1));
        // -60 dBFS stays above the -65 dBFS gate but reads far lower on its own.
        const auto soft = feed(analyzer, sine(48000, 1000, -60, 1600.0 / 48000));
        QCOMPARE(soft.size(), std::size_t(1));
        const auto before = levels(loud[0]), after = levels(soft[0]);
        for (int b = 0; b < Bands; ++b)
            QVERIFY2(after[b] >= int(std::floor(0.82 * before[b])) - 1, qPrintable(QString::number(b)));
        QVERIFY(after[bandOf(48000, 1000)] < before[bandOf(48000, 1000)]);
    }

    void nonFiniteSamplesAndBadRates() {
        Analyzer analyzer(48000);
        std::vector<float> samples(1600, std::numeric_limits<float>::quiet_NaN());
        const auto lines = analyzer.push(samples.data(), samples.size());
        QVERIFY(lines.empty());  // NaN reads as silence, and a fresh analyzer starts quiet.
        QVERIFY(analyzer.push(nullptr, 10).empty());
        QVERIFY_THROWS_EXCEPTION(std::invalid_argument, Analyzer(0));
        QVERIFY_THROWS_EXCEPTION(std::invalid_argument, Analyzer(std::nan("")));
    }
};
QTEST_GUILESS_MAIN(SpectrumTest)
#include "spectrum-test.moc"
