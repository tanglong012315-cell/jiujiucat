import XCTest
@testable import PawFolio

final class EarnProductTests: XCTestCase {
    func testStocksCannotEnterEarn() {
        XCTAssertThrowsError(try EarnProduct(
            name: "AAPL Earn",
            asset: LedgerAsset(code: "AAPL", kind: .equity),
            annualRatePercent: 3,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: Date()
        )) { error in
            XCTAssertEqual(error as? EarnProductError, .unsupportedAsset)
        }
    }

    func testFixedProductMustUseSimpleInterest() {
        XCTAssertThrowsError(try EarnProduct(
            name: "Fixed USDT",
            asset: LedgerAsset(code: "USDT", kind: .stablecoin),
            annualRatePercent: 5,
            interestMode: .compound,
            term: .fixed,
            payoutFrequency: .atMaturity,
            startsAt: Date(timeIntervalSince1970: 0),
            maturesAt: Date(timeIntervalSince1970: 86_400)
        )) { error in
            XCTAssertEqual(error as? EarnProductError, .fixedMustUseSimpleInterest)
        }
    }

    func testFiatSubscriptionMovesExistingSpotBalance() throws {
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let product = try EarnProduct(
            id: "usdt-flex",
            name: "USDT Flexible",
            asset: usdt,
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: Date(timeIntervalSince1970: 0)
        )
        let opening = try LedgerEntry.openingBalance(
            asset: usdt,
            quantity: 100,
            account: .fiat("exchange"),
            occurredAt: Date(timeIntervalSince1970: 0),
            legacyHoldingID: "cash",
            id: "opening"
        )
        let subscribe = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 60,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let projection = try LedgerProjection(entries: [opening, subscribe])

        XCTAssertEqual(projection.balance(in: .fiat("exchange"), asset: usdt), 40, accuracy: 1e-9)
        XCTAssertEqual(projection.balance(in: .earn(productID: product.id), asset: usdt), 60, accuracy: 1e-9)
    }

    func testCryptoSubscriptionUsesTradingBalance() throws {
        let btc = LedgerAsset(code: "BTC", kind: .cryptocurrency)
        let product = try EarnProduct(
            id: "btc-flex",
            name: "BTC Flexible",
            asset: btc,
            annualRatePercent: 1,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .weekly,
            startsAt: Date(timeIntervalSince1970: 0)
        )
        let subscribe = try LedgerEntry.earnSubscribe(product: product, quantity: 0.1, occurredAt: Date())

        XCTAssertTrue(subscribe.postings.contains { $0.account == .trading && $0.quantity == -0.1 })
    }

    func testCompoundInterestReinvestsOnlyAtPayoutEntry() throws {
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let product = try EarnProduct(
            id: "compound",
            name: "Compound",
            asset: usdt,
            annualRatePercent: 5,
            interestMode: .compound,
            term: .flexible,
            payoutFrequency: .monthly,
            startsAt: Date(timeIntervalSince1970: 0)
        )
        let payout = try LedgerEntry.interestPayout(product: product, quantity: 1.25, occurredAt: Date())

        XCTAssertTrue(payout.postings.contains {
            $0.account == .earn(productID: product.id) && $0.quantity == 1.25
        })
    }

    func testSimpleInterestPaysBackToSpot() throws {
        let usdt = LedgerAsset(code: "USDT", kind: .stablecoin)
        let product = try EarnProduct(
            id: "simple",
            name: "Simple",
            asset: usdt,
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .monthly,
            startsAt: Date(timeIntervalSince1970: 0)
        )
        let payout = try LedgerEntry.interestPayout(product: product, quantity: 1.25, occurredAt: Date())

        XCTAssertTrue(payout.postings.contains {
            $0.account == .fiat("exchange") && $0.quantity == 1.25
        })
    }

    func testPaidInterestExcludesAccrualUntilARealPayoutExists() throws {
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            id: "paid-only",
            name: "Paid only",
            asset: usd,
            annualRatePercent: 36.5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: start
        )
        let opening = try LedgerEntry.openingBalance(
            asset: usd,
            quantity: 100,
            account: .earn(productID: product.id),
            occurredAt: start,
            legacyHoldingID: "legacy",
            id: "opening-paid-only"
        )
        let asOf = Date(timeIntervalSince1970: 10 * 86_400)

