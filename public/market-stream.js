/**
 * 行情数据层 —— 加密走 Binance 现货 WebSocket 推送，美股走 Binance Stocks 轮询。
 *
 * 为什么要它：原来 BTC 走 CoinGecko、股票走 Yahoo，都是 60 秒轮询。价格一分钟
 * 跳一次；CoinGecko 免费接口还按 IP 限流，人一多就随机吐 429，表现是行情条
 * 无规律地变「暂不可用」。
 *
 * 为什么两种取数方式：
 *   加密 7×24 连续成交，交易所提供公开 WebSocket，推送是天然选择。
 *   美股有交易时段，而且 Binance Stocks 没有公开的行情流，只能轮询。但它的
 *   「全量实时价」接口一次返回全部 7928 个标的，经 Worker 边缘缓存后按需裁剪
 *   —— 也就是说无论持仓有多少只股票，都只花一次请求，比原来每个标的一次还省。
 *
 * ⚠️ 用的是**真实美股**（bapi/equity，代号 EQ_VOO），不是现货那套代币化股票
 * （bStocks，代号 AAPLB）。后者是第三方发行的代币，和真实股价有 0.2~0.7% 偏差，
 * 拿来给持仓估值会把那个偏差直接变成盈亏里的误差。详见 src/index.js 顶部。
 *
 * ⛔ **所有行情都必须客户端直连交易所，不能经过 Worker。**
 * Binance 对 Cloudflare 出口 IP 返回 403（api 和 bapi 两个域名都拦），OKX 返回
 * 429。同一时刻浏览器直连全部 200 —— 它们拦的是数据中心 IP，不是地区。
 * 2026-09-07 上线时把这几个端点做成 Worker 代理，结果全线 502。
 * 目录也因此改成静态文件（见 scripts/build_catalog.py），静态资源由 Cloudflare
 * 直接分发，根本不经过 Worker。
 *
 * 加密多场所：Binance 为主，OKX 补它没有的 —— Binance 不上架任何竞争对手的
 * 平台币（OKB / CRO / LEO 都没有，只有自家 BNB）。两家都没有的就是不支持，
 * 诚实显示「暂不支持」，不编价格。OKX 的标的只轮询不推送：它们是长尾，
 * 为此再接一套 OKX 的 WebSocket 协议不值得。
 *
 * 边界：本模块只负责「取到价格」，不碰估值和渲染。失败时安静降级并让调用方
 * 看得出来（entry.live / entry.unsupported），绝不捏造价格。
 */
