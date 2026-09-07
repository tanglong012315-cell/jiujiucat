/**
 * 同源行情代理（Binance）。
 *
 * 为什么需要它：浏览器不能直连的上游都在这里转发 —— Binance 的资产名称接口、
 * 美股接口（bapi/*，站内接口不发 CORS 头）、CMC 的图标接口。加密货币的实时
 * 价格是浏览器直连交易所 WebSocket 的（见 public/market-stream.js），不走这里。
 *
 * 2026-09-07：整站从 Yahoo 切到 Binance（用户决定）。Yahoo 是非官方接口、会 403、
 * 没有 SLA。
 *
 * ⚠️ Binance 有**两套完全不同**的股票产品，别搞混（这一点排查时踩过坑）：
 *
 *   现货 bStocks   代号 AAPLB，交易对 AAPLBUSDT，走 api.binance.com/api/v3。
 *                  是**代币化股票**：第三方发行、USDT 计价、7×24 交易，价格和
 *                  真实股价有 0.2~0.7% 偏差。只有 72 个标的，没有 VOO。
 *   Binance Stocks 代号 EQ_VOO，走 www.binance.com/bapi/equity。
 *                  是**真实美股**：真实价格、真实交易时段，7928 个标的
 *                  （4805 股票 + 3122 ETF），VOO / VTI / 传统蓝筹都有。
 *
 * 本站用的是后者 —— 持仓估值必须对着真实股价，代币盘那 0.x% 的偏差会直接
 * 变成盈亏里的误差。前者一个都不用。
 *
 * 路由说明：静态资源命中时 Cloudflare 直接分发、根本不会执行这段代码，
 * 所以只有 /api/* 才会进来，不给首屏增加开销。
 */

const BINANCE = 'https://api.binance.com';
// 美股接口。都是 public，服务端直接可取，不需要鉴权或浏览器会话。
const EQUITY = 'https://www.binance.com/bapi/equity/v1/public/equity';
// 名称走币安站内接口 —— 公开的 exchangeInfo 只有代号，没有公司名，
// 搜索结果只显示「AAPLB」对用户毫无意义。和 /api/crypto-logos 用的 CMC
// 接口是同一类非公开端点，随时可能变；挂了就退化成「只有代号」，不影响价格。
const BINANCE_ASSETS = 'https://www.binance.com/bapi/asset/v2/public/asset/asset/get-all-asset';

const BROWSER_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Accept': 'application/json'
};

// 只允许行情代号会用到的有限字符，避免把代理变成开放中继。
const PAIR_PATTERN = /^[A-Z0-9]{4,30}$/;
// 美股代号会带点号（BRK.B）和连字符，但仍然只放行有限字符。
const EQ_SYMBOL_PATTERN = /^[A-Z0-9][A-Z0-9.\-]{0,11}$/;

// 代币化股票的名字都带这个后缀，是它们和普通币种唯一可靠的区分标志 ——
// 光看代号结尾的 B 会把 SHIB、ARB、CKB 这些币误判成股票。
const STOCK_TAG = '(bStocks)';
// 名字里出现这些词的按 ETF 归类，其余算个股。只影响搜索结果里的类型标签。
const ETF_WORDS = /\b(ETF|Trust|Bull|Bear|Long|Short|Ultra|ProShares|Direxion|iShares|VanEck|Roundhill|GraniteShares|Tradr)\b/i;
// 名字里没有任何 ETF 字样、光看名字认不出来的，在这里点名。币安给 SPY 的
// 名字就是「SPY」两个字母，规则匹配不到。
const ETF_TICKERS = new Set(['SPY']);

// 这些基础资产要优先选**美元**盘，而不是默认的 USDT 盘。
//
// 稳定币是这条规则唯一的用户，也是必须有它的原因：USDC 同时有 USDCUSDT 和
// USDCUSD 两个盘，按默认规则会选中前者 —— 那给出的是「USDC 值多少 USDT」，
// 不是「值多少美元」。而持仓估值要的恰恰是后者：拿 USDT 当美元来给稳定币
// 定价，等于用一个本身会脱锚的东西当尺子，脱锚幅度直接被抹平成 0。
const USD_PREFERRED = new Set(['USDT', 'USDC', 'FDUSD', 'TUSD', 'DAI', 'PYUSD', 'USDG', 'USD1']);

