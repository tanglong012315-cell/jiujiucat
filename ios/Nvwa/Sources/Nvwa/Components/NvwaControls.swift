import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct NvwaToggle: View {
    @Binding private var isOn: Bool
    private let accessibilityLabel: String

    public init(isOn: Binding<Bool>, accessibilityLabel: String) {
        _isOn = isOn
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Toggle(accessibilityLabel, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(NvwaToggleStyle())
            .accessibilityLabel(accessibilityLabel)
    }
}

public struct NvwaToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Nvwa.grayPrimary : Nvwa.graySecondary)
                .frame(width: 50, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Nvwa.backgroundContainer)
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.16, extraBounce: 0), value: configuration.isOn)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

public struct NvwaAvatar: View {
    private let initials: String
    private let image: Image?
    private let flag: Image?
    private let diameter: CGFloat
    private let typography: NvwaTypographyToken

    /// 库里画了两档：`2014:7932` 是 42 配 `B-L Semi Bold`，`47:2224` 的个人中心
    /// 大头像是 72 配 `T Semi Bold`；导航栏 `2206:768` 又把实例改写成 40 配
    /// `T-G Medium`。尺寸和字体都不钉死在其中一档，调用方按实际位置给——但字号、
    /// 字重、字距三者必须成套来自同一枚排版 token，不要拆开单给。
    ///
    /// `image` 是宿主注入的头像图（Figma 里没有这档变体，属于代码扩展）：给了就
    /// 铺满圆形、盖掉首字母，没给才回落到首字母。图片由调用方提供，跟图标一样
    /// 不打包进 Nvwa。
    public init(
        initials: String,
        image: Image? = nil,
        flag: Image? = nil,
        diameter: CGFloat = 42,
        typography: NvwaTypographyToken = Nvwa.Typography.bodyLargeSemibold
    ) {
        self.initials = initials
        self.image = image
        self.flag = flag
        self.diameter = diameter
        self.typography = typography
    }

