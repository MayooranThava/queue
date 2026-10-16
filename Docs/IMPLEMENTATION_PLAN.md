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

### Phase 1 — App foundation (current)

**Build:** App entry, tab navigation, design system, SwiftData, task model, Queue screen, add/edit, FIFO service, onboarding shell.

**Acceptance:** Create, edit, reorder, persist tasks.

**Tests:** FIFO ordering, single active invariant, reorder, invalid transitions.

**Done in this milestone:**
- `QueueCore` package with task state machine, FIFO service, timer engine, reward ledger, Smart Gaps algorithm
- 15 Swift Testing domain tests passing via `swift test` (Linux)
- iOS app scaffold: onboarding, Queue home, add/edit/reorder, SwiftData persistence, companion SwiftUI fallback, tab placeholders, Focus shell
- `Queue.xcodeproj` + `project.yml` (XcodeGen) + generator script
- Docs under `Docs/`

**Not verified here:** Full iOS app compile/simulator (no Xcode on this Linux environment).

### Phase 2 — Focus engine

Timer state machine, Focus screen, pause/resume/extend/expiry, notifications, session restore.

**Acceptance:** Correct timing across background, kill, lock, navigation.

### Phase 3 — Companion and rewards

Native companion, completion animation, XP ledger, levels, Progress, streaks, Reduce Motion.

**Acceptance:** Exactly one XP award per completion; skippable celebration.

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

1. Final bundle ID and Apple Developer Team ID?
2. Azure AD app registration for Outlook (when Phase 5 starts)?
3. Confirm Pro as non-consumable vs subscription before StoreKit work?
4. Can design export PNGs into `DesignReferences/` for parity checks?

## Workflow per phase

1. Explain scope → 2. List files/tests → 3. Small coherent change → 4. Build/test when tooling allows → 5. Fix → 6. Summarize risks
