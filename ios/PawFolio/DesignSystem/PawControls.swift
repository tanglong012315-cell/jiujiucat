import Nvwa
import SwiftUI
import UIKit

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
    /// **只给 iOS 17–25 的自绘导航条用** —— iOS 26 走原生 `TabView`，底部留白由
    /// 系统自己下发。别直接用它，用 `View.pawTabBarBottomMargin()`。
    static let tabBarHeight: CGFloat = 64

    /// `.metric-grid` 在 `max-width: 389px` 时塌成一列。这里换算成卡片内容宽度：
    /// 389 减去两侧页面边距和卡片内边距。
    static let narrowContentWidth: CGFloat = 389 - pageHorizontal * 2 - blockPadding * 2
}

/// 滚动内容给贴底导航让出的下边距。
///
/// iOS 26 用原生 `TabView`，标签栏的安全区由系统下发给内部的 ScrollView，这里再加
/// 一份就会变成双倍留白，所以什么都不做。iOS 17–25 是 `overlay` 上去的自绘导航条，
/// 那份 inset 传不进各页的 ScrollView（表现是底部内容被挡住、拖出来一松手又弹回），
/// 只能自己补。
extension View {
    @ViewBuilder
    func pawTabBarBottomMargin() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            contentMargins(.bottom, PawLayout.tabBarHeight, for: .scrollContent)
        }
    }

    /// 关闭所属 SwiftUI `ScrollView` 的边缘拉伸，但保留正常滚动。
    /// SwiftUI iOS 17 没有 `.scrollBounceBehavior(.never)`，所以只在需要的页面内容里
    /// 放一个原生探针，找到最近的 `UIScrollView` 后局部关闭 bounce。
    func pawScrollBounceDisabled() -> some View {
        background(PawScrollBounceDisabler())
    }
}

private struct PawScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> PawScrollBounceProbe {
        PawScrollBounceProbe()
    }

    func updateUIView(_ uiView: PawScrollBounceProbe, context: Context) {
        uiView.disableBounce()
    }
}

private final class PawScrollBounceProbe: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        disableBounce()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        disableBounce()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        disableBounce()
    }

    func disableBounce() {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                scrollView.bounces = false
                scrollView.alwaysBounceVertical = false
                return
            }
            ancestor = view.superview
        }
    }
}

/// Portfolio pull-to-refresh interaction. The spinner remains UIKit's native
/// `UIRefreshControl`; only the trigger distance and held inset are standardized.
enum PawPullToRefreshMetrics {
    static let triggerDistance: CGFloat = 80
}

private extension Notification.Name {
    static let pawRefreshRequested = Notification.Name("pawfolio.refresh-requested")
}

private struct PawRefreshControlInstaller: UIViewRepresentable {
    let action: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PawRefreshControlProbe {
        let view = PawRefreshControlProbe()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PawRefreshControlProbe, context: Context) {
        context.coordinator.action = action
        uiView.installIfPossible()
    }

