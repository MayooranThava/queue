# Queue Animation Specification

Figma storyboards are design references, not runtime assets. Implement natively.

## Design tokens (motion)

| Token | Value | Use |
| --- | --- | --- |
| `motion.quick` | 0.2s | Buttons, toggles |
| `motion.standard` | 0.35s | List reorder, sheet present |
| `motion.celebration` | 0.8–1.2s | Task complete companion |
| `motion.xpCount` | ~0.8s | XP counter |
| `motion.levelUp` | ~2.0s | Level-up sequence |
| `motion.queueAdvance` | 0.45s | Next task promotion |

Easing: gentle spring for celebration; easeInOut for progress fills.

## Companion states

`idle → preparing → working → paused → completed → celebrating → levelUp`  
`working|paused → timerExpired`

| State | Motion |
| --- | --- |
| idle | Occasional blink, subtle breathing |
| preparing | Settles at desk / laptop |
| working | Gentle typing, blink, laptop interaction |
| paused | Typing stops; relaxed posture |
| completed | Brief positive reaction |
| celebrating | Small expressive movement + restrained sparkles |
| levelUp | Stronger celebration, short confetti, badge |
| timerExpired | Thoughtful pause — never angry/disappointed |

## Completion sequence (committed state only)

1. Persist completion  
2. Award XP (idempotent ledger)  
3. Companion reaction  
4. Show XP gain + count up  
5. Fill level bar  
6. Level-up if crossed (may multi-level)  
7. Offer next task  
8. Animate queue advance  

Celebrations are **skippable**. Never block navigation. With Reduce Motion: cross-fade + static companion, no confetti loops.

## Implementation layers

1. SwiftUI for layout, XP, progress  
2. `CompanionAnimationView` → SpriteKit atlas renderer (`SKTextureAtlas` + `SKSpriteNode`)  
3. Pause companion activity when scene phase ≠ active  
4. `QueueMotion` tokens + soft haptics (`QueueHaptics`) on focus transitions  
5. `FocusCountdownRing` — remaining fraction from session timestamps  

### Native companion detail (current)

SpriteKit plays authored PNG sequences from `Queue/Resources/Atlases/`:

| Atlas | States | Playback |
| --- | --- | --- |
| `Working.atlas` | working, preparing; static for idle/paused | **2.6s seamless loop** (12 frames) |
| `DeepFocus.atlas` | deepFocus | **3.5s seamless loop** |
| `Completed.atlas` | completed, celebrating, levelUp | **~1.7s once**, hold final frame |
| `Expired.atlas` | timerExpired | **~1.5s once**, hold final frame |

All four atlas folders ship in the bundle. Replace DeepFocus / Completed / Expired PNGs in place (same size + naming) when unique art is ready — the SpriteKit loader already keys off those atlas names. If an atlas is empty at runtime, textures fall back to Working so Focus never shows an empty frame.

Frames share identical 768×768 bounds, sprite anchor `(0.5, 0.5)`, and scale. `resize: false` on `SKAction.animate` prevents desk/laptop drift. The `SKScene` is created once in `CompanionSpriteView`’s coordinator and is **not** rebuilt on Focus timer ticks. XP / completion logic stays in `FocusSessionView` and never depends on animation playback.

Reduce Motion → mid/end static pose from the mapped atlas. Background (`scenePhase != .active`) pauses the scene so loops suspend without tearing down textures.

`CompanionAnimationView(compact: true)` uses the same SpriteKit scene inside the Queue “Now” card.

Completion: staged entrance → XP count (`motion.xpCount`) → level bar fill → optional level-up badge (`motion.levelUp`). All skippable; Reduce Motion uses cross-fade/static.

### Timer visibility outside Focus

- Queue “Now” card shows a live `TimelineView` countdown + mini ring while a session is running/paused/expired
- Home Screen widgets + Live Activities use **`Text(timerInterval:countsDown:)`** so the clock keeps ticking while the app is suspended
- `FocusActivityStore` (App Group) mirrors timestamps; timeline refreshes mainly for progress ring / expiry chrome
- Task titles use smaller type + `lineLimit` / `minimumScaleFactor` so they don’t clip beside the companion

## Visual language reminders

- Off-white / warm ivory light backgrounds; deep charcoal Focus
- Sage secondary surfaces; yellow-green reward accents
- No heavy gradients, excessive shadows, or constant motion
- Companion must not obscure task title or primary controls
