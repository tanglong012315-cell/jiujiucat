import XCTest
@testable import PawFolio

@MainActor
final class LedgerPortfolioViewModelTests: XCTestCase {
    private let usd = LedgerAsset(code: "USD", kind: .fiat)
    private let btc = LedgerAsset(code: "BTC", kind: .cryptocurrency)

    func testAccountLabelToneOnlyEmphasizesASelectionWhenMultipleAccountsExist() {
        XCTAssertFalse(LedgerAccountLabelTonePolicy.usesPrimaryTone(isSelected: true, accountCount: 1))
        XCTAssertTrue(LedgerAccountLabelTonePolicy.usesPrimaryTone(isSelected: true, accountCount: 2))
        XCTAssertFalse(LedgerAccountLabelTonePolicy.usesPrimaryTone(isSelected: false, accountCount: 2))
    }

    func testInitialLoadingCompletesAfterFirstReload() async {
        let fixture = makeFixture()

        XCTAssertTrue(fixture.model.isLoading)
        XCTAssertFalse(fixture.model.hasCompletedInitialLoad)

        await fixture.model.reload()

        XCTAssertFalse(fixture.model.isLoading)
        XCTAssertTrue(fixture.model.hasCompletedInitialLoad)
    }

    func testUnavailableMarketPriceDoesNotShowAPersistentRefreshBanner() async {
        let unavailableAsset = LedgerAsset(code: "111NSETEST.NS", kind: .equity)
        let ledger = LedgerStub()
        let model = LedgerPortfolioViewModel(
            ledgerRepository: ledger,
            holdingRepository: HoldingStub(),
            scope: .guest,
            quoteRepository: UnavailableQuoteRepositoryStub()
        )
        await model.reload()

        let deposited = await model.deposit(asset: usd, quantity: 1_000, location: "exchange", note: nil)
        let bought = await model.buy(
            asset: unavailableAsset,
            quantity: 1,
            unitPrice: 200,
            settlementAsset: usd,
            fee: 0,
            note: nil
        )
        XCTAssertTrue(deposited)
        XCTAssertTrue(bought)
        XCTAssertEqual(model.portfolioSummary.missingAssetCodes, [unavailableAsset.code])
        XCTAssertNil(model.valuationStatusMessage)

        await model.reload()

        XCTAssertEqual(model.portfolioSummary.missingAssetCodes, [unavailableAsset.code])
        XCTAssertNil(model.valuationStatusMessage)
    }

    func testSpotBalancesRestoreAndPersistManualOrder() async {
        let cny = LedgerAsset(code: "CNY", kind: .fiat)
        let usdg = LedgerAsset(code: "USDG", kind: .stablecoin)
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let preferences = LedgerPortfolioPreferencesStub(spotOrder: [usdt, cny])
        let ledger = LedgerStub()
        let model = LedgerPortfolioViewModel(
            ledgerRepository: ledger,
            holdingRepository: HoldingStub(),
            scope: .guest,
            portfolioPreferences: preferences
        )
        await model.reload()

        let depositedCNY = await model.deposit(asset: cny, quantity: 100, location: "cash", note: nil)
        let depositedUSDG = await model.deposit(asset: usdg, quantity: 100, location: "exchange", note: nil)
        let depositedUSDT = await model.deposit(asset: usdt, quantity: 100, location: "exchange", note: nil)
        XCTAssertTrue(depositedCNY)
        XCTAssertTrue(depositedUSDG)
        XCTAssertTrue(depositedUSDT)
        XCTAssertEqual(model.spotBalances.map(\.asset), [usdt, cny, usdg])

        model.moveSpotAsset(usdg, to: 0)

        XCTAssertEqual(model.spotBalances.map(\.asset), [usdg, usdt, cny])
        XCTAssertEqual(preferences.spotOrder, [usdg, usdt, cny])
    }

