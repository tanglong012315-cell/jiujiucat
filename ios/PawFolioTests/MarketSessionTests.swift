import XCTest
@testable import PawFolio

final class MarketSessionTests: XCTestCase {
    /// 传入的都是美东本地时刻，夏令时交给 TimeZone 处理。
    private func eastern(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func session(_ text: String) -> MarketSession {
        MarketSessionCalendar.session(at: eastern(text))
    }

    // MARK: 常规交易日（2026-08-25 是周二）

    func testPreMarketStartsAtFour() {
        XCTAssertEqual(session("2026-08-25 03:59"), .night)
        XCTAssertEqual(session("2026-08-25 04:00"), .pre)
        XCTAssertEqual(session("2026-08-25 09:29"), .pre)
    }

    func testRegularSession() {
        XCTAssertEqual(session("2026-08-25 09:30"), .open)
        XCTAssertEqual(session("2026-08-25 15:59"), .open)
    }

    func testAfterHours() {
        XCTAssertEqual(session("2026-08-25 16:00"), .after)
        XCTAssertEqual(session("2026-08-25 19:59"), .after)
    }

    func testNightSessionStartsAtEight() {
        XCTAssertEqual(session("2026-08-25 20:00"), .night)
        XCTAssertEqual(session("2026-08-25 23:59"), .night)
    }

    // MARK: 周末边界

    /// 周五 20:00 收市直接进周末，不再有夜盘。
    func testFridayEveningClosesForTheWeekend() {
        XCTAssertEqual(session("2026-08-28 19:59"), .after)
        XCTAssertEqual(session("2026-08-28 20:00"), .closed)
    }

    func testSaturdayIsAlwaysClosed() {
        XCTAssertEqual(session("2026-08-29 03:00"), .closed)
        XCTAssertEqual(session("2026-08-29 10:00"), .closed)
        XCTAssertEqual(session("2026-08-29 22:00"), .closed)
    }

    func testSundayNightReopensAtEight() {
        XCTAssertEqual(session("2026-08-30 19:59"), .closed)
        XCTAssertEqual(session("2026-08-30 20:00"), .night)
    }

    /// 周一凌晨属于周日晚开的那一段夜盘。
    func testMondayEarlyHoursContinueSundayNight() {
        XCTAssertEqual(session("2026-08-31 02:00"), .night)
    }

    // MARK: 假日

    func testHolidayIsClosedAllDay() {
        XCTAssertEqual(session("2026-12-25 10:00"), .closed)
        XCTAssertEqual(session("2026-12-25 18:00"), .closed)
    }

    /// 假日次日的凌晨没有夜盘可延续——前一晚根本没开。
    func testEarlyHoursAfterAHolidayStayClosed() {
        XCTAssertEqual(session("2026-12-26 02:00"), .closed)
    }

    // MARK: 提前收盘日

    /// 2026-11-27 美东 13:00 收盘，之后直接进盘后。
    func testHalfDayClosesAtOne() {
        XCTAssertEqual(session("2026-11-27 12:59"), .open)
        XCTAssertEqual(session("2026-11-27 13:00"), .after)
        XCTAssertEqual(session("2026-11-27 15:00"), .after)
    }

    /// 同一时刻在普通交易日仍然是盘中。
    func testSameClockOnANormalDayIsStillOpen() {
        XCTAssertEqual(session("2026-11-30 13:00"), .open)
    }

    // MARK: 夏令时

    /// 判定走的是美东墙上时间，夏令时切换不该让 09:30 偏移。
    func testDaylightSavingBoundaryKeepsWallClockRules() {
        XCTAssertEqual(session("2026-03-09 09:30"), .open)   // EDT 起始后的周一
        XCTAssertEqual(session("2026-11-02 09:30"), .open)   // EST 恢复后的周一
    }

    func testWording() {
        XCTAssertEqual(MarketSession.pre.label, "盘前")
        XCTAssertEqual(MarketSession.open.label, "交易中")
        XCTAssertEqual(MarketSession.after.label, "盘后")
        XCTAssertEqual(MarketSession.night.label, "夜间")
        XCTAssertEqual(MarketSession.closed.label, "休市")
        XCTAssertEqual(MarketSession.open.fullLabel, "常规交易时段")
    }
}
