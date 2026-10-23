# Queue Testing Strategy

## Philosophy

Prefer reliable domain tests over superficial snapshots. UI tests cover critical happy paths once screens stabilize.

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

## UI coverage (Phase 6 focus)

- First-run onboarding
- Add task → start focus → complete → XP celebration
- Timer expiry paths
- Calendar permission denied
- Companion disabled / Reduce Motion

## How to run

```bash
# Domain package (Linux or macOS)
swift test --package-path .

# Full iOS app (macOS + Xcode)
xcodegen generate
xcodebuild -scheme Queue -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and every push to `main`. The check name to require in branch protection is **Queue CI**.

The job uses the `macos-26` runner and Xcode 26.6. It runs `swift test` for QueueCore, builds the `Queue` scheme for an available iPhone simulator, and runs the `QueueTests` unit-test target. The hosted runner has no Apple signing certificate, so that job ad-hoc signs the simulator build and replaces the App Group entitlement with an empty file in the checkout only. The committed project still uses Automatic signing for local devices.

## Reporting honesty

Do not claim compilation or test success without executing the relevant command. Document environment limits (e.g. Linux cannot build the iOS app target).
