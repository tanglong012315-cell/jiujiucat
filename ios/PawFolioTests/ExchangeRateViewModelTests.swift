import XCTest
@testable import PawFolio

/// 这一组在 SPM 里跑不了：`ExchangeRateViewModel` 在 `Features/`、
/// `ExchangeRateServing` 在 `Data/ExchangeRateClient.swift`，两者都不在
/// `PawFolioDomain` 这个 package 的 target 里。跟 `AccountViewModelTests`
/// 一样，只由 Xcode 的测试 bundle 编译。
@MainActor
final class ExchangeRateViewModelTests: XCTestCase {
    private struct StubClient: ExchangeRateServing {
        let snapshot: ExchangeRateSnapshot
        /// 数一数接口真的被打了几次。并发刷新只该打一次。
        let calls: Counter?

        init(snapshot: ExchangeRateSnapshot, calls: Counter? = nil) {
            self.snapshot = snapshot
            self.calls = calls
        }

        func latestRates() async throws -> ExchangeRateSnapshot {
            await calls?.increment()
            // 让两个调用者有机会真的重叠上，否则第二个进来时第一个已经结束了。
            try? await Task.sleep(nanoseconds: 20_000_000)
            return snapshot
        }
    }

    private actor Counter {
        private(set) var count = 0

        func increment() { count += 1 }
    }