    public var body: some View {
        Text(initials)
            .font(Nvwa.font(typography.size, weight: typography.weight))
            .tracking(typography.tracking)
            .foregroundStyle(Nvwa.grayPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .opacity(image == nil ? 1 : 0)
            .frame(width: diameter, height: diameter)
            .background(Nvwa.backgroundVessel, in: Circle())
            .overlay {
                if let image {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let flag {
                    // 角标跟着直径走，42 时正好是设计稿的 16。
                    let badge = (diameter * 16 / 42).rounded()
                    flag
                        .resizable()
                        .scaledToFill()
                        .frame(width: badge, height: badge)
                        .clipShape(Circle())
                        .padding(2)
                        .background(Nvwa.backgroundMain, in: Circle())
                }
            }
            .accessibilityLabel(initials)
    }
}

public enum NvwaTagTone: CaseIterable, Sendable {
    case gray
    case green
    case red
    case blue

    var foregroundRole: NvwaTagColorRole {
        switch self {
        case .gray: .grayPrimary
        case .green: .marketBuy
        case .red: .sentimentNegative
        case .blue: .primaryGreen
        }
    }

    var backgroundRole: NvwaTagColorRole {
        switch self {
        case .gray: .backgroundInput
        case .green: .alphaGreen20
        case .red: .alphaRed20
        case .blue: .alphaBlue10
        }
    }
}

enum NvwaTagColorRole: Equatable, Sendable {
    case grayPrimary
    case marketBuy
    case sentimentNegative
    case primaryGreen
    case backgroundInput
    case alphaGreen20
    case alphaRed20
    case alphaBlue10

    fileprivate var color: Color {
        switch self {
        case .grayPrimary: Nvwa.grayPrimary
        case .marketBuy: Nvwa.marketBuy
        case .sentimentNegative: Nvwa.sentimentNegative
        case .primaryGreen: Nvwa.primaryGreen
        case .backgroundInput: Nvwa.backgroundInput
        case .alphaGreen20: Nvwa.alphaGreen20
        case .alphaRed20: Nvwa.alphaRed20
        case .alphaBlue10: Nvwa.alphaBlue10
        }
    }
}

public enum NvwaTagIconPlacement: Sendable {
    case none
    case leading
    case trailing
}

public struct NvwaTag: View {
    private let title: String
    private let tone: NvwaTagTone
    private let icon: Image?
    private let iconPlacement: NvwaTagIconPlacement
    /// 旋转一枚箭头图标来表达展开/收起，比在两张不同的图之间切换更顺滑——
    /// SwiftUI 能对角度插值，但两张贴图之间没有交叉淡入淡出（2026-09-03，
    /// 持仓合并卡的展开箭头）。
    private let iconRotationDegrees: Double

    public init(
        _ title: String,
        tone: NvwaTagTone = .gray,
        icon: Image? = nil,
        iconPlacement: NvwaTagIconPlacement = .none,
        iconRotationDegrees: Double = 0
    ) {
        self.title = title
        self.tone = tone
        self.icon = icon
        self.iconPlacement = iconPlacement
        self.iconRotationDegrees = iconRotationDegrees
    }

    public var body: some View {
        HStack(spacing: 0) {
            if iconPlacement == .leading, let icon {
                tagIcon(icon)
            }

            Text(LocalizedStringKey(title))
                .font(Nvwa.caption2)
                .tracking(0.1)
                .lineLimit(1)

            if iconPlacement == .trailing, let icon {
                tagIcon(icon)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(foreground)
        .frame(height: 16)
        .background(background, in: Capsule())
    }

    private func tagIcon(_ image: Image) -> some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(iconRotationDegrees))
    }

    private var foreground: Color {
        tone.foregroundRole.color
    }

    private var background: Color {
        tone.backgroundRole.color
    }
}

public enum NvwaSegmentSize: Sendable {
    case normal
    case small
}

enum NvwaSegmentMetrics {
    static let selectionAnimationDuration = 0.06

    static func height(for size: NvwaSegmentSize) -> CGFloat {
        size == .normal ? 40 : 28
    }

    static func itemHeight(for size: NvwaSegmentSize) -> CGFloat {
        size == .normal ? 36 : 24
    }

    static func fixedWidth(for size: NvwaSegmentSize) -> CGFloat? {
        size == .normal ? 345 : nil
    }

    static let smallAuthoredExampleWidth: CGFloat = 89

    static func isFigmaAuthored(size: NvwaSegmentSize, optionCount: Int) -> Bool {
        switch size {
        case .normal: (2...4).contains(optionCount)
        case .small: optionCount == 3
        }
    }
}

public struct NvwaSegmentControl<Option: Hashable>: View {
    private let options: [Option]
    private let title: (Option) -> String
    private let size: NvwaSegmentSize
    private let expandsHorizontally: Bool
    /// 选中项的文字色。默认是 `Text/Blue`；交易页的 Buy / Sell 传涨跌色
    /// （产品稿 `154:11963` / `154:12261`），涨跌是语义色、不跟品牌色走。
    private let selectedTint: Color?
    @Binding private var selection: Option
    @Namespace private var selectedBackground
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        options: [Option],
        selection: Binding<Option>,
        size: NvwaSegmentSize = .normal,
        expandsHorizontally: Bool = false,
        selectedTint: Color? = nil,
        title: @escaping (Option) -> String
    ) {
        self.options = options
        _selection = selection
        self.size = size
        self.expandsHorizontally = expandsHorizontally
        self.selectedTint = selectedTint
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(LocalizedStringKey(title(option)))
                        .font(size == .normal ? Nvwa.bodyMediumSemibold : Nvwa.bodySmallSemibold)
                        .tracking(size == .normal ? 0.175 : 0.12)
                        .foregroundStyle(selected ? (selectedTint ?? Nvwa.textBlue) : Nvwa.graySecondary)
                        // Only the pill moves. Animating text color in the same
                        // transaction reads as a flash during rapid switching.
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                        .padding(.horizontal, size == .small ? 8 : 0)
                        .frame(maxWidth: size == .normal ? .infinity : nil)
                        .frame(height: NvwaSegmentMetrics.itemHeight(for: size))
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Nvwa.backgroundContainer)
                                    .matchedGeometryEffect(id: "selection", in: selectedBackground)
                                    // The default insertion/removal fade competes
                                    // with the geometry move and causes a blink.
                                    .transition(.identity)
                            }
                        }
                        // 没有这一句时，未选中项的可点区域只有文字本身（选中项
                        // 靠那枚胶囊底才碰巧整格可点）——摸上去就是「非得点在
                        // 字上」。补上之后每一格按自己的 frame 平分热区。
                        .contentShape(Rectangle())
                        .animation(
                            reduceMotion
                                ? nil
                                : .linear(duration: NvwaSegmentMetrics.selectionAnimationDuration),
                            value: selection
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: NvwaSegmentMetrics.height(for: size))
        .frame(
            width: expandsHorizontally ? nil : NvwaSegmentMetrics.fixedWidth(for: size)
        )
        .frame(maxWidth: expandsHorizontally ? .infinity : nil)
        .background(Nvwa.backgroundVessel, in: Capsule())
    }
}