// 上游失败时把状态码和一小段响应体带出来。
//
// 原来这里只抛一个笼统的错，Worker 再统一返回 502 —— 结果线上出问题时，
// 「是被限流、被地区封锁、还是结构变了」完全分不出来，只能靠猜。
class UpstreamError extends Error {
  constructor(url, status, body) {
    super(`upstream ${status}`);
    this.status = status;
    this.body = body;
    this.host = new URL(url).host;
  }
}

async function fetchUpstream(url, cacheTtl) {
  const response = await fetch(url, {
    headers: BROWSER_HEADERS,
    cf: { cacheTtl, cacheEverything: true }
  });
  if (!response.ok) {
    // 只取前 200 字符：够看清是什么错，又不会把大段 HTML 错误页灌进日志。
    const body = await response.text().catch(() => '');
    throw new UpstreamError(url, response.status, body.slice(0, 200));
  }
  return response.json();
}

/**
 * 标的目录：代号 → [交易对, 名称]。
 *
 * 搜索和价格解析都靠它。压成两张表返回（eq = 股票，cx = 加密），约 60KB，
 * 前端缓存一天 —— 这样搜索是本地过滤，不用每敲一个字母就打一次请求。
 *
 * 为什么分两张表：代号会撞。QNTB 是 Quantinuum（股票），去掉后缀是 QNT，
 * 而 QNT 同时是 Quant 这个币。合成一张表就必然有一个被覆盖掉。
 */
async function handleCatalog() {
  const [info, assets, stocks] = await Promise.all([
    fetchUpstream(`${BINANCE}/api/v3/exchangeInfo`, 21600),
    // 名称拿不到不是致命的：退化成「只有代号」，搜索仍然可用。
    fetchUpstream(BINANCE_ASSETS, 21600).catch(() => null),
    fetchUpstream(`${EQUITY}/symbol/get-symbols-static`, 21600).catch(() => null)
  ]);

  const symbols = Array.isArray(info?.symbols) ? info.symbols : [];
  if (!symbols.length) throw new Error('unexpected exchangeInfo shape');

  const names = {};
  for (const row of (assets?.data || [])) {
    if (row?.assetCode) names[row.assetCode] = String(row.assetName || '');
  }

  // 同一个基础资产可能有多个计价盘口，这里为每个资产挑一个。
  // 默认优先 USDT 盘（几乎总是最深的），USD_PREFERRED 里的反过来优先 USD 盘。
  const best = new Map();
  for (const item of symbols) {
    if (item?.status !== 'TRADING' || item?.isSpotTradingAllowed !== true) continue;
    const quote = item.quoteAsset;
    if (quote !== 'USDT' && quote !== 'USD') continue;
    const base = item.baseAsset;
    const wanted = USD_PREFERRED.has(base) ? 'USD' : 'USDT';
    const current = best.get(base);
    if (!current || (current.quote !== wanted && quote === wanted)) {
      best.set(base, { pair: item.symbol, quote });
    }
  }

  // 加密：代号 → [交易对, 名称, 计价货币]。
  // 代币化股票（名字带 bStocks）整类跳过 —— 本站的美股走真实股价，
  // 留着它们只会在搜索里和真实标的撞号，让人选到错的那一个。
  const cx = {};
  for (const [base, entry] of best) {
    const fullName = names[base] || '';
    if (fullName.includes(STOCK_TAG)) continue;
    cx[base] = [entry.pair, fullName || base, entry.quote];
  }

  // 美股：代号 → [名称, 类型]。不需要交易对 —— 那边的接口直接认代号。
  const eq = {};
  for (const row of (stocks?.data || [])) {
    const code = String(row?.s || '').toUpperCase();
    if (!code || !row?.n) continue;
    // 名字截断到 48 字符：全量 7928 条，不截的话目录会明显变大，而列表里
    // 本来也放不下更长的名字。
    eq[code] = [String(row.n).slice(0, 48), row.t === 'ETF' ? 'ETF' : 'EQUITY'];
  }

  return Response.json({ eq, cx, savedAt: Date.now() }, {
    headers: { 'Cache-Control': 'public, max-age=21600' }
  });
}

