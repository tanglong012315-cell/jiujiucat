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

    /// 按回车或点「搜索」时立即搜，不走 350ms 防抖。
    func search() async {
        await performSearch(debounced: false)
    }

    func searchAfterDelay() async {
        await performSearch(debounced: true)
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
        } catch is CancellationError {
            return
        } catch {
            let fallback = AssetSearchResult.offlineMatches(for: normalized)
            state = fallback.isEmpty ? .failed : .results(fallback, offline: true)
        }
    }
}

/// Web 的标的搜索弹层（`#asset-search-overlay`）。右上角是「取消」文字按钮而不是 ×，
/// 内容区靠 `state-art` 插画承载空/错状态。
struct AssetSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: AssetSearchViewModel
    @FocusState private var isQueryFocused: Bool

    let onSelect: (AssetSearchResult) -> Void

    init(
        initialQuery: String,
        onSelect: @escaping (AssetSearchResult) -> Void
    ) {
        _model = StateObject(wrappedValue: AssetSearchViewModel(initialQuery: initialQuery))
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(PawTheme.ink10)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ZStack {
                Text("搜索标的代码")
                    .font(PawFont.inter(17, weight: .semibold))
                    .foregroundStyle(PawTheme.ink)

                HStack {
                    Spacer()

                    Button("取消") { dismiss() }
                        .font(PawFont.inter(14, weight: .medium))
                        .foregroundStyle(PawTheme.ink)
                        .frame(height: 44)
                        .buttonStyle(PawPressableButtonStyle())
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 20)

            VStack(spacing: 16) {
                searchField

                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(PawTheme.bg1)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(26)
        .presentationBackground(PawTheme.bg1)
        .task(id: model.query) { await model.searchAfterDelay() }
        .onAppear { isQueryFocused = true }
    }

    /// Web `.asset-search-input-shell`：48 高，左侧放大镜，右侧一颗黑色「搜索」。
    private var searchField: some View {
        HStack(spacing: 10) {
            Image("IconSearch")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(PawTheme.ink40)

            TextField("例如 AAPL、BTC", text: $model.query)
                .font(PawFont.inter(15))
                .foregroundStyle(PawTheme.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isQueryFocused)
                .onSubmit { Task { await model.search() } }

            Button {
                isQueryFocused = false
                Task { await model.search() }
            } label: {
                Text("搜索")
                    .font(PawFont.inter(13, weight: .semibold))
                    .foregroundStyle(PawTheme.bg1)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(PawTheme.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PawPressableButtonStyle())
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(PawTheme.ink4, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .suggestions:
            VStack(spacing: 0) {
                stateBlock(
                    art: "ArtSearch",
                    title: "输入代码或名称，按回车开始搜索",
                    detail: "支持 Yahoo Finance 上的股票、ETF 和 Crypto"
                )

                resultList(
                    AssetSearchResult.offlineFallbacks.filter { ["VOO", "AAPL", "BTC"].contains($0.symbol) }
                )
            }

        case .loading:
            stateBlock(art: "ArtLoading", title: "正在搜索 Yahoo Finance…", detail: nil)

        case .results(let results, let offline):
            VStack(alignment: .leading, spacing: 0) {
                if offline {
                    Text("网络搜索暂不可用，当前显示内置常用标的。")
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink40)
                        .padding(.bottom, 8)
                }

                resultList(results)
            }

        case .empty:
            VStack(spacing: 0) {
                stateBlock(
                    art: "ArtNotFound",
                    title: "没有找到「\(model.query)」",
                    detail: "换个代码或名称再试，也可以在下面手动使用这个代码"
                )
                manualEntry
            }

        case .failed:
            VStack(spacing: 0) {
                stateBlock(
                    art: "ArtNetFail",
                    title: "暂时无法搜索",
                    detail: "可以稍后重试，或在下面手动使用有效的 Yahoo 代码"
                )
                manualEntry
            }
        }
    }

    /// Web `.asset-search-state`：插画 + 一句主文案 + 一句说明。
    private func stateBlock(art: String, title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(art)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(title)
                .font(PawFont.inter(14, weight: .semibold))
                .foregroundStyle(PawTheme.ink)
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(PawFont.inter(12))
                    .foregroundStyle(PawTheme.ink40)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    @ViewBuilder
    private var manualEntry: some View {
        if let manualAsset = model.manualAsset {
            Button {
                select(manualAsset)
            } label: {
                HStack(spacing: 12) {
                    Text("手动使用 \(manualAsset.quoteSymbol)")
                        .font(PawFont.inter(14, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)

                    Spacer(minLength: 0)

                    Image("IconArrowRightS")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(PawTheme.ink40)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(PawTheme.ink4, in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous))
            }
            .buttonStyle(PawPressableButtonStyle())
            .padding(.top, 8)
        }
    }

    /// Web `.asset-result`：64 高，行间发丝线，最后一行不留线。
    private func resultList(_ results: [AssetSearchResult]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, asset in
                Button {
                    select(asset)
                } label: {
                    HStack(spacing: 12) {
                        PawAssetLogo(
                            quoteSymbol: asset.quoteSymbol,
                            assetType: asset.assetType,
                            name: asset.name,
                            fallbackText: String(asset.symbol.prefix(2)),
                            diameter: 40
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.name)
                                .font(PawFont.inter(14, weight: .medium))
                                .foregroundStyle(PawTheme.ink)
                                .lineLimit(1)

                            Text(
                                [asset.assetType.title, asset.exchange]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · ")
                            )
                            .font(PawFont.inter(12))
                            .foregroundStyle(PawTheme.ink40)
                            .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(asset.symbol)
                            .font(PawFont.inter(13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PawTheme.ink40)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PawPressableButtonStyle())
                .accessibilityLabel("选择 \(asset.symbol)，\(asset.name)")

                if index < results.count - 1 {
                    PawDivider()
                }
            }
        }
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

