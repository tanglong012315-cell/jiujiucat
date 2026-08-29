import SwiftUI

// Web 界面的 SwiftUI 复刻件。每个类型对应 `public/styles.css` 里的一个类，
// 数值直接照搬，不要换成 iOS 系统控件——见 `AGENTS.md` 的 Design direction。

/// Web `.shell` 的页面边距与 `.workspace` 的区块间距。
enum PawLayout {
    // 这几个值取自 375 宽下的实测 computed style，不是 CSS 源码里的桌面值：
    // `@media (max-width: 767px)` 把页面边距和卡片内边距整体降到 16，
    // 而所有 iPhone 都在这个断点内。改动前请先在浏览器里量一遍。
    /// `.shell` 的 `padding`，窄屏是 16（桌面才是 28）。
    static let pageHorizontal: CGFloat = 16
    /// `--gap-grid`，区块之间的间距。窄屏不变。
    static let blockGap: CGFloat = 32
    /// 仍保留卡片外观的区块（只有计算页的「投资计划」）的内边距，窄屏是 16。
    static let blockPadding: CGFloat = 16
    /// 区块内部元素的默认间距。
    static let blockSpacing: CGFloat = 16
    /// 贴底导航的内容高度（不含安全区，安全区由系统的 scroll safe area 提供）。
    /// 各页滚动内容用它作为底部留白，否则最后一屏会被导航挡住。
    static let tabBarHeight: CGFloat = 64

    /// `.metric-grid` 在 `max-width: 389px` 时塌成一列。这里换算成卡片内容宽度：
    /// 389 减去两侧页面边距和卡片内边距。
    static let narrowContentWidth: CGFloat = 389 - pageHorizontal * 2 - blockPadding * 2
}

/// Web 的媒体查询按**视口**宽度生效，不是容器宽度，所以断点判断统一读这个值。
/// 由 `RootTabView` 在根部注入。
private struct PawViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 393
}

private struct PawViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 852
}

extension EnvironmentValues {
    var pawViewportWidth: CGFloat {
        get { self[PawViewportWidthKey.self] }
        set { self[PawViewportWidthKey.self] = newValue }
    }

    var pawViewportHeight: CGFloat {
        get { self[PawViewportHeightKey.self] }
        set { self[PawViewportHeightKey.self] = newValue }
    }
}

/// 全 App 唯一的分割线。厚度固定 0.5pt——用户定的统一口径，不随 `displayScale` 变。
///
/// 不要再手写 `Rectangle().fill(PawTheme.ink10).frame(height: …)`：先前四个调用点写出了
/// 两种厚度，标签栏是 0.5、其余是 1，深色下这点差别看得很清楚。
struct PawDivider: View {
    /// 两端留白。列表行之间通常留出与行内容相同的横向内边距。
    var insets: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(PawTheme.ink10)
            .frame(height: PawDivider.thickness)
            .padding(.horizontal, insets)
    }

    static let thickness: CGFloat = 0.5
}

/// Web `.card`：无边框无阴影，`--bg-2` 底加 `--radius-block` 圆角。
struct PawBlock<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = PawLayout.blockSpacing, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(PawLayout.blockPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PawTheme.bg2,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusBlock, style: .continuous)
        )
    }
}

/// Web `.field-label`：12/16，`--ink-40`。
struct PawFieldLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(PawFont.inter(12))
            .foregroundStyle(PawTheme.ink40)
    }
}

/// Web `.input-shell`：`--ink-4` 底，`--radius-card` 圆角，默认 52 高。
struct PawInputShell<Content: View>: View {
    private let height: CGFloat
    private let horizontalPadding: CGFloat
    private let spacing: CGFloat
    private let content: Content

    init(
        height: CGFloat = 52,
        horizontalPadding: CGFloat = 16,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
    }
}

/// Web `.quick-amounts`：五等分，36 高，选中时前景背景对调。
struct PawQuickAmounts: View {
    let amounts: [Double]
    let selected: Double?
    let title: (Double) -> String
    let onSelect: (Double) -> Void