        XCTAssertEqual(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: [opening],
                asOf: asOf
            ),
            1,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            EarnInterestCalculator.paidInterest(
                product: product,
                entries: [opening],
                asOf: asOf
            ),
            0,
            accuracy: 1e-9
        )
    }

    func testPaidInterestIncludesOnlyEffectiveUnreversedPayouts() throws {
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            id: "paid",
            name: "Paid",
            asset: usd,
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: start
        )
        let otherProduct = try EarnProduct(
            id: "other-paid",
            name: "Other",
            asset: usd,
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: start
        )
        let first = try LedgerEntry.interestPayout(
            product: product,
            quantity: 1.25,
            occurredAt: Date(timeIntervalSince1970: 100),
            id: "first-paid"
        )
        let reversed = try LedgerEntry.interestPayout(
            product: product,
            quantity: 2,
            occurredAt: Date(timeIntervalSince1970: 200),
            id: "reversed-paid"
        )
        let reversal = try LedgerEntry.reversal(
            of: reversed,
            occurredAt: Date(timeIntervalSince1970: 300),
            id: "paid-reversal"
        )
        let future = try LedgerEntry.interestPayout(
            product: product,
            quantity: 4,
            occurredAt: Date(timeIntervalSince1970: 500),
            id: "future-paid"
        )
        let other = try LedgerEntry.interestPayout(
            product: otherProduct,
            quantity: 8,
            occurredAt: Date(timeIntervalSince1970: 100),
            id: "other-product-paid"
        )

        XCTAssertEqual(
            EarnInterestCalculator.paidInterest(
                product: product,
                entries: [first, reversed, reversal, future, other],
                asOf: Date(timeIntervalSince1970: 400)
            ),
            1.25,
            accuracy: 1e-9
        )
    }

    func testMonthlyPayoutStaysAnchoredToProductStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let product = try EarnProduct(
            name: "Monthly", asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 5, interestMode: .simple, term: .flexible,
            payoutFrequency: .monthly, startsAt: start
        )
        let after = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!

        XCTAssertEqual(
            product.nextPayout(after: after, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 16))
        )
    }

    func testMonthlyPayoutDoesNotDriftAfterShortFebruary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let product = try EarnProduct(
            name: "Month end", asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 5, interestMode: .simple, term: .flexible,
            payoutFrequency: .monthly, startsAt: start
        )
        let afterFebruary = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        XCTAssertEqual(
            product.nextPayout(after: afterFebruary, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 16))
        )
    }

    func testScheduledRateDoesNotRewriteEarlierPeriods() throws {
        let start = Date(timeIntervalSince1970: 0)
        var product = try EarnProduct(
            name: "Rate history", asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 5, interestMode: .simple, term: .flexible,
            payoutFrequency: .monthly, startsAt: start
        )
        try product.scheduleAnnualRate(8, effectiveAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(product.annualRate(at: Date(timeIntervalSince1970: 99)), 5)
        XCTAssertEqual(product.annualRate(at: Date(timeIntervalSince1970: 100)), 8)
    }

    func testAccruedInterestStartsAfterLastRecordedPayout() throws {
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            id: "earn", name: "Earn", asset: usd, annualRatePercent: 36.5,
            interestMode: .simple, term: .flexible, payoutFrequency: .daily,
            startsAt: start
        )
        let opening = try LedgerEntry.openingBalance(
            asset: usd, quantity: 100, account: .earn(productID: product.id),
            occurredAt: start, legacyHoldingID: "legacy", id: "opening"
        )
        let payoutDate = Date(timeIntervalSince1970: 10 * 86_400)
        let payout = try LedgerEntry.interestPayout(product: product, quantity: 1, occurredAt: payoutDate, id: "payout")

        let accrued = try EarnInterestCalculator.accruedInterest(
            product: product, entries: [opening, payout],
            asOf: Date(timeIntervalSince1970: 20 * 86_400)
        )

        XCTAssertEqual(accrued, 1, accuracy: 1e-9)
    }

    func testReversedSubscriptionDoesNotAccrueInterest() throws {
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            id: "earn", name: "Earn", asset: usd, annualRatePercent: 36.5,
            interestMode: .simple, term: .flexible, payoutFrequency: .daily,
            startsAt: start
        )
        let funding = try LedgerEntry.deposit(
            asset: usd, quantity: 100, occurredAt: start, id: "funding"
        )
        let subscription = try LedgerEntry.earnSubscribe(
            product: product, quantity: 100,
            occurredAt: Date(timeIntervalSince1970: 1), id: "subscription"
        )
        let reversal = try LedgerEntry.reversal(
            of: subscription,
            occurredAt: Date(timeIntervalSince1970: 2), id: "reversal"
        )

        let accrued = try EarnInterestCalculator.accruedInterest(
            product: product,
            entries: [funding, subscription, reversal],
            asOf: Date(timeIntervalSince1970: 10 * 86_400)
        )

        XCTAssertEqual(accrued, 0, accuracy: 1e-9)
    }

    func testReversedPayoutDoesNotResetAccrualPeriod() throws {
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            id: "earn", name: "Earn", asset: usd, annualRatePercent: 36.5,
            interestMode: .simple, term: .flexible, payoutFrequency: .daily,
            startsAt: start
        )
        let opening = try LedgerEntry.openingBalance(
            asset: usd, quantity: 100, account: .earn(productID: product.id),
            occurredAt: start, legacyHoldingID: "legacy", id: "opening"
        )
        let payout = try LedgerEntry.interestPayout(
            product: product, quantity: 1,
            occurredAt: Date(timeIntervalSince1970: 5 * 86_400), id: "payout"
        )
        let reversal = try LedgerEntry.reversal(
            of: payout,
            occurredAt: Date(timeIntervalSince1970: 6 * 86_400), id: "reversal"
        )

        let accrued = try EarnInterestCalculator.accruedInterest(
            product: product,
            entries: [opening, payout, reversal],
            asOf: Date(timeIntervalSince1970: 10 * 86_400)
        )

        XCTAssertEqual(accrued, 1, accuracy: 1e-9)
    }

    func testInterestStopsAccruingAtMaturity() throws {
        let usd = LedgerAsset(code: "USD", kind: .fiat)
        let start = Date(timeIntervalSince1970: 0)
        let maturity = Date(timeIntervalSince1970: 10 * 86_400)
        let product = try EarnProduct(
            id: "fixed", name: "Fixed", asset: usd, annualRatePercent: 36.5,
            interestMode: .simple, term: .fixed, payoutFrequency: .atMaturity,
            startsAt: start, maturesAt: maturity
        )
        let opening = try LedgerEntry.openingBalance(
            asset: usd, quantity: 100, account: .earn(productID: product.id),
            occurredAt: start, legacyHoldingID: "legacy", id: "opening"
        )

        let accrued = try EarnInterestCalculator.accruedInterest(
            product: product,
            entries: [opening],
            asOf: Date(timeIntervalSince1970: 20 * 86_400)
        )

        XCTAssertEqual(accrued, 1, accuracy: 1e-9)
    }
}

