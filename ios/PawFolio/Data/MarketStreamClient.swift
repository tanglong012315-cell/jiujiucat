import Foundation
import os

/// 一条实时报价。价格已经换算成美元。
struct MarketStreamTick: Sendable, Equatable {
    /// App 内部代号（BTC），不是交易对（BTCUSDT）。
    let symbol: String
    let priceUSD: Double
    let receivedAtMilliseconds: TimeInterval
}

/// 加密货币实时行情 —— Binance 现货公开 WebSocket。
///
/// 为什么只有加密：加密 7×24 连续成交且交易所提供公开行情流，推送是天然选择。
/// 美股有交易时段，而且 Binance Stocks 没有公开的行情流，只能轮询 —— 那条路
/// 已经在 `MarketQuoteRepository` 里，一次请求覆盖所有持仓，不需要也不可能改成推送。
///
/// 这一层只负责「把最新价推出来」，不碰估值和缓存。调用方拿到 tick 后自己决定
/// 怎么合并进已有的报价。
///
/// 行为与 Web 的 `public/market-stream.js` 同构，包括那几个踩过的坑：
/// - 连接静默超时要主动断开重连。切后台回来时 `state` 常常还是 `.running`，
///   但实际早就不通了，光等回调是等不到的。
/// - 重连退避必须带抖动，否则一次上游抖动会让所有客户端在同一毫秒重连。
/// - Binance 单条连接只活 24 小时，到点服务端主动断。这是设计，不是故障。
actor MarketStreamClient {
    private static let log = Logger(
        subsystem: "com.jiujiucat.pawfolio",
        category: "market-stream"
    )

    private static let endpoint = URL(string: "wss://stream.binance.com:9443/ws")!
    /// 静默超过这么久就当连接已死。Binance 会定期发 ping frame，
    /// URLSessionWebSocketTask 自动回 pong，所以正常情况下不会这么久没消息。
    private static let staleInterval: TimeInterval = 30
    private static let maxBackoff: TimeInterval = 30

    private let session: URLSession
    private let catalogCache: MarketCatalogCache
    private let catalogLoader: @Sendable () async -> MarketCatalog

    private var task: URLSessionWebSocketTask?
    // Gate.io 单独一套连接：订阅消息和推送结构都和 Binance 不同，
    // 塞进同一套 if/else 只会让两边都难读。
    private var gateTask: URLSessionWebSocketTask?
    private var gatePairs: [String: String] = [:]   // 交易对 → App 代号
    private var gateReceive: Task<Void, Never>?
    private var gateRetry = 0
    private var subscribed: [String: String] = [:]   // 交易对 → App 代号
    private var quoteCurrencies: [String: String] = [:] // App 代号 → 计价货币
    private var usdtPerUSD: Double = 1
    private var retryCount = 0
    private var lastMessageAt = Date()
    private var receiveTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var isRunning = false
    private var continuation: AsyncStream<MarketStreamTick>.Continuation?

    init(
        session: URLSession = .shared,
        catalogCache: MarketCatalogCache = .shared,
        catalogLoader: @escaping @Sendable () async -> MarketCatalog = {
            await MarketCatalogCache.shared.catalog {
                let url = APIConfiguration.production.baseURL.appendingPathComponent("api/catalog")
                let (data, _) = try await URLSession.shared.data(from: url)
                return try MarketDataPayloadDecoder.catalog(from: data)
            }
        }
    ) {
        self.session = session
        self.catalogCache = catalogCache
        self.catalogLoader = catalogLoader
    }

    /// 取 tick 流。**只应该调用一次** —— 每次调用都会新建一条流，
    /// 上一条会被结束掉，正在 `for await` 的循环随之退出。
    /// 加订阅走 `subscribe(symbols:)`，那条路不碰流。
    func ticks() -> AsyncStream<MarketStreamTick> {
        continuation?.finish()
        var captured: AsyncStream<MarketStreamTick>.Continuation?
        let stream = AsyncStream<MarketStreamTick>(bufferingPolicy: .bufferingNewest(64)) { cont in
            captured = cont
        }
        continuation = captured
        return stream
    }

    /// 订阅这些代号。重复调用是安全且廉价的：已经订过的不会重复订阅，
    /// 也不会打断正在接收的连接 —— 持仓一变就会调一次，必须是幂等的。
    ///
    /// 只有加密会真的被订阅 —— 美股和法币直接忽略，调用方不必自己过滤。
    func subscribe(symbols: Set<String>) async {
        let catalog = await catalogLoader()
        var newPairs: [String] = []
        var newGatePairs: [String] = []
        for symbol in symbols {
            // 每个场所有自己的订阅集，放错的后果不是报错而是**安静地收不到推送**
            //   美股（Binance Stocks）没有公开行情流。
            //   CMC 只有 REST 报价，也没有流。
            //   Gate 有流，但协议不同，要走 gatePairs 那条路。
            // 2026-09-07 真机上就是这么暴露的：长尾币的对进了 Binance 的集合，
            // 订了一个不存在的流，价格永远停在首次取到的值。
            guard let instrument = catalog.resolve(symbol: symbol),
                  !instrument.isEquity,
                  instrument.venue != "cmc",
                  let pair = instrument.pair else { continue }
            if instrument.venue == "gate" {
                quoteCurrencies[instrument.symbol] = instrument.quoteCurrency
                if gatePairs[pair] == nil {
                    gatePairs[pair] = instrument.symbol
                    newGatePairs.append(pair)
                }
                continue
            }
            quoteCurrencies[instrument.symbol] = instrument.quoteCurrency
            guard subscribed[pair] == nil else { continue }
            subscribed[pair] = instrument.symbol
            newPairs.append(pair)
        }
        // USDT 计价的标的要乘 USDT/USD 才是美元价，所以 USDT 自己也得订上 ——
        // 否则那个汇率永远停在初始的 1，价格会一直差着 0.0x%。
        if quoteCurrencies.values.contains("USDT"),
           subscribed["USDTUSD"] == nil,
           let usdt = catalog.resolve(symbol: "USDT", assetType: .cryptocurrency),
           let pair = usdt.pair {
            subscribed[pair] = "USDT"
            quoteCurrencies["USDT"] = usdt.quoteCurrency
            newPairs.append(pair)
        }
        guard !newPairs.isEmpty else { return }

        isRunning = true
        if !newGatePairs.isEmpty {
            if gateTask == nil { connectGate() } else { sendGate(subscribe: newGatePairs) }
        }
        guard !newPairs.isEmpty else { return }
        if task == nil {
            connect()
        } else {
            send(subscribeMessage(for: newPairs))
        }
    }

    // MARK: - Gate.io

    /// 为什么值得单独接一套：OKB 这类币 Binance 根本不上架（不上架任何竞争对手的
    /// 平台币），而 OKX 在部分网络下 DNS 解析不出来。Gate 实测可达、有 K 线，
    /// 而且 WebSocket 是干净的 JSON。
    private func connectGate() {
        guard isRunning, !gatePairs.isEmpty else { return }
        gateReceive?.cancel()
        gateTask?.cancel(with: .goingAway, reason: nil)
        guard let url = URL(string: MarketEndpoints.gateWebSocket) else { return }
        let socket = session.webSocketTask(with: url)
        gateTask = socket
        socket.resume()
        sendGate(subscribe: Array(gatePairs.keys))
        gateReceive = Task { [weak self] in await self?.gateLoop(on: socket) }
    }

    private func sendGate(subscribe pairs: [String]) {
        guard !pairs.isEmpty else { return }
        let payload = pairs.map { "\"\($0)\"" }.joined(separator: ",")
        let message = "{\"time\":\(Int(Date().timeIntervalSince1970))," +
            "\"channel\":\"spot.tickers\",\"event\":\"subscribe\",\"payload\":[\(payload)]}"
        gateTask?.send(.string(message)) { error in
            if let error {
                Self.log.debug("gate subscribe failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func gateLoop(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                gateRetry = 0
                handleGate(message)
            } catch {
                guard !Task.isCancelled else { return }
                gateTask = nil
                guard isRunning else { return }
                // 指数退避 + 抖动，和 Binance 那条一致。
                let backoff = min(pow(2, Double(gateRetry)), Self.maxBackoff) + Double.random(in: 0...1)
                gateRetry += 1
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    await self?.connectGate()
                }
                return
            }
        }
    }

    private struct GateTicker: Decodable {
        struct Result: Decodable {
            let currency_pair: String?
            let last: String?
        }
        let channel: String?
        let event: String?
        let result: Result?
    }

    private func handleGate(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text): data = text.data(using: .utf8)
        case .data(let raw): data = raw
        @unknown default: data = nil
        }
        guard let data,
              let payload = try? JSONDecoder().decode(GateTicker.self, from: data),
              payload.channel == "spot.tickers", payload.event == "update",
              let pair = payload.result?.currency_pair,
              let symbol = gatePairs[pair],
              let price = payload.result?.last.flatMap(Double.init),
              price > 0 else { return }
        // Gate 的对都是 USDT 计价，换算成美元和 Binance 那条一致。
        let rate = quoteCurrencies[symbol] == "USDT" ? usdtPerUSD : 1
        continuation?.yield(MarketStreamTick(
            symbol: symbol,
            priceUSD: price * rate,
            receivedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        ))
    }

    func stop() {
        isRunning = false
        gateReceive?.cancel()
        gateReceive = nil
        gateTask?.cancel(with: .goingAway, reason: nil)
        gateTask = nil
        teardownConnection()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - 连接

    private func connect() {
        guard isRunning, !subscribed.isEmpty else { return }
        teardownConnection()

        let socket = session.webSocketTask(with: Self.endpoint)
        task = socket
        lastMessageAt = Date()
        socket.resume()
        send(subscribeMessage(for: Array(subscribed.keys)))

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(on: socket)
        }
        watchdogTask = Task { [weak self] in
            await self?.watchdogLoop()
        }
    }

    private func teardownConnection() {
        receiveTask?.cancel()
        receiveTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func scheduleReconnect() {
        guard isRunning else { return }
        // 指数退避 + 抖动。不加抖动的话，一次上游抖动会让所有客户端在同一毫秒
        // 重连，反而把上游打死。
        let backoff = min(pow(2, Double(retryCount)), Self.maxBackoff)
        let jitter = Double.random(in: 0...1)
        retryCount += 1
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((backoff + jitter) * 1_000_000_000))
            await self?.reconnectIfNeeded()
        }
    }

    private func reconnectIfNeeded() {
        guard isRunning, task == nil else { return }
        connect()
    }

    private func receiveLoop(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                lastMessageAt = Date()
                retryCount = 0
                handle(message)
            } catch {
                guard !Task.isCancelled else { return }
                // 连接断了。24 小时强制断开是 Binance 的设计，不是故障，
                // 所以这里不记 error 级别的日志，直接重连。
                Self.log.debug("stream closed: \(String(describing: error), privacy: .public)")
                task = nil
                scheduleReconnect()
                return
            }
        }
    }

    private func watchdogLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled, isRunning else { return }
            guard Date().timeIntervalSince(lastMessageAt) > Self.staleInterval else { continue }
            // 静默太久：`task.state` 可能还写着 running，但连接实际上已经死了 ——
            // 手机切后台再回来时尤其常见。主动断开，走统一的重连路径。
            Self.log.debug("stream stale, forcing reconnect")
            teardownConnection()
            scheduleReconnect()
            return
        }
    }

    // MARK: - 消息

    private func subscribeMessage(for pairs: [String]) -> String {
        // @ticker 每 1000ms 一条，含最新价和 24h 统计。不用 @trade：逐笔一秒
        // 几十条，全是前端消化不掉也用不上的噪音。
        let params = pairs.map { "\"\($0.lowercased())@ticker\"" }.joined(separator: ",")
        return "{\"method\":\"SUBSCRIBE\",\"params\":[\(params)],\"id\":\(Int(Date().timeIntervalSince1970))}"
    }

    private func send(_ text: String) {
        task?.send(.string(text)) { error in
            if let error {
                Self.log.debug("subscribe failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text): data = text.data(using: .utf8)
        case .data(let raw): data = raw
        @unknown default: data = nil
        }
        guard let data, let tick = Self.decodeTicker(from: data) else { return }
        guard let symbol = subscribed[tick.pair] else { return }

        if symbol == "USDT" { usdtPerUSD = tick.price }
        // 涨跌幅不在这里算：分子分母同乘一个数比值不变，换算只会把 USDT 自己的
        // 抖动混成标的的涨跌。调用方用「上一次完整报价隐含的基准」重算。
        let rate = quoteCurrencies[symbol] == "USDT" ? usdtPerUSD : 1
        continuation?.yield(MarketStreamTick(
            symbol: symbol,
            priceUSD: tick.price * rate,
            receivedAtMilliseconds: Date().timeIntervalSince1970 * 1_000
        ))
    }

    private struct TickerPayload: Decodable {
        let e: String?
        let s: String?
        let c: String?
    }

    private static func decodeTicker(from data: Data) -> (pair: String, price: Double)? {
        guard let payload = try? JSONDecoder().decode(TickerPayload.self, from: data),
              payload.e == "24hrTicker",
              let pair = payload.s,
              let price = payload.c.flatMap(Double.init),
              price.isFinite,
              price > 0 else { return nil }
        return (pair, price)
    }
}