    func testSpotAssetMoveKeepsTemporarilyHiddenPreferences() async {
        let cny = LedgerAsset(code: "CNY", kind: .fiat)
        let usdg = LedgerAsset(code: "USDG", kind: .stablecoin)
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let preferences = LedgerPortfolioPreferencesStub(spotOrder: [usdg, cny, usdt])
        let ledger = LedgerStub()
        let model = LedgerPortfolioViewModel(
            ledgerRepository: ledger,
            holdingRepository: HoldingStub(),
            scope: .guest,
            portfolioPreferences: preferences
        )
        await model.reload()

        let depositedCNY = await model.deposit(asset: cny, quantity: 100, location: "cash", note: nil)
        let depositedUSDT = await model.deposit(asset: usdt, quantity: 100, location: "exchange", note: nil)
        XCTAssertTrue(depositedCNY)
        XCTAssertTrue(depositedUSDT)
        model.moveSpotAsset(usdt, to: 0)

        XCTAssertEqual(model.spotBalances.map(\.asset), [usdt, cny])
        XCTAssertEqual(preferences.spotOrder, [usdt, cny, usdg])
    }

    func testTradingBalancesRestoreAndPersistManualOrder() async {
        let eth = LedgerAsset(code: "ETH", kind: .cryptocurrency)
        let preferences = LedgerPortfolioPreferencesStub(tradingOrder: [eth, btc])
        let ledger = LedgerStub()
        let model = LedgerPortfolioViewModel(
            ledgerRepository: ledger,
            holdingRepository: HoldingStub(),
            scope: .guest,
            portfolioPreferences: preferences
        )
        await model.reload()

        let deposited = await model.deposit(asset: usd, quantity: 1_000, location: "exchange", note: nil)
        let boughtBTC = await model.buy(
            asset: btc,
            quantity: 1,
            unitPrice: 100,
            settlementAsset: usd,
            fee: 0,
            note: nil
        )
        let boughtETH = await model.buy(
            asset: eth,
            quantity: 1,
            unitPrice: 100,
            settlementAsset: usd,
            fee: 0,
            note: nil
        )
        XCTAssertTrue(deposited)
        XCTAssertTrue(boughtBTC)
        XCTAssertTrue(boughtETH)
        XCTAssertEqual(model.tradingBalances.map(\.asset), [eth, btc])

        model.moveTradingAsset(btc, to: 0)

        XCTAssertEqual(model.tradingBalances.map(\.asset), [btc, eth])
        XCTAssertEqual(preferences.tradingOrder, [btc, eth])
    }

    func testEarnBalancesRestoreAndPersistManualOrder() async throws {
        let first = try makeProduct(id: "first", asset: usd, mode: .simple)
        let second = try makeProduct(id: "second", asset: usd, mode: .compound)
        let preferences = LedgerPortfolioPreferencesStub(earnOrder: [second.id, first.id])
        let ledger = LedgerStub()
        let model = LedgerPortfolioViewModel(
            ledgerRepository: ledger,
            holdingRepository: HoldingStub(),
            scope: .guest,
            portfolioPreferences: preferences
        )
        await model.reload()

        let deposited = await model.deposit(asset: usd, quantity: 1_000, location: "exchange", note: nil)
        let createdFirst = await model.createProduct(first)
        let createdSecond = await model.createProduct(second)
        let subscribedFirst = await model.subscribe(product: first, quantity: 100)
        let subscribedSecond = await model.subscribe(product: second, quantity: 100)
        XCTAssertTrue(deposited)
        XCTAssertTrue(createdFirst)
        XCTAssertTrue(createdSecond)
        XCTAssertTrue(subscribedFirst)
        XCTAssertTrue(subscribedSecond)
        XCTAssertEqual(model.earnBalances.map { $0.product.id }, [second.id, first.id])

        model.moveEarnProduct(first.id, to: 0)

        XCTAssertEqual(model.earnBalances.map { $0.product.id }, [first.id, second.id])
        XCTAssertEqual(preferences.earnOrder, [first.id, second.id])
    }