    static func dismantleUIView(_ uiView: PawRefreshControlProbe, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: @MainActor () async -> Void

        private weak var scrollView: UIScrollView?
        private let refreshControl = UIRefreshControl()
        private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        private var refreshTask: Task<Void, Never>?
        private var restingInsetTop: CGFloat?
        private var originalAlwaysBounceVertical = false

        init(action: @escaping @MainActor () async -> Void) {
            self.action = action
            super.init()
            refreshControl.tintColor = UIColor(Nvwa.ink)
            refreshControl.addTarget(self, action: #selector(systemDidRequestRefresh), for: .valueChanged)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(accessibilityDidRequestRefresh),
                name: .pawRefreshRequested,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func install(in candidate: UIScrollView?) {
            guard let candidate, candidate !== scrollView else { return }
            uninstall()

            scrollView = candidate
            originalAlwaysBounceVertical = candidate.alwaysBounceVertical
            candidate.alwaysBounceVertical = true
            candidate.refreshControl = refreshControl
            candidate.panGestureRecognizer.addTarget(self, action: #selector(panDidChange))
        }

        func uninstall() {
            refreshTask?.cancel()
            refreshTask = nil

            if let scrollView {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(panDidChange))
                if let restingInsetTop {
                    scrollView.contentInset.top = restingInsetTop
                }
                scrollView.alwaysBounceVertical = originalAlwaysBounceVertical
                if scrollView.refreshControl === refreshControl {
                    scrollView.refreshControl = nil
                }
            }

            refreshControl.endRefreshing()
            restingInsetTop = nil
            scrollView = nil
        }

        @objc private func panDidChange() {
            guard refreshTask == nil, let scrollView else { return }

            if scrollView.panGestureRecognizer.state == .began {
                feedbackGenerator.prepare()
                return
            }

            guard scrollView.panGestureRecognizer.state == .changed else { return }

            let pullDistance = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
            guard pullDistance >= PawPullToRefreshMetrics.triggerDistance else { return }
            beginRefresh(providesFeedback: true)
        }

        @objc private func systemDidRequestRefresh() {
            beginRefresh(providesFeedback: true)
        }

        @objc private func accessibilityDidRequestRefresh() {
            beginRefresh(providesFeedback: true)
        }

        private func beginRefresh(providesFeedback: Bool) {
            guard refreshTask == nil, let scrollView else { return }

            if providesFeedback {
                feedbackGenerator.impactOccurred()
            }

            restingInsetTop = scrollView.contentInset.top
            if !refreshControl.isRefreshing {
                refreshControl.beginRefreshing()
            }

            // At the 80pt threshold the current offset already matches this new
            // resting inset, so releasing the finger does not bounce content home.
            scrollView.contentInset.top += PawPullToRefreshMetrics.triggerDistance

            refreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await action()
                finishRefresh()
            }
        }

        private func finishRefresh() {
            guard let scrollView else {
                refreshTask = nil
                return
            }

            let targetInset = restingInsetTop ?? scrollView.contentInset.top
            refreshControl.endRefreshing()
            UIView.animate(
                withDuration: 0.2,
                animations: { scrollView.contentInset.top = targetInset },
                completion: { [weak self] _ in
                    self?.restingInsetTop = nil
                    self?.refreshTask = nil
                }
            )
        }
    }
}

private final class PawRefreshControlProbe: UIView {
    weak var coordinator: PawRefreshControlInstaller.Coordinator?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installIfPossible()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfPossible()
    }

    func installIfPossible() {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                coordinator?.install(in: scrollView)
                return
            }
            ancestor = view.superview
        }
    }
}

/// Web 的媒体查询按**视口**宽度生效，不是容器宽度，所以断点判断统一读这个值。
/// 由 `RootTabView` 在根部注入。
private struct PawViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 393
}

private struct PawViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 852
}

private struct PawViewportBottomSafeAreaKey: EnvironmentKey {
    static let defaultValue: CGFloat = 34
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

    var pawViewportBottomSafeArea: CGFloat {
        get { self[PawViewportBottomSafeAreaKey.self] }
        set { self[PawViewportBottomSafeAreaKey.self] = newValue }
    }

}

/// 全 App 唯一的分割线。厚度固定 0.5pt——用户定的统一口径，不随 `displayScale` 变。
///
/// 不要再手写 `Rectangle().fill(Nvwa.ink10).frame(height: …)`：先前四个调用点写出了
/// 两种厚度，标签栏是 0.5、其余是 1，深色下这点差别看得很清楚。
struct PawDivider: View {
    /// 两端留白。列表行之间通常留出与行内容相同的横向内边距。
    var insets: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Nvwa.ink10)
            .frame(height: PawDivider.thickness)
            .padding(.horizontal, insets)
    }

    static let thickness: CGFloat = 0.5
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

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

/// Shared adaptive sizing for every bottom dialog.
///
/// `PresentationDetent.height` excludes the bottom safe area, so the maximum
/// content height subtracts it explicitly. The resulting sheet keeps at least
/// 80 points clear above its top edge in the current window, including iPad
/// multitasking and rotation, instead of reading the physical screen bounds.
enum PawSheetSizing {
    static let topClearance: CGFloat = 80
    static let measurementTolerance: CGFloat = 1
    static let initialHeight: CGFloat = 98
    /// Gives the middle ScrollView a real first layout pass even when a sheet
    /// has both the 66-point header and a fixed footer. This is only the
    /// bootstrap detent; the first preference update resolves to the content's
    /// actual natural height (and may shrink below it).
    static let bootstrapHeight: CGFloat = 320

