import SwiftUI

// Web 的固定框架：顶部 `.topbar` 与贴底 `.tabbar`。三个标签页与 Web 一致，
// 账号入口在头部头像上，不是第四个标签页——见 `AGENTS.md` 的 Design direction。

/// Web 的三个标签页。
enum PawTab: String, CaseIterable, Hashable {
    case portfolio
    case calculator
    case exchangeRate

    var title: String {
        switch self {
        case .portfolio: "投资组合"
        case .calculator: "计算"
        case .exchangeRate: "汇率"
        }
    }

    /// Web 用的 Remix Icon，同名 SVG 已打包进 Asset Catalog。
    var iconName: String {
        switch self {
        case .portfolio: "IconCoin"                 // ri-coin-line
        case .calculator: "IconIncreaseDecrease"    // ri-increase-decrease-line
        case .exchangeRate: "IconMoneyDollarCircle" // ri-money-dollar-circle-line
        }
    }
}

/// Web 的主题切换：手动选择存本地，未选择时跟随系统。
@MainActor
final class PawThemeController: ObservableObject {
    private enum Storage {
        static let key = "pawfolio.theme"
    }

    @Published var preference: ColorScheme? {
        didSet { persist() }
    }

    init() {
        // 直接初始化底层存储：`preference` 是 Optional，声明时就隐式是 nil，
        // 在 init 里再赋值会触发 didSet，把「跟随系统」当成一次显式选择写进本地，
        // 结果是首次启动后就被锁在当时的外观上。
        let stored = UserDefaults.standard.string(forKey: Storage.key)
        _preference = Published(
            initialValue: stored == "light" ? .light : stored == "dark" ? .dark : nil
        )
    }

    func toggle(systemScheme: ColorScheme) {
        let current = preference ?? systemScheme
        preference = current == .dark ? .light : .dark
    }

    private func persist() {
        switch preference {
        case .light: UserDefaults.standard.set("light", forKey: Storage.key)
        case .dark: UserDefaults.standard.set("dark", forKey: Storage.key)
        case .none: UserDefaults.standard.removeObject(forKey: Storage.key)
        @unknown default: break
        }
    }
}

/// Web 头部的行情条。点一下换下一个标的，对应 `GLOBAL_TICKER_SYMBOLS`。
@MainActor
final class MarketTickerViewModel: ObservableObject {
    /// 与 Web 的 `GLOBAL_TICKER_SYMBOLS` 一致。
    static let symbols = ["BTC", "MSTR", "QQQ"]

    @Published private(set) var index: Int = {
        #if DEBUG
        // 视觉 QA：轮换要点击才动，用 `SIMCTL_CHILD_PAWFOLIO_TICKER_INDEX` 直接定位标的。
        if let raw = ProcessInfo.processInfo.environment["PAWFOLIO_TICKER_INDEX"],
           let value = Int(raw) {
            return value % MarketTickerViewModel.symbols.count
        }
        #endif
        return 0
    }()
    @Published private(set) var quotes: [String: MarketQuote] = [:]

    private let repository: any MarketQuoteRepositoryServing

    init(repository: any MarketQuoteRepositoryServing = CachedMarketQuoteRepository()) {
        self.repository = repository
    }

    var symbol: String {
        Self.symbols[index % Self.symbols.count]
    }

    var asset: AssetSearchResult? {
        AssetSearchResult.offlineFallbacks.first { $0.symbol == symbol }
    }

    var quote: MarketQuote? {
        guard let asset else { return nil }
        return quotes[asset.quoteSymbol]
    }

    /// Web 行情条上的短名，和搜索结果里的长名（如 `Bitcoin USD`）不是一回事。
    var displayName: String {
        switch symbol {
        case "BTC": "Bitcoin"
        case "MSTR": "Strategy"
        case "QQQ": "Invesco QQQ"
        default: asset?.name ?? symbol
        }
    }

    var priceText: String {
        guard let quote else { return "$—" }
        return "$" + quote.price.formatted(
            .number.grouping(.automatic).precision(.fractionLength(2))
        )
    }

    var changeText: String {
        guard let quote else { return "获取中" }
        return abs(quote.changePercent).formatted(.number.precision(.fractionLength(2))) + "%"
    }

    /// Web 用 `ri-arrow-up-line` / `ri-arrow-down-line` / `ri-subtract-line`，
    /// 不是文字箭头——方向靠图形表达，颜色只是辅助。
    var changeIconName: String? {
        guard let quote else { return nil }
        if quote.changePercent > 0 { return "IconArrowUp" }
        if quote.changePercent < 0 { return "IconArrowDown" }
        return "IconSubtract"
    }

    var changeColor: Color {
        guard let quote else { return PawTheme.ink40 }
        if quote.changePercent > 0 { return PawTheme.gain }
        if quote.changePercent < 0 { return PawTheme.loss }
        return PawTheme.ink40
    }

    /// Web 只给股票类标的显示时段徽章——加密货币没有时段可言。
    var session: MarketSession? {
        guard let asset, asset.assetType != .cryptocurrency else { return nil }
        return MarketSessionCalendar.session()
    }

    func advance() {
        index = (index + 1) % Self.symbols.count
    }

    func load() async {
        let quoteSymbols = Set(
            AssetSearchResult.offlineFallbacks
                .filter { Self.symbols.contains($0.symbol) }
                .map(\.quoteSymbol)
        )

        quotes = await repository.cachedQuotes(for: quoteSymbols)
        let refresh = await repository.refreshQuotes(for: quoteSymbols)
        if !refresh.quotes.isEmpty {
            quotes = refresh.quotes
        }
    }
}

