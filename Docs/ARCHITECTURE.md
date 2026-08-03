# Architecture

## Overview

Grok Monitor is a SwiftUI agent-style macOS app (`LSUIElement` + `MenuBarExtra`) with provider-specific services for Grok and OpenCode. The shared shell owns provider selection, menu-bar presentation, settings, and lifecycle; each provider owns its authentication and usage implementation.

```
┌─────────────────────────────────────────────────────────┐
│ MenuBarExtra label  →  MenuBarPanelView (window style)  │
│ Preferences Window  →  charts / export / settings       │
└───────────────┬─────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────┐
│ Provider selection → Grok or OpenCode provider service  │
│      │                         │                        │
│      ▼                         ▼                        │
│ Grok UsagePoller          OpenCode UsagePoller           │
│ Auth / client / history   Auth / console / local stats  │
│      │                         │                        │
│      └────────── shared MenuBar / Settings ─────────────┘
└─────────────────────────────────────────────────────────┘
```

## Modules

| Area | Responsibility |
|------|----------------|
| `App/` | `MenuBarExtra` scenes, `AppDelegate` activation policy |
| `Grok/` | Grok auth, usage client/parser/poller, history, and alerts |
| `OpenCode/` | OpenCode auth, console/local usage, models, and panel |
| `Provider/` | Provider identity, switching, and logos |
| `Shared/` | Provider-neutral infrastructure such as the WebKit cookie bridge |
| `MenuBar/` | Label, panel, segmented bar, category rows |
| `Settings/` | UserDefaults-backed preferences, launch-at-login |

## Data flow

1. On launch, `AppModel` constructs one instance of each provider service and injects its dependencies.
2. Each provider poller starts a loop: active interval while the menu is open, idle interval otherwise; Grok also pauses across sleep/wake.
3. Grok usage tries REST JSON candidates, then grok.com gRPC-web billing, then CLI billing JSON. OpenCode prefers official console usage and falls back to local database estimates.
4. Grok snapshots update the UI and append to SwiftData (deduped).
5. The dropdown **Daily use** chart is always **7 days** of the active billing period (e.g. Thu→Wed). Before `resetsAt`, the window ends the day before reset; once `now >= resetsAt` (or the API advances `resetsAt`), the whole window rolls to the new period starting that Thursday — never two Thursdays. Each day scales to `100/7` of the weekly pool. Prefer server `dailySeries` when present; otherwise derive **day-over-day deltas** in the same billing period. A caption shows when the pool resets.
6. `ThresholdNotifier` fires once per threshold crossing.

## Auth storage

Session cookies and optional bearer tokens are stored as mode `0600` files under:

`~/Library/Application Support/GrokMonitor/{auth_*,opencode_auth_*}.dat`

Keychain is intentionally avoided: unsigned/debug builds repeatedly prompt “wants to access the keychain.” Legacy Keychain items from earlier builds are deleted on launch.

## Percent semantics

- **Menu bar** shows **used** percent (e.g. 38%).
- **Dropdown** shows both used and remaining (e.g. `38% used · 62% remaining`) plus a billing-period daily use chart.

## Build source of truth

`project.yml` is the only Xcode project definition. Run `xcodegen generate` after adding or moving files; do not maintain a second handwritten project generator.

## Error handling

- `401/403` → `AuthSessionService.markSessionInvalid` + panel prompts re-auth
- `429/5xx` / network → exponential backoff (30s → 10m cap)
- Decode failures are logged and recorded with empty products rather than crashing
