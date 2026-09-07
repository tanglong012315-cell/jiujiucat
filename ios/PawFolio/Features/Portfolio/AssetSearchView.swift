import Combine
import Nvwa
import SwiftUI

@MainActor
final class AssetSearchViewModel: ObservableObject {
    enum State: Equatable {
        case suggestions
        case loading
        case results([AssetSearchResult], offline: Bool)
        case empty
        case failed
    }

    @Published var query: String
    @Published private(set) var state: State = .suggestions
    /// Figma 的结果行右侧带现价和涨跌幅，而 `AssetSearchResult` 只有标的信息。
    /// 报价按行单独取，取不到就让那一行留空，不阻塞列表本身。
    @Published private(set) var quotes: [String: MarketQuote] = [:]

    private let client: any MarketDataServing
    private var quoteTask: Task<Void, Never>?

    init(
        initialQuery: String = "",
        client: any MarketDataServing = LiveMarketDataClient()
    ) {
        query = initialQuery
        self.client = client
    }

    var manualAsset: AssetSearchResult? {
        let symbol = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard symbol.range(of: #"^[A-Z0-9^][A-Z0-9.^=-]{0,19}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let isCrypto = symbol.hasSuffix("-USD")
        return AssetSearchResult(
            symbol: isCrypto ? String(symbol.dropLast(4)) : symbol,
            quoteSymbol: symbol,
            name: symbol,
            assetType: isCrypto ? .cryptocurrency : .equity,
            exchange: "Manual"
        )
    }

    /// 按回车或点「搜索」时立即搜，不走 350ms 防抖。
    func search() async {
        await performSearch(debounced: false)
    }

    func searchAfterDelay() async {
        await performSearch(debounced: true)
    }

    func clear() {
        query = ""
        state = .suggestions
        quoteTask?.cancel()
    }

    private func performSearch(debounced: Bool) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            state = .suggestions
            return
        }

        do {
            if debounced {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
            }
            state = .loading
            let results = try await client.search(query: normalized)
            try Task.checkCancellation()
            state = results.isEmpty ? .empty : .results(results, offline: false)
            loadQuotes(for: results)
        } catch is CancellationError {
            return
        } catch {
            let fallback = AssetSearchResult.offlineMatches(for: normalized)
            state = fallback.isEmpty ? .failed : .results(fallback, offline: true)
            loadQuotes(for: fallback)
        }
    }

    /// 只给当前这批结果取报价，换一次搜索就取消上一批。
    private func loadQuotes(for results: [AssetSearchResult]) {
        quoteTask?.cancel()
        let symbols = results.map(\.quoteSymbol).filter { quotes[$0] == nil }
        guard !symbols.isEmpty else { return }

        quoteTask = Task { [weak self, client] in
            await withTaskGroup(of: MarketQuote?.self) { group in
                for symbol in symbols {
                    group.addTask { try? await client.quote(symbol: symbol) }
                }
                for await quote in group {
                    guard !Task.isCancelled, let quote else { continue }
                    self?.quotes[quote.symbol] = quote
                }
            }
        }
    }
}

/// Figma V1.1 添加持仓的标的搜索：`43:2617`（空）、`43:2851`（有结果）、
/// `43:3053`（未找到）。三态共用 `Add Position` 弹层头和同一个搜索框，只有
/// 内容区不同。
struct AssetSearchView: View {
    @StateObject private var model: AssetSearchViewModel
    @FocusState private var isQueryFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// 把搜索结果行已经拿到的报价一起交给调用方。否则交易表单会在弹层关闭后
    /// 再发一次完全相同的请求；第二次请求偶发失败时，就会出现列表明明有价格、
    /// 选中后价格框却为空的割裂状态。
    let onSelect: (AssetSearchResult, MarketQuote?) -> Void
    private let title: LocalizedStringKey

