import CoreText
import SwiftUI

public enum NvwaTextScaleRole: Sendable, Equatable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case footnote
    case caption
    case caption2

    fileprivate var swiftUITextStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }
}

public struct NvwaTypographyToken: Sendable, Equatable {
    public let figmaName: String
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let letterSpacingPercent: CGFloat
    public let weight: Nvwa.FontWeight
    public let isUnderlined: Bool
    public let scaleRole: NvwaTextScaleRole

    public var tracking: CGFloat {
        size * letterSpacingPercent / 100
    }

    /// 字体自带的行盒高度（ascent + descent + leading）。Inter 12pt 约 14.5——
    /// **不是** 稿子标的 20，SwiftUI 也没有「行高」这个概念可以直接设。
    public var naturalLineHeight: CGFloat {
        let font = CTFontCreateWithName(weight.postScriptName as CFString, size, nil)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// 行与行之间要补的空隙。`lineSpacing` 只加在行**之间**，所以补的是差额全额。
    public var lineSpacing: CGFloat {
        max(0, lineHeight - naturalLineHeight)
    }

    /// 首行上方与末行下方各要补的空隙。
    ///
    /// Figma 的行高是 CSS 语义——行盒总高，多出来的部分上下各分一半（half-leading）。
    /// SwiftUI 的 `Text` 只给字体自带的行盒，`lineSpacing` 又够不着首尾两端，所以
    /// 首尾这一半必须自己补，否则同一段文字在稿子里是 20pt 行盒、在代码里只有
    /// 14.5pt，上下留白会凭空少掉一圈——**用了 `lineSpacing` 就要一起用这个**。
    public var halfLeading: CGFloat {
        lineSpacing / 2
    }

    public var font: Font {
        Nvwa.font(size, weight: weight, relativeTo: scaleRole.swiftUITextStyle)
    }

    public var fixedFont: Font {
        Nvwa.fixedFont(size, weight: weight)
    }

    init(
        _ figmaName: String,
        size: CGFloat,
        lineHeight: CGFloat,
        letterSpacingPercent: CGFloat,
        weight: Nvwa.FontWeight,
        isUnderlined: Bool = false,
        scaleRole: NvwaTextScaleRole
    ) {
        self.figmaName = figmaName
        self.size = size
        self.lineHeight = lineHeight
        self.letterSpacingPercent = letterSpacingPercent
        self.weight = weight
        self.isUnderlined = isUnderlined
        self.scaleRole = scaleRole
    }
}

public extension Nvwa {
    enum FontWeight: Sendable, Equatable {
        case regular
        case medium
        case semibold
        case bold

        fileprivate var postScriptName: String {
            switch self {
            case .regular: "Inter-Regular"
            case .medium: "Inter-Medium"
            case .semibold: "Inter-SemiBold"
            case .bold: "Inter-Bold"
            }
        }
    }

    /// Inter is bundled by PawFolio. Other Nvwa hosts should bundle the same
    /// four PostScript names to preserve the Figma typography exactly. Custom
    /// fonts scale with Dynamic Type by default.
    static func font(
        _ size: CGFloat,
        weight: FontWeight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: textStyle)
    }