    private func makeModel(
        defaults: UserDefaults
    ) -> ExchangeRateViewModel {
        ExchangeRateViewModel(
            client: StubClient(
                snapshot: ExchangeRateSnapshot(
                    base: .usd,
                    ratesPerUSD: [.usd: 1, .cny: 7.2, .thb: 36, .myr: 4.5, "JPY": 150],
                    fetchedAt: Date(timeIntervalSince1970: 0)
                )
            ),
            store: UserDefaultsPreferencesStore(defaults: defaults)
        )
    }

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "pawfolio.tests.\(name)")!
        defaults.removePersistentDomain(forName: "pawfolio.tests.\(name)")
        return defaults
    }

    /// 首屏加载和下拉刷新可以同时发生。两个调用者必须并进同一次请求：不然两份
    /// 结果的写入顺序不定，慢的那份会把快的覆盖掉，界面上就是数字回退。
    func testConcurrentRefreshesShareOneRequest() async {
        let counter = Counter()
        let model = ExchangeRateViewModel(
            client: StubClient(
                snapshot: ExchangeRateSnapshot(
                    base: .usd,
                    ratesPerUSD: [.usd: 1, .cny: 7.2, .thb: 36, .myr: 4.5],
                    fetchedAt: Date(timeIntervalSince1970: 0)
                ),
                calls: counter
            ),
            store: UserDefaultsPreferencesStore(defaults: makeDefaults())
        )

        async let first: Void = model.refresh()
        async let second: Void = model.refresh()
        async let third: Void = model.refresh()
        _ = await (first, second, third)

        let count = await counter.count
        XCTAssertEqual(count, 1)
        XCTAssertNotNil(model.snapshot)

        // 合流器用完要归位，之后还得能再刷一次。
        await model.refresh()
        let afterSecondRound = await counter.count
        XCTAssertEqual(afterSecondRound, 2)
    }

    func testAddedCurrencySurvivesARelaunch() {
        let defaults = makeDefaults()

        let first = makeModel(defaults: defaults)
        first.add("JPY")
        XCTAssertEqual(first.currencies.last, "JPY")

        let second = makeModel(defaults: defaults)
        XCTAssertEqual(second.currencies, CurrencyCatalog.defaultSelection + ["JPY"])
    }

    func testReorderSurvivesARelaunch() {
        let defaults = makeDefaults()

        let first = makeModel(defaults: defaults)
        first.move(.thb, to: 0)

        let second = makeModel(defaults: defaults)
        XCTAssertEqual(second.currencies.first, .thb)
    }

    // 删掉的正好是基准行时，基准要顶给第一行，否则整页都算不出数。
    func testRemovingTheBaseCurrencyPromotesTheFirstRow() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        XCTAssertEqual(model.baseCurrency, .cny)
        model.remove(.cny)

        XCTAssertFalse(model.currencies.contains(.cny))
        XCTAssertEqual(model.baseCurrency, model.currencies.first)
    }

    func testLastCurrencyCannotBeRemoved() {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)

        for code in CurrencyCatalog.defaultSelection.dropFirst() {
            model.remove(code)
        }
        let survivor = model.currencies
        model.remove(survivor[0])

        XCTAssertEqual(model.currencies, survivor)
    }

    // 点进另一行：保留现有数字并进入灰色等待态，基准与其余换算都不变。
    func testFocusingAnotherRowKeepsItsAmountWhileAwaitingInput() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        let usdBefore = model.text(for: .usd)
        let thbBefore = model.text(for: .thb)

        model.beginEditing(.usd)

        XCTAssertEqual(model.text(for: .usd), usdBefore)
        XCTAssertTrue(model.isAwaitingInput(.usd))
        XCTAssertEqual(model.baseCurrency, .cny)
        XCTAssertEqual(model.text(for: .thb), thbBefore)
    }

    func testLeavingAWaitingRowWithoutTypingChangesNothing() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        let usdBefore = model.text(for: .usd)
        model.beginEditing(.usd)
        model.finishEditing(.usd)

        XCTAssertEqual(model.text(for: .usd), usdBefore)
        XCTAssertFalse(model.isAwaitingInput(.usd))
        XCTAssertEqual(model.baseCurrency, .cny)
    }

    func testFocusEchoDoesNotActivateAWaitingRow() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        model.beginEditing(.usd)
        let oldUSD = model.text(for: .usd)
        model.updateAmountText(oldUSD, for: .usd)

        XCTAssertEqual(model.text(for: .usd), oldUSD)
        XCTAssertTrue(model.isAwaitingInput(.usd))
        XCTAssertEqual(model.baseCurrency, .cny)
    }

    func testFocusPreparationEchoBeforeBeginDoesNotSwitchTheBase() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        let oldUSD = model.text(for: .usd)
        model.updateAmountText(oldUSD, for: .usd)
        model.beginEditing(.usd)

        XCTAssertEqual(model.text(for: .usd), oldUSD)
        XCTAssertTrue(model.isAwaitingInput(.usd))
        XCTAssertEqual(model.baseCurrency, .cny)
    }

    func testSubtitleShowsTheUnitRateAndTheFullCurrencyName() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        XCTAssertEqual(model.subtitle(for: .cny), "Chinese Yuan")
        XCTAssertEqual(model.subtitle(for: .usd), "0.1389 US Dollar")
    }

    func testFirstTypedDigitReplacesWaitingValueAndDrivesTheOthers() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        model.beginEditing(.usd)
        let oldUSD = model.text(for: .usd)
        let textFieldProposal = oldUSD + "1"
        model.updateAmountText(textFieldProposal, for: .usd)
        model.updateAmountText(textFieldProposal, for: .usd) // SwiftUI binding echo

        XCTAssertEqual(model.baseCurrency, .usd)
        XCTAssertEqual(model.text(for: .usd), "1")
        XCTAssertEqual(model.text(for: .cny), "7.2")
        XCTAssertFalse(model.isAwaitingInput(.usd))
    }

    func testFirstBackspaceClearsTheWholeWaitingValueWithoutActivatingIt() async {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        await model.loadIfNeeded()

        model.beginEditing(.usd)
        let oldUSD = model.text(for: .usd)
        let textFieldProposal = String(oldUSD.dropLast())
        model.updateAmountText(textFieldProposal, for: .usd)
        model.updateAmountText(textFieldProposal, for: .usd) // SwiftUI binding echo

        XCTAssertEqual(model.text(for: .usd), "")
        XCTAssertTrue(model.isAwaitingInput(.usd))
        XCTAssertEqual(model.baseCurrency, .cny)

        model.updateAmountText(textFieldProposal + "5", for: .usd)

        XCTAssertEqual(model.text(for: .usd), "5")
        XCTAssertFalse(model.isAwaitingInput(.usd))
        XCTAssertEqual(model.baseCurrency, .usd)
    }
}
