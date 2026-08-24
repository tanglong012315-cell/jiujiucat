const form = document.querySelector('#calculator-form');
const principalInput = document.querySelector('#principal');
const rateInput = document.querySelector('#rate');
const rateSlider = document.querySelector('#rate-slider');
const canvas = document.querySelector('#growth-chart');
const tooltip = document.querySelector('#chart-tooltip');
const periodButtons = [...document.querySelectorAll('[data-period]')];
const quickAmountButtons = [...document.querySelectorAll('[data-amount]')];
const themeToggle = document.querySelector('#theme-toggle');

let state = { principal: 10000, rate: 8, type: 'compound', period: 'year', usdCny: null };
let chartPoints = [];
let currentReturns = { daily: 0, monthly: 0, yearly: 0, chartTotal: 0 };
const preferencesKey = 'retirement-calculator-preferences';
const themeKey = 'retirement-calculator-theme';

const money = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const cnyMoney = new Intl.NumberFormat('zh-CN', { style: 'currency', currency: 'CNY', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const btcMoney = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const moneyWhole = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const cnyWhole = new Intl.NumberFormat('zh-CN', { style: 'currency', currency: 'CNY', maximumFractionDigits: 0 });
// Cents are false precision past five figures, and they cost the row a type size.
const metricMoney = value => (Math.abs(value) >= 10000 ? moneyWhole : money).format(value);
const metricCny = value => (Math.abs(value) >= 10000 ? cnyWhole : cnyMoney).format(value);
const marketAssets = [
  { symbol: 'BTC', name: 'Bitcoin', icon: 'btc-icon.svg', basis: '北京时间今日', price: null, change: null, series: [], cached: false, status: '获取中' },
  { symbol: 'MSTR', name: 'MSTR', icon: 'mstr-icon.svg', basis: '北京时间今日', price: null, change: null, series: [], cached: false, status: '获取中', equity: true },
  { symbol: 'QQQ', name: 'QQQ', icon: 'qqq-icon.svg', basis: '北京时间今日', price: null, change: null, series: [], cached: false, status: '获取中', equity: true }
];
let currentMarketIndex = 0;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let marketRotationId = null;

function applyTheme(theme, persist = false) {
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
  document.querySelector('meta[name="theme-color"]').content = theme === 'dark' ? '#1C1C1C' : '#FFFFFF';
  themeToggle.setAttribute('aria-label', theme === 'dark' ? '切换到浅色模式' : '切换到深色模式');
  if (persist) localStorage.setItem(themeKey, theme);
  requestAnimationFrame(() => {
    drawChart();
    fitMetricNumbers();
  });
}

function initializeTheme() {
  const systemTheme = matchMedia('(prefers-color-scheme: dark)');
  const savedTheme = localStorage.getItem(themeKey);
  applyTheme(savedTheme || (systemTheme.matches ? 'dark' : 'light'));
  themeToggle.addEventListener('click', () => {
    applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark', true);
  });
  systemTheme.addEventListener('change', event => {
    if (!localStorage.getItem(themeKey)) applyTheme(event.matches ? 'dark' : 'light');
  });
}

// ── 美股交易时段 ─────────────────────────────────────────
// 美东时间：04:00 盘前 → 09:30 主盘 → 16:00 盘后 → 20:00 夜盘。
// 夜盘从周日 20:00 一路滚到周五 20:00，周末整体休市。
// BTC 不参与这套判定 —— 加密货币没有时段可言。

// 全天休市日。每年得更新一次；表过期不会崩，只是当天会被误判成正常时段。
const MARKET_HOLIDAYS = new Set([
  '2026-01-01', '2026-01-19', '2026-02-16', '2026-04-03', '2026-05-25',
  '2026-06-19', '2026-07-03', '2026-09-07', '2026-11-26', '2026-12-25',
  '2027-01-01', '2027-01-18', '2027-02-15', '2027-03-26', '2027-05-31',
  '2027-06-18', '2027-07-05', '2027-09-06', '2027-11-25', '2027-12-24'
]);
// 提前收盘日：美东 13:00 就收，之后直接进盘后。
const MARKET_HALF_DAYS = new Set(['2026-11-27', '2026-12-24', '2027-11-26']);

const MARKET_SESSIONS = {
  pre:    { label: '盘前', full: '盘前交易' },
  open:   { label: '交易中', full: '常规交易时段' },
  after:  { label: '盘后', full: '盘后交易' },
  night:  { label: '夜间', full: '夜间交易' },
  closed: { label: '休市', full: '休市' }
};

// 交给 Intl 做时区换算，别自己算偏移 —— 美国夏令时一年切两次，手算必错。
const etClock = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/New_York', hour12: false,
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', weekday: 'short'
});
const ET_WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function etSnapshot(date) {
  const parts = {};
  for (const part of etClock.formatToParts(date)) parts[part.type] = part.value;
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    // hour12:false 在部分实现里把午夜报成 '24'，取模归零。
    minutes: (Number(parts.hour) % 24) * 60 + Number(parts.minute),
    dow: ET_WEEKDAYS.indexOf(parts.weekday)
  };
}

function marketSessionKey(now = new Date()) {
  const t = etSnapshot(now);
  if (t.dow === 6) return 'closed';                                  // 周六：周五 20:00 就收了
  if (t.dow === 0) return t.minutes >= 1200 ? 'night' : 'closed';    // 周日 20:00 夜盘开市
  if (MARKET_HOLIDAYS.has(t.date)) return 'closed';
  if (t.minutes < 240) {
    // 00:00–04:00 是前一晚夜盘的延续，所以要看「昨天」开没开。
    const prev = etSnapshot(new Date(now.getTime() - 864e5));
    return (prev.dow === 6 || MARKET_HOLIDAYS.has(prev.date)) ? 'closed' : 'night';
  }
  if (t.minutes < 570) return 'pre';                                 // 04:00–09:30
  if (t.minutes < (MARKET_HALF_DAYS.has(t.date) ? 780 : 960)) return 'open';
  if (t.minutes < 1200) return 'after';                              // 收盘–20:00
  return t.dow === 5 ? 'closed' : 'night';                           // 周五 20:00 进入周末
}

function renderMarketSession(asset) {
  const badge = document.querySelector('#market-session');
  if (!asset || !asset.equity) { badge.hidden = true; return null; }
  const key = marketSessionKey();
  badge.hidden = false;
  badge.textContent = MARKET_SESSIONS[key].label;
  badge.dataset.state = key;
  return MARKET_SESSIONS[key];
}

function renderMarketTicker(asset) {
  document.querySelector('#market-icon').src = asset.icon;
  document.querySelector('#market-name').textContent = asset.name;
  document.querySelector('#market-price').textContent = Number.isFinite(asset.price) ? btcMoney.format(asset.price) : '$—';
  const changeLabel = document.querySelector('#market-change');
  let accessibleChange = asset.cached ? '最近价格' : asset.status;
  if (Number.isFinite(asset.change)) {
    const displayedChange = roundedMovementValue(asset.change);
    const directionText = displayedChange > 0 ? '上涨' : displayedChange < 0 ? '下跌' : '持平';
    const directionIcon = document.createElement('i');
    directionIcon.className = displayedChange > 0
      ? 'ri-arrow-up-line'
      : displayedChange < 0
        ? 'ri-arrow-down-line'
        : 'ri-subtract-line';
    directionIcon.setAttribute('aria-hidden', 'true');
    changeLabel.replaceChildren(
      directionIcon,
      document.createTextNode(`${Math.abs(displayedChange).toFixed(2)}%${asset.cached ? ' · 最近' : ''}`)
    );
    changeLabel.className = movementTone(displayedChange);
    accessibleChange = `${directionText} ${Math.abs(displayedChange).toFixed(2)}%${asset.cached ? '，最近数据' : ''}`;
  } else {
    changeLabel.textContent = asset.cached ? '最近价格' : asset.status;
    changeLabel.className = '';
  }
  const session = renderMarketSession(asset);
  const sessionText = session ? `，美股${session.full}` : '';
  const priceText = Number.isFinite(asset.price) ? btcMoney.format(asset.price) : '价格暂不可用';
  document.querySelector('.btc-ticker').setAttribute('aria-label', `${asset.name} ${priceText}，${asset.basis}${accessibleChange}${sessionText}，点击查看下一个标的`);
  document.querySelector('.btc-ticker').title = `${asset.name}/USD 实时行情；${asset.basis}涨跌幅${session ? `；美股${session.full}` : ''}`;
}

function setMarketData(symbol, price, change, cached = false, status = '暂不可用', basis, series = []) {
  const asset = marketAssets.find(item => item.symbol === symbol);
  if (!asset) return;
  if (basis) asset.basis = basis;
  asset.price = Number.isFinite(price) ? price : null;
  asset.change = Number.isFinite(change) ? change : null;
  if (Array.isArray(series) && series.length > 1) asset.series = series.filter(Number.isFinite);
  asset.cached = cached;
  asset.status = Number.isFinite(price) ? '' : status;
  if (marketAssets[currentMarketIndex] === asset) renderMarketTicker(asset);
  // 顶部 ticker 一次只画当前轮播的那一个，但「快捷添加」要三个同时展示最新
  // 价格——这三个各自的 60 秒轮询互不同步，只有这里（价格真正写入的地方）
  // 才知道该刷新了。#portfolio-app.hidden 只在「还没解锁过」时为 true，
  // 用它当门槛能避免用户压根没打开过投资组合时也做这次渲染。
  if (!document.querySelector('#portfolio-app').hidden) renderHoldings();
}

// 切换动画有 150ms 的淡出等待。连点时若不拦，多个 setTimeout 会叠在一起，
// 索引连跳、动画互相打断。150ms 短到不会让人觉得按钮没反应。
let marketTransitioning = false;

function showNextMarket() {
  if (marketTransitioning) return;
  marketTransitioning = true;
  const content = document.querySelector('#market-content');
  content.classList.add('is-leaving');
  setTimeout(() => {
    currentMarketIndex = (currentMarketIndex + 1) % marketAssets.length;
    renderMarketTicker(marketAssets[currentMarketIndex]);
    content.classList.add('is-resetting', 'is-entering');
    content.classList.remove('is-leaving');
    void content.offsetHeight;
    content.classList.remove('is-resetting');
    requestAnimationFrame(() => content.classList.remove('is-entering'));
    marketTransitioning = false;
  }, 150);
}

function getBeijingDayStartUnix() {
  const beijingNow = new Date(Date.now() + 8 * 60 * 60 * 1000);
  return Math.floor((Date.UTC(
    beijingNow.getUTCFullYear(),
    beijingNow.getUTCMonth(),
    beijingNow.getUTCDate()
  ) - 8 * 60 * 60 * 1000) / 1000);
}

async function updateBitcoinPrice() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const dayStart = getBeijingDayStartUnix();
    const now = Math.floor(Date.now() / 1000);
    const weekStart = now - 7 * 24 * 60 * 60;
    const response = await fetch(`https://api.coingecko.com/api/v3/coins/bitcoin/market_chart/range?vs_currency=usd&from=${weekStart}&to=${now}`, { signal: controller.signal, cache: 'no-store' });
    if (!response.ok) throw new Error('Bitcoin price request failed');
    const data = await response.json();
    const prices = Array.isArray(data?.prices) ? data.prices : [];
    const series = prices.map(point => Number(point?.[1])).filter(value => Number.isFinite(value) && value > 0);
    let openingPrice = NaN;
    for (const point of prices) {
      if (Number(point?.[0]) > dayStart * 1000) break;
      if (Number.isFinite(Number(point?.[1]))) openingPrice = Number(point[1]);
    }
    const price = Number(prices.at(-1)?.[1]);
    if (!Number.isFinite(price) || price <= 0 || !Number.isFinite(openingPrice) || openingPrice <= 0) throw new Error('Invalid Bitcoin price');
    const change = ((price - openingPrice) / openingPrice) * 100;
    localStorage.setItem('retirement-calculator-btc', JSON.stringify({ price, change, series, dayStart, savedAt: Date.now() }));
    setMarketData('BTC', price, change, false, '暂不可用', undefined, series);
  } catch (error) {
    try {
      const cached = JSON.parse(localStorage.getItem('retirement-calculator-btc') || 'null');
      if (cached?.price) {
        const cachedChange = Number(cached.dayStart) === getBeijingDayStartUnix() ? Number(cached.change) : NaN;
        setMarketData('BTC', Number(cached.price), cachedChange, true, '暂不可用', undefined, cached.series);
      }
      else setMarketData('BTC', NaN, NaN);
    } catch (cacheError) {
      setMarketData('BTC', NaN, NaN);
    }
  } finally {
    clearTimeout(timeout);
  }
}

function saveStockQuote(symbol, price, change, basis = '北京时间今日', series = []) {
  localStorage.setItem(`retirement-calculator-${symbol.toLowerCase()}`, JSON.stringify({ price, change, series, basis, dayStart: getBeijingDayStartUnix(), savedAt: Date.now() }));
  setMarketData(symbol, price, change, false, '暂不可用', basis, series);
}

function restoreCachedStockPrices() {
  for (const symbol of ['MSTR', 'QQQ']) {
    try {
      const cached = JSON.parse(localStorage.getItem(`retirement-calculator-${symbol.toLowerCase()}`) || 'null');
      if (cached?.price) {
        // A Beijing-day change is stale once the Beijing date rolls over.
        const sameDay = Number(cached.dayStart) === getBeijingDayStartUnix();
        setMarketData(symbol, Number(cached.price), sameDay ? Number(cached.change) : NaN, true, '暂不可用', cached.basis, cached.series);
      }
      else setMarketData(symbol, NaN, NaN);
    } catch (cacheError) {
      setMarketData(symbol, NaN, NaN);
    }
  }
}

// Beijing-day basis, matching the BTC ticker: change is measured from the last
// trade at or before Beijing midnight. The API returns the latest five trading
// days so the portfolio sparkline consistently represents one trading week.
async function fetchBeijingQuote(symbol) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    // 同源代理（见 src/index.js）。原来借道 corsproxy.io，但那个公共代理在公网域名
    // 下被 Yahoo 稳定 403，害得涨跌基准一直降级成「较前收盘」。走自己的 Worker 就
    // 没有 CORS 问题，也不看第三方限流的脸色。
    // 注：本地用 http.server 预览时没有这个端点，会 404 → 抛错 → 自动走下面的
    // TradingView 备用链路，所以本地开发依然能显示报价，只是基准是「较前收盘」。
    const response = await fetch(`/api/quote?symbol=${encodeURIComponent(symbol)}`, { signal: controller.signal, cache: 'no-store' });
    if (!response.ok) throw new Error(`${symbol} quote request failed`);
    const data = await response.json();
    const result = data?.chart?.result?.[0];
    const price = Number(result?.meta?.regularMarketPrice);
    const timestamps = Array.isArray(result?.timestamp) ? result.timestamp : [];
    const closes = result?.indicators?.quote?.[0]?.close ?? [];
    const series = closes.filter(Number.isFinite).map(Number).slice(-80);
    const dayStart = getBeijingDayStartUnix();
    let reference = NaN;
    for (let i = 0; i < timestamps.length; i++) {
      if (timestamps[i] > dayStart) break;
      if (Number.isFinite(closes[i])) reference = closes[i];
    }
    // No bar before midnight in range (e.g. Sunday): price hasn't moved this
    // Beijing day, so the flat last close is the honest reference.
    if (!Number.isFinite(reference)) reference = price;
    if (!Number.isFinite(price) || price <= 0 || reference <= 0) throw new Error(`Invalid ${symbol} data`);
    return { symbol, price, change: ((price - reference) / reference) * 100, series };
  } finally {
    clearTimeout(timeout);
  }
}

// Fallback only — TradingView can't give a Beijing-day basis, so its change is
// vs previous close and the ticker relabels itself accordingly.
const TRADINGVIEW_TICKERS = {
  MSTR: 'NASDAQ:MSTR',
  QQQ: 'NASDAQ:QQQ',
  AAPL: 'NASDAQ:AAPL',
  VOO: 'AMEX:VOO'
};