    init(
        initialQuery: String,
        title: LocalizedStringKey = "Add Position",
        onSelect: @escaping (AssetSearchResult, MarketQuote?) -> Void
    ) {
        _model = StateObject(wrappedValue: AssetSearchViewModel(initialQuery: initialQuery))
        self.title = title
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            NvwaModalHeader(title)
                .pawSheetMeasuredPart()

            VStack(spacing: 16) {
                NvwaSearchInput(
                    placeholder: "Ex. AAPL, BTC",
                    text: $model.query,
                    searchIcon: Image("IconSearch2"),
                    clearIcon: Image("IconCloseCircleFill"),
                    focus: $isQueryFocused,
                    onClear: {
                        model.clear()
                        isQueryFocused = true
                    }
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await model.search() } }
                .pawSheetMeasuredPart()

                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pawSheetMeasuredPart()
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(16)
            .pawSheetHeightContribution(48)
        }
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
        .task(id: model.query) { await model.searchAfterDelay() }
        .onAppear { isQueryFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .suggestions:
            stateBlock(art: "ArtSearch") {
                Text("Supports Yahoo Finance stock search.")
                    .font(Nvwa.bodySmall)
                    .tracking(0.12)
                    .foregroundStyle(Nvwa.graySecondary)
            }

        case .loading:
            stateBlock {
                Text("Searching Yahoo Finance…")
                    .font(Nvwa.bodySmall)
                    .tracking(0.12)
                    .foregroundStyle(Nvwa.graySecondary)
            } art: {
                PawLoadingIndicator("Searching Yahoo Finance")
            }

        case .results(let results, let offline):
            VStack(alignment: .leading, spacing: 0) {
                if offline {
                    Text("Search is unavailable. Showing built-in symbols.")
                        .font(Nvwa.bodySmall)
                        .tracking(0.12)
                        .foregroundStyle(Nvwa.graySecondary)
                        .padding(.bottom, 8)
                }

                ForEach(results) { asset in
                    resultRow(asset)
                }
            }

        case .empty:
            notFoundBlock(art: "ArtNotFound")

        case .failed:
            notFoundBlock(art: "ArtNetFail")
        }
    }

    /// `43:2851` 的结果行：32 描边圆 logo、代码 16 Semibold 压名称 10，
    /// 右侧现价 16 Semibold 压涨跌幅 10。
    private func resultRow(_ asset: AssetSearchResult) -> some View {
        Button {
            select(asset)
        } label: {
            HStack(spacing: 12) {
                PawAssetLogo(
                    quoteSymbol: asset.quoteSymbol,
                    assetType: asset.assetType,
                    name: asset.name,
                    fallbackText: String(asset.symbol.prefix(2)),
                    diameter: 32
                )
                .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 0.5))

                // 设计改稿：两行的行距是 8，副行文字是 B-S Regular（原来是
                // C-2 Regular，偏小）。
                VStack(alignment: .leading, spacing: 8) {
                    Text(asset.symbol)
                        .font(Nvwa.bodyLarge)
                        .tracking(0.08)
                        .foregroundStyle(Nvwa.grayPrimary)
                        .lineLimit(1)

                    Text(asset.name)
                        .font(Nvwa.bodySmall)
                        .tracking(0.12)
                        .foregroundStyle(Nvwa.graySecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // 报价是异步逐行到达的，命中率很高——往往正好在手指按下那一刻
                // 送达。之前用 `if let quote = ...` 整块加进/退出这棵子树，报价
                // 一到就把 Button 的 label 结构改了：分支从"没有这个 VStack"
                // 变成"有"，UIKit 把这当作视图拓扑变化，正在识别的这次点按
                // 就被取消——摸上去像「点了没反应」，其实是被自己写的异步刷新
                // 打断的。现在这棵子树一直在，报价没到时两行文字给空字符串，
                // 结构不再随数据变化，只有内容变。
                let quote = model.quotes[asset.quoteSymbol]
                VStack(alignment: .trailing, spacing: 8) {
                    Text(quote.map(Self.priceText) ?? "")
                        .font(Nvwa.bodyLarge.monospacedDigit())
                        .tracking(0.08)
                        .foregroundStyle(Nvwa.grayPrimary)

                    Text(quote.map(Self.changeText) ?? "")
                        .font(Nvwa.bodySmall.monospacedDigit())
                        .tracking(0.12)
                        .foregroundStyle(
                            (quote?.changePercent ?? 0) < 0 ? Nvwa.marketSell : Nvwa.marketBuy
                        )
                }
                .lineLimit(1)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(NvwaPressButtonStyle())
        .accessibilityLabel("\(asset.symbol), \(asset.name)")
    }

    /// 选中即关闭。弹层自己关，而不是让每个调用方在回调里各写一遍——漏写的
    /// 表现是「点了没反应」：草稿其实已经填好了，只是搜索层还盖在上面。
    private func select(_ asset: AssetSearchResult) {
        onSelect(asset, model.quotes[asset.quoteSymbol])
        dismiss()
    }

    /// `43:3053`：未找到时仍允许沿用输入的代码建仓。
    private func notFoundBlock(art: String) -> some View {
        stateBlock(art: art) {
            Text("Not Found “\(model.query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .font(Nvwa.bodySmall)
                .tracking(0.12)
                .foregroundStyle(Nvwa.graySecondary)
                .multilineTextAlignment(.center)

            if let manualAsset = model.manualAsset {
                Button {
                    select(manualAsset)
                } label: {
                    Text("Still Use This Symbol")
                        .font(Nvwa.bodySmallSemibold)
                        .tracking(0.12)
                        .foregroundStyle(Nvwa.primaryGreen)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NvwaPressButtonStyle())
            }
        }
    }

    private func stateBlock<Caption: View>(
        art: String?,
        @ViewBuilder caption: () -> Caption
    ) -> some View {
        stateBlock(caption: caption) {
            if let art {
                Image(art)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private func stateBlock<Caption: View, Art: View>(
        @ViewBuilder caption: () -> Caption,
        @ViewBuilder art: () -> Art
    ) -> some View {
        VStack(spacing: 8) {
            art()
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)

            caption()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private static func priceText(_ quote: MarketQuote) -> String {
        let amount = quote.price.formatted(
            .number.precision(.fractionLength(0...2)).grouping(.automatic)
        )
        return "\(amount) \(quote.currency.uppercased())"
    }

    private static func changeText(_ quote: MarketQuote) -> String {
        let value = quote.changePercent.formatted(.number.precision(.fractionLength(2)))
        return quote.changePercent > 0 ? "+\(value)%" : "\(value)%"
    }
}
