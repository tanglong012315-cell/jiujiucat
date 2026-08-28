import SwiftUI

struct RootTabView: View {
    private enum Tab: Hashable {
        case portfolio
        case calculator
        case exchangeRate
        case account
    }

    @State private var selection: Tab = .calculator
    @StateObject private var accountModel: AccountViewModel
    private let scopedRepository: ScopedLocalHoldingRepository

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
    }

    var body: some View {
        TabView(selection: $selection) {
            PortfolioView(
                model: PortfolioViewModel(
                    repository: FixedScopeHoldingRepository(
                        repository: scopedRepository,
                        scope: accountModel.activeScope
                    )
                )
            )
                .id(accountModel.activeScope)
                .tabItem {
                    Label("投资组合", systemImage: "chart.pie")
                }
                .tag(Tab.portfolio)

            CalculatorView()
                .tabItem {
                    Label("计算", systemImage: "function")
                }
                .tag(Tab.calculator)

            ExchangeRateView()
                .tabItem {
                    Label("汇率", systemImage: "arrow.left.arrow.right")
                }
                .tag(Tab.exchangeRate)

            AccountView(model: accountModel)
                .tabItem {
                    Label("账户", systemImage: "person.crop.circle")
                }
                .tag(Tab.account)
        }
        .task {
            await accountModel.loadIfNeeded()
        }
    }
}