    @Environment(\.pawViewportWidth) private var viewportWidth

    var body: some View {
        // `@media (max-width: 380px)` 把间距收到 4。
        HStack(spacing: viewportWidth < 380 ? 4 : 8) {
            ForEach(amounts, id: \.self) { amount in
                let isSelected = selected == amount

                Button {
                    onSelect(amount)
                } label: {
                    Text(title(amount))
                        .font(PawFont.inter(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(isSelected ? PawTheme.bg1 : PawTheme.ink)
                        .background(
                            isSelected ? PawTheme.ink : PawTheme.ink4,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Web `input[type="range"]`：2pt 轨道，16pt 圆钮带 3pt 描边环。
/// SwiftUI 的 `Slider` 无法做到这个外观，所以自绘。
struct PawSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let trackHeight: CGFloat = 2
    private let thumbDiameter: CGFloat = 16
    private let thumbRing: CGFloat = 3

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span).clamped(to: 0...1)
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - thumbDiameter, 1)
            let thumbX = thumbDiameter / 2 + travel * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PawTheme.ink10)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(PawTheme.ink)
                    .frame(width: thumbX, height: trackHeight)

                Circle()
                    .fill(PawTheme.ink)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle()
                            .strokeBorder(PawTheme.bg1, lineWidth: thumbRing)
                    )
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = ((gesture.location.x - thumbDiameter / 2) / travel)
                            .clamped(to: 0...1)
                        value = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: thumbDiameter)
    }
}

/// Web `.segmented`：`--ink-4` 槽，选中块用 `--segment-active`（即 `--ink-20`）。
struct PawSegmented<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    /// 选中块在两个分段之间滑过去。`matchedGeometryEffect` 让它是同一个矩形在移动，
    /// 而不是这边淡出、那边淡入——后者在只有两段时看着像闪了一下。
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    withAnimation(PawMotion.selection) { selection = option }
                } label: {
                    Text(title(option))
                        .font(PawFont.inter(14, weight: isSelected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(isSelected ? PawTheme.ink : PawTheme.ink40)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PawTheme.ink20)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

/// Web `.calculate-btn`：满宽 40 高，`--ink` 底配 `--bg-1` 字。
struct PawPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PawFont.inter(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(PawTheme.bg1)
                .background(
                    PawTheme.ink,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(PawPressableButtonStyle())
    }
}

/// Web 的 `:active { opacity: .7 }`。
struct PawPressableButtonStyle: ButtonStyle {
    /// 整行整卡的按压。缩放幅度要很小：这些是满宽的行，1% 已经足够看出「按下去了」，
    /// 再多就会露出底下的背景边。
    var scale: CGFloat = 0.99

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(PawMotion.press, value: configuration.isPressed)
    }
}

/// Web `.metric`：`--ink-4` 底，标题 60% 不透明，副值 40%。
///
/// `@media (max-width: 767px)` 把内边距降到 `10px 12px`、主数字降到 20/28，
/// 所有 iPhone 都在这个断点内，所以这里按紧凑值写死。389px 那条断点只管列数。
struct PawMetricCard: View {
    let title: String
    let value: String
    let secondary: String?

    @Environment(\.pawViewportWidth) private var viewportWidth

    /// 三档，按 CSS 里的层叠顺序：560 那条把字号压到 17，但 389 那条排在它后面，
    /// 窄到塌成一列时又回到 20。
    private var isSingleColumn: Bool { viewportWidth < 389 }
    private var isCompact: Bool { viewportWidth < 560 }

    private var valueFontSize: CGFloat {
        if isSingleColumn { return 20 }
        return isCompact ? 17 : 24
    }

    private var captionFontSize: CGFloat {
        isCompact && !isSingleColumn ? 11 : 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PawFont.inter(captionFontSize))
                .foregroundStyle(PawTheme.ink.opacity(0.6))

            Text(value)
                .font(PawFont.inter(valueFontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(PawTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let secondary {
                Text(secondary)
                    .font(PawFont.inter(captionFontSize).monospacedDigit())
                    .foregroundStyle(PawTheme.ink.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, isSingleColumn ? 12 : (isCompact ? 10 : 16))
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Web `.period-tabs`：区块标题右侧的小号周期切换。
struct PawPeriodTabs<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    withAnimation(PawMotion.selection) { selection = option }
                } label: {
                    Text(title(option))
                        .font(PawFont.inter(12, weight: isSelected ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 32)
                        .frame(height: 28)
                        .foregroundStyle(isSelected ? PawTheme.ink : PawTheme.ink40)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(PawTheme.ink20)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

/// Web `.sheet-panel`：顶部抓手、居中标题、右上关闭，左上角放破坏性操作，底部可选操作区。
///
/// 高度自适应内容：内容装得下就只占那么高，装不下才滚动。
struct PawSheet<Content: View, Footer: View>: View {
    private let title: String
    private let content: Content
    private let footer: Footer
    /// Web `.sheet-delete-btn`：左上角、`--loss` 色的破坏性操作。
    private let destructiveIcon: String?
    private let destructiveLabel: String?
    private let onDestructive: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.pawViewportHeight) private var viewportHeight
    @State private var contentHeight: CGFloat = 0

    /// 抓手 20 + 标题栏 48；有底部操作区时再加它的 73（1 发丝线 + 12 + 40 按钮 + 20）。
    private var chromeHeight: CGFloat {
        68 + (Footer.self == EmptyView.self ? 0 : 73)
    }

    /// 弹层只有一个高度：内容需要多少就多少，超过屏幕能给的就封顶、内容区自己滚。
    ///
    /// 上限直接用 `viewportHeight`，**不要**再减 92：那个 92 是 Web 相对 `100dvh`
    /// 留的，而这里拿到的已经是安全区**以内**的高度（状态栏 + Home 指示器合计也差不多
    /// 就是 92），再减一次会白丢近 100pt，表现就是弹层底部内容被压在按钮下面。
    private var detentHeight: CGFloat {
        let maximum = max(viewportHeight, 320)
        guard contentHeight > 0 else { return maximum }
        return min(contentHeight + chromeHeight, maximum)
    }

    init(
        title: String,
        destructiveIcon: String? = nil,
        destructiveLabel: String? = nil,
        onDestructive: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.destructiveIcon = destructiveIcon
        self.destructiveLabel = destructiveLabel
        self.onDestructive = onDestructive
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(PawTheme.ink10)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ZStack {
                Text(title)
                    .font(PawFont.inter(17, weight: .semibold))
                    .foregroundStyle(PawTheme.ink)

                HStack {
                    if let destructiveIcon, let onDestructive {
                        Button(action: onDestructive) {
                            Image(destructiveIcon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundStyle(PawTheme.loss)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PawPressableButtonStyle())
                        .accessibilityLabel(destructiveLabel ?? "删除")
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image("IconClose")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(PawTheme.ink)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PawPressableButtonStyle())
                    .accessibilityLabel("关闭\(title)")
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 20)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .background {
                        // 量一次内容高度，交给 presentationDetents 决定弹层多高。
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: PawSheetContentHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            }
            // 内容不够高时不要留出滚动空间，弹层就贴着内容收住。
            .scrollBounceBehavior(.basedOnSize)

            footerArea
        }
        .background(PawTheme.bg1)
        .onPreferenceChange(PawSheetContentHeightKey.self) { contentHeight = $0 }
        // 只给一个 detent：不要「默认收起、上滑变全屏」那种两段式。
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(26)
        .presentationBackground(PawTheme.bg1)
        // 弹层盖在主界面之上，主界面那个 toast 出口被挡住了，这里要自己挂一个。
        .pawToast()
    }

    @ViewBuilder
    private var footerArea: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 0) {
                PawDivider()

                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
        }
    }
}

private struct PawSheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension PawSheet where Footer == EmptyView {
    init(
        title: String,
        destructiveIcon: String? = nil,
        destructiveLabel: String? = nil,
        onDestructive: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            destructiveIcon: destructiveIcon,
            destructiveLabel: destructiveLabel,
            onDestructive: onDestructive,
            content: content,
            footer: { EmptyView() }
        )
    }
}

/// 资产 logo，取不到就显示首字母——和 Web 的 `applyAssetLogo` 同一套降级。
/// 行情条、快捷添加、持仓行、搜索结果四处共用。
struct PawAssetLogo: View {
    let quoteSymbol: String
    let assetType: AssetType
    let name: String
    /// 没有 logo 时显示的字符，Web 在不同位置分别取 1 位或 2 位。
    let fallbackText: String
    let diameter: CGFloat
    var fallbackFontSize: CGFloat = 11

    @StateObject private var store = AssetLogoStore.shared
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Text(fallbackText)
                    .font(PawFont.inter(fallbackFontSize, weight: .bold))
                    .foregroundStyle(PawTheme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PawTheme.ink10)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: quoteSymbol) {
            image = store.cachedImage(for: quoteSymbol)
            guard image == nil, !store.isUnavailable(quoteSymbol) else { return }
            image = await store.image(
                quoteSymbol: quoteSymbol,
                assetType: assetType,
                name: name
            )
        }
        .accessibilityHidden(true)
    }
}

// 表单字段件。原本是 `HoldingEditorView` 的私有方法，分红记录弹层要用同一套，
// 提到这里共用。对应 Web 的 `.field` / `.input-shell` / `.money-input`。

/// Web `.field`：标签、控件、可选的一行说明。
struct PawEditorField<Content: View>: View {
    private let label: String
    private let hint: String?
    private let content: Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PawFieldLabel(label)

            // 说明贴着控件走，用嵌套的 4pt 间距而不是负 padding——
            // 负 padding 会让外层少算高度。
            VStack(alignment: .leading, spacing: 4) {
                content
                if let hint {
                    Text(hint)
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink40)
                }
            }
        }
    }
}

