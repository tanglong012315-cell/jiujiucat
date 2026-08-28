import Combine
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

    private let client: any MarketDataServing

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
            exchange: "手动"
        )
    }

    func searchAfterDelay() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            state = .suggestions
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            state = .loading
            let results = try await client.search(query: normalized)
            try Task.checkCancellation()
            state = results.isEmpty ? .empty : .results(results, offline: false)
        } catch is CancellationError {
            return
        } catch {
            let fallback = AssetSearchResult.offlineMatches(for: normalized)
            state = fallback.isEmpty ? .failed : .results(fallback, offline: true)
        }
    }
}

struct AssetSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AssetSearchViewModel

    let onSelect: (AssetSearchResult) -> Void

    init(
        initialQuery: String,
        onSelect: @escaping (AssetSearchResult) -> Void
    ) {
        _model = StateObject(wrappedValue: AssetSearchViewModel(initialQuery: initialQuery))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                content

                if let manualAsset = model.manualAsset {
                    Section {
                        Button {
                            select(manualAsset)
                        } label: {
                            Label("手动使用 \(manualAsset.quoteSymbol)", systemImage: "square.and.pencil")
                        }
                    } footer: {
                        Text("仅在 Yahoo 搜索没有目标时使用；保存前仍可修改资产类别。")
                    }
                }
            }
            .navigationTitle("搜索标的")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "代码或名称，例如 AAPL、BTC"
            )
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task(id: model.query) {
                await model.searchAfterDelay()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .suggestions:
            Section("常用标的") {
                ForEach(AssetSearchResult.offlineFallbacks.filter { ["VOO", "AAPL", "BTC"].contains($0.symbol) }) { asset in
                    resultButton(asset)
                }
            }

        case .loading:
            HStack {
                Spacer()
                ProgressView("正在搜索 Yahoo Finance…")
                Spacer()
            }
            .frame(minHeight: 180)

        case .results(let results, let offline):
            Section {
                ForEach(results) { asset in
                    resultButton(asset)
                }
            } header: {
                Text(offline ? "离线常用结果" : "搜索结果")
            } footer: {
                if offline {
                    Text("网络搜索暂不可用，当前显示内置常用标的。")
                }
            }

        case .empty:
            ContentUnavailableView.search(text: model.query)
                .listRowBackground(Color.clear)

        case .failed:
            ContentUnavailableView(
                "暂时无法搜索",
                systemImage: "wifi.exclamationmark",
                description: Text("可以稍后重试，或在下方手动使用有效的 Yahoo 代码。")
            )
            .listRowBackground(Color.clear)
        }
    }

    private func resultButton(_ asset: AssetSearchResult) -> some View {
        Button {
            select(asset)
        } label: {
            HStack(spacing: 12) {
                Text(String(asset.symbol.prefix(2)))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PawTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(PawTheme.quietBlue, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text([asset.assetType.title, asset.exchange].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(asset.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PawTheme.accent)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择 \(asset.symbol)，\(asset.name)")
    }

    private func select(_ asset: AssetSearchResult) {
        onSelect(asset)
        dismiss()
    }
}

extension AssetType {
    var title: String {
        switch self {
        case .equity: "股票"
        case .etf: "ETF"
        case .cryptocurrency: "加密货币"
        case .stable: "稳定资产"
        }
    }
}