async function fetchTradingViewQuotes(symbols = ['MSTR', 'QQQ']) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const requests = symbols.map(symbol => ({ symbol, ticker: TRADINGVIEW_TICKERS[symbol] })).filter(item => item.ticker);
    if (requests.length !== symbols.length) throw new Error('Unsupported TradingView symbol');
    // No Content-Type header on purpose: application/json makes this a preflighted
    // request, and TradingView's scanner rejects the preflight. Omitting it leaves a
    // CORS-safelisted text/plain body, which the endpoint parses fine.
    const response = await fetch('https://scanner.tradingview.com/america/scan', {
      method: 'POST',
      body: JSON.stringify({
        symbols: { tickers: requests.map(item => item.ticker), query: { types: [] } },
        columns: ['close', 'change']
      }),
      signal: controller.signal,
      cache: 'no-store'
    });
    if (!response.ok) throw new Error('Stock price request failed');
    const data = await response.json();
    const rows = Array.isArray(data?.data) ? data.data : [];
    return requests.map(({ symbol, ticker }) => {
      const row = rows.find(item => item?.s === ticker);
      const price = Number(row?.d?.[0]);
      const change = Number(row?.d?.[1]);
      if (!Number.isFinite(price) || price <= 0 || !Number.isFinite(change)) throw new Error(`Invalid ${symbol} price`);
      return { symbol, price, change };
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function updateStockPrices() {
  try {
    const quotes = await Promise.all([fetchBeijingQuote('MSTR'), fetchBeijingQuote('QQQ')]);
    quotes.forEach(quote => saveStockQuote(quote.symbol, quote.price, quote.change, '北京时间今日', quote.series));
  } catch (error) {
    try {
      const quotes = await fetchTradingViewQuotes();
      quotes.forEach(quote => saveStockQuote(quote.symbol, quote.price, quote.change, '较前收盘'));
    } catch (fallbackError) {
      restoreCachedStockPrices();
    }
  }
}

function clockLabel(date = new Date()) {
  return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
}

function renderCnyValues() {
  const convert = value => state.usdCny ? metricCny(value * state.usdCny) : '¥—';
  document.querySelector('#daily-profit-cny').textContent = convert(currentReturns.daily);
  document.querySelector('#monthly-profit-cny').textContent = convert(currentReturns.monthly);
  document.querySelector('#yearly-profit-cny').textContent = convert(currentReturns.yearly);
  document.querySelector('#chart-total-cny').textContent = `≈${convert(currentReturns.chartTotal)}`;
}

// One request feeds both tabs — the endpoint returns every currency at once,
// so the converter costs no extra network.
async function updateExchangeRate() {
  const rateLabel = document.querySelector('#fx-rate');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch('https://open.er-api.com/v6/latest/USD', { signal: controller.signal, cache: 'no-store' });
    if (!response.ok) throw new Error('Exchange rate request failed');
    const data = await response.json();
    const rate = Number(data?.rates?.CNY);
    if (!Number.isFinite(rate) || rate <= 0) throw new Error('Invalid exchange rate');
    const perUsd = {};
    for (const code of FX_CODES) {
      const value = Number(data?.rates?.[code]);
      if (Number.isFinite(value) && value > 0) perUsd[code] = value;
    }
    state.usdCny = rate;
    const savedAt = Date.now();
    localStorage.setItem('wealthly-usd-cny', JSON.stringify({ rate, perUsd, savedAt }));
    rateLabel.textContent = `1 USD = ${rate.toFixed(4)} CNY · 更新于 ${clockLabel()}`;
    renderCnyValues();
    setFxRates(perUsd, savedAt);
  } catch (error) {
    const cached = JSON.parse(localStorage.getItem('wealthly-usd-cny') || 'null');
    if (cached?.rate) {
      state.usdCny = Number(cached.rate);
      const savedAt = Number(cached.savedAt);
      const stamp = Number.isFinite(savedAt) ? new Date(savedAt) : undefined;
      rateLabel.textContent = `1 USD = ${state.usdCny.toFixed(4)} CNY · 更新于 ${clockLabel(stamp)}`;
      renderCnyValues();
      if (cached.perUsd) setFxRates(cached.perUsd, savedAt, true);
    } else {
      rateLabel.textContent = 'USD/CNY 汇率暂时无法获取';
      renderFxRows();
    }
  } finally {
    clearTimeout(timeout);
  }
}

/* ── Currency converter ─────────────────────────────────── */

const FX_CODES = ['CNY', 'USD', 'THB', 'MYR'];
const FX_FLAGS = { CNY: 'flags/CN.svg', USD: 'flags/US.svg', THB: 'flags/TH.svg', MYR: 'flags/MY.svg' };
const fxState = { base: 'CNY', amount: 1000, perUsd: null, savedAt: null, cached: false };
const fxAmountInput = document.querySelector('#fx-amount');
const fxResults = document.querySelector('#fx-results');

const fxAmountFormat = new Intl.NumberFormat('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
// Four significant-ish decimals keeps sub-unit pairs (1 CNY = 0.1483 USD) legible.
const fxRateFormat = new Intl.NumberFormat('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 });

function fxConvert(amount, from, to) {
  if (!fxState.perUsd) return NaN;
  const fromRate = fxState.perUsd[from], toRate = fxState.perUsd[to];
  if (!Number.isFinite(fromRate) || !Number.isFinite(toRate) || fromRate <= 0) return NaN;
  return (amount / fromRate) * toRate;
}

function setFxRates(perUsd, savedAt, cached = false) {
  fxState.perUsd = perUsd;
  fxState.savedAt = savedAt;
  fxState.cached = cached;
  renderFxRows();
}

function renderFxRows() {
  const targets = FX_CODES.filter(code => code !== fxState.base);
  fxResults.replaceChildren(...targets.map(code => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'fx-row';
    row.dataset.code = code;

    const flag = document.createElement('img');
    flag.className = 'fx-flag';
    flag.src = FX_FLAGS[code];
    flag.alt = '';
    flag.width = 28; flag.height = 20;

    const body = document.createElement('div');
    body.className = 'fx-row-body';

    const converted = fxConvert(fxState.amount, fxState.base, code);
    const value = document.createElement('div');
    value.className = 'fx-row-value';
    value.textContent = Number.isFinite(converted) ? fxAmountFormat.format(converted) : '—';

    const unit = fxConvert(1, fxState.base, code);
    const rate = document.createElement('div');
    rate.className = 'fx-row-rate';
    rate.textContent = Number.isFinite(unit)
      ? `1 ${fxState.base} = ${fxRateFormat.format(unit)} ${code}`
      : '汇率暂不可用';

    const label = document.createElement('span');
    label.className = 'fx-row-code';
    label.textContent = code;

    body.append(value, rate);
    row.append(flag, body, label);
    row.setAttribute('aria-label', `切换到 ${code}，当前 ${value.textContent} ${code}`);
    return row;
  }));

  const updated = document.querySelector('#fx-updated');
  if (!fxState.perUsd) updated.textContent = '汇率暂时无法获取';
  else {
    const stamp = Number.isFinite(fxState.savedAt) ? new Date(fxState.savedAt) : undefined;
    updated.textContent = `${fxState.cached ? '最近' : '实时'}汇率 · 更新于 ${clockLabel(stamp)}`;
  }
}

function readFxAmount() {
  const parsed = Number(fxAmountInput.value.replace(/,/g, ''));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

// Swapping carries the converted value across, so the money keeps its worth and
// only its denomination changes.
function swapFxBase(code) {
  // 换基只换单位，不换数字。原来会把金额折算过去以保持总价值不变（1000 CNY 点
  // USD 变成 148.30 USD），但那等于把用户刚敲进去的数字冲掉了 —— 在这个页面上
  // 点另一张卡片的意图是「用同一个数换种货币再算一遍」，不是「换个单位表示同
  // 一笔钱」。所以 fxState.amount 和输入框都原样保留。
  fxState.base = code;
  document.querySelector('#fx-base-flag').src = FX_FLAGS[code];
  document.querySelector('#fx-base-code').textContent = code;
  renderFxRows();
}

fxAmountInput.addEventListener('input', () => {
  fxState.amount = readFxAmount();
  renderFxRows();
});
fxAmountInput.addEventListener('blur', () => {
  if (fxAmountInput.value.trim() !== '') fxAmountInput.value = fxAmountFormat.format(fxState.amount);
});
fxResults.addEventListener('click', event => {
  const row = event.target.closest('.fx-row');
  if (row) swapFxBase(row.dataset.code);
});

/* ── Tab navigation ─────────────────────────────────────── */

const tabButtons = [...document.querySelectorAll('.tabbar-item')];

function activateTab(name) {
  tabButtons.forEach(button => {
    const selected = button.dataset.tab === name;
    button.setAttribute('aria-selected', String(selected));
    document.querySelector(`#${button.getAttribute('aria-controls')}`).hidden = !selected;
  });
  localStorage.setItem('jiujiu-active-tab', name);
  // The canvas has no layout size while hidden, so it must redraw on reveal.
  if (name === 'retirement') requestAnimationFrame(() => { drawChart(); fitMetricNumbers(); });
}

tabButtons.forEach(button => button.addEventListener('click', () => activateTab(button.dataset.tab)));

// Fritsch–Carlson monotone cubic tangents — matches Recharts' type="monotone".
// A naive midpoint bezier forces a horizontal tangent at every point, which makes
// exponential data visibly ripple.
function monotoneTangents(points) {
  const n = points.length;
  if (n < 2) return [0];
  const d = [];
  for (let i = 0; i < n - 1; i++) {
    const dx = points[i + 1].x - points[i].x;
    d.push(dx === 0 ? 0 : (points[i + 1].y - points[i].y) / dx);
  }
  const m = [d[0]];
  for (let i = 1; i < n - 1; i++) m.push((d[i - 1] + d[i]) / 2);
  m.push(d[n - 2]);
  for (let i = 0; i < n - 1; i++) {
    if (d[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
    const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
    if (s > 9) { const t = 3 / Math.sqrt(s); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i]; }
  }
  return m;
}

// 轴域对齐到刻度，而不是让刻度去迁就数据极值。
//
// 原来定义域取 [数据min, 数据max]，刻度只能取这个区间「之内」的整数，于是最高
// 刻度永远悬在半空 —— 数据到 12,682 时顶格只有 12K，上方白白空掉一大截，整根
// 轴看起来是沉在底部的。
//
// 现在反过来：先选步长，再把定义域向外扩到整刻度。首尾刻度正好落在绘图区的上下
// 边缘，标签自然均匀铺满纵向空间，最高刻度与图表顶部对齐。
//
// 单纯向外取整的代价是留白可能过大（步长 5000 时 25,182 会被顶到 30,000）。所以
// 在候选步长里挑「刻度数合理且留白最少」的那个，兼顾整数和贴合度。
function niceScale(min, max, target = 4) {
  if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) {
    return { min, max: min + 1, step: 1, ticks: [] };
  }
  const range = max - min;
  const mag = Math.pow(10, Math.floor(Math.log10(range / target)));
  let best = null;
  // 步长候选给得密一些。只有 1/2/5/10 的话，25,182 这种数只能被顶到 30,000，
  // 白白空掉四分之一高度；补上 3 和 4 之后就能落在 27,000。
  for (const m of [1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10]) {
    const step = m * mag;
    const lo = Math.floor(min / step) * step;
    const hi = Math.ceil(max / step) * step;
    const count = Math.round((hi - lo) / step) + 1;
    // 少于 3 条读不出趋势；多于 7 条在这个高度上会挤成一片。
    if (count < 3 || count > 7) continue;
    // 标签必须两两可区分。步长细到低于显示精度时，相邻刻度会被格式化成同一串
    // 字（10,000 与 10,050 都是 "10K"），那种候选一律淘汰。
    const format = tickFormatter(step, Math.max(Math.abs(lo), Math.abs(hi)));
    const labels = [];
    for (let k = 0; k < count; k++) labels.push(format(lo + k * step));
    if (new Set(labels).size !== count) continue;
    // 留白按占比算（跨量级可比），再对刻度数加一点惩罚：留白相当时取标签更少的
    // 那个，否则会为了省几个像素塞一堆标签。
    const score = ((min - lo) + (hi - max)) / range + count * 0.02;
    if (!best || score < best.score) best = { step, lo, hi, score };
  }
  // 候选都不合适时退回等分，宁可刻度不整也不能不画。
  if (!best) best = { step: range / target, lo: min, hi: max };
  const ticks = [];
  for (let v = best.lo; v <= best.hi + best.step * 0.001; v += best.step) ticks.push(v);
  return { min: best.lo, max: best.hi, step: best.step, ticks };
}


// 一根轴共用一个单位和一个小数位数，由「最大刻度」定单位、「步长」定精度。
//
// 两个都不能省。单位若按每个值各自的量级选，轴上会混出 [5K 6K … 1M 1.1M]；
// 精度若只看量级，10,000 和 10,050 会双双变成 "10K"，并排出现两个一样的标签。
function tickFormatter(step, maxAbs) {
  const UNITS = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K'], [1, '']];
  let index = UNITS.findIndex(([size]) => maxAbs >= size);
  if (index < 0) index = UNITS.length - 1;
  // 先按最大刻度选紧凑单位，再往下退到步长在该单位里至少有两位有效精度为止。
  // 不退的话，步长细过显示精度时 10,000 和 10,002 会双双变成 "10K" —— 而且
  // 更糟的是，唯一性检查会把所有细步长全毙掉，逼着轴去用最粗的那档，白白空出
  // 四成高度。单位降级同时解决重复标签和留白两件事。
  while (index < UNITS.length - 1 && Math.abs(step) / UNITS[index][0] < 0.01) index++;
  const [unit, suffix] = UNITS[index];
  const stepInUnit = Math.abs(step) / unit;
  const decimals = stepInUnit >= 1 ? 0 : stepInUnit >= 0.1 ? 1 : 2;
  return value => {
    if (value === 0) return '0';   // "0M" 读着别扭，零就是零
    const text = (value / unit).toFixed(decimals);
    // 只在有小数点时去尾随零，否则 "10" 会被削成 "1"、"800" 削成 "8"。
    return (text.includes('.') ? text.replace(/\.?0+$/, '') : text) + suffix;
  };
}



function amountAt(years) {
  const r = state.rate / 100;
  return state.type === 'compound'
    ? state.principal * Math.pow(1 + r, years)
    : state.principal * (1 + r * years);
}

function readInputs() {
  state.principal = Math.max(1, Number(principalInput.value.replace(/,/g, '')) || 1);
  state.rate = Math.max(0, Number(rateInput.value) || 0);
  state.type = form.elements.interest.value;
}

function updateQuickAmountState() {
  const currentAmount = Number(principalInput.value.replace(/,/g, '')) || 0;
  quickAmountButtons.forEach(button => {
    button.setAttribute('aria-pressed', String(Number(button.dataset.amount) === currentAmount));
  });
}

function savePreferences() {
  readInputs();
  localStorage.setItem(preferencesKey, JSON.stringify({
    principal: state.principal,
    rate: state.rate,
    type: state.type,
    period: state.period
  }));
}

function loadPreferences() {
  try {
    const saved = JSON.parse(localStorage.getItem(preferencesKey) || 'null');
    if (!saved) return;
    if (Number.isFinite(Number(saved.principal)) && Number(saved.principal) >= 1) state.principal = Number(saved.principal);
    if (Number.isFinite(Number(saved.rate)) && Number(saved.rate) >= 0) state.rate = Number(saved.rate);
    if (['compound', 'simple'].includes(saved.type)) state.type = saved.type;
    if (['day', 'month', 'year'].includes(saved.period)) state.period = saved.period;
    principalInput.value = state.principal.toLocaleString('en-US', { maximumFractionDigits: 2 });
    rateInput.value = state.rate.toFixed(2);
    rateSlider.value = Math.min(30, Math.max(0.01, state.rate));
    form.elements.interest.value = state.type;
    periodButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.period === state.period)));
  } catch (error) {
    localStorage.removeItem(preferencesKey);
  }
}

function updateSliderFill() {
  const min = Number(rateSlider.min), max = Number(rateSlider.max);
  const progress = ((Number(rateSlider.value) - min) / (max - min)) * 100;
  rateSlider.style.setProperty('--progress', `${progress}%`);
}

// One shared size across the row — fitting each card independently produces
// three different type sizes and breaks the rhythm.
function fitMetricNumbers() {
  const elements = [...document.querySelectorAll('.metric strong')];
  if (!elements.length) return;
  elements.forEach(element => { element.style.fontSize = ''; });
  const base = Number.parseFloat(getComputedStyle(elements[0]).fontSize);
  if (!elements.some(element => element.clientWidth && element.scrollWidth > element.clientWidth)) return;
  let fontSize = base;
  while (fontSize > 10 && elements.some(element => element.clientWidth && element.scrollWidth > element.clientWidth)) {
    fontSize -= 0.5;
    elements.forEach(element => { element.style.fontSize = `${fontSize}px`; });
  }
}

