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
// ── 资产 logo ────────────────────────────────────────────────────────
// 全站四处共用：顶部行情条、持仓行、资产搜索结果、快捷添加推荐区。
// 两个源分工，都是「按圆形满铺设计」的图标，不往仓库里塞图片：
//   股票 / ETF → Parqet   加密货币 → CoinCap
// 为什么不用 FMP：它给的是原始品牌图片而非图标——有的自带白底、有的是方形带
// 底色、有的是透明背景的纯文字（Vanguard 在深色模式下几乎看不见）。拼在一排
// 圆形容器里必然参差。Parqet / CoinCap 都已经做成统一的圆形图标。
//
// 两家查不到时都返回 404 而不是占位图，所以「加载失败」可以放心当成
// 「这个标的没有 logo」，直接回退首字母。
//
// 结果按 quoteSymbol 记住，**并且落到 localStorage**：持仓页每 60 秒重渲染一次，
// 没有缓存的话没 logo 的标的会反复打 404、有 logo 的每次都先闪一下首字母。只放
// 内存里还不够 —— 每次刷新都要重新按序试一遍候选，哪个源当时慢/连不上，这一轮
// 就落到下一个源，同一个币今天是新图明天是旧图，看起来就是「logo 不稳定」。
// 存下命中的地址后，之后每次刷新都直接铺同一张，只有它真的加载失败才重新找。
//
// 「查不到」的结论也存，但只存一天：新上市的币过阵子就会有图了。
//
// 这一整块必须留在 marketAssets 之前：renderMarketTicker 在模块顶层就被调用，
// 而 assetLogoStatus 是 const，定义在后面会直接抛 TDZ 错误。
const ASSET_LOGO_CACHE_KEY = 'jiujiucat-asset-logos';
const ASSET_LOGO_TTL = 7 * 24 * 60 * 60 * 1000;
const ASSET_LOGO_FAIL_TTL = 24 * 60 * 60 * 1000;

function loadAssetLogoCache() {
  const cache = new Map();
  try {
    const saved = JSON.parse(localStorage.getItem(ASSET_LOGO_CACHE_KEY) || '{}');
    const now = Date.now();
    for (const [symbol, entry] of Object.entries(saved)) {
      const url = entry?.url;
      const savedAt = Number(entry?.savedAt);
      if (typeof url !== 'string' || !Number.isFinite(savedAt)) continue;
      if (now - savedAt >= (url === 'fail' ? ASSET_LOGO_FAIL_TTL : ASSET_LOGO_TTL)) continue;
      cache.set(symbol, { url, savedAt });
    }
  } catch {
    // 缓存坏了就从空的开始，重新解析一遍即可。
  }
  return cache;
}

const assetLogoStatus = loadAssetLogoCache();

function persistAssetLogoCache() {
  try {
    localStorage.setItem(ASSET_LOGO_CACHE_KEY, JSON.stringify(Object.fromEntries(assetLogoStatus)));
  } catch {
    // 存不下（隐私模式/配额满）就退化成纯内存缓存，功能不受影响。
  }
}

function rememberAssetLogo(quoteSymbol, url) {
  assetLogoStatus.set(quoteSymbol, { url, savedAt: Date.now() });
  persistAssetLogoCache();
}

function forgetAssetLogo(quoteSymbol) {
  assetLogoStatus.delete(quoteSymbol);
  persistAssetLogoCache();
}

// 加密货币优先用 CoinMarketCap 的图：它跟着品牌更新，CoinCap 那套还停在几年前
// （OKB 2025 年已经换成黑底棋盘格，CoinCap 至今给的是旧的蓝色渐变图）。
//
// CMC 只认数字 ID。曾经为此在前端硬编码过 34 个币的映射表，漏得多又要人手维护，
// 所以当时整个换成了按代码索引的 CoinCap。这回换回来但不再硬编码：
// /api/crypto-logos 由 Worker 拉一次市值前 1000 的列表、压成 {代码: ID} 返回，
// 前端缓存一天。CoinCap 退居兜底 —— 1000 名开外、或改过代码的币（RNDR 在 CMC
// 已经叫 RENDER）在表里找不到，仍然按代码去 CoinCap 试一次。
const CRYPTO_ID_KEY = 'jiujiucat-cmc-crypto-ids';
const CRYPTO_ID_TTL = 24 * 60 * 60 * 1000;

function loadCachedCryptoIds() {
  try {
    const cached = JSON.parse(localStorage.getItem(CRYPTO_ID_KEY) || 'null');
    // 老版本缓存的是一张扁平的 {代码: ID}，没有 names —— 当过期处理，重新拉一次。
    if (cached?.map?.ids && Date.now() - Number(cached.savedAt) < CRYPTO_ID_TTL) return cached.map;
  } catch {
    // 缓存坏了当没有，下面会重新拉。
  }
  return null;
}

let cryptoLogoIds = loadCachedCryptoIds() || { ids: {}, names: {} };

async function refreshCryptoLogoIds() {
  if (loadCachedCryptoIds()) return;
  try {
    // ?v=2 是给边缘缓存换个键：返回结构从扁平的 {代码: ID} 变成了
    // { ids, names }，不换键的话新前端会在长达 6 小时里读到旧结构的缓存，
    // 校验不过就整轮退回 CoinCap。以后再改结构，记得同步递增这个数。
    const response = await fetch('/api/crypto-logos?v=2', { cache: 'no-store' });
    if (!response.ok) throw new Error('crypto logo map failed');
    const map = await response.json();
    if (!map?.ids || typeof map.ids !== 'object' || Array.isArray(map.ids)) throw new Error('bad crypto logo map');
    cryptoLogoIds = { ids: map.ids, names: map.names && typeof map.names === 'object' ? map.names : {} };
    localStorage.setItem(CRYPTO_ID_KEY, JSON.stringify({ savedAt: Date.now(), map: cryptoLogoIds }));
    // 表通常比首屏晚到：清掉已经落到 CoinCap 的解析结果，重渲染一次换成 CMC 的图。
    assetLogoStatus.clear();
    persistAssetLogoCache();
    renderMarketTicker(marketAssets[currentMarketIndex]);
    if (!document.querySelector('#portfolio-app').hidden) renderHoldings();
  } catch {
    // 拿不到就继续用 CoinCap。logo 不在关键路径上，本地静态预览也没有这个端点。
  }
}

const cmcLogo = id => `https://s2.coinmarketcap.com/static/img/coins/64x64/${id}.png`;
const coinCapLogo = bare => `https://assets.coincap.io/assets/icons/${bare.toLowerCase()}@2x.png`;
// 最后一道兜底：Cryptofonts/cryptoicons（jsDelivr 直连 GitHub，按代码索引）。
// 只放在最后 —— 这套图风格不统一，有的是画好底色的圆形徽标（USDT/USDG），有的
// 是纯色字形不带底（BTC 只有一个橙色 ₿），OKB 那张甚至整张都是白色，铺在浅色
// 背景上等于看不见。仓库本身也早就不更新了，OKB 还是换标之前的老图。所以它只
// 用来救「CMC 和 CoinCap 都没有」的长尾币 —— 那种情况本来只能显示首字母。
const cryptoIconsLogo = bare => `https://cdn.jsdelivr.net/gh/Cryptofonts/cryptoicons@master/SVG/${bare.toLowerCase()}.svg`;
const parqetLogo = symbol => `https://assets.parqet.com/logos/symbol/${encodeURIComponent(symbol)}?format=png`;

// 稳定生息持仓的「标的名」是用户手打的，可能是 USDT、USDG 这类代码，也可能是
// 「活期」这种词。不像代码的就一个候选都不给，直接退首字母 —— 拿它去拼图片地址
// 只会白打两次 404。
// 放到 20 位是因为 Yahoo 会给重名的币加数字后缀（FARTCOIN34814），12 位卡不住。
const TICKER_PATTERN = /^[A-Z0-9]{1,20}$/;

// 和 Worker 里的 normalizeCoinName 必须保持一致，两边都要能把
// Yahoo 的 "Render USD" 和 CMC 的 "Render" 归一成同一个 render。
function normalizeCoinName(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '').replace(/usd$/, '');
}