/// Web `.topbar`。
struct PawHeader: View {
    let avatar: CatAvatar?
    /// Web `.header-name`：登录后才显示。
    let displayName: String?
    let onOpenAccount: () -> Void
    /// Web 的彩蛋：双击顶栏头像打开「我们家的猫」。
    let onOpenCats: () -> Void
    let onToggleTheme: () -> Void

    @ObservedObject var ticker: MarketTickerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pawViewportWidth) private var viewportWidth

    /// `@media (max-width: 485px) { .btc-name { display: none } }`
    private var showsName: Bool { viewportWidth >= 485 }
    /// `@media (max-width: 415px) { .btc-ticker small { display: none } }`
    private var showsChange: Bool { viewportWidth >= 415 }
    /// `@media (max-width: 347px) { .btc-ticker { display: none } }`
    private var showsTicker: Bool { viewportWidth >= 347 }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                    if let avatar {
                        Image(avatar.assetName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Image("IconUserSmile")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(PawTheme.ink40)
                    }
                }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: avatar == nil ? 0 : 2))
            .contentShape(Circle())
            // 双击必须先声明，否则单击会先把手势吃掉。
            .onTapGesture(count: 2, perform: onOpenCats)
            .onTapGesture(perform: onOpenAccount)
            .accessibilityLabel("账号与个人资料")
            .accessibilityHint("双击可以看我们家的猫")
            .accessibilityAddTraits(.isButton)

            if let displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(PawFont.inter(16, weight: .medium))
                    .foregroundStyle(PawTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2, perform: onOpenCats)
                    .onTapGesture(perform: onOpenAccount)
            }

            Spacer(minLength: 0)

            if showsTicker {
                tickerButton
            }

            Button(action: onToggleTheme) {
                Image(colorScheme == .dark ? "IconSun" : "IconMoon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(PawTheme.ink)
                    // Web `.icon-btn` 的布局尺寸是 24×24；那边的 44 触控区是
                    // `::after` 伪元素撑的，不参与布局。这里如果直接写 44×44，
                    // 整条 header 会被撑高 16pt，看着就像底部留白没改。
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PawPressableButtonStyle())
            .accessibilityLabel(colorScheme == .dark ? "切换到浅色模式" : "切换到深色模式")
        }
        // Web `.topbar` 在 767 以下是四边 16、列间距 12。
        .padding(.horizontal, PawLayout.pageHorizontal)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(PawTheme.bg1)
    }

    /// Web `.btc-ticker`：点一下换下一个标的。窄屏下名字和涨跌会被媒体查询隐藏，
    /// 只留 logo、价格和交易时段。
    private var tickerButton: some View {
        Button {
            // Web 切换标的时旧的向上移出、新的从下移入（`is-leaving` / `is-entering`）。
            withAnimation(PawMotion.appear) {
                ticker.advance()
            }
        } label: {
            HStack(spacing: 8) {
                if let asset = ticker.asset {
                    PawAssetLogo(
                        quoteSymbol: asset.quoteSymbol,
                        assetType: asset.assetType,
                        name: asset.name,
                        fallbackText: String(asset.symbol.prefix(1)),
                        diameter: 18,
                        fallbackFontSize: 9
                    )
                }

                if showsName {
                    Text(ticker.displayName)
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 88, alignment: .leading)
                }

                HStack(spacing: 4) {
                    Text(ticker.priceText)
                        .font(PawFont.inter(12).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)

                    if showsChange {
                        HStack(spacing: 2) {
                            if let icon = ticker.changeIconName {
                                Image(icon)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 13, height: 13)
                            }

                            Text(ticker.changeText)
                                .font(PawFont.inter(12).monospacedDigit())
                        }
                        .foregroundStyle(ticker.changeColor)
                    }

                    if let session = ticker.session {
                        // Web `.market-session`：一个 5pt 圆点加短标签。
                        HStack(spacing: 5) {
                            Circle()
                                .fill(session.tone)
                                .frame(width: 5, height: 5)

                            Text(session.label)
                                .font(PawFont.inter(12))
                                .foregroundStyle(session.tone)
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                PawTheme.ink4,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .id(ticker.symbol)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
        }
        .buttonStyle(PawPressableButtonStyle())
        .clipped()
        .accessibilityLabel(
            "\(ticker.displayName) \(ticker.priceText)，\(ticker.changeText)"
                + (ticker.session.map { "，美股\($0.fullLabel)" } ?? "")
                + "，点击查看下一个标的"
        )
    }
}

/// Web `.tabbar`：贴底毛玻璃条，顶部一条发丝线。
struct PawTabBar: View {
    @Binding var selection: PawTab

    /// 切换标签时给一次轻震动。毛玻璃在整条导航的背景上，不做选中项高亮。
    @State private var haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PawTab.allCases, id: \.self) { tab in
                let isSelected = selection == tab

                Button {
                    guard selection != tab else { return }
                    haptics.impactOccurred()
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(tab.iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)

                        Text(tab.title)
                            .font(PawFont.inter(12, weight: isSelected ? .medium : .regular))
                    }
                    .foregroundStyle(isSelected ? PawTheme.ink : PawTheme.ink40)
                    .frame(maxWidth: 168)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .onAppear { haptics.prepare() }
        // 条压在安全区之上（Home Indicator），玻璃铺满到屏幕物理边缘，
        // 图标和文字由 safeAreaInset 顶回安全区内——Web 的做法也是这样。
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            PawDivider()
        }
    }
}


extension MarketSession {
    /// `styles.css` 的 `--session-*`：绿=正在交易，琥珀=盘前，蓝=盘后，靛=夜盘，灰=休市。
    var tone: Color {
        switch self {
        case .open: PawTheme.sessionOpen
        case .pre: PawTheme.sessionPre
        case .after: PawTheme.sessionAfter
        case .night: PawTheme.sessionNight
        case .closed: PawTheme.sessionClosed
        }
    }
}