function renderResults() {
  readInputs();
  const daily = amountAt(1 / 365) - state.principal;
  const monthly = amountAt(1 / 12) - state.principal;
  const yearly = amountAt(1) - state.principal;
  currentReturns = { ...currentReturns, daily, monthly, yearly };
  document.querySelector('#daily-profit').textContent = metricMoney(daily);
  document.querySelector('#monthly-profit').textContent = metricMoney(monthly);
  document.querySelector('#yearly-profit').textContent = metricMoney(yearly);
  requestAnimationFrame(fitMetricNumbers);
  renderCnyValues();
  drawChart();
}

function chartConfig() {
  if (state.period === 'day') return { count: 366, years: i => i / 365, caption: '365 天预测', labels: i => i === 0 ? '现在' : i === 365 ? '365天' : '' };
  if (state.period === 'month') return { count: 37, years: i => i / 12, caption: '36 个月预测', labels: i => i === 0 ? '现在' : i === 12 ? '12月' : i === 24 ? '24月' : i === 36 ? '36月' : '' };
  return { count: 13, years: i => i, caption: '12 年预测', labels: i => [0,3,6,9,12].includes(i) ? (i === 0 ? '现在' : `${i}年`) : '' };
}

function drawChart() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const rect = canvas.getBoundingClientRect();
  const themeStyles = getComputedStyle(document.documentElement);
  const chartLabel = themeStyles.getPropertyValue('--ink-40').trim();
  const chartInk = themeStyles.getPropertyValue('--ink').trim();
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  const w = rect.width, h = rect.height;
  const pad = { top: 8, right: 8, bottom: 24, left: 44 };
  const config = chartConfig();
  const data = Array.from({ length: config.count }, (_, i) => amountAt(config.years(i)));
  const scale = niceScale(Math.min(...data), Math.max(...data));
  const spread = Math.max(scale.max - scale.min, 1);
  const x = i => pad.left + i / (data.length - 1) * (w - pad.left - pad.right);
  // 定义域来自 scale 而非数据极值，所以 y(scale.max) 正好等于 pad.top，
  // 最高刻度贴着绘图区顶部。
  const y = v => pad.top + (1 - (v - scale.min) / spread) * (h - pad.top - pad.bottom - 8);
  chartPoints = data.map((value, i) => ({ x: x(i), y: y(value), value, label: i === 0 ? '现在' : state.period === 'day' ? `第 ${i} 天` : state.period === 'month' ? `第 ${i} 月` : `第 ${i} 年` }));

  // SnowUI charts: no gridlines, no axis lines, no tick marks, no area fill.
  // A single solid black monotone line; only the labels remain.
  const tangents = monotoneTangents(chartPoints);
  ctx.beginPath();
  ctx.moveTo(chartPoints[0].x, chartPoints[0].y);
  for (let i = 0; i < chartPoints.length - 1; i++) {
    const p0 = chartPoints[i], p1 = chartPoints[i + 1], dx = (p1.x - p0.x) / 3;
    ctx.bezierCurveTo(p0.x + dx, p0.y + tangents[i] * dx, p1.x - dx, p1.y - tangents[i + 1] * dx, p1.x, p1.y);
  }
  ctx.strokeStyle = chartInk; ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke();

  ctx.fillStyle = chartLabel;
  ctx.font = '400 12px Inter, system-ui, sans-serif';

  ctx.textBaseline = 'bottom'; ctx.textAlign = 'center';
  data.forEach((_, i) => {
    const label = config.labels(i);
    if (!label) return;
    ctx.textAlign = i === 0 ? 'left' : i === data.length - 1 ? 'right' : 'center';
    ctx.fillText(label, x(i), h - 4);
  });

  ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
  const formatTick = tickFormatter(scale.step, Math.max(Math.abs(scale.min), Math.abs(scale.max)));
  scale.ticks.forEach(value => ctx.fillText(formatTick(value), 0, y(value)));

  const final = data.at(-1), profit = final - state.principal;
  const changePercent = state.principal ? (profit / state.principal) * 100 : 0;
  const displayedProfit = roundedMovementValue(profit);
  const displayedPercent = roundedMovementValue(changePercent);
  const sign = displayedProfit > 0 ? '+' : '';
  currentReturns.chartTotal = final;
  document.querySelector('#chart-total').textContent = metricMoney(final);
  document.querySelector('#chart-delta').textContent = `${sign}${metricMoney(displayedProfit)}`;
  document.querySelector('#chart-percent').textContent = `${displayedPercent > 0 ? '+' : ''}${displayedPercent.toFixed(2)}%`;
  document.querySelector('#chart-change').className = `chart-sub ${movementTone(displayedProfit)}`;
  renderCnyValues();
  canvas.setAttribute('aria-label', `${config.caption}，预计总资产从 ${money.format(state.principal)} 增长至 ${money.format(final)}`);
}

function showTooltip(event) {
  if (!chartPoints.length) return;
  const rect = canvas.getBoundingClientRect();
  const clientX = event.touches ? event.touches[0].clientX : event.clientX;
  const localX = clientX - rect.left;
  const point = chartPoints.reduce((a, b) => Math.abs(b.x - localX) < Math.abs(a.x - localX) ? b : a);
  tooltip.hidden = false;
  const cnyText = state.usdCny ? cnyMoney.format(point.value * state.usdCny) : 'CNY —';
  const pointChange = state.principal ? ((point.value - state.principal) / state.principal) * 100 : 0;
  const displayedPointChange = roundedMovementValue(pointChange);
  const pointChangeText = `${displayedPointChange > 0 ? '+' : ''}${displayedPointChange.toFixed(2)}%`;
  tooltip.textContent = `${point.label} · ${money.format(point.value)}\n${cnyText} · 涨跌 ${pointChangeText}`;
  const tooltipWidth = tooltip.offsetWidth;
  const tooltipHeight = tooltip.offsetHeight;
  const edgeGap = 4;
  const minLeft = tooltipWidth / 2 + edgeGap;
  const maxLeft = rect.width - tooltipWidth / 2 - edgeGap;
  tooltip.style.left = `${Math.max(minLeft, Math.min(maxLeft, point.x))}px`;
  tooltip.style.top = `${point.y}px`;
  tooltip.style.transform = point.y >= tooltipHeight + 12
    ? 'translate(-50%, calc(-100% - 10px))'
    : 'translate(-50%, 10px)';
}

principalInput.addEventListener('blur', () => {
  const value = Math.max(1, Number(principalInput.value.replace(/,/g, '')) || 1);
  principalInput.value = value.toLocaleString('en-US', { maximumFractionDigits: 2 });
  updateQuickAmountState();
});
principalInput.addEventListener('change', () => { savePreferences(); updateQuickAmountState(); });
quickAmountButtons.forEach(button => button.addEventListener('click', () => {
  const amount = Number(button.dataset.amount);
  principalInput.value = amount.toLocaleString('en-US');
  updateQuickAmountState();
  savePreferences();
  renderResults();
}));
rateSlider.addEventListener('input', () => { rateInput.value = Number(rateSlider.value).toFixed(2); updateSliderFill(); savePreferences(); });
rateInput.addEventListener('input', () => { rateSlider.value = Math.min(30, Number(rateInput.value) || 0); updateSliderFill(); });
rateInput.addEventListener('change', savePreferences);
form.elements.interest.forEach(input => input.addEventListener('change', savePreferences));
form.addEventListener('submit', event => { event.preventDefault(); savePreferences(); renderResults(); document.querySelector('.results').scrollIntoView({ behavior: reducedMotion.matches ? 'auto' : 'smooth', block: 'start' }); });
periodButtons.forEach(button => button.addEventListener('click', () => { state.period = button.dataset.period; periodButtons.forEach(b => b.setAttribute('aria-pressed', String(b === button))); savePreferences(); drawChart(); }));
canvas.addEventListener('mousemove', showTooltip);
canvas.addEventListener('touchmove', showTooltip, { passive: true });
canvas.addEventListener('mouseleave', () => tooltip.hidden = true);
canvas.addEventListener('touchend', () => tooltip.hidden = true);
window.addEventListener('resize', () => {
  drawChart();
  requestAnimationFrame(fitMetricNumbers);
});

initializeTheme();
loadPreferences();
updateQuickAmountState();
updateSliderFill();
renderResults();
fxState.amount = readFxAmount();
renderFxRows();
const savedTab = localStorage.getItem('jiujiu-active-tab');
activateTab(['retirement', 'portfolio', 'fx'].includes(savedTab) ? savedTab : 'retirement');
updateExchangeRate();
setInterval(updateExchangeRate, 15 * 60 * 1000);
renderMarketTicker(marketAssets[0]);
updateBitcoinPrice();
setInterval(updateBitcoinPrice, 60 * 1000);
updateStockPrices();
setInterval(updateStockPrices, 60 * 1000);
function syncMarketRotation() {
  if (reducedMotion.matches) {
    clearInterval(marketRotationId);
    marketRotationId = null;
  } else if (marketRotationId === null) {
    marketRotationId = setInterval(showNextMarket, 5 * 1000);
  }
}
syncMarketRotation();
reducedMotion.addEventListener('change', syncMarketRotation);

// 点击行情区切到下一个标的。
// 对开启了「减弱动态效果」的用户尤其有用 —— 自动轮播对他们是关闭的，
// 手动点击是他们看到 MSTR/QQQ 的唯一途径。
document.querySelector('.btc-ticker').addEventListener('click', () => {
  showNextMarket();
  // 重置计时：手动切换后应当有完整的 5 秒停留，而不是被残余的定时器
  // 立刻又推走。轮播关闭时（marketRotationId 为 null）不要顺手打开。
  if (marketRotationId !== null) {
    clearInterval(marketRotationId);
    marketRotationId = setInterval(showNextMarket, 5 * 1000);
  }
});

// 时段边界（04:00 / 09:30 / 16:00 / 20:00）不会等行情刷新才到来，每分钟自己对一次表。
setInterval(() => renderMarketSession(marketAssets[currentMarketIndex]), 60000);

// ══════════════════════════════════════════════════════════════════════
// 投资组合 — 持仓追踪
//
// 账号系统还没接：需要先建一个 Supabase 项目（免费版含 Google/邮箱登录 +
// Postgres，行级安全策略能保证用户只读到自己的数据），那一步要用户自己去
// 注册账号、拿密钥，不是这里能做的事。所以先用 localStorage 落一个完整可用
// 的本地版 —— 加/改/删、算盈亏、拉实时价，一样不少；接入账号后，把下面
// loadHoldings/saveHoldings 换成远程读写，其余逻辑不用动。
// ══════════════════════════════════════════════════════════════════════

const PORTFOLIO_KEY = 'jiujiucat-portfolio-holdings';
const PORTFOLIO_UNLOCKED_KEY = 'jiujiucat-portfolio-unlocked';
const PORTFOLIO_RECOMMEND_DISMISSED_KEY = 'jiujiucat-portfolio-recommend-dismissed';
const PORTFOLIO_MERGE_KEY = 'jiujiucat-portfolio-merge-same';
const HOLDING_KINDS = new Set(['market', 'interest', 'hybrid', 'dividend']);
const DAY_MS = 24 * 60 * 60 * 1000;
// 这三个已经被全局行情轮询覆盖（见 marketAssets），持仓用它们时直接读
// 现成的价格，不再单独发请求。
const GLOBAL_TICKER_SYMBOLS = new Set(['BTC', 'MSTR', 'QQQ']);
const ASSET_TYPE_LABELS = { EQUITY: '股票', ETF: 'ETF', CRYPTOCURRENCY: 'Crypto' };
const DIVIDEND_FREQUENCY_LABELS = {
  quarterly: '季度', monthly: '月度', semimonthly: '每月两次',
  semiannual: '半年', annual: '年度', irregular: '不固定'
};
const DIVIDEND_FREQUENCY_CONTROL_LABELS = {
  quarterly: '每季度一次', monthly: '每月一次', semimonthly: '每月两次',
  semiannual: '每半年一次', annual: '每年一次', irregular: '不固定'
};
// 本地 http.server 没有 Worker 路由。这里放一组 Yahoo Finance 的有效代码作为
// 开发预览后备；线上仍以 /api/search 的 Yahoo 实时搜索为准。
const FALLBACK_ASSETS = [
  ['AAPL', 'Apple Inc.', 'EQUITY', 'NASDAQ'],
  ['MSFT', 'Microsoft Corporation', 'EQUITY', 'NASDAQ'],
  ['NVDA', 'NVIDIA Corporation', 'EQUITY', 'NASDAQ'],
  ['AMZN', 'Amazon.com, Inc.', 'EQUITY', 'NASDAQ'],
  ['GOOGL', 'Alphabet Inc.', 'EQUITY', 'NASDAQ'],
  ['META', 'Meta Platforms, Inc.', 'EQUITY', 'NASDAQ'],
  ['TSLA', 'Tesla, Inc.', 'EQUITY', 'NASDAQ'],
  ['MSTR', 'Strategy Inc.', 'EQUITY', 'NASDAQ'],
  ['QQQ', 'Invesco QQQ Trust', 'ETF', 'NASDAQ'],
  ['SPY', 'SPDR S&P 500 ETF Trust', 'ETF', 'NYSEArca'],
  ['VOO', 'Vanguard S&P 500 ETF', 'ETF', 'NYSEArca'],
  ['BTC-USD', 'Bitcoin USD', 'CRYPTOCURRENCY', 'CCC'],
  ['ETH-USD', 'Ethereum USD', 'CRYPTOCURRENCY', 'CCC'],
  ['SOL-USD', 'Solana USD', 'CRYPTOCURRENCY', 'CCC'],
  ['BNB-USD', 'BNB USD', 'CRYPTOCURRENCY', 'CCC'],
  ['XRP-USD', 'XRP USD', 'CRYPTOCURRENCY', 'CCC'],
  ['DOGE-USD', 'Dogecoin USD', 'CRYPTOCURRENCY', 'CCC']
].map(([quoteSymbol, name, assetType, exchange]) => ({
  symbol: assetType === 'CRYPTOCURRENCY' ? quoteSymbol.replace(/-USD$/, '') : quoteSymbol,
  quoteSymbol, name, assetType, exchange
}));
const RECOMMENDED_ASSETS = [
  { symbol: 'VOO', quoteSymbol: 'VOO', name: 'Vanguard S&P 500 ETF', assetType: 'ETF', exchange: 'NYSEArca' },
  { symbol: 'AAPL', quoteSymbol: 'AAPL', name: 'Apple Inc.', assetType: 'EQUITY', exchange: 'NASDAQ' },
  { symbol: 'BTC', quoteSymbol: 'BTC-USD', name: 'Bitcoin', assetType: 'CRYPTOCURRENCY', exchange: 'CCC', icon: 'btc-icon.svg' }
];

function normalizeAsset(asset) {
  if (!asset) return null;
  const quoteSymbol = String(asset.quoteSymbol || asset.symbol || '').toUpperCase();
  if (!quoteSymbol) return null;
  const assetType = asset.assetType || (quoteSymbol.endsWith('-USD') ? 'CRYPTOCURRENCY' : 'EQUITY');
  return {
    symbol: String(asset.symbol || (assetType === 'CRYPTOCURRENCY' ? quoteSymbol.replace(/-USD$/, '') : quoteSymbol)).toUpperCase(),
    quoteSymbol,
    name: asset.name || quoteSymbol,
    assetType,
    exchange: asset.exchange || ''
  };
}

function normalizeDividendRecords(item) {
  const source = Array.isArray(item.dividendRecords)
    ? item.dividendRecords
    : (item.holdingKind === 'dividend' && item.dividendExDate && Number(item.dividendPerShare) > 0
      ? [{
          id: item.dividendRecordId || `d_${item.id || 'legacy'}_${item.dividendExDate}`,
          perShare: Number(item.dividendPerShare),
          quantity: Number(item.quantity) || 0,
          amount: (Number(item.quantity) || 0) * Number(item.dividendPerShare),
          frequency: item.dividendFrequency,
          exDate: item.dividendExDate,
          payDate: item.dividendPayDate,
          createdAt: item.createdAt || Date.now()
        }]
      : []);
  return source.map((record, index) => ({
    id: record.id || `d_${item.id || 'legacy'}_${record.exDate || index}`,
    perShare: Number(record.perShare) || 0,
    quantity: Number(record.quantity) || 0,
    amount: Number.isFinite(Number(record.amount))
      ? Number(record.amount)
      : (Number(record.quantity) || 0) * (Number(record.perShare) || 0),
    frequency: DIVIDEND_FREQUENCY_LABELS[record.frequency] ? record.frequency : 'irregular',
    exDate: record.exDate || '',
    payDate: record.payDate || '',
    createdAt: Number(record.createdAt) || Date.now()
  })).filter(record => record.exDate && record.perShare > 0 && record.amount >= 0);
}

