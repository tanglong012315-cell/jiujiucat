// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PawFolioDomain",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PawFolio", targets: ["PawFolio"])
    ],
    targets: [
        .target(
            name: "PawFolio",
            path: "PawFolio",
            exclude: [
                "App",
                "DesignSystem",
                "Features",
                "Resources",
                "Data/AssetLogoStore.swift",
                "Data/ExchangeRateClient.swift"
            ],
            sources: [
                "Domain",
                "Data/HoldingRepository.swift",
                "Data/LedgerRepository.swift",
                "Data/LedgerBootstrapService.swift",
                "Data/LedgerGuestImportService.swift",
                "Data/CloudSyncContracts.swift",
                "Data/SupabaseServices.swift",
                "Data/KeychainSessionStore.swift",
                "Data/HoldingSyncCoordinator.swift",
                "Data/GuestImportDecisionStore.swift",
                "Data/AccountProfileStore.swift",
                "Data/ProfileSyncCoordinator.swift",
                "Data/MarketDataClient.swift",
                "Data/MarketQuoteRepository.swift",
                "Data/PreferencesStore.swift"
            ]
        ),
        .testTarget(
            name: "PawFolioTests",
            dependencies: ["PawFolio"],
            path: "PawFolioTests",
            exclude: [
                "AccountViewModelTests.swift",
                "ExchangeRateViewModelTests.swift",
                "LedgerPortfolioViewModelTests.swift",
                "PortfolioViewModelTests.swift"
            ]
        )
    ]
)