/**
 * 美股实时价。
 *
 * 上游一次返回全部 7928 个标的（约 0.9MB），所以**不能**让每个客户端每次都拉
 * 全量。这里在边缘缓存 60 秒，再按调用方点名的代号裁剪 —— 一次上游请求服务
 * 所有用户，每个用户只收到自己那几行。
 *
 * mp 是市场阶段（C = 已收市）。c 是现价，prc 是前收盘 —— 但本站的涨跌口径是
 * 「北京时间今日」，基准由 /api/quote 的 K 线给，不用这里的 prc。
 */
async function handlePrices(url) {
  const wanted = (url.searchParams.get('eq') || '')
    .toUpperCase().split(',').map(code => code.trim())
    .filter(code => code && EQ_SYMBOL_PATTERN.test(code))
    .slice(0, 60);
  if (!wanted.length) return Response.json({ error: 'no symbols' }, { status: 400 });

  const dynamic = await fetchUpstream(`${EQUITY}/symbol/get-symbols-dynamic`, 60);
  const rows = Array.isArray(dynamic?.data) ? dynamic.data : [];
  const index = new Map();
  for (const row of rows) {
    if (row?.ac) index.set(String(row.ac).replace(/^EQ_/, ''), row);
  }

  const prices = {};
  for (const code of wanted) {
    const row = index.get(code);
    const price = Number(row?.c);
    if (price > 0) prices[code] = { price, phase: row.mp || null };
  }

  return Response.json({ prices }, {
    headers: { 'Cache-Control': 'public, max-age=60' }
  });
}

/**
 * 按需报价：给没走 WebSocket 的路径用（首屏补齐、流没连上时的兜底）。
 *
 * 涨跌幅口径是「北京时间今日」，和站内其余部分一致。Binance 的 K 线接口
 * 支持 timeZone 参数，日线直接按北京时间切，不用自己去盘中找那一根 ——
 * 实测 timeZone=8 的日开盘价和 UTC 的确实是两个数，这个参数是真生效。
 */
async function handleQuote(url) {
  const eqSymbol = (url.searchParams.get('eq') || '').toUpperCase();
  if (eqSymbol) return handleEquityQuote(eqSymbol, url);

  const pair = (url.searchParams.get('pair') || '').toUpperCase();
  if (!PAIR_PATTERN.test(pair)) {
    return Response.json({ error: 'unsupported pair' }, { status: 400 });
  }
  // 粒度写死在白名单里，不让调用方自由指定，免得把代理变成任意转发。
  const RANGES = { '5d': ['1h', 168], '1mo': ['4h', 180], '1y': ['1d', 365] };
  const key = RANGES[url.searchParams.get('range')] ? url.searchParams.get('range') : '5d';
  const [interval, limit] = RANGES[key];

  const [klines, daily] = await Promise.all([
    fetchUpstream(`${BINANCE}/api/v3/klines?symbol=${pair}&interval=${interval}&limit=${limit}`, 60),
    fetchUpstream(`${BINANCE}/api/v3/klines?symbol=${pair}&interval=1d&timeZone=8&limit=1`, 60)
  ]);

  if (!Array.isArray(klines) || !klines.length) {
    return Response.json({ error: 'no data' }, { status: 502 });
  }

  const series = klines
    .filter(row => Array.isArray(row) && Number(row[0]) > 0 && Number(row[4]) > 0)
    .map(row => [Number(row[0]), Number(row[4])]);
  const price = series.at(-1)?.[1];
  const dayOpen = Number(daily?.[0]?.[1]);
  // 拿不到北京日开盘价就不返回涨跌幅，也不改口径标注 —— 让前端显示「—」，
  // 而不是拿一个别的口径的数冒充「北京时间今日」。
  const change = dayOpen > 0 && price > 0 ? ((price - dayOpen) / dayOpen) * 100 : null;

  return Response.json({ price, change, series }, {
    headers: { 'Cache-Control': 'public, max-age=60' }
  });
}