function loadHoldings() {
  try {
    const parsed = JSON.parse(localStorage.getItem(PORTFOLIO_KEY) || '[]');
    return Array.isArray(parsed) ? parsed.map(item => {
      const dividendRecords = normalizeDividendRecords(item);
      return {
        ...item,
        ...normalizeAsset({
          symbol: item.symbol,
          quoteSymbol: item.quoteSymbol || (item.symbol === 'BTC' ? 'BTC-USD' : item.symbol),
          name: item.name,
          assetType: item.assetType,
          exchange: item.exchange
        }),
        holdingKind: HOLDING_KINDS.has(item.holdingKind) ? item.holdingKind : 'market',
        // “当前价格”曾允许手动覆盖实时行情。新版统一使用行情源，旧值不再参与计算。
        priceOverride: null,
        interestMode: item.interestMode === 'compound' ? 'compound' : 'simple',
        positionAdjustments: Array.isArray(item.positionAdjustments) ? item.positionAdjustments : [],
        dividendRecords,
        dividendRecordId: item.dividendRecordId || dividendRecords.at(-1)?.id || null
      };
    }) : [];
  } catch {
    return [];
  }
}
// updatedAt 是跨设备冲突的唯一裁判，所以只给「内容真的变了」的那几条盖章。
// 每次保存都全量盖章的话，A 设备上一条没碰过的持仓也会显得比 B 设备上刚编辑过
// 的同一条更新，回头就把真实修改覆盖掉了。
function holdingFingerprint(item) {
  return JSON.stringify({ ...item, updatedAt: null });
}

let holdingFingerprints = new Map();
function resetHoldingFingerprints() {
  holdingFingerprints = new Map(holdings.map(item => [item.id, holdingFingerprint(item)]));
}

function saveHoldings() {
  const now = Date.now();
  for (const item of holdings) {
    const print = holdingFingerprint(item);
    if (holdingFingerprints.get(item.id) !== print) item.updatedAt = now;
    holdingFingerprints.set(item.id, print);
  }
  localStorage.setItem(PORTFOLIO_KEY, JSON.stringify(holdings));
  queueCloudPush();
}

let holdings = loadHoldings();
resetHoldingFingerprints();
let editingHoldingId = null;
let holdingSheetTrigger = null;
let holdingSheetCloseTimer = null;
let profitSheetTrigger = null;
let profitSheetCloseTimer = null;
let profitSheetAction = null;
let profitSheetItems = [];
let selectedHoldingAsset = null;
let marketIncomeKindOverride = null;
let positionAdjustmentMode = 'add';
let dividendRecordsContext = [];
let dividendRecordsTrigger = null;
let dividendRecordsCloseTimer = null;
let pendingConfirmAction = null;
let assetSearchTrigger = null;
let assetSearchCloseTimer = null;
let assetSearchController = null;
let lastSubmittedAssetQuery = '';
let dividendFrequencyTrigger = null;
let dividendFrequencyCloseTimer = null;
// 持仓里任意代号（非 BTC/MSTR/QQQ）的抓取结果，键是代号。和 marketAssets
// 分开存，因为后者是给顶部轮播用的固定三项，这里是用户自己输入的任意集合。
const holdingPrices = new Map();

function isInterestHolding(holding) {
  return holding.holdingKind === 'interest' || holding.holdingKind === 'hybrid';
}

function isDividendHolding(holding) {
  return holding.holdingKind === 'dividend' && holding.assetType === 'EQUITY';
}

function holdingDividendRecords(holding) {
  return Array.isArray(holding.dividendRecords) ? holding.dividendRecords : [];
}

function confirmedDividendRecords(holding, timestamp = Date.now()) {
  const today = beijingDateString(timestamp);
  return holdingDividendRecords(holding).filter(record => record.exDate && record.exDate <= today);
}

function latestDividendRecord(holding) {
  return [...holdingDividendRecords(holding)].sort((a, b) => {
    const dateOrder = String(b.exDate).localeCompare(String(a.exDate));
    return dateOrder || Number(b.createdAt) - Number(a.createdAt);
  })[0] || null;
}

function syncHoldingDividendRecord(holding) {
  if (!isDividendHolding(holding) || !holding.dividendExDate || !(Number(holding.dividendPerShare) > 0)) return;
  if (!Array.isArray(holding.dividendRecords)) holding.dividendRecords = [];
  let record = holding.dividendRecords.find(item => item.id === holding.dividendRecordId);
  // 同一除息日视为修正；换了除息日则新增一条历史记录，避免覆盖上一次分红。
  if (record?.exDate && record.exDate !== holding.dividendExDate) record = null;
  if (!record) {
    record = { id: `d_${Date.now()}_${Math.random().toString(36).slice(2, 7)}` };
    holding.dividendRecords.push(record);
    holding.dividendRecordId = record.id;
  }
  // 已存在的股息记录冻结除息时的数量；后续加减仓只影响下一次分红。
  const quantity = record && Number(record.quantity) > 0
    ? Number(record.quantity)
    : (Number(holding.quantity) || 0);
  const perShare = Number(holding.dividendPerShare) || 0;
  Object.assign(record, {
    perShare,
    quantity,
    amount: quantity * perShare,
    frequency: holding.dividendFrequency,
    exDate: holding.dividendExDate,
    payDate: holding.dividendPayDate || '',
    createdAt: Number(record.createdAt) || Date.now()
  });
}