    /// Compatibility escape hatch for surfaces that deliberately preserve a
    /// fixed Figma canvas size.
    static func fixedFont(_ size: CGFloat, weight: FontWeight = .regular) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }

    enum Typography {
        public static let titleScreen = NvwaTypographyToken(
            "T Semi Bold", size: 30, lineHeight: 34, letterSpacingPercent: -2.5,
            weight: .semibold, scaleRole: .largeTitle
        )
        public static let titleSection = NvwaTypographyToken(
            "T-S Semi Bold", size: 26, lineHeight: 32, letterSpacingPercent: -1.5,
            weight: .semibold, scaleRole: .title
        )
        public static let titleSubsection = NvwaTypographyToken(
            "T-Sub Semi Bold", size: 22, lineHeight: 28, letterSpacingPercent: -1.5,
            weight: .semibold, scaleRole: .title2
        )
        public static let titleBody = NvwaTypographyToken(
            "T-B Semi Bold", size: 18, lineHeight: 24, letterSpacingPercent: -1,
            weight: .semibold, scaleRole: .title3
        )
        public static let titleGroup = NvwaTypographyToken(
            "T-G Medium", size: 14, lineHeight: 20, letterSpacingPercent: 1.5,
            weight: .medium, scaleRole: .headline
        )
        public static let bodyLarge = NvwaTypographyToken(
            "B-L Regular", size: 16, lineHeight: 24, letterSpacingPercent: -0.5,
            weight: .regular, scaleRole: .body
        )
        public static let bodyLargeSemibold = NvwaTypographyToken(
            "B-L Semi Bold", size: 16, lineHeight: 24, letterSpacingPercent: 0.5,
            weight: .semibold, scaleRole: .body
        )
        public static let bodyMedium = NvwaTypographyToken(
            "B-M Regular", size: 14, lineHeight: 22, letterSpacingPercent: 1,
            weight: .regular, scaleRole: .body
        )
        public static let bodyMediumSemibold = NvwaTypographyToken(
            "B-M Semi Bold", size: 14, lineHeight: 22, letterSpacingPercent: 1.25,
            weight: .semibold, scaleRole: .body
        )
        public static let bodySmall = NvwaTypographyToken(
            "B-S Regular", size: 12, lineHeight: 20, letterSpacingPercent: 1,
            weight: .regular, scaleRole: .footnote
        )
        public static let bodySmallSemibold = NvwaTypographyToken(
            "B-S Semi Bold", size: 12, lineHeight: 20, letterSpacingPercent: 1,
            weight: .semibold, scaleRole: .footnote
        )
        public static let linkLarge = NvwaTypographyToken(
            "Link L Semi Bold", size: 16, lineHeight: 24, letterSpacingPercent: 1,
            weight: .semibold, isUnderlined: true, scaleRole: .body
        )
        public static let linkMedium = NvwaTypographyToken(
            "Link M Semi Bold", size: 14, lineHeight: 22, letterSpacingPercent: 1.25,
            weight: .semibold, isUnderlined: true, scaleRole: .body
        )
        public static let caption1 = NvwaTypographyToken(
            "C-1 Regular", size: 11, lineHeight: 18, letterSpacingPercent: 1,
            weight: .regular, scaleRole: .caption
        )
        public static let caption2 = NvwaTypographyToken(
            "C-2 Regular", size: 10, lineHeight: 16, letterSpacingPercent: 1,
            weight: .regular, scaleRole: .caption2
        )

        public static let all: [NvwaTypographyToken] = [
            titleScreen,
            titleSection,
            titleSubsection,
            titleBody,
            titleGroup,
            bodyLarge,
            bodyLargeSemibold,
            bodyMedium,
            bodyMediumSemibold,
            bodySmall,
            bodySmallSemibold,
            linkLarge,
            linkMedium,
            caption1,
            caption2
        ]
    }

    // Source-compatible Font aliases used by existing components.
    static let titleBody = Typography.titleBody.font
    static let titleGroup = Typography.titleGroup.font
    static let bodyLarge = Typography.bodyLargeSemibold.font
    static let bodyMediumSemibold = Typography.bodyMediumSemibold.font
    static let bodyMedium = Typography.bodyMedium.font
    static let bodySmall = Typography.bodySmall.font
    static let bodySmallSemibold = Typography.bodySmallSemibold.font
    static let caption2 = Typography.caption2.font

    static let moneyLarge = font(24, weight: .semibold).monospacedDigit()
    static let moneyMedium = font(20, weight: .semibold).monospacedDigit()
    static let moneyHero = font(30, weight: .semibold).monospacedDigit()
}

public extension View {
    /// 按排版 token 还原 Figma 的字号、字距、下划线与**行盒**。
    ///
    /// `linesFillLineHeight` 打开时会把 half-leading 补到首尾（见
    /// `NvwaTypographyToken.halfLeading`），文字块的高度才等于稿子上的行高 ×
    /// 行数。放在定高容器里居中的单行文字可以关掉——补了也是白补，还会把
    /// 外面量好的固定高度顶大。
    func nvwaTextStyle(
        _ token: NvwaTypographyToken,
        fixedSize: Bool = false,
        linesFillLineHeight: Bool = true
    ) -> some View {
        font(fixedSize ? token.fixedFont : token.font)
            .tracking(token.tracking)
            .lineSpacing(token.lineSpacing)
            .padding(.vertical, linesFillLineHeight ? token.halfLeading : 0)
            .underline(token.isUnderlined)
    }
}