/// 用户 2026-09-06 确认的申购起息规则：提交即锁资，但每笔申购只在
/// 16:00 前对应的当日 16:00，或 16:00 及之后对应的次日 16:00 起息。
final class EarnSubscriptionEffectiveDateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0,
        nanosecond: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: day,
            hour: hour,
            minute: minute,
            second: second,
            nanosecond: nanosecond
        ))!
    }

    private func product() throws -> EarnProduct {
        try EarnProduct(
            id: "effective-date",
            name: "USDT Flexible",
            asset: LedgerAsset(code: "USDT", kind: .stablecoin),
            annualRatePercent: 365,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: date(day: 1, hour: 0)
        )
    }

    func testSubmissionImmediatelyBeforeFourPMStartsAtFourPMTheSameDay() {
        let submittedAt = date(day: 5, hour: 15, minute: 59, second: 59, nanosecond: 999_000_000)
        XCTAssertEqual(
            EarnProduct.subscriptionEffectiveDate(for: submittedAt, calendar: calendar),
            date(day: 5, hour: 16)
        )
    }

    func testSubmissionExactlyAtFourPMStartsAtFourPMTheNextDay() {
        XCTAssertEqual(
            EarnProduct.subscriptionEffectiveDate(for: date(day: 5, hour: 16), calendar: calendar),
            date(day: 6, hour: 16)
        )
    }

    func testSubmissionAfterFourPMStartsAtFourPMTheNextDay() {
        let submittedAt = date(day: 5, hour: 16, nanosecond: 1_000_000)
        XCTAssertEqual(
            EarnProduct.subscriptionEffectiveDate(for: submittedAt, calendar: calendar),
            date(day: 6, hour: 16)
        )
    }

    func testInterestAccruesAfterEffectiveDateButPayoutWaitsForFullCycle() throws {
        let product = try product()
        let submittedAt = date(day: 5, hour: 15, minute: 59, second: 59)
        let opening = try LedgerEntry.deposit(
            asset: product.asset,
            quantity: 100,
            occurredAt: date(day: 5, hour: 10),
            id: "opening-before-cutoff"
        )
        let subscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: submittedAt,
            id: "subscription-before-cutoff"
        )
        let beforeFirstPayout = date(day: 6, hour: 15, minute: 59, second: 59)

        XCTAssertGreaterThan(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: [opening, subscription],
                asOf: beforeFirstPayout,
                calendar: calendar
            ),
            0
        )
        XCTAssertEqual(
            EarnInterestCalculator.nextPayoutDate(
                product: product,
                entries: [opening, subscription],
                asOf: beforeFirstPayout,
                calendar: calendar
            ),
            date(day: 6, hour: 16)
        )
    }

    func testFundsAreLockedImmediatelyButDoNotEarnBeforeEffectiveDate() throws {
        let product = try product()
        let opening = try LedgerEntry.deposit(
            asset: product.asset,
            quantity: 100,
            occurredAt: date(day: 5, hour: 10),
            id: "opening"
        )
        let subscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: date(day: 5, hour: 16),
            id: "subscription"
        )
        let entries = [opening, subscription]
        let projection = try LedgerProjection(entries: entries)

        XCTAssertEqual(projection.balance(in: .fiat("exchange"), asset: product.asset), 0, accuracy: 1e-9)
        XCTAssertEqual(projection.balance(in: .earn(productID: product.id), asset: product.asset), 100, accuracy: 1e-9)
        XCTAssertEqual(
            EarnInterestCalculator.interestBearingPrincipal(
                product: product,
                entries: entries,
                asOf: date(day: 6, hour: 15, minute: 59, second: 59),
                calendar: calendar
            ),
            0,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: entries,
                asOf: date(day: 6, hour: 15, minute: 59, second: 59),
                calendar: calendar
            ),
            0,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            EarnInterestCalculator.interestBearingPrincipal(
                product: product,
                entries: entries,
                asOf: date(day: 6, hour: 16),
                calendar: calendar
            ),
            100,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: entries,
                asOf: date(day: 6, hour: 16),
                calendar: calendar
            ),
            0,
            accuracy: 1e-9
        )
    }

    func testInterestUsesOnlyTimeAfterEffectiveDate() throws {
        let product = try product()
        let opening = try LedgerEntry.deposit(
            asset: product.asset,
            quantity: 100,
            occurredAt: date(day: 5, hour: 10),
            id: "opening"
        )
        let subscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: date(day: 5, hour: 16),
            id: "subscription"
        )

        XCTAssertEqual(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: [opening, subscription],
                asOf: date(day: 7, hour: 16),
                calendar: calendar
            ),
            1,
            accuracy: 0.000_001
        )
    }

    func testAdditionalSubscriptionsUseIndependentEffectiveDates() throws {
        let product = try product()
        let opening = try LedgerEntry.deposit(
            asset: product.asset,
            quantity: 200,
            occurredAt: date(day: 5, hour: 10),
            id: "opening"
        )
        let sameDay = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: date(day: 5, hour: 15),
            id: "same-day"
        )
        let nextDay = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: date(day: 5, hour: 17),
            id: "next-day"
        )

        XCTAssertEqual(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: [opening, sameDay, nextDay],
                asOf: date(day: 7, hour: 16),
                calendar: calendar
            ),
            3,
            accuracy: 0.000_001
        )
    }

    func testReversingPendingSubscriptionPreventsAllFutureInterest() throws {
        let product = try product()
        let opening = try LedgerEntry.deposit(
            asset: product.asset,
            quantity: 100,
            occurredAt: date(day: 5, hour: 10),
            id: "opening"
        )
        let subscription = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 100,
            occurredAt: date(day: 5, hour: 17),
            id: "subscription"
        )
        let reversal = try LedgerEntry.reversal(
            of: subscription,
            occurredAt: date(day: 5, hour: 18),
            id: "reversal"
        )

        XCTAssertEqual(
            try EarnInterestCalculator.accruedInterest(
                product: product,
                entries: [opening, subscription, reversal],
                asOf: date(day: 8, hour: 16),
                calendar: calendar
            ),
            0,
            accuracy: 1e-9
        )
    }
}