/**
 * 美股报价：序列 + 「北京时间今日」基准。
 *
 * 基准的取法和站内其余部分一致：找时间戳 ≤ 北京 0 点的最后一根，用它的收盘价。
 * 北京 0 点正好是 UTC 16:00，而美股接口的小时线就对齐在整点上，所以边界那根
 * 的**开盘价**就是北京 0 点的价格，比用上一根的收盘价更准 —— 有那根就用它。
 *
 * 美股接口的最细粒度是 1H（1m / 30m 都返回空，5m 直接报 488004），所以精度就
 * 到小时。休市日（周末、节假日）0 点前没有成交，基准回退成最后收盘价，涨跌
 * 显示 0% —— 对「北京今日」这个口径来说这是诚实的，不是缺陷。
 */
async function handleEquityQuote(symbol, url) {
  if (!EQ_SYMBOL_PATTERN.test(symbol)) {
    return Response.json({ error: 'unsupported symbol' }, { status: 400 });
  }
  // 只有 1H / 1D / 1W 有数据，别的粒度上游返回空。
  const RANGES = { '5d': ['1H', 200], '1mo': ['1D', 60], '1y': ['1D', 365] };
  const key = RANGES[url.searchParams.get('range')] ? url.searchParams.get('range') : '5d';
  const [timeframe, limit] = RANGES[key];

  const encoded = encodeURIComponent(symbol);
  const data = await fetchUpstream(
    `${EQUITY}/kline/chart?symbol=${encoded}&timeframe=${timeframe}&limit=${limit}&adjustmentMode=ADJUSTED`,
    60
  );
  const bars = Array.isArray(data?.data?.bars) ? data.data.bars : [];
  if (!bars.length) return Response.json({ error: 'no data' }, { status: 502 });

  const series = bars
    .filter(bar => Number(bar?.t) > 0 && Number(bar?.c) > 0)
    .map(bar => [Number(bar.t), Number(bar.c)]);
  const price = series.at(-1)?.[1];

  const dayStart = beijingDayStartMs();
  const boundary = bars.find(bar => Number(bar.t) === dayStart);
  let base = Number(boundary?.o);
  if (!(base > 0)) {
    const prior = bars.filter(bar => Number(bar.t) <= dayStart && Number(bar.c) > 0);
    base = Number(prior.at(-1)?.c);
  }
  const change = base > 0 && price > 0 ? ((price - base) / base) * 100 : null;

  return Response.json({ price, change, series }, {
    headers: { 'Cache-Control': 'public, max-age=60' }
  });
}

// 北京日起点（毫秒）。和 public/app.js 的 getBeijingDayStartUnix() 同一个定义，
// 只是单位不同；两边一旦要改，必须一起改。
function beijingDayStartMs() {
  const beijingNow = new Date(Date.now() + 8 * 60 * 60 * 1000);
  return Date.UTC(
    beijingNow.getUTCFullYear(),
    beijingNow.getUTCMonth(),
    beijingNow.getUTCDate()
  ) - 8 * 60 * 60 * 1000;
}

