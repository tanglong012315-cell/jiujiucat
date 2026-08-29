import XCTest
@testable import PawFolio

final class CatProfileTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    func testNineCatsMatchTheWebRoster() {
        XCTAssertEqual(CatProfile.all.count, 9)
        XCTAssertEqual(
            CatProfile.all.map(\.id),
            ["puffy", "nono", "jiujiu", "liz", "pudding", "zhezhe", "coco", "momo", "bobo"]
        )
    }

    func testMissingBirthReadsAsUnknown() {
        XCTAssertEqual(CatAgeFormatter.ageText(birth: nil), "年龄未知")
        XCTAssertEqual(CatAgeFormatter.ageText(birth: ""), "年龄未知")
    }

    func testYearOnlyBirthReportsTheYear() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2025", now: date("2026-08-28"), calendar: calendar),
            "2025 年生"
        )
    }

    func testUnderOneYearIsCountedInMonths() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2025-11-09", now: date("2026-08-28"), calendar: calendar),
            "9 个月大"
        )
    }

    /// 生日当月但还没到那一天，要少算一个月。
    func testDayOfMonthBeforeBirthdayLosesAMonth() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2025-11-09", now: date("2026-08-08"), calendar: calendar),
            "8 个月大"
        )
    }

    func testBetweenOneAndTwoKeepsTheMonths() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2025-02-10", now: date("2026-08-28"), calendar: calendar),
            "1 岁 6 个月"
        )
    }

    func testExactlyOneYearOmitsTheMonths() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2025-08-28", now: date("2026-08-28"), calendar: calendar),
            "1 岁"
        )
    }

    func testTwoYearsAndAboveReportWholeYearsOnly() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2017-09-17", now: date("2026-08-28"), calendar: calendar),
            "8 岁"
        )
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2022-05-17", now: date("2026-08-28"), calendar: calendar),
            "4 岁"
        )
    }

    /// 生日还没到的猫（数据录入超前）不该出现负数年龄。
    func testFutureBirthFallsBackToYearAndMonth() {
        XCTAssertEqual(
            CatAgeFormatter.ageText(birth: "2027-03-02", now: date("2026-08-28"), calendar: calendar),
            "2027.03 生"
        )
    }

    func testBirthTextNeedsAFullDate() {
        XCTAssertEqual(CatAgeFormatter.birthText(birth: "2023-03-02"), "2023.03.02 生")
        XCTAssertEqual(CatAgeFormatter.birthText(birth: "2025"), "")
        XCTAssertEqual(CatAgeFormatter.birthText(birth: nil), "")
    }

    func testSexWording() {
        XCTAssertEqual(CatProfile.Sex.female.title, "母猫")
        XCTAssertEqual(CatProfile.Sex.male.title, "公猫")
    }
}