function beijingDateString(timestamp = Date.now()) {
  const date = new Date(timestamp + 8 * 60 * 60 * 1000);
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function formatPortfolioDate(value) {
  const [year, month, day] = String(value || '').split('-');
  return year && month && day ? `${year}/${month}/${day}` : '—';
}

function signedMoney(value) {
  if (!Number.isFinite(value)) return '$—';
  const displayedValue = roundedMovementValue(value);
  return `${displayedValue > 0 ? '+' : ''}${money.format(displayedValue)}`;
}

function roundedMovementValue(value) {
  return Number.isFinite(value) ? Number(value.toFixed(2)) : NaN;
}

function movementTone(value) {
  const displayedValue = roundedMovementValue(value);
  if (displayedValue > 0) return 'is-gain';
  if (displayedValue < 0) return 'is-loss';
  return 'is-flat';
}

function firstInterestSettlement(startDate) {
  const [year, month, day] = String(startDate || '').split('-').map(Number);
  if (![year, month, day].every(Number.isFinite)) return NaN;
  // 北京时间起息日次日 16:00，即 UTC 次日 08:00。
  return Date.UTC(year, month - 1, day + 1, 8, 0, 0, 0);
}

function settledInterestDays(holding, timestamp = Date.now()) {
  const firstSettlement = firstInterestSettlement(holding.interestStartDate);
  if (!Number.isFinite(firstSettlement) || timestamp < firstSettlement) return 0;
  return Math.floor((timestamp - firstSettlement) / DAY_MS) + 1;
}

function holdingInterestPrincipal(holding) {
  if (holding.holdingKind === 'interest') return Number(holding.principal) || 0;
  const quantity = Number(holding.quantity) || 0;
  const costPerShare = Number(holding.costPerShare) || 0;
  return quantity * costPerShare;
}

function holdingInterestForDays(holding, days) {
  const principal = holdingInterestPrincipal(holding);
  const annualRate = Number(holding.annualRate) / 100;
  const elapsedDays = Math.max(0, Number(days) || 0);
  if (!(principal > 0) || !(annualRate > 0) || elapsedDays === 0) return 0;
  if (holding.interestMode === 'compound') {
    return principal * (Math.pow(1 + annualRate / 365, elapsedDays) - 1);
  }
  return principal * annualRate * elapsedDays / 365;
}

function holdingAccruedInterest(holding, timestamp = Date.now()) {
  return isInterestHolding(holding)
    ? holdingInterestForDays(holding, settledInterestDays(holding, timestamp))
    : 0;
}

function holdingDividendIncome(holding, timestamp = Date.now()) {
  if (!isDividendHolding(holding)) return 0;
  return confirmedDividendRecords(holding, timestamp)
    .reduce((total, record) => total + (Number(record.amount) || 0), 0);
}

function resolveHoldingPrice(holding) {
  if (holding.holdingKind === 'interest') return 1;
  const known = marketAssets.find(asset => asset.symbol === holding.symbol);
  if (known && Number.isFinite(known.price)) return known.price;
  const fetched = holdingPrices.get(holding.quoteSymbol || holding.symbol);
  if (fetched && Number.isFinite(fetched.price)) return fetched.price;
  return null;
}

async function fetchHoldingPrice(holding) {
  if (typeof holding !== 'string' && holding.holdingKind === 'interest') return 1;
  const symbol = typeof holding === 'string' ? holding : holding.symbol;
  const quoteSymbol = typeof holding === 'string' ? holding : (holding.quoteSymbol || holding.symbol);
  const known = marketAssets.find(asset => asset.symbol === symbol);
  if (GLOBAL_TICKER_SYMBOLS.has(symbol) && Number.isFinite(known?.price)) return known.price;
  let quote = null;
  try {
    // 复用理财 ticker 用的同一个函数与同源代理（src/index.js）——那边的
    // 白名单已经从固定两个代号放开成格式校验，这里不用另起一套抓取逻辑。
    quote = await fetchBeijingQuote(quoteSymbol);
    holdingPrices.set(quoteSymbol, { price: quote.price, change: quote.change, series: quote.series });
  } catch {
    // 静态预览没有 Worker 路由；美股/ETF 可退回 TradingView，Crypto 则等
    // 全局行情或下一轮 Yahoo 请求，绝不捏造价格。
    try {
      [quote] = await fetchTradingViewQuotes([symbol]);
      holdingPrices.set(quoteSymbol, { price: quote.price, change: quote.change, series: quote.series });
    } catch {
      quote = null;
    }
  }
  if (!document.querySelector('#portfolio-app').hidden) renderHoldings();
  return Number.isFinite(quote?.price) ? quote.price : null;
}

function refreshHoldingPrices() {
  const seen = new Set();
  holdings.forEach(holding => {
    if (holding.holdingKind === 'interest') return;
    const quoteSymbol = holding.quoteSymbol || holding.symbol;
    if (GLOBAL_TICKER_SYMBOLS.has(holding.symbol) || seen.has(quoteSymbol)) return;
    seen.add(quoteSymbol);
    fetchHoldingPrice(holding);
  });
}

function holdingMetrics(holding, timestamp = Date.now()) {
  const kind = HOLDING_KINDS.has(holding.holdingKind) ? holding.holdingKind : 'market';
  const interest = holdingAccruedInterest(holding, timestamp);
  const dividend = holdingDividendIncome(holding, timestamp);

  if (kind === 'interest') {
    const principal = Number(holding.principal) || 0;
    const value = principal + interest;
    return {
      kind, quantity: principal, cost: principal, value, profit: interest,
      pct: principal > 0 ? interest / principal * 100 : 0,
      interest, hasValue: principal > 0
    };
  }

  const price = resolveHoldingPrice(holding);
  const quantity = Number(holding.quantity) || 0;
  const costPerShare = Number(holding.costPerShare) || 0;
  const cost = costPerShare * quantity;
  const hasValue = Number.isFinite(price);
  // 市价资产只按最新价计算当前总资产；持仓盈亏严格等于市值减持仓成本。
  const value = hasValue ? price * quantity : null;
  const profit = hasValue ? value - cost : null;
  return {
    kind, price, quantity, costPerShare, cost, value, profit,
    pct: cost > 0 && Number.isFinite(profit) ? profit / cost * 100 : 0,
    interest, dividend, hasValue
  };
}

function portfolioProfitTrendValues() {
  const interestHoldings = holdings.filter(holding => holding.holdingKind === 'interest');

  // 生息资产按北京时间每日 16:00 结算。存在生息持仓时，走势图固定使用最近
  // 7 天；市价资产的当前浮盈亏作为基线，生息收益在其上逐日累加。
  if (interestHoldings.length) {
    let marketProfit = 0;
    for (const holding of holdings.filter(item => item.holdingKind !== 'interest')) {
      const metrics = holdingMetrics(holding);
      if (!metrics.hasValue || !Number.isFinite(metrics.profit)) return [];
      marketProfit += metrics.profit;
    }
    const currentDays = interestHoldings.map(holding => settledInterestDays(holding));
    const pointCount = 7;
    return Array.from({ length: pointCount }, (_, index) => {
      const daysAgo = pointCount - 1 - index;
      const interest = interestHoldings.reduce((total, holding, holdingIndex) => {
        return total + holdingInterestForDays(holding, Math.max(0, currentDays[holdingIndex] - daysAgo));
      }, 0);
      return marketProfit + interest;
    });
  }

  const sources = [];
  let hasHistoricalSource = false;
  for (const holding of holdings) {
    const quantity = Number(holding.quantity);
    const costPerShare = Number(holding.costPerShare);
    // 成本或当前价缺失时无法计算这笔持仓对组合盈亏的贡献。
    if (!Number.isFinite(quantity) || quantity <= 0 || !Number.isFinite(costPerShare) || costPerShare <= 0) return [];
    const known = marketAssets.find(asset => asset.symbol === holding.symbol);
    const fetched = holdingPrices.get(holding.quoteSymbol || holding.symbol);
    const sourceSeries = known?.series?.length > 1 ? known.series : fetched?.series;
    let values = Array.isArray(sourceSeries)
      ? sourceSeries.filter(value => Number.isFinite(value) && value > 0)
      : [];
    if (values.length > 1) {
      hasHistoricalSource = true;
    } else {
      // 手动价格或 TradingView 备用报价只有当前点。它们应作为恒定基线参与
      // 组合，而不是让任意一笔缺历史的持仓把整张走势图降级为直线。
      const currentPrice = resolveHoldingPrice(holding);
      if (!Number.isFinite(currentPrice) || currentPrice <= 0) return [];
      values = [currentPrice, currentPrice];
    }
    sources.push({ quantity, costPerShare, values });
  }

  if (!sources.length || !hasHistoricalSource) return [];
  const pointCount = Math.min(48, Math.max(2, ...sources.map(source => source.values.length)));
  return Array.from({ length: pointCount }, (_, index) => sources.reduce((total, source) => {
    const sourceIndex = Math.round((index / (pointCount - 1)) * (source.values.length - 1));
    return total + (source.values[sourceIndex] - source.costPerShare) * source.quantity;
  }, 0));
}

function renderPortfolioSparkline(tone) {
  const svg = document.querySelector('#portfolio-sparkline');
  const path = document.querySelector('#portfolio-sparkline-path');
  const values = portfolioProfitTrendValues();
  const width = 160, height = 72, padding = 4;

  if (values.length < 2) {
    path.setAttribute('d', `M${padding} ${height / 2} L${width - padding} ${height / 2}`);
    svg.setAttribute('class', `portfolio-sparkline ${tone}`);
    svg.setAttribute('aria-label', '近一周总盈亏走势暂无历史数据');
    return;
  }

  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min;
  const yFor = value => range > 0
    ? padding + ((max - value) / range) * (height - padding * 2)
    : height / 2;
  const points = values.map((value, index) => {
    const x = padding + (index / (values.length - 1)) * (width - padding * 2);
    return `${index ? 'L' : 'M'}${x.toFixed(2)} ${yFor(value).toFixed(2)}`;
  });
  path.setAttribute('d', points.join(' '));
  svg.setAttribute('class', `portfolio-sparkline ${tone}`);
  svg.setAttribute('aria-label', `近一周总盈亏走势，从 ${money.format(values[0])} 到 ${money.format(values.at(-1))}`);
}

function renderPortfolioSummary() {
  let totalValue = 0, totalCost = 0, totalProfit = 0;
  let hasAllValues = holdings.length > 0;
  let hasAllCosts = holdings.length > 0;
  holdings.forEach(holding => {
    const metrics = holdingMetrics(holding);
    if (Number.isFinite(metrics.cost) && metrics.cost > 0) totalCost += metrics.cost;
    else hasAllCosts = false;
    if (metrics.hasValue && Number.isFinite(metrics.value)) totalValue += metrics.value;
    else hasAllValues = false;
    if (Number.isFinite(metrics.profit)) totalProfit += metrics.profit;
  });
  document.querySelector('#pf-total-value').textContent = hasAllValues ? money.format(totalValue) : '$—';
  const plEl = document.querySelector('#pf-total-pl');
  const pctEl = document.querySelector('#pf-total-pl-pct');
  const performanceEl = document.querySelector('#pf-total-performance');
  let tone = 'is-flat';
  if (hasAllValues && hasAllCosts && totalCost > 0) {
    const profit = totalProfit;
    const pct = (profit / totalCost) * 100;
    plEl.textContent = signedMoney(profit);
    const displayedPct = roundedMovementValue(pct);
    pctEl.textContent = `(${displayedPct > 0 ? '+' : ''}${displayedPct.toFixed(2)}%)`;
    tone = movementTone(profit);
    performanceEl.className = `portfolio-overview-change ${tone}`;
  } else {
    plEl.textContent = '$0.00';
    pctEl.textContent = '(0.00%)';
    performanceEl.className = 'portfolio-overview-change is-flat';
  }
  renderPortfolioSparkline(tone);
}

function holdingRowModel(holding) {
  const metrics = holdingMetrics(holding);
  const annualRate = Number(holding.annualRate) || 0;
  let detail;
  if (metrics.kind === 'interest') {
    detail = `本金 ${money.format(metrics.cost)} · 年化 ${annualRate.toFixed(2)}%`;
  } else if (metrics.kind === 'hybrid') {
    detail = `${metrics.quantity} 份 · 成本 ${money.format(metrics.costPerShare)} · 年化 ${annualRate.toFixed(2)}%`;
  } else if (metrics.kind === 'dividend') {
    const frequency = DIVIDEND_FREQUENCY_LABELS[holding.dividendFrequency] || '不固定';
    detail = `${metrics.quantity} 份 · 成本 ${money.format(metrics.costPerShare)} · ${frequency}分红`;
  } else {
    detail = `${metrics.quantity} 份 · 成本 ${money.format(metrics.costPerShare)}`;
  }
  let dividendDates = null;
  const dividendRecord = metrics.kind === 'dividend' ? latestDividendRecord(holding) : null;
  if (dividendRecord) {
    dividendDates = {
      exDate: formatPortfolioDate(dividendRecord.exDate),
      payDate: formatPortfolioDate(dividendRecord.payDate)
    };
  }
  return {
    symbol: holding.symbol,
    detail,
    value: metrics.value,
    profit: metrics.profit,
    pct: metrics.pct,
    hasValue: metrics.hasValue,
    profitLabel: metrics.kind === 'interest' ? '利息' : '盈亏',
    typeTag: metrics.kind === 'interest' ? '稳定生息' : null,
    dividendDates
  };
}

function appendHoldingRowContent(row, model, expandable = false) {
  const logo = document.createElement('span');
  logo.className = 'holding-logo';
  logo.textContent = model.symbol.slice(0, 2);

  const meta = document.createElement('span');
  meta.className = 'holding-meta';
  const titleLine = document.createElement('span');
  titleLine.className = 'holding-title-line';
  const symbolEl = document.createElement('span');
  symbolEl.className = 'holding-symbol';
  symbolEl.textContent = model.symbol;
  titleLine.append(symbolEl);
  if (model.typeTag) {
    const typeTag = document.createElement('span');
    typeTag.className = 'holding-type-tag';
    typeTag.textContent = model.typeTag;
    titleLine.append(typeTag);
  }
  if (expandable) {
    const expand = document.createElement('span');
    expand.className = 'holding-expand';
    const count = document.createElement('span');
    count.textContent = `${model.count} 笔`;
    const chevron = document.createElement('i');
    chevron.className = 'ri-arrow-right-s-line';
    chevron.setAttribute('aria-hidden', 'true');
    expand.append(count, chevron);
    titleLine.append(expand);
  }
  const detail = document.createElement('span');
  detail.className = 'holding-qty';
  detail.textContent = model.detail;
  meta.append(titleLine, detail);
  const right = document.createElement('span');
  right.className = 'holding-right';
  if (model.hasValue && Number.isFinite(model.value)) {
    const value = document.createElement('span');
    value.className = 'holding-value';
    value.textContent = money.format(model.value);
    const pl = document.createElement('span');
    const profit = Number(model.profit) || 0;
    pl.className = `holding-pl ${movementTone(profit)}`;
    const plLabel = document.createElement('span');
    plLabel.className = 'holding-pl-label';
    plLabel.textContent = model.profitLabel;
    const plValue = document.createElement('span');
    plValue.className = 'holding-pl-value';
    plValue.textContent = signedMoney(profit);
    pl.append(plLabel, plValue);
    if (model.profitLabel !== '利息') {
      const plPercent = document.createElement('span');
      plPercent.className = 'holding-pl-pct';
      const displayedPct = roundedMovementValue(model.pct);
      plPercent.textContent = `(${displayedPct > 0 ? '+' : ''}${displayedPct.toFixed(2)}%)`;
      pl.append(plPercent);
    }
    right.append(value, pl);
  } else {
    const hint = document.createElement('span');
    hint.className = 'holding-price-hint';
    hint.append(document.createTextNode('盈亏待计算'), document.createElement('i'));
    hint.lastElementChild.className = 'ri-arrow-right-line';
    hint.lastElementChild.setAttribute('aria-hidden', 'true');
    right.append(hint);
  }

  row.append(logo, meta, right);
  if (model.dividendDates) {
    row.classList.add('has-dividend-dates');

    const dates = document.createElement('span');
    dates.className = 'holding-dividend-dates';

    const exDate = document.createElement('span');
    exDate.innerHTML = `<small>除息日</small><strong>${model.dividendDates.exDate}</strong>`;

    const payDate = document.createElement('span');
    payDate.innerHTML = `<small>派息日</small><strong>${model.dividendDates.payDate}</strong>`;

    dates.append(exDate, payDate);
    row.append(dates);
  }
}

function createHoldingRow(holding, className = 'holding-row') {
  const row = document.createElement('button');
  row.type = 'button';
  row.className = className;
  appendHoldingRowContent(row, holdingRowModel(holding));
  row.setAttribute('aria-label', `查看 ${holding.symbol} 盈亏明细`);
  row.addEventListener('click', () => openProfitSheet([holding], {
    label: '编辑持仓',
    action: () => openHoldingSheet(holding.id)
  }));
  return row;
}

function mergedHoldingModel(group) {
  const metrics = group.map(holding => holdingMetrics(holding));
  const totalCost = metrics.reduce((sum, item) => sum + item.cost, 0);
  const totalValue = metrics.every(item => item.hasValue)
    ? metrics.reduce((sum, item) => sum + item.value, 0)
    : null;
  const totalProfit = metrics.every(item => Number.isFinite(item.profit))
    ? metrics.reduce((sum, item) => sum + item.profit, 0)
    : null;
  const marketMetrics = metrics.filter(item => item.kind !== 'interest');
  const totalQuantity = marketMetrics.reduce((sum, item) => sum + item.quantity, 0);
  const allStable = metrics.every(item => item.kind === 'interest');
  const allMarketBased = marketMetrics.length === metrics.length;
  const detail = allStable
    ? `本金 ${money.format(totalCost)}`
    : allMarketBased && totalQuantity > 0
      ? `${totalQuantity} 份 · 均价 ${money.format(totalCost / totalQuantity)}`
      : `综合成本 ${money.format(totalCost)}`;
  return {
    symbol: group[0].symbol,
    detail,
    count: group.length,
    value: totalValue,
    profit: totalProfit,
    pct: totalCost > 0 && Number.isFinite(totalProfit) ? totalProfit / totalCost * 100 : 0,
    hasValue: Number.isFinite(totalValue),
    profitLabel: allStable ? '利息' : '盈亏',
    typeTag: allStable ? '稳定生息' : null
  };
}

function createMergedHoldingGroup(group) {
  const wrapper = document.createElement('div');
  wrapper.className = 'holding-group';
  const summary = document.createElement('button');
  summary.type = 'button';
  summary.className = 'holding-row holding-group-summary';
  summary.setAttribute('aria-label', `查看 ${group[0].symbol} 合并持仓盈亏明细`);
  appendHoldingRowContent(summary, mergedHoldingModel(group), true);

  const lots = document.createElement('div');
  lots.className = 'holding-group-lots';
  lots.hidden = true;
  lots.replaceChildren(...group.map(holding => createHoldingRow(holding, 'holding-row holding-subrow')));
  summary.addEventListener('click', () => openProfitSheet(group, {
    label: `查看 ${group.length} 笔持仓`,
    action: () => { lots.hidden = false; lots.querySelector('button')?.focus(); }
  }));
  wrapper.append(summary, lots);
  return wrapper;
}

function renderHoldings() {
  const list = document.querySelector('#holdings-list');
  const empty = document.querySelector('#holdings-empty');
  const hasHoldings = holdings.length > 0;
  document.querySelector('.portfolio-summary').hidden = !hasHoldings;
  list.hidden = !hasHoldings;
  empty.hidden = hasHoldings;

  const mergeSame = document.querySelector('#merge-holdings').checked;
  if (mergeSame) {
    const groups = new Map();
    holdings.forEach(holding => {
      const key = String(holding.symbol || '').trim().toUpperCase();
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(holding);
    });
    list.replaceChildren(...[...groups.values()].map(group => (
      group.length > 1 ? createMergedHoldingGroup(group) : createHoldingRow(group[0])
    )));
  } else {
    list.replaceChildren(...holdings.map(holding => createHoldingRow(holding)));
  }

  renderPortfolioSummary();
  renderPortfolioRecommend();
}

// 快捷添加固定为三类长期资产：宽基 ETF、优质公司和主流 Crypto。同一标的
// 可以按不同买入批次重复添加，按钮始终作为新建一笔仓位的入口。
function renderPortfolioRecommend() {
  const section = document.querySelector('#portfolio-recommend');
  const grid = document.querySelector('#recommend-grid');
  section.hidden = localStorage.getItem(PORTFOLIO_RECOMMEND_DISMISSED_KEY) === '1';
  if (section.hidden) return;

  grid.replaceChildren(...RECOMMENDED_ASSETS.map(asset => {
    const known = marketAssets.find(item => item.symbol === asset.symbol);
    const fetched = holdingPrices.get(asset.quoteSymbol);
    const quote = Number.isFinite(known?.price) ? known : (fetched || known || {});
    const card = document.createElement('article');
    card.className = 'recommend-card';

    const icon = asset.icon ? document.createElement('img') : document.createElement('span');
    icon.className = asset.icon ? 'recommend-icon' : 'recommend-icon recommend-letter';
    if (asset.icon) { icon.src = asset.icon; icon.alt = ''; }
    else icon.textContent = asset.symbol.slice(0, 1);

    const symbolEl = document.createElement('span');
    symbolEl.className = 'recommend-symbol';
    symbolEl.textContent = asset.symbol;

    const priceEl = document.createElement('span');
    if (Number.isFinite(quote.price)) {
      priceEl.className = 'recommend-price';
      priceEl.textContent = btcMoney.format(quote.price);
    } else {
      priceEl.className = 'recommend-price is-pending';
      priceEl.textContent = '获取中';
    }

    const changeEl = document.createElement('span');
    if (Number.isFinite(quote.change)) {
      const displayedChange = roundedMovementValue(quote.change);
      const directionText = displayedChange > 0 ? '上涨' : displayedChange < 0 ? '下跌' : '持平';
      changeEl.className = `recommend-change ${movementTone(displayedChange)}`;
      changeEl.setAttribute('aria-label', `${directionText} ${Math.abs(displayedChange).toFixed(2)}%`);
      const directionIcon = document.createElement('i');
      directionIcon.className = displayedChange > 0
        ? 'ri-arrow-up-line'
        : displayedChange < 0
          ? 'ri-arrow-down-line'
          : 'ri-subtract-line';
      directionIcon.setAttribute('aria-hidden', 'true');
      changeEl.append(directionIcon, document.createTextNode(`${Math.abs(displayedChange).toFixed(2)}%`));
    } else {
      changeEl.className = 'recommend-change';
      changeEl.textContent = '—';
    }

    const addButton = document.createElement('button');
    addButton.type = 'button';
    addButton.className = 'recommend-add-btn';
    addButton.textContent = '一键添加';
    addButton.setAttribute('aria-label', `一键添加 ${asset.symbol}`);
    addButton.addEventListener('click', () => openHoldingSheet(null, asset));

    card.append(icon, symbolEl, priceEl, changeEl, addButton);
    return card;
  }));
}

function refreshRecommendationPrices() {
  RECOMMENDED_ASSETS.forEach(asset => fetchHoldingPrice(asset));
}

// 打开弹层：先摘掉 hidden，强制回流一次，再加 is-open 触发 CSS 过渡。
// 强制回流（读 offsetHeight）比 requestAnimationFrame 更可靠——rAF 要等
// 页面下一次绘制才执行，标签页哪怕短暂不可见都会被节流并错过那一帧，
// 弹层就会卡在「hidden 已摘但看不见」的状态；强制回流是同步的，不依赖
// 页面是否在渲染。
function openOverlay(overlay, openClass = 'is-open') {
  overlay.hidden = false;
  overlay.querySelectorAll('[data-dialog-scroll]').forEach(element => { element.scrollTop = 0; });
  void overlay.offsetHeight;
  overlay.classList.add(openClass);
}

function setProfitValue(element, value) {
  element.textContent = signedMoney(value);
  element.classList.remove('is-gain', 'is-loss', 'is-flat');
  if (Number.isFinite(value)) element.classList.add(movementTone(value));
}

function openProfitSheet(items, action) {
  clearTimeout(profitSheetCloseTimer);
  const holdingsForBreakdown = Array.isArray(items) ? items : [items];
  const metrics = holdingsForBreakdown.map(holding => holdingMetrics(holding));
  profitSheetTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  profitSheetAction = action;
  profitSheetItems = holdingsForBreakdown;

  let holdingProfit = 0;
  let hasHoldingProfit = true;
  metrics.forEach(metric => {
    if (metric.kind === 'interest') return;
    if (!metric.hasValue || !Number.isFinite(metric.price)) {
      hasHoldingProfit = false;
      return;
    }
    holdingProfit += metric.price * metric.quantity - metric.cost;
  });
  const dividend = metrics.reduce((sum, metric) => sum + (Number(metric.dividend) || 0), 0);
  const interest = metrics.reduce((sum, metric) => sum + (Number(metric.interest) || 0), 0);
  const stableOnly = metrics.length > 0 && metrics.every(metric => metric.kind === 'interest');
  const hasTotalProfit = metrics.every(metric => Number.isFinite(metric.profit));
  const totalProfit = hasTotalProfit ? metrics.reduce((sum, metric) => sum + metric.profit, 0) : NaN;
  const totalCost = metrics.reduce((sum, metric) => sum + (Number(metric.cost) || 0), 0);
  const annualRate = stableOnly && totalCost > 0
    ? holdingsForBreakdown.reduce((sum, holding) => (
        sum + (Number(holding.principal) || 0) * (Number(holding.annualRate) || 0)
      ), 0) / totalCost
    : NaN;
  const hasCurrentValue = metrics.every(metric => metric.hasValue && Number.isFinite(metric.value));
  const totalValue = hasCurrentValue ? metrics.reduce((sum, metric) => sum + metric.value, 0) : NaN;
  const symbol = holdingsForBreakdown[0]?.symbol || '资产';

  document.querySelector('#profit-sheet-symbol').textContent = holdingsForBreakdown.length > 1
    ? `${symbol} · ${holdingsForBreakdown.length} 笔持仓`
    : symbol;
  setProfitValue(document.querySelector('#profit-sheet-total'), totalProfit);
  document.querySelector('#profit-sheet-total-label').textContent = stableOnly ? '总利息' : '总盈亏';
  setProfitValue(document.querySelector('#profit-market-value'), hasHoldingProfit ? holdingProfit : NaN);
  setProfitValue(document.querySelector('#profit-dividend-value'), dividend);
  setProfitValue(document.querySelector('#profit-interest-value'), interest);
  document.querySelector('#profit-market-detail').textContent = hasHoldingProfit
    ? '当前总资产减去持仓成本'
    : '获取最新价格后可计算';

  const dividendHoldings = holdingsForBreakdown.filter(isDividendHolding);
  const dividendRecords = dividendHoldings.flatMap(holding => holdingDividendRecords(holding));
  const confirmedRecordCount = dividendHoldings.reduce((count, holding) => count + confirmedDividendRecords(holding).length, 0);
  const dividendDetail = document.querySelector('#profit-dividend-detail');
  if (!dividendRecords.length) {
    dividendDetail.textContent = '暂无已确认股息';
  } else if (confirmedRecordCount > 0) {
    dividendDetail.textContent = `${dividendRecords.length} 条记录，${confirmedRecordCount} 条已确认`;
  } else {
    const nextRecord = [...dividendRecords].sort((a, b) => String(a.exDate).localeCompare(String(b.exDate)))[0];
    dividendDetail.textContent = `等待 ${formatPortfolioDate(nextRecord.exDate)} 除息`;
  }

  const interestRow = document.querySelector('#profit-interest-row');
  const annualRateRow = document.querySelector('#profit-annual-rate-row');
  document.querySelector('.profit-breakdown-list').classList.toggle('is-stable-only', stableOnly);
  document.querySelector('#profit-market-row').hidden = stableOnly;
  document.querySelector('#profit-dividend-row').hidden = stableOnly;
  interestRow.hidden = !holdingsForBreakdown.some(isInterestHolding);
  annualRateRow.hidden = !stableOnly;
  document.querySelector('#profit-annual-rate-value').textContent = Number.isFinite(annualRate)
    ? `${annualRate.toFixed(2)}%`
    : '—';
  document.querySelector('#profit-annual-rate-detail').textContent = holdingsForBreakdown.length > 1
    ? '多笔持仓按本金加权'
    : '当前持仓设置';

  const eventCard = document.querySelector('#profit-event-card');
  const latestRecord = dividendHoldings.length === 1 ? latestDividendRecord(dividendHoldings[0]) : null;
  eventCard.hidden = !latestRecord;
  if (latestRecord) {
    document.querySelector('#profit-dividend-per-share').textContent = money.format(Number(latestRecord.perShare) || 0);
    document.querySelector('#profit-ex-date').textContent = formatPortfolioDate(latestRecord.exDate);
    document.querySelector('#profit-pay-date').textContent = formatPortfolioDate(latestRecord.payDate);
  }

  const recordsButton = document.querySelector('#profit-dividend-records-btn');
  recordsButton.hidden = !dividendHoldings.length;
  document.querySelector('#profit-dividend-records-count').textContent = `${dividendRecords.length} 条记录`;

  document.querySelector('#profit-sheet-foot').textContent = `持仓成本 ${money.format(totalCost)} · 当前资产 ${Number.isFinite(totalValue) ? money.format(totalValue) : '$—'}`;
  document.querySelector('#profit-edit-btn').textContent = action?.label || '编辑持仓';
  openOverlay(document.querySelector('#profit-sheet-overlay'));
  document.querySelector('#profit-close-btn').focus();
}

function closeProfitSheet(restoreFocus = true) {
  const overlay = document.querySelector('#profit-sheet-overlay');
  overlay.classList.remove('is-open');
  const trigger = profitSheetTrigger;
  profitSheetCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    if (restoreFocus && trigger?.isConnected) trigger.focus();
    profitSheetTrigger = null;
  }, 220);
}

