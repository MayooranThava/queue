# Queue Architecture

## Status

Phase 0 assessment complete. Phase 1 implements app foundation (navigation, design system, SwiftData, FIFO queue).

## Repository assessment (Phase 0)

| Item | Finding |
| --- | --- |
| Existing code | Greenfield — only `README.md` and git history |
| Xcode project | None present; generated via XcodeGen (`project.yml`) |
| Design references | Figma MCP unavailable; Figma WebGL unavailable in this environment; no `DesignReferences/` screenshots in repo |
| Tooling | Linux CI/dev environment with Swift 6 toolchain for domain tests; full iOS build requires macOS + Xcode |
| Remote | `https://github.com/MayooranThava/queue` |

## Product architecture summary

Queue is a **local-first** iOS app. The daily loop is:

**Open → See one task → Focus → Finish → Celebrate → Advance**

Everything else (calendar, Smart Gaps, advanced analytics, Outlook) supports that loop and must degrade without breaking it.

```
┌─────────────────────────────────────────────────────────────┐
│ Presentation (SwiftUI)                                      │
│  Tabs: Queue · Calendar · Progress · Settings               │
│  Modal/fullscreen: Focus · Completion · Onboarding          │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│ Domain (QueueCore — pure Swift, Linux-testable)             │
│  TaskStateMachine · TimerEngine · RewardEngine              │
│  LevelProgression · SmartGaps · MotivationProfiles          │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│ Data (SwiftData adapters + repositories)                    │
│  TaskEntity · FocusSessionEntity · XPTransactionEntity      │
│  UserPreferencesEntity · migrations                         │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│ Integrations                                                │
│  EventKit · UserNotifications · MSAL/Graph (Phase 5)        │
│  StoreKit 2 (post-core) · LocalAnalytics                    │
└─────────────────────────────────────────────────────────────┘
```

## Module boundaries

### QueueCore (Swift Package)

Pure domain types and services with no UIKit/SwiftUI/SwiftData imports.

- Testable on Linux and macOS
- Clock abstraction (`Clock` / `ControllableClock`) for timer tests
- Actors for serialized mutation of queue and reward ledgers where races matter

### Queue (iOS app target)

- SwiftUI presentation
- SwiftData persistence adapters mapping to/from domain models
- Design system tokens
- Integration adapters

### Design principles for code

- Domain services own state transitions; views never mutate task status directly
- Prefer feature folders over premature SPM micro-modules
- Protocols only at meaningful external boundaries (calendar, notifications, analytics, entitlements)
- Avoid generic DI frameworks

## Data model (domain)

### Task

| Field | Type | Notes |
| --- | --- | --- |
| id | UUID | Stable |
| title | String | Required |
| notes | String? | Optional |
| estimatedDuration | Duration | Guidance, not punishment |
| difficulty | TaskDifficulty | trivial…hard — scales XP only |
| plannedStartAt | Date? | Optional preferred start; Up-next toggle |
| createdAt | Date | |
| scheduledDate | Date? | Calendar day association |
| queuePosition | Int | FIFO order among non-terminal tasks |
| status | TaskStatus | See state machine |
| startedAt | Date? | |
| completedAt | Date? | |
| actualFocusDuration | Duration | Active focus time |
| accumulatedPausedDuration | Duration | |
| extensions | [TimerExtension] | History |
| category | String? | |
| calendarEventID | String? | Optional association |
| xpAwardID | UUID? | Links to ledger when awarded |
| modifiedAt | Date | |

### TaskStatus

`queued → active → paused → active`  
`active|paused → completed | expired | review | skipped`  
`expired → completed | active (extend/continue) | review | skipped`  
`review → queued | skipped | archived`  
`completed|skipped → archived`  
`archived` is terminal for active queue membership.

Invalid transitions throw / return typed errors from `TaskQueueService`.

### Focus session (authoritative timer)

Persisted timestamps are the source of truth. UI countdown is derived.

- sessionStart
- segmentStart
- plannedDuration
- accumulatedActive
- accumulatedPaused
- state: `idle | running | paused | expired | completed`
- extensions[]
- completedAt?

### XP transaction ledger

- id, sourceEventID, taskID?, rewardType, amount, timestamp
- Unique constraint: `(sourceEventID, rewardType)`
- Total XP = sum(ledger) or verified projection

## Navigation map

```
Root
├── Onboarding (first launch, NavigationStack)
└── MainTabView
    ├── QueueTab
    │   ├── QueueHome
    │   ├── TaskDetail / Edit
    │   ├── ReviewUnfinished
    │   └── → Focus (fullScreenCover)
    │         └── → Completion (overlay / cover)
    ├── CalendarTab
    │   ├── DayAgenda
    │   └── SmartGapsSheet
    ├── ProgressTab
    └── SettingsTab
```

Focus is **not** a tab. Task creation uses a prominent toolbar / FAB-style add control.

## Timer policy

- No repeating `Timer` as source of truth
- Remaining = `planned + extensions − elapsedActive(derived from timestamps)`
- Local notification scheduled for expected fire date; cancelled/rescheduled on pause/extend
- System clock jumps: prefer monotonic elapsed where available; document wall-clock correction policy in timer engine (clamp negative remaining to 0; never auto-complete twice)
- Single active session invariant enforced in domain service

## Companion

`CompanionAnimationView` hosts a single SpriteKit scene (`CompanionSpriteView` / `CompanionSpriteScene`) that plays `SKTextureAtlas` sequences from `Queue/Resources/Atlases/` (`Working`, `DeepFocus`, `Completed`, `Expired`). Frames are ordered by filename, drawn at identical size/anchor/scale, and paused when `scenePhase != .active`. Reduce Motion shows a static atlas pose. Timer / XP domain logic does not depend on animation playback.

## Calendar

`CalendarProvider` protocol → EventKit (Phase 4) → MSAL/Graph (Phase 5).  
Dedup: prefer Graph `iCalUId` / EventKit `eventIdentifier` + start/end/title conservative match.

## Monetization isolation

`EntitlementService` protocol with free defaults. StoreKit 2 wired after core loop is stable. Accessibility and existing tasks never paywalled.

## Concurrency

- `TaskQueueService` / `RewardEngine` as actors (or serialized via dedicated executor) to prevent races among expiry, completion, persistence, and XP award
- SwiftUI observes projections; mutations go through services

## Testing layers

| Layer | Tool | Priority |
| --- | --- | --- |
| Domain (FIFO, timer, XP, Smart Gaps) | Swift Testing in QueueCore | Highest |
| Integration (SwiftData adapters) | XCTest on macOS | Medium |
| UI flows | XCUITest on macOS | After screens stabilize |

## Risks and open questions

See [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md#risks-and-open-questions).