// 先按代码查，查不到再按名称查。**名称这条是给代码对不上的情况准备的**：
// Yahoo 会给重名的币加数字后缀（FARTCOIN34814-USD），CMC 那边也可能改过代码
// （RNDR 现在叫 RENDER）—— 这两种情况下代码永远对不上，名字却是对得上的。
function cryptoLogoCandidates(bare, name) {
  if (!TICKER_PATTERN.test(bare)) return [];
  const byName = Number(cryptoLogoIds.names?.[normalizeCoinName(name)]);
  const id = Number(cryptoLogoIds.ids?.[bare]) || byName;
  // 校验成正整数再拼进 URL：这张表是从网络上拿的，别把任意内容拼进地址里。
  const cmc = Number.isInteger(id) && id > 0 ? [cmcLogo(id)] : [];
  return [...cmc, coinCapLogo(bare), cryptoIconsLogo(bare)];
}

// 判断是不是加密货币不能只看 assetType：旧持仓里的加密货币没存 -USD 后缀，
// normalizeAsset 只能按后缀猜，ETH 这种会被判成 EQUITY（loadHoldings 的兼容
// 特判只覆盖了 BTC）。所以两条候选都给出去，按序试第一个能加载的。
function assetLogoCandidates(quoteSymbol, assetType, name) {
  const bare = quoteSymbol.replace(/-USD$/, '').toUpperCase();
  const crypto = cryptoLogoCandidates(bare, name);
  const stock = parqetLogo(quoteSymbol);
  // 稳定生息持仓的 assetType 是 'STABLE'，填的标的名就是 USDT / USDG 这类稳定币
  // ——它们在 Parqet（股票/ETF 源）永远 404，得和加密货币一样先走加密源。
  // 之前没算上这一类，USDT 每次都是先白打一次 Parqet 404，再落到兜底的 CoinCap，
  // 拿到的正是那张旧的渐变圆图，CMC 那条候选根本轮不上。
  const cryptoFirst = assetType === 'CRYPTOCURRENCY' || assetType === 'STABLE';
  // 手打的名字不像代码时 crypto 是空的，这时连 Parqet 都不用试。
  if (cryptoFirst) return crypto.length ? [...crypto, stock] : [];
  // 其余先试股票源，失败再按「可能是漏判类型的旧数据」补试一次加密源。
  return [stock, ...crypto];
}

function applyAssetLogo(element, quoteSymbol, fallbackText, assetType, name) {
  element.textContent = fallbackText;
  element.classList.remove('has-logo');
  element.style.backgroundImage = '';
  if (!quoteSymbol) return;

  const show = url => {
    element.textContent = '';
    element.classList.add('has-logo');
    element.style.backgroundImage = `url("${url}")`;
  };

  const candidates = assetLogoCandidates(quoteSymbol, assetType, name);
  const resolve = () => {
    (function tryNext(i) {
      if (i >= candidates.length) return rememberAssetLogo(quoteSymbol, 'fail');
      const url = candidates[i];
      const probe = new Image();
      probe.onload = () => { rememberAssetLogo(quoteSymbol, url); show(url); };
      probe.onerror = () => tryNext(i + 1);
      probe.src = url;
    })(0);
  };

  // 缓存存的是「哪个 URL 成功过」，命中就同步铺上，不必再等一次 onload
  // （图片本身走浏览器缓存）。'fail' 表示所有候选都试过且都没有。
  const cached = assetLogoStatus.get(quoteSymbol)?.url;
  if (cached === 'fail') return;
  if (!cached) return resolve();

  show(cached);
  // 缓存的地址也有今天打不开的时候（源站故障、被墙）。那就当没缓存过：擦掉这条
  // 记录、退回首字母、重新按序试一遍候选，而不是留一个空白的圆圈在那里。
  const verify = new Image();
  verify.onerror = () => {
    forgetAssetLogo(quoteSymbol);
    element.textContent = fallbackText;
    element.classList.remove('has-logo');
    element.style.backgroundImage = '';
    resolve();
  };
  verify.src = cached;
}

