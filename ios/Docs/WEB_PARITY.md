# Web-to-iOS behavior parity

This document records behavior that must survive the native rewrite. The source implementation is `public/app.js`; do not copy its DOM architecture.

## Investment calculator

- Principal is at least USD 1.
- Annual rate is non-negative.
- Simple interest: `principal * (1 + annualRate * years)`.
- Compound interest: `principal * pow(1 + annualRate, years)`.
- Daily return uses `1 / 365` years.
- Monthly return uses `1 / 12` years.
- Annual return uses `1` year.
- **iOS diverges from the Web here (user's decision of 2026-09-06):** the native
  Results grid shows Daily, Weekly, Monthly, Yearly, 5 Year, and 10 Year. Weekly
  uses `7 / 365` years; the former 20 Year field is no longer shown or calculated.
- Forecast ranges:
  - Day: 366 samples from now through day 365.
  - Month: 37 samples from now through month 36.
  - Year: 13 samples from now through year 12.

## Holding kinds

Persisted values currently include:

- `market`: stock, ETF, or crypto valued by market price.
- `interest`: manually named stable principal with APR.
- `hybrid`: market holding that also accrues interest on cost basis.
- `dividend`: market holding with dividend records.

The iOS `Codable` representation must continue to decode all four values.

## Stable interest

- First settlement occurs at 16:00 Asia/Shanghai on the day after the start date.
- Simple interest is based on principal and settled day count.
- Compound mode compounds daily.
- **iOS diverges from the Web here (user's decision of 2026-09-02):** principal changes take effect at the settlement on their selected effective date, not the following one. The effective date may be historical or future; choosing a historical date explicitly recalculates settled interest from that date onward. The Web still uses the old next-settlement rule.
- APR edits create dated rate-history entries. Dates before the selected effective date retain the previous APR; a historical effective date recalculates interest from that date onward.
- A manually skipped settlement date contributes no interest.

## Earn payout totals (changed 2026-09-07)

- `Received (USD)` in the Earn Holding summary means interest that has actually
  been credited through an `interest` ledger entry, not live accrued interest.
- Interest accrued after the effective date remains visible on each holding row,
  but does not enter `Received (USD)` before the provider payout is recorded.
- Reversed and future-dated payouts are excluded. Paid quantities are converted
  to USD using the same current valuation path as the rest of the Earn summary.

## Market data source (changed 2026-09-07)

The whole stack moved off Yahoo Finance, TradingView and CoinGecko onto Binance
(user's decision of 2026-09-07). Yahoo was an unofficial endpoint that returned
403s and carried no SLA.

- Crypto prices come from Binance spot. The Web streams them over a public
  WebSocket; iOS polls the Worker. Both express change against the same
  Beijing-day basis, so the two clients never show different percentages.
- **US equities come from Binance Stocks (`bapi/equity`, asset code `EQ_VOO`) —
  real share prices, ~7,900 symbols.** They are NOT the spot "bStocks" tokenised
  equities (`AAPLB`, pair `AAPLBUSDT`): those are third-party tokens that track
  the underlying with a 0.2–0.7% basis, which would land straight in reported P&L.
  Do not switch to them.
- Symbol resolution and search both run off `/api/catalog`, cached for a day.
  Search is a pure in-memory filter over that catalog — there is no search
  endpoint any more.
- USDT-quoted pairs are multiplied by USDT/USD to get a dollar price. The
  **change percentage is computed in the native quote currency and never scaled**:
  numerator and denominator share the factor, so scaling would only fold the
  stablecoin's own drift into the instrument's move.
- Legacy `BTC-USD` style symbols still resolve; the `-USD` suffix is stripped.

## Stablecoin valuation (changed 2026-09-07)

Stablecoin units were previously valued at exactly USD 1 on both clients.
They are now valued at their **real spot price** (user's decision of 2026-09-07):
1 USDT measured 0.9998 USD at the time of the change, and on a five-figure
position that difference is real money.

- Web: `holdingMetrics` for `kind === 'interest'` uses
  `value = (principal + interest) * price`, and `profit = value - principal`.
  Because profit now carries de-peg P&L on top of interest, the row label
  switches from 「利息」 to 「盈亏」.
- iOS: `LedgerValuation.unitValueUSD` returns the quote price for
  `.stablecoin` assets, and `LedgerAsset.marketQuoteSymbol` now returns the
  asset code for stablecoins so a quote is actually fetched.
- **Both clients fall back to exactly 1 when no real price is available** —
  long-tail stablecoins with no exchange market, or an unreachable quote
  service. Never substitute a guessed rate.
- The identity `profit == value - cost` is preserved, matching market holdings.

## Dividends

- A dividend becomes confirmed on its ex-dividend date.
- Pay date records cash timing but does not decide confirmation.
- Record amount is quantity at record creation multiplied by per-share dividend.
- Future dividend records update their quantity after position changes; confirmed records do not.

## Position changes

- Adding a market position recalculates weighted average cost.
- Reducing a market position does not change cost per share.
- Sale proceeds create a zero-APR USDT stable holding. **iOS diverges (user's decision of 2026-09-02):** every sale creates its own new holding instead of increasing an existing USDT one; the Web still merges.
- A full sale marks the source holding closed instead of immediately deleting it, preserving chart history.
- Closed holdings are retained for 400 days.
- **iOS only (user's request of 2026-09-02):** adjustment records can be deleted, which undoes their effect on quantity, cost, principal and the USDT a sale created. The Web has no adjustment-history list at all.

## Portfolio chart

- Current total and chart endpoint must use the same valuation basis.
- Historical quantities/principal are reconstructed from adjustment records.
- Day/week use short intraday series; month/year prefer one-year daily series.
- Missing early price coverage may be forward-filled but must not be presented as genuine coverage.

## Storage and sync

- Web uses local-first persistence and mirrors to Supabase after login.
- Conflicts for existing records are resolved by the newest `updatedAt`.
- Native persistence must add `schemaVersion` before remote writes.
- Cross-platform deletion must use tombstones rather than absence from a full local list.
- A tombstone participates in conflict resolution using `deletedAt`; it wins an exact timestamp tie against an active record.
- Physical deletion of remote rows that are absent locally must be removed before native sync is enabled.
- The complete migration contract is `ios/Docs/SYNC_CONTRACT.md`.
