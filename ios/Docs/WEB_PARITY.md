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
- Principal changes take effect from the next settlement after their effective date.
- Editing current principal must not rewrite already settled interest.
- A manually skipped settlement date contributes no interest.

## Dividends

- A dividend becomes confirmed on its ex-dividend date.
- Pay date records cash timing but does not decide confirmation.
- Record amount is quantity at record creation multiplied by per-share dividend.
- Future dividend records update their quantity after position changes; confirmed records do not.

## Position changes

- Adding a market position recalculates weighted average cost.
- Reducing a market position does not change cost per share.
- Sale proceeds create or increase a zero-APR USDT stable holding.
- A full sale marks the source holding closed instead of immediately deleting it, preserving chart history.
- Closed holdings are retained for 400 days.

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