// quoteSymbol / assetType 是给 applyAssetLogo 用的：行情条的图标和持仓、搜索、
// 推荐区走同一套解析，不再各自维护仓库里的 svg。
const marketAssets = [
  { symbol: 'BTC', quoteSymbol: 'BTC-USD', assetType: 'CRYPTOCURRENCY', name: 'Bitcoin', basis: '北京时间今日', price: null, change: null, series: [], cached: false, status: '获取中' },
  { symbol: 'MSTR', quoteSymbol: 'MSTR', assetType: 'EQUITY', name: 'MSTR', basis: '北京时间今日', price: null, change: null, series: [], cached: false, status: '获取中', equity: true },
  { symbol: 'QQQ', quoteSymbol: 'QQQ', assetType: 'EQUITY', name: 'QQQ', basis: '北京时间今日', price: null, change: null, series: [], cached: false, status: '获取中', equity: true }
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
  applyAssetLogo(document.querySelector('#market-icon'), asset.quoteSymbol, asset.symbol.slice(0, 1), asset.assetType, asset.name);
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

// 走势序列统一存成 [时间戳(ms), 价格] 对。只存价格数组时没法按时间对齐 ——
// 组合走势图要把好几个标的叠在一起，而它们的 K 线根数和覆盖时长都不一样。
// 旧缓存里就是纯数字数组，这里直接丢掉，下一轮刷新会换成新格式。
const SERIES_MAX_POINTS = 240;

function normalizeSeries(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter(point => Array.isArray(point) && Number.isFinite(Number(point[0])) && Number(point[1]) > 0)
    .map(point => [Number(point[0]), Number(point[1])])
    .sort((a, b) => a[0] - b[0]);
}

function setMarketData(symbol, price, change, cached = false, status = '暂不可用', basis, series = []) {
  const asset = marketAssets.find(item => item.symbol === symbol);
  if (!asset) return;
  if (basis) asset.basis = basis;
  asset.price = Number.isFinite(price) ? price : null;
  asset.change = Number.isFinite(change) ? change : null;
  if (Array.isArray(series) && series.length > 1) asset.series = normalizeSeries(series);
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
    const series = prices
      .filter(point => Number.isFinite(Number(point?.[0])) && Number(point?.[1]) > 0)
      .map(point => [Number(point[0]), Number(point[1])])
      .slice(-SERIES_MAX_POINTS);
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
    // Yahoo 的 timestamp 是秒，序列统一用毫秒。原来只留最后 80 根收盘价：
    // 加密货币 24 小时连续成交，80 根 30 分钟线只有 40 小时，美股 80 根却横跨
    // 整整 5 天 —— 两条序列叠在一起画的时候完全对不上。
    const series = timestamps
      .map((time, index) => [Number(time) * 1000, Number(closes[index])])
      .filter(point => Number.isFinite(point[0]) && Number.isFinite(point[1]) && point[1] > 0)
      .slice(-SERIES_MAX_POINTS);
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
refreshCryptoLogoIds();
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
// 曾经用 jiujiucat-portfolio-unlocked 记「解锁过就一直放行」，结果是点过一次
// 「先用本地版」的人再也回不到登录页。现在持仓只认真实会话，这里把历史遗留的
// 标记清掉，老用户下次进来一律回到登录页。
localStorage.removeItem('jiujiucat-portfolio-unlocked');
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
  { symbol: 'BTC', quoteSymbol: 'BTC-USD', name: 'Bitcoin', assetType: 'CRYPTOCURRENCY', exchange: 'CCC' }
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
        // 被手动删掉的结算日（北京日期串）。删一天等于那天没发利息。
        interestSkips: Array.isArray(item.interestSkips) ? item.interestSkips.filter(date => typeof date === 'string') : [],
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
// 记录弹层现在两种记录共用：'dividend' 是分红，'interest' 是稳定生息的每日发放。
// DOM 里的 id / class 仍叫 dividend-records-*，是历史名字，别按它判断当前模式。
let recordsSheetMode = 'dividend';
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

// 能不能记分红，看的是「有没有市价」这一件事：股票、ETF、加密货币都能，只有
// 手填的稳定生息（STABLE）不能 —— 那类没有份数，收益本来就按本金和年化算。
// 原来这里写死 EQUITY，于是 ETF 和加密货币都被挡在外面；实际上 ETF 本来就按份
// 派息，加密货币也有各种按持仓发放的分红/空投。
const DIVIDEND_ASSET_TYPES = new Set(['EQUITY', 'ETF', 'CRYPTOCURRENCY']);

function canAssetRecordDividends(assetType) {
  return DIVIDEND_ASSET_TYPES.has(assetType);
}

// 股票按「股」，ETF 和加密货币按「份」——持仓行里数量单位一直是「份」，
// 这里跟着走，不要在同一个资产上一会儿股一会儿份。
function perShareLabel(assetType) {
  return assetType === 'EQUITY' ? '每股' : '每份';
}

function isDividendHolding(holding) {
  return holding.holdingKind === 'dividend' && canAssetRecordDividends(holding.assetType);
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
  // 已存在的分红记录冻结除息时的数量；后续加减仓只影响下一次分红。
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

function holdingInterestSkips(holding) {
  return Array.isArray(holding.interestSkips) ? [...new Set(holding.interestSkips)] : [];
}

// 已结算的每一天（北京日期串）。第 k 天 = 起息日次日 16:00 起的第 k 个 24 小时。
function interestSettlementDates(holding, timestamp = Date.now()) {
  const first = firstInterestSettlement(holding.interestStartDate);
  const count = settledInterestDays(holding, timestamp);
  if (!Number.isFinite(first) || count <= 0) return [];
  return Array.from({ length: count }, (_, index) => beijingDateString(first + index * DAY_MS));
}

// 删掉的结算日不计息。**单利和复利都可以归结为「有效天数」**：单利是乘法、
// 复利是连乘，少一天分别等于少一项、少一个因子，不必逐日累乘回放。
// 这里不展开整张日期表再取交集 —— 组合走势图会对每个采样点算一次利息，
// 展开几百个日期串会白白跑上万次。日期串是 YYYY-MM-DD，直接按字典序比区间。
function skippedInterestDays(holding, timestamp = Date.now()) {
  const skips = holdingInterestSkips(holding);
  if (!skips.length) return 0;
  const first = firstInterestSettlement(holding.interestStartDate);
  const count = settledInterestDays(holding, timestamp);
  if (!Number.isFinite(first) || count <= 0) return 0;
  const firstDate = beijingDateString(first);
  const lastDate = beijingDateString(first + (count - 1) * DAY_MS);
  return skips.filter(date => date >= firstDate && date <= lastDate).length;
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
  if (!isInterestHolding(holding)) return 0;
  const days = settledInterestDays(holding, timestamp) - skippedInterestDays(holding, timestamp);
  return holdingInterestForDays(holding, Math.max(0, days));
}

// 逐日的发放明细：第 n 个未跳过的结算日拿到的，是「累计到 n 天」减「累计到
// n-1 天」。单利下每天一样多，复利下逐日变大 —— 都由同一个公式推出来，
// 不会和持仓行上那个总数打架。
function interestRecordEntries(holding, timestamp = Date.now()) {
  const skips = new Set(holdingInterestSkips(holding));
  const entries = [];
  let effectiveDays = 0;
  let accrued = 0;
  for (const date of interestSettlementDates(holding, timestamp)) {
    if (skips.has(date)) continue;
    effectiveDays += 1;
    const total = holdingInterestForDays(holding, effectiveDays);
    entries.push({ holding, date, amount: total - accrued });
    accrued = total;
  }
  return entries;
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

// 走势图的时间轴：最近 5 个交易日，48 个采样点。
const TREND_POINT_COUNT = 48;
const TREND_WINDOW_MS = 5 * DAY_MS;

// 各标的的价格序列必须先对齐到同一条时间轴再相加。之前是按「数组下标」按比例
// 对齐的：加密货币一天 48 根 30 分钟线、美股一天只有 13 根，同样根数覆盖的真实
// 时间差好几倍，叠出来的曲线根本不是时间序列；每刷新一次各自的窗口滑动幅度还
// 不一样，形状自然一直在变。问题不在「数据时间太短」，在对齐方式。
function portfolioProfitTrendValues() {
  if (!holdings.length) return [];
  const now = Date.now();
  const grid = Array.from({ length: TREND_POINT_COUNT }, (_, index) =>
    now - TREND_WINDOW_MS * (TREND_POINT_COUNT - 1 - index) / (TREND_POINT_COUNT - 1));
  const totals = new Array(TREND_POINT_COUNT).fill(0);
  // 至少得有一个随时间变化的来源，否则画出来是条直线，不如老实说没有历史数据。
  let hasHistory = false;

  for (const holding of holdings) {
    // 生息持仓本身就是时间的函数，直接按每个采样时刻算已结算的利息。
    if (holding.holdingKind === 'interest') {
      if (!(Number(holding.principal) > 0)) return [];
      grid.forEach((time, index) => { totals[index] += holdingAccruedInterest(holding, time); });
      hasHistory = true;
      continue;
    }
    const quantity = Number(holding.quantity);
    const costPerShare = Number(holding.costPerShare);
    // 成本或数量缺失时无法计算这笔持仓对组合盈亏的贡献。
    if (!Number.isFinite(quantity) || quantity <= 0 || !Number.isFinite(costPerShare) || costPerShare <= 0) return [];
    const history = holdingPriceHistory(holding);
    if (history.length > 1) {
      hasHistory = true;
      resampleSeries(history, grid).forEach((price, index) => {
        totals[index] += (price - costPerShare) * quantity;
      });
      continue;
    }
    // 手动价格、TradingView 备用报价只有当前一个点：作为恒定基线参与组合，
    // 而不是让任意一笔缺历史的持仓把整张图拉成直线。
    const price = resolveHoldingPrice(holding);
    if (!Number.isFinite(price) || price <= 0) return [];
    const profit = (price - costPerShare) * quantity;
    for (let index = 0; index < totals.length; index++) totals[index] += profit;
  }
  return hasHistory ? totals : [];
}

function holdingPriceHistory(holding) {
  const known = normalizeSeries(marketAssets.find(asset => asset.symbol === holding.symbol)?.series);
  if (known.length > 1) return known;
  return normalizeSeries(holdingPrices.get(holding.quoteSymbol || holding.symbol)?.series);
}

// 前向填充式重采样：每个时刻取该时刻之前最后一个已知价。序列开始之前的时刻用
// 最早的价格兜底 —— 覆盖时长比别人短的标的（如只回溯 40 小时的加密货币）在前
// 半段保持水平，而不是凭空插值出一段假行情。
function resampleSeries(points, grid) {
  let cursor = 0;
  let last = points[0][1];
  return grid.map(time => {
    while (cursor < points.length && points[cursor][0] <= time) last = points[cursor++][1];
    return last;
  });
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
  // 分段而不是拼成一整串：窄屏上这行要能按「份数 / 成本 / 年化」这种语义边界
  // 折行，一整串就只能从中间截断，被截掉的往往正是成本。
  let detail;
  // 成本只在点开后的盈亏明细里给。行里留「有多少」这一个字段：市价持仓是份数，
  // 生息持仓是本金金额 —— 后者不带「本金」两个字，一列金额自己说得清。
  detail = metrics.kind === 'interest'
    ? [money.format(metrics.cost)]
    : [`${metrics.quantity} 份`];
  // 除息日 / 派息日 / 分红频率不再挤在持仓行里 —— 一行塞六七个字段，窄屏上
  // 怎么排都是坏的。它们移到点开后的盈亏明细弹层（#profit-event-card）。
  return {
    symbol: holding.symbol,
    quoteSymbol: holding.quoteSymbol,
    assetType: holding.assetType,
    // 名称是 logo 解析按名字兜底用的（代码对不上时），不显示在行里。
    name: holding.name,
    detail,
    value: metrics.value,
    profit: metrics.profit,
    pct: metrics.pct,
    hasValue: metrics.hasValue,
    profitLabel: metrics.kind === 'interest' ? '利息' : '盈亏',
    typeTag: metrics.kind === 'interest'
      ? (holding.interestMode === 'compound' ? '复利' : '单利')
      : null,
    // 年化跟在代号后面当数字芯片，标签词省掉 —— 下面那行就只剩本金/成本了。
    rateTag: (metrics.kind === 'interest' || metrics.kind === 'hybrid') && annualRate > 0
      ? `${annualRate.toFixed(2)}%`
      : null
  };
}

function appendHoldingRowContent(row, model, expandable = false) {
  // 合并组展开后的子行不放 logo：同一个标的的几笔仓位，图标一模一样地竖着排
  // 四个，只是在重复上面那一行已经说过的话。
  const isSubrow = row.classList.contains('holding-subrow');
  const logo = document.createElement('span');
  logo.className = 'holding-logo';
  if (!isSubrow) applyAssetLogo(logo, model.quoteSymbol, model.symbol.slice(0, 2), model.assetType, model.name);

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
  if (model.rateTag) {
    const rateTag = document.createElement('span');
    rateTag.className = 'holding-rate-tag';
    rateTag.textContent = model.rateTag;
    // 只有数字，读屏时补一句它是什么。
    rateTag.setAttribute('aria-label', `年化 ${model.rateTag}`);
    titleLine.append(rateTag);
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
  detail.replaceChildren(...model.detail.map(part => {
    const segment = document.createElement('span');
    segment.textContent = part;
    return segment;
  }));
  // 没有可写的字段时（生息持仓）连这个空元素都不要，否则会撑出一段空行高。
  detail.hidden = !model.detail.length;
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
    // 「盈亏」「利息」这两个词不显示 —— 带正负号的绿/红金额已经说明了它是什么。
    // 但读屏拿到的是一串裸数字，所以补一个 aria-label 把词说回来。
    pl.setAttribute('aria-label', `${model.profitLabel} ${signedMoney(profit)}`);
    const plValue = document.createElement('span');
    plValue.className = 'holding-pl-value';
    plValue.textContent = signedMoney(profit);
    pl.append(plValue);
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

  if (isSubrow) row.append(meta, right);
  else row.append(logo, meta, right);
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
    ? [money.format(totalCost)]
    : allMarketBased && totalQuantity > 0
      ? [`${totalQuantity} 份`]
      : [`综合成本 ${money.format(totalCost)}`];
  const rates = new Set(group.filter(isInterestHolding).map(item => Number(item.annualRate) || 0));
  return {
    symbol: group[0].symbol,
    quoteSymbol: group[0].quoteSymbol,
    assetType: group[0].assetType,
    name: group[0].name,
    detail,
    // 合并的几笔年化不一致时不显示 —— 挑其中一个当代表就是谎报。
    rateTag: allStable && rates.size === 1 && [...rates][0] > 0 ? `${[...rates][0].toFixed(2)}%` : null,
    count: group.length,
    value: totalValue,
    profit: totalProfit,
    pct: totalCost > 0 && Number.isFinite(totalProfit) ? totalProfit / totalCost * 100 : 0,
    hasValue: Number.isFinite(totalValue),
    profitLabel: allStable ? '利息' : '盈亏',
    // 合并组里计息方式可能不一致，那就别谎报成其中一种。
    // 合并的几笔计息方式不一致时不给标签 —— 挑一个是谎报，写「稳定生息」又是
    // 一句不含信息的废话。展开后每一笔各自标着自己的方式。
    typeTag: allStable
      ? (group.every(item => item.interestMode === 'compound') ? '复利'
        : group.every(item => item.interestMode !== 'compound') ? '单利'
        : null)
      : null
  };
}

// 展开状态记在渲染之外：持仓列表每 60 秒整体重建一次（renderHoldings 用
// replaceChildren），状态挂在 DOM 上的话展开的组会自己合上。
const expandedHoldingGroups = new Set();

function createMergedHoldingGroup(group, key) {
  const wrapper = document.createElement('div');
  wrapper.className = 'holding-group';
  const summary = document.createElement('button');
  summary.type = 'button';
  summary.className = 'holding-row holding-group-summary';
  appendHoldingRowContent(summary, mergedHoldingModel(group), true);

  const lots = document.createElement('div');
  lots.className = 'holding-group-lots';
  lots.replaceChildren(...group.map(holding => createHoldingRow(holding, 'holding-row holding-subrow')));

  // 合并卡点开是展开这一组的明细，不再是盈亏弹层：合并后用户想看的是「这几笔
  // 分别是什么」，单笔的盈亏明细在展开后的子行上照样点得到。
  const applyExpanded = expanded => {
    lots.hidden = !expanded;
    summary.setAttribute('aria-expanded', String(expanded));
    summary.setAttribute('aria-label',
      `${expanded ? '收起' : '展开'} ${group[0].symbol} 的 ${group.length} 笔持仓`);
  };
  applyExpanded(expandedHoldingGroups.has(key));
  summary.addEventListener('click', () => {
    const expanded = !expandedHoldingGroups.has(key);
    if (expanded) expandedHoldingGroups.add(key); else expandedHoldingGroups.delete(key);
    applyExpanded(expanded);
  });
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
    list.replaceChildren(...[...groups.entries()].map(([key, group]) => (
      group.length > 1 ? createMergedHoldingGroup(group, key) : createHoldingRow(group[0])
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

    // 和持仓行、搜索结果共用同一套 logo 解析。原先只认 asset.icon 这个内置
    // 字段（仅 BTC 有），其余一律首字母。
    const icon = document.createElement('span');
    icon.className = 'recommend-icon recommend-letter';
    applyAssetLogo(icon, asset.quoteSymbol, asset.symbol.slice(0, 1), asset.assetType, asset.name);

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
    dividendDetail.textContent = '暂无已确认分红';
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
  const interestHoldings = holdingsForBreakdown.filter(isInterestHolding);
  interestRow.hidden = !interestHoldings.length;
  if (interestHoldings.length) {
    const modes = new Set(interestHoldings.map(holding => holding.interestMode === 'compound' ? '复利' : '单利'));
    const modeLabel = modes.size === 1 ? [...modes][0] : '单利 + 复利';
    document.querySelector('#profit-interest-detail').textContent = `${modeLabel} · 每日北京时间 16:00 更新`;
  }
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
    document.querySelector('#profit-per-share-label').textContent =
      `${perShareLabel(dividendHoldings[0].assetType)}分红`;
    document.querySelector('#profit-dividend-frequency').textContent =
      `${DIVIDEND_FREQUENCY_LABELS[latestRecord.frequency || dividendHoldings[0].dividendFrequency] || '不固定'}分红`;
    document.querySelector('#profit-dividend-per-share').textContent = money.format(Number(latestRecord.perShare) || 0);
    document.querySelector('#profit-ex-date').textContent = formatPortfolioDate(latestRecord.exDate);
    document.querySelector('#profit-pay-date').textContent = formatPortfolioDate(latestRecord.payDate);
  }

  const recordsButton = document.querySelector('#profit-dividend-records-btn');
  recordsButton.hidden = !dividendHoldings.length;
  document.querySelector('#profit-dividend-records-count').textContent = `${dividendRecords.length} 条记录`;

  const interestRecordsButton = document.querySelector('#profit-interest-records-btn');
  const interestRecordCount = interestHoldings
    .reduce((count, holding) => count + interestRecordEntries(holding).length, 0);
  interestRecordsButton.hidden = !interestHoldings.length;
  document.querySelector('#profit-interest-records-count').textContent = `${interestRecordCount} 条记录`;

  // 每份成本从持仓行搬到这里。多笔合并时它是按份数加权的均价，标签也跟着改，
  // 免得看成「其中某一笔的成本」。
  const costMetrics = metrics.filter(metric => metric.kind !== 'interest');
  const costQuantity = costMetrics.reduce((sum, metric) => sum + (Number(metric.quantity) || 0), 0);
  const unitCost = costQuantity > 0
    ? costMetrics.reduce((sum, metric) => sum + (Number(metric.cost) || 0), 0) / costQuantity
    : null;
  document.querySelector('#profit-sheet-foot').textContent = [
    unitCost === null ? null : `${holdingsForBreakdown.length > 1 ? '均价' : '成本'} ${money.format(unitCost)}/份`,
    `${stableOnly ? '本金' : '持仓成本'} ${money.format(totalCost)}`,
    `当前资产 ${Number.isFinite(totalValue) ? money.format(totalValue) : '$—'}`
  ].filter(Boolean).join(' · ');
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

// 记录弹层只列最近 15 条。生息持仓一天一条，存半年就是 180 条 —— 再往前翻
// 已经没人看，却要一直渲染。**汇总金额仍按全部记录算**，截断的只是列表。
const RECORDS_DISPLAY_LIMIT = 15;

function recordsMoreNote(total) {
  if (total <= RECORDS_DISPLAY_LIMIT) return null;
  const note = document.createElement('p');
  note.className = 'records-more-note';
  note.textContent = `只显示最近 ${RECORDS_DISPLAY_LIMIT} 次，共 ${total} 次`;
  return note;
}

function dividendRecordEntries(items = dividendRecordsContext) {
  return items.flatMap(holding => holdingDividendRecords(holding).map(record => ({ holding, record })))
    .sort((a, b) => String(b.record.exDate).localeCompare(String(a.record.exDate)));
}

function renderDividendRecordsSheet() {
  const title = recordsSheetMode === 'interest' ? '利息发放记录' : '分红记录';
  document.querySelector('#dividend-records-title').textContent = title;
  document.querySelector('#dividend-records-empty').textContent = `暂无${title.replace('记录', '')}记录`;
  document.querySelector('#dividend-records-total-label').textContent =
    recordsSheetMode === 'interest' ? '已发放利息' : '已确认分红';
  if (recordsSheetMode === 'interest') return renderInterestRecordsSheet();

  const allEntries = dividendRecordEntries();
  const entries = allEntries.slice(0, RECORDS_DISPLAY_LIMIT);
  const list = document.querySelector('#dividend-records-list');
  const empty = document.querySelector('#dividend-records-empty');
  const symbols = [...new Set(dividendRecordsContext.map(holding => holding.symbol))];
  // 汇总按全部记录算，不受列表截断影响。
  const confirmedTotal = allEntries.reduce((total, { record }) => (
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
    detail.textContent = `除息日 ${formatPortfolioDate(record.exDate)} · 派息日 ${formatPortfolioDate(record.payDate)}`
      + ` · ${perShareLabel(holding.assetType)} ${money.format(record.perShare)}`;
    copy.append(title, detail);

    const amount = document.createElement('span');
    const recordAmount = Number(record.amount) || 0;
    amount.className = `dividend-record-amount ${movementTone(recordAmount)}`;
    amount.textContent = signedMoney(recordAmount);

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'dividend-record-delete';
    remove.setAttribute('aria-label', `删除 ${holding.symbol} ${formatPortfolioDate(record.exDate)} 的分红记录`);
    const removeIcon = document.createElement('i');
    removeIcon.className = 'ri-delete-bin-line';
    removeIcon.setAttribute('aria-hidden', 'true');
    remove.append(removeIcon);
    remove.addEventListener('click', () => requestConfirmation({
      title: '删除分红记录',
      body: `删除后，总盈亏将减少 ${money.format(Number(record.amount) || 0)}。`,
      confirmLabel: '删除记录',
      action: () => deleteDividendRecord(holding.id, record.id)
    }));

    row.append(copy, amount, remove);
    return row;
  }));
  const note = recordsMoreNote(allEntries.length);
  if (note) list.append(note);
}

// 利息按天列，一笔生息持仓存了几个月就是几百条 —— 按月分组，每组一个带小计的
// 标题，滚起来才找得到某一天。
function renderInterestRecordsSheet() {
  const list = document.querySelector('#dividend-records-list');
  const empty = document.querySelector('#dividend-records-empty');
  const allEntries = dividendRecordsContext
    .filter(isInterestHolding)
    .flatMap(holding => interestRecordEntries(holding))
    .sort((a, b) => b.date.localeCompare(a.date));
  const entries = allEntries.slice(0, RECORDS_DISPLAY_LIMIT);
  const symbols = [...new Set(dividendRecordsContext.map(holding => holding.symbol))];
  // 汇总是「已发放利息」的全部，和持仓行上那个数一致；列表才只给最近 15 条。
  const total = allEntries.reduce((sum, entry) => sum + entry.amount, 0);

  document.querySelector('#dividend-records-symbol').textContent =
    symbols.length === 1 ? symbols[0] : `${symbols.length} 个资产`;
  const totalEl = document.querySelector('#dividend-records-total');
  totalEl.textContent = signedMoney(total);
  totalEl.className = movementTone(total);
  empty.hidden = entries.length > 0;
  list.hidden = entries.length === 0;

  const nodes = [];
  let currentMonth = null;
  entries.forEach(entry => {
    const month = entry.date.slice(0, 7);
    if (month !== currentMonth) {
      currentMonth = month;
      // 月度小计按当月的全部记录算，不只是显示出来的那几条 —— 它是关于这个月的
      // 事实。列表被截断这件事由下面那行说明负责，不该让同一个月出现两个数。
      const monthTotal = allEntries
        .filter(item => item.date.startsWith(month))
        .reduce((sum, item) => sum + item.amount, 0);
      const head = document.createElement('div');
      head.className = 'records-month-head';
      const [year, monthPart] = month.split('-');
      head.innerHTML = `<span>${year} 年 ${Number(monthPart)} 月</span><span>${signedMoney(monthTotal)}</span>`;
      nodes.push(head);
    }
    nodes.push(interestRecordRow(entry));
  });
  const note = recordsMoreNote(allEntries.length);
  if (note) nodes.push(note);
  list.replaceChildren(...nodes);
}

function interestRecordRow({ holding, date, amount }) {
  const row = document.createElement('div');
  row.className = 'dividend-record-row';

  const copy = document.createElement('span');
  copy.className = 'dividend-record-copy';
  const title = document.createElement('strong');
  const mode = holding.interestMode === 'compound' ? '复利' : '单利';
  title.textContent = `${holding.symbol} · ${mode}`;
  const detail = document.createElement('small');
  detail.textContent = `结算日 ${formatPortfolioDate(date)} · 本金 ${money.format(holdingInterestPrincipal(holding))}`;
  copy.append(title, detail);

  const value = document.createElement('span');
  value.className = `dividend-record-amount ${movementTone(amount)}`;
  value.textContent = signedMoney(amount);

  const remove = document.createElement('button');
  remove.type = 'button';
  remove.className = 'dividend-record-delete';
  remove.setAttribute('aria-label', `删除 ${holding.symbol} ${formatPortfolioDate(date)} 的利息`);
  const removeIcon = document.createElement('i');
  removeIcon.className = 'ri-delete-bin-line';
  removeIcon.setAttribute('aria-hidden', 'true');
  remove.append(removeIcon);
  remove.addEventListener('click', () => requestConfirmation({
    title: '删除利息记录',
    // 复利下删掉一天，后面每天的利息也会跟着变小（少滚一天），所以只承诺
    // 「不少于」这个数，不写死一个会对不上的金额。
    body: holding.interestMode === 'compound'
      ? `${formatPortfolioDate(date)} 起将按未发放这一天重新计息，总利息至少减少 ${money.format(amount)}。`
      : `删除后，总利息将减少 ${money.format(amount)}。`,
    confirmLabel: '删除记录',
    action: () => skipInterestDay(holding.id, date)
  }));

  row.append(copy, value, remove);
  return row;
}

// 利息是按公式算出来的，没有「一条记录」可以删 —— 删的是「这天发过利息」这个
// 事实，落成 interestSkips 里的一个日期，计息时从有效天数里扣掉。
function skipInterestDay(holdingId, date) {
  const holding = holdings.find(item => item.id === holdingId);
  if (!holding) return;
  holding.interestSkips = [...new Set([...holdingInterestSkips(holding), date])];
  saveHoldings();
  renderHoldings();
  renderDividendRecordsSheet();
  if (!document.querySelector('#profit-sheet-overlay').hidden && profitSheetItems.length) {
    const trigger = profitSheetTrigger;
    openProfitSheet(profitSheetItems, profitSheetAction);
    profitSheetTrigger = trigger;
    document.querySelector('#dividend-records-close-btn').focus();
  }
  showToast('该日利息已删除，总利息已更新');
}

function openDividendRecordsSheet(items, mode = 'dividend') {
  clearTimeout(dividendRecordsCloseTimer);
  recordsSheetMode = mode;
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
  showToast('分红记录已删除，总盈亏已更新');
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
  const canRecordDividends = canAssetRecordDividends(selectedHoldingAsset?.assetType);
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
      preview.textContent = `填写数量与${perShareLabel(selectedHoldingAsset?.assetType)}分红后显示本次收益`;
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
  const canRecordDividends = baseKind === 'market' && canAssetRecordDividends(selectedHoldingAsset?.assetType);
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
  document.querySelector('#holding-market-income-label').textContent = '记录分红';
  const unit = perShareLabel(selectedHoldingAsset?.assetType);
  document.querySelector('#holding-dividend-per-share-label').textContent = `${unit}分红`;
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
    applyAssetLogo(mark, asset.quoteSymbol, asset.symbol.slice(0, 2), asset.assetType, asset.name);
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
      return showToast(`请填写${perShareLabel(selectedHoldingAsset?.assetType)}分红金额`);
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
document.querySelector('#profit-interest-records-btn').addEventListener('click', () => openDividendRecordsSheet(profitSheetItems, 'interest'));
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
  if (!document.querySelector('#cat-photo-viewer').hidden) return closeCatPhoto();
  if (!document.querySelector('#cat-sheet-overlay').hidden) return closeCatSheet();
  if (!document.querySelector('#profile-sheet-overlay').hidden) return closeProfileSheet();
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

// 同步状态不再常驻显示。「已同步」这三个字挂在那里几乎永远为真，属于噪音；
// 真正要让人知道的只有失败，那用 toast 说一次就够了。
function reportSyncFailure(message) {
  showToast(message);
}

// 身份会出现在截图和录屏里，完整邮箱没必要露出来。头尾各留几位是为了让本人
// 一眼认出是哪个账号，中间遮掉，**域名整段不显示** —— 「@gmail」对本人没有
// 任何信息量（自己用哪个邮箱当然知道），对别人反而是一条线索。
// 本地部分短于 6 位时不留尾巴：那种长度下「前三后二」几乎等于原样显示。
function maskEmail(email) {
  const at = email.lastIndexOf('@');
  const local = at < 1 ? email : email.slice(0, at);
  return local.length > 5
    ? `${local.slice(0, 3)}***${local.slice(-2)}`
    : `${local.slice(0, 1)}***`;
}

// ── 个人资料（用户名 + 头像）─────────────────────────────────────────
//
// 单独一张 profiles 表，不塞进 holdings 的 payload：那个 payload 是一整条持仓，
// 用户名放进去等于每条持仓都存一份副本，改名还得逐条重写。见 supabase/schema.sql。
const PROFILE_KEY = 'jiujiucat-profile';
const DEFAULT_AVATAR = 'ri-bear-smile-line';
// 头像值会直接当成 <i> 的 class 用，而云端那一行是用户自己可写的 —— 取值必须
// 限定在这张表里，不能把任意字符串当类名塞进 DOM。
// 每个头像自带一个纯色底（不带透明度，图标一律白色）—— 一屏十几个圆点，
// 只靠线条图形分不出谁是谁，颜色才是第一眼的识别位。深浅两个主题共用同一组色：
// 它们本来就不是从 token 派生的，是身份色。
const PROFILE_AVATARS = [
  { icon: 'ri-bear-smile-line', label: '小熊', color: '#D9772E' },
  { icon: 'ri-mickey-line', label: '米奇', color: '#6C5CE7' },
  { icon: 'ri-aliens-line', label: '外星人', color: '#0E9F6E' },
  { icon: 'ri-ghost-smile-line', label: '幽灵', color: '#3C7DE0' },
  { icon: 'ri-star-smile-line', label: '星星', color: '#C08A00' },
  { icon: 'ri-emotion-laugh-line', label: '笑脸', color: '#D9527A' },
  { icon: 'ri-robot-2-line', label: '机器人', color: '#1F7FBF' },
  { icon: 'ri-planet-line', label: '星球', color: '#7A5AF8' },
  { icon: 'ri-rocket-line', label: '火箭', color: '#E05A3C' },
  { icon: 'ri-flower-line', label: '小花', color: '#C2478F' },
  { icon: 'ri-fire-line', label: '火苗', color: '#D2451E' },
  { icon: 'ri-magic-line', label: '魔法棒', color: '#0E8F8F' }
];
// 未登录时的占位：中性灰，和任何一个已选头像都不一样，一眼能看出「还没设置」。
const GUEST_AVATAR_COLOR = '#8A8A8F';

// 猫。头像除了上面那 12 个图标，也可以是其中一只 —— 存成 'cat:<id>'。
// **file 为 null 表示照片还没到**：那一格只画一个带色边框的空位，不可选，
// 免得存进一个加载不出来的头像。图片放在 public/ 下，名字填进 file 即可。
// 顺序是主人定的：Puffy 是元老，BoBo 最小，排最后。
// 照片统一压到 800×800 的 JPEG（原图是 1200 的 PNG，九张加起来 16MB，
// 压完 1.2MB）—— 格子最大也就 300px 左右，大图 520px，800 足够，
// **以后换图记得也过一遍这道压缩**。
// sex: 'female' | 'male'，名字后面跟一个小图标。全部经主人确认过：介绍里能读出
// 来的（教母/萌妹/公主是母，种公/少爷是公）之外，NoNo 和 ZheZhe 是公、
// Liz 和 CoCo 是母。
const CAT_AVATARS = [
  { id: 'puffy', name: 'Puffy', desc: '元老教母', sex: 'female', file: 'cats/puffy.jpg' },
  { id: 'nono', name: 'NoNo', desc: '不喜欢同性', sex: 'male', file: 'cats/nono.jpg' },
  { id: 'jiujiu', name: 'JiuJiu', desc: '大眼萌妹', sex: 'female', file: 'cats/jiujiu.jpg' },
  { id: 'liz', name: 'Liz', desc: '别名 Mini', sex: 'female', file: 'cats/liz.jpg' },
  { id: 'pudding', name: 'Pudding', desc: '娘娘腔，种公', sex: 'male', file: 'cats/pudding.jpg' },
  { id: 'zhezhe', name: 'ZheZhe', desc: '疯P', sex: 'male', file: 'cats/zhezhe.jpg' },
  { id: 'coco', name: 'CoCo', desc: '脾气暴躁', sex: 'female', file: 'cats/coco.jpg' },
  { id: 'momo', name: 'MoMo', desc: '小公主', sex: 'female', file: 'cats/momo.jpg' },
  { id: 'bobo', name: 'BoBo', desc: '小少爷', sex: 'male', file: 'cats/bobo.jpg' }
];
const CAT_SEX = {
  female: { icon: 'ri-women-line', label: '母猫' },
  male: { icon: 'ri-men-line', label: '公猫' }
};
const CAT_AVATAR_PREFIX = 'cat:';
const CATS_BY_ID = new Map(CAT_AVATARS.map(cat => [cat.id, cat]));

// 只认「照片已经就位」的猫：值是从云端读回来的，不能拿它去拼一个不存在的图片。
function catAvatar(value) {
  if (typeof value !== 'string' || !value.startsWith(CAT_AVATAR_PREFIX)) return null;
  const cat = CATS_BY_ID.get(value.slice(CAT_AVATAR_PREFIX.length));
  return cat?.file ? cat : null;
}
const PROFILE_AVATAR_ICONS = new Set(PROFILE_AVATARS.map(item => item.icon));
const PROFILE_AVATAR_COLORS = new Map(PROFILE_AVATARS.map(item => [item.icon, item.color]));

// 头像有两种：图标（纯色圆底 + 白色图标）和猫（照片铺满 + 那只猫的颜色描边）。
// 顶栏、资料弹层的选项、猫弹层都走这一个函数，两种形态不会各写各的。
function applyProfileAvatar(element, avatar, color) {
  const cat = catAvatar(avatar);
  element.classList.toggle('is-photo', !!cat);
  const glyph = element.querySelector('i');
  if (cat) {
    element.style.backgroundColor = 'transparent';
    element.style.backgroundImage = `url("${cat.file}")`;
    element.style.borderColor = '';   // 白边交给 .is-photo
    if (glyph) glyph.className = '';
    return;
  }
  element.style.backgroundImage = '';
  element.style.borderColor = 'transparent';
  element.style.backgroundColor = color || PROFILE_AVATAR_COLORS.get(avatar) || GUEST_AVATAR_COLOR;
  if (glyph) glyph.className = avatar;
}
const PROFILE_NAME_MAX = 20;

function normalizeProfile(raw) {
  const avatar = raw?.avatar;
  return {
    name: typeof raw?.name === 'string' ? raw.name.trim().slice(0, PROFILE_NAME_MAX) : '',
    avatar: PROFILE_AVATAR_ICONS.has(avatar) || catAvatar(avatar) ? avatar : DEFAULT_AVATAR,
    updatedAt: Number(raw?.updatedAt) || 0
  };
}

function loadProfile() {
  try {
    return normalizeProfile(JSON.parse(localStorage.getItem(PROFILE_KEY) || '{}'));
  } catch {
    return normalizeProfile(null);
  }
}

let profile = loadProfile();
let profileDraftAvatar = profile.avatar;
let profileSheetTrigger = null;
let profileSheetCloseTimer = null;

// 顶栏的身份区：登录后是「头像 + 名字」，没登录只留一个灰色占位头像。
// 名字优先用自定义用户名，没设就退回脱敏邮箱。
function renderAccountBar() {
  const signedIn = !!currentUser;
  const masked = currentUser?.email ? maskEmail(currentUser.email) : '已登录';
  const name = signedIn ? (profile.name || masked) : '';
  const avatar = document.querySelector('#header-avatar');
  const nameEl = document.querySelector('#header-name');

  applyProfileAvatar(avatar, signedIn ? profile.avatar : DEFAULT_AVATAR,
    signedIn ? undefined : GUEST_AVATAR_COLOR);
  nameEl.textContent = name;
  nameEl.hidden = !signedIn;
  document.querySelector('#header-account-btn')
    .setAttribute('aria-label', signedIn ? `个人资料：${name}` : '未登录，点按登录');

  document.querySelector('#profile-email').textContent = signedIn ? masked : '—';
}

async function pullCloudProfile() {
  const { data, error } = await cloud
    .from('profiles')
    .select('display_name, avatar, updated_at')
    .eq('user_id', currentUser.id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return normalizeProfile({
    name: data.display_name,
    avatar: data.avatar,
    updatedAt: Date.parse(data.updated_at)
  });
}

async function pushCloudProfile() {
  const { error } = await cloud.from('profiles').upsert({
    user_id: currentUser.id,
    display_name: profile.name || null,
    avatar: profile.avatar,
    updated_at: new Date(profile.updatedAt || Date.now()).toISOString()
  });
  if (error) throw error;
}

// 独立于持仓同步，且自己吞掉错误：profiles 表要在 Supabase 控制台手动建，没建
// 之前这里必然报错 —— 不能让它把持仓的「已同步」状态也一起拖成失败，那是两件事。
async function syncProfile() {
  if (!cloud || !currentUser) return;
  try {
    const remote = await pullCloudProfile();
    // 退出会清掉本机资料，所以登录后通常直接收下云端那份；只有「本机改过、且比
    // 云端新」时才反过来推上去（例如在另一台设备改完这台还没拉过）。
    if (remote && remote.updatedAt >= profile.updatedAt) {
      profile = remote;
      profileDraftAvatar = profile.avatar;
      localStorage.setItem(PROFILE_KEY, JSON.stringify(profile));
      renderAccountBar();
    } else if (profile.updatedAt) {
      await pushCloudProfile();
    }
  } catch {
    // 资料同步不上只影响显示名，持仓不受影响，不值得打断用户。
  }
}

function setProfileDraftAvatar(icon) {
  // 当前头像是猫时，图标里没有一个该是选中的 —— 传进来的值原样保留判断，
  // 别硬拉回默认的小熊。
  profileDraftAvatar = PROFILE_AVATAR_ICONS.has(icon) || catAvatar(icon) ? icon : DEFAULT_AVATAR;
  document.querySelectorAll('.profile-avatar-option').forEach(option => {
    option.setAttribute('aria-pressed', String(option.dataset.avatar === profileDraftAvatar));
  });
}

const profileAvatarGrid = document.querySelector('#profile-avatar-grid');
PROFILE_AVATARS.forEach(({ icon, label }) => {
  const option = document.createElement('button');
  option.type = 'button';
  option.className = 'avatar-chip profile-avatar-option';
  option.dataset.avatar = icon;
  option.setAttribute('aria-pressed', 'false');
  option.setAttribute('aria-label', `头像 ${label}`);
  option.innerHTML = `<i class="${icon}" aria-hidden="true"></i>`;
  applyProfileAvatar(option, icon);
  option.addEventListener('click', () => setProfileDraftAvatar(icon));
  profileAvatarGrid.append(option);
});

function openProfileSheet() {
  clearTimeout(profileSheetCloseTimer);
  profileSheetTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  // 未登录时资料无处可存，弹层只留一句说明和登录按钮 —— 改了名字和头像却
  // 存不下来，比不给改更糟。
  const signedIn = !!currentUser;
  document.querySelector('#profile-sheet-title').textContent = signedIn ? '个人资料' : '登录';
  document.querySelector('.profile-signed-in').hidden = !signedIn;
  document.querySelector('.profile-guest-note').hidden = signedIn;
  document.querySelector('#profile-submit-btn').hidden = !signedIn;
  document.querySelector('#profile-login-btn').hidden = signedIn;
  document.querySelector('#profile-name').value = profile.name;
  setProfileDraftAvatar(profile.avatar);
  renderAccountBar();
  openOverlay(document.querySelector('#profile-sheet-overlay'));
}

function closeProfileSheet(restoreFocus = true) {
  const overlay = document.querySelector('#profile-sheet-overlay');
  overlay.classList.remove('is-open');
  const trigger = profileSheetTrigger;
  profileSheetCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    if (restoreFocus && trigger?.isConnected) trigger.focus();
    profileSheetTrigger = null;
  }, 220);
}

// 单击开个人资料，双击看猫。
//
// 自己数 click 次数，不用原生的 dblclick 事件：触屏上 dblclick 各家实现不一
// （iOS 上双击优先被当成缩放手势，很多时候根本不发这个事件），只靠它会出现
// 「怎么双击都出不来」。click 在触屏和鼠标上都稳定触发，数两次就行。
// 窗口给到 320ms —— 260ms 对不少人的双击来说偏紧，第一下的动作已经跑掉了。
// 配套还需要 CSS 的 touch-action: manipulation，否则移动端的双击缩放会把
// 第二下吞掉。
const HEADER_DOUBLE_CLICK_MS = 320;
let headerAccountClickTimer = null;
let headerAccountClicks = 0;
const headerAccountBtn = document.querySelector('#header-account-btn');
headerAccountBtn.addEventListener('click', () => {
  headerAccountClicks += 1;
  if (headerAccountClicks === 1) {
    headerAccountClickTimer = setTimeout(() => {
      headerAccountClicks = 0;
      openProfileSheet();
    }, HEADER_DOUBLE_CLICK_MS);
    return;
  }
  clearTimeout(headerAccountClickTimer);
  headerAccountClicks = 0;
  openCatSheet();
});
document.querySelector('#profile-close-btn').addEventListener('click', () => closeProfileSheet());
[...document.querySelectorAll('[data-close-profile]')]
  .forEach(el => el.addEventListener('click', () => closeProfileSheet()));

// ── 猫（双击顶栏头像）─────────────────────────────────────────────────
let catSheetTrigger = null;
let catSheetCloseTimer = null;

function renderCatGrid() {
  const grid = document.querySelector('#cat-grid');
  grid.replaceChildren(...CAT_AVATARS.map(cat => {
    const value = `${CAT_AVATAR_PREFIX}${cat.id}`;
    const cell = document.createElement('button');
    cell.type = 'button';
    cell.className = 'cat-cell';
    cell.dataset.cat = cat.id;
    cell.setAttribute('aria-pressed', String(profile.avatar === value));
    // 照片还没到的格子只是占位，不给点 —— 存进去会得到一个加载不出来的头像。
    cell.disabled = !cat.file;
    cell.setAttribute('aria-label', cat.file ? `把头像换成 ${cat.name}` : '这只猫的照片还没上传');

    const photo = document.createElement('span');
    photo.className = 'cat-photo';
    if (cat.file) photo.style.backgroundImage = `url("${cat.file}")`;

    const name = document.createElement('span');
    name.className = 'cat-name';
    const sex = CAT_SEX[cat.sex];
    name.append(cat.name);
    if (sex) {
      const mark = document.createElement('i');
      mark.className = `${sex.icon} cat-sex is-${cat.sex}`;
      // 图标本身不带语义，读屏要能读出「母猫/公猫」。
      mark.setAttribute('role', 'img');
      mark.setAttribute('aria-label', sex.label);
      name.append(mark);
    }

    // 一句话介绍，五六个字。还没写的显示成一条灰条占位，位置先留着。
    const desc = document.createElement('span');
    desc.className = 'cat-desc';
    desc.textContent = cat.desc || '';

    cell.append(photo, name, desc);
    if (cat.file) bindCatCellGestures(cell, cat);
    return cell;
  }));
}

// 短按设头像、长按看大图。两个手势挂在同一个元素上，长按触发后要把随之而来
// 的那次 click 吃掉，否则手一松就顺带把头像也换了。
const CAT_LONG_PRESS_MS = 500;

function bindCatCellGestures(cell, cat) {
  let pressTimer = null;
  let longPressed = false;
  const cancel = () => clearTimeout(pressTimer);

  cell.addEventListener('pointerdown', () => {
    longPressed = false;
    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      longPressed = true;
      openCatPhoto(cat);
    }, CAT_LONG_PRESS_MS);
  });
  ['pointerup', 'pointerleave', 'pointercancel'].forEach(type => cell.addEventListener(type, cancel));
  // 移动端长按图片会弹系统菜单（保存图片/拷贝），把它挡掉。
  cell.addEventListener('contextmenu', event => event.preventDefault());
  cell.addEventListener('click', event => {
    if (!longPressed) return chooseCatAvatar(cat);
    event.preventDefault();
    longPressed = false;
  });
}

let catPhotoTrigger = null;
let catPhotoCloseTimer = null;

function openCatPhoto(cat) {
  clearTimeout(catPhotoCloseTimer);
  catPhotoTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  const image = document.querySelector('#cat-photo-viewer-img');
  image.src = cat.file;
  image.alt = cat.name ? `${cat.name}的照片` : '猫的照片';
  const viewerName = document.querySelector('#cat-photo-viewer-name');
  const sex = CAT_SEX[cat.sex];
  viewerName.replaceChildren(cat.name);
  if (sex) {
    const mark = document.createElement('i');
    mark.className = `${sex.icon} cat-sex is-${cat.sex}`;
    mark.setAttribute('role', 'img');
    mark.setAttribute('aria-label', sex.label);
    viewerName.append(mark);
  }
  document.querySelector('#cat-photo-viewer-desc').textContent = cat.desc || '';
  openOverlay(document.querySelector('#cat-photo-viewer'));
  document.querySelector('.photo-viewer-scrim').focus();
}

function closeCatPhoto(restoreFocus = true) {
  const overlay = document.querySelector('#cat-photo-viewer');
  overlay.classList.remove('is-open');
  const trigger = catPhotoTrigger;
  catPhotoCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    if (restoreFocus && trigger?.isConnected) trigger.focus();
    catPhotoTrigger = null;
  }, 220);
}

[...document.querySelectorAll('[data-close-photo]')]
  .forEach(el => el.addEventListener('click', () => closeCatPhoto()));

async function chooseCatAvatar(cat) {
  // 头像属于账号资料，没登录就没地方存 —— 和资料弹层里那条规则保持一致。
  if (!currentUser) return showToast('登录后可以把猫设成头像');
  profile = normalizeProfile({
    name: profile.name,
    avatar: `${CAT_AVATAR_PREFIX}${cat.id}`,
    updatedAt: Date.now()
  });
  localStorage.setItem(PROFILE_KEY, JSON.stringify(profile));
  profileDraftAvatar = profile.avatar;
  renderAccountBar();
  renderCatGrid();
  showToast(`头像已换成 ${cat.name}`);
  try {
    await pushCloudProfile();
  } catch {
    showToast('头像已存在本机，云端同步失败');
  }
}

function openCatSheet() {
  clearTimeout(catSheetCloseTimer);
  catSheetTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  renderCatGrid();
  openOverlay(document.querySelector('#cat-sheet-overlay'));
  document.querySelector('#cat-close-btn').focus();
}

function closeCatSheet(restoreFocus = true) {
  const overlay = document.querySelector('#cat-sheet-overlay');
  overlay.classList.remove('is-open');
  const trigger = catSheetTrigger;
  catSheetCloseTimer = setTimeout(() => {
    overlay.hidden = true;
    if (restoreFocus && trigger?.isConnected) trigger.focus();
    catSheetTrigger = null;
  }, 220);
}

document.querySelector('#cat-close-btn').addEventListener('click', () => closeCatSheet());
[...document.querySelectorAll('[data-close-cat]')]
  .forEach(el => el.addEventListener('click', () => closeCatSheet()));

document.querySelector('#profile-form').addEventListener('submit', async event => {
  event.preventDefault();
  profile = normalizeProfile({
    name: document.querySelector('#profile-name').value,
    avatar: profileDraftAvatar,
    updatedAt: Date.now()
  });
  // 先落本地再推云端：本地是即时读取源，网络失败也不该让刚改的名字弹回去。
  localStorage.setItem(PROFILE_KEY, JSON.stringify(profile));
  renderAccountBar();
  closeProfileSheet();
  if (!cloud || !currentUser) return;
  try {
    await pushCloudProfile();
  } catch {
    showToast('资料已存在本机，云端同步失败');
  }
});

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
    try {
      await pushCloudHoldings();
    } catch {
      reportSyncFailure('云端同步失败，改动已存在本机');
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
  syncProfile();
  // 失败重试一次。刷新时如果 access token 刚好过期，第一次查表会吃一个 401，
  // supabase-js 随后自己刷新了 token，但 onAuthStateChange 只在「换了个人」时
  // 才重跑 handleSignedIn —— 同一个人的 TOKEN_REFRESHED 不会重来，状态就一直
  // 挂着「同步失败」。数据其实没丢（之后的改动照样推得上去），但这个状态现在
  // 显示在个人资料里，挂错了会让人以为云端坏了。
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      holdings = mergeHoldings(holdings, await pullCloudHoldings());
      // 合并结果直接落盘：走 saveHoldings 会把刚拉下来的远端行当成「刚改过」
      // 重新盖章，冲突裁判就失效了。
      resetHoldingFingerprints();
      localStorage.setItem(PORTFOLIO_KEY, JSON.stringify(holdings));
      renderHoldings();
      refreshHoldingPrices();
      await pushCloudHoldings();
      return;
    } catch {
      if (attempt === 0) {
        await new Promise(resolve => setTimeout(resolve, 3000));
        continue;
      }
      reportSyncFailure('云端同步失败，本地数据仍可用');
    }
  }
}

// 退出时清掉本地副本：这台设备换个 Google 账号登进来，不该继承上一个人的持仓。
// 数据在云端，登回来就有。
function handleSignedOut() {
  currentUser = null;
  holdings = [];
  resetHoldingFingerprints();
  localStorage.removeItem(PORTFOLIO_KEY);
  // 资料和持仓同理：这台设备换个 Google 账号登进来，不该继承上一个人的用户名和头像。
  localStorage.removeItem(PROFILE_KEY);
  profile = normalizeProfile(null);
  profileDraftAvatar = profile.avatar;
  renderAccountBar();
  renderHoldings();
  document.querySelector('#portfolio-gate').hidden = false;
  document.querySelector('#portfolio-app').hidden = true;
}

// 只由真实会话调用（handleSignedIn）。不再落任何「已解锁」标记 —— 刷新后
// 是否放行，一律重新问 Supabase 要会话。
function unlockPortfolio() {
  document.querySelector('#portfolio-gate').hidden = true;
  document.querySelector('#portfolio-app').hidden = false;
  renderHoldings();
  refreshHoldingPrices();
  refreshRecommendationPrices();
}

async function startGoogleLogin() {
  if (!cloud) {
    // 以前这里会直接放行本地版。但那条旁路同时也是「配置挂了就静默变成免登录」
    // 的后门，持仓页从此不再有这种降级。
    showToast('登录服务暂时不可用，请稍后重试');
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
}

document.querySelector('#portfolio-login-btn').addEventListener('click', startGoogleLogin);
document.querySelector('#profile-login-btn').addEventListener('click', () => {
  closeProfileSheet(false);
  startGoogleLogin();
});

document.querySelector('#profile-signout-btn').addEventListener('click', async () => {
  closeProfileSheet(false);
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

// 进来先一律显示登录页。真有会话时，onAuthStateChange 会补发 INITIAL_SESSION
// 再走 handleSignedIn 解锁 —— 已登录的人只会看到一瞬间的登录页，没登录的人
// 则不会再被历史标记放行。
renderAccountBar();
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