public struct NvwaCheckbox: View {
    @Binding private var isChecked: Bool
    private let title: String
    private let checkedIcon: Image
    private let uncheckedIcon: Image

    public init(
        _ title: String,
        isChecked: Binding<Bool>,
        checkedIcon: Image,
        uncheckedIcon: Image
    ) {
        self.title = title
        _isChecked = isChecked
        self.checkedIcon = checkedIcon
        self.uncheckedIcon = uncheckedIcon
    }

    public var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 4) {
                (isChecked ? checkedIcon : uncheckedIcon)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isChecked ? Nvwa.grayPrimary : Nvwa.graySecondary)

                Text(LocalizedStringKey(title))
                    .font(Nvwa.bodySmall)
                    .tracking(0.12)
                    .foregroundStyle(Nvwa.grayPrimary)
            }
            .frame(minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isChecked ? "Checked" : "Unchecked")
    }
}

public enum NvwaHintLevel: Int, Sendable {
    case neutral = 1
    case positive = 2
    case warning = 3
    case negative = 4

    /// 提示插画的底色。`2062:773` 的四个等级并不是一套写法：level 1 用实色
    /// `Line`、level 3 用实色 `Sentiment/Warning`，而 level 2 / 4 用的是和胶囊
    /// 底色**同一枚** 20% 色板——两层叠在一起才比背景深一点点。看着不统一，但这
    /// 是稿子里画的，不要顺手都改成实色或都改成 20%。
    var markBackground: Color {
        switch self {
        case .neutral: Nvwa.line
        case .positive: Nvwa.alphaGreen20
        case .warning: Nvwa.sentimentWarning
        case .negative: Nvwa.alphaRed20
        }
    }
}

enum NvwaHintMetrics {
    static let minimumHeight: CGFloat = 32
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 6
    static let contentSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 10
    static let rightIconSize: CGFloat = 20
    /// 提示插画：12pt 的 Warning 插画，顶部再让 4pt——`2232:127` 那个 12×16、
    /// `paddingTop: 4` 的小框就是干这个的，让 12pt 的圆片对准首行文字的字面
    /// 中线，而不是对准行盒顶部。
    static let markSize: CGFloat = 12
    static let markTopInset: CGFloat = 4
}