    func testAddAssetCreditsExchangeSpot() async {
        let fixture = makeFixture()
        await fixture.model.reload()

        let deposited = await fixture.model.deposit(
            asset: usd,
            quantity: 1_000,
            location: "exchange",
            note: "Salary"
        )
        XCTAssertTrue(deposited)

        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            1_000,
            accuracy: 1e-9
        )
        XCTAssertEqual(fixture.model.entries.first?.note, "Salary")
    }

    func testPayRejectsInsufficientSelectedAccountBalance() async {
        let fixture = makeFixture()
        await fixture.model.reload()

        let paid = await fixture.model.pay(
            asset: usd,
            quantity: 1,
            location: "cash",
            note: nil
        )
        XCTAssertFalse(paid)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("cash"), asset: usd),
            0,
            accuracy: 1e-9
        )
        XCTAssertNotNil(fixture.model.errorMessage)
    }

    func testBuyConsumesOnlyExchangeSpotAndSellReturnsThere() async {
        let fixture = makeFixture()
        await fixture.model.reload()
        let deposited = await fixture.model.deposit(
            asset: usd,
            quantity: 1_000,
            location: "exchange",
            note: nil
        )
        XCTAssertTrue(deposited)

        let bought = await fixture.model.buy(
            asset: btc,
            quantity: 2,
            unitPrice: 100,
            settlementAsset: usd,
            fee: 3,
            note: nil
        )
        XCTAssertTrue(bought)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            797,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            fixture.model.projection.balance(in: .trading, asset: btc),
            2,
            accuracy: 1e-9
        )

        let sold = await fixture.model.sell(
            asset: btc,
            quantity: 1,
            unitPrice: 125,
            settlementAsset: usd,
            fee: 2,
            note: nil
        )
        XCTAssertTrue(sold)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            920,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            fixture.model.projection.balance(in: .trading, asset: btc),
            1,
            accuracy: 1e-9
        )
    }

    func testEarnRoutesFiatFromSpotAndCryptoFromTrading() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        let firstDeposit = await fixture.model.deposit(asset: usd, quantity: 500, location: "exchange", note: nil)
        let secondDeposit = await fixture.model.deposit(asset: usd, quantity: 500, location: "exchange", note: nil)
        XCTAssertTrue(firstDeposit)
        XCTAssertTrue(secondDeposit)
        let bought = await fixture.model.buy(
            asset: btc,
            quantity: 2,
            unitPrice: 100,
            settlementAsset: usd,
            fee: 0,
            note: nil
        )
        XCTAssertTrue(bought)

        let fiatProduct = try makeProduct(id: "usd-earn", asset: usd, mode: .simple)
        let cryptoProduct = try makeProduct(id: "btc-earn", asset: btc, mode: .compound)
        let createdFiat = await fixture.model.createProduct(fiatProduct)
        let createdCrypto = await fixture.model.createProduct(cryptoProduct)
        XCTAssertEqual(fixture.model.preferredEarnAsset(code: "btc", fallbackKind: .cryptocurrency), btc)
        XCTAssertEqual(fixture.model.availableBalance(for: cryptoProduct), 2, accuracy: 1e-9)
        let subscribedFiat = await fixture.model.subscribe(product: fiatProduct, quantity: 100)
        let subscribedCrypto = await fixture.model.subscribe(product: cryptoProduct, quantity: 1)
        XCTAssertTrue(createdFiat)
        XCTAssertTrue(createdCrypto)
        XCTAssertTrue(subscribedFiat)
        XCTAssertTrue(subscribedCrypto)

        XCTAssertEqual(fixture.model.projection.balance(in: .fiat("exchange"), asset: usd), 700, accuracy: 1e-9)
        XCTAssertEqual(fixture.model.projection.balance(in: .trading, asset: btc), 1, accuracy: 1e-9)
        XCTAssertEqual(fixture.model.projection.balance(in: .earn(productID: fiatProduct.id), asset: usd), 100, accuracy: 1e-9)
        XCTAssertEqual(fixture.model.projection.balance(in: .earn(productID: cryptoProduct.id), asset: btc), 1, accuracy: 1e-9)
    }

    func testFlexibleEarnPartialRedemptionReturnsOnlyTheRequestedAmountToSpot() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        let deposited = await fixture.model.deposit(asset: usd, quantity: 500, location: "exchange", note: nil)

        let product = try makeProduct(id: "usd-flexible-redeem", asset: usd, mode: .simple)
        let created = await fixture.model.createProduct(product)
        let subscribed = await fixture.model.subscribe(product: product, quantity: 100)
        let redeemed = await fixture.model.redeem(product: product, quantity: 40)

        XCTAssertTrue(deposited)
        XCTAssertTrue(created)
        XCTAssertTrue(subscribed)
        XCTAssertTrue(redeemed)

        XCTAssertEqual(
            fixture.model.projection.balance(in: .earn(productID: product.id), asset: usd),
            60,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            440,
            accuracy: 1e-9
        )
    }

    func testLegacyUSDGProductFindsFiatBalanceAndCorrectsAssetWhenSubscribing() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        let usdg = LedgerAsset(code: "USDG", kind: .stablecoin)
        let legacyWrongAsset = LedgerAsset(code: "USDG", kind: .cryptocurrency)
        let deposited = await fixture.model.deposit(
            asset: usdg,
            quantity: 250,
            location: "exchange",
            note: nil
        )
        XCTAssertTrue(deposited)

        let product = try makeProduct(id: "legacy-usdg", asset: legacyWrongAsset, mode: .simple)
        let created = await fixture.model.createProduct(product)
        XCTAssertTrue(created)
        XCTAssertEqual(fixture.model.preferredEarnAsset(code: "usdg", fallbackKind: .cryptocurrency), usdg)
        XCTAssertEqual(fixture.model.availableBalance(for: product), 250, accuracy: 1e-9)

        let subscribed = await fixture.model.subscribe(product: product, quantity: 100)
        XCTAssertTrue(subscribed)
        XCTAssertEqual(fixture.model.snapshot.earnProducts.first?.asset, usdg)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usdg),
            150,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            fixture.model.projection.balance(in: .earn(productID: product.id), asset: usdg),
            100,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            fixture.model.projection.balance(in: .trading, asset: legacyWrongAsset),
            0,
            accuracy: 1e-9
        )
    }

    func testInterestPayoutReinvestsOnlyCompoundProducts() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        let deposited = await fixture.model.deposit(asset: usd, quantity: 500, location: "exchange", note: nil)
        XCTAssertTrue(deposited)

        let simple = try makeProduct(id: "simple", asset: usd, mode: .simple)
        let compound = try makeProduct(id: "compound", asset: usd, mode: .compound)
        let createdSimple = await fixture.model.createProduct(simple)
        let createdCompound = await fixture.model.createProduct(compound)
        let subscribedSimple = await fixture.model.subscribe(product: simple, quantity: 100)
        let subscribedCompound = await fixture.model.subscribe(product: compound, quantity: 100)
        let simplePayoutAt = try XCTUnwrap(fixture.model.nextPayoutDate(for: simple))
        let compoundPayoutAt = try XCTUnwrap(fixture.model.nextPayoutDate(for: compound))
        let paidSimple = await fixture.model.recordInterestPayout(
            product: simple,
            quantity: 5,
            occurredAt: simplePayoutAt
        )
        let paidCompound = await fixture.model.recordInterestPayout(
            product: compound,
            quantity: 7,
            occurredAt: compoundPayoutAt
        )
        XCTAssertTrue(createdSimple)
        XCTAssertTrue(createdCompound)
        XCTAssertTrue(subscribedSimple)
        XCTAssertTrue(subscribedCompound)
        XCTAssertTrue(paidSimple)
        XCTAssertTrue(paidCompound)

        XCTAssertEqual(fixture.model.projection.balance(in: .earn(productID: simple.id), asset: usd), 100, accuracy: 1e-9)
        XCTAssertEqual(fixture.model.projection.balance(in: .earn(productID: compound.id), asset: usd), 107, accuracy: 1e-9)
        XCTAssertEqual(fixture.model.projection.balance(in: .fiat("exchange"), asset: usd), 305, accuracy: 1e-9)
    }

    func testEarnTotalIncludesPaidInterestButNotCurrentAccrual() async throws {
        let fixture = makeFixture()
        let product = try makeProduct(id: "paid-total", asset: usd, mode: .simple)
        let opening = try LedgerEntry.openingBalance(
            asset: usd,
            quantity: 100,
            account: .earn(productID: product.id),
            occurredAt: Date(timeIntervalSince1970: 1),
            legacyHoldingID: "paid-total-opening",
            id: "paid-total-opening"
        )
        try await fixture.ledger.save(
            LedgerStoreSnapshot(entries: [opening], earnProducts: [product]),
            for: .guest
        )
        await fixture.model.reload()

        XCTAssertGreaterThan(fixture.model.accruedInterest(for: product), 0)
        XCTAssertEqual(
            try XCTUnwrap(fixture.model.totalEarnPaidInterestUSD),
            0,
            accuracy: 1e-9
        )

        let payout = try LedgerEntry.interestPayout(
            product: product,
            quantity: 3.5,
            occurredAt: Date(timeIntervalSince1970: 86_400),
            id: "paid-total-payout"
        )
        try await fixture.ledger.save(
            LedgerStoreSnapshot(entries: [opening, payout], earnProducts: [product]),
            for: .guest
        )
        await fixture.model.reload()

        XCTAssertEqual(
            try XCTUnwrap(fixture.model.totalEarnPaidInterestUSD),
            3.5,
            accuracy: 1e-9
        )
    }

    func testInterestPayoutRequiresAnExistingHolding() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        let product = try makeProduct(id: "empty", asset: usd, mode: .simple)
        let created = await fixture.model.createProduct(product)
        let paid = await fixture.model.recordInterestPayout(product: product, quantity: 5)

        XCTAssertTrue(created)
        XCTAssertFalse(paid)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            0,
            accuracy: 1e-9
        )
        XCTAssertEqual(fixture.model.errorMessage, "Subscribe before recording an interest payout.")
    }

    func testInterestPayoutCannotBeRecordedBeforeAFullCycle() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func date(day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
            calendar.date(from: DateComponents(
                year: 2026, month: 9, day: day,
                hour: hour, minute: minute, second: second
            ))!
        }

        let fixture = makeFixture()
        let product = try EarnProduct(
            id: "daily-full-cycle",
            name: "Daily Full Cycle",
            asset: usd,
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: date(day: 5, hour: 15, minute: 59)
        )
        let deposit = try LedgerEntry.deposit(
            asset: usd,
            quantity: 100,
            occurredAt: date(day: 5, hour: 10),
            id: "daily-full-cycle-deposit"
        )
        let subscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: date(day: 5, hour: 15, minute: 59),
            id: "daily-full-cycle-subscription"
        )
        try await fixture.ledger.save(
            LedgerStoreSnapshot(entries: [deposit, subscription], earnProducts: [product]),
            for: .guest
        )
        await fixture.model.reload()

        let early = await fixture.model.recordInterestPayout(
            product: product,
            quantity: 1,
            occurredAt: date(day: 6, hour: 15, minute: 59, second: 59)
        )
        XCTAssertFalse(early)
        XCTAssertEqual(fixture.model.errorMessage, "A full payout cycle has not elapsed yet.")
        XCTAssertFalse(fixture.model.entries.contains(where: { $0.kind == .interest }))

        let onTime = await fixture.model.recordInterestPayout(
            product: product,
            quantity: 1,
            occurredAt: date(day: 6, hour: 16)
        )
        XCTAssertTrue(onTime)
        XCTAssertEqual(fixture.model.entries.filter { $0.kind == .interest }.count, 1)
    }

    func testDelistingFlexibleProductRedeemsAllSubscriptionsAndKeepsInterestHistory() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        let deposited = await fixture.model.deposit(asset: usd, quantity: 1_000, location: "exchange", note: nil)
        XCTAssertTrue(deposited)

        let product = try makeProduct(id: "flexible", asset: usd, mode: .simple)
        let created = await fixture.model.createProduct(product)
        let firstSubscription = await fixture.model.subscribe(product: product, quantity: 250)
        let secondSubscription = await fixture.model.subscribe(product: product, quantity: 150)
        let payoutAt = try XCTUnwrap(fixture.model.nextPayoutDate(for: product))
        let paidInterest = await fixture.model.recordInterestPayout(
            product: product,
            quantity: 8,
            occurredAt: payoutAt
        )
        XCTAssertTrue(created)
        XCTAssertTrue(firstSubscription)
        XCTAssertTrue(secondSubscription)
        XCTAssertTrue(paidInterest)

        let interestEntryID = try XCTUnwrap(
            fixture.model.entries.first(where: { $0.kind == .interest })?.id
        )
        let delisted = await fixture.model.delist(product: product)
        XCTAssertTrue(delisted)

        XCTAssertEqual(
            fixture.model.projection.balance(in: .earn(productID: product.id), asset: usd),
            0,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            1_008,
            accuracy: 1e-9
        )
        XCTAssertNotNil(fixture.model.snapshot.earnProducts.first?.delistedAt)
        XCTAssertTrue(fixture.model.snapshot.entries.contains(where: { $0.id == interestEntryID }))
        XCTAssertEqual(fixture.model.entries.filter { $0.kind == .earnRedeem }.count, 1)
    }

    func testDelistingCryptoProductReturnsFullBalanceAndCostToTrading() async throws {
        let fixture = makeFixture()
        let openedAt = Date().addingTimeInterval(-90 * 86_400)
        let deposit = try LedgerEntry.deposit(
            asset: usd,
            quantity: 1_000,
            occurredAt: openedAt,
            id: "btc-delist-deposit"
        )
        let buy = try LedgerEntry.buy(
            asset: btc,
            quantity: 2,
            unitPrice: 100,
            settlementAsset: usd,
            fee: 0,
            occurredAt: openedAt.addingTimeInterval(1),
            id: "btc-delist-buy"
        )
        let product = try makeProduct(id: "btc-flexible", asset: btc, mode: .compound)
        let firstSubscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 0.75,
            occurredAt: openedAt.addingTimeInterval(2),
            id: "btc-delist-subscribe-1"
        )
        let secondSubscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 0.25,
            occurredAt: openedAt.addingTimeInterval(3),
            id: "btc-delist-subscribe-2"
        )
        try await fixture.ledger.save(
            LedgerStoreSnapshot(
                entries: [deposit, buy, firstSubscription, secondSubscription],
                earnProducts: [product]
            ),
            for: .guest
        )
        await fixture.model.reload()

        let paidInterest = await fixture.model.recordInterestPayout(product: product, quantity: 0.1)
        let delisted = await fixture.model.delist(product: product)
        XCTAssertTrue(paidInterest)
        XCTAssertTrue(delisted)

        // 复利已派息进了 Earn 本金，下架时与申购本金一起返回；
        // 它没有买入成本，所以 Trading 数量增加、历史成本仍是 200。
        XCTAssertEqual(fixture.model.projection.balance(in: .trading, asset: btc), 2.1, accuracy: 1e-9)
        XCTAssertEqual(fixture.model.projection.tradingPositions[btc]?.costBasis ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .earn(productID: product.id), asset: btc),
            0,
            accuracy: 1e-9
        )
        XCTAssertEqual(fixture.model.entries.filter { $0.kind == .interest }.count, 1)
    }

    func testUpdatingAPYPersistsTheExistingProductIdentity() async throws {
        let fixture = makeFixture()
        await fixture.model.reload()
        var product = try makeProduct(id: "editable", asset: usd, mode: .simple)
        let created = await fixture.model.createProduct(product)
        product.annualRatePercent = 8.25
        let updated = await fixture.model.updateProduct(product)

        XCTAssertTrue(created)
        XCTAssertTrue(updated)
        XCTAssertEqual(fixture.model.snapshot.earnProducts.count, 1)
        XCTAssertEqual(fixture.model.snapshot.earnProducts.first?.id, "editable")
        XCTAssertEqual(fixture.model.snapshot.earnProducts.first?.annualRatePercent, 8.25)
        XCTAssertEqual(fixture.model.snapshot.earnProducts.first?.initialAnnualRatePercent, 5)
        XCTAssertEqual(fixture.model.snapshot.earnProducts.first?.annualRate(at: Date()), 5)
    }

    func testReversalKeepsHistoryAndCancelsBalance() async {
        let fixture = makeFixture()
        await fixture.model.reload()
        let deposited = await fixture.model.deposit(
            asset: usd, quantity: 100, location: "exchange", note: nil
        )
        XCTAssertTrue(deposited)
        guard let deposit = fixture.model.entries.first else {
            return XCTFail("Missing deposit")
        }

        let reversed = await fixture.model.reverse(deposit)
        XCTAssertTrue(reversed)

        XCTAssertEqual(fixture.model.entries.count, 2)
        XCTAssertEqual(
            fixture.model.projection.balance(in: .fiat("exchange"), asset: usd),
            0,
            accuracy: 1e-9
        )
        XCTAssertFalse(fixture.model.canReverse(deposit))
    }

    private func makeProduct(
        id: String,
        asset: LedgerAsset,
        mode: InterestMode
    ) throws -> EarnProduct {
        try EarnProduct(
            id: id,
            name: id,
            asset: asset,
            annualRatePercent: 5,
            interestMode: mode,
            term: .flexible,
            payoutFrequency: .monthly,
            startsAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeFixture() -> (model: LedgerPortfolioViewModel, ledger: LedgerStub) {
        let ledger = LedgerStub()
        let model = LedgerPortfolioViewModel(
            ledgerRepository: ledger,
            holdingRepository: HoldingStub(),
            scope: .guest
        )
        return (model, ledger)
    }
}

private actor LedgerStub: ScopedLedgerRepository {
    private var snapshot = LedgerStoreSnapshot()

    func load(for scope: HoldingStorageScope) async throws -> LedgerStoreSnapshot { snapshot }

    func save(_ snapshot: LedgerStoreSnapshot, for scope: HoldingStorageScope) async throws {
        self.snapshot = snapshot
    }
}

private actor HoldingStub: HoldingRepository {
    func load() async throws -> [Holding] { [] }
    func save(_ holdings: [Holding]) async throws {}
}

private actor UnavailableQuoteRepositoryStub: MarketQuoteRepositoryServing {
    func cachedQuotes(for symbols: Set<String>) async -> [String: MarketQuote] { [:] }

    func refreshQuotes(for symbols: Set<String>) async -> MarketQuoteRefresh {
        MarketQuoteRefresh(quotes: [:], failedSymbols: symbols, usedCachedValues: false)
    }

    func cachedOneYearHistories(for symbols: Set<String>) async -> [String: MarketPriceHistory] { [:] }

    func refreshOneYearHistories(for symbols: Set<String>) async -> MarketHistoryRefresh {
        MarketHistoryRefresh(histories: [:], failedSymbols: symbols, usedCachedValues: false)
    }
}

private final class LedgerPortfolioPreferencesStub: PortfolioPreferencesStoring, @unchecked Sendable {
    var historyRange: PortfolioHistoryRange?
    var spotOrder: [LedgerAsset]
    var tradingOrder: [LedgerAsset]
    var earnOrder: [String]

    init(
        historyRange: PortfolioHistoryRange? = nil,
        spotOrder: [LedgerAsset] = [],
        tradingOrder: [LedgerAsset] = [],
        earnOrder: [String] = []
    ) {
        self.historyRange = historyRange
        self.spotOrder = spotOrder
        self.tradingOrder = tradingOrder
        self.earnOrder = earnOrder
    }

    func loadHistoryRange() -> PortfolioHistoryRange? { historyRange }

    func save(historyRange: PortfolioHistoryRange) { self.historyRange = historyRange }

    func loadSpotAssetOrder() -> [LedgerAsset] { spotOrder }

    func save(spotAssetOrder: [LedgerAsset]) { spotOrder = spotAssetOrder }

    func loadTradingAssetOrder() -> [LedgerAsset] { tradingOrder }

    func save(tradingAssetOrder: [LedgerAsset]) { tradingOrder = tradingAssetOrder }

    func loadEarnProductOrder() -> [String] { earnOrder }

    func save(earnProductOrder: [String]) { earnOrder = earnProductOrder }
}

/// 交易表单三个数的联动（用户 2026-09-06 定的规则）。
final class LedgerTradeLinkageTests: XCTestCase {
    func testGrossValueIsPriceTimesQuantity() {
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "1.2", price: "123213", current: ""),
            "147855.6"
        )
    }

    /// 数量为空则金额为空、数量为 0 则金额为 0（前提是价格成立）。
    func testEmptyQuantityEmptiesTheGrossValueAndZeroShowsZero() {
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "", price: "123213", current: "8"), ""
        )
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "0", price: "123213", current: "8"), "0"
        )
    }

    /// 价格为空或为 0 时等式不成立：改数量不会波及金额，连「清空数量」也不该
    /// 把金额抹掉——那一步同样是在套一条不成立的等式。
    func testGrossValueIsUntouchedWhenThePriceIsEmptyOrZero() {
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "1.2", price: "", current: "8"), "8"
        )
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "1.2", price: "0", current: "8"), "8"
        )
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "", price: "", current: "8"), "8"
        )
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "0", price: "", current: "8"), "8"
        )
    }

    func testQuantityIsGrossValueOverPrice() {
        XCTAssertEqual(
            LedgerTradeLinkage.quantity(grossValue: "246426", price: "123213", current: "1.2"), "2"
        )
        XCTAssertEqual(
            LedgerTradeLinkage.quantity(grossValue: "", price: "123213", current: "1.2"), ""
        )
    }

    /// 「价格为空或为 0，这个等式不成立，数量这时不会受影响」。
    func testQuantityIsUntouchedWhenThePriceIsEmptyOrZero() {
        XCTAssertEqual(
            LedgerTradeLinkage.quantity(grossValue: "246426", price: "", current: "1.2"), "1.2"
        )
        XCTAssertEqual(
            LedgerTradeLinkage.quantity(grossValue: "246426", price: "0", current: "1.2"), "1.2"
        )
        // 金额被清空也一样：等式不成立就一个字都不动。
        XCTAssertEqual(
            LedgerTradeLinkage.quantity(grossValue: "", price: "", current: "1.2"), "1.2"
        )
    }

    /// 回填的数要能被 `Double(_:)` 读回来，否则联动在下一跳就断了，
    /// 提交时还会判成「数量不合法」。
    func testWrittenBackNumbersStayParseable() {
        let gross = LedgerTradeLinkage.grossValue(quantity: "12000", price: "0.42", current: "")
        XCTAssertNotNil(Double(gross))
        XCTAssertFalse(gross.contains(","))

        let quantity = LedgerTradeLinkage.quantity(grossValue: "5040", price: "0.42", current: "")
        XCTAssertNotNil(Double(quantity))
        XCTAssertFalse(quantity.contains(","))
    }

    /// 半截输入（`1.`）不该把已经算好的金额抹成别的东西。
    func testPartialInputLeavesTheOtherFieldAlone() {
        XCTAssertEqual(
            LedgerTradeLinkage.grossValue(quantity: "-", price: "100", current: "500"), "500"
        )
    }
}
