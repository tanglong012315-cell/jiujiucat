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
  { symbol: 'BTC', name: 'Bitcoin', icon: 'btc-icon.svg', basis: '北京时间今日', price: null, change: null, cached: false, status: '获取中' },
  { symbol: 'MSTR', name: 'MSTR', icon: 'mstr-icon.svg', basis: '北京时间今日', price: null, change: null, cached: false, status: '获取中', equity: true },
  { symbol: 'QQQ', name: 'QQQ', icon: 'qqq-icon.svg', basis: '北京时间今日', price: null, change: null, cached: false, status: '获取中', equity: true }
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
  if (Number.isFinite(asset.change)) {
    // SnowUI signals direction with the glyph, not with color.
    changeLabel.textContent = `${asset.change >= 0 ? '▲' : '▼'} ${Math.abs(asset.change).toFixed(2)}%${asset.cached ? ' · 最近' : ''}`;
    changeLabel.className = asset.change >= 0 ? 'positive' : 'negative';
  } else {
    changeLabel.textContent = asset.cached ? '最近价格' : asset.status;
    changeLabel.className = '';
  }
  const session = renderMarketSession(asset);
  const sessionText = session ? `，美股${session.full}` : '';
  const priceText = Number.isFinite(asset.price) ? btcMoney.format(asset.price) : '价格暂不可用';
  document.querySelector('.btc-ticker').setAttribute('aria-label', `${asset.name} ${priceText}，${asset.basis}涨跌 ${changeLabel.textContent}${sessionText}，点击查看下一个标的`);
  document.querySelector('.btc-ticker').title = `${asset.name}/USD 实时行情；${asset.basis}涨跌幅${session ? `；美股${session.full}` : ''}`;
}

function setMarketData(symbol, price, change, cached = false, status = '暂不可用', basis) {
  const asset = marketAssets.find(item => item.symbol === symbol);
  if (!asset) return;
  if (basis) asset.basis = basis;
  asset.price = Number.isFinite(price) ? price : null;
  asset.change = Number.isFinite(change) ? change : null;
  asset.cached = cached;
  asset.status = Number.isFinite(price) ? '' : status;
  if (marketAssets[currentMarketIndex] === asset) renderMarketTicker(asset);
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
    const response = await fetch(`https://api.coingecko.com/api/v3/coins/bitcoin/market_chart/range?vs_currency=usd&from=${dayStart}&to=${now}`, { signal: controller.signal, cache: 'no-store' });
    if (!response.ok) throw new Error('Bitcoin price request failed');
    const data = await response.json();
    const prices = Array.isArray(data?.prices) ? data.prices : [];
    const openingPrice = Number(prices[0]?.[1]);
    const price = Number(prices.at(-1)?.[1]);
    if (!Number.isFinite(price) || price <= 0 || !Number.isFinite(openingPrice) || openingPrice <= 0) throw new Error('Invalid Bitcoin price');
    const change = ((price - openingPrice) / openingPrice) * 100;
    localStorage.setItem('retirement-calculator-btc', JSON.stringify({ price, change, dayStart, savedAt: Date.now() }));
    setMarketData('BTC', price, change);
  } catch (error) {
    try {
      const cached = JSON.parse(localStorage.getItem('retirement-calculator-btc') || 'null');
      if (cached?.price) {
        const cachedChange = Number(cached.dayStart) === getBeijingDayStartUnix() ? Number(cached.change) : NaN;
        setMarketData('BTC', Number(cached.price), cachedChange, true);
      }
      else setMarketData('BTC', NaN, NaN);
    } catch (cacheError) {
      setMarketData('BTC', NaN, NaN);
    }
  } finally {
    clearTimeout(timeout);
  }
}

function saveStockQuote(symbol, price, change, basis = '北京时间今日') {
  localStorage.setItem(`retirement-calculator-${symbol.toLowerCase()}`, JSON.stringify({ price, change, basis, dayStart: getBeijingDayStartUnix(), savedAt: Date.now() }));
  setMarketData(symbol, price, change, false, '暂不可用', basis);
}

function restoreCachedStockPrices() {
  for (const symbol of ['MSTR', 'QQQ']) {
    try {
      const cached = JSON.parse(localStorage.getItem(`retirement-calculator-${symbol.toLowerCase()}`) || 'null');
      if (cached?.price) {
        // A Beijing-day change is stale once the Beijing date rolls over.
        const sameDay = Number(cached.dayStart) === getBeijingDayStartUnix();
        setMarketData(symbol, Number(cached.price), sameDay ? Number(cached.change) : NaN, true, '暂不可用', cached.basis);
      }
      else setMarketData(symbol, NaN, NaN);
    } catch (cacheError) {
      setMarketData(symbol, NaN, NaN);
    }
  }
}

// Beijing-day basis, matching the BTC ticker: change is measured from the last
// trade at or before Beijing midnight. interval=5m gives a bar right at that
// boundary (00:00 Beijing falls mid-session in US hours); range=2d covers the
// case where midnight sits in the previous session.
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
    return { symbol, price, change: ((price - reference) / reference) * 100 };
  } finally {
    clearTimeout(timeout);
  }
}

// Fallback only — TradingView can't give a Beijing-day basis, so its change is
// vs previous close and the ticker relabels itself accordingly.
async function fetchTradingViewQuotes() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    // No Content-Type header on purpose: application/json makes this a preflighted
    // request, and TradingView's scanner rejects the preflight. Omitting it leaves a
    // CORS-safelisted text/plain body, which the endpoint parses fine.
    const response = await fetch('https://scanner.tradingview.com/america/scan', {
      method: 'POST',
      body: JSON.stringify({
        symbols: { tickers: ['NASDAQ:MSTR', 'NASDAQ:QQQ'], query: { types: [] } },
        columns: ['close', 'change']
      }),
      signal: controller.signal,
      cache: 'no-store'
    });
    if (!response.ok) throw new Error('Stock price request failed');
    const data = await response.json();
    const rows = Array.isArray(data?.data) ? data.data : [];
    return ['MSTR', 'QQQ'].map(symbol => {
      const row = rows.find(item => item?.s === `NASDAQ:${symbol}`);
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
    quotes.forEach(quote => saveStockQuote(quote.symbol, quote.price, quote.change));
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
  const sign = profit >= 0 ? '+' : '';
  currentReturns.chartTotal = final;
  document.querySelector('#chart-total').textContent = metricMoney(final);
  document.querySelector('#chart-delta').textContent = `${sign}${metricMoney(profit)}`;
  document.querySelector('#chart-percent').textContent = `${changePercent >= 0 ? '+' : ''}${changePercent.toFixed(2)}%`;
  document.querySelector('#chart-change').classList.toggle('is-loss', profit < 0);
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
  const pointChangeText = `${pointChange > 0 ? '+' : ''}${pointChange.toFixed(2)}%`;
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
