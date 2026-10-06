#pragma once

#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>
#include <QSet>
#include <QStringList>
#include <QVector>
#include <functional>

namespace Island::Calendar {
inline constexpr qsizetype SourceLimit = 4 * 1024 * 1024;
inline constexpr int ComponentLimit = 10000;
inline constexpr int InstanceLimit = 500;
// Exclusion dates kept per entry; more are dropped and reported as EXDATE.
inline constexpr int ExclusionLimit = 4096;
// Longer TZID values are unknown zones and never searched.
inline constexpr int ZoneIdLimit = 256;
// Recurrence dates examined per source per window; a series still running
// when the budget ends is cut short and the source reports recurrence-limit.
inline constexpr int StepBudget = 1000000;
// One window across every source keeps at most this many items and this
// many encoded bytes; the sources it cuts report window-limit.
inline constexpr int WindowItemLimit = 5000;
inline constexpr qint64 WindowByteLimit = 4 * 1024 * 1024;

struct Entry {
    QString uid, title, location, status, rule, duration;
    QStringList unsupported;
    QSet<qint64> exdateInstants, exdateDays;
    QDateTime start, end, due, completedAt, recurrenceId;
    bool allDay = false, todo = false;
};

struct WindowStats {
    int budget = StepBudget;
    bool limited = false;
};

struct ParseResult {
    QVector<Entry> entries;
    QString error;
};

ParseResult parse(const QByteArray &data);
// The upper-cased name and the value of one unfolded content line; a colon
// inside a quoted parameter value does not end the name.
QPair<QString, QString> property(const QString &line);
QJsonArray window(const QVector<Entry> &entries, const QDateTime &from, const QDateTime &until,
                  const QString &sourceId, const QString &color = {});
void visitWindow(const QVector<Entry> &entries, const QDateTime &from, const QDateTime &until,
                 const QString &sourceId, const QString &color,
                 const std::function<bool(const QJsonObject &)> &visitor, WindowStats *stats = nullptr);
}
