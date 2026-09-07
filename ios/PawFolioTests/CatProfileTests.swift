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

    /// 生日当月但还没到那一天，要少算一个月。
    /// 生日还没到的猫（数据录入超前）不该出现负数年龄。
    func testSexWording() {
        XCTAssertEqual(CatProfile.Sex.female.title, "Girl")
        XCTAssertEqual(CatProfile.Sex.male.title, "Boy")
    }
}
