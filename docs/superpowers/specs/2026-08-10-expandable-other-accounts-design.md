# Expandable full-detail "other accounts" cards

## Problem

The popover shows full live detail (progress bars, reset times, Opus/Sonnet
breakdown) for the currently logged-in account, but the "其他账号" section
(accounts previously seen on this machine, cached because `claude auth
login` overwrites the single Keychain credential on switch) only shows a
compact one-line summary: account label, plan, session %, weekly %, and a
relative "last recorded" timestamp. There's no way to see reset times or
Opus/Sonnet numbers for a non-active account, even though that data was
available at the time it was recorded.

## Goal

Let each cached "other account" show the same full detail as the live
account card, without permanently expanding the popover — collapsed by
default, expandable per-account on tap.

## Data model changes

`AccountUsageSnapshot` (Services/AccountUsageHistoryStore.swift) gains four
optional fields, mirroring `UsageSnapshot`:

```swift
struct AccountUsageSnapshot: Codable, Equatable {
    let accountLabel: String
    let planLabel: String
    let sessionPercent: Int
    let sessionResetsAt: Date?      // new
    let weeklyPercent: Int
    let weeklyResetsAt: Date?       // new
    let opusPercent: Int?           // new
    let sonnetPercent: Int?         // new
    let recordedAt: Date
}
```

Fields are optional so existing `account-history.json` entries (written
before this change) continue to decode successfully — they'll just render
without reset times/Opus/Sonnet until that account is active again and the
snapshot is refreshed and overwritten. No migration step, no cache wipe.

`UsageViewModel.refreshUsageAndAccount()` already computes a full
`UsageSnapshot` for the live account each refresh; the `historyStore.upsert`
call there is extended to pass through `sessionResetsAt`, `weeklyResetsAt`,
`opusPercent`, `sonnetPercent` instead of dropping them.

## UI changes

`UsagePopoverView` (Views/UsagePopoverView.swift):

- Add `@State private var expandedAccounts: Set<String> = []`, keyed by
  masked `accountLabel`. Per-account, independent toggles — multiple cards
  can be expanded at once. Not persisted; resets whenever the view is
  recreated (consistent with this being non-realtime cached data, not
  something worth remembering across popover opens).
- Each row in `otherAccountsSection` gets a chevron affordance and becomes
  tappable, toggling membership in `expandedAccounts`.
- **Collapsed row** (default): account label + plan label (unchanged),
  then session % and weekly % each shown with their reset time inline
  (e.g. "会话 42% · 重置于 14:30"), replacing the current relative
  "3天前"-style last-recorded timestamp — that timestamp moves to the
  expanded view only.
- **Expanded row**: reuses the existing `usageRow` treatment (title +
  percent + progress bar + reset time) for session and weekly, plus
  conditional Opus/Sonnet rows exactly like the live card — same visual
  language as `content(for:footer:)`. Footer line: "上次记录于
  \(relativeTime(recordedAt))".
- If a cached snapshot predates this change and lacks reset
  times/Opus/Sonnet, those sub-rows are simply omitted, same conditional
  pattern the live card already uses today for `opusPercent`/`sonnetPercent`.

## Out of scope

- No change to how/when snapshots are recorded (still only on live refresh
  of the active account).
- No persistence of expand/collapse state across popover opens.
- No migration or backfill of pre-existing cache entries — they degrade
  gracefully and self-heal next time that account is active.

## Testing

- `AccountUsageHistoryStoreTests` (or equivalent): round-trip encode/decode
  of the extended `AccountUsageSnapshot`, and decode of an old-format JSON
  fixture (missing the four new keys) to confirm it still loads with `nil`
  for the new fields.
- `UsageViewModel` test: refreshing the live account persists the full
  snapshot (all four new fields) into the history store.
- View-level: manual check in the running app (or a snapshot test if the
  project has one) that collapsed shows reset times, not last-recorded
  time; expanded shows the full card; toggling one account doesn't affect
  others.
