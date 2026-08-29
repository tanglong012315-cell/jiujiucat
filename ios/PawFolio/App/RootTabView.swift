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

    @State private var selection: PawTab = .calculator
    @State private var isAccountPresented = false
    @State private var isCatGalleryPresented = false
    @StateObject private var themeController = PawThemeController()
    @StateObject private var ticker = MarketTickerViewModel()
    @StateObject private var accountModel: AccountViewModel
    private let scopedRepository: ScopedLocalHoldingRepository

    @Environment(\.colorScheme) private var colorScheme

    init() {
        let scopedRepository = ScopedLocalHoldingRepository()
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
        _accountModel = StateObject(
            wrappedValue: AccountViewModel(
                authentication: authentication,
                localRepository: scopedRepository,
                syncCoordinator: syncCoordinator,
                decisionStore: UserDefaultsGuestImportDecisionStore(),
                profileStore: profileStore,
                profileSyncCoordinator: profileSyncCoordinator
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
        if ProcessInfo.processInfo.environment["PAWFOLIO_SHOW_CATS"] == "1" {
            _isCatGalleryPresented = State(initialValue: true)
        }
        #endif
    }

    var body: some View {
        // Web 的媒体查询按视口宽度生效，这里量一次供各组件判断断点。
        GeometryReader { geometry in
            content(viewportWidth: geometry.size.width)
                .environment(\.pawViewportHeight, geometry.size.height)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func content(viewportWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            PawHeader(
                avatar: accountModel.identity?.avatar,
                displayName: accountModel.identity?.displayName,
                onOpenAccount: { isAccountPresented = true },
                onOpenCats: { isCatGalleryPresented = true },
                onToggleTheme: { themeController.toggle(systemScheme: colorScheme) },
                ticker: ticker
            )

            // Web 的三个 panel 始终留在 DOM 里，切换只改可见性；这里同样保留各页状态。
            ZStack {
                panel(.portfolio) {
                    PortfolioView(
                        model: PortfolioViewModel(
                            repository: FixedScopeHoldingRepository(
                                repository: scopedRepository,
                                scope: accountModel.activeScope
                            )
                        ),
                        isSignedIn: accountModel.isSignedIn,
                        onSignIn: {
                            Task { await accountModel.signIn(using: .google) }
                        }
                    )
                    .id(accountModel.activeScope)
                }

                panel(.calculator) { CalculatorView() }

                panel(.exchangeRate) { ExchangeRateView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 导航浮在内容之上，内容从毛玻璃底下穿过。
        //
        // 这里**不用** `safeAreaInset`：那份 inset 传不进各页自己的 ScrollView，
        // 表现就是底部内容默认被导航挡住、能拖出来但一松手又弹回去。改成 overlay
        // 之后，由各页用 `.contentMargins(.bottom, PawLayout.tabBarHeight)` 自己
        // 留出下边距——这条不依赖 safe area 的传播，是确定生效的。
        .overlay(alignment: .bottom) {
            PawTabBar(selection: $selection)
        }
        .background(PawTheme.bg1)
        .pawToast()
        .environment(\.pawViewportWidth, viewportWidth)
        .preferredColorScheme(themeController.preference)
        .sheet(isPresented: $isAccountPresented) {
            AccountView(model: accountModel)
        }
        .sheet(isPresented: $isCatGalleryPresented) {
            // 双击头像的彩蛋在未登录时也能看，只是选中的头像存不下来。
            CatGallerySheet(selected: accountModel.identity?.avatar) { avatar in
                guard let identity = accountModel.identity else { return }
                Task {
                    _ = await accountModel.saveProfile(
                        displayName: identity.displayName,
                        avatar: avatar
                    )
                }
            }
        }
        .task {
            AssetLogoStore.shared.loadIndexIfNeeded()
            await accountModel.loadIfNeeded()
            await ticker.load()
        }
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
