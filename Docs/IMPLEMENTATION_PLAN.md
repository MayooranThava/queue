# Queue Implementation Plan

## Dependency decisions

| Dependency | Decision | Rationale |
| --- | --- | --- |
| Swift / SwiftUI / SwiftData | **Adopt** (iOS 17+) | Native, local-first, low ops cost |
| EventKit | **Adopt** Phase 4 | Apple Calendar without backend |
| UserNotifications | **Adopt** Phase 2 | Timer completion without background execution |
| MSAL + Microsoft Graph | **Adopt** Phase 5 (optional) | Direct Outlook; no client secret; PKCE |
| RiveRuntime | **Optional later** | Companion works with SwiftUI fallback first |
| StoreKit 2 | **After core loop** | EntitlementService stub first |
| Paid analytics | **Not in MVP** | Local analytics protocol only |
| Custom backend | **Avoid** | No demonstrated sync/auth need yet |
| XcodeGen | **Adopt** | Reproducible `.xcodeproj` from `project.yml` |
| SPM QueueCore | **Adopt** | Domain tests on Linux + macOS |

### Material decisions flagged

1. **No backend for v1** — lowest cost and privacy-friendly; sync later if retention demands it.
2. **Outlook via MSAL public client** — requires Azure app registration by the product owner; cannot fabricate credentials.
3. **Rive deferred** — avoid blocking builds on missing assets.
4. **Pro as one-time purchase hypothesis** — validate before locking pricing.
5. **Figma not machine-readable here** — implement from written visual language + product screens; import screenshots into `DesignReferences/` when available.

## Milestones

### Phase 0 — Assessment ✅

- Inspect repo, tooling, design access
- Architecture, PRD, plan, testing, animation, Microsoft setup docs

### Phase 1 — App foundation ✅

**Build:** App entry, tab navigation, design system, SwiftData, task model, Queue screen, add/edit, FIFO service, onboarding shell.

**Acceptance:** Create, edit, reorder, persist tasks.

### Phase 2–3 — Focus + rewards (current)

**Build:** Instant focus countdown (timestamp-backed), working companion, pause/extend/expiry, completion celebration, fair Effort XP (difficulty × duration × budget), optional Up-next start-time toggle, Progress XP/level surface, XP ledger persistence.

**Acceptance:**
- Start focus begins countdown immediately with working animation
- Complete awards idempotent XP (never negative for overtime)
- Up next can toggle durations ↔ projected/planned start times
- Domain tests cover timer, XP, and schedule projection

**Done in this milestone:**
- `FocusSessionView` + `CompletionCelebrationView` (skippable)
- `XPCalculator` fair formula + `RewardEngine` ledger restore
- `TaskDifficulty`, optional `plannedStartAt`, `QueueSchedule` projections
- SwiftData `XPTransactionEntity`; Progress tab shows level/XP
- 20 Swift Testing domain tests via `swift test` (Linux)

**Hardening follow-up (same PR track):**
- Continue focus resumes an in-progress session (no invalid `.start` from `.active`)
- `FocusSessionEntity` persists timestamps; bootstrap restores after kill/relaunch
- Completion undo banner + `RewardEngine.revoke` so XP cannot be double-farmed

**Timer surfaces + companion polish:**
- Live countdown on Queue “Now” card (not Focus-only)
- Home Screen / Lock Screen WidgetKit extension + optional Live Activity via App Group snapshot
- Companion redraw: desk/laptop/lamp/typing aligned to storyboard states

**Not verified here:** Full iOS app compile/simulator (no Xcode on this Linux environment). Local notifications remain a Phase 2 follow-up. Enable App Group `group.com.queueapp.Queueup` for the app + widget targets in the Apple Developer portal before device widget testing.

### Phase 4 — Calendar + Smart Gaps

EventKit provider, permission flows, agenda, Smart Gaps pure engine.

**Acceptance:** Meetings visible; suggestions never silently reorder.

### Phase 5 — Outlook

MSAL, Graph calendarView, tokens, disconnect, dedup, graceful admin-consent failure.

### Phase 6 — Polish

Haptics, a11y pass, empty/error states, UI tests, App Store checklist, optional Rive/StoreKit.

## Phase 1 file plan

```
Package.swift
Sources/QueueCore/...
Tests/QueueCoreTests/...
Queue/App/QueueApp.swift
Queue/App/AppModelContainer.swift
Queue/App/RootView.swift
Queue/Core/DesignSystem/...
Queue/Core/Persistence/...
Queue/Features/Queue/...
Queue/Features/Onboarding/...
Queue/Features/Calendar|Progress|Settings (placeholders)
project.yml
README.md
Docs/*
```

## Risks and open questions

| Risk | Impact | Mitigation |
| --- | --- | --- |
| No macOS/Xcode in this environment | Cannot run simulator or ship IPA from CI here | Domain tests on Linux; document Mac build steps |
| Missing Figma screenshots | Visual drift from design file | Encode tokens from written spec; add DesignReferences later |
| SwiftData schema evolution | Data loss | Versioned models + migration plan from Phase 1 |
| Timer + XP race | Duplicate rewards | Actor services + ledger uniqueness |
| Corporate Outlook consent | Feature unavailable for some users | Graceful failure; EventKit still works |
| Scope creep (AI, sync, dashboards) | Dilutes daily loop | CTO veto; calendar/analytics stay secondary |

### Open questions for product owner

1. Apple Developer Team ID? (Bundle ID confirmed: `com.queueapp.Queueup`)
2. Azure AD app registration for Outlook (when Phase 5 starts)?
3. Confirm Pro as non-consumable vs subscription before StoreKit work?
4. Can design export PNGs into `DesignReferences/` for parity checks?

## Workflow per phase

1. Explain scope → 2. List files/tests → 3. Small coherent change → 4. Build/test when tooling allows → 5. Fix → 6. Summarize risks
