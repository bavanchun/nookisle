#include "calendar-parser.h"
#include <QRegularExpression>
#include <QTimeZone>
#include <QVarLengthArray>
#include <algorithm>

namespace Island::Calendar {
namespace {
QString unescape(QString s) {
    return s.replace("\\n", "\n", Qt::CaseInsensitive).replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\");
}
// A property parameter's value, unquoted; empty when absent.
QString parameter(const QString &params, const QString &name) {
    static const QRegularExpression pattern("(?:^|;)([A-Za-z0-9-]+)=(?:\"([^\"]*)\"|([^;]*))");
    for (auto it = pattern.globalMatch(params); it.hasNext();) {
        auto match = it.next();
        if (match.captured(1).compare(name, Qt::CaseInsensitive) != 0) continue;
        return match.capturedStart(2) >= 0 ? match.captured(2) : match.captured(3);
    }
    return {};
}
// IANA IDs, Windows zone names (Outlook, Exchange) and producer-prefixed IDs
// such as /mozilla.org/20050126_1/Europe/Berlin. A source repeats its few IDs
// on every date, so each resolves once per thread; an overlong ID is unknown
// without a search, which would otherwise cost one lookup per slash.
QTimeZone zoneFor(const QString &name) {
    if (name.size() > ZoneIdLimit) return {};
    static thread_local QHash<QString, QTimeZone> resolved;
    if (auto it = resolved.constFind(name); it != resolved.constEnd()) return *it;
    QTimeZone zone(name.toUtf8());
    if (!zone.isValid()) {
        QByteArray iana = QTimeZone::windowsIdToDefaultIanaId(name.toUtf8());
        if (!iana.isEmpty() && QTimeZone(iana).isValid()) zone = QTimeZone(iana);
    }
    for (int slash = name.indexOf('/'); !zone.isValid() && slash >= 0; slash = name.indexOf('/', slash + 1)) {
        QTimeZone suffix(name.mid(slash + 1).toUtf8());
        if (suffix.isValid()) zone = suffix;
    }
    if (resolved.size() >= 256) resolved.clear();
    resolved.insert(name, zone);
    return zone;
}
// An unknown TZID falls back to floating time and sets unknownZone.
QDateTime dateValue(const QString &value, const QString &params, bool *allDay = nullptr, bool *unknownZone = nullptr) {
    const bool dateOnly = parameter(params, "VALUE").compare("DATE", Qt::CaseInsensitive) == 0 || value.size() == 8;
    if (allDay) *allDay = dateOnly;
    QDate date = QDate::fromString(value.left(8), "yyyyMMdd");
    if (!date.isValid()) return {};
    QTime time = dateOnly ? QTime(0, 0) : QTime::fromString(value.mid(9, 6), "HHmmss");
    if (!dateOnly && !time.isValid()) time = QTime::fromString(value.mid(9, 4), "HHmm");
    if (!time.isValid()) return {};
    if (value.endsWith('Z')) return QDateTime(date, time, QTimeZone::UTC);
    QString tzid = parameter(params, "TZID");
    if (!tzid.isEmpty()) {
        QTimeZone zone = zoneFor(tzid);
        if (zone.isValid()) return QDateTime(date, time, zone);
        if (unknownZone) *unknownZone = true;
    }
    return QDateTime(date, time, QTimeZone::systemTimeZone());
}
// The first colon outside a quoted parameter value separates name from value.
int valueColon(const QString &line) {
    bool quoted = false;
    for (int i = 0; i < line.size(); ++i) {
        if (line[i] == '"') quoted = !quoted;
        else if (line[i] == ':' && !quoted) return i;
    }
    return -1;
}
qint64 durationSeconds(const QString &value) {
    auto match = QRegularExpression("^P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$").match(value);
    if (!match.hasMatch()) return 0;
    constexpr qint64 maxSeconds = 36500LL * 86400;
    constexpr qint64 factors[] = {604800, 86400, 3600, 60, 1};
    qint64 result = 0;
    for (int i = 1; i <= 5; ++i) {
        bool valid = false;
        qint64 n = match.captured(i).isEmpty() ? 0 : match.captured(i).toLongLong(&valid);
        if (!match.captured(i).isEmpty() && !valid) return 0;
        if (n < 0 || n > (maxSeconds - result) / factors[i - 1]) return 0;
        result += n * factors[i - 1];
    }
    return result;
}
int weekday(const QString &day) {
    static const QStringList names{"MO", "TU", "WE", "TH", "FR", "SA", "SU"};
    return names.indexOf(day) + 1;
}
QMap<QString, QString> ruleParts(const QString &rule) {
    QMap<QString, QString> parts;
    for (const auto &part : rule.split(';')) {
        int equal = part.indexOf('=');
        if (equal > 0) parts.insert(part.left(equal).toUpper(), part.mid(equal + 1).toUpper());
    }
    return parts;
}
bool isSupported(const QMap<QString, QString> &parts) {
    static const QStringList keys{"FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "BYMONTH", "WKST"};
    for (auto it = parts.begin(); it != parts.end(); ++it) if (!keys.contains(it.key())) return false;
    QString freq = parts.value("FREQ");
    if (!QStringList{"DAILY", "WEEKLY", "MONTHLY", "YEARLY"}.contains(freq)) return false;
    for (const auto &key : {"INTERVAL", "COUNT"}) {
        if (!parts.contains(key)) continue;
        bool valid = false;
        int n = parts.value(key).toInt(&valid);
        if (!valid || n <= 0) return false;
    }
    if (parts.contains("UNTIL") && !dateValue(parts.value("UNTIL"), {}).isValid()) return false;
    if (parts.contains("BYDAY") && parts.value("BYDAY").isEmpty()) return false;
    static const QRegularExpression dayPattern("^([+-]?[1-5])?([A-Z]{2})$");
    for (const auto &day : parts.value("BYDAY").split(',', Qt::SkipEmptyParts)) {
        auto match = dayPattern.match(day);
        // An ordinal counts within a month: MONTHLY, or YEARLY limited to
        // months by BYMONTH ("the second Sunday of March").
        if (!match.hasMatch() || !weekday(match.captured(2))
            || (!match.captured(1).isEmpty() && freq != "MONTHLY" && !(freq == "YEARLY" && parts.contains("BYMONTH"))))
            return false;
    }
    if (parts.contains("WKST") && !weekday(parts.value("WKST"))) return false;
    if (parts.contains("BYMONTH") && parts.value("BYMONTH").isEmpty()) return false;
    for (const auto &month : parts.value("BYMONTH").split(',', Qt::SkipEmptyParts)) {
        bool valid = false;
        int n = month.toInt(&valid);
        if (!valid || n < 1 || n > 12) return false;
    }
    if (parts.contains("BYMONTHDAY") && parts.value("BYMONTHDAY").isEmpty()) return false;
    if (freq == "WEEKLY" && parts.contains("BYMONTHDAY")) return false;
    for (const auto &day : parts.value("BYMONTHDAY").split(',', Qt::SkipEmptyParts)) {
        bool valid = false;
        int n = day.toInt(&valid);
        if (!valid || n == 0 || n < -31 || n > 31) return false;
    }
    return true;
}
struct Rule {
    QString freq;
    int interval = 1, count = 0;
    QDateTime until;
    QVector<QPair<int, int>> byday;  // (nth or 0, ISO weekday)
    QVector<int> bymonthday;
    QVector<int> bymonth;  // ascending, 1..12
    int wkst = 1;  // ISO weekday the week starts on; Monday unless WKST says
    bool filtered() const { return !byday.isEmpty() || !bymonthday.isEmpty(); }
    bool inMonths(const QDate &date) const { return bymonth.isEmpty() || bymonth.contains(date.month()); }
};
Rule makeRule(const QMap<QString, QString> &parts) {
    static const QRegularExpression dayPattern("^([+-]?[1-5])?([A-Z]{2})$");
    Rule rule;
    rule.freq = parts.value("FREQ");
    rule.interval = std::clamp(parts.value("INTERVAL", "1").toInt(), 1, 1000);
    rule.count = parts.value("COUNT").toInt();
    rule.until = dateValue(parts.value("UNTIL"), {});
    if (parts.value("UNTIL").size() == 8 && rule.until.isValid()) rule.until = rule.until.addDays(1).addMSecs(-1);
    for (const auto &day : parts.value("BYDAY").split(',', Qt::SkipEmptyParts)) {
        auto match = dayPattern.match(day);
        rule.byday.append({match.captured(1).toInt(), weekday(match.captured(2))});
    }
    for (const auto &day : parts.value("BYMONTHDAY").split(',', Qt::SkipEmptyParts)) rule.bymonthday.append(day.toInt());
    for (const auto &month : parts.value("BYMONTH").split(',', Qt::SkipEmptyParts)) rule.bymonth.append(month.toInt());
    // Repeats change no date. Without them the lists hold at most 77 BYDAY
    // (7 days, each plain or +-1..5), 62 BYMONTHDAY and 12 BYMONTH values,
    // whatever length a source gives them.
    auto distinct = [](auto &list) {
        std::sort(list.begin(), list.end());
        list.erase(std::unique(list.begin(), list.end()), list.end());
    };
    distinct(rule.byday);
    distinct(rule.bymonthday);
    distinct(rule.bymonth);
    if (parts.contains("WKST")) rule.wkst = weekday(parts.value("WKST"));
    return rule;
}
// The first day of the week holding `date`, for weeks starting on `wkst`.
QDate weekStart(const QDate &date, int wkst) { return date.addDays(-((date.dayOfWeek() - wkst + 7) % 7)); }
bool dayMatches(const QDate &date, const Rule &rule, bool monthly) {
    if (rule.byday.isEmpty()) return true;
    for (const auto &[nth, day] : rule.byday) {
        if (date.dayOfWeek() != day) continue;
        if (!monthly || nth == 0) return true;
        int ordinal = (date.day() - 1) / 7 + 1;
        int fromEnd = (date.daysInMonth() - date.day()) / 7 + 1;
        if ((nth > 0 && ordinal == nth) || (nth < 0 && fromEnd == -nth)) return true;
    }
    return false;
}
bool monthDayMatches(const QDate &date, const Rule &rule) {
    if (rule.bymonthday.isEmpty()) return true;
    for (int n : rule.bymonthday) if (date.day() == (n > 0 ? n : date.daysInMonth() + n + 1)) return true;
    return false;
}
using Dates = QVarLengthArray<QDate, 64>;
void sortDates(Dates &dates) {
    std::sort(dates.begin(), dates.end());
    dates.erase(std::unique(dates.begin(), dates.end()), dates.end());
}
void monthDates(int year, int month, const QDate &base, const Rule &rule, Dates &out) {
    QDate first(year, month, 1);
    if (!first.isValid()) return;
    const int days = first.daysInMonth();
    if (!rule.filtered()) {
        if (base.day() <= days) out.append(QDate(year, month, base.day()));
    } else if (!rule.bymonthday.isEmpty()) {
        for (int n : rule.bymonthday) {
            int day = n > 0 ? n : days + n + 1;
            if (day < 1 || day > days) continue;
            QDate date(year, month, day);
            if (dayMatches(date, rule, true)) out.append(date);
        }
    } else {
        QDate last(year, month, days);
        for (const auto &[nth, day] : rule.byday) {
            QDate firstMatch = first.addDays((day - first.dayOfWeek() + 7) % 7);
            QDate lastMatch = last.addDays(-((last.dayOfWeek() - day + 7) % 7));
            if (nth > 0) {
                QDate date = firstMatch.addDays(7 * (nth - 1));
                if (date.month() == month) out.append(date);
            } else if (nth < 0) {
                QDate date = lastMatch.addDays(-7 * (-nth - 1));
                if (date.month() == month) out.append(date);
            } else {
                for (QDate date = firstMatch; date <= last; date = date.addDays(7)) out.append(date);
            }
        }
    }
    sortDates(out);
}
// The first day of period p, counted in whole intervals from the series start.
// Weekly periods begin on the rule's week start (WKST, Monday by default).
QDate periodStart(const Rule &rule, const QDate &base, qint64 p) {
    const qint64 n = p * rule.interval;
    if (rule.freq == "DAILY") return base.addDays(n);
    if (rule.freq == "WEEKLY") return weekStart(base, rule.wkst).addDays(7 * n);
    if (rule.freq == "MONTHLY") return n > 120000 ? QDate() : QDate(base.year(), base.month(), 1).addMonths(int(n));
    return n > 10000 ? QDate() : QDate(base.year() + int(n), 1, 1);
}
// The dates one period contributes, ascending. YEARLY covers the BYMONTH
// months, or the month of DTSTART without BYMONTH; its BYDAY and BYMONTHDAY
// apply within each of those months. BYMONTH limits every other frequency.
void periodDates(const Rule &rule, const QDate &base, const QDate &start, Dates &out) {
    out.clear();
    if (rule.freq == "DAILY") {
        if (rule.inMonths(start) && dayMatches(start, rule, false) && monthDayMatches(start, rule)) out.append(start);
    } else if (rule.freq == "WEEKLY") {
        auto offset = [&](int day) { return (day - rule.wkst + 7) % 7; };
        if (rule.byday.isEmpty()) out.append(start.addDays(offset(base.dayOfWeek())));
        for (const auto &day : rule.byday) out.append(start.addDays(offset(day.second)));
        if (!rule.bymonth.isEmpty())
            out.erase(std::remove_if(out.begin(), out.end(), [&](const QDate &d) { return !rule.inMonths(d); }), out.end());
        sortDates(out);
    } else if (rule.freq == "MONTHLY") {
        if (rule.inMonths(start)) monthDates(start.year(), start.month(), base, rule, out);
    } else {
        const QVector<int> months = rule.bymonth.isEmpty() ? QVector<int>{base.month()} : rule.bymonth;
        Dates month;
        for (int m : months) {
            if (rule.filtered()) {
                monthDates(start.year(), m, base, rule, month);
                for (const QDate &date : month) out.append(date);
                month.clear();
            } else {
                QDate date(start.year(), m, base.day());
                if (date.isValid()) out.append(date);
            }
        }
        sortDates(out);
    }
}
// The checks one period's expansion makes: every BYMONTHDAY is matched
// against every BYDAY in each month, and a plain BYDAY yields up to five dates
// a month. It is charged to the budget before the period runs, so a rule
// whose lists multiply ends the budget rather than stalling the helper.
int periodWork(const Rule &rule) {
    const int byday = int(rule.byday.size()), bymonthday = int(rule.bymonthday.size());
    if (rule.freq == "DAILY") return 1 + byday + bymonthday + int(rule.bymonth.size());
    if (rule.freq == "WEEKLY") return 1 + byday;
    const int months = rule.freq == "MONTHLY" ? 1 : qMax(1, int(rule.bymonth.size()));
    const int perMonth = bymonthday ? bymonthday * qMax(1, byday) : byday ? 5 * byday : 1;
    return months * perMonth;
}
qint64 periodsBefore(const Rule &rule, const QDate &base, const QDate &date) {
    if (date <= base) return 0;
    if (rule.freq == "DAILY") return base.daysTo(date) / rule.interval;
    if (rule.freq == "WEEKLY") return weekStart(base, rule.wkst).daysTo(weekStart(date, rule.wkst)) / 7 / rule.interval;
    if (rule.freq == "MONTHLY") return ((date.year() - base.year()) * 12 + date.month() - base.month()) / rule.interval;
    return (date.year() - base.year()) / rule.interval;
}
// Instances in every period after the first when that number is constant,
// else 0; it lets COUNT series skip ahead without walking each period.
// Only the WEEKLY probe expands a period; it is charged `cost` from `budget`.
int steadyCount(const Rule &rule, const QDate &base, int cost, int &budget) {
    if (!rule.bymonth.isEmpty() && rule.freq != "YEARLY") return 0;
    if (rule.freq == "DAILY") return rule.filtered() ? 0 : 1;
    if (rule.freq == "WEEKLY") {
        budget -= cost;
        Dates dates;
        periodDates(rule, base, periodStart(rule, base, 1), dates);
        return int(dates.size());
    }
    if (rule.filtered()) return 0;
    if (rule.freq == "MONTHLY") return base.day() <= 28 ? 1 : 0;
    if (!rule.bymonth.isEmpty()) return base.day() <= 28 ? int(rule.bymonth.size()) : 0;
    return base.month() == 2 && base.day() == 29 ? 0 : 1;
}
QString instanceKey(const QString &uid, const QDateTime &instance) {
    return uid + '\n' + QString::number(instance.toMSecsSinceEpoch());
}
bool excluded(const Entry &entry, const QDateTime &instance) {
    return entry.exdateInstants.contains(instance.toMSecsSinceEpoch())
        || entry.exdateDays.contains(instance.date().toJulianDay());
}
QJsonObject asJson(const Entry &e, const QDateTime &instance, const QString &source, const QString &color,
                   const QDateTime &original = {}) {
    qint64 shift = e.start.isValid() ? e.start.secsTo(instance) : 0;
    QDateTime end = e.end.isValid() ? e.end.addSecs(shift) : instance;
    QDateTime due = e.due.isValid() ? e.due.addSecs(shift) : QDateTime();
    QJsonObject result{{"sourceId", source}, {"uid", e.uid}, {"instanceStart", (original.isValid() ? original : instance).toString(Qt::ISODateWithMs)},
        {"start", instance.toString(Qt::ISODateWithMs)}, {"end", end.toString(Qt::ISODateWithMs)},
        {"allDay", e.allDay}, {"title", e.title}, {"location", e.location}, {"color", color},
        {"todo", e.todo}, {"completed", e.status == "COMPLETED" || e.completedAt.isValid()},
        {"due", due.isValid() ? due.toString(Qt::ISODateWithMs) : QString()}};
    if (!e.unsupported.isEmpty()) result["unsupported"] = QJsonArray::fromStringList(e.unsupported);
    return result;
}
}

QPair<QString, QString> property(const QString &line) {
    int colon = valueColon(line);
    if (colon < 0) return {};
    return {line.left(colon).section(';', 0, 0).toUpper(), line.mid(colon + 1)};
}

ParseResult parse(const QByteArray &data) {
    ParseResult result;
    if (data.size() > SourceLimit) { result.error = "too-large"; return result; }
    QString raw = QString::fromUtf8(data);
    QStringList lines;
    for (const QString &line : raw.split(QRegularExpression("\r\n|\n|\r"))) {
        if ((line.startsWith(' ') || line.startsWith('\t')) && !lines.isEmpty()) lines.last() += line.mid(1);
        else lines.append(line);
    }
    bool calendar = false, inEntry = false;
    // A date-only DUE: a reminder with no DTSTART is then all-day.
    bool dueDateOnly = false;
    int nested = 0;
    Entry current;
    int components = 0;
    auto note = [&current](const QString &key) {
        if (key.size() <= 64 && current.unsupported.size() < 32 && !current.unsupported.contains(key)) current.unsupported.append(key);
    };
    for (const QString &line : lines) {
        if (line == "BEGIN:VCALENDAR") { calendar = true; continue; }
        if (!calendar) continue;
        if (line == "BEGIN:VEVENT" || line == "BEGIN:VTODO") {
            if (++components > ComponentLimit) { result.error = "too-many-components"; result.entries.clear(); return result; }
            current = Entry{}; current.todo = line == "BEGIN:VTODO"; inEntry = true; nested = 0; dueDateOnly = false; continue;
        }
        if (line == "END:VEVENT" || line == "END:VTODO") {
            if (inEntry && !current.uid.isEmpty() && (current.start.isValid() || current.due.isValid())) {
                if (!current.start.isValid()) { current.start = current.due; current.allDay = dueDateOnly; }
                if (!current.end.isValid() && !current.duration.isEmpty()) current.end = current.start.addSecs(durationSeconds(current.duration));
                if (!current.end.isValid()) current.end = current.due.isValid() ? current.due : current.start;
                result.entries.append(current);
            }
            inEntry = false; continue;
        }
        if (!inEntry) continue;
        // Sub-components such as VALARM carry their own SUMMARY, DURATION and
        // DESCRIPTION; none of them belongs to the enclosing entry.
        if (line.startsWith("BEGIN:", Qt::CaseInsensitive)) { ++nested; continue; }
        if (line.startsWith("END:", Qt::CaseInsensitive)) { if (nested) --nested; continue; }
        if (nested) continue;
        int colon = valueColon(line);
        if (colon < 0) continue;
        QString left = line.left(colon), value = line.mid(colon + 1);
        QString key = left.section(';', 0, 0).toUpper(), params = left.mid(key.size());
        bool unknownZone = false;
        if (key == "UID") current.uid = value.left(1024);
        else if (key == "SUMMARY") current.title = unescape(value.left(2048));
        else if (key == "LOCATION") current.location = unescape(value.left(2048));
        else if (key == "STATUS") current.status = value.toUpper();
        else if (key == "DTSTART") current.start = dateValue(value, params, &current.allDay, &unknownZone);
        else if (key == "DTEND") current.end = dateValue(value, params, nullptr, &unknownZone);
        else if (key == "DUE") current.due = dateValue(value, params, &dueDateOnly, &unknownZone);
        else if (key == "COMPLETED") current.completedAt = dateValue(value, params);
        else if (key == "DURATION") current.duration = value;
        else if (key == "RRULE") current.rule = value;
        else if (key == "RECURRENCE-ID") current.recurrenceId = dateValue(value, params, nullptr, &unknownZone);
        else if (key == "EXDATE") {
            for (const auto &v : value.split(',')) {
                if (current.exdateInstants.size() + current.exdateDays.size() >= ExclusionLimit) { note("EXDATE"); break; }
                bool dateOnly = false;
                QDateTime excludedAt = dateValue(v, params, &dateOnly, &unknownZone);
                if (!excludedAt.isValid()) continue;
                if (dateOnly) current.exdateDays.insert(excludedAt.date().toJulianDay());
                else current.exdateInstants.insert(excludedAt.toMSecsSinceEpoch());
            }
        }
        else if (!QStringList{"BEGIN", "END", "VERSION", "PRODID", "DTSTAMP", "CREATED", "LAST-MODIFIED", "SEQUENCE"}.contains(key)) note(key);
        if (unknownZone) note("TZID");
    }
    if (!calendar) result.error = "invalid-calendar";
    return result;
}

void visitWindow(const QVector<Entry> &entries, const QDateTime &from, const QDateTime &until,
                 const QString &sourceId, const QString &color,
                 const std::function<bool(const QJsonObject &)> &visitor, WindowStats *stats) {
    WindowStats local;
    WindowStats &work = stats ? *stats : local;
    QHash<QString, const Entry *> overrides;
    QHash<QString, QVector<const Entry *>> overridesByUid;
    for (const Entry &entry : entries) if (entry.recurrenceId.isValid()) {
        overrides.insert(instanceKey(entry.uid, entry.recurrenceId), &entry);
        overridesByUid[entry.uid].append(&entry);
    }
    auto intersects = [&](const QDateTime &start, const QDateTime &end) {
        return start < until && (start >= from || end > from);
    };
    QSet<QString> visited;
    // Emits one instance of a series unless it is excluded, cancelled or
    // outside the window; returns false once the visitor asks to stop.
    auto emitInstance = [&](const Entry &e, const QDateTime &candidate, bool unsupportedRule, int &emitted) {
        QString key = instanceKey(e.uid, candidate);
        const Entry *moved = overrides.value(key);
        if (moved) visited.insert(key);
        if (excluded(e, candidate)) return true;
        const Entry &shown = moved ? *moved : e;
        if (shown.status == "CANCELLED") return true;
        QDateTime start = moved ? moved->start : candidate;
        QDateTime end = moved ? moved->end : e.end.addSecs(e.start.secsTo(candidate));
        // An unsupported rule is reported through its first instance even
        // when that falls before the window, so the series never vanishes.
        if (!intersects(start, end) && !(unsupportedRule && start < from)) return true;
        auto item = moved ? asJson(*moved, moved->start, sourceId, color, candidate) : asJson(e, candidate, sourceId, color);
        if (unsupportedRule) {
            auto unsupported = item.value("unsupported").toArray();
            unsupported.append("RRULE");
            item["unsupported"] = unsupported;
        }
        ++emitted;
        return visitor(item);
    };
    Dates dates;
    for (const Entry &e : entries) {
        if (e.recurrenceId.isValid() || !e.start.isValid()) continue;
        int emitted = 0;
        auto parts = ruleParts(e.rule);
        if (e.rule.isEmpty() || !isSupported(parts)) {
            if (!emitInstance(e, e.start, !e.rule.isEmpty(), emitted)) return;
            continue;
        }
        if (work.budget <= 0) { work.limited = true; continue; }
        const Rule rule = makeRule(parts);
        const QDate base = e.start.date();
        const qint64 span = qMax<qint64>(0, e.start.secsTo(e.end));
        // Day slack on each side absorbs zone differences between the series
        // and the window; exact comparisons happen on the full date-time.
        const QDate low = from.addSecs(-span).date().addDays(-1);
        const QDate high = until.date().addDays(1);
        const QDate untilDay = rule.until.isValid() ? rule.until.date().addDays(1) : QDate();
        const int cost = periodWork(rule);
        const int steady = steadyCount(rule, base, cost, work.budget);
        qint64 first = 0, ordinal = 0;
        if (low > base && (rule.count == 0 || steady > 0)) {
            first = qMax<qint64>(0, periodsBefore(rule, base, low) - 1);
            if (rule.count && first > 0) {
                work.budget -= cost;
                periodDates(rule, base, periodStart(rule, base, 0), dates);
                ordinal = std::count_if(dates.begin(), dates.end(), [&](const QDate &d) { return d >= base; })
                    + (first - 1) * steady;
            }
        }
        bool done = false;
        for (qint64 p = first; !done; ++p) {
            const QDate start = periodStart(rule, base, p);
            if (!start.isValid() || start > high || (untilDay.isValid() && start > untilDay)) break;
            // Charged only for a period that is expanded: a series that
            // starts after the window costs nothing and limits nothing.
            work.budget -= cost;
            if (work.budget < 0) { work.limited = true; break; }
            periodDates(rule, base, start, dates);
            for (const QDate &date : dates) {
                --work.budget;
                if (date < base) continue;
                if (date > high || (untilDay.isValid() && date > untilDay) || (rule.count && ordinal >= rule.count)) { done = true; break; }
                if (date < low) { ++ordinal; continue; }
                QDateTime candidate(date, e.start.time(), e.start.timeRepresentation());
                if (!candidate.isValid() || candidate < e.start) continue;
                if (candidate >= until || (rule.until.isValid() && candidate > rule.until)) { done = true; break; }
                ++ordinal;
                if (!emitInstance(e, candidate, false, emitted)) return;
                if (emitted >= InstanceLimit) { done = true; break; }
            }
        }
        // An override moved into the window from an original outside it.
        for (const Entry *moved : overridesByUid.value(e.uid)) {
            if (emitted >= InstanceLimit) break;
            if (visited.contains(instanceKey(e.uid, moved->recurrenceId)) || moved->status == "CANCELLED"
                || excluded(e, moved->recurrenceId) || !intersects(moved->start, moved->end)) continue;
            visited.insert(instanceKey(e.uid, moved->recurrenceId));
            ++emitted;
            if (!visitor(asJson(*moved, moved->start, sourceId, color, moved->recurrenceId))) return;
        }
    }
}

QJsonArray window(const QVector<Entry> &entries, const QDateTime &from, const QDateTime &until,
                  const QString &sourceId, const QString &color) {
    QJsonArray out;
    visitWindow(entries, from, until, sourceId, color, [&](const QJsonObject &item) { out.append(item); return true; });
    return out;
}
}