/// 申购弹层「<频率> Profits」那行的估算（设计 `158:17628`）。
final class EarnProjectedPayoutTests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testDailyPayoutProjectsOneDayOfInterest() throws {
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            name: "USD Flexible",
            asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 365,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: start
        )
        let projected = try XCTUnwrap(
            EarnInterestCalculator.projectedPayout(
                product: product,
                principal: 1_000,
                asOf: start,
                calendar: utcCalendar()
            )
        )
        // 年化 365%、一天正好是 1/365 年，所以每期恰好是本金的 1%。
        XCTAssertEqual(projected, 10, accuracy: 0.000_001)
    }

    /// 月付的周期长度必须来自 `nextPayout`，不能按固定 30 天算——
    /// 1 月 31 日起息的产品，第一期是 31 天而不是 30 天。
    func testMonthlyPayoutUsesCalendarMonthNotThirtyDays() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let product = try EarnProduct(
            name: "USD Monthly",
            asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 365,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .monthly,
            startsAt: start
        )
        let projected = try XCTUnwrap(
            EarnInterestCalculator.projectedPayout(
                product: product,
                principal: 1_000,
                asOf: start,
                calendar: calendar
            )
        )
        XCTAssertEqual(projected, 310, accuracy: 0.000_001)
    }

    func testNonPositivePrincipalHasNoProjection() throws {
        let product = try EarnProduct(
            name: "USD Flexible",
            asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertNil(
            EarnInterestCalculator.projectedPayout(
                product: product,
                principal: 0,
                asOf: Date(timeIntervalSince1970: 0),
                calendar: utcCalendar()
            )
        )
    }

    func testAtMaturityProjectsWholeTerm() throws {
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            name: "USDT Fixed",
            asset: LedgerAsset(code: "USDT", kind: .stablecoin),
            annualRatePercent: 365,
            interestMode: .simple,
            term: .fixed,
            payoutFrequency: .atMaturity,
            startsAt: start,
            maturesAt: start.addingTimeInterval(10 * 86_400)
        )
        let projected = try XCTUnwrap(
            EarnInterestCalculator.projectedPayout(
                product: product,
                principal: 1_000,
                asOf: start,
                calendar: utcCalendar()
            )
        )
        XCTAssertEqual(projected, 100, accuracy: 0.000_001)
    }
}

