import SwiftUI

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func themed(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

/// Web 设计变量的原样移植。数值对应 `public/styles.css` 的 `:root` 与
/// `:root[data-theme="dark"]`，改动前先看那边的注释——多数颜色是按对比度反推的。
enum PawTheme {
    // MARK: 背景与表面

    /// `--bg-1` 页面底色。
    static let bg1 = themed(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x1C1C1C))
    /// `--bg-2` 卡片/区块底色。深色下是叠在 `bg1` 上的 5% 白。
    static let bg2 = themed(
        light: UIColor(hex: 0xF9F9FA),
        dark: UIColor(hex: 0xFFFFFF, alpha: 0.05)
    )
    /// `--surface-1` 毛玻璃表面。
    static let surface1 = themed(
        light: UIColor(hex: 0xFFFFFF, alpha: 0.8),
        dark: UIColor(hex: 0xFFFFFF, alpha: 0.06)
    )

    // MARK: 墨色 alpha 阶梯

    /// `--ink` 主前景色。浅色是纯黑，深色是纯白。
    static let ink = themed(light: UIColor(hex: 0x000000), dark: UIColor(hex: 0xFFFFFF))
    /// `--ink-80`
    static let ink80 = inkRamp(0.8)
    /// `--ink-40` 次要文字。
    static let ink40 = inkRamp(0.4)
    /// `--ink-20` 分段控件选中块、滑杆等。
    static let ink20 = inkRamp(0.2)
    /// `--ink-10` 发丝线。
    static let ink10 = inkRamp(0.1)
    /// `--ink-4` 轨道底色。
    static let ink4 = inkRamp(0.04)

    private static func inkRamp(_ alpha: CGFloat) -> Color {
        themed(
            light: UIColor(hex: 0x000000, alpha: alpha),
            dark: UIColor(hex: 0xFFFFFF, alpha: alpha)
        )
    }

    // MARK: 染色标签

    /// `--tint-blue`
    static let tintBlue = themed(
        light: UIColor(hex: 0xE6F1FD),
        dark: UIColor(hex: 0x7DBBFF, alpha: 0.16)
    )
    /// `--on-tint-blue` 单利标签前景。
    static let onTintBlue = themed(light: UIColor(hex: 0x0B5CAD), dark: UIColor(hex: 0x7DBBFF))
    /// `--tint-green`
    static let tintGreen = themed(
        light: UIColor(hex: 0xE3F5E9),
        dark: UIColor(hex: 0x3DDC84, alpha: 0.16)
    )
    /// `--on-tint-green` 生息类标签前景。
    static let onTintGreen = themed(light: UIColor(hex: 0x0F6D36), dark: UIColor(hex: 0x3DDC84))
    /// `--tint-orange`
    static let tintOrange = themed(
        light: UIColor(hex: 0xFBEEDD),
        dark: UIColor(hex: 0xFFB340, alpha: 0.16)
    )
    /// `--on-tint-orange` 每日复利标签前景。
    static let onTintOrange = themed(light: UIColor(hex: 0x8A4B00), dark: UIColor(hex: 0xFFB340))
    /// `--on-tint` 染色卡片上的前景色。
    static let onTint = themed(light: UIColor(hex: 0x000000), dark: UIColor(hex: 0xFFFFFF))

    // MARK: 语义色

    /// `--accent`
    static let accent = themed(light: UIColor(hex: 0x007AFF), dark: UIColor(hex: 0x0A84FF))
    /// `--gain`
    static let gain = themed(light: UIColor(hex: 0x12803F), dark: UIColor(hex: 0x3DDC84))
    /// `--loss`
    static let loss = themed(light: UIColor(hex: 0xC0392B), dark: UIColor(hex: 0xF87171))
    /// `--flat` 零涨跌。
    static let flat = themed(light: UIColor(hex: 0x6B6B6B), dark: UIColor(hex: 0x8E8E8E))

    // MARK: 美股交易时段

    /// `--session-open`
    static let sessionOpen = themed(light: UIColor(hex: 0x12803F), dark: UIColor(hex: 0x3DDC84))
    /// `--session-pre`
    static let sessionPre = themed(light: UIColor(hex: 0xA35F00), dark: UIColor(hex: 0xF5A623))
    /// `--session-after`
    static let sessionAfter = themed(light: UIColor(hex: 0x0A6ED1), dark: UIColor(hex: 0x4DA3FF))
    /// `--session-night`
    static let sessionNight = themed(light: UIColor(hex: 0x5B4BD6), dark: UIColor(hex: 0xA99CFF))
    /// `--session-closed`
    static let sessionClosed = themed(light: UIColor(hex: 0x6B6B6B), dark: UIColor(hex: 0x8E8E8E))

    // MARK: 图表序列色

    /// `--series-*`
    static let seriesBlue = Color(uiColor: UIColor(hex: 0x7DBBFF))
    static let seriesCyan = Color(uiColor: UIColor(hex: 0xA0BCE8))
    static let seriesMint = Color(uiColor: UIColor(hex: 0x6BE6D3))
    static let seriesPurple = Color(uiColor: UIColor(hex: 0xB899EB))
    static let seriesGreen = Color(uiColor: UIColor(hex: 0x71DD8C))

    // MARK: 圆角

    /// `--radius-block`
    static let radiusBlock: CGFloat = 20
    /// `--radius-card`
    static let radiusCard: CGFloat = 16
    /// 输入框、按钮等控件圆角。
    static let radiusControl: CGFloat = 14

    // MARK: 字体

    /// 卡片内大额数字：Web 24px / 600。
    static let moneyLarge = PawFont.inter(24, weight: .semibold).monospacedDigit()
    /// 汇率行数字：Web 20px / 600。
    static let moneyMedium = PawFont.inter(20, weight: .semibold).monospacedDigit()
    /// 总资产等主数字：Web 30px / 650，静态字重取最接近的 SemiBold。
    static let moneyHero = PawFont.inter(30, weight: .semibold).monospacedDigit()

    // MARK: 兼容旧调用点
    //
    // 尚未按 Web 复刻的界面仍在用这些名字，逐屏改造时会替换掉。

    static let quietBlue = tintBlue
    static let cardRadius = radiusBlock
    static let controlRadius: CGFloat = 12
    static let contentWidth: CGFloat = 760
}