    static func resolvedHeight(
        idealHeight: CGFloat,
        viewportHeight: CGFloat,
        bottomSafeArea: CGFloat
    ) -> CGFloat {
        let maximum = max(
            initialHeight,
            viewportHeight - topClearance - bottomSafeArea
        )
        return min(max(idealHeight, initialHeight), maximum)
    }
}

/// Each fixed section and the intrinsic content inside the middle ScrollView
/// reports its own height. Summing those independent parts avoids the circular
/// measurement that occurs when the already-constrained sheet root is measured.
struct PawSheetHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private struct PawSheetMeasuredPartModifier: ViewModifier {
    let additionalHeight: CGFloat
    @State private var measuredHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // A preference emitted from a GeometryReader living in a
            // ScrollView background is pruned when that scroll view initially
            // has no viewport. Persist the geometry value on the measured
            // view itself, then emit the preference from that view's branch.
            // `onGeometryChange` is back-deployed to iOS 16, so this remains
            // valid for PawFolio's iOS 17 deployment target.
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height + additionalHeight
            } action: { newHeight in
                guard newHeight > 0,
                      abs(newHeight - measuredHeight) > PawSheetSizing.measurementTolerance else {
                    return
                }
                measuredHeight = newHeight
            }
            .preference(key: PawSheetHeightPreferenceKey.self, value: measuredHeight)
    }
}

private struct PawSheetHeightContribution: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .preference(key: PawSheetHeightPreferenceKey.self, value: height)
    }
}

private struct PawSheetPresentationModifier: ViewModifier {
    @Environment(\.pawViewportHeight) private var viewportHeight
    @Environment(\.pawViewportBottomSafeArea) private var bottomSafeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var idealHeight = PawSheetSizing.bootstrapHeight

    private var resolvedHeight: CGFloat {
        PawSheetSizing.resolvedHeight(
            idealHeight: idealHeight,
            viewportHeight: viewportHeight,
            bottomSafeArea: bottomSafeArea
        )
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(PawSheetHeightPreferenceKey.self) { measuredHeight in
                guard measuredHeight > 0,
                      abs(measuredHeight - idealHeight) > PawSheetSizing.measurementTolerance else {
                    return
                }
                withAnimation(reduceMotion ? nil : .snappy) {
                    idealHeight = measuredHeight
                }
            }
            .presentationDetents([.height(resolvedHeight)])
            .presentationContentInteraction(.scrolls)
    }
}

extension View {
    /// Marks a fixed section or an unconstrained ScrollView child as part of the
    /// sheet's natural height. Padding must be applied before this modifier when
    /// that padding should contribute to the measured height.
    func pawSheetMeasuredPart(additionalHeight: CGFloat = 0) -> some View {
        modifier(PawSheetMeasuredPartModifier(additionalHeight: additionalHeight))
    }

    /// Adds spacing owned by a container rather than any one measurable child.
    func pawSheetHeightContribution(_ height: CGFloat) -> some View {
        background(PawSheetHeightContribution(height: height))
    }

    /// Applies the one shared content-driven detent. The sheet grows with its
    /// measured sections, caps at an 80-point top clearance and then leaves
    /// overflow to its middle ScrollView.
    func pawSheetPresentation() -> some View {
        modifier(PawSheetPresentationModifier())
    }
}

/// Figma `154:12605` 的成功反馈：当前操作 Sheet 原地切换成这张短 Sheet，
/// 由用户沿用顶部抓手下拉关闭。勾选图形直接复用 Nvwa `2029:9063` 的 Tick，
/// 不在业务层重画或替换成系统图标。
struct PawSuccessSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Nvwa.backgroundVessel)
                .frame(width: 40, height: 4)
                .padding(.vertical, 6)
                .pawSheetMeasuredPart()

            VStack(spacing: 16) {
                NvwaKeyFeatureIcon(.tick)
                    .accessibilityHidden(true)

                // 产品稿的源文案就是这个拼法；先严格跟稿，不在业务页各写一份。
                Text("Succesful")
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium)
                    .foregroundStyle(Nvwa.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .pawSheetMeasuredPart()
        }
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Successful")
    }
}