/// 用户 2026-09-05 定的资金规则：手续费由金额×费率算、三种 Earn 均可下架，
/// 定期只能全额赎回。
final class LedgerTradeAndEarnRuleTests: XCTestCase {
    func testTradesDefaultToUSDTSettlement() {
        XCTAssertEqual(LedgerEntry.defaultSettlementCode, "USDT")
        XCTAssertTrue(LedgerEntry.allowedSettlementCodes.contains(LedgerEntry.defaultSettlementCode))
    }

    func testFeeIsGrossValueTimesRate() {
        let fee = LedgerTradeDetails.feeAmount(grossValue: 10_000, ratePercent: 0.06)
        XCTAssertEqual(try XCTUnwrap(fee), 6, accuracy: 0.000_001)
    }

    func testZeroRateHasNoFee() {
        XCTAssertEqual(try XCTUnwrap(LedgerTradeDetails.feeAmount(grossValue: 10_000, ratePercent: 0)), 0)
    }

    func testNegativeRateIsRejected() {
        XCTAssertNil(LedgerTradeDetails.feeAmount(grossValue: 10_000, ratePercent: -1))
    }

    private func product(term: EarnProductTerm) throws -> EarnProduct {
        let start = Date(timeIntervalSince1970: 0)
        return try EarnProduct(
            name: "USD \(term.rawValue)",
            asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 5,
            interestMode: .simple,
            term: term,
            payoutFrequency: term == .fixed ? .atMaturity : .daily,
            startsAt: start,
            maturesAt: term == .flexible ? nil : start.addingTimeInterval(90 * 86_400),
            structuredParameters: term == .structured ? "Strike 830,000 USD" : nil
        )
    }

    func testAllActiveProductsCanDelist() throws {
        XCTAssertTrue(try product(term: .structured).canDelist)
        XCTAssertTrue(try product(term: .fixed).canDelist)
        XCTAssertTrue(try product(term: .flexible).canDelist)

        var delisted = try product(term: .flexible)
        delisted.delistedAt = Date(timeIntervalSince1970: 1)
        XCTAssertFalse(delisted.canDelist)
    }

    /// 设计 `158:17375` / `158:16698` 的注释：定期和结构化「不能加仓，只能单独申购」，
    /// 所以只有活期的明细页有 Subscribe More。
    func testOnlyFlexibleProductsAllowAdditionalSubscription() throws {
        XCTAssertTrue(try product(term: .flexible).allowsAdditionalSubscription)
        XCTAssertFalse(try product(term: .fixed).allowsAdditionalSubscription)
        XCTAssertFalse(try product(term: .structured).allowsAdditionalSubscription)
    }

    /// 「定期赎回没有收益」；活期和结构化「赎回不影响已产生的利息」。
    func testOnlyFixedProductsForfeitInterestOnEarlyRedemption() throws {
        XCTAssertTrue(try product(term: .fixed).forfeitsInterestOnEarlyRedemption)
        XCTAssertFalse(try product(term: .flexible).forfeitsInterestOnEarlyRedemption)
        XCTAssertFalse(try product(term: .structured).forfeitsInterestOnEarlyRedemption)
    }

    /// 定期是用户 2026-09-05 定的；结构化见设计 `155:13496` 的注释
    /// 「结构化理财只能全部赎回全部金额」。只有活期能部分赎回。
    func testOnlyFlexibleProductsAllowPartialRedemption() throws {
        XCTAssertTrue(try product(term: .fixed).redeemsFullAmountOnly)
        XCTAssertTrue(try product(term: .structured).redeemsFullAmountOnly)
        XCTAssertFalse(try product(term: .flexible).redeemsFullAmountOnly)
    }

    /// Holding 页汇总条的 Daily：一天的利息 = 本金 × APY / 365，
    /// 和派息周期无关（周付产品的一天不等于一期）。
    func testDailyInterestIsIndependentOfThePayoutCycle() throws {
        let weekly = try EarnProduct(
            name: "USD Weekly",
            asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 36.5,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .weekly,
            startsAt: Date(timeIntervalSince1970: 0)
        )
        let daily = EarnInterestCalculator.dailyInterest(
            product: weekly,
            principal: 1_000,
            asOf: Date(timeIntervalSince1970: 0)
        )
        // 36.5% / 365 = 0.1% 一天，1000 × 0.1% = 1
        XCTAssertEqual(daily, 1, accuracy: 0.000_001)
    }

