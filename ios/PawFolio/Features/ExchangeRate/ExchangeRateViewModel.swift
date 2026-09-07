import Combine
import Foundation

@MainActor
final class ExchangeRateViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready(isCached: Bool)
        case failed(message: String)
    }

    /// 用户自己攒的那一列货币，可增可删可排序。
    @Published private(set) var currencies: [CurrencyCode]
    @Published private(set) var amountTexts: [CurrencyCode: String]
    @Published private(set) var baseCurrency: CurrencyCode
    @Published private(set) var snapshot: ExchangeRateSnapshot?
    @Published private(set) var loadState = LoadState.idle

    /// 已经聚焦、但还没有真正输入的币种。它继续显示现有换算值，只把数字降成
    /// Text Secondary；第一个数字会整体替换旧值，退格则一次清空。
    @Published private(set) var pendingCurrency: CurrencyCode?

    /// TextField 编辑器内部的原始文本可能晚一拍才接受 Binding 回写。单独记住它，按
    /// 输入增量更新界面值，避免首次覆盖/清空后又被旧的编辑器内容顶回来。
    private var keyboardTexts: [CurrencyCode: String] = [:]

    /// 在途的刷新。首屏的 `.task` 和下拉刷新可以同时发生，第二个调用者并进同一个
    /// 任务而不是再打一次接口——否则两次结果的写入顺序不定，慢的那个会把快的覆盖掉。
    private var refreshTask: Task<Void, Never>?

    private let client: any ExchangeRateServing
    private let store: any ExchangeRatePreferencesStoring

    init(
        client: any ExchangeRateServing = LiveExchangeRateClient(),
        store: any ExchangeRatePreferencesStoring = UserDefaultsPreferencesStore()
    ) {
        self.client = client
        self.store = store

        // 表里没有的代码直接丢掉：币种表是写死的，下架过的代码留着只会渲染成空行。
        let restored = (store.loadSelection() ?? []).filter(CurrencyCatalog.contains)
        let selection = restored.isEmpty ? CurrencyCatalog.defaultSelection : restored
        currencies = selection
        baseCurrency = selection.first ?? .cny
        pendingCurrency = nil
        amountTexts = Dictionary(
            uniqueKeysWithValues: selection.enumerated().map { index, code in
                (code, index == 0 ? "100" : "")
            }
        )
    }

    var updatedAt: Date? {
        snapshot?.fetchedAt
    }

    /// 「添加货币」页要排除已经在列表里的。
    var availableCurrencies: [CurrencyInfo] {
        let taken = Set(currencies)
        return CurrencyCatalog.all.filter { !taken.contains($0.code) }
    }

    func text(for currency: CurrencyCode) -> String {
        amountTexts[currency, default: ""]
    }

    func placeholder(for currency: CurrencyCode) -> String {
        "0"
    }

    func isAwaitingInput(_ currency: CurrencyCode) -> Bool {
        pendingCurrency == currency
    }

    func hasRate(for currency: CurrencyCode) -> Bool {
        snapshot?.hasRate(for: currency) ?? false
    }

    // MARK: - 编辑

    func beginEditing(_ currency: CurrencyCode) {
        keyboardTexts.removeAll()
        keyboardTexts[currency] = amountTexts[currency, default: ""]
        pendingCurrency = currency == baseCurrency ? nil : currency
    }

    func updateAmountText(_ text: String, for currency: CurrencyCode) {
        let currentText = amountTexts[currency, default: ""]
        // TextField 在获得焦点时会先回写一次相同内容；不能把这个框架回调当成输入。
        if text == currentText {
            keyboardTexts[currency] = text
            return
        }
        let keyboardBaseline = keyboardTexts[currency] ?? currentText
        guard text != keyboardBaseline else { return }
        keyboardTexts[currency] = text

        if pendingCurrency == currency {
            // decimalPad 的退格会先交来一个比旧文本少一位的字符串。等待态下不逐位删，
            // 第一次退格直接清空，但仍保持等待态；下一次数字输入才正式切换基准币种。
            if text.isEmpty
                || (keyboardBaseline.count - text.count == 1 && keyboardBaseline.hasPrefix(text)) {
                amountTexts[currency] = ""
                return
            }

            pendingCurrency = nil
            baseCurrency = currency
            amountTexts[currency] = Self.applyingInputChange(
                from: keyboardBaseline,
                to: text,
                currentValue: ""
            )
        } else {
            if baseCurrency != currency {
                baseCurrency = currency
            }
            amountTexts[currency] = Self.applyingInputChange(
                from: keyboardBaseline,
                to: text,
                currentValue: currentText
            )
        }
        synchronizeConvertedAmounts(preserving: currency)
    }

    func finishEditing(_ currency: CurrencyCode) {
        keyboardTexts.removeAll()
        if pendingCurrency == currency {
            pendingCurrency = nil
            return
        }

        guard currency == baseCurrency else { return }

        guard let value = parsedAmount(for: currency) else { return }
        amountTexts[currency] = Self.formattedAmount(value)
        synchronizeConvertedAmounts(preserving: currency)
    }

    /// 副标题：基准行是货币全名，其余行是「单位汇率 + 货币全名」，例如
    /// `0.1484 US Dollar`。**不带 `1 CNY =` 前缀**——基准是哪一行，看数字颜色就知道
    /// （用户 2026-09-03 的要求）。
    func subtitle(for currency: CurrencyCode, locale: Locale = Locale(identifier: "en")) -> String {
        let name = currency.localizedDisplayName(locale: locale)
        guard currency != baseCurrency else { return name }
        guard let rate = snapshot?.converted(1, from: baseCurrency, to: currency) else {
            return "Rate unavailable"
        }
        return rate.formatted(.number.grouping(.never).precision(.fractionLength(4)))
            + " \(name)"
    }

    // MARK: - 增删排序

    func add(_ currency: CurrencyCode) {
        guard CurrencyCatalog.contains(currency), !currencies.contains(currency) else { return }
        currencies.append(currency)
        amountTexts[currency] = ""
        saveSelection()
        synchronizeConvertedAmounts(preserving: baseCurrency)
    }

    func remove(_ currency: CurrencyCode) {
        guard currencies.count > 1, let index = currencies.firstIndex(of: currency) else { return }
        currencies.remove(at: index)
        amountTexts.removeValue(forKey: currency)
        if pendingCurrency == currency {
            pendingCurrency = nil
        }
        keyboardTexts.removeValue(forKey: currency)

        // 删掉的正是当前基准：把第一行顶上来，它的数字原样保留，其余行跟着它重算。
        if baseCurrency == currency, let next = currencies.first {
            baseCurrency = next
            synchronizeConvertedAmounts(preserving: next)
        }
        saveSelection()
    }

    /// 收手时把拖动预览提交成一次有目标下标的移动。
    func move(_ currency: CurrencyCode, to destination: Int) {
        guard let index = currencies.firstIndex(of: currency),
              currencies.indices.contains(destination),
              index != destination else {
            return
        }
        currencies.remove(at: index)
        currencies.insert(currency, at: destination)
        saveSelection()
    }

    // MARK: - 取数

    func loadIfNeeded() async {
        guard loadState == .idle else { return }

        if let cached = loadCache() {
            snapshot = cached
            loadState = .ready(isCached: true)
            synchronizeConvertedAmounts(preserving: baseCurrency)
        }

        await refresh()
    }

    func refresh() async {
        if let inFlight = refreshTask {
            await inFlight.value
            return
        }

        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        if snapshot == nil {
            loadState = .loading
        }

        do {
            let latest = try await client.latestRates()
            snapshot = latest
            saveCache(latest)
            loadState = .ready(isCached: false)
            synchronizeConvertedAmounts(preserving: baseCurrency)
        } catch {
            if snapshot != nil {
                loadState = .ready(isCached: true)
            } else {
                loadState = .failed(
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "Unable to fetch the latest exchange rates."
                )
            }
        }
    }

    private func synchronizeConvertedAmounts(preserving source: CurrencyCode) {
        guard let snapshot, let sourceAmount = parsedAmount(for: source) else {
            for currency in currencies where currency != source && currency != pendingCurrency {
                amountTexts[currency] = ""
            }
            return
        }

        for currency in currencies where currency != source && currency != pendingCurrency {
            guard let converted = snapshot.converted(sourceAmount, from: source, to: currency) else {
                amountTexts[currency] = ""
                continue
            }
            amountTexts[currency] = Self.formattedAmount(converted)
        }
    }

    /// 汇率页比别处严：`inf` 和负数都当没填。金额本身的归一化交给 `AmountInput`。
    private func parsedAmount(for currency: CurrencyCode) -> Double? {
        guard let value = AmountInput.parse(text(for: currency)),
              value.isFinite,
              value >= 0 else {
            return nil
        }
        return value
    }

    private static func formattedAmount(_ amount: Double) -> String {
        amount.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...2))
        )
    }

    /// SwiftUI 的 `TextField` 在光标末尾输入时会给出「旧值 + 新字符」。等待态需要的
    /// 是替换语义，所以只提取新增部分；直接粘贴/全选替换时则采用完整的新文本。
    private static func applyingInputChange(
        from keyboardText: String,
        to proposed: String,
        currentValue: String
    ) -> String {
        if proposed.hasPrefix(keyboardText) {
            return currentValue + String(proposed.dropFirst(keyboardText.count))
        }
        if keyboardText.hasPrefix(proposed) {
            let removedCount = keyboardText.count - proposed.count
            return String(currentValue.dropLast(min(removedCount, currentValue.count)))
        }
        return proposed
    }

    private func saveSelection() {
        store.save(selection: currencies)
    }

    private func loadCache() -> ExchangeRateSnapshot? {
        store.loadSnapshot()
    }

    private func saveCache(_ snapshot: ExchangeRateSnapshot) {
        store.save(snapshot: snapshot)
    }
}