/// Web `.sheet-panel`：顶部抓手、居中标题、右上关闭，左上角放破坏性操作，底部可选操作区。
///
/// Height follows Header + intrinsic Content + Footer until the shared maximum;
/// overflow then stays inside this scroll view.
struct PawSheet<Content: View, Footer: View>: View {
    private let title: LocalizedStringKey
    private let content: Content
    private let footer: Footer
    private let showsCloseButton: Bool
    /// Web `.sheet-delete-btn`：左上角、`--loss` 色的破坏性操作。
    private let destructiveIcon: String?
    private let destructiveLabel: String?
    private let onDestructive: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    init(
        title: String,
        showsCloseButton: Bool = true,
        destructiveIcon: String? = nil,
        destructiveLabel: String? = nil,
        onDestructive: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = LocalizedStringKey(title)
        self.showsCloseButton = showsCloseButton
        self.destructiveIcon = destructiveIcon
        self.destructiveLabel = destructiveLabel
        self.onDestructive = onDestructive
        self.content = content()
        self.footer = footer()
    }

    init(
        localizedTitle title: LocalizedStringKey,
        showsCloseButton: Bool = true,
        destructiveIcon: String? = nil,
        destructiveLabel: String? = nil,
        onDestructive: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.showsCloseButton = showsCloseButton
        self.destructiveIcon = destructiveIcon
        self.destructiveLabel = destructiveLabel
        self.onDestructive = onDestructive
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Nvwa.ink10)
                .frame(width: 40, height: 4)
                .padding(.top, 6)
                .padding(.bottom, 6)

            ZStack {
                Text(title)
                    .nvwaTextStyle(Nvwa.Typography.titleBody, linesFillLineHeight: false)
                    .foregroundStyle(Nvwa.ink)

                HStack {
                    if let destructiveIcon, let onDestructive {
                        Button(action: onDestructive) {
                            Image(destructiveIcon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundStyle(Nvwa.destructive)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PawPressableButtonStyle())
                        .accessibilityLabel(destructiveLabel ?? "Delete")
                    }

                    Spacer()

                    if showsCloseButton {
                        Button {
                            dismiss()
                        } label: {
                            Image("IconClose")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundStyle(Nvwa.ink)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PawPressableButtonStyle())
                        .accessibilityLabel(Text("Close") + Text(" ") + Text(title))
                    } else if destructiveIcon != nil {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 15)
            .pawSheetMeasuredPart(additionalHeight: 16)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    // The initial detent can be completely consumed by the
                    // header and footer. Without an intrinsic vertical size,
                    // ScrollView then proposes zero height to a long form and
                    // its preference never reports the hidden content. The
                    // sheet remains permanently collapsed at header + footer.
                    // Keep the measured copy width-constrained for wrapping,
                    // but let it claim its full natural height vertically.
                    .fixedSize(horizontal: false, vertical: true)
                    .pawSheetMeasuredPart()
            }
            .scrollBounceBehavior(.basedOnSize)

            footerArea
                .pawSheetMeasuredPart()
        }
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
        // 弹层盖在主界面之上，主界面那个 toast 出口被挡住了，这里要自己挂一个。
        .pawToast()
    }

    @ViewBuilder
    private var footerArea: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 0) {
                footer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }
}

extension PawSheet where Footer == EmptyView {
    init(
        title: String,
        showsCloseButton: Bool = true,
        destructiveIcon: String? = nil,
        destructiveLabel: String? = nil,
        onDestructive: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            showsCloseButton: showsCloseButton,
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
                    .foregroundStyle(Nvwa.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Nvwa.ink10)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: "\(assetType.rawValue)|\(quoteSymbol)") {
            image = store.cachedImage(for: quoteSymbol, assetType: assetType)
            guard image == nil,
                  !store.isUnavailable(quoteSymbol, assetType: assetType) else { return }
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