    /// 下架标记是可选字段，第一版 schema-v3 写下的快照（没有这个 key）必须仍能解码。
    func testSnapshotWithoutDelistedAtStillDecodes() throws {
        let json = """
        {"id":"p1","name":"USD Flexible Term","asset":{"code":"USD","kind":"fiat"},
         "annualRatePercent":5,"interestMode":"simple","term":"flexible",
         "payoutFrequency":"daily","startsAt":"1970-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EarnProduct.self, from: Data(json.utf8))
        XCTAssertNil(decoded.delistedAt)
        XCTAssertFalse(decoded.isDelisted)
    }
}

/// 固定票息的行权价 / 敲出价（设计 `155:15940` / `155:16010`）。
final class EarnStructuredPriceTests: XCTestCase {
    func testStructuredProductCarriesStrikeAndKnockOutPrices() throws {
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            name: "USD 固定票息",
            asset: LedgerAsset(code: "USD", kind: .fiat),
            annualRatePercent: 15.56,
            interestMode: .simple,
            term: .structured,
            payoutFrequency: .weekly,
            startsAt: start,
            maturesAt: start.addingTimeInterval(90 * 86_400),
            strikePrice: 830_000,
            knockOutPrice: 2_368.23
        )
        XCTAssertEqual(try XCTUnwrap(product.strikePrice), 830_000)
        XCTAssertEqual(try XCTUnwrap(product.knockOutPrice), 2_368.23)
    }

    /// 两个价格是后加的可选字段，没有它们的旧快照必须照常解码——
    /// 仓库在 load 时会对每个产品跑 `validate()`，这里退化了会让整个账本读不出来。
    func testSnapshotWithoutStructuredPricesStillDecodesAndValidates() throws {
        let json = """
        {"id":"p1","name":"USD 固定票息","asset":{"code":"USD","kind":"fiat"},
         "annualRatePercent":15.56,"interestMode":"simple","term":"structured",
         "payoutFrequency":"weekly","startsAt":"1970-01-01T00:00:00Z",
         "maturesAt":"1970-04-01T00:00:00Z","structuredParameters":"Strike 830,000 USD"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EarnProduct.self, from: Data(json.utf8))
        XCTAssertNil(decoded.strikePrice)
        XCTAssertNil(decoded.knockOutPrice)
        XCTAssertEqual(decoded.structuredParameters, "Strike 830,000 USD")
        XCTAssertNoThrow(try decoded.validate())
    }
}

/// 用户 2026-09-05 定的口径：**申购什么资产，利息就是什么资产**。
/// 所以理财只管 APY，不管币价——币价只影响本金和利息折成法币后的估值，
/// 不参与利息本身的计算。这一组测试就是把这条钉死。
final class EarnInterestIsDenominatedInProductAssetTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// Crypto 的申购来源是 Trading 账户，先给它开个仓，
    /// 否则投影会因为「禁止负余额」直接拒掉申购。
    private func openingBTC(_ quantity: Double, at date: Date) throws -> LedgerEntry {
        try LedgerEntry.openingBalance(
            asset: LedgerAsset(code: "BTC", kind: .cryptocurrency),
            quantity: quantity,
            account: .trading,
            occurredAt: date,
            legacyHoldingID: "seed-btc",
            id: "seed-btc"
        )
    }

    private func bitcoinFlexible() throws -> EarnProduct {
        try EarnProduct(
            name: "BTC Flexible",
            asset: LedgerAsset(code: "BTC", kind: .cryptocurrency),
            annualRatePercent: 10,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 派息流水的 posting 必须记在产品资产上，不能记成 USD。
    func testInterestPayoutIsPostedInTheProductAsset() throws {
        let product = try bitcoinFlexible()
        let entry = try LedgerEntry.interestPayout(
            product: product,
            quantity: 0.2,
            occurredAt: Date(timeIntervalSince1970: 86_400)
        )
        XCTAssertFalse(entry.postings.isEmpty)
        for posting in entry.postings {
            XCTAssertEqual(posting.asset, product.asset, "利息不能换成别的资产计价")
        }
        // 单利：利息进来源账户，也就是 Crypto 的 Trading 账户。
        let credited = entry.postings.first { $0.quantity > 0 }
        XCTAssertEqual(try XCTUnwrap(credited).account, .trading)
    }

    /// 2 BTC 按 10% 放满一年 = 0.2 BTC，和当时 BTC 值多少钱无关。
    func testAccruedInterestIsAQuantityInTheProductAssetAndIgnoresPrice() throws {
        let product = try bitcoinFlexible()
        let start = Date(timeIntervalSince1970: 0)
        let seed = try openingBTC(2, at: start.addingTimeInterval(-2 * 86_400))
        let subscribe = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 2,
            occurredAt: start.addingTimeInterval(-33 * 60 * 60)
        )
        let oneYear = start.addingTimeInterval(365 * 24 * 60 * 60)
        let accrued = try EarnInterestCalculator.accruedInterest(
            product: product,
            entries: [seed, subscribe],
            asOf: oneYear,
            calendar: utcCalendar
        )
        XCTAssertEqual(accrued, 0.2, accuracy: 0.000_001)
    }

    /// 同一份持仓，无论行情如何，计算器都拿不到价格——签名里就没有这个入参。
    /// 这条断言的是「一年的利息 = 本金 × APY」，任何把币价掺进来的改动都会让它红。
    func testInterestDoesNotScaleWithAnyPrice() throws {
        let product = try bitcoinFlexible()
        let start = Date(timeIntervalSince1970: 0)
        let seed = try openingBTC(2, at: start.addingTimeInterval(-2 * 86_400))
        let subscribe = try LedgerEntry.earnSubscribe(
            product: product,
            quantity: 2,
            occurredAt: start.addingTimeInterval(-33 * 60 * 60)
        )
        let half = try EarnInterestCalculator.accruedInterest(
            product: product,
            entries: [seed, subscribe],
            asOf: start.addingTimeInterval(365 * 24 * 60 * 60 / 2),
            calendar: utcCalendar
        )
        XCTAssertEqual(half, 0.1, accuracy: 0.000_001)
    }
}

