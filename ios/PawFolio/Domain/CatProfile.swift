import Foundation

/// 「我们家的猫」图鉴里的一只猫。数据与 `public/app.js` 的 `CAT_AVATARS` 一一对应，
/// 改动前先对照那份定义。
struct CatProfile: Equatable, Identifiable, Sendable {
    enum Sex: String, Equatable, Sendable {
        case female
        case male

        /// Web `CAT_SEX` 的措辞。
        var title: String {
            switch self {
            case .female: "母猫"
            case .male: "公猫"
            }
        }
    }

    let id: String
    let name: String
    let detail: String
    let sex: Sex
    /// `YYYY-MM-DD`，只知道年份时是 `YYYY`。
    let birth: String

    static let all: [Self] = [
        Self(id: "puffy", name: "Puffy", detail: "元老教母", sex: .female, birth: "2017-09-17"),
        Self(id: "nono", name: "NoNo", detail: "不喜欢同性", sex: .male, birth: "2022-05-17"),
        Self(id: "jiujiu", name: "JiuJiu", detail: "大眼萌妹", sex: .female, birth: "2022-10-03"),
        Self(id: "liz", name: "Liz", detail: "别名 Mini", sex: .female, birth: "2023-10-15"),
        Self(id: "pudding", name: "Pudding", detail: "娘娘腔，种公", sex: .male, birth: "2023-03-02"),
        Self(id: "zhezhe", name: "ZheZhe", detail: "疯P", sex: .male, birth: "2025"),
        Self(id: "coco", name: "CoCo", detail: "脾气暴躁", sex: .female, birth: "2024-01-15"),
        Self(id: "momo", name: "MoMo", detail: "小公主", sex: .female, birth: "2025-11-09"),
        Self(id: "bobo", name: "BoBo", detail: "小少爷", sex: .male, birth: "2025-11-09")
    ]

    static func profile(id: String) -> Self? {
        all.first { $0.id == id }
    }
}

/// Web `catAgeText` / `catBirthText` 的移植。
///
/// 措辞规则照搬那边的注释：不满一岁按月说、一两岁带上月份、再大就只说岁——
/// 小猫差一个月是另一个样子，八岁的猫差一个月没人在意。
enum CatAgeFormatter {
    static func ageText(
        birth: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let birth, !birth.isEmpty else { return "年龄未知" }

        let parts = birth.split(separator: "-").map(String.init)
        guard let year = Int(parts.first ?? "") else { return "年龄未知" }

        // 只登记了年份的猫，Web 直接说「YYYY 年生」。
        guard parts.count >= 2, let month = Int(parts[1]) else { return "\(year) 年生" }
        let day = parts.count >= 3 ? Int(parts[2]) : nil

        let nowParts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let nowYear = nowParts.year, let nowMonth = nowParts.month, let nowDay = nowParts.day else {
            return "年龄未知"
        }

        var months = (nowYear - year) * 12 + (nowMonth - month)
        if let day, nowDay < day { months -= 1 }

        if months < 0 {
            return "\(year).\(String(format: "%02d", month)) 生"
        }

        let years = months / 12
        let rest = months % 12
        if years < 1 { return "\(months) 个月大" }
        if years < 2 { return rest > 0 ? "\(years) 岁 \(rest) 个月" : "\(years) 岁" }
        return "\(years) 岁"
    }

    /// 只有年月日齐全时才给出生日期，与 Web 一致。
    static func birthText(birth: String?) -> String {
        guard let birth else { return "" }
        let parts = birth.split(separator: "-").map(String.init)
        guard parts.count >= 3 else { return "" }
        return "\(parts[0]).\(parts[1]).\(parts[2]) 生"
    }
}
