# ClaudeUsageBar — Design

## Purpose

A native macOS menu bar utility that shows the user's Claude Code subscription
usage (session and weekly quota) without opening a terminal. Click the menu
bar icon to see current utilization for the 5-hour session window and the
7-day weekly window, matching the data shown by the CLI's usage indicators.

## Non-goals (v1)

- Background polling / auto-refresh timers
- Launch-at-login
- Notifications / alerts when nearing a limit
- Historical usage charts or trend tracking
- Support for API-key-only auth (no claude.ai OAuth session)

## Data Source

Claude Code CLI, when logged in via `claude.ai` (not a raw API key), stores an
OAuth credential in the macOS Keychain under the generic-password service name
`Claude Code-credentials`. This entry is a JSON blob:

```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-...",
    "refreshToken": "sk-ant-...",
    "expiresAt": 1784069475705,
    "scopes": [...],
    "subscriptionType": "pro",
    "rateLimitTier": "default_claude_ai"
  }
}
```

Claude Code itself keeps this token refreshed whenever the CLI runs. This app
only reads it — it never writes to this Keychain item, to avoid any risk of
corrupting the credential Claude Code depends on.

Verified live on 2026-07-14: `GET https://api.anthropic.com/api/oauth/usage`
with header `Authorization: Bearer <accessToken>` returns:

```json
{
  "five_hour": { "utilization": 63.0, "resets_at": "2026-07-14T16:49:59Z", ... },
  "seven_day": { "utilization": 28.0, "resets_at": "2026-07-20T02:59:59Z", ... },
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  ...
  "limits": [ { "kind": "session", "percent": 63, ... }, ... ],
  "spend": { ... }
}
```

`five_hour` and `seven_day` are always present for a claude.ai-subscription
login. Opus/Sonnet-scoped weekly fields are non-null only for plans that have
those sub-limits (e.g. Max); the app shows those rows only when present.

## Architecture

- **Language/UI**: Swift + SwiftUI, using `MenuBarExtra` (macOS 13+).
- **Build**: Swift Package Manager executable target. No Xcode.app required
  (only Command Line Tools are installed on this machine); SPM builds an
  executable which a build script wraps into a `.app` bundle.
- **Distribution**: build script → `.app` → ad-hoc codesign
  (`codesign --sign -`) → `.dmg` via `hdiutil`. Not notarized (no paid Apple
  Developer ID) — user accepted the one-time Gatekeeper right-click-to-open
  step.

## Data Flow

1. User clicks the menu bar icon.
2. App reads `Claude Code-credentials` from Keychain (via Security framework,
   `kSecClassGenericPassword`, service = `Claude Code-credentials`).
3. Parse JSON, extract `accessToken`, `expiresAt`, `subscriptionType`.
4. If `expiresAt` is in the past: skip the network call, show the "needs
   refresh" message (see Error Handling).
5. Otherwise `GET https://api.anthropic.com/api/oauth/usage` with
   `Authorization: Bearer <accessToken>`.
6. Parse `five_hour.utilization`, `five_hour.resets_at`, `seven_day.utilization`,
   `seven_day.resets_at`, and any non-null `seven_day_opus`/`seven_day_sonnet`.
7. Update the menu bar label (see UI) and the popover contents. Cache the
   result in memory (not disk) as "last known" for the error-fallback case.

No timers, no background fetches. Between clicks, the icon shows whatever was
last fetched.

## UI

**Menu bar icon**: a small glyph + text label showing the `five_hour`
utilization percentage (e.g. `63%`). Session window was chosen as the headline
number because it resets most frequently and is the most actionable at a
glance; weekly is one click away.

**Popover (on click)**, Claude-brand-styled (warm orange/cream accents),
simple card layout:

- Plan badge: "Pro" / "Max" (from `subscriptionType`)
- Session usage: progress bar + `{utilization}%` + "resets at {local time}"
- Weekly usage: progress bar + `{utilization}%` + "resets at {local time}"
- Extra rows for `seven_day_opus` / `seven_day_sonnet` etc., only if non-null
- Small footer: "updated just now" / "updated 4m ago" (if serving cached data)

## Error Handling

| Condition | Behavior |
|---|---|
| Keychain item not found | "未检测到 Claude.ai 订阅登录 — 请先用 `claude auth login` 登录" |
| `expiresAt` in the past | "登录已过期，请在终端运行一次 `claude` 刷新后重试" |
| Network request fails | Show last cached values (if any) + "上次更新于 Xm 前"; if no cache yet, show a simple retry prompt |
| Non-200 response | Same as network failure path |

## Security Principles

- Keychain access is read-only; the app never modifies or deletes the
  `Claude Code-credentials` item.
- The access token is held in memory only for the duration of a single fetch;
  never logged, never written to disk, never included in crash reports.

## Testing

Manual verification (no automated UI test harness planned for v1):

1. Build and launch the app; confirm the menu bar icon appears.
2. Click the icon; confirm the displayed session/weekly percentages match
   what `claude`'s own usage indicators show for the same account.
3. Kill network access, click again; confirm graceful fallback to cached
   values with an "updated Xm ago" label (or the no-cache retry prompt on
   first-ever click).
4. Rename/remove the Keychain item temporarily (in a throwaway test, not on
   this machine's real entry); confirm the "not logged in" message appears.
5. Build the `.dmg`, open it fresh, drag to `/Applications`, right-click →
   Open; confirm Gatekeeper prompt appears once and the app launches after
   approval.
