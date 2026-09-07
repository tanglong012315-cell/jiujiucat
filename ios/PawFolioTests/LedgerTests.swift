import XCTest
@testable import PawFolio

final class LedgerTests: XCTestCase {
    private let usd = LedgerAsset(code: "USD", kind: .fiat)
    private let btc = LedgerAsset(code: "BTC", kind: .cryptocurrency)

    func testDepositAndExpenseKeepAssetBalanced() throws {
        let deposit = try LedgerEntry.deposit(
            asset: usd,
            quantity: 1_000,
            into: "Bank",
            occurredAt: Date(timeIntervalSince1970: 1),
            note: " Salary "
        )
        let expense = try LedgerEntry.expense(
            asset: usd,
            quantity: 125,
            from: "Bank",
            occurredAt: Date(timeIntervalSince1970: 2)
        )

        let projection = try LedgerProjection(entries: [expense, deposit])

        XCTAssertEqual(projection.balance(in: .fiat("bank"), asset: usd), 875, accuracy: 1e-9)
        XCTAssertEqual(deposit.note, "Salary")
        XCTAssertEqual(deposit.postings.reduce(0) { $0 + $1.quantity }, 0, accuracy: 1e-9)
    }

    func testExpenseCannotOverdrawAccount() throws {
        let expense = try LedgerEntry.expense(
            asset: usd,
            quantity: 1,
            from: "Cash",
            occurredAt: Date()
        )

        XCTAssertThrowsError(try LedgerProjection(entries: [expense])) { error in
            guard case LedgerError.insufficientBalance(let account, let asset) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(account, .fiat("cash"))
            XCTAssertEqual(asset, self.usd)
        }
    }

    func testBuyUsesTradingAccountAndTracksActualCost() throws {
        let funding = try LedgerEntry.openingBalance(
            asset: usd,
            quantity: 50_000,
            account: .fiat("exchange"),
            occurredAt: Date(timeIntervalSince1970: 1),
            legacyHoldingID: "cash",
            id: "opening"
        )
        let buy = try LedgerEntry.buy(
            asset: btc,
            quantity: 2,
            unitPrice: 10_000,
            settlementAsset: usd,
            fee: 25,
            occurredAt: Date(timeIntervalSince1970: 2)
        )

        let projection = try LedgerProjection(entries: [funding, buy])

        XCTAssertEqual(projection.balance(in: .fiat("exchange"), asset: usd), 29_975, accuracy: 1e-9)
        XCTAssertEqual(projection.balance(in: .trading, asset: btc), 2, accuracy: 1e-9)
        XCTAssertEqual(projection.tradingPositions[btc]?.averageCost ?? 0, 10_012.5, accuracy: 1e-9)
    }

    func testTradeRejectsUnsupportedSettlementCurrency() {
        let cny = LedgerAsset(code: "CNY", kind: .fiat)
        XCTAssertThrowsError(try LedgerEntry.buy(
            asset: btc,
            quantity: 1,
            unitPrice: 100,
            settlementAsset: cny,
            occurredAt: Date()
        )) { error in
            XCTAssertEqual(error as? LedgerError, .unsupportedSettlementAsset)
        }
    }

    func testSpotTransactionsRejectCryptoAndSettlementRequiresTheCorrectKind() {
        XCTAssertThrowsError(try LedgerEntry.deposit(
            asset: btc, quantity: 1, occurredAt: Date()
        )) { error in
            XCTAssertEqual(error as? LedgerError, .invalidSpotAsset)
        }
        XCTAssertThrowsError(try LedgerEntry.buy(
            asset: btc,
            quantity: 1,
            unitPrice: 100,
            settlementAsset: LedgerAsset(code: "USD", kind: .stablecoin),
            occurredAt: Date()
        )) { error in
            XCTAssertEqual(error as? LedgerError, .unsupportedSettlementAsset)
        }
    }