/// Web `.input-shell` 里放一个文本框。
struct PawTextFieldShell: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .decimalPad
    var isDisabled = false
    var isCompact = false
    /// `.money-input`：前面挂一个 `$`。
    var showsCurrencyPrefix = false
    /// 传了就在右侧挂一枚清除按钮。由调用方决定什么时候有值——空输入时传 nil，
    /// 按钮就不出现。
    var onClear: (() -> Void)?

    var body: some View {
        PawInputShell(horizontalPadding: isCompact ? 12 : 16) {
            if showsCurrencyPrefix {
                Text("$")
                    .font(PawFont.inter(16, weight: .medium))
                    .foregroundStyle(PawTheme.ink40)
            }

            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .font(PawFont.inter(16, weight: .medium).monospacedDigit())
                .foregroundStyle(isDisabled ? PawTheme.ink40 : PawTheme.ink)
                .disabled(isDisabled)

            if let onClear {
                Button(action: onClear) {
                    Image("IconClose")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(PawTheme.ink40)
                        // 图标 16 太小点不准，撑出 44 的热区但不占版面。
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -14)
                .transition(.opacity)
                .accessibilityLabel("清除")
            }
        }
        .animation(PawMotion.selection, value: onClear == nil)
    }
}

/// Web 的日期字段：同样的壳子里放一个紧凑日期选择器。
struct PawDateFieldShell: View {
    @Binding var selection: Date
    var minimumDate: Date?

    var body: some View {
        PawInputShell(horizontalPadding: 12) {
            Group {
                if let minimumDate {
                    DatePicker(
                        "", selection: $selection,
                        in: minimumDate...Date.distantFuture,
                        displayedComponents: .date
                    )
                } else {
                    DatePicker("", selection: $selection, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(PawTheme.ink)

            Spacer(minLength: 0)
        }
    }
}

/// Web 的开关行：左边说明，右边一个原生开关（Web 那边是 checkbox，移动端原生开关更顺手）。
struct PawToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(PawFont.inter(14))
                .foregroundStyle(PawTheme.ink)

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(PawTheme.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
    }
}