(function () {
  'use strict';

  const WS_URL = 'wss://stream.binance.com:9443/ws';
  const BINANCE_BASE = 'https://api.binance.com';
  const EQUITY_BASE = 'https://www.binance.com/bapi/equity/v1/public/equity';
  const SERIES_CAP = 240;
  // 连接静默超过这个时长就当它已经死了。Binance 服务端会定期发 ping frame
  // （浏览器自动回 pong，不用管），30 秒收不到任何东西必然有问题 —— 手机切
  // 后台回来时尤其常见：readyState 还是 OPEN，实际早就不通了。
  const STALE_MS = 30000;
  const MAX_BACKOFF_MS = 30000;
  const HIDDEN_GRACE_MS = 60000;
  // 稳定币的代号。它们的价格就是「相对美元值多少」，不需要再换算。
  const STABLECOINS = new Set(['USDT', 'USDC', 'FDUSD', 'TUSD', 'DAI', 'PYUSD', 'USDG', 'USD1']);

  const state = new Map();       // symbol → entry
  const pairIndex = new Map();   // 交易对 → symbol
  const listeners = new Set();
  const watched = new Set();     // 已订阅的交易对
  let catalog = null;            // { eq: {代号: [对, 名, 类型, 计价]}, cx: {...} }
  let catalogPromise = null;
  let running = false;
  let socket = null;
  let retry = 0;
  let reconnectTimer = null;
  let watchdog = null;
  let lastAt = 0;
  let hiddenTimer = null;
  let equityTimer = null;
  // 正在建条目的 watch() 调用。见 watch() 里的注释。
  const admitting = new Map();

  // 条目已存在时，只在「这次要历史、而它还没有」的情况下补一次。
  async function topUpHistory(key, wantHistory) {
    const entry = state.get(key);
    if (!entry || entry.unsupported) return Boolean(entry && !entry.unsupported);
    if (wantHistory && !entry.series?.length) await primeSymbol(key, true);
    return true;
  }

  // 目录拿不到时的最小内置表。
  //
  // 不是为了本地开发方便才有的：catalog.json 一旦取不到，整站会失去**所有**价格
  // —— 行情条、持仓、快捷添加全部空白。有这张表兜底，至少行情条那三个标的和
  // 稳定币折算还是活的，退化范围收敛到「搜不到新标的」。
  // 只放最核心的几个，多了就成了要人手维护的第二份真相。
  const FALLBACK_CATALOG = {
    eq: {
      MSTR: ['Strategy Inc Common Stock Class A', 'EQUITY'],
      QQQ: ['Invesco QQQ Trust, Series 1', 'ETF']
    },
    cx: {
      BTC: ['BTCUSDT', 'Bitcoin', 'USDT'],
      ETH: ['ETHUSDT', 'Ethereum', 'USDT'],
      USDT: ['USDTUSD', 'TetherUS', 'USD'],
      USDC: ['USDCUSD', 'USDC', 'USD']
    }
  };

  const CATALOG_KEY = 'jiujiucat-binance-catalog';
  const CATALOG_TTL = 24 * 60 * 60 * 1000;

  function emit(symbol) {
    const entry = state.get(symbol);
    if (!entry) return;
    for (const fn of listeners) {
      try { fn(symbol, entry); } catch { /* 一个订阅者出错不该拖垮其余的 */ }
    }
  }

  // 和 app.js 的 getBeijingDayStartUnix() 是同一个定义。这里独立实现是为了不
  // 依赖加载顺序；两边一旦要改，必须一起改。
  function beijingDayStartUnix() {
    const beijingNow = new Date(Date.now() + 8 * 60 * 60 * 1000);
    return Math.floor((Date.UTC(
      beijingNow.getUTCFullYear(),
      beijingNow.getUTCMonth(),
      beijingNow.getUTCDate()
    ) - 8 * 60 * 60 * 1000) / 1000);
  }

  // ── 标的目录 ─────────────────────────────────────────────
  // 代号 → 交易对的解析、以及搜索，都靠它。由 Worker 拉一次 exchangeInfo 压成
  // 约 16KB 返回，前端缓存一天。目录里只有 status=TRADING 的盘口，所以订阅前
  // 不用再逐个校验 —— 这一步以前是每个标的一次 REST。
  function loadCachedCatalog() {
    try {
      const cached = JSON.parse(localStorage.getItem(CATALOG_KEY) || 'null');
      if (cached?.data?.eq && Date.now() - Number(cached.savedAt) < CATALOG_TTL) return cached.data;
    } catch { /* 缓存坏了就当没有 */ }
    return null;
  }

  function ensureCatalog() {
    if (catalog) return Promise.resolve(catalog);
    if (catalogPromise) return catalogPromise;
    const cached = loadCachedCatalog();
    if (cached) { catalog = cached; return Promise.resolve(catalog); }
    // 静态资源，不经过 Worker —— Binance 对 Cloudflare 出口返回 403，
    // 目录端点放在 Worker 里必然挂。见 scripts/build_catalog.py。
    catalogPromise = fetch('/catalog.json', { cache: 'default' })
      .then(response => { if (!response.ok) throw new Error('catalog failed'); return response.json(); })
      .then(data => {
        if (!data?.eq || !data?.cx) throw new Error('bad catalog shape');
        catalog = { eq: data.eq, cx: data.cx };
        try {
          localStorage.setItem(CATALOG_KEY, JSON.stringify({ savedAt: Date.now(), data: catalog }));
        } catch { /* 隐私模式写不进去，不影响本次会话 */ }
        return catalog;
      })
      .catch(() => {
        catalogPromise = null;
        // 内置表不写进 localStorage：它是降级态，不该把完整目录的缓存位置占掉，
        // 否则下次刷新会拿着这张残表当真，反而更难恢复。
        catalog = catalog || FALLBACK_CATALOG;
        return catalog;
      });
    return catalogPromise;
  }

  /**
   * 代号 → 标的信息。
   *
   * assetType 用来消除撞号：少数代号在两边都存在（比如 STX 既是美股也是币）。
   * 给了类型就按类型查；没给就先查美股 —— 用户手打裸代号时，7928 个美股比
   * 400 多个币更可能是目标。
   */
  function resolve(symbol, assetType) {
    if (!catalog) return null;
    // 老持仓里加密标的存的是 Yahoo 格式的 BTC-USD，这里统一剥掉后缀。
    const key = String(symbol || '').toUpperCase().replace(/-USD$/, '');
    const wantEquity = assetType === 'EQUITY' || assetType === 'ETF';
    const wantCrypto = assetType === 'CRYPTOCURRENCY' || assetType === 'STABLE';
    const eqRow = catalog.eq[key];
    const cxRow = catalog.cx[key];
    if (wantEquity && Array.isArray(eqRow)) {
      return { symbol: key, equity: true, name: eqRow[0], assetType: eqRow[1] || 'EQUITY' };
    }
    if (wantCrypto && Array.isArray(cxRow)) {
      return { symbol: key, equity: false, pair: cxRow[0], name: cxRow[1], quote: cxRow[2], venue: cxRow[3] || 'binance', assetType: 'CRYPTOCURRENCY' };
    }
    if (Array.isArray(eqRow)) {
      return { symbol: key, equity: true, name: eqRow[0], assetType: eqRow[1] || 'EQUITY' };
    }
    if (Array.isArray(cxRow)) {
      return { symbol: key, equity: false, pair: cxRow[0], name: cxRow[1], quote: cxRow[2], venue: cxRow[3] || 'binance', assetType: 'CRYPTOCURRENCY' };
    }
    return null;
  }

  /**
   * 把盘口原始价换算成美元价。
   *
   * USDT 计价的标的要乘以 USDT/USD。涨跌幅**不**用换算后的价格算，而是在原生
   * 计价里算 —— 分子分母同乘一个数比值不变，换算反而把 USDT 那 0.0x% 的汇率
   * 抖动当成标的自己的涨跌混进去。
   */
  function toUsd(entry, price) {
    if (entry.equity || entry.quote !== 'USDT' || !(price > 0)) return price;
    const rate = state.get('USDT')?.price;
    // 拿不到汇率就先按 1:1 显示。误差 0.03% 量级，远小于「整个价格不显示」的
    // 代价；entry.fxApplied 会告诉调用方这次到底换没换算。
    return rate > 0 ? price * rate : price;
  }

  function recompute(entry) {
    if (!Number.isFinite(entry.raw)) { entry.price = null; entry.change = null; return; }
    entry.price = toUsd(entry, entry.raw);
    entry.fxApplied = entry.equity || entry.quote !== 'USDT' || Number(state.get('USDT')?.price) > 0;
    if (entry.venue === 'cmc') {
      // CMC 直接给涨跌幅，没有基准价可算。
      entry.change = Number.isFinite(entry.presetChange) ? entry.presetChange : null;
      return;
    }
    const base = Number.isFinite(entry.dayOpen) && entry.dayOpen > 0 ? entry.dayOpen : entry.open24h;
    entry.change = Number.isFinite(base) && base > 0 ? ((entry.raw - base) / base) * 100 : null;
  }

  async function fetchJSON(url) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(url, { signal: controller.signal, cache: 'no-store' });
      if (!response.ok) throw new Error(`${url} -> ${response.status}`);
      return await response.json();
    } finally { clearTimeout(timer); }
  }

  /**
   * 补上基准价和历史序列。
   *
   * 加密直连交易所：Binance 的 K 线接口支持 timeZone 偏移，日线直接按北京时间
   * 切，第一个字段就是当日开盘价。实测 timeZone=8 的日开（143.31）和 UTC 的
   * （146.64）确实是两个数，这个参数是真生效。
   *
   * 美股走 Worker：那边的接口不发 CORS 头，浏览器直连不了；北京日基准的取法
   * 也复杂些（最细只有小时线），统一在 Worker 里算完再下发。
   */
  async function primeSymbol(symbol, wantHistory) {
    const entry = state.get(symbol);
    if (!entry) return;
    // 覆盖不到的标的也会留一个 entry（好让调用方看到 unsupported），但它没有
    // 交易对。跨天重取和回前台重连都会遍历整个 state，漏掉这个判断就会拿
    // undefined 去拼 URL —— 实测会打出 symbol=undefined 的请求。
    if (entry.unsupported) return;
    if (entry.equity) {
      try {
        // 一次 1H K 线同时给出：最新价、北京日基准、迷你走势序列。
        // 美股接口最细就是 1H（1m / 30m 返回空，5m 报 488004）。
        const data = await fetchJSON(
          `${EQUITY_BASE}/kline/chart?symbol=${encodeURIComponent(entry.symbol)}` +
          `&timeframe=1H&limit=200&adjustmentMode=ADJUSTED`
        );
        const bars = Array.isArray(data?.data?.bars) ? data.data.bars : [];
        if (!bars.length) throw new Error('no bars');
        applyEquityBars(entry, bars, wantHistory);
        entry.basis = '北京时间今日';
      } catch {
        entry.basis = '北京时间今日';
      }
      recompute(entry);
      emit(symbol);
      return;
    }
    if (entry.venue === 'cmc') {
      // Binance 没有的长尾币走 Worker → CMC。
      //
      // 这是**唯一**还经过 Worker 的行情路径，理由是别的路都不通：Binance 不上架
      // 竞争对手的平台币；原本用 OKX 补，但 2026-09-07 在真机上实测
      // www.okx.com 在用户网络下 DNS 解析不出来（OKX 走 Cloudflare CDN 域名）。
      // CMC 不拦 Worker，覆盖也更全。
      //
      // ⚠️ CMC 只给 24 小时涨跌，没有北京日基准，也没有 K 线。所以 basis 必须
      // 标成「24 小时」——不能挂着北京口径的牌子显示 24 小时的数。
      try {
        const data = await fetchJSON(`/api/crypto-quote?symbols=${encodeURIComponent(entry.symbol)}`);
        const row = data?.quotes?.[entry.symbol];
        const price = Number(row?.price);
        if (!(price > 0)) throw new Error('no price');
        entry.raw = price;
        entry.at = Date.now();
        entry.dayOpen = null;
        entry.presetChange = Number(row.change24h);
        entry.basis = '24 小时';
      } catch {
        entry.presetChange = null;
      }
      recompute(entry);
      emit(symbol);
      return;
    }
    try {
      const rows = await fetchJSON(
        `${BINANCE_BASE}/api/v3/klines?symbol=${entry.pair}&interval=1d&timeZone=8&limit=1`
      );
      const open = Number(rows?.[0]?.[1]);
      if (!(open > 0)) throw new Error('no kline');
      entry.dayOpen = open;
      entry.dayStart = beijingDayStartUnix();
      entry.basis = '北京时间今日';
      // 顺手把当日这根的**收盘价**当作初始价。
      //
      // 不做这一步的话，加密的价格完全依赖 WebSocket 推送，而清淡的盘口
      // （USDTUSD、USDCUSD 这种）可能很久没有成交，@ticker 就一直不推 ——
      // 表现是稳定币永远显示不出价格，而它恰恰是估值要用的那个数。
      // 这根 K 线本来就取回来了，收盘价白拿，不用多发一次请求。
      const close = Number(rows?.[0]?.[4]);
      if (close > 0 && !Number.isFinite(entry.raw)) {
        entry.raw = close;
        entry.at = Date.now();
      }
    } catch {
      // 拿不到基准价不是致命错误：价格照常实时更新，只是涨跌幅要退成 24 小时
      // 口径。绝不拿 24 小时的数挂着「北京时间今日」的牌子。
      entry.dayOpen = null;
      entry.basis = '24 小时';
    }
    if (wantHistory) {
      try {
        const rows = await fetchJSON(
          `${BINANCE_BASE}/api/v3/klines?symbol=${entry.pair}&interval=1h&limit=168`
        );
        entry.series = (Array.isArray(rows) ? rows : [])
          .filter(r => Array.isArray(r) && Number(r[0]) > 0 && Number(r[4]) > 0)
          .map(r => [Number(r[0]), Number(r[4])]);
      } catch { /* 没序列就不画图，不影响价格 */ }
    }
    recompute(entry);
    emit(symbol);
  }

  /**
   * 美股轮询。
   *
   * 一次请求带上所有已订阅的美股代号，Worker 从边缘缓存的全量表里裁出这几行 ——
   * 持仓里有 1 只还是 30 只股票，都只花一次请求。60 秒一轮：美股本来就没有
   * 秒级变化的必要，而且交易时段之外根本不动。
   */
  /// 轮询那些没有推送的标的：美股（Binance Stocks 没有公开行情流）和 OKX
  /// 的长尾币（为几个平台币再接一套 OKX 的 WS 协议不值得）。
  ///
  /// 按标的逐个取，而不是拉那张 0.9MB 的全量表：全量表本来是打算让 Worker 拉
  /// 一次、边缘缓存后按需裁剪的，但 Worker 到不了 Binance。每个客户端自己拉
  /// 0.9MB 在移动网络上不可接受，单标的一次约 30KB，持仓再多也比它省。
  async function pollSlowSymbols() {
    const targets = [...state.values()].filter(entry =>
      !entry.unsupported && (entry.equity || entry.venue === 'cmc')
    );
    if (!targets.length) return;
    // 并发但有上限：持仓几十只时一次性全发出去会被限流。
    for (let i = 0; i < targets.length; i += 6) {
      const batch = targets.slice(i, i + 6);
      await Promise.all(batch.map(entry =>
        primeSymbol(entry.symbol, Array.isArray(entry.series) && entry.series.length > 0)
          .then(() => { entry.live = true; })
          // 一个标的失败不改它的价格：上一次的值继续显示，下一轮再试。
          // 清掉反而更糟，界面会闪一下再回来。
          .catch(() => {})
      ));
    }
  }

  // 把美股的小时线套进 entry：最新价 + 北京日基准 + 序列。
  //
  // 北京 0 点正好是 UTC 16:00，而这些小时线就对齐在整点上，所以边界那根的
  // **开盘价**就是北京 0 点的价格，比拿上一根的收盘价更准 —— 有那根就用它。
  // 休市日（周末、节假日）0 点前没有成交，回退成最后收盘价、涨跌显示 0%。
  // 对「北京今日」这个口径来说这是诚实的，不是缺陷。
  function applyEquityBars(entry, bars, wantHistory) {
    const series = bars
      .filter(bar => Number(bar?.t) > 0 && Number(bar?.c) > 0)
      .map(bar => [Number(bar.t), Number(bar.c)]);
    if (!series.length) return;
    entry.raw = series.at(-1)[1];
    entry.at = Date.now();
    const dayStart = beijingDayStartUnix() * 1000;
    const boundary = bars.find(bar => Number(bar.t) === dayStart);
    const open = Number(boundary?.o);
    if (open > 0) entry.dayOpen = open;
    else {
      const prior = series.filter(point => point[0] <= dayStart);
      entry.dayOpen = prior.length ? prior.at(-1)[1] : series[0][1];
    }
    if (wantHistory) entry.series = series;
  }

  function handleTick(raw) {
    if (raw?.e !== '24hrTicker') return;
    const symbol = pairIndex.get(raw.s);
    if (!symbol) return;
    const entry = state.get(symbol);
    const price = Number(raw.c);
    if (!entry || !(price > 0)) return;
    entry.raw = price;
    entry.live = true;
    entry.at = Date.now();
    const open24h = Number(raw.o);
    if (open24h > 0) entry.open24h = open24h;
    recompute(entry);
    if (Array.isArray(entry.series) && entry.series.length && Number.isFinite(entry.price)) {
      const hour = Math.floor(entry.at / 3600000) * 3600000;
      if (entry.series.at(-1)[0] === hour) entry.series.at(-1)[1] = entry.price;
      else {
        entry.series.push([hour, entry.price]);
        // 每小时追加一根，页面挂着不关就会一直长。
        if (entry.series.length > SERIES_CAP) entry.series = entry.series.slice(-SERIES_CAP);
      }
    }
    emit(symbol);
    // USDT/USD 一动，所有 USDT 计价的标的换算结果都要跟着更新，否则它们的
    // 美元价会一直用着上一次的汇率。
    if (symbol === 'USDT') {
      for (const [other, otherEntry] of state) {
        if (other === 'USDT' || otherEntry.quote !== 'USDT') continue;
        recompute(otherEntry);
        emit(other);
      }
    }
  }

  function subscribeMessage(pairs) {
    return JSON.stringify({
      method: 'SUBSCRIBE',
      // @ticker 每 1000ms 一条，含最新价和 24h 统计。不用 @trade：逐笔一秒
      // 几十条，全是前端消化不掉也用不上的噪音。
      params: pairs.map(pair => `${pair.toLowerCase()}@ticker`),
      id: Date.now() % 1e9
    });
  }

  function armWatchdog() {
    clearInterval(watchdog);
    watchdog = setInterval(() => {
      if (!running) return;
      if (Date.now() - lastAt > STALE_MS) {
        try { socket?.close(); } catch { /* 已经关了就无所谓 */ }
      }
    }, 5000);
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    // 指数退避 + 抖动：不加抖动的话，一次上游抖动会让所有用户在同一毫秒重连。
    const delay = Math.min(1000 * 2 ** retry, MAX_BACKOFF_MS) + Math.random() * 1000;
    retry += 1;
    reconnectTimer = setTimeout(() => { if (running) connect(); }, delay);
  }

  function connect() {
    if (!running || !watched.size) return;
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) return;
    let ws;
    try { ws = new WebSocket(WS_URL); } catch { scheduleReconnect(); return; }
    socket = ws;
    lastAt = Date.now();

    ws.onopen = () => {
      retry = 0;
      if (watched.size) ws.send(subscribeMessage([...watched]));
      armWatchdog();
    };
    ws.onmessage = event => {
      lastAt = Date.now();
      let raw;
      try { raw = JSON.parse(event.data); } catch { return; }
      handleTick(raw);
    };
    ws.onclose = () => {
      clearInterval(watchdog);
      for (const entry of state.values()) entry.live = false;
      // 连接断了价格就是旧的。让调用方立刻看得见，而不是对着一个不再更新的
      // 数字以为还是实时的 —— 兜底轮询靠这个信号接管。
      for (const symbol of state.keys()) emit(symbol);
      if (running) scheduleReconnect();
    };
    ws.onerror = () => { try { ws.close(); } catch { /* onclose 会接手 */ } };
  }

  function disconnect() {
    clearTimeout(reconnectTimer);
    clearInterval(watchdog);
    const ws = socket;
    socket = null;
    if (ws) { ws.onclose = null; try { ws.close(); } catch { /* 已经关了 */ } }
    for (const entry of state.values()) entry.live = false;
  }

  // 北京日一翻篇，昨天的基准价就作废了，必须重取，否则涨跌幅会一直挂着昨天的账。
  function watchDayRollover() {
    setInterval(() => {
      const today = beijingDayStartUnix();
      for (const [symbol, entry] of state) {
        if (entry.dayStart !== today) primeSymbol(symbol, Array.isArray(entry.series) && entry.series.length > 0);
      }
    }, 60000);
  }

  // 切后台不立刻断。桌面端切个标签页看一眼就回来是常态，每次都断开重连意味着
  // 一次 REST 重取加一次握手，纯属自找的抖动。真正需要释放连接的是「长时间
  // 不看」和手机被系统冻结，60 秒的宽限期把这两类区分开。
  function onVisibilityChange() {
    if (!running) return;
    if (document.hidden) {
      clearTimeout(hiddenTimer);
      hiddenTimer = setTimeout(disconnect, HIDDEN_GRACE_MS);
      return;
    }
    clearTimeout(hiddenTimer);
    hiddenTimer = null;
    pollSlowSymbols();   // 回前台立刻补一轮，别让用户盯着一个旧价等 60 秒
    if (socket?.readyState === WebSocket.OPEN) return;  // 没断过，数据是连续的
    // 断过就一律当它已死：补基准价（可能已经跨天了），再重连。
    retry = 0;
    for (const [symbol, entry] of state) {
      primeSymbol(symbol, Array.isArray(entry.series) && entry.series.length > 0);
    }
    connect();
  }

  const MarketStream = {
    supported: typeof WebSocket === 'function',

    /** 目录就绪后 resolve。搜索和价格解析都要等它。 */
    ready() { return ensureCatalog(); },

    /** 代号 → 盘口信息，目录没加载好或标的不在覆盖范围内时返回 null。 */
    resolve,

    isStablecoin(symbol) { return STABLECOINS.has(String(symbol || '').toUpperCase()); },

    onTick(fn) { listeners.add(fn); return () => listeners.delete(fn); },

    /** 同步读最新状态，给不能 await 的估值路径用。没有就 null，绝不返回占位数。 */
    get(symbol) { return state.get(String(symbol || '').toUpperCase()) || null; },

    /**
     * 搜索标的。目录在本地，所以这是纯内存过滤 —— 不用每敲一个字母打一次
     * 请求，也就没有防抖和竞态问题。
     *
     * 排序：代号完全匹配 > 代号前缀匹配 > 名称匹配。加密排在股票前面，
     * 因为覆盖面差得远（400+ vs 72），裸代号更可能指的是币。
     */
    search(query, limit = 12) {
      if (!catalog) return [];
      const q = String(query || '').trim().toUpperCase();
      if (!q) return [];
      const out = [];
      const scan = (table, isEquity) => {
        for (const [code, row] of Object.entries(table)) {
          // 美股是 [名称, 类型]，加密是 [交易对, 名称, 计价]。
          const name = String((isEquity ? row[0] : row[1]) || '');
          const upperName = name.toUpperCase();
          let score;
          if (code === q) score = 0;
          else if (code.startsWith(q)) score = 1;
          else if (upperName.startsWith(q)) score = 2;
          else if (upperName.includes(q)) score = 3;
          else continue;
          out.push({
            // 同分时美股排前面：7928 个 vs 400 多个，裸代号更可能是股票。
            score: score + (isEquity ? 0 : 0.5),
            symbol: code,
            quoteSymbol: code,
            name: name || code,
            assetType: isEquity ? (row[1] || 'EQUITY') : 'CRYPTOCURRENCY',
            exchange: isEquity ? '美股' : 'Crypto'
          });
        }
      };
      scan(catalog.eq, true);
      scan(catalog.cx, false);
      return out
        .sort((a, b) => a.score - b.score || a.symbol.length - b.symbol.length || a.symbol.localeCompare(b.symbol))
        .slice(0, limit)
        .map(({ score, ...rest }) => rest);
    },

    /**
     * 加入订阅。wantHistory 只有要画趋势图的标的才传，省掉多余的 REST。
     * 目录里只有 TRADING 的盘口，所以不用再逐个校验 —— 但目录可能还没到，
     * 所以这里是异步的，调用方要通过 onTick 拿结果，不能假设立刻有值。
     */
    async watch(symbol, wantHistory = false, assetType) {
      const key = String(symbol || '').toUpperCase().replace(/-USD$/, '');
      // 已经建好了，或者正有另一个调用在建 —— 两种情况都等它，然后只补历史。
      //
      // 这个 in-flight 表不是可选的优化。watch() 里有 await（等目录、等基准价），
      // 两个调用方几乎同时进来时会**双双**通过 state.has() 检查，各建一次条目，
      // 后一次 state.set 把前一次连同已经取到的序列一起覆盖掉。表现是行情条的
      // 迷你走势图随机地画不出来 —— 快捷添加那几张卡片和行情条抢同一个 BTC，
      // 谁后完成谁说了算。
      const pending = admitting.get(key);
      if (pending) await pending;
      if (state.has(key)) return topUpHistory(key, wantHistory);

      const task = (async () => {
        await ensureCatalog();
        const info = resolve(key, assetType);
        if (!info) {
          // 留下 entry 而不是什么都不做：调用方 get() 时能看到 unsupported，
          // 从而明确走自己的兜底，而不是对着 null 猜是「还没到」还是「不支持」。
          state.set(key, { symbol: key, price: null, raw: NaN, unsupported: true });
          emit(key);
          return false;
        }
        state.set(key, {
          symbol: key, equity: info.equity, pair: info.pair, quote: info.quote,
          // venue 必须存进来：primeSymbol 靠它决定去 Binance 还是 OKX 取价。
          // 漏了这个字段，OKX 的币会拿着 OKX 的对（OKB-USDT）去问 Binance，
          // 而 Binance 对不认识的 symbol 连 CORS 头都不发，报的是 CORS 错误，
          // 看起来像跨域问题，其实是路由错了。
          venue: info.venue || 'binance',
          assetType: info.assetType, name: info.name, price: null, raw: NaN
        });
        if (info.equity) {
          // 美股没有行情流，靠 pollSlowSymbols 轮询。这里先补一次。
          await primeSymbol(key, wantHistory);
          if (running) pollSlowSymbols();
          return true;
        }
        pairIndex.set(info.pair, key);
        watched.add(info.pair);
        await primeSymbol(key, wantHistory);
        if (!running) return true;
        if (info.venue === 'cmc') return true;   // CMC 不订阅，靠轮询
        if (socket?.readyState === WebSocket.OPEN) socket.send(subscribeMessage([info.pair]));
        else connect();
        return true;
      })();

      admitting.set(key, task);
      try { return await task; } finally { admitting.delete(key); }
    },

    /// 取一次报价（订阅 + 补基准 + 返回当前状态）。
    /// 调用方拿到的就是 get() 的那个 entry，所以之后它会被推送继续更新。
    async fetchQuote(symbol, assetType, wantHistory = false) {
      const key = String(symbol || '').toUpperCase().replace(/-USD$/, '');
      await MarketStream.watch(key, wantHistory, assetType);
      const entry = state.get(key);
      if (!entry || entry.unsupported || !Number.isFinite(entry.price)) {
        throw new Error(`${key} 暂不支持或取价失败`);
      }
      return entry;
    },

    /// 一年日线，给组合走势图的「月 / 年」档用。
    /// 直连交易所 —— 和其余行情一样，不能经过 Worker。
    async fetchYearHistory(symbol, assetType) {
      await ensureCatalog();
      const info = resolve(String(symbol || '').toUpperCase().replace(/-USD$/, ''), assetType);
      if (!info) throw new Error('不在覆盖范围内');
      let series = [];
      if (info.equity) {
        const data = await fetchJSON(
          `${EQUITY_BASE}/kline/chart?symbol=${encodeURIComponent(info.symbol)}` +
          `&timeframe=1D&limit=365&adjustmentMode=ADJUSTED`
        );
        series = (data?.data?.bars || [])
          .filter(bar => Number(bar?.t) > 0 && Number(bar?.c) > 0)
          .map(bar => [Number(bar.t), Number(bar.c)]);
      } else if (info.venue === 'cmc') {
        // CMC 没有 K 线，长尾币画不了长期走势图。诚实地告诉调用方，
        // 而不是拿一个点画出一条假的平线。
        throw new Error('CMC 不提供历史序列');
      } else {
        const rows = await fetchJSON(
          `${BINANCE_BASE}/api/v3/klines?symbol=${info.pair}&interval=1d&limit=365`
        );
        series = (Array.isArray(rows) ? rows : [])
          .filter(r => Array.isArray(r) && Number(r[0]) > 0 && Number(r[4]) > 0)
          .map(r => [Number(r[0]), Number(r[4])]);
      }
      series.sort((a, b) => a[0] - b[0]);
      if (series.length < 2) throw new Error('日线不足');
      // USDT 计价的换算成美元，和实时价用同一个汇率，否则长短两段序列接不上。
      const rate = info.quote === 'USDT' ? (Number(state.get('USDT')?.price) || 1) : 1;
      return rate === 1 ? series : series.map(([t, p]) => [t, p * rate]);
    },

    start() {
      if (!MarketStream.supported || running) return;
      running = true;
      // 页面可能一开始就在后台（新标签页里打开、或从后台恢复的会话）。
      // 不判断这个就会白开连接，一直挂到用户第一次切过来为止。
      if (!document.hidden) connect();
      watchDayRollover();
      // 美股 60 秒一轮。页面在后台时跳过 —— 没人看的时候没必要打请求。
      pollSlowSymbols();
      equityTimer = setInterval(() => { if (!document.hidden) pollSlowSymbols(); }, 60000);
      document.addEventListener('visibilitychange', onVisibilityChange);
    },

    stop() {
      running = false;
      clearInterval(equityTimer);
      equityTimer = null;
      clearTimeout(hiddenTimer);
      hiddenTimer = null;
      disconnect();
    }
  };

  window.MarketStream = MarketStream;
})();
