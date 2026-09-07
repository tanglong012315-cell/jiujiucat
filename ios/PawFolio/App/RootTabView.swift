import Nvwa
import SwiftUI

struct RootTabView: View {
    #if DEBUG
    /// 视觉 QA 与 UI 测试用：以 `SIMCTL_CHILD_PAWFOLIO_INITIAL_TAB` 指定初始标签页。
    /// `account` 不再是标签页，它会直接把账号面板弹出来。
    private static var launchOverride: (tab: PawTab?, showsAccount: Bool) {
        switch ProcessInfo.processInfo.environment["PAWFOLIO_INITIAL_TAB"] {
        case "portfolio": (.portfolio, false)
        case "calculator": (.calculator, false)
        case "exchangeRate": (.exchangeRate, false)
        case "account": (nil, true)
        default: (nil, false)
        }
    }
    #endif

    /// 冷启动落在 PawFolio（用户 2026-09-03 的要求）。Web 那边默认仍是计算页，
    /// 这处两端刻意不一致。
    @State private var selection: PawTab = .portfolio
    @State private var isAccountPresented = false
    @State private var isLoginPresented = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_QA_LOGIN_SHEET"] == "1"
        #else
        return false
        #endif
    }()
    /// Calculate 页顶栏的「+」：切到 PawFolio 页并让那边弹出新增持仓编辑器。
    @StateObject private var themeController = NvwaThemeController()
    @StateObject private var languageStore = LanguagePreferenceStore()
    @StateObject private var accountModel: AccountViewModel
    private let scopedRepository: ScopedLocalHoldingRepository
    private let scopedLedgerRepository: ScopedLocalLedgerRepository
    private let marketQuoteRepository: CachedMarketQuoteRepository
    private let exchangeRateClient: LiveExchangeRateClient
    private let preferencesStore: UserDefaultsPreferencesStore

    init() {
        let scopedRepository = ScopedLocalHoldingRepository()
        let scopedLedgerRepository = ScopedLocalLedgerRepository()
        let marketQuoteRepository = CachedMarketQuoteRepository()
        let exchangeRateClient = LiveExchangeRateClient()
        let preferencesStore = UserDefaultsPreferencesStore()
        let sessionStore = KeychainSupabaseSessionStore()
        let authentication = SupabaseAuthenticationService(
            sessionStore: sessionStore,
            oauthAuthorizer: SystemOAuthAuthorizer()
        )
        let cloudRepository = SupabaseCloudHoldingRepository(
            tokenProvider: authentication
        )
        let syncCoordinator = HoldingSyncCoordinator(
            authentication: authentication,
            localRepository: scopedRepository,
            cloudRepository: cloudRepository
        )
        let profileStore = UserDefaultsAccountProfileStore()
        let cloudProfileRepository = SupabaseCloudProfileRepository(
            tokenProvider: authentication
        )
        let profileSyncCoordinator = ProfileSyncCoordinator(
            authentication: authentication,
            localRepository: profileStore,
            cloudRepository: cloudProfileRepository
        )

        self.scopedRepository = scopedRepository
        self.scopedLedgerRepository = scopedLedgerRepository
        self.marketQuoteRepository = marketQuoteRepository
        self.exchangeRateClient = exchangeRateClient
        self.preferencesStore = preferencesStore
        _accountModel = StateObject(
            wrappedValue: AccountViewModel(
                authentication: authentication,
                localRepository: scopedRepository,
                syncCoordinator: syncCoordinator,
                decisionStore: UserDefaultsGuestImportDecisionStore(),
                profileStore: profileStore,
                profileSyncCoordinator: profileSyncCoordinator,
                ledgerGuestImporter: LedgerGuestImportService(repository: scopedLedgerRepository)
            )
        )

        #if DEBUG
        let override = Self.launchOverride
        if let tab = override.tab {
            _selection = State(initialValue: tab)
        }
        if override.showsAccount {
            _isAccountPresented = State(initialValue: true)
        }
        #endif
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["PAWFOLIO_SHOW_NVWA_CATALOG"] == "1" {
                NvwaComponentCatalog(
                    icons: NvwaComponentCatalogIcons(
                        check: Image("IconCheck"),
                        search: Image("IconSearch2"),
                        close: Image("IconClose"),
                        checkboxChecked: Image("IconCheckboxFill"),
                        checkboxUnchecked: Image("IconCheckboxBlank"),
                        calendar: Image("IconCalendar"),
                        previous: Image("IconArrowLeftS"),
                        next: Image("IconArrowRightS"),
                        hintRight: Image("IconArrowDropRight"),
                        navigationGuest: Image("IconShining"),
                        navigationAdd: Image("IconAdd"),
                        navigationBack: Image("IconArrowLeft"),
                        navigationTheme: Image("IconMoonFill"),
                        logout: Image("IconLogout"),
                        flagUS: Image("FlagUS"),
                        dropdown: Image("IconArrowDropDownFill"),
                        dropdownChevron: Image("IconArrowDownSFill"),
                        closeCircle: Image("IconCloseCircleFill")
                    ),
                    initialSection: ProcessInfo.processInfo.environment[
                        "PAWFOLIO_NVWA_CATALOG_SECTION"
                    ]
                )
                .preferredColorScheme(themeController.preference)
            } else {
                rootContent
            }
            #else
            rootContent
            #endif
        }
        .environment(\.locale, languageStore.selected.locale)
        // Active 态的一键清除（`2276:630`）在稿子上不是可选项，每个输入框有字
        // 就该有它。图标由宿主注入一次，组件自己取——Nvwa 不自带图标集。
        .nvwaInputClearIcon(Image("IconCloseCircleFill"))
    }

    private var rootContent: some View {
        // Web 的媒体查询按视口宽度生效，这里量一次供各组件判断断点。
        GeometryReader { geometry in
            content(
                viewportWidth: geometry.size.width,
                // This root GeometryReader reports the safe-area content height.
                // Reconstruct the current window height so an adaptive sheet's
                // 80pt clearance is measured from the window edge. The sizing
                // policy subtracts the bottom inset again because `.height`
                // detents add that safe area outside their requested height.
                viewportHeight: geometry.size.height
                    + geometry.safeAreaInsets.top
                    + geometry.safeAreaInsets.bottom,
                safeAreaInsets: geometry.safeAreaInsets
            )
        }
        .ignoresSafeArea(.keyboard)
    }

    private func content(
        viewportWidth: CGFloat,
        viewportHeight: CGFloat,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        Group {
            if showsInitialSessionLoading {
                sessionRestorationShell(
                    verticalIndicatorOffset: (
                        safeAreaInsets.bottom - safeAreaInsets.top
                    ) / 2
                )
            } else {
                appShell
            }
        }
        .background(Nvwa.bg1)
        .pawToast()
        .environment(\.pawViewportWidth, viewportWidth)
        .environment(\.pawViewportHeight, viewportHeight)
        .environment(\.pawViewportBottomSafeArea, safeAreaInsets.bottom)
        .preferredColorScheme(themeController.preference)
        .fullScreenCover(isPresented: $isAccountPresented) {
            AccountView(model: accountModel, themeController: themeController, languageStore: languageStore)
                .preferredColorScheme(themeController.preference)
        }
        .fullScreenCover(isPresented: $isLoginPresented) {
            LoginView(model: accountModel, themeController: themeController, languageStore: languageStore)
                .preferredColorScheme(themeController.preference)
        }
        .task {
            AssetLogoStore.shared.loadIndexIfNeeded()
            await accountModel.loadIfNeeded()
        }
    }

    /// Figma `173:22196`：冷启动先确认 Keychain / Supabase 会话，再放出可交互页面。
    ///
    /// `AccountViewModel` 的初始值本来就是 `.restoringSession`，因此这里没有另造一套
    /// 启动布尔值，也不会出现 View 和认证服务各自认为「加载完成」的竞态。会话恢复
    /// 成功、确认未登录，或恢复失败进入可重试态后，根页面才开始接收点击。
    private var showsInitialSessionLoading: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_SESSION_RESTORING"] == "1" {
            return true
        }
        #endif
        return accountModel.state == .restoringSession
    }

    @ViewBuilder
    private var appShell: some View {
        if #available(iOS 26.0, *) {
            nativeShell
        } else {
            legacyShell
        }
    }

    /// 启动等待态保留产品稿里的顶部访客入口与底部三标签骨架，但所有入口都不可操作。
    /// 中央控件直接使用 Nvwa outline button 的原生 loading state：48pt 高、24pt 横向
    /// padding、16pt ProgressView，最终自然得到稿子里的 64×48pt 胶囊。
    private func sessionRestorationShell(verticalIndicatorOffset: CGFloat) -> some View {
        ZStack {
            Group {
                if #available(iOS 26.0, *) {
                    nativeSessionRestorationShell
                } else {
                    legacySessionRestorationShell
                }
            }
            .allowsHitTesting(false)

            PawAppLoadingIndicator("Checking login status")
            // RootTabView 的内容区域扣除了不对称的上下安全区；补回差值后，控件
            // 才落在整块物理屏幕中心（Figma：y 382...430，中心 406）。
            .offset(y: verticalIndicatorOffset)
        }
        .background(Nvwa.backgroundMain)
    }

    @available(iOS 26.0, *)
    private var nativeSessionRestorationShell: some View {
        TabView(selection: .constant(PawTab.portfolio)) {
            Tab(
                PawTab.portfolio.title,
                image: PawTab.portfolio.iconName,
                value: PawTab.portfolio
            ) {
                sessionRestorationPage
            }

            Tab(
                PawTab.calculator.title,
                image: PawTab.calculator.iconName,
                value: PawTab.calculator
            ) {
                sessionRestorationPage
            }

            Tab(
                PawTab.exchangeRate.title,
                image: PawTab.exchangeRate.iconName,
                value: PawTab.exchangeRate
            ) {
                sessionRestorationPage
            }
        }
        .tint(Nvwa.ink)
    }

    private var legacySessionRestorationShell: some View {
        ZStack {
            sessionRestorationPage

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                PawTabBar(selection: .constant(.portfolio))
            }
        }
    }

    private var sessionRestorationPage: some View {
        ZStack(alignment: .top) {
            Nvwa.backgroundMain

            PawTopNavigation(
                isSignedIn: false,
                profileInitials: "PF",
                profileAvatar: .faceHappy,
                trailingIcon: nil,
                onOpenAccount: {},
                onSignIn: {}
            )
        }
    }

    // MARK: - iOS 26

    /// 底部导航交给系统的 `TabView`。
    ///
    /// 跟手拖动的玻璃胶囊、边缘色散、松手回弹全由 Apple 的玻璃 shader 渲染——这是
    /// 手搓版补不上的差距（色散是逐通道采样背景，第三方 API 拿不到）。这条**推翻了**
    /// `AGENTS.md` 里「不用 iOS 系统控件」的规则，仅限这一个控件，见那份文档的
    /// Design direction（2026-08-31）。
    ///
    /// 顶栏不套在 `TabView` 外面，而是各页自己挂一条 `PawTopNavigation`：左边的
    /// 账号入口三页一致，右边的主操作各页不同（PawFolio/Calculate 是新增持仓，
    /// Currency 是添加货币）。V1.2.0 之前只有 PawFolio 页有顶栏。
    ///
    /// 标题一律用 `PawTab.title` 的本地化键：曾经在两侧各垫 4 个全角空格想把玻璃胶囊
    /// 撑宽，结果 3 个标签加起来远超屏宽，系统只能压缩字距并截断，文字被挤扁、
    /// 也不再和图标对齐。胶囊宽度没有公开 API，宁可窄一点也别动标题。
    @available(iOS 26.0, *)
    private var nativeShell: some View {
        TabView(selection: $selection) {
            Tab(
                PawTab.portfolio.title,
                image: PawTab.portfolio.iconName,
                value: PawTab.portfolio
            ) {
                portfolioPage
            }

            Tab(
                PawTab.calculator.title,
                image: PawTab.calculator.iconName,
                value: PawTab.calculator
            ) {
                calculatorPage
            }

            Tab(
                PawTab.exchangeRate.title,
                image: PawTab.exchangeRate.iconName,
                value: PawTab.exchangeRate
            ) {
                exchangeRatePage
            }
        }
        // 系统默认把选中项染成 iOS 蓝。Figma 的选中态使用 Text Primary。
        .tint(Nvwa.ink)
    }

    // MARK: - iOS 17–25

    /// 自绘导航条的老结构。
    ///
    /// 这里**不用** `safeAreaInset`：那份 inset 传不进各页自己的 ScrollView，
    /// 表现就是底部内容默认被导航挡住、能拖出来但一松手又弹回去。改成 overlay
    /// 之后，由各页用 `pawTabBarBottomMargin()` 自己留出下边距。
    private var legacyShell: some View {
        // 三个页面始终保留在层级里，切换时不丢失输入与滚动位置。
        ZStack {
            panel(.portfolio) { portfolioPage }
            panel(.calculator) { calculatorPage }
            panel(.exchangeRate) { exchangeRatePage }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            PawTabBar(selection: $selection)
        }
    }

    // MARK: - 两条路共用

    private var portfolioPage: some View {
        LedgerPortfolioView(
            model: makeLedgerPortfolioModel(),
            isSignedIn: portfolioIsSignedIn,
            profileInitials: portfolioProfileInitials,
            profileAvatar: portfolioProfileAvatar,
            onOpenAccount: { isAccountPresented = true },
            onSignIn: { isLoginPresented = true }
        )
        .id(accountModel.activeScope)
    }

    private func makeLedgerPortfolioModel() -> LedgerPortfolioViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_FIXTURE"] == "v2.1.1" {
            return LedgerPortfolioViewModel(
                ledgerRepository: LedgerV211QAFixtureRepository(),
                holdingRepository: FixedScopeHoldingRepository(
                    repository: scopedRepository,
                    scope: accountModel.activeScope
                ),
                scope: accountModel.activeScope,
                portfolioPreferences: preferencesStore
            )
        }
        #endif

        return LedgerPortfolioViewModel(
            ledgerRepository: scopedLedgerRepository,
            holdingRepository: FixedScopeHoldingRepository(
                repository: scopedRepository,
                scope: accountModel.activeScope
            ),
            scope: accountModel.activeScope,
            quoteRepository: marketQuoteRepository,
            exchangeRateClient: exchangeRateClient,
            preferences: preferencesStore,
            portfolioPreferences: preferencesStore
        )
    }

    /// 三页共用同一套顶栏（用户 2026-09-03 的要求），账号入口的取值也共用，
    /// 免得 QA 环境变量在三处各判一遍。
    private var calculatorPage: some View {
        CalculatorView(
            isSignedIn: portfolioIsSignedIn,
            profileInitials: portfolioProfileInitials,
            profileAvatar: portfolioProfileAvatar,
            onOpenAccount: { isAccountPresented = true },
            onSignIn: { isLoginPresented = true },
        )
    }

    private var exchangeRatePage: some View {
        ExchangeRateView(
            isSignedIn: portfolioIsSignedIn,
            profileInitials: portfolioProfileInitials,
            profileAvatar: portfolioProfileAvatar,
            onOpenAccount: { isAccountPresented = true },
            onSignIn: { isLoginPresented = true }
        )
    }

    private var portfolioIsSignedIn: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_SIGNED_OUT"] == "1" {
            return false
        }
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_SIGNED_IN"] == "1"
            || ProcessInfo.processInfo.environment["PAWFOLIO_QA_PORTFOLIO"] != nil {
            return true
        }
        #endif
        return accountModel.isSignedIn
    }

    private var portfolioProfileInitials: String {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_SIGNED_IN"] == "1"
            || ProcessInfo.processInfo.environment["PAWFOLIO_QA_PORTFOLIO"] != nil {
            return "TL"
        }
        #endif
        return profileInitials
    }

    private var portfolioProfileAvatar: CatAvatar {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_SIGNED_IN"] == "1"
            || ProcessInfo.processInfo.environment["PAWFOLIO_QA_PORTFOLIO"] != nil {
            return CatAvatar.decodePersisted(
                ProcessInfo.processInfo.environment["PAWFOLIO_QA_AVATAR"]
            )
        }
        #endif
        return accountModel.identity?.avatar ?? .faceHappy
    }

    private var portfolioSyncFailureMessage: String? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_SYNC_FAILURE"] == "1" {
            return "Sync failed. Please try again. "
        }
        #endif

        guard accountModel.isSignedIn else { return nil }

        if case .failed = accountModel.state {
            return "Sync failed. Please try again. "
        }
        if case .failed = accountModel.profileSyncState {
            return "Sync failed. Please try again. "
        }
        return nil
    }

    private var profileInitials: String {
        guard let displayName = accountModel.identity?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !displayName.isEmpty else {
            return "PF"
        }

        let words = displayName.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    @ViewBuilder
    private func panel<Content: View>(
        _ tab: PawTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = selection == tab

        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}

#if DEBUG
/// Deterministic, in-memory data for comparing the v2.1.1 Earn list and Daily sheet with Figma.
/// It is selected only by `SIMCTL_CHILD_PAWFOLIO_QA_LEDGER_FIXTURE=v2.1.1` and never touches
/// the user's on-device ledger.
private actor LedgerV211QAFixtureRepository: ScopedLedgerRepository {
    private var snapshot = LedgerV211QAFixtureRepository.makeSnapshot()

    func load(for scope: HoldingStorageScope) async throws -> LedgerStoreSnapshot { snapshot }

    func save(_ snapshot: LedgerStoreSnapshot, for scope: HoldingStorageScope) async throws {
        self.snapshot = snapshot
    }

    private static func makeSnapshot() -> LedgerStoreSnapshot {
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let startedAt = Date(timeIntervalSince1970: 1_767_225_600)
        let maturity = startedAt.addingTimeInterval(365 * 86_400)
        let products = [
            try! EarnProduct(
                id: "qa-structured-1",
                name: "Structured Products",
                asset: usdt,
                annualRatePercent: 17.38,
                interestMode: .simple,
                term: .structured,
                payoutFrequency: .daily,
                startsAt: startedAt,
                maturesAt: maturity,
                strikePrice: 83_000,
                knockOutPrice: 96_000
            ),
            try! EarnProduct(
                id: "qa-structured-2",
                name: "Structured Products",
                asset: usdt,
                annualRatePercent: 17.38,
                interestMode: .simple,
                term: .structured,
                payoutFrequency: .daily,
                startsAt: startedAt,
                maturesAt: maturity,
                strikePrice: 83_000,
                knockOutPrice: 96_000
            ),
            try! EarnProduct(
                id: "qa-flexible-1",
                name: "USD Flexible Term",
                asset: usdt,
                annualRatePercent: 17.38,
                interestMode: .simple,
                term: .flexible,
                payoutFrequency: .daily,
                startsAt: startedAt
            ),
            try! EarnProduct(
                id: "qa-flexible-2",
                name: "USD Flexible Term",
                asset: usdt,
                annualRatePercent: 17.38,
                interestMode: .compound,
                term: .flexible,
                payoutFrequency: .daily,
                startsAt: startedAt
            ),
        ]
        var entries = [try! LedgerEntry.deposit(
            asset: usdt,
            quantity: 500_000,
            occurredAt: startedAt,
            id: "qa-v211-deposit"
        )]
        entries += products.enumerated().map { index, product in
            try! LedgerEntry.earnSubscribe(
                product: product,
                quantity: 100_000,
                occurredAt: startedAt.addingTimeInterval(TimeInterval(index + 1)),
                id: "qa-v211-subscribe-\(index)"
            )
        }
        return LedgerStoreSnapshot(entries: entries, earnProducts: products)
    }
}
#endif