function dividendRecordEntries(items = dividendRecordsContext) {
  return items.flatMap(holding => holdingDividendRecords(holding).map(record => ({ holding, record })))
    .sort((a, b) => String(b.record.exDate).localeCompare(String(a.record.exDate)));
}

function renderDividendRecordsSheet() {
  const entries = dividendRecordEntries();
  const list = document.querySelector('#dividend-records-list');
  const empty = document.querySelector('#dividend-records-empty');
  const symbols = [...new Set(dividendRecordsContext.map(holding => holding.symbol))];
  const confirmedTotal = entries.reduce((total, { record }) => (
    record.exDate <= beijingDateString() ? total + (Number(record.amount) || 0) : total
  ), 0);

  document.querySelector('#dividend-records-symbol').textContent = symbols.length === 1 ? symbols[0] : `${symbols.length} 个资产`;
  const total = document.querySelector('#dividend-records-total');
  total.textContent = signedMoney(confirmedTotal);
  total.className = movementTone(confirmedTotal);
  empty.hidden = entries.length > 0;
  list.hidden = entries.length === 0;
  list.replaceChildren(...entries.map(({ holding, record }) => {
    const row = document.createElement('div');
    row.className = 'dividend-record-row';

    const copy = document.createElement('span');
    copy.className = 'dividend-record-copy';
    const title = document.createElement('strong');
    const frequency = DIVIDEND_FREQUENCY_LABELS[record.frequency] || '不固定';
    title.textContent = `${holding.symbol} · ${frequency}分红`;
    const detail = document.createElement('small');
    detail.textContent = `除息日 ${formatPortfolioDate(record.exDate)} · 派息日 ${formatPortfolioDate(record.payDate)} · 每股 ${money.format(record.perShare)}`;
    copy.append(title, detail);

    const amount = document.createElement('span');
    const recordAmount = Number(record.amount) || 0;
    amount.className = `dividend-record-amount ${movementTone(recordAmount)}`;
    amount.textContent = signedMoney(recordAmount);

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'dividend-record-delete';
    remove.setAttribute('aria-label', `删除 ${holding.symbol} ${formatPortfolioDate(record.exDate)} 的股息记录`);
    const removeIcon = document.createElement('i');
    removeIcon.className = 'ri-delete-bin-line';
    removeIcon.setAttribute('aria-hidden', 'true');
    remove.append(removeIcon);
    remove.addEventListener('click', () => requestConfirmation({
      title: '删除股息记录',
      body: `删除后，总盈亏将减少 ${money.format(Number(record.amount) || 0)}。`,
      confirmLabel: '删除记录',
      action: () => deleteDividendRecord(holding.id, record.id)
    }));

    row.append(copy, amount, remove);
    return row;
  }));
}

function openDividendRecordsSheet(items) {
  clearTimeout(dividendRecordsCloseTimer);
  dividendRecordsTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  dividendRecordsContext = (Array.isArray(items) ? items : [items]).filter(Boolean);
  renderDividendRecordsSheet();
  openOverlay(document.querySelector('#dividend-records-overlay'));
  document.querySelector('#dividend-records-close-btn').focus();
}

function closeDividendRecordsSheet(restoreFocus = true) {
  const overlay = document.querySelector('#dividend-records-overlay');
  overlay.classList.remove('is-open');
  const trigger = dividendRecordsTrigger;
  dividendRecordsCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    if (restoreFocus && trigger?.isConnected) trigger.focus();
    dividendRecordsTrigger = null;
    dividendRecordsContext = [];
  }, 220);
}

function deleteDividendRecord(holdingId, recordId) {
  const holding = holdings.find(item => item.id === holdingId);
  if (!holding) return;
  holding.dividendRecords = holdingDividendRecords(holding).filter(record => record.id !== recordId);
  if (holding.dividendRecordId === recordId) {
    holding.dividendRecordId = null;
    holding.dividendPerShare = null;
    holding.dividendExDate = null;
    holding.dividendPayDate = null;
  }
  saveHoldings();
  renderHoldings();
  renderDividendRecordsSheet();
  if (editingHoldingId === holdingId) {
    document.querySelector('#holding-dividend-per-share').value = '';
    document.querySelector('#holding-ex-dividend-date').value = '';
    document.querySelector('#holding-dividend-pay-date').value = '';
    updateHoldingYieldPreview();
    updateHoldingSubmitState();
    updateHoldingDividendRecordsLink(holding);
  }
  if (!document.querySelector('#profit-sheet-overlay').hidden && profitSheetItems.length) {
    const trigger = profitSheetTrigger;
    openProfitSheet(profitSheetItems, profitSheetAction);
    profitSheetTrigger = trigger;
    document.querySelector('#dividend-records-close-btn').focus();
  }
  showToast('股息记录已删除，总盈亏已更新');
}

// ── 资产搜索 ────────────────────────────────────────────────────────
function setSelectedHoldingAsset(asset, preserveIncomeKind = false) {
  if (!preserveIncomeKind) marketIncomeKindOverride = null;
  selectedHoldingAsset = normalizeAsset(asset);
  const value = document.querySelector('#holding-symbol-value');
  const select = document.querySelector('#holding-symbol-select');
  if (selectedHoldingAsset) {
    value.textContent = selectedHoldingAsset.symbol;
    value.classList.remove('is-placeholder');
    select.setAttribute('aria-label', `标的代码 ${selectedHoldingAsset.symbol}，点击重新搜索`);
    fetchHoldingPrice(selectedHoldingAsset).finally(() => {
      updateHoldingYieldPreview();
      updateHoldingSubmitState();
    });
  } else {
    value.textContent = '例如 AAPL、BTC';
    value.classList.add('is-placeholder');
    select.setAttribute('aria-label', '标的代码，必填，点击搜索');
  }
  updateHoldingFormVisibility();
}

function currentHoldingKind() {
  const baseKind = document.querySelector('input[name="holding-kind"]:checked')?.value || 'market';
  const canRecordDividends = selectedHoldingAsset?.assetType === 'EQUITY';
  if (baseKind !== 'market' || !canRecordDividends || !document.querySelector('#holding-market-interest').checked) return baseKind;
  return marketIncomeKindOverride || 'dividend';
}

function manualHoldingAsset() {
  const symbol = document.querySelector('#holding-symbol-manual').value.trim().replace(/\s+/g, ' ').toUpperCase();
  return symbol ? { symbol, quoteSymbol: symbol, name: symbol, assetType: 'STABLE', exchange: '手动' } : null;
}

function updateHoldingYieldPreview() {
  const kind = currentHoldingKind();
  if (kind === 'market') return;
  if (kind === 'dividend') {
    const preview = document.querySelector('#holding-dividend-preview');
    const quantity = Number(document.querySelector('#holding-qty').value);
    const perShare = Number(document.querySelector('#holding-dividend-per-share').value);
    const exDate = document.querySelector('#holding-ex-dividend-date').value;
    if (!(quantity > 0) || !(perShare > 0)) {
      preview.textContent = '填写数量与每股分红后显示本次收益';
      return;
    }
    const expected = quantity * perShare;
    const status = exDate && exDate <= beijingDateString() ? '已确认' : '预计';
    preview.textContent = `本次${status}分红 ${money.format(expected)} · 不按日累计，不计算复利`;
    return;
  }
  const preview = document.querySelector('#holding-yield-preview');
  const rate = Number(document.querySelector('#holding-rate').value);
  let principal = Number(document.querySelector('#holding-principal').value);
  if (kind === 'hybrid') {
    const quantity = Number(document.querySelector('#holding-qty').value);
    const enteredCost = Number(document.querySelector('#holding-cost').value);
    const resolvedPrice = selectedHoldingAsset ? resolveHoldingPrice(selectedHoldingAsset) : null;
    const cost = Number.isFinite(enteredCost) && enteredCost > 0 ? enteredCost : resolvedPrice;
    principal = Number.isFinite(quantity) && quantity > 0 && Number.isFinite(cost) ? quantity * cost : NaN;
  }
  if (!(principal > 0) || !(rate > 0)) {
    preview.textContent = kind === 'hybrid'
      ? '填写数量与年化利率后显示预计收益'
      : '填写本金与年化利率后显示预计收益';
    return;
  }
  preview.textContent = `预计每日收益 ${money.format(principal * rate / 100 / 365)} · 每日 16:00（北京时间）更新`;
}

function updateHoldingSubmitState() {
  // 表单始终允许提交，让校验在点击后给出明确反馈；只有真正保存期间才锁按钮。
  const submit = document.querySelector('#holding-submit-btn');
  if (submit.dataset.saving !== 'true') submit.disabled = false;
}

function updateHoldingFormVisibility() {
  const baseKind = document.querySelector('input[name="holding-kind"]:checked')?.value || 'market';
  const marketIncomeInput = document.querySelector('#holding-market-interest');
  const canRecordDividends = baseKind === 'market' && selectedHoldingAsset?.assetType === 'EQUITY';
  if (!canRecordDividends) {
    marketIncomeInput.checked = false;
    marketIncomeKindOverride = null;
  }
  const kind = currentHoldingKind();
  document.querySelectorAll('[data-holding-market]').forEach(element => { element.hidden = kind === 'interest'; });
  document.querySelectorAll('[data-holding-stable]').forEach(element => { element.hidden = kind !== 'interest'; });
  document.querySelectorAll('[data-holding-yield]').forEach(element => { element.hidden = kind !== 'interest' && kind !== 'hybrid'; });
  document.querySelectorAll('[data-holding-dividend]').forEach(element => { element.hidden = kind !== 'dividend'; });
  const editingHolding = holdings.find(item => item.id === editingHoldingId);
  const canAdjust = Boolean(editingHolding) && kind !== 'interest';
  document.querySelector('#holding-adjustment').hidden = !canAdjust;
  document.querySelector('#holding-qty').disabled = canAdjust;
  document.querySelector('#holding-qty-hint').hidden = !canAdjust;
  const dividendOption = document.querySelector('#holding-dividend-option');
  dividendOption.hidden = !canRecordDividends;
  marketIncomeInput.disabled = !canRecordDividends;
  document.querySelector('#holding-market-income-label').textContent = '记录股息';
  document.querySelector('#holding-market-interest').setAttribute('aria-expanded', String(kind === 'hybrid' || kind === 'dividend'));
  updateHoldingDividendRecordsLink(editingHolding);
  updateHoldingYieldPreview();
  updateHoldingSubmitState();
}

function updateHoldingDividendRecordsLink(holding) {
  const button = document.querySelector('#holding-dividend-records-btn');
  const show = Boolean(holding) && isDividendHolding(holding);
  button.hidden = !show;
  if (show) document.querySelector('#holding-dividend-records-count').textContent = `${holdingDividendRecords(holding).length} 条记录`;
}

function setPositionAdjustmentMode(mode) {
  positionAdjustmentMode = mode === 'reduce' ? 'reduce' : 'add';
  const isAdd = positionAdjustmentMode === 'add';
  const addButton = document.querySelector('#holding-add-mode');
  const reduceButton = document.querySelector('#holding-reduce-mode');
  addButton.classList.toggle('is-active', isAdd);
  reduceButton.classList.toggle('is-active', !isAdd);
  addButton.setAttribute('aria-pressed', String(isAdd));
  reduceButton.setAttribute('aria-pressed', String(!isAdd));
  document.querySelector('#holding-adjustment-submit').textContent = isAdd ? '确认加仓' : '确认减仓';
  document.querySelector('#holding-adjustment-hint').textContent = isAdd
    ? '按成交价计入成本；留空使用市场价，操作瞬间总盈亏不变'
    : '按成交价减持；留空使用市场价，盈亏将按剩余持仓重新计算';
}

