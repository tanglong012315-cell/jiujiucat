# Smart Money version design intake ledger

- Date: 2026-09-02 (Asia/Singapore)
- Scope source: user explicitly supplied two PRD URLs; no full-version scan was performed.
- Destination: `https://www.figma.com/design/f4uhzBZRtYQko9Mj4A9O60/Bun-File-Transfer?node-id=0-1&p=f&t=XkJjG2ST9KBsvo5R-11`
- Current status: replacement Figma preflight and Section skeleton creation passed. PRD links remain unchanged.
- User granularity decision: PRD `616782650` scopes A-D must be combined into one Section and one consolidated Design Checklist.

## Figma access evidence

- Parsed file key: `f4uhzBZRtYQko9Mj4A9O60`
- Parsed target node: `0:1`
- Figma MCP identity: `TangLong` / `935545516@qq.com`
- `get_metadata`: target is the empty canvas `Page 1` with no children.
- Read-only `use_figma` preflight: editor type `figma`, one page, zero top-level nodes, no duplicate target names.
- Font preflight: `Noto Sans SC` and `Inter` are available; `Binance Nova` is unavailable, so the checklist's documented Noto Sans SC fallback will be used.
- Library preflight: `Nvwa` is subscribed. A Checkbox component exists, but the Design Checklist skill explicitly requires its own `Checklist Checkbox` two-variant ComponentSet; the prescribed checklist component remains authoritative.
- Edit capability: proven by successful Section creation.

## Intake items

### 1. FUT-83213 — Secondary confirmation when users unsubscribe

- Stable identity: Confluence pageId `616777362`; Jira `FUT-83213`
- Source: `https://confluence.toolsfdg.net/display/FUT/Add+a+secondary+confirmation+modal+when+users+unsubscribe`
- Jira: `https://jira.toolsfdg.net/browse/FUT-83213`
- PM/source author: `eve.z@binance.com`
- Designer/owner evidence: no dedicated Designer field was visible in the PRD or Jira. Included because the user explicitly supplied this PRD as authoritative intake scope.
- Platform: PRD `web&mp`; Jira `Web`
- Dev confirmation: no `not take` evidence found
- Existing Figma/design link: none found in the PRD or Jira
- Product intent: prevent accidental unsubscription by inserting a confirmation modal before cancellation.
- Affected surfaces: trader profile, Top Traders list, My Subscriptions
- Exact UI copy:
  - `Confirm Unsubscribe?`
  - `After unsubscribing, you will no longer receive this trader's futures live trading updates.`
  - `If this trader has enabled Code Subscription or Approval Subscription, you will need the correct code or the trader's approval to subscribe again.`
  - `Confirm`, `Cancel`, `Subscribed`
- Behavior:
  - Confirm cancels the subscription, closes the modal, and shows the existing unsubscribe toast.
  - Cancel closes the modal without cancelling.
- Screenshot evidence: 3 PRD screenshots; all show a narrow/mobile-style Smart Money surface. This is treated as MP visual evidence only and does not override the PRD's Web & MP target.
- Ownership result: included by explicit item scope; owner marker otherwise unknown
- Design triage: needs design (user-confirmed exact item; user-visible modal and flow change)
- Existing-design result: no exact duplicate in the empty destination page
- Proposed section: `FUT-83213 · Secondary confirmation when users unsubscribe · Web & MP (#PRD-616777362)`
- Planned baseline queries: `Confirm Unsubscribe?`, `Subscribed`, `My Subscriptions`, `Top Traders`, `Futures Live Trading`, `Code Subscription`, `Approval Subscription`
- Action status: Section created as node `3:2`; checklist pending
- Created Section URL: `https://www.figma.com/design/f4uhzBZRtYQko9Mj4A9O60/Bun-File-Transfer?node-id=3-2`
- Retrieval terminal status: not started; runs after checklist verification

### 2A. Cancel a pending subscription request

- Stable identity: Confluence pageId `616782650`, scope A
- Source: `https://confluence.toolsfdg.net/pages/viewpage.action?pageId=616782650`
- Requirement title: `Manage subscriptions page support search applicants & Support applicants cancel the application`
- PM/source author: `eve.z@binance.com`
- Designer/owner: `Bun` (explicit PRD field)
- Platform: Web & MP; PRD has one inconsistent `Web&App` heading, while the explicit Scope states `Web&MP&Admin`. Use Web & MP for this user-facing flow unless PM clarifies otherwise.
- Dev confirmation: no `not take` evidence found
- Existing Figma/design link: none found in the PRD
- Product intent: let applicants cancel their own pending approval request and restore the trader entry to a state where a new request can be submitted.
- Affected surfaces: trader profile, My Subscriptions, Top Traders, My Subscription Requests
- Exact UI copy:
  - `Cancel Subscription Request?`
  - `Your request is still pending. If you cancel it, the trader will no longer review this request. You can submit a new request from the trader's profile anytime.`
  - `Cancel Request`, `Pending Approval`
- Screenshot evidence: one mobile-style confirmation modal.
- Ownership result: mine (`Designer: Bun`)
- Design triage: needs design
- Existing-design result: no exact duplicate in the empty destination page
- Consolidated section: `Manage subscription applications · Web, MP & Admin (#PRD-616782650)`
- Planned baseline queries: `Cancel Subscription Request?`, `Cancel Request`, `Pending Approval`, `My Subscription Requests`
- Action status: consolidated Section created as node `3:3`; checklist pending
- Created Section URL: `https://www.figma.com/design/f4uhzBZRtYQko9Mj4A9O60/Bun-File-Transfer?node-id=3-3`
- Retrieval terminal status: not started; runs once for the consolidated Section after checklist verification

