import Foundation

/// 美股交易时段。措辞与配色对应 `public/app.js` 的 `MARKET_SESSIONS`
/// 和 `styles.css` 的 `--session-*`。
enum MarketSession: String, CaseIterable, Sendable {
    case pre
    case open
    case after
    case night
    case closed

    /// 行情条上的短标签。
    var label: String {
        switch self {
        case .pre: "盘前"
        case .open: "交易中"
        case .after: "盘后"
        case .night: "夜间"
        case .closed: "休市"
        }
    }

    /// 无障碍朗读用的完整说法。
    var fullLabel: String {
        switch self {
        case .pre: "盘前交易"
        case .open: "常规交易时段"
        case .after: "盘后交易"
        case .night: "夜间交易"
        case .closed: "休市"
        }
    }
}

/// `app.js` 的 `marketSessionKey` 移植。
///
/// 美东时间：04:00 盘前 → 09:30 主盘 → 16:00 盘后 → 20:00 夜盘。
/// 夜盘从周日 20:00 一路滚到周五 20:00，周末整体休市。加密货币不参与这套判定。
enum MarketSessionCalendar {
    /// 全天休市日。每年得更新一次；表过期不会崩，只是当天会被误判成正常时段。
    static let holidays: Set<String> = [
        "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25",
        "2026-06-19", "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
        "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31",
        "2027-06-18", "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24"
    ]

    /// 提前收盘日：美东 13:00 就收，之后直接进盘后。
    static let halfDays: Set<String> = ["2026-11-27", "2026-12-24", "2027-11-26"]

    /// 交给系统做时区换算，别自己算偏移——美国夏令时一年切两次，手算必错。
    private static let easternTimeZone = TimeZone(identifier: "America/New_York")!

    private static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        return calendar
    }

    private struct Snapshot {
        /// `yyyy-MM-dd`，美东当天。
        let date: String
        /// 美东当天的分钟数。
        let minutes: Int
        /// 0 = 周日，与 `app.js` 的 `ET_WEEKDAYS` 对齐。
        let weekday: Int
    }

    private static func snapshot(at date: Date) -> Snapshot {
        let calendar = easternCalendar
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .weekday],
            from: date
        )
        let year = parts.year ?? 0
        let month = parts.month ?? 1
        let day = parts.day ?? 1

        return Snapshot(
            date: String(format: "%04d-%02d-%02d", year, month, day),
            minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
            // Calendar 的 weekday 从 1 = 周日起算。
            weekday: (parts.weekday ?? 1) - 1
        )
    }

    static func session(at date: Date = Date()) -> MarketSession {
        let now = snapshot(at: date)

        // 周六：周五 20:00 就收了。
        if now.weekday == 6 { return .closed }
        // 周日 20:00 夜盘开市。
        if now.weekday == 0 { return now.minutes >= 1_200 ? .night : .closed }
        if holidays.contains(now.date) { return .closed }

        if now.minutes < 240 {
            // 00:00–04:00 是前一晚夜盘的延续，所以要看「昨天」开没开。
            let previous = snapshot(at: date.addingTimeInterval(-86_400))
            return (previous.weekday == 6 || holidays.contains(previous.date)) ? .closed : .night
        }

        if now.minutes < 570 { return .pre }                                       // 04:00–09:30
        if now.minutes < (halfDays.contains(now.date) ? 780 : 960) { return .open }
        if now.minutes < 1_200 { return .after }                                   // 收盘–20:00
        return now.weekday == 5 ? .closed : .night                                 // 周五 20:00 进入周末
    }
}
