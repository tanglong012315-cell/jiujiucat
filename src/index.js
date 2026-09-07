/**
 * 同源代理 —— 只剩图标一个用途。
 *
 * 行情**不能**放在这里。2026-09-07 实测：Binance 对 Cloudflare Worker 的出口
 * 返回 403（api.binance.com 和 www.binance.com 两个域名都拦），OKX 返回 429，
 * 而同一时刻浏览器和本机直连全部 200 —— 它们拦的是数据中心 IP，不是地区。
 * 当时把目录和报价做成 Worker 代理，上线即全线 502。
 *
 * 现在的分工：
 *   行情价格  客户端直连交易所（见 public/market-stream.js）
 *   标的目录  预生成的静态文件 public/catalog.json（见 scripts/build_catalog.py），
 *             静态资源由 Cloudflare 直接分发，根本不经过 Worker
 *   图标映射  留在这里 —— 上游是 CMC，它不拦 Worker（探针实测 200）
 *
 * /api/probe 是上游连通性探针，出问题时用它分辨「谁拦了我」，只回状态码。
 *
 * 路由说明：静态资源命中时 Cloudflare 直接分发、根本不会执行这段代码。
 */


const BROWSER_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Accept': 'application/json'
};

// 美股代号会带点号（BRK.B）和连字符，但仍然只放行有限字符。


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