async function adjustHoldingPosition() {
  const holding = holdings.find(item => item.id === editingHoldingId);
  if (!holding || holding.holdingKind === 'interest') return;
  const quantityInput = document.querySelector('#holding-adjustment-qty');
  const priceInput = document.querySelector('#holding-adjustment-price');
  const amount = Number(quantityInput.value);
  const currentQuantity = Number(holding.quantity) || 0;
  if (!Number.isFinite(amount) || amount <= 0) {
    quantityInput.focus();
    return showToast('请输入有效的调整数量');
  }
  if (positionAdjustmentMode === 'reduce' && amount >= currentQuantity) {
    quantityInput.focus();
    return showToast('减仓数量需小于当前持有数量；全部清仓请删除持仓');
  }

  const rawPrice = priceInput.value.trim();
  let transactionPrice = rawPrice === '' ? resolveHoldingPrice(holding) : Number(rawPrice);
  if (!Number.isFinite(transactionPrice) || transactionPrice <= 0) {
    const button = document.querySelector('#holding-adjustment-submit');
    button.disabled = true;
    button.textContent = '获取市场价…';
    transactionPrice = await fetchHoldingPrice(holding);
    button.disabled = false;
    setPositionAdjustmentMode(positionAdjustmentMode);
  }
  if (!Number.isFinite(transactionPrice) || transactionPrice <= 0) {
    priceInput.focus();
    return showToast('暂时无法获取市场价，请填写成交价格');
  }

  const costPerShare = Number(holding.costPerShare) || transactionPrice;
  if (positionAdjustmentMode === 'add') {
    const nextQuantity = currentQuantity + amount;
    holding.costPerShare = ((currentQuantity * costPerShare) + (amount * transactionPrice)) / nextQuantity;
    holding.quantity = nextQuantity;
  } else {
    holding.quantity = currentQuantity - amount;
  }
  if (!Array.isArray(holding.positionAdjustments)) holding.positionAdjustments = [];
  holding.positionAdjustments.push({
    id: `t_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
    type: positionAdjustmentMode,
    quantity: amount,
    price: transactionPrice,
    createdAt: Date.now()
  });
  holdingDividendRecords(holding).forEach(record => {
    if (record.exDate > beijingDateString()) {
      record.quantity = Number(holding.quantity) || 0;
      record.amount = record.quantity * (Number(record.perShare) || 0);
    }
  });

  saveHoldings();
  renderHoldings();
  document.querySelector('#holding-qty').value = holding.quantity;
  document.querySelector('#holding-cost').value = Number(holding.costPerShare).toFixed(4).replace(/0+$/, '').replace(/\.$/, '');
  quantityInput.value = '';
  priceInput.value = '';
  updateHoldingYieldPreview();
  showToast(positionAdjustmentMode === 'add' ? '已完成加仓' : '已完成减仓');
}

function createSearchState(title, detail) {
  const state = document.createElement('div');
  state.className = 'asset-search-state';
  const icon = document.createElement('i');
  icon.className = 'ri-search-line';
  icon.setAttribute('aria-hidden', 'true');
  const heading = document.createElement('p');
  heading.textContent = title;
  const description = document.createElement('span');
  description.textContent = detail;
  state.append(icon, heading, description);
  return state;
}

function renderAssetSearchState(title = '输入代码或名称，按回车开始搜索', detail = '支持 Yahoo Finance 上的股票、ETF 和 Crypto') {
  document.querySelector('#asset-search-content').replaceChildren(createSearchState(title, detail));
}

function renderAssetResults(results, query) {
  const content = document.querySelector('#asset-search-content');
  if (!results.length) {
    content.replaceChildren(createSearchState(`没有找到“${query}”`, '换一个代码或名称再试试'));
    return;
  }
  const list = document.createElement('div');
  list.className = 'asset-search-list';
  results.forEach(rawAsset => {
    const asset = normalizeAsset(rawAsset);
    if (!asset) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'asset-result';
    button.setAttribute('aria-label', `选择 ${asset.symbol} ${asset.name}`);

    const mark = document.createElement('span');
    mark.className = 'asset-result-mark';
    mark.textContent = asset.symbol.slice(0, 2);
    const copy = document.createElement('span');
    copy.className = 'asset-result-copy';
    const name = document.createElement('span');
    name.className = 'asset-result-name';
    name.textContent = asset.name;
    const meta = document.createElement('span');
    meta.className = 'asset-result-meta';
    meta.textContent = [ASSET_TYPE_LABELS[asset.assetType] || asset.assetType, asset.exchange].filter(Boolean).join(' · ');
    copy.append(name, meta);
    const symbol = document.createElement('span');
    symbol.className = 'asset-result-symbol';
    symbol.textContent = asset.symbol;
    button.append(mark, copy, symbol);
    button.addEventListener('click', () => {
      setSelectedHoldingAsset(asset);
      closeAssetSearch(document.querySelector('#holding-qty'));
    });
    list.append(button);
  });
  content.replaceChildren(list);
}

function fallbackAssetSearch(query) {
  const needle = query.trim().toLowerCase();
  return FALLBACK_ASSETS
    .filter(asset => `${asset.symbol} ${asset.quoteSymbol} ${asset.name}`.toLowerCase().includes(needle))
    .sort((a, b) => {
      const aExact = [a.symbol, a.quoteSymbol].some(value => value.toLowerCase() === needle);
      const bExact = [b.symbol, b.quoteSymbol].some(value => value.toLowerCase() === needle);
      return Number(bExact) - Number(aExact);
    })
    .slice(0, 12);
}

async function searchAssets(query) {
  assetSearchController?.abort();
  assetSearchController = new AbortController();
  try {
    const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`, {
      signal: assetSearchController.signal,
      cache: 'no-store'
    });
    if (!response.ok) throw new Error('asset search unavailable');
    const data = await response.json();
    return Array.isArray(data?.results) ? data.results.map(normalizeAsset).filter(Boolean) : [];
  } catch (error) {
    if (error.name === 'AbortError') throw error;
    return fallbackAssetSearch(query);
  }
}

function openAssetSearch() {
  clearTimeout(assetSearchCloseTimer);
  assetSearchTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  lastSubmittedAssetQuery = '';
  const input = document.querySelector('#asset-search-input');
  input.value = selectedHoldingAsset?.symbol || '';
  renderAssetSearchState();
  openOverlay(document.querySelector('#asset-search-overlay'));
  input.focus();
  input.select();
}

function closeAssetSearch(focusTarget = null) {
  assetSearchController?.abort();
  assetSearchController = null;
  const overlay = document.querySelector('#asset-search-overlay');
  overlay.classList.remove('is-open');
  const target = focusTarget || assetSearchTrigger;
  assetSearchCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    (target?.isConnected ? target : document.querySelector('#holding-symbol-select'))?.focus();
    assetSearchTrigger = null;
  }, 220);
}

function setDividendFrequency(value, announce = false) {
  const normalized = DIVIDEND_FREQUENCY_CONTROL_LABELS[value] ? value : 'quarterly';
  const control = document.querySelector('#holding-dividend-frequency');
  control.value = normalized;
  document.querySelector('#holding-dividend-frequency-value').textContent = DIVIDEND_FREQUENCY_CONTROL_LABELS[normalized];
  document.querySelectorAll('.frequency-option').forEach(option => {
    option.setAttribute('aria-pressed', String(option.dataset.frequency === normalized));
  });
  if (announce) control.dispatchEvent(new Event('change', { bubbles: true }));
}

function openDividendFrequencySheet() {
  clearTimeout(dividendFrequencyCloseTimer);
  const control = document.querySelector('#holding-dividend-frequency');
  dividendFrequencyTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : control;
  setDividendFrequency(control.value);
  control.setAttribute('aria-expanded', 'true');
  openOverlay(document.querySelector('#dividend-frequency-overlay'));
  document.querySelector(`.frequency-option[data-frequency="${control.value}"]`)?.focus();
}

function closeDividendFrequencySheet(restoreFocus = true) {
  const overlay = document.querySelector('#dividend-frequency-overlay');
  overlay.classList.remove('is-open');
  document.querySelector('#holding-dividend-frequency').setAttribute('aria-expanded', 'false');
  const trigger = dividendFrequencyTrigger;
  dividendFrequencyCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    if (restoreFocus && trigger?.isConnected) trigger.focus();
    dividendFrequencyTrigger = null;
  }, 220);
}

const dividendFrequencyOptions = [...document.querySelectorAll('.frequency-option')];
dividendFrequencyOptions.forEach((option, index) => {
  option.addEventListener('click', () => {
    setDividendFrequency(option.dataset.frequency, true);
    closeDividendFrequencySheet();
  });
  option.addEventListener('keydown', event => {
    const lastIndex = dividendFrequencyOptions.length - 1;
    const nextIndex = event.key === 'ArrowDown' || event.key === 'ArrowRight'
      ? Math.min(index + 1, lastIndex)
      : event.key === 'ArrowUp' || event.key === 'ArrowLeft'
        ? Math.max(index - 1, 0)
        : event.key === 'Home'
          ? 0
          : event.key === 'End'
            ? lastIndex
            : null;
    if (nextIndex === null) return;
    event.preventDefault();
    dividendFrequencyOptions[nextIndex].focus();
  });
});

document.querySelector('#holding-dividend-frequency').addEventListener('click', openDividendFrequencySheet);
document.querySelector('#dividend-frequency-close-btn').addEventListener('click', () => closeDividendFrequencySheet());
[...document.querySelectorAll('[data-close-frequency]')].forEach(element => {
  element.addEventListener('click', () => closeDividendFrequencySheet());
});

document.querySelector('#asset-search-form').addEventListener('submit', async event => {
  event.preventDefault();
  const input = document.querySelector('#asset-search-input');
  const query = input.value.trim();
  if (!query) return renderAssetSearchState('请输入标的代码或名称', '例如 AAPL、BTC');
  lastSubmittedAssetQuery = query;
  const submit = event.currentTarget.querySelector('.asset-search-submit');
  submit.disabled = true;
  submit.textContent = '搜索中';
  renderAssetSearchState('正在搜索', `正在 Yahoo Finance 中查找“${query}”`);
  try {
    const results = await searchAssets(query);
    if (input.value.trim() === lastSubmittedAssetQuery) renderAssetResults(results, query);
  } catch (error) {
    if (error.name !== 'AbortError') renderAssetSearchState('暂时无法搜索', '请稍后再试');
  } finally {
    submit.disabled = false;
    submit.textContent = '搜索';
  }
});

document.querySelector('#asset-search-input').addEventListener('input', event => {
  if (event.currentTarget.value.trim() !== lastSubmittedAssetQuery) {
    renderAssetSearchState('按回车或点击搜索', '输入变化后不会自动发起搜索');
  }
});
document.querySelector('#asset-search-input').addEventListener('keydown', event => {
  if (event.key !== 'Enter') return;
  event.preventDefault();
  document.querySelector('#asset-search-form').requestSubmit();
});
document.querySelector('#asset-search-cancel').addEventListener('click', () => {
  document.querySelector('#asset-search-input').value = '';
  closeAssetSearch();
});
[...document.querySelectorAll('[data-close-search]')].forEach(el => el.addEventListener('click', () => closeAssetSearch()));
document.querySelector('#holding-symbol-select').addEventListener('click', openAssetSearch);

document.querySelectorAll('input[name="holding-kind"]').forEach(input => {
  input.addEventListener('change', updateHoldingFormVisibility);
});
document.querySelector('#holding-market-interest').addEventListener('change', updateHoldingFormVisibility);
document.querySelectorAll('input[name="holding-interest-mode"]').forEach(input => {
  input.addEventListener('change', updateHoldingYieldPreview);
});
document.querySelector('#holding-symbol-manual').addEventListener('input', event => {
  const original = event.currentTarget.value;
  const uppercased = original.toUpperCase().replace(/[^A-Z0-9 ._-]/g, '');
  if (uppercased !== original) event.currentTarget.value = uppercased;
  updateHoldingSubmitState();
});
['holding-qty', 'holding-cost', 'holding-principal', 'holding-rate', 'holding-dividend-per-share'].forEach(id => {
  document.querySelector(`#${id}`).addEventListener('input', () => {
    updateHoldingYieldPreview();
    updateHoldingSubmitState();
  });
});
document.querySelector('#holding-start-date').addEventListener('change', updateHoldingSubmitState);
['holding-dividend-frequency', 'holding-ex-dividend-date', 'holding-dividend-pay-date'].forEach(id => {
  document.querySelector(`#${id}`).addEventListener('change', () => {
    updateHoldingYieldPreview();
    updateHoldingSubmitState();
  });
});
document.querySelector('#holding-add-mode').addEventListener('click', () => setPositionAdjustmentMode('add'));
document.querySelector('#holding-reduce-mode').addEventListener('click', () => setPositionAdjustmentMode('reduce'));
document.querySelector('#holding-adjustment-submit').addEventListener('click', adjustHoldingPosition);
document.querySelector('#holding-dividend-records-btn').addEventListener('click', () => {
  const holding = holdings.find(item => item.id === editingHoldingId);
  if (holding) openDividendRecordsSheet([holding]);
});

// ── 新增 / 编辑弹层 ──────────────────────────────────────────────────
function openHoldingSheet(id = null, presetAsset = null) {
  clearTimeout(holdingSheetCloseTimer);
  holdingSheetTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  editingHoldingId = id;
  const holding = id ? holdings.find(item => item.id === id) : null;
  const submitButton = document.querySelector('#holding-submit-btn');
  delete submitButton.dataset.saving;
  submitButton.disabled = false;
  submitButton.textContent = '保存';

  document.querySelector('#holding-sheet-title').textContent = holding ? '编辑持仓' : '添加持仓';
  document.querySelector('#holding-close-btn').setAttribute('aria-label', holding ? '关闭编辑持仓' : '关闭添加持仓');
  document.querySelector('#holding-delete-btn').hidden = !holding;
  document.querySelector('.holding-kind-field').hidden = Boolean(holding);
  const holdingKind = HOLDING_KINDS.has(holding?.holdingKind) ? holding.holdingKind : 'market';
  const baseKind = holdingKind === 'hybrid' || holdingKind === 'dividend' ? 'market' : holdingKind;
  const kindInput = document.querySelector(`input[name="holding-kind"][value="${baseKind}"]`);
  if (kindInput) kindInput.checked = true;
  document.querySelector('#holding-market-interest').checked = holdingKind === 'hybrid' || holdingKind === 'dividend';
  marketIncomeKindOverride = holdingKind === 'hybrid' || holdingKind === 'dividend' ? holdingKind : null;
  setSelectedHoldingAsset(holdingKind === 'interest' ? null : (holding || (typeof presetAsset === 'string' ? { symbol: presetAsset } : presetAsset)), true);
  document.querySelector('#holding-symbol-manual').value = holdingKind === 'interest' ? holding.symbol : '';
  document.querySelector('#holding-qty').value = holding && holdingKind !== 'interest' ? holding.quantity : '';
  document.querySelector('#holding-cost').value = holding && Number(holding.costPerShare) > 0 ? holding.costPerShare : '';
  document.querySelector('#holding-principal').value = holding && holdingKind === 'interest' ? holding.principal : '';
  document.querySelector('#holding-rate').value = holding && isInterestHolding(holding) ? holding.annualRate : '';
  document.querySelector(`input[name="holding-interest-mode"][value="${holding?.interestMode === 'compound' ? 'compound' : 'simple'}"]`).checked = true;
  const startDate = document.querySelector('#holding-start-date');
  startDate.max = beijingDateString();
  startDate.value = holding && isInterestHolding(holding) ? holding.interestStartDate : beijingDateString();
  document.querySelector('#holding-dividend-per-share').value = holding && isDividendHolding(holding) && Number(holding.dividendPerShare) > 0 ? holding.dividendPerShare : '';
  setDividendFrequency(holding && isDividendHolding(holding) && DIVIDEND_FREQUENCY_LABELS[holding.dividendFrequency]
    ? holding.dividendFrequency
    : 'quarterly');
  document.querySelector('#holding-ex-dividend-date').value = holding && isDividendHolding(holding) ? holding.dividendExDate || '' : '';
  document.querySelector('#holding-dividend-pay-date').value = holding && isDividendHolding(holding) ? holding.dividendPayDate || '' : '';
  document.querySelector('#holding-adjustment-qty').value = '';
  document.querySelector('#holding-adjustment-price').value = '';
  const currentPrice = holding ? resolveHoldingPrice(holding) : null;
  document.querySelector('#holding-adjustment-price').placeholder = Number.isFinite(currentPrice)
    ? currentPrice.toFixed(2)
    : '市场价';
  setPositionAdjustmentMode('add');
  updateHoldingFormVisibility();

  openOverlay(document.querySelector('#holding-sheet-overlay'));
  const firstInput = holdingKind === 'interest'
    ? document.querySelector('#holding-symbol-manual')
    : (selectedHoldingAsset ? document.querySelector('#holding-qty') : document.querySelector('#holding-symbol-select'));
  firstInput.focus();
}

function closeHoldingSheet() {
  const overlay = document.querySelector('#holding-sheet-overlay');
  overlay.classList.remove('is-open');
  const trigger = holdingSheetTrigger;
  holdingSheetCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    (trigger?.isConnected ? trigger : document.querySelector('#add-holding-btn'))?.focus();
    holdingSheetTrigger = null;
  }, 220);
  editingHoldingId = null;
  selectedHoldingAsset = null;
  marketIncomeKindOverride = null;
}

