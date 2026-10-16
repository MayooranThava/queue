# Queue

One task at a time. Small tasks. Real progress.

Queue is a premium iOS productivity app: a FIFO task queue, a reliable focus timer, and a calm companion with XP rewards. Local-first, privacy-conscious, and built for App Store quality.

## Status

**Phase 0** complete (architecture & docs).  
**Phase 1** in progress: app foundation — navigation, design system, SwiftData tasks, Queue screen, onboarding shell, FIFO domain service + tests.

| Capability | Status |
| --- | --- |
| Domain FIFO / timer / XP / Smart Gaps engines | Implemented in `QueueCore` |
| Queue UI + add/edit/reorder + persistence | Phase 1 |
| Focus timer UI + notifications | Phase 2 |
| Companion celebrations + Progress | Phase 3 |
| Apple Calendar + Smart Gaps UI | Phase 4 |
| Outlook (MSAL/Graph) | Phase 5 |
| App Store polish / StoreKit | Phase 6 |

## Requirements

- Xcode 15+ / iOS 17+
- [XcodeGen](https://github.com/yonaskolov/XcodeGen) optional (`project.yml`) — or use the committed `Queue.xcodeproj`
- Swift 5.9+ (Swift 6 toolchain works for `QueueCore` tests on Linux)

## Quick start (macOS)

```bash
# Option A: committed project
open Queue.xcodeproj

# Option B: regenerate from project.yml
brew install xcodegen
xcodegen generate
open Queue.xcodeproj
```

Select the **Queue** scheme, an iPhone simulator, and Run.

Or regenerate the project file:

```bash
python3 Scripts/generate_xcodeproj.py
```

## Domain tests (Linux or macOS)

```bash
swift test
```

These cover FIFO ordering, timer lifecycle, idempotent XP awards, and Smart Gaps.

## Documentation

- [Architecture](Docs/ARCHITECTURE.md)
- [Product requirements](Docs/PRODUCT_REQUIREMENTS.md)
- [Implementation plan](Docs/IMPLEMENTATION_PLAN.md)
- [Testing](Docs/TESTING.md)
- [Animation spec](Docs/ANIMATION_SPEC.md)
- [Microsoft Outlook setup](Docs/MICROSOFT_SETUP.md)
- [Design references](DesignReferences/README.md)

## Design

Visual language: warm ivory, sage secondary surfaces, charcoal Focus mode, restrained yellow-green rewards. Inspired by Weekstack’s calm minimalism with Queue’s own identity. Figma: [Queue design file](https://www.figma.com/design/dl0Mw2ko5CmMqfFq8Czynu).

## Privacy

Tasks and XP live on-device (SwiftData). Calendar access is optional and read-only. Analytics is a local interface in v1 — no third-party telemetry without an explicit privacy decision.

## License

Proprietary — all rights reserved unless otherwise stated by the repository owner.
