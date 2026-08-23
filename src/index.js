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
 */

// 只允许这两个代号。缺了这道白名单，任何人都能拿 ?symbol=../../ 之类的构造把
// 这个 Worker 当成开放中继，用你账号的额度去转发任意流量。
const ALLOWED_SYMBOLS = new Set(['MSTR', 'QQQ']);

async function handleQuote(url) {
  const symbol = (url.searchParams.get('symbol') || '').toUpperCase();
  if (!ALLOWED_SYMBOLS.has(symbol)) {
    return Response.json({ error: 'unsupported symbol' }, { status: 400 });
  }

  const upstream =
    `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=5m&range=2d`;

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

    // 其余交回静态资源（含 404 处理）。
    return env.ASSETS.fetch(request);
  }
};