/// 用户 2026-09-05 补充：理财产品本身不专门展示价格，**但价格波动必须体现在总资产上**。
/// Earn 账户和 Trading 一样是 user-controlled，所以本金要按行情计价进总额。
final class EarnPrincipalIsValuedAtMarketTests: XCTestCase {
    private func btcInEarn() throws -> (product: EarnProduct, entries: [LedgerEntry]) {
        let start = Date(timeIntervalSince1970: 0)
        let product = try EarnProduct(
            name: "BTC Flexible",
            asset: LedgerAsset(code: "BTC", kind: .cryptocurrency),
            annualRatePercent: 10,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: .daily,
            startsAt: start
        )
        let seed = try LedgerEntry.openingBalance(
            asset: LedgerAsset(code: "BTC", kind: .cryptocurrency),
            quantity: 2,
            account: .trading,
            occurredAt: start.addingTimeInterval(-86_400),
            legacyHoldingID: "seed-btc",
            id: "seed-btc"
        )
        let subscribe = try LedgerEntry.earnSubscribe(product: product, quantity: 2, occurredAt: start)
        return (product, [seed, subscribe])
    }

    private func quote(_ price: Double) -> [String: MarketQuote] {
        // Crypto 的行情键是 `<code>-USD`（见 `LedgerAsset.marketQuoteSymbol`）。
        [
            "BTC-USD": MarketQuote(
                symbol: "BTC-USD",
                currency: "USD",
                price: price,
                changePercent: 0,
                series: [MarketPricePoint(timestampMilliseconds: 0, price: price)],
                marketTimeMilliseconds: nil,
                fetchedAtMilliseconds: 0
            )
        ]
    }

    /// 放在 Earn 里的 BTC 也要参与报价请求，否则总资产会因为缺行情而算不出来。
    func testEarnBalanceIsIncludedInRequiredQuotes() throws {
        let (_, entries) = try btcInEarn()
        let projection = try LedgerProjection(entries: entries)
        XCTAssertTrue(LedgerValuation.requiredQuoteSymbols(for: projection).contains("BTC-USD"))
    }

    /// 拿不到行情时不能伪造总额（`HANDOFF.md` 里承诺过的性质）。
    func testMissingQuoteLeavesTheTotalUnknown() throws {
        let (_, entries) = try btcInEarn()
        let projection = try LedgerProjection(entries: entries)
        let summary = LedgerValuation.summary(
            entries: entries, projection: projection,
            quotes: [:], exchangeRates: nil
        )
        XCTAssertNil(summary.totalValueUSD)
        XCTAssertTrue(summary.missingAssetCodes.contains("BTC"))
    }

    /// 币价翻倍，总资产跟着翻倍——利息不参与，这里没有派息流水。
    func testTotalValueFollowsThePriceOfAssetsHeldInEarn() throws {
        let (_, entries) = try btcInEarn()
        let projection = try LedgerProjection(entries: entries)
        let cheap = LedgerValuation.summary(
            entries: entries, projection: projection,
            quotes: quote(50_000), exchangeRates: nil
        )
        let rich = LedgerValuation.summary(
            entries: entries, projection: projection,
            quotes: quote(100_000), exchangeRates: nil
        )
        XCTAssertEqual(try XCTUnwrap(cheap.totalValueUSD), 100_000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(rich.totalValueUSD), 200_000, accuracy: 0.01)
    }
}