    func testMalformedEntryIsRejectedWhenAssetDoesNotBalance() {
        XCTAssertThrowsError(try LedgerEntry(
            kind: .deposit,
            occurredAt: Date(),
            postings: [LedgerPosting(account: .fiat("exchange"), asset: usd, quantity: 10)]
        )) { error in
            XCTAssertEqual(error as? LedgerError, .unbalancedEntry)
        }
    }

    func testPrimaryPostingUsesSettlementCashForBuyAndSell() throws {
        let buy = try LedgerEntry.buy(
            asset: btc,
            quantity: 2,
            unitPrice: 100,
            settlementAsset: usd,
            fee: 3,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let sell = try LedgerEntry.sell(
            asset: btc,
            quantity: 1,
            unitPrice: 125,
            settlementAsset: usd,
            fee: 2,
            occurredAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(buy.primaryUserPosting?.account, .fiat("exchange"))
        XCTAssertEqual(buy.primaryUserPosting?.asset, usd)
        XCTAssertEqual(buy.primaryUserPosting?.quantity ?? 0, -203, accuracy: 1e-9)
        XCTAssertEqual(sell.primaryUserPosting?.account, .fiat("exchange"))
        XCTAssertEqual(sell.primaryUserPosting?.asset, usd)
        XCTAssertEqual(sell.primaryUserPosting?.quantity ?? 0, 123, accuracy: 1e-9)
    }

    func testPrimaryPostingUsesFundingSideForEarnMovements() throws {
        let product = try EarnProduct(
            id: "earn-usd",
            name: "USD Flexible",
            asset: usd,
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .monthly,
            startsAt: Date(timeIntervalSince1970: 1)
        )
        let subscribe = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 50,
            occurredAt: Date(timeIntervalSince1970: 2)
        )
        let redeem = try LedgerEntry.earnRedeem(
            product: product,
            quantity: 20,
            occurredAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(subscribe.primaryUserPosting?.account, .fiat("exchange"))
        XCTAssertEqual(subscribe.primaryUserPosting?.quantity ?? 0, -50, accuracy: 1e-9)
        XCTAssertEqual(redeem.primaryUserPosting?.account, .fiat("exchange"))
        XCTAssertEqual(redeem.primaryUserPosting?.quantity ?? 0, 20, accuracy: 1e-9)
    }

    func testReversalKeepsBothRecordsAndCancelsTheOriginalEffect() throws {
        let deposit = try LedgerEntry.deposit(
            asset: usd,
            quantity: 100,
            occurredAt: Date(timeIntervalSince1970: 1),
            id: "deposit"
        )
        let reversal = try LedgerEntry.reversal(
            of: deposit,
            occurredAt: Date(timeIntervalSince1970: 2),
            id: "reversal"
        )

        let projection = try LedgerProjection(entries: [deposit, reversal])

        XCTAssertEqual(projection.balance(in: .fiat("exchange"), asset: usd), 0, accuracy: 1e-9)
        XCTAssertEqual(projection.appliedEntryIDs, ["deposit", "reversal"])
        XCTAssertThrowsError(try LedgerProjection(entries: [deposit, reversal, reversal]))
    }

    func testCryptoEarnMovesAverageCostOutOfTradingAndBack() throws {
        let funding = try LedgerEntry.openingBalance(
            asset: usd, quantity: 1_000, account: .fiat("exchange"),
            occurredAt: Date(timeIntervalSince1970: 1), legacyHoldingID: "cash", id: "cash"
        )
        let buy = try LedgerEntry.buy(
            asset: btc, quantity: 2, unitPrice: 100, settlementAsset: usd,
            occurredAt: Date(timeIntervalSince1970: 2), id: "buy"
        )
        let product = try EarnProduct(
            id: "btc-earn", name: "BTC Earn", asset: btc, annualRatePercent: 2,
            interestMode: .simple, term: .flexible, payoutFrequency: .monthly,
            startsAt: Date(timeIntervalSince1970: 2)
        )
        let subscribe = try LedgerEntry.earnSubscribe(
            product: product, quantity: 1, occurredAt: Date(timeIntervalSince1970: 3), id: "subscribe"
        )
        let redeem = try LedgerEntry.earnRedeem(
            product: product, quantity: 0.5, occurredAt: Date(timeIntervalSince1970: 4), id: "redeem"
        )

        let projection = try LedgerProjection(entries: [funding, buy, subscribe, redeem])

        XCTAssertEqual(projection.tradingPositions[btc]?.quantity ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(projection.tradingPositions[btc]?.costBasis ?? 0, 150, accuracy: 1e-9)
        XCTAssertEqual(projection.earnPositions[product.id]?.quantity ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(projection.earnPositions[product.id]?.costBasis ?? 0, 50, accuracy: 1e-9)
    }

    func testLedgerValuationUsesQuotesRatesAndExternalCapitalOnly() throws {
        let cny = LedgerAsset(code: "CNY", kind: .fiat)
        let cash = try LedgerEntry.deposit(
            asset: cny, quantity: 700, occurredAt: Date(timeIntervalSince1970: 1), id: "cash"
        )
        let usdFunding = try LedgerEntry.deposit(
            asset: usd, quantity: 200, occurredAt: Date(timeIntervalSince1970: 1), id: "usd"
        )
        let buy = try LedgerEntry.buy(
            asset: btc, quantity: 1, unitPrice: 100, settlementAsset: usd,
            occurredAt: Date(timeIntervalSince1970: 2), id: "buy"
        )
        let projection = try LedgerProjection(entries: [cash, usdFunding, buy])
        let quote = MarketQuote(
            symbol: "BTC-USD", currency: "USD", price: 125, changePercent: 0,
            series: [], marketTimeMilliseconds: nil, fetchedAtMilliseconds: 3
        )
        let rates = ExchangeRateSnapshot(
            base: .usd, ratesPerUSD: [.usd: 1, .cny: 7], fetchedAt: Date()
        )

        let summary = LedgerValuation.summary(
            entries: [cash, usdFunding, buy], projection: projection,
            quotes: ["BTC-USD": quote], exchangeRates: rates
        )

        XCTAssertEqual(summary.totalValueUSD ?? 0, 325, accuracy: 1e-9)
        XCTAssertEqual(summary.contributedCapitalUSD ?? 0, 300, accuracy: 1e-9)
        XCTAssertEqual(summary.profitUSD ?? 0, 25, accuracy: 1e-9)
    }

    func testLedgerValuationReportsMissingQuoteButValuesStablecoinWithoutOne() throws {
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let unknown = LedgerAsset(code: "UNKNOWN", kind: .equity)
        let stableDeposit = try LedgerEntry.deposit(
            asset: usdt, quantity: 25, occurredAt: Date(timeIntervalSince1970: 1), id: "stable"
        )
        let opening = try LedgerEntry.openingBalance(
            asset: unknown, quantity: 2, account: .trading,
            occurredAt: Date(timeIntervalSince1970: 1), legacyHoldingID: "unknown", unitCost: 3, id: "unknown"
        )
        let entries = [stableDeposit, opening]
        let summary = LedgerValuation.summary(
            entries: entries,
            projection: try LedgerProjection(entries: entries),
            quotes: [:],
            exchangeRates: nil
        )

        XCTAssertNil(summary.totalValueUSD)
        XCTAssertEqual(summary.missingAssetCodes, ["UNKNOWN"])
    }

    func testLedgerValuationHistoryEndsAtHeadlineTotalWithUnsortedSeries() throws {
        let now = Date(timeIntervalSince1970: 40)
        let opening = try LedgerEntry.openingBalance(
            asset: btc, quantity: 1, account: .trading,
            occurredAt: Date(timeIntervalSince1970: 1), legacyHoldingID: "btc", unitCost: 50, id: "btc"
        )
        let quote = MarketQuote(
            symbol: "BTC-USD", currency: "USD", price: 125, changePercent: 0,
            series: [
                MarketPricePoint(timestampMilliseconds: 30_000, price: 90),
                MarketPricePoint(timestampMilliseconds: 10_000, price: 70),
                MarketPricePoint(timestampMilliseconds: 20_000, price: 80)
            ],
            marketTimeMilliseconds: nil,
            fetchedAtMilliseconds: 40_000
        )
        let summary = LedgerValuation.summary(
            entries: [opening], projection: try LedgerProjection(entries: [opening]),
            quotes: ["BTC-USD": quote], exchangeRates: nil, asOf: now
        )

        XCTAssertEqual(summary.totalValueUSD, 125)
        XCTAssertEqual(summary.historyUSD.count, 12)
        XCTAssertEqual(summary.historyUSD.last, summary.totalValueUSD)
    }

    func testPortfolioChartRequiresPositiveAssetsAndValidHistory() {
        XCTAssertFalse(LedgerPortfolioChartPolicy.shouldShow(totalValueUSD: 0, values: [0, 0]))
        XCTAssertFalse(LedgerPortfolioChartPolicy.shouldShow(totalValueUSD: nil, values: [1, 2]))
        XCTAssertFalse(LedgerPortfolioChartPolicy.shouldShow(totalValueUSD: 100, values: [100]))
        XCTAssertFalse(
            LedgerPortfolioChartPolicy.shouldShow(
                totalValueUSD: 100,
                values: [100, .nan]
            )
        )
        XCTAssertTrue(LedgerPortfolioChartPolicy.shouldShow(totalValueUSD: 100, values: [90, 100]))
    }

    /// 展开态那张图跟收起态的迷你曲线取的是两条序列：区间由 1D/1W/1M/1Y 决定，
    /// 点上必须带时间戳，两端的坐标标注才有东西可写。
    func testChartSeriesWindowFollowsTheSelectedRange() throws {
        let now = Date(timeIntervalSince1970: 400 * 86_400)
        let deposit = try LedgerEntry.deposit(
            asset: usd, quantity: 100, occurredAt: now.addingTimeInterval(-200 * 86_400), id: "deposit"
        )
        let week = LedgerValuation.series(
            entries: [deposit], quotes: [:], exchangeRates: nil, range: .week, asOf: now
        )

        XCTAssertEqual(week.count, LedgerValuation.seriesSampleCount)
        XCTAssertEqual(week.last?.value, 100)
        XCTAssertEqual(
            week.last!.timestampMilliseconds - week.first!.timestampMilliseconds,
            PortfolioHistoryRange.week.spanMilliseconds,
            accuracy: 1
        )
    }

    /// 建账之前那一段恒为 0，画出来是贴着底边的长横线。起点跟着第一笔分录走，
    /// 只有 10 天流水时切到 1Y 也不该先躺 355 天的 0。
    func testChartSeriesStartsAtTheFirstEntryRatherThanTheFullWindow() throws {
        let now = Date(timeIntervalSince1970: 400 * 86_400)
        let firstEntryAt = now.addingTimeInterval(-10 * 86_400)
        let deposit = try LedgerEntry.deposit(
            asset: usd, quantity: 100, occurredAt: firstEntryAt, id: "deposit"
        )
        let year = LedgerValuation.series(
            entries: [deposit], quotes: [:], exchangeRates: nil, range: .year, asOf: now
        )

        XCTAssertEqual(
            year.first?.timestampMilliseconds ?? 0,
            firstEntryAt.timeIntervalSince1970 * 1_000,
            accuracy: 1
        )
        XCTAssertEqual(year.first?.value, 100)
    }

    func testReversedDepositDoesNotCountAsContributedCapital() throws {
        let deposit = try LedgerEntry.deposit(
            asset: usd, quantity: 100, occurredAt: Date(timeIntervalSince1970: 1), id: "deposit"
        )
        let reversal = try LedgerEntry.reversal(
            of: deposit, occurredAt: Date(timeIntervalSince1970: 2), id: "reverse"
        )
        let entries = [deposit, reversal]
        let summary = LedgerValuation.summary(
            entries: entries,
            projection: try LedgerProjection(entries: entries),
            quotes: [:], exchangeRates: nil, asOf: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(summary.totalValueUSD, 0)
        XCTAssertEqual(summary.contributedCapitalUSD, 0)
        XCTAssertEqual(summary.profitUSD, 0)
    }
}