public struct NvwaHint: View {
    private let text: LocalizedStringKey
    private let highlight: String?
    private let highlightColor: Color?
    private let level: NvwaHintLevel
    private let rightIcon: Image?
    private let rightIconAccessibilityLabel: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// `highlight` 跟在正文后面，默认用 Primary Green 显示——设计里的估算提示
    /// （例如 `Daily Interest: 12.23 USD`）就是这个两段式。收益类数字按
    /// AGENTS.md 传 `Nvwa.marketBuy`。
    public init(
        _ text: String,
        highlight: String? = nil,
        highlightColor: Color? = nil,
        level: NvwaHintLevel = .neutral,
        rightIcon: Image? = nil,
        rightIconAccessibilityLabel: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.text = LocalizedStringKey(text)
        self.highlight = highlight
        self.highlightColor = highlightColor
        self.level = level
        self.rightIcon = rightIcon
        self.rightIconAccessibilityLabel = rightIconAccessibilityLabel
        self.actionTitle = actionTitle
        self.action = action
    }

    public init(
        localizedText text: LocalizedStringKey,
        highlight: String? = nil,
        highlightColor: Color? = nil,
        level: NvwaHintLevel = .neutral,
        rightIcon: Image? = nil,
        rightIconAccessibilityLabel: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.highlight = highlight
        self.highlightColor = highlightColor
        self.level = level
        self.rightIcon = rightIcon
        self.rightIconAccessibilityLabel = rightIconAccessibilityLabel
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .top, spacing: NvwaHintMetrics.contentSpacing) {
            mark

            textContent
                .nvwaTextStyle(Nvwa.Typography.bodySmall)

            if let rightIcon {
                Spacer(minLength: 0)
                rightIcon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: NvwaHintMetrics.rightIconSize,
                        height: NvwaHintMetrics.rightIconSize
                    )
                    .foregroundStyle(Nvwa.grayPrimary)
                    .accessibilityLabel(rightIconAccessibilityLabel ?? "More")
            }
        }
        .padding(.horizontal, NvwaHintMetrics.horizontalPadding)
        .padding(.vertical, NvwaHintMetrics.verticalPadding)
        .frame(minHeight: NvwaHintMetrics.minimumHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            background,
            in: RoundedRectangle(
                cornerRadius: NvwaHintMetrics.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            if level == .neutral {
                RoundedRectangle(
                    cornerRadius: NvwaHintMetrics.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(Nvwa.line, lineWidth: 1)
            }
        }
    }

    /// 提示插画：Key Feature 的 Warning 那枚缩到 12pt，底色跟等级走。
    /// 稿子的八个变体都带着它，所以这里不做成可选项。
    private var mark: some View {
        NvwaKeyFeatureIcon(
            .warning,
            containerSize: NvwaHintMetrics.markSize,
            background: level.markBackground
        )
        .padding(.top, NvwaHintMetrics.markTopInset)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var textContent: some View {
        if let actionTitle, let action {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(text)
                    .foregroundStyle(Nvwa.grayPrimary)

                Button(action: action) {
                    Text(LocalizedStringKey(actionTitle))
                }
                    .font(Nvwa.bodySmallSemibold)
                    .foregroundStyle(Nvwa.primaryGreen)
                    .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let highlight {
            (Text(text).foregroundColor(Nvwa.grayPrimary)
                + Text(highlight).foregroundColor(highlightColor ?? Nvwa.primaryGreen))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .foregroundStyle(Nvwa.grayPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var background: Color {
        switch level {
        case .neutral: Nvwa.backgroundVessel
        case .positive: Nvwa.alphaGreen20
        case .warning: Nvwa.alphaYellow20
        case .negative: Nvwa.alphaRed20
        }
    }

}

enum NvwaToastMetrics {
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6
    static let minimumTextHeight: CGFloat = 20
    static let maximumWidth: CGFloat = 300
    static let cornerRadius: CGFloat = 10

    static var maximumTextWidth: CGFloat {
        maximumWidth - horizontalPadding * 2
    }
}

public struct NvwaToast: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            toastSurface {
                toastText
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
            }

            toastSurface {
                toastText
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(
                        width: NvwaToastMetrics.maximumTextWidth,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: NvwaToastMetrics.maximumWidth)
        .accessibilityAddTraits(.isStaticText)
    }

    private var toastText: some View {
        Text(LocalizedStringKey(text))
            .font(Nvwa.bodySmall)
            .tracking(0.12)
            .foregroundStyle(Nvwa.backgroundMain)
    }

    private func toastSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(minHeight: NvwaToastMetrics.minimumTextHeight, alignment: .leading)
            .padding(.horizontal, NvwaToastMetrics.horizontalPadding)
            .padding(.vertical, NvwaToastMetrics.verticalPadding)
            .background(
                Nvwa.grayPrimary,
                in: RoundedRectangle(
                    cornerRadius: NvwaToastMetrics.cornerRadius,
                    style: .continuous
                )
            )
    }
}

/// Figma `2070:825` 把 Section 拆成了四个组件集，不是一个组件的四种改法。
/// 四档共用同一处文字排版和「立刻生效」的选中反馈，差别在底色、几何和图标槽位。
public enum NvwaSectionStyle: Sendable, CaseIterable {
    /// `2071:843` Primary Section：选中 `Alpha/Blue 10%` + `Primary Green`。
    case primary
    /// `2282:303` Sec Section：同样的药丸，选中换成 `BG/Vessel` + `Text/Primary`。
    case secondary
    /// `2282:248` Currency Section：36 高、带一枚 20pt 图标；选中 `BG/Vessel`，
    /// **两态文字同为 `Text/Primary`**——有了图标和底色之后，文字不再兼职当选中
    /// 指示。稿子上就是这么画的，不是漏改。
    case currency
    /// `2282:236` Text Section：没有底色也没有内边距的纯文字页签，
    /// 16pt 图标 + `B-S Regular`，靠文字颜色区分 Active。
    case text
}

enum NvwaSectionMetrics {
    /// Primary / Sec 两档药丸（`2071:843`、`2282:303`）：28 高、左右 16、上下 3、圆角 24。
    static let height: CGFloat = 28
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 3
    static let cornerRadius: CGFloat = 24
    /// Currency（`2282:248`）：36 高、左右 10、图标 20、间距 5。稿子上的圆角写的是
    /// 66，超过半个高度，落到代码里就是一颗胶囊。
    static let currencyHeight: CGFloat = 36
    static let currencyHorizontalPadding: CGFloat = 10
    static let currencyIconSize: CGFloat = 20
    static let currencyIconSpacing: CGFloat = 5
    /// Text（`2282:236`）：图标 16、间距 4；20 的高度是 `B-S Regular` 的行盒撑出来的，
    /// 不是钉死的容器高。
    static let textIconSize: CGFloat = 16
    static let textIconSpacing: CGFloat = 4
    /// Section is a high-frequency filter control. Its selection feedback is
    /// intentionally immediate and must not inherit a feature-level animation.
    static let selectionAnimation: Animation? = nil

    /// `.text` 没有固定高度，返回 `nil` 让行盒自己说了算。
    static func height(for style: NvwaSectionStyle) -> CGFloat? {
        switch style {
        case .primary, .secondary: height
        case .currency: currencyHeight
        case .text: nil
        }
    }

    static func horizontalPadding(for style: NvwaSectionStyle) -> CGFloat {
        switch style {
        case .primary, .secondary: horizontalPadding
        case .currency: currencyHorizontalPadding
        case .text: 0
        }
    }

    static func verticalPadding(for style: NvwaSectionStyle) -> CGFloat {
        switch style {
        case .primary, .secondary: verticalPadding
        case .currency, .text: 0
        }
    }

    // Primary / Sec 在 Figma 里只有 `Icon=No`。宿主真塞了图标就按 Text 那档的
    // 16pt 排，不替稿子编一个没画过的尺寸。
    static func iconSize(for style: NvwaSectionStyle) -> CGFloat {
        switch style {
        case .currency: currencyIconSize
        case .primary, .secondary, .text: textIconSize
        }
    }

    static func iconSpacing(for style: NvwaSectionStyle) -> CGFloat {
        switch style {
        case .currency: currencyIconSpacing
        case .primary, .secondary, .text: textIconSpacing
        }
    }

    static func typography(for style: NvwaSectionStyle) -> NvwaTypographyToken {
        switch style {
        case .primary, .secondary, .currency: Nvwa.Typography.bodySmallSemibold
        case .text: Nvwa.Typography.bodySmall
        }
    }
}

/// 一枚 Section。图标是宿主注入的（Nvwa 不带图标集），组件只负责槽位尺寸和间距。
public struct NvwaSection<Icon: View>: View {
    private let title: String
    private let style: NvwaSectionStyle
    private let isSelected: Bool
    private let expandsHorizontally: Bool
    private let icon: Icon?
    private let action: () -> Void

    private init(
        title: String,
        style: NvwaSectionStyle,
        isSelected: Bool,
        expandsHorizontally: Bool,
        icon: Icon?,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isSelected = isSelected
        self.expandsHorizontally = expandsHorizontally
        self.icon = icon
        self.action = action
    }

    /// 带图标的一档（`.currency`、`.text`）。
    public init(
        _ title: String,
        style: NvwaSectionStyle,
        isSelected: Bool,
        expandsHorizontally: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            style: style,
            isSelected: isSelected,
            expandsHorizontally: expandsHorizontally,
            icon: icon(),
            action: action
        )
    }

    public var body: some View {
        Button(action: performAction) {
            HStack(spacing: icon == nil ? 0 : NvwaSectionMetrics.iconSpacing(for: style)) {
                if let icon {
                    icon.frame(
                        width: NvwaSectionMetrics.iconSize(for: style),
                        height: NvwaSectionMetrics.iconSize(for: style)
                    )
                }

                Text(LocalizedStringKey(title))
                    .nvwaTextStyle(
                        NvwaSectionMetrics.typography(for: style),
                        // 三档药丸的高度由 `frame(height:)` 钉死，再补首尾的
                        // half-leading 只会把文字往下推；`.text` 没有容器，
                        // 20pt 的行盒就是它的高度。
                        linesFillLineHeight: style == .text
                    )
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            // 等宽排布时槽位宽度由外部决定，再加内边距会把文字挤掉
            // （`1,000K` 会截成 `1,00…`）。设计稿里那排等宽实例也是文字占满
            // 槽位的，内边距只对按内容取宽的单个 Section 有意义。
            .padding(
                .horizontal,
                expandsHorizontally ? 0 : NvwaSectionMetrics.horizontalPadding(for: style)
            )
            .padding(.vertical, NvwaSectionMetrics.verticalPadding(for: style))
            .frame(maxWidth: expandsHorizontally ? .infinity : nil)
            .frame(height: NvwaSectionMetrics.height(for: style))
            .background(background, in: shape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A host can mutate focus, charts, or other animated state from the
        // callback. Override that inherited transaction as well as any local
        // implicit animation so selection feedback always remains immediate.
        .transaction { transaction in
            transaction.animation = NvwaSectionMetrics.selectionAnimation
            transaction.disablesAnimations = true
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        switch style {
        case .primary: isSelected ? Nvwa.primaryGreen : Nvwa.graySecondary
        case .secondary, .text: isSelected ? Nvwa.grayPrimary : Nvwa.graySecondary
        // 两态同色，理由见 `NvwaSectionStyle.currency`。稿子上是 unbound 的纯黑，
        // 深色下要跟着主文字色翻过来，所以落到 `Text/Primary` 而不是 `Text/Black`。
        case .currency: Nvwa.grayPrimary
        }
    }

    private var background: Color {
        guard isSelected else { return .clear }
        switch style {
        case .primary: return Nvwa.alphaBlue10
        case .secondary, .currency: return Nvwa.backgroundVessel
        case .text: return .clear
        }
    }

    private var shape: AnyShape {
        switch style {
        case .currency: AnyShape(Capsule())
        case .primary, .secondary, .text:
            AnyShape(
                RoundedRectangle(
                    cornerRadius: NvwaSectionMetrics.cornerRadius,
                    style: .continuous
                )
            )
        }
    }

    private func performAction() {
        var transaction = Transaction(animation: NvwaSectionMetrics.selectionAnimation)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}

public extension NvwaSection where Icon == EmptyView {
    /// 不带图标的一档。`.primary` / `.secondary` 在 Figma 里只有这一种。
    init(
        _ title: String,
        style: NvwaSectionStyle = .primary,
        isSelected: Bool,
        expandsHorizontally: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            style: style,
            isSelected: isSelected,
            expandsHorizontally: expandsHorizontally,
            icon: nil,
            action: action
        )
    }
}

enum NvwaSliderMetrics {
    static let height: CGFloat = 16
    static let trackHeight: CGFloat = 4
    static let thumbDiameter: CGFloat = 12
    static let thumbBorderWidth: CGFloat = 2
    /// Figma `2072:865`：4pt 轨道两端为 2pt 圆角。
    static let trackCornerRadius: CGFloat = 2
    /// 震动的档位数。全程 20 档，和无障碍 `adjustableAction` 的步长是同一个数——
    /// 手指滑过去和用旁白按一下，走的应该是同样粗细的刻度。
    static let hapticSteps = 20
}

public struct NvwaSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    /// 上一次震动停在第几档。滑过一档才震一下——按住不动、或者一路滑到底
    /// 每帧都震，手感是持续的嗡嗡声，不是刻度。
    @State private var lastHapticStep: Int?
    #if os(iOS)
    @State private var haptics = UISelectionFeedbackGenerator()
    #endif

    public init(value: Binding<Double>, in range: ClosedRange<Double> = 0...1) {
        _value = value
        self.range = range
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let progress = normalizedValue
            let thumb = NvwaSliderMetrics.thumbDiameter
            let thumbX = progress * max(width - thumb, 0) + thumb / 2

            ZStack(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: NvwaSliderMetrics.trackCornerRadius,
                    style: .continuous
                )
                    .fill(Nvwa.backgroundInput)
                    .frame(height: NvwaSliderMetrics.trackHeight)

                RoundedRectangle(
                    cornerRadius: NvwaSliderMetrics.trackCornerRadius,
                    style: .continuous
                )
                    .fill(Nvwa.primaryGreen)
                    .frame(width: thumbX, height: NvwaSliderMetrics.trackHeight)

                Circle()
                    .fill(Nvwa.backgroundMain)
                    .frame(width: thumb, height: thumb)
                    .overlay(
                        Circle().strokeBorder(
                            Nvwa.primaryGreen,
                            lineWidth: NvwaSliderMetrics.thumbBorderWidth
                        )
                    )
                    .position(x: thumbX, y: NvwaSliderMetrics.height / 2)
            }
            .frame(height: NvwaSliderMetrics.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let progress = min(max(gesture.location.x / width, 0), 1)
                        value = range.lowerBound + progress * (range.upperBound - range.lowerBound)
                        notchHaptic(at: progress)
                    }
                    // 松手后清掉档位，下一次从同一处按下去照样有反馈。
                    .onEnded { _ in lastHapticStep = nil }
            )
        }
        .frame(height: NvwaSliderMetrics.height)
        .onAppear(perform: prepareHaptics)
        .accessibilityElement()
        .accessibilityLabel("Slider")
        .accessibilityValue(Text(value.formatted()))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func notchHaptic(at progress: Double) {
        let step = Int((progress * Double(NvwaSliderMetrics.hapticSteps)).rounded())
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        #if os(iOS)
        haptics.selectionChanged()
        // 打完一次就得重新预热，否则下一档会慢半拍。
        haptics.prepare()
        #endif
    }

    private func prepareHaptics() {
        #if os(iOS)
        haptics.prepare()
        #endif
    }
}