/// 用户 2026-09-05：「派息时间要固定下午四点」。设计 `155:16083` 把钟点直接写进了
/// 选项文案（`16:00 , Daily` / `16:00 Friday, Weekly`），明细页的 `Next Time Payout`
/// 也一律是 16:00。此前派息点继承 `startsAt` 的时分，每建一个产品都落在不同钟点。
final class EarnPayoutIsAnchoredToFourPMTests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func product(
        _ frequency: EarnPayoutFrequency,
        startsAt: Date,
        maturesAt: Date? = nil
    ) throws -> EarnProduct {
        try EarnProduct(
            name: "Anchored",
            asset: LedgerAsset(code: "USDT", kind: .stablecoin),
            annualRatePercent: 365,
            interestMode: .simple,
            term: .flexible,
            payoutFrequency: frequency,
            startsAt: startsAt,
            maturesAt: maturesAt
        )
    }

    /// 16:00 前申购：当天 16:00 起息，完整经过一天后，次日 16:00 才首次派息。
    func testDailyPayoutRequiresAFullDayAfterSameDayEffectiveDate() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026, month: 9, day: 5, hour: 15, minute: 59, second: 59
            ))
        )
        let payout = try product(.daily, startsAt: start)

        XCTAssertEqual(
            payout.nextPayout(after: start, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 16))
        )
    }

    /// 16:00 整及之后申购：次日 16:00 起息，再隔一天才首次派息。
    func testDailyPayoutStartsTomorrowAndPaysTheDayAfter() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 16))
        )
        let payout = try product(.daily, startsAt: start)

        XCTAssertEqual(
            payout.nextPayout(after: start, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 16))
        )
    }

    /// 周付钉在周五 16:00（设计 `155:16083`），不是「起息日 + 7 天」。
    /// 2026-09-05 是周六；完整经过一周后，再落到下一个周五 16:00。
    func testWeeklyPayoutRequiresAFullCycleBeforeFridayPayout() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))
        )
        let payout = try product(.weekly, startsAt: start)
        let next = try XCTUnwrap(payout.nextPayout(after: start, calendar: calendar))

        XCTAssertEqual(calendar.component(.weekday, from: next), EarnProduct.weeklyPayoutWeekday)
        XCTAssertEqual(
            next,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))
        )
    }

    func testMonthlyPayoutRequiresAFullCalendarMonth() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))
        )
        let payout = try product(.monthly, startsAt: start)

        XCTAssertEqual(
            payout.nextPayout(after: start, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 16))
        )
    }

    /// Hourly 在下一个整点起息，再到下下个整点满一小时才首次派息。
    func testHourlyPayoutRequiresAFullHourAfterTheEffectiveBoundary() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 37))
        )
        let payout = try product(.hourly, startsAt: start)

        XCTAssertEqual(
            payout.nextPayout(after: start, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 11))
        )
    }

    func testHourlySubmissionExactlyOnTheHourStillStartsAtTheNextHour() throws {
        let calendar = utcCalendar()
        let submittedAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))
        )
        let payout = try product(.hourly, startsAt: submittedAt)

        XCTAssertEqual(
            payout.subscriptionEffectiveDate(for: submittedAt, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))
        )
        XCTAssertEqual(
            payout.firstPayoutDate(forSubscriptionAt: submittedAt, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 11))
        )
    }

    /// 每期收益量的是「一次派息到下一次派息」，始终是完整周期。
    func testProjectedPayoutMeasuresAFullCycleNotTheTruncatedFirstOne() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))
        )
        let payout = try product(.daily, startsAt: start)
        let projected = try XCTUnwrap(
            EarnInterestCalculator.projectedPayout(
                product: payout, principal: 1_000, asOf: start, calendar: calendar
            )
        )
        // 年化 365%，整整一天就是本金的 1%。
        XCTAssertEqual(projected, 10, accuracy: 0.000_001)
    }

    /// 申购时刻的分秒不该影响派息点：同一天 16:00 前建的两个日付产品，
    /// 第一次派息落在同一个时间。
    func testStartTimeOfDayDoesNotLeakIntoThePayoutClock() throws {
        let calendar = utcCalendar()
        let morning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 2, minute: 3, second: 4))
        )
        let noon = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12, minute: 45, second: 59))
        )

        XCTAssertEqual(
            try product(.daily, startsAt: morning).nextPayout(after: morning, calendar: calendar),
            try product(.daily, startsAt: noon).nextPayout(after: noon, calendar: calendar)
        )
    }
}
