/**
 * 同源行情代理。
 *
 * 为什么需要它：Yahoo Finance 不发 CORS 头，浏览器没法直连，所以原来借道
 * corsproxy.io 这个公共代理。本地开发时它是好的，但换到公网域名后 Yahoo 那两个
 * 请求稳定返回 403，美股涨跌基准被迫从「北京时间今日」降级成「较前收盘」。
 *
 * 走 Worker 转发就没有这个问题：请求由边缘节点发出，不受浏览器同源策略约束，
 * 也不经第三方、不看别人的限流脸色。
 *
 * 路由说明：静态资源命中时 Cloudflare 直接分发、根本不会执行这段代码，
 * 所以只有 /api/* 这类请求才会进来，不会给首屏增加开销。
 *
 * /api/quote 提供 Yahoo 行情；/api/search 只返回 Yahoo 可识别的股票、ETF 和
 * Crypto，前端只允许把这些搜索结果存成持仓。
 */

// 这道格式校验不是可选的：缺了它，构造出的路径可能让 Worker 变成开放中继。
// Yahoo 的合法代码不只 AAPL 这种纯字母：Crypto 是 BTC-USD，部分股票含点号
// 或连字符。仍然只允许行情代码会用到的有限字符，避免把代理变成开放中继。
const SYMBOL_PATTERN = /^[A-Z0-9^][A-Z0-9.^=-]{0,19}$/;
const SEARCH_TYPES = new Set(['EQUITY', 'ETF', 'CRYPTOCURRENCY']);

async function handleQuote(url) {
  const symbol = (url.searchParams.get('symbol') || '').toUpperCase();
  if (!SYMBOL_PATTERN.test(symbol)) {
    return Response.json({ error: 'unsupported symbol' }, { status: 400 });
  }

  // 最近 5 个交易日就是股票市场可交易的一周；30 分钟粒度足够绘制小型趋势图。
  const upstream =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=30m&range=5d`;

  const response = await fetch(upstream, {
    headers: {
      // Yahoo 对缺少浏览器特征的请求直接返回 403，这也是公共代理挂掉的原因之一。
      'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'application/json'
    },
    // 边缘缓存 60 秒：行情不需要秒级精度，但能挡住刷新风暴打到上游。
    cf: { cacheTtl: 60, cacheEverything: true }
  });

  if (!response.ok) {
    // 交回非 2xx，前端的 TradingView 备用链路会照常接管。
    return Response.json({ error: 'upstream failed' }, { status: 502 });
  }

  // 原样透传 Yahoo 的结构，前端解析逻辑一行都不用改。
  return new Response(response.body, {
    status: 200,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'public, max-age=60'
    }
  });
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
async function handleCryptoLogos() {
  const upstream =
    'https://api.coinmarketcap.com/data-api/v3/cryptocurrency/listing' +
    '?start=1&limit=1000&sortBy=market_cap&sortType=desc&cryptoType=all&tagType=all';

  const response = await fetch(upstream, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'application/json'
    },
    // 上游响应 1.3MB，边缘缓存 6 小时：币的排名会动，但图标 ID 一旦分配就不变。
    cf: { cacheTtl: 21600, cacheEverything: true }
  });

  if (!response.ok) {
    return Response.json({ error: 'upstream failed' }, { status: 502 });
  }

  const data = await response.json();
  const list = data?.data?.cryptoCurrencyList;
  if (!Array.isArray(list)) {
    return Response.json({ error: 'unexpected upstream shape' }, { status: 502 });
  }

  const ids = {};
  for (const coin of list) {
    const symbol = String(coin?.symbol || '').toUpperCase();
    // 同一个代码会被多个币占用（山寨币蹭代码）。列表按市值降序，先出现的那个
    // 才是用户想看到的那一个，所以只认第一次出现。
    if (symbol && Number.isInteger(coin?.id) && coin.id > 0 && !(symbol in ids)) {
      ids[symbol] = coin.id;
    }
  }

  return Response.json(ids, {
    headers: { 'Cache-Control': 'public, max-age=21600' }
  });
}

async function handleSearch(url) {
  const query = (url.searchParams.get('q') || '').trim();
  if (!query || query.length > 40 || /[\u0000-\u001f\u007f]/.test(query)) {
    return Response.json({ error: 'invalid query' }, { status: 400 });
  }

  const upstream =
    `https://query2.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(query)}` +
    '&quotesCount=16&newsCount=0&enableFuzzyQuery=false';
  const response = await fetch(upstream, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'application/json'
    },
    cf: { cacheTtl: 300, cacheEverything: true }
  });

  if (!response.ok) {
    return Response.json({ error: 'upstream failed' }, { status: 502 });
  }

  const data = await response.json();
  const results = (Array.isArray(data?.quotes) ? data.quotes : [])
    .filter(item => item?.isYahooFinance !== false && SEARCH_TYPES.has(item?.quoteType))
    .map(item => {
      const quoteSymbol = String(item.symbol || '').toUpperCase();
      if (!SYMBOL_PATTERN.test(quoteSymbol)) return null;
      const isCrypto = item.quoteType === 'CRYPTOCURRENCY';
      return {
        symbol: isCrypto ? quoteSymbol.replace(/-USD$/, '') : quoteSymbol,
        quoteSymbol,
        name: String(item.longname || item.shortname || quoteSymbol).slice(0, 120),
        assetType: item.quoteType,
        exchange: String(item.exchDisp || item.exchange || '').slice(0, 60)
      };
    })
    .filter(Boolean)
    .slice(0, 12);

  return Response.json({ results }, {
    headers: { 'Cache-Control': 'public, max-age=300' }
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/api/quote') {
      if (request.method !== 'GET') {
        return new Response('Method Not Allowed', { status: 405 });
      }
      try {
        return await handleQuote(url);
      } catch {
        return Response.json({ error: 'proxy error' }, { status: 502 });
      }
    }

    if (url.pathname === '/api/search') {
      if (request.method !== 'GET') {
        return new Response('Method Not Allowed', { status: 405 });
      }
      try {
        return await handleSearch(url);
      } catch {
        return Response.json({ error: 'search error' }, { status: 502 });
      }
    }

    if (url.pathname === '/api/crypto-logos') {
      if (request.method !== 'GET') {
        return new Response('Method Not Allowed', { status: 405 });
      }
      try {
        return await handleCryptoLogos();
      } catch {
        return Response.json({ error: 'crypto logo error' }, { status: 502 });
      }
    }

    // 其余交回静态资源（含 404 处理）。
    return env.ASSETS.fetch(request);
  }
};
