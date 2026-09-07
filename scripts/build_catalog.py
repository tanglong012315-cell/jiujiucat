#!/usr/bin/env python3
"""生成 public/catalog.json —— 搜索用的标的目录。

为什么是预生成的静态文件，而不是 Worker 端点：
Binance 对 Cloudflare Worker 的出口 IP 返回 403（2026-09-07 实测，api 和 bapi
两个域名都拦；同一时刻浏览器和本机直连都是 200）。所以 Worker 拉不到这些数据。
静态资源由 Cloudflare 直接分发、根本不经过 Worker，也就绕开了这个封锁。

代价是会过时：新上市的标的要重新跑一次这个脚本才会出现。目录只用于**搜索**，
取价是按代号直连交易所的，所以过时的影响仅限于「搜不到新标的」，不影响已有持仓。

用法：python3 scripts/build_catalog.py
"""

import json
import gzip
import pathlib
import urllib.request

UA = {"User-Agent": "Mozilla/5.0", "Accept": "application/json"}
OUT = pathlib.Path(__file__).resolve().parent.parent / "public" / "catalog.json"

# 这些基础资产要优先选**美元**盘，而不是默认的 USDT 盘。
# 稳定币是唯一的用户，也是必须有它的原因：USDC 同时有 USDCUSDT 和 USDCUSD，
# 默认规则会选中前者 —— 那给出的是「USDC 值多少 USDT」，不是「值多少美元」。
# 拿一个本身会脱锚的东西当尺子，脱锚幅度会被直接抹平成 0。
USD_PREFERRED = {"USDT", "USDC", "FDUSD", "TUSD", "DAI", "PYUSD", "USDG", "USD1"}

# 代币化股票的名字都带这个后缀，是它们和普通币种唯一可靠的区分标志 ——
# 光看代号结尾的 B 会把 SHIB、ARB、CKB 这些币误判成股票。
# 本站的美股走真实股价（bapi/equity），这一类整体排除。
BSTOCK_TAG = "(bStocks)"


def fetch(url):
    request = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read())


def build_crypto():
    """加密：Binance 为主，CMC 补它没有的。

    Binance 不上架任何竞争对手的平台币 —— OKB / BGB / KCS / GT / MX / CRO / LEO
    都没有，只有自家 BNB。单一交易所必然有这类洞。

    ⚠️ CMC 只给 24 小时涨跌，没有「北京时间今日」基准，也没有 K 线序列。
    走这条路的标的必须把 basis 标成「24 小时」。
    """
    info = fetch("https://api.binance.com/api/v3/exchangeInfo")
    assets = fetch("https://www.binance.com/bapi/asset/v2/public/asset/asset/get-all-asset")
    names = {row["assetCode"]: str(row.get("assetName") or "") for row in assets.get("data", [])}

    best = {}
    for item in info["symbols"]:
        if item.get("status") != "TRADING" or item.get("isSpotTradingAllowed") is not True:
            continue
        quote = item["quoteAsset"]
        if quote not in ("USDT", "USD"):
            continue
        base = item["baseAsset"]
        wanted = "USD" if base in USD_PREFERRED else "USDT"
        current = best.get(base)
        if current is None or (current[1] != wanted and quote == wanted):
            best[base] = (item["symbol"], quote)

    catalog = {}
    for base, (pair, quote) in best.items():
        name = names.get(base, "")
        if BSTOCK_TAG in name:
            continue
        catalog[base] = [pair, name or base, quote, "binance"]

    # Binance 没有的走 CMC（经 Worker）。
    #
    # 原本用 OKX 补，但 2026-09-07 在真机上实测 www.okx.com 在用户网络下
    # DNS 解析不出来（OKX 走 Cloudflare CDN 域名）。CMC 不拦 Worker，
    # 覆盖也比 OKX 全（BGB / KCS / GT / MX 这些 OKX 也没有）。
    cmc = fetch(
        "https://api.coinmarketcap.com/data-api/v3/cryptocurrency/listing"
        "?start=1&limit=1000&sortBy=market_cap&sortType=desc&cryptoType=all&tagType=all"
    )
    added = 0
    for coin in cmc.get("data", {}).get("cryptoCurrencyList", []):
        code = str(coin.get("symbol") or "").upper()
        if not code or code in catalog:
            continue
        # 交易对留空：CMC 是按代号查的，没有交易对的概念。
        catalog[code] = ["", coin.get("name") or code, "USD", "cmc"]
        added += 1

    print(f"  加密 {len(catalog)} 个（其中 CMC 补了 {added} 个）")
    return catalog


def build_equity():
    """美股：Binance Stocks 的真实股价，不是现货那套代币化股票。"""
    data = fetch("https://www.binance.com/bapi/equity/v1/public/equity/symbol/get-symbols-static")
    catalog = {}
    for row in data.get("data", []):
        code = str(row.get("s") or "").upper()
        name = row.get("n")
        if not code or not name:
            continue
        # 名字截到 48 字符：全量近 8000 条，不截目录会明显变大，列表里也放不下更长的。
        catalog[code] = [str(name)[:48], "ETF" if row.get("t") == "ETF" else "EQUITY"]
    print(f"  美股 {len(catalog)} 个")
    return catalog


def main():
    print("拉取目录…")
    payload = {"cx": build_crypto(), "eq": build_equity()}
    blob = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    OUT.write_text(blob, encoding="utf-8")
    print(f"写入 {OUT}")
    print(f"  {len(blob) // 1024} KB（gzip 后约 {len(gzip.compress(blob.encode())) // 1024} KB）")


if __name__ == "__main__":
    main()
