#include "ipc-protocol.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <cmath>
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>

namespace Island {
bool validLoopStatus(const QJsonValue &value) {
    return value.isString() && (value == "None" || value == "Track" || value == "Playlist");
}
bool validSeekOffset(const QJsonValue &value) {
    return value.isDouble() && std::isfinite(value.toDouble())
        && value.toDouble() >= -3600 && value.toDouble() <= 3600;
}
QByteArray encodeFrame(const QJsonObject &object) {
    // Quickshell raw chunks are QStrings: ASCII escapes survive arbitrary byte splits.
    const auto json = QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
    QByteArray encoded;
    encoded.reserve(json.size() + 1);
    constexpr char hex[] = "0123456789abcdef";
    for (const QChar character : json) {
        const auto value = character.unicode();
        if (value < 128) encoded.append(char(value));
        else {
            encoded.append("\\u");
            for (int shift = 12; shift >= 0; shift -= 4) encoded.append(hex[(value >> shift) & 15]);
        }
    }
    return encoded + '\n';
}

QJsonObject boundedEndpoint(QJsonObject endpoint) {
    if (encodeFrame(endpoint).size() <= EntryLimit - 512) return endpoint;
    auto presentation = endpoint.value("presentation").toObject();
    endpoint["presentationTruncated"] = true;
    // Metadata is presentation, never command authority; trim in a stable order.
    for (const auto &field : {"artists", "album", "title", "hostApp", "platform"}) {
        if (field == QByteArray("artists")) presentation[field] = QJsonArray();
        else {
            QString text = presentation.value(field).toString();
            while (!text.isEmpty()) {
                text.truncate(text.size() / 2);
                if (!text.isEmpty() && text.back().isHighSurrogate()) text.chop(1);
                presentation[field] = text;
                endpoint["presentation"] = presentation;
                if (encodeFrame(endpoint).size() <= EntryLimit - 512) return endpoint;
            }
            presentation.remove(field);
        }
        endpoint["presentation"] = presentation;
        if (encodeFrame(endpoint).size() <= EntryLimit - 512) return endpoint;
    }
    return {};
}

QVector<QByteArray> snapshotFrames(const QVector<QJsonObject> &endpoints,
                                 const QString &connection, const QString &sequence,
                                 const QString &busEpoch) {
    QJsonObject base{{"protocolVersion", 1}, {"connectionGeneration", connection},
                     {"sequence", sequence}};
    QVector<QByteArray> entries;
    qsizetype total = 0;
    for (const auto &raw : endpoints) {
        if (entries.size() >= EndpointLimit) break;
        auto endpoint = boundedEndpoint(raw);
        if (endpoint.isEmpty()) {
            fprintf(stderr, "endpoint-identity-exceeds-budget\n");
            continue;
        }
        QJsonObject frame = base;
        frame["type"] = "snapshotEntry";
        frame["index"] = entries.size();
        frame["endpoint"] = endpoint;
        auto encoded = encodeFrame(frame);
        // Reserve 2 KiB for begin/commit envelopes before admitting entries.
        if (encoded.size() > EntryLimit || total + encoded.size() > SnapshotLimit - 2048) {
            fprintf(stderr, "snapshot-budget-exceeded\n");
            continue;
        }
        total += encoded.size();
        entries.append(encoded);
    }
    auto begin = base;
    begin["type"] = "snapshotBegin";
    begin["busEpoch"] = busEpoch;
    begin["count"] = entries.size();
    auto commit = base;
    commit["type"] = "snapshotCommit";
    commit["count"] = entries.size();
    QVector<QByteArray> frames{encodeFrame(begin)};
    frames += entries;
    frames.append(encodeFrame(commit));
    return frames;
}

JsonLines::JsonLines(QObject *parent) : QObject(parent) {}
void JsonLines::fail(const QString &code) {
    failed_ = true;
    pending_.clear();
    emit error(code);
}
void JsonLines::feed(const QByteArray &bytes) {
    if (failed_) return;
    // Process incremental chunks instead of duplicating an arbitrarily large input.
    qsizetype start = 0;
    while (start < bytes.size()) {
        auto newline = bytes.indexOf('\n', start);
        auto count = (newline < 0 ? bytes.size() : newline) - start;
        if (pending_.size() + count + 1 > FrameLimit) { fail("frame-too-large"); return; }
        pending_.append(bytes.constData() + start, count);
        if (newline < 0) return;
        QJsonParseError parse;
        auto document = QJsonDocument::fromJson(pending_, &parse);
        pending_.clear();
        if (parse.error != QJsonParseError::NoError || !document.isObject()) {
            fail("invalid-json"); return;
        }
        emit message(document.object());
        if (failed_) return;
        start = newline + 1;
    }
}

StdioChannel::StdioChannel(QObject *parent)
    : QObject(parent), input_(STDIN_FILENO, QSocketNotifier::Read),
      output_(STDOUT_FILENO, QSocketNotifier::Write) {
    output_.setEnabled(false);
    for (int fd : {STDIN_FILENO, STDOUT_FILENO}) {
        const int flags = fcntl(fd, F_GETFL);
        if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
    connect(&input_, &QSocketNotifier::activated, this, &StdioChannel::readReady);
    connect(&output_, &QSocketNotifier::activated, this, &StdioChannel::writeReady);
    connect(&parser_, &JsonLines::message, this, &StdioChannel::message);
    connect(&parser_, &JsonLines::error, this, &StdioChannel::fail);
}
void StdioChannel::fail(const QString &code) {
    if (closed_) return;
    closed_ = true;
    input_.setEnabled(false);
    output_.setEnabled(false);
    queue_.clear();
    emit error(code);
}
void StdioChannel::readReady() {
    char bytes[8192];
    // Bound work per event turn so commands cannot starve D-Bus or teardown.
    for (int i = 0; i < 8 && !closed_; ++i) {
        const auto count = ::read(STDIN_FILENO, bytes, sizeof bytes);
        if (count > 0) parser_.feed(QByteArray(bytes, count));
        else if (count == 0) { closed_ = true; input_.setEnabled(false); emit closed(); return; }
        else if (errno == EAGAIN || errno == EWOULDBLOCK) return;
        else if (errno != EINTR) { fail("stdin-error"); return; }
    }
}
bool StdioChannel::send(const QByteArray &frame, qsizetype reserveBytes) {
    if (closed_ || reserveBytes < 0 || reserveBytes > QueueLimit || frame.size() > FrameLimit
        || queue_.size() + frame.size() > QueueLimit - reserveBytes)
        return false;
    queue_.append(frame);
    output_.setEnabled(true);
    return true;
}
void StdioChannel::writeReady() {
    if (queue_.isEmpty()) { output_.setEnabled(false); return; }
    const auto count = ::write(STDOUT_FILENO, queue_.constData(), queue_.size());
    if (count > 0) { queue_.remove(0, count); emit drained(); }
    else if (count < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK)
        fail("stdout-error");
    if (queue_.isEmpty()) output_.setEnabled(false);
}
}