### 2B. Search applicants on Manage Subscriptions

- Stable identity: Confluence pageId `616782650`, scope B
- Source: `https://confluence.toolsfdg.net/pages/viewpage.action?pageId=616782650`
- PM/source author: `eve.z@binance.com`
- Designer/owner: `Bun`
- Platform: Web & MP
- Dev confirmation: no `not take` evidence found
- Existing Figma/design link: none found in the PRD
- Product intent: let traders find applicants by nickname, with live fuzzy/case-insensitive multilingual matching, highlighted hits, ranking, clear, empty, and network-error states.
- Affected surfaces: Manage Subscriptions > Pending Approval
- Exact UI copy:
  - `Manage Subscriptions`, `Pending Approval`, `History`
  - `Search UID or nickname`, `Search`, `No records`
  - `Network error, please try again`
- MP-specific behavior: search results open as a separate list and return into the filtered Manage Subscriptions list.
- Screenshot evidence: one four-state mobile search flow.
- Ownership result: mine (`Designer: Bun`)
- Design triage: needs design
- Existing-design result: no exact duplicate in the empty destination page
- Consolidated section: `Manage subscription applications · Web, MP & Admin (#PRD-616782650)`
- Planned baseline queries: `Manage Subscriptions`, `Pending Approval`, `Search UID or nickname`, `No records`, `Network error, please try again`
- Action status: merged into consolidated Section node `3:3`; checklist pending
- Retrieval terminal status: not started; runs once for the consolidated Section after checklist verification

### 2C. Batch reject pending applications

- Stable identity: Confluence pageId `616782650`, scope C
- Source: `https://confluence.toolsfdg.net/pages/viewpage.action?pageId=616782650`
- PM/source author: `eve.z@binance.com`
- Designer/owner: `Bun`
- Platform: Web & MP
- Dev confirmation: no `not take` evidence found
- Existing Figma/design link: none found in the PRD
- Product intent: let traders select up to 100 pending applications and reject the selected set after confirmation.
- Affected surfaces: Manage Subscriptions > Pending Approval, selection mode, confirmation modal, loading/success/failure states
- Exact UI copy:
  - `Selected {nums}`, `Reject`
  - `Clear selection to review individually`
  - `You can select up to 100 requests at a time.`
  - `Reject Applications?`
  - `This will reject {nums} selected pending applications. It only applies to selected rows in the current result.`
  - `Rejected successful.`
  - `No requests were rejected. Please refresh and try again.`
- Open product question from PRD: whether the page is paginated and whether cross-page selection is unsupported.
- Screenshot evidence: selection-off, multi-selected, and confirmation-modal mobile states.
- Ownership result: mine (`Designer: Bun`)
- Design triage: needs design
- Existing-design result: no exact duplicate in the empty destination page
- Consolidated section: `Manage subscription applications · Web, MP & Admin (#PRD-616782650)`
- Planned baseline queries: `Selected`, `Reject Applications?`, `Clear selection to review individually`, `You can select up to 100 requests at a time`, `Rejected successful`
- Action status: merged into consolidated Section node `3:3`; checklist pending
- Retrieval terminal status: not started; runs once for the consolidated Section after checklist verification

### 2D. Admin application cancellation and change log

- Stable identity: Confluence pageId `616782650`, scope D
- Source: `https://confluence.toolsfdg.net/pages/viewpage.action?pageId=616782650`
- PM/source author: `eve.z@binance.com`
- Designer/owner: `Bun`
- Platform: Admin Web
- Dev confirmation: no `not take` evidence found
- Existing Figma/design link: none found in the PRD
- Product intent: let authorized operators query applications, cancel pending requests with a required reason, and audit every operation through Change Log.
- Affected surfaces: Application Subscription admin list, status/source filters, Action column, cancellation modal, Change Log
- Exact UI copy:
  - `Application Subscription`, `Change Log`, `Action`, `Cancel`
  - `Cancel Subscription Request`
  - `Back`, `Confirm`
  - `操作失败，请重试`
- Validation/state requirements: reason required, max 400 characters, only Pending can be cancelled, audit failure blocks the cancellation, source enum includes User/Trader/Trader Batch/Admin/System.
- Screenshot evidence: Admin query/list with status menu and Change Log; cancellation modal with reason input.
- Ownership result: mine (`Designer: Bun`)
- Design triage: needs design
- Existing-design result: no exact duplicate in the empty destination page
- Consolidated section: `Manage subscription applications · Web, MP & Admin (#PRD-616782650)`
- Planned baseline queries: `Application Subscription`, `Change Log`, `Applicant UID`, `Trader UID`, `Cancel Subscription Request`
- Action status: merged into consolidated Section node `3:3`; checklist pending
- Retrieval terminal status: not started; runs once for the consolidated Section after checklist verification

## Planned creation batch

- 2 actual `SECTION` nodes, each `8000 × 4000`, fixed fill `#D5D5D5`, vertically stacked at the same x with a 600 px gap.
- Section 1: `FUT-83213 · Secondary confirmation when users unsubscribe · Web & MP (#PRD-616777362)`.
- Section 2: `Manage subscription applications · Web, MP & Admin (#PRD-616782650)`, combining scopes 2A-2D.
- One standards-compliant `Design Checklist` frame per section at `x=160, y=160`; no extra intake cards.
- Run duplicate checks before creation using exact Jira/title/page identity.
- PRD link backfill was not requested and must not be performed unless explicitly requested later.
- Run bounded baseline retrieval for both sections after checklist verification; provided file first, using exact UI copy before aliases.
