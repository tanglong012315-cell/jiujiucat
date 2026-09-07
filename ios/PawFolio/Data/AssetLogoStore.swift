import Foundation
import UIKit

/// 资产 logo 的解析与缓存。四处共用（行情条、快捷添加、持仓行、搜索结果），
/// 对应 Web 的 `applyAssetLogo`。
///
/// 解析顺序由 `AssetLogoCandidates` 给出，这里只负责按序试、记住结果、给回图片。
/// logo 不在关键路径上：任何一步失败都安静退回首字母。
@MainActor
final class AssetLogoStore: ObservableObject {
    static let shared = AssetLogoStore()

    private enum Cached {
        case image(UIImage)
        /// 所有候选都试过且都没有，别再重试。
        case unavailable
    }

    private let configuration: APIConfiguration
    private let session: URLSession

    private var entries: [String: Cached] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var index: CryptoLogoIndex = .empty
    private var indexTask: Task<Void, Never>?

    init(configuration: APIConfiguration = .production, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        index = Self.loadCachedIndex() ?? .empty
    }

    // MARK: CMC 映射表

    private static let indexCacheKey = "pawfolio.crypto-logo-index"
    private static let indexTTL: TimeInterval = 24 * 60 * 60

    private struct CachedIndex: Codable {
        let savedAt: Date
        let index: CryptoLogoIndex
    }

    private static func loadCachedIndex() -> CryptoLogoIndex? {
        guard let data = UserDefaults.standard.data(forKey: indexCacheKey),
              let cached = try? JSONDecoder().decode(CachedIndex.self, from: data),
              Date().timeIntervalSince(cached.savedAt) < indexTTL else {
            return nil
        }
        return cached.index
    }

    /// 拉一次市值前 1000 的 `{代码: CMC ID}` 表，缓存一天。拿不到就继续用兜底源。
    func loadIndexIfNeeded() {
        guard indexTask == nil, Self.loadCachedIndex() == nil else { return }

        indexTask = Task { [weak self] in
            guard let self else { return }

            // `?v=2` 是给边缘缓存换的键，返回结构变过一次。以后再改结构记得递增。
            guard let url = URL(string: "api/crypto-logos?v=2", relativeTo: configuration.baseURL) else {
                return
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(CryptoLogoIndex.self, from: data),
                  !decoded.ids.isEmpty else {
                return
            }

            await MainActor.run {
                self.index = decoded
                if let encoded = try? JSONEncoder().encode(
                    CachedIndex(savedAt: Date(), index: decoded)
                ) {
                    UserDefaults.standard.set(encoded, forKey: Self.indexCacheKey)
                }
                // 表通常比首屏晚到：清掉已经落到兜底源的结果，让界面换上 CMC 的图。
                self.entries.removeAll()
                self.objectWillChange.send()
            }
        }
    }

    // MARK: 解析

    private func cacheKey(quoteSymbol: String, assetType: AssetType) -> String {
        "\(assetType.rawValue)|\(quoteSymbol.uppercased())"
    }

    func cachedImage(for quoteSymbol: String, assetType: AssetType) -> UIImage? {
        let key = cacheKey(quoteSymbol: quoteSymbol, assetType: assetType)
        if case .image(let image) = entries[key] { return image }
        return nil
    }

    func isUnavailable(_ quoteSymbol: String, assetType: AssetType) -> Bool {
        let key = cacheKey(quoteSymbol: quoteSymbol, assetType: assetType)
        if case .unavailable = entries[key] { return true }
        return false
    }

    func image(quoteSymbol: String, assetType: AssetType, name: String) async -> UIImage? {
        guard !quoteSymbol.isEmpty else { return nil }
        let key = cacheKey(quoteSymbol: quoteSymbol, assetType: assetType)

        if let cached = entries[key] {
            switch cached {
            case .image(let image): return image
            case .unavailable: return nil
            }
        }

        if let existing = inFlight[key] { return await existing.value }

        // 市值 Top 100 随 App 安装，优先于任何网络源。这样常见标的首次出现时
        // 不闪占位、不依赖网络，也不会消耗 CMC / Parqet 的请求额度。
        if let assetName = AssetLogoCatalog.assetName(
            quoteSymbol: quoteSymbol,
            assetType: assetType,
            name: name
        ), let bundled = UIImage(named: assetName) {
            entries[key] = .image(bundled)
            return bundled
        }

        let candidates = AssetLogoCandidates.candidates(
            quoteSymbol: quoteSymbol,
            assetType: assetType,
            name: name,
            index: index
        )
        guard !candidates.isEmpty else {
            entries[key] = .unavailable
            return nil
        }

        let task = Task<UIImage?, Never> { [session] in
            for url in candidates {
                guard let (data, response) = try? await session.data(from: url),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    continue
                }
                return image
            }
            return nil
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        entries[key] = image.map(Cached.image) ?? .unavailable
        return image
    }
}
