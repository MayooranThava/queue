# Queue Testing Strategy

## Philosophy

Prefer reliable domain tests over superficial snapshots. UI tests cover critical happy paths once screens stabilize.

## Critical journeys

These six are the canonical criteria. Animations, wording, and layout are left untested.

1. The queue and XP survive an app update (SwiftData migration).
2. Add, edit, skip, requeue, and delete never reorder the queue silently.
3. Start focus, pause, +5, and Done award XP exactly once, from the app, the widget, or the Lock Screen.
4. The focus-end alert fires once, and Start next hands off cleanly.
5. Every theme passes contrast in light and dark mode.
6. Settings stick after a relaunch.

## Where each journey is tested

| Journey | Tests |
| --- | --- |
| 1. Migration | `QueueTests/SchemaMigrationTests.swift` — `testVersionedStoreRoundTripsSampleData`, `testLegacyUnversionedStoreRoundTripsThroughMigrationPlan` |
| 2. Queue order | `QueueTests/QueueOrderTests.swift` |
| 3. XP once | `QueueTests/FocusAwardTests.swift`. Widget and Lock Screen commands: `Tests/QueueCoreTests/WidgetFocusIntentTests.swift` |
| 4. Alert and Start next | `QueueTests/FocusHandoffTests.swift`. Planner: `Tests/QueueCoreTests/FocusEndNotificationTests.swift` |
| 5. Contrast | `Tests/QueueCoreTests/QueueThemeTests.swift` — `textAndButtonContrast` |
| 6. Settings relaunch | `QueueTests/SettingsPreferencePersistenceTests.swift` — `testSettingsStickAfterRelaunch`. Theme id: `QueueThemeTests.storeRoundTrip` |
| Onboarding, add, focus, XP smoke | `QueueUITests/CriticalJourneyUITests.swift` (separate job, not required) |

Task values used by the migration sample and the functional tests are built in `QueueTests/Support/QueueTestFixture.swift`.

## When a feature changes

- New stored task field: add it to `QueueTestFixture.makeTask`. The migration sample uses that builder.
- New settings field: extend `testSettingsStickAfterRelaunch`.
- New theme: add it to `QueueTheme.all`. Contrast already loops every theme. Add the theme's hex values to `QueueThemeTests.hexValues`.
- New screen on a critical path: add an id in `Shared/QueueAccessibilityID.swift`. If it belongs on the onboarding or focus smoke flow, update `QueueUITests/CriticalJourneyUITests.swift`.
- New widget or Lock Screen intent: add a `WidgetFocusAction`, cover the command in `WidgetFocusIntentTests`, and if it can award XP drive it from `FocusAwardTests`.
- New schema version: add a migration stage and a round-trip in `SchemaMigrationTests`. Do not rewrite the V1 sample's stored shape.

UI smoke tests find elements by identifier. Do not assert copy, colours, or frames.

## Tooling

| Target | Framework | Where it runs |
| --- | --- | --- |
| QueueCore (domain) | Swift Testing | Linux + macOS (`swift test`) |
| App persistence / UI | XCTest / XCUITest | macOS + Xcode |

## Domain coverage (required)

### Task engine

- FIFO ordering on insert
- Drag reorder updates positions
- Single active task invariant
- Completion advances eligibility (does not auto-start unless preference set)
- Skip, review, undo completion
- Invalid transitions rejected

### Timer engine

- Start, pause, resume, extend, expire
- Restore after relaunch from persisted timestamps
- Background elapsed time correctness
- Clock anomaly policy
- No duplicate completion
- Single active session

### Rewards

- XP amounts by motivation profile
- Idempotent ledger (duplicate sourceEventID + rewardType)
- Level thresholds + multi-level crossing
- No negative XP in v1

### Smart Gaps

- Overlapping meetings merged
- No gaps / exact fit / buffer
- Time zones, all-day, cancelled ignored
- Conflicting calendar sources
- Recommendation explanation; confirmation required to break FIFO

### Persistence (QueueTests, iOS Simulator)

SwiftData models live in the app target, so these run with `QueueTests` rather than `swift test`.

- V1 lists the shipping `@Model` types at `Schema.Version(1, 0, 0)` and the migration plan has no stages yet
- A store written with that plan reopens with the same tasks, preferences, focus session, and XP
- A store written the TestFlight way (unversioned schema, `QueueLocalStore`, no migration plan) reopens through `QueueMigrationPlan` with the same rows
- `AppModelContainer.open` uses the on-disk store (the App Group file after the one-time sandbox copy, otherwise the sandbox file). A failed open throws, leaves the file bytes in place, and does not substitute an in-memory store. Widget and App Intent opens use the same plan. In-memory containers are only created by `makeInMemory()`

## UI coverage

The required smoke flows are onboarding, and add → start focus → complete → XP visible. They live in `QueueUITests` and are not part of the required check. Timer expiry, calendar denial, companion, and Reduce Motion stay out of UI tests.

## How to run

```bash
# Domain package (Linux or macOS)
swift test --package-path .

# App unit and functional tests (macOS + Xcode). Does not run UI tests.
xcodegen generate
xcodebuild -scheme Queue -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:QueueTests test

# UI smoke tests. Slow. Same scheme, separate invocation.
xcodebuild -scheme Queue -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:QueueUITests test
```

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and every push to `main`. The check name to require in branch protection is **Queue CI**.

The **Queue CI** job uses the `macos-26` runner and Xcode 26.6. It runs `swift test` for QueueCore, builds the `Queue` scheme for an available iPhone simulator, and runs `QueueTests` (unit and functional) with code coverage. The coverage bundle is uploaded as the `queue-simulator-coverage` artifact. The hosted runner has no Apple signing certificate, so that job ad-hoc signs the simulator build and replaces the App Group entitlement with an empty file in the checkout only. The committed project still uses Automatic signing for local devices.

**Queue UI Tests** is a separate job and is not a required check. It runs on a nightly schedule (08:00 UTC), on `workflow_dispatch`, and on pull requests labelled `ui-tests`. It runs only `QueueUITests`. A failure there does not fail Queue CI.

## Reporting honesty

Do not claim compilation or test success without executing the relevant command. Document environment limits (e.g. Linux cannot build the iOS app target).
