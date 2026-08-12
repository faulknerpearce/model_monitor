# Architecture

## Overview

Model Monitor is a SwiftUI agent-style macOS app (`LSUIElement` + `MenuBarExtra`) with provider-specific services for Grok, OpenCode, and Cursor. The shared shell owns provider selection, menu-bar presentation, settings, and lifecycle; each provider owns its authentication and usage implementation.

```
┌─────────────────────────────────────────────────────────┐
│ MenuBarExtra label  →  MenuBarPanelView (window style)  │
│ Preferences Window  →  charts / export / settings       │
└───────────────┬─────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────┐
│ Provider selection → Grok / OpenCode / Cursor services  │
│      │              │                 │                 │
│      ▼              ▼                 ▼                 │
│ Grok UsagePoller  OpenCode Poller   Cursor Poller       │
│ Auth / history    Console / local   Dashboard cookies   │
│      │              │                 │                 │
│      └────────── shared MenuBar / Settings ─────────────┘
└─────────────────────────────────────────────────────────┘
```

## Modules

| Area | Responsibility |
|------|----------------|
| `App/` | `MenuBarExtra` scenes, `AppDelegate` activation policy |
| `Grok/` | Grok auth, usage client/parser/poller, history, and alerts |
| `OpenCode/` | OpenCode auth, console/local usage, models, and panel |
| `Cursor/` | Cursor auth, dashboard usage client/poller, and panel |
| `Overview/` | Concentric usage rings and hourly multi-provider chart |
| `Provider/` | Provider identity, switching, and logos |
| `Shared/` | Provider-neutral infrastructure: WebKit cookie bridge/capture, sign-in sheet shell, poll interval, formatters |
| `MenuBar/` | Label, panel, segmented bar, category rows |
| `Settings/` | UserDefaults-backed preferences, launch-at-login |

## Data flow

1. On launch, `AppModel` constructs one instance of each provider service and injects its dependencies.
2. Each provider poller starts a loop: active interval while the menu is open, idle interval otherwise; Grok also pauses across sleep/wake.
3. Grok usage tries REST JSON candidates, then grok.com gRPC-web billing, then CLI billing JSON. OpenCode prefers official console usage and falls back to local database estimates. Cursor uses cookie-authenticated dashboard endpoints (`/api/usage-summary` and filtered usage events).
4. Grok snapshots update the UI and append to SwiftData (deduped).
5. The dropdown **Daily use** chart is always **7 days** of the active billing period (e.g. Thu→Wed). Before `resetsAt`, the window ends the day before reset; once `now >= resetsAt` (or the API advances `resetsAt`), the whole window rolls to the new period starting that Thursday — never two Thursdays. Each day scales to `100/7` of the weekly pool. Prefer server `dailySeries` when present; otherwise derive **day-over-day deltas** in the same billing period. A caption shows when the pool resets.
6. `ThresholdNotifier` fires once per threshold crossing.

## Auth storage

Session cookies and optional bearer tokens are stored as mode `0600` files under:

`~/Library/Application Support/ModelMonitor/{auth_*,opencode_auth_*,cursor_auth_*}.dat`

Keychain is intentionally avoided: unsigned/debug builds repeatedly prompt “wants to access the keychain.”

## Percent semantics

- **Menu bar** shows **used** percent (e.g. 38%).
- **Dropdown** shows both used and remaining (e.g. `38% used · 62% remaining`) plus a billing-period daily use chart.

## Build source of truth

`project.yml` (XcodeGen) is the only project definition. Run `xcodegen generate` after adding or moving files. There is no Swift Package Manager app target — use `ModelMonitor.xcodeproj`.

## Shared provider patterns

- **Auth capture** — `WebKitCookieCapture` + per-provider domain/session policy (`AuthSessionService`, `OpenCodeAuthSession`, `CursorAuthSession`).
- **Sign-in UI** — `ProviderSignInSheet` + `ProviderSignInWebView`; thin provider wrappers supply URLs and return-page rules.
- **Polling** — `PollingLoop` + `PollInterval.seconds(menuIsOpen:settings:)`. Grok alone adds sleep/wake and error backoff.

## Error handling

- `401/403` → provider `markSessionInvalid` + panel prompts re-auth (Grok REST probes must not swallow unauthorized)
- `429/5xx` / network → exponential backoff on Grok (30s → 10m cap)
- Decode failures are logged and recorded with empty products rather than crashing