document.querySelector('#holding-form').addEventListener('submit', async event => {
  event.preventDefault();
  const holdingKind = currentHoldingKind();
  const asset = holdingKind === 'interest' ? normalizeAsset(manualHoldingAsset()) : normalizeAsset(selectedHoldingAsset);
  const quantity = Number(document.querySelector('#holding-qty').value);
  const principal = Number(document.querySelector('#holding-principal').value);
  const annualRate = Number(document.querySelector('#holding-rate').value);
  const interestMode = document.querySelector('input[name="holding-interest-mode"]:checked')?.value || 'simple';
  const interestStartDate = document.querySelector('#holding-start-date').value;
  const dividendPerShare = Number(document.querySelector('#holding-dividend-per-share').value);
  const dividendFrequency = document.querySelector('#holding-dividend-frequency').value;
  const dividendExDate = document.querySelector('#holding-ex-dividend-date').value;
  const dividendPayDate = document.querySelector('#holding-dividend-pay-date').value;
  const costInput = document.querySelector('#holding-cost');
  const costRaw = costInput.value.trim();
  let costPerShare = costRaw === '' ? null : Number(costRaw);

  if (!asset) {
    if (holdingKind === 'interest') document.querySelector('#holding-symbol-manual').focus();
    else {
      setSelectedHoldingAsset(null);
      document.querySelector('#holding-symbol-select').focus();
    }
    return showToast(holdingKind === 'interest' ? '请填写资产名称' : '请选择标的代码');
  }
  if (holdingKind === 'interest') {
    if (!Number.isFinite(principal) || principal <= 0) {
      document.querySelector('#holding-principal').focus();
      return showToast('请填写投资本金');
    }
  } else {
    if (!Number.isFinite(quantity) || quantity <= 0) {
      document.querySelector('#holding-qty').focus();
      return showToast('请填写持有数量');
    }
    if (costRaw !== '' && (!Number.isFinite(costPerShare) || costPerShare <= 0)) {
      costInput.focus();
      return showToast('请输入有效的单位成本价');
    }
  }
  if (holdingKind === 'interest' || holdingKind === 'hybrid') {
    if (!Number.isFinite(annualRate) || annualRate <= 0 || annualRate > 1000) {
      document.querySelector('#holding-rate').focus();
      return showToast('请输入 0–1000% 的年化利率');
    }
    if (!interestStartDate || interestStartDate > beijingDateString()) {
      document.querySelector('#holding-start-date').focus();
      return showToast('请选择有效的起息日期');
    }
  }
  if (holdingKind === 'dividend') {
    if (!Number.isFinite(dividendPerShare) || dividendPerShare <= 0) {
      document.querySelector('#holding-dividend-per-share').focus();
      return showToast('请填写每股分红金额');
    }
    if (!dividendExDate) {
      document.querySelector('#holding-ex-dividend-date').focus();
      return showToast('请选择除息日');
    }
    if (dividendPayDate && dividendPayDate < dividendExDate) {
      document.querySelector('#holding-dividend-pay-date').focus();
      return showToast('派息日不能早于除息日');
    }
  }

  const submitButton = document.querySelector('#holding-submit-btn');
  const wasEditing = Boolean(editingHoldingId);
  submitButton.dataset.saving = 'true';
  submitButton.disabled = true;
  submitButton.textContent = '保存中…';
  try {
    if (holdingKind !== 'interest' && costRaw === '') {
      submitButton.textContent = '获取最新价…';
      costPerShare = resolveHoldingPrice(asset);
      if (!Number.isFinite(costPerShare) || costPerShare <= 0) {
        costPerShare = await fetchHoldingPrice(asset);
      }
      if (!selectedHoldingAsset || selectedHoldingAsset.quoteSymbol !== asset.quoteSymbol) return;
      if (!Number.isFinite(costPerShare) || costPerShare <= 0) {
        costInput.focus();
        showToast('暂时无法获取最新价，请填写单位成本价');
        return;
      }
      costInput.value = Number(costPerShare).toFixed(4).replace(/0+$/, '').replace(/\.$/, '');
      submitButton.textContent = '保存中…';
    }

    const holdingData = {
      ...asset,
      holdingKind,
      quantity: holdingKind === 'interest' ? null : quantity,
      costPerShare: holdingKind === 'interest' ? null : costPerShare,
      priceOverride: null,
      principal: holdingKind === 'interest' ? principal : null,
      annualRate: holdingKind === 'interest' || holdingKind === 'hybrid' ? annualRate : null,
      interestMode: holdingKind === 'interest' || holdingKind === 'hybrid' ? interestMode : null,
      interestStartDate: holdingKind === 'interest' || holdingKind === 'hybrid' ? interestStartDate : null,
      dividendPerShare: holdingKind === 'dividend' ? dividendPerShare : null,
      dividendFrequency: holdingKind === 'dividend' ? dividendFrequency : null,
      dividendExDate: holdingKind === 'dividend' ? dividendExDate : null,
      dividendPayDate: holdingKind === 'dividend' ? dividendPayDate : null
    };

    let savedHolding;
    if (editingHoldingId) {
      const holding = holdings.find(item => item.id === editingHoldingId);
      if (!holding) throw new Error('Holding no longer exists');
      Object.assign(holding, holdingData);
      syncHoldingDividendRecord(holding);
      savedHolding = holding;
    } else {
      const newHolding = {
        id: `h_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
        ...holdingData,
        positionAdjustments: [],
        dividendRecords: [],
        dividendRecordId: null,
        createdAt: Date.now()
      };
      syncHoldingDividendRecord(newHolding);
      holdings.push(newHolding);
      savedHolding = newHolding;
    }

    saveHoldings();
    renderHoldings();
    if (savedHolding.holdingKind !== 'interest') fetchHoldingPrice(savedHolding);
    closeHoldingSheet();
    showToast(wasEditing ? '持仓已更新' : '持仓已添加');
  } catch (error) {
    console.error('Unable to save holding', error);
    showToast('保存失败，请重试');
  } finally {
    delete submitButton.dataset.saving;
    submitButton.disabled = false;
    submitButton.textContent = '保存';
  }
});

// ── 删除 ─────────────────────────────────────────────────────────────
function requestConfirmation({ title, body, confirmLabel = '删除', action }) {
  pendingConfirmAction = action;
  document.querySelector('#delete-confirm-title').textContent = title;
  document.querySelector('#delete-confirm-body').textContent = body;
  document.querySelector('#delete-confirm-btn').textContent = confirmLabel;
  openOverlay(document.querySelector('#delete-confirm-overlay'));
  document.querySelector('#delete-cancel-btn').focus();
}

document.querySelector('#holding-delete-btn').addEventListener('click', () => {
  const holding = holdings.find(item => item.id === editingHoldingId);
  if (!holding) return;
  requestConfirmation({
    title: '删除持仓',
    body: `删除后不可恢复，确定要删除 ${holding.symbol} 吗？`,
    confirmLabel: '删除持仓',
    action: () => {
      holdings = holdings.filter(item => item.id !== holding.id);
      saveHoldings();
      renderHoldings();
      closeHoldingSheet();
      showToast('持仓已删除');
    }
  });
});

function closeDeleteConfirm() {
  const overlay = document.querySelector('#delete-confirm-overlay');
  overlay.classList.remove('is-open');
  setTimeout(() => {
    overlay.hidden = true;
    pendingConfirmAction = null;
  }, 220);
}

document.querySelector('#delete-cancel-btn').addEventListener('click', closeDeleteConfirm);
document.querySelector('#delete-confirm-btn').addEventListener('click', () => {
  const action = pendingConfirmAction;
  closeDeleteConfirm();
  action?.();
});

[...document.querySelectorAll('[data-close-sheet]')].forEach(el => el.addEventListener('click', closeHoldingSheet));
[...document.querySelectorAll('[data-close-confirm]')].forEach(el => el.addEventListener('click', closeDeleteConfirm));
[...document.querySelectorAll('[data-close-profit]')].forEach(el => el.addEventListener('click', () => closeProfitSheet()));
[...document.querySelectorAll('[data-close-dividend-records]')].forEach(el => el.addEventListener('click', () => closeDividendRecordsSheet()));

document.querySelector('#add-holding-btn').addEventListener('click', () => openHoldingSheet(null));
document.querySelector('#holding-close-btn').addEventListener('click', closeHoldingSheet);
document.querySelector('#profit-close-btn').addEventListener('click', () => closeProfitSheet());
document.querySelector('#dividend-records-close-btn').addEventListener('click', () => closeDividendRecordsSheet());
document.querySelector('#profit-dividend-records-btn').addEventListener('click', () => openDividendRecordsSheet(profitSheetItems));
document.querySelector('#profit-edit-btn').addEventListener('click', () => {
  const action = profitSheetAction?.action;
  const returnTarget = profitSheetTrigger;
  closeProfitSheet(false);
  setTimeout(() => {
    action?.();
    if (!document.querySelector('#holding-sheet-overlay').hidden) holdingSheetTrigger = returnTarget;
  }, 230);
});
document.querySelector('#recommend-close-btn').addEventListener('click', () => {
  localStorage.setItem(PORTFOLIO_RECOMMEND_DISMISSED_KEY, '1');
  document.querySelector('#portfolio-recommend').hidden = true;
  document.querySelector('#add-holding-btn').focus();
});
const mergeHoldingsInput = document.querySelector('#merge-holdings');
mergeHoldingsInput.checked = localStorage.getItem(PORTFOLIO_MERGE_KEY) === '1';
mergeHoldingsInput.addEventListener('change', () => {
  localStorage.setItem(PORTFOLIO_MERGE_KEY, mergeHoldingsInput.checked ? '1' : '0');
  renderHoldings();
});

document.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  if (!document.querySelector('#delete-confirm-overlay').hidden) return closeDeleteConfirm();
  if (!document.querySelector('#dividend-frequency-overlay').hidden) return closeDividendFrequencySheet();
  if (!document.querySelector('#asset-search-overlay').hidden) return closeAssetSearch();
  if (!document.querySelector('#dividend-records-overlay').hidden) return closeDividendRecordsSheet();
  if (!document.querySelector('#profit-sheet-overlay').hidden) return closeProfitSheet();
  if (!document.querySelector('#holding-sheet-overlay').hidden) closeHoldingSheet();
});

// ── Toast ────────────────────────────────────────────────────────────
let toastTimer = null;
function showToast(message) {
  const el = document.querySelector('#toast');
  el.textContent = message;
  openOverlay(el, 'is-visible'); // 复用同一套「摘 hidden → 强制回流 → 触发过渡」写法
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.classList.remove('is-visible');
    setTimeout(() => { el.hidden = true; }, 220);
  }, 2400);
}

// ── 账号与云端同步 ───────────────────────────────────────────────────
//
// anon key 明文出现在这个文件里，这是设计如此：它只代表「一个匿名访客」，
// 真正的隔离在 Postgres 的行级安全策略上（见 supabase/schema.sql）。策略没建
// 好之前别上线，否则拿到 key 就等于拿到所有人的持仓。
//
// 同步是单向镜像而不是双向实时：localStorage 始终是即时读取源，云端只在登录
// 时拉一次、之后每次改动异步推上去。这样 renderHoldings 这些同步计算路径一行
// 都不用改。
const SUPABASE_URL = 'https://iwtitkgzaxwvpzviypue.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_jZC7mTKs8dbX78jQwo-BEg_JeJ3pAYh';
const cloud = SUPABASE_URL && SUPABASE_ANON_KEY && window.supabase
  ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  : null;
const PENDING_LOGIN_KEY = 'jiujiucat-pending-login';
let currentUser = null;
let cloudPushTimer = null;

function setSyncStatus(text) {
  document.querySelector('#account-sync').textContent = text;
}

function renderAccountBar() {
  const bar = document.querySelector('#account-bar');
  bar.hidden = !currentUser;
  if (currentUser) {
    document.querySelector('#account-email').textContent = currentUser.email || '已登录';
  }
}

async function pullCloudHoldings() {
  const { data, error } = await cloud.from('holdings').select('payload').eq('user_id', currentUser.id);
  if (error) throw error;
  return (data || []).map(row => row.payload).filter(item => item?.id);
}

async function pushCloudHoldings() {
  const rows = holdings.map(item => ({
    id: item.id,
    user_id: currentUser.id,
    payload: item,
    updated_at: new Date(Number(item.updatedAt) || Date.now()).toISOString()
  }));
  if (rows.length) {
    const { error } = await cloud.from('holdings').upsert(rows);
    if (error) throw error;
  }
  // 本地删掉的那些，云端也得跟着消失。id 是本地生成的 h_<时间戳>_<随机>，
  // 这道字符校验只是防止意外内容拼进 PostgREST 的 in(...) 列表。
  const keep = holdings.map(item => item.id).filter(id => /^[A-Za-z0-9_-]+$/.test(id));
  let query = cloud.from('holdings').delete().eq('user_id', currentUser.id);
  if (keep.length) query = query.not('id', 'in', `(${keep.join(',')})`);
  const { error: deleteError } = await query;
  if (deleteError) throw deleteError;
}

function queueCloudPush() {
  if (!cloud || !currentUser) return;
  clearTimeout(cloudPushTimer);
  cloudPushTimer = setTimeout(async () => {
    setSyncStatus('同步中…');
    try {
      await pushCloudHoldings();
      setSyncStatus('已同步');
    } catch {
      setSyncStatus('同步失败');
    }
  }, 800);
}

// 同一条持仓两边都改过时，updatedAt 新的赢；只在一边存在的直接收下。
function mergeHoldings(local, remote) {
  const stamp = item => Number(item.updatedAt) || Number(item.createdAt) || 0;
  const byId = new Map();
  for (const item of [...remote, ...local]) {
    if (!item?.id) continue;
    const existing = byId.get(item.id);
    if (!existing || stamp(item) >= stamp(existing)) byId.set(item.id, item);
  }
  return [...byId.values()];
}

async function handleSignedIn(user) {
  currentUser = user;
  renderAccountBar();
  unlockPortfolio();
  if (sessionStorage.getItem(PENDING_LOGIN_KEY)) {
    sessionStorage.removeItem(PENDING_LOGIN_KEY);
    document.querySelector('#tab-portfolio').click();
  }
  setSyncStatus('同步中…');
  try {
    holdings = mergeHoldings(holdings, await pullCloudHoldings());
    // 合并结果直接落盘：走 saveHoldings 会把刚拉下来的远端行当成「刚改过」
    // 重新盖章，冲突裁判就失效了。
    resetHoldingFingerprints();
    localStorage.setItem(PORTFOLIO_KEY, JSON.stringify(holdings));
    renderHoldings();
    refreshHoldingPrices();
    await pushCloudHoldings();
    setSyncStatus('已同步');
  } catch {
    setSyncStatus('同步失败，本地数据仍可用');
  }
}

// 退出时清掉本地副本：这台设备换个 Google 账号登进来，不该继承上一个人的持仓。
// 数据在云端，登回来就有。
function handleSignedOut() {
  currentUser = null;
  holdings = [];
  resetHoldingFingerprints();
  localStorage.removeItem(PORTFOLIO_KEY);
  localStorage.removeItem(PORTFOLIO_UNLOCKED_KEY);
  renderAccountBar();
  renderHoldings();
  document.querySelector('#portfolio-gate').hidden = false;
  document.querySelector('#portfolio-app').hidden = true;
}

function unlockPortfolio() {
  localStorage.setItem(PORTFOLIO_UNLOCKED_KEY, '1');
  document.querySelector('#portfolio-gate').hidden = true;
  document.querySelector('#portfolio-app').hidden = false;
  renderHoldings();
  refreshHoldingPrices();
  refreshRecommendationPrices();
}

document.querySelector('#portfolio-login-btn').addEventListener('click', async () => {
  if (!cloud) {
    // Supabase 还没配好时不要把人挡在门外，先给本地版；配好后同一个按钮就是
    // 真登录，本地这批数据会在首次登录时并进账号。
    showToast('账号登录尚未开放，先用本地版体验');
    unlockPortfolio();
    return;
  }
  sessionStorage.setItem(PENDING_LOGIN_KEY, '1');
  const { error } = await cloud.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: `${location.origin}/` }
  });
  if (error) {
    sessionStorage.removeItem(PENDING_LOGIN_KEY);
    showToast('登录失败，请稍后重试');
  }
});

document.querySelector('#account-signout-btn').addEventListener('click', async () => {
  await cloud?.auth.signOut();
});

if (cloud) {
  cloud.auth.onAuthStateChange((event, session) => {
    // 只认显式的 SIGNED_OUT。首次加载会先来一个 session 为 null 的
    // INITIAL_SESSION，当成登出处理会把从没登录过的人的本地持仓清空。
    if (event === 'SIGNED_OUT') return handleSignedOut();
    // 回调是在 auth 的内部锁里跑的，而 handleSignedIn 会去查表 —— 那次查询同样
    // 要拿这把锁，锁却要等回调返回才释放，两边互等就是死锁。丢到下一个 tick
    // 执行，回调先返回、锁先松开。这条是 Supabase 文档明说的用法约束，不是
    // 保险起见：它是否发作取决于时序，本机跑通不代表别人的网络下也跑得通。
    if (session?.user && currentUser?.id !== session.user.id) {
      setTimeout(() => handleSignedIn(session.user), 0);
    }
  });
}

if (localStorage.getItem(PORTFOLIO_UNLOCKED_KEY) === '1') {
  document.querySelector('#portfolio-gate').hidden = true;
  document.querySelector('#portfolio-app').hidden = false;
}
updateHoldingFormVisibility();
renderHoldings();
if (!document.querySelector('#portfolio-app').hidden) refreshRecommendationPrices();

// 只在面板可见时才拉价格/重渲染——持仓页没人看的时候没必要占请求配额。
setInterval(() => {
  if (!document.querySelector('#portfolio-app').hidden) {
    renderHoldings();
    refreshHoldingPrices();
    refreshRecommendationPrices();
  }
}, 60000);