// 加密货币图标的「代码 → CMC 数字 ID」映射表。
//
// 为什么要绕这一圈：CoinMarketCap 的图是跟着品牌更新的（OKB 2025 年换成黑底
// 棋盘格那版，CoinCap 到现在还是旧的蓝色渐变图），但它只认数字 ID。前端曾经
// 硬编码过 34 个币的 ID，漏得多又要人手维护。这里改成拉一次市值前 1000 的
// 列表、压成 {代码: ID} 返回（约 15KB），前端缓存一天，映射表不再进代码。
//
// 用的是 CMC 站内的非公开接口，随时可能变。挂了就返回 502，前端会继续用
// CoinCap —— logo 不在关键路径上。
// 名称索引是给「代码对不上」的情况兜底的：改过代码的币（RNDR 在 CMC 已经叫
// RENDER）按代码永远查不到，但两边的「名字」是对得上的。归一化 = 转小写 +
// 去掉所有非字母数字 + 去掉结尾的 usd。
function normalizeCoinName(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
    .replace(/usd$/, '');
}

async function handleCryptoLogos() {
  const data = await fetchUpstream(
    'https://api.coinmarketcap.com/data-api/v3/cryptocurrency/listing' +
    '?start=1&limit=1000&sortBy=market_cap&sortType=desc&cryptoType=all&tagType=all',
    21600
  );
  const list = data?.data?.cryptoCurrencyList;
  if (!Array.isArray(list)) {
    return Response.json({ error: 'unexpected upstream shape' }, { status: 502 });
  }

  const ids = {};
  const names = {};
  for (const coin of list) {
    if (!Number.isInteger(coin?.id) || coin.id <= 0) continue;
    const symbol = String(coin.symbol || '').toUpperCase();
    // 同一个代码会被多个币占用（山寨币蹭代码）。列表按市值降序，先出现的那个
    // 才是用户想看到的那一个，所以只认第一次出现。名称索引同理。
    if (symbol && !(symbol in ids)) ids[symbol] = coin.id;
    const name = normalizeCoinName(coin.name);
    if (name && !(name in names)) names[name] = coin.id;
  }

  return Response.json({ ids, names }, {
    headers: { 'Cache-Control': 'public, max-age=21600' }
  });
}


/**
 * 上游连通性探针。
 *
 * 存在的理由：2026-09-07 上线时 Binance 对 Worker 全线 403，而同一时刻浏览器
 * 直连全部 200 —— 当时完全分不清是「Binance 专门拦数据中心 IP」还是「Cloudflare
 * 出口被普遍拦」。这两种结论对架构的含义完全相反，靠猜会改错方向。
 * 只回状态码，不回响应内容。
 */
async function handleProbe() {
  const targets = {
    'binance-api': 'https://api.binance.com/api/v3/ping',
    'binance-bapi': 'https://www.binance.com/bapi/equity/v1/public/equity/symbol/get-symbols-static',
    'okx': 'https://www.okx.com/api/v5/market/ticker?instId=BTC-USDT',
    'coinbase': 'https://api.exchange.coinbase.com/products/BTC-USD/stats',
    'coinmarketcap': 'https://api.coinmarketcap.com/data-api/v3/cryptocurrency/listing?start=1&limit=1'
  };
  const results = {};
  await Promise.all(Object.entries(targets).map(async ([name, url]) => {
    try {
      const response = await fetch(url, { headers: BROWSER_HEADERS });
      results[name] = response.status;
    } catch (error) {
      results[name] = String(error?.message || error).slice(0, 80);
    }
  }));
  return Response.json({ colo: 'edge', results }, {
    headers: { 'Cache-Control': 'no-store' }
  });
}

const ROUTES = {
  '/api/catalog': handleCatalog,
  '/api/quote': handleQuote,
  '/api/prices': handlePrices,
  '/api/crypto-logos': handleCryptoLogos,
  '/api/probe': handleProbe
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const handler = ROUTES[url.pathname];
    if (!handler) return env.ASSETS.fetch(request);
    if (request.method !== 'GET') return new Response('Method Not Allowed', { status: 405 });
    try {
      return await handler(url);
    } catch (error) {
      if (error instanceof UpstreamError) {
        return Response.json({
          error: 'upstream failed',
          host: error.host,
          status: error.status,
          detail: error.body
        }, { status: 502 });
      }
      return Response.json({ error: String(error?.message || error) }, { status: 502 });
    }
  }
};