/// 圆形图标徽章。随 Dynamic Type 缩放，但设上限，避免辅助字号下挤掉正文空间。
struct PawBadge<Label: View>: View {
    private let base: CGFloat
    private let label: Label

    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1

    init(base: CGFloat = 42, @ViewBuilder label: () -> Label) {
        self.base = base
        self.label = label()
    }

    private var diameter: CGFloat {
        base * min(scale, 1.6)
    }

    var body: some View {
        label
            .frame(width: diameter, height: diameter)
            .background(PawTheme.quietBlue, in: Circle())
    }
}

/// 页首的「徽章 + 标题 + 说明」。辅助字号下改为纵向排列，避免徽章与折行文字挤在一起。
struct PawIntroHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            PawBadge {
                Image(systemName: symbol)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PawTheme.accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

struct PawCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: PawTheme.cardRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }
}

struct PawSectionHeading: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PawFeatureScaffold: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
        }
    }
}


/// 全 App 的动效口径。
///
/// 一律走 iOS 17 自带的 spring 预设（`.snappy` / `.smooth` / `.bouncy`），不再手写
/// `.easeOut(duration:)`。系统预设是按感知速度调好的弹簧，位移和尺寸变化用它收尾时不会
/// 像缓动曲线那样「到位了还在挪」；被打断时也能从当前速度接着走，而不是跳一下重来——
/// 列表连点展开、连点切换标的时差别最明显。
///
/// 新加动画请从这里取值，不要就地写时长。用户对这套节奏提过一次「感觉慢、有延迟」，
/// 集中在一处才好整体调。
enum PawMotion {
    /// 展开、收起、插入删除等会改变布局的变化。
    static let expand: Animation = .snappy(duration: 0.28, extraBounce: 0)

    /// 选中态切换：分段控件的选中块、箭头旋转这类小位移。
    static let selection: Animation = .snappy(duration: 0.22, extraBounce: 0)

    /// 元素进出场：toast、行情轮播。进场用弹簧，收尾干净。
    static let appear: Animation = .snappy(duration: 0.3, extraBounce: 0.08)

    /// 出场比进场快一档——东西要走的时候，没人愿意等它慢慢飘。
    static let disappear: Animation = .smooth(duration: 0.18)

    /// 按压反馈。要短到手指还没离开就已经到位。
    static let press: Animation = .snappy(duration: 0.12, extraBounce: 0)
}

/// Web 的 `font-family: Inter, "PingFang SC", "Hiragino Sans GB", ...`。
///
/// Inter 4.1 的四个字重随 App 打包（SIL OFL 1.1，许可证见
/// `ios/PawFolio/Resources/LICENSE-inter.txt`）。Inter 不含中文字形，中文由系统回退到
/// PingFang SC —— 与 Web 的字体栈行为一致。
///
/// 字号用 `fixedSize`，不随 Dynamic Type 缩放：Web 是固定 px，控件高度（输入壳 52、
/// 按钮 40、分段 36）也都是固定值，跟着缩放会撑破这些盒子。这是「界面完全复刻 Web」
/// 的直接后果，已与用户确认。
enum PawFont {
    enum Weight {
        case regular
        case medium
        case semibold
        case bold

        /// 字体文件的 PostScript 名，已从 ttf 的 name table 读出核对。
        var postScriptName: String {
            switch self {
            case .regular: "Inter-Regular"
            case .medium: "Inter-Medium"
            case .semibold: "Inter-SemiBold"
            case .bold: "Inter-Bold"
            }
        }
    }

    static func inter(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }
}
