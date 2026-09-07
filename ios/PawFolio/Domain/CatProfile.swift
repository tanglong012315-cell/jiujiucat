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
            case .female: "Girl"
            case .male: "Boy"
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
        Self(id: "puffy", name: "Puffy", detail: "Founding matriarch", sex: .female, birth: "2017-09-17"),
        Self(id: "nono", name: "NoNo", detail: "Independent spirit", sex: .male, birth: "2022-05-17"),
        Self(id: "jiujiu", name: "JiuJiu", detail: "Big-eyed sweetheart", sex: .female, birth: "2022-10-03"),
        Self(id: "liz", name: "Liz", detail: "Also known as Mini", sex: .female, birth: "2023-10-15"),
        Self(id: "pudding", name: "Pudding", detail: "Gentle gentleman", sex: .male, birth: "2023-03-02"),
        Self(id: "zhezhe", name: "ZheZhe", detail: "Wild child", sex: .male, birth: "2025"),
        Self(id: "coco", name: "CoCo", detail: "Feisty", sex: .female, birth: "2024-01-15"),
        Self(id: "momo", name: "MoMo", detail: "Little princess", sex: .female, birth: "2025-11-09"),
        Self(id: "bobo", name: "BoBo", detail: "Little prince", sex: .male, birth: "2025-11-09")
    ]

    static func profile(id: String) -> Self? {
        all.first { $0.id == id }
    }
}

extension CatAvatar {
    /// `cat:` 前缀的头像背后那只猫。表情头像返回 nil。
    ///
    /// 原来和「猫图鉴弹层」放在同一个文件里，那个弹层 2026-09-06 清理时确认没有
    /// 任何入口，整个删掉了；这段扩展是它唯一还活着的部分（个人中心的头像详情
    /// 文案在用），所以搬到了 `CatProfile` 旁边。
    var catProfile: CatProfile? {
        guard rawValue.hasPrefix("cat:") else { return nil }
        return CatProfile.profile(id: String(rawValue.dropFirst(4)))
    }
}
