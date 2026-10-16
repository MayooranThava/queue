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
2. `CompanionAnimationView` → Rive if configured, else SwiftUI vector, else static  
3. Pause companion activity when scene phase ≠ active  
4. `QueueMotion` tokens + soft haptics (`QueueHaptics`) on focus transitions  
5. `FocusCountdownRing` — remaining fraction from session timestamps  

### Native companion detail (current)

Layered vector scene in a fixed **512×512** design space (`Features/Companion`), guided by
`DesignReferences/queue-character-concept.png` — **not** cropped sprite playback.

Cream companion, warm lamp, fixed desk / laptop / plant / books. Only character motion + effects animate.

| State | Loop / once | Motion |
| --- | --- | --- |
| idle | loop | Soft breath, `...` bubble |
| preparing | loop | Mug in hands, screen warm-up |
| working | **2.6s seamless loop** | Lamp on, alternating typing arms, independent blinks, subtle lean |
| deepFocus | **3.5s loop** | Headphones, calmer hands, closed-eye beats, floating notes |
| paused | loop | Dim screen, slower breath |
| timerExpired | **~1.5s once** | Hourglass, scribble → lightbulb (encouraging) |
| celebrating / completed | **~1.7s once** | Smile, arms up, bounce, sage/gold sparkles |
| levelUp | once | Celebrate + held glowing star |

Differences vs concept sheet (intentional for maintainability): vector recreation rather than frame crops; leaf logo simplified; particle count restrained for Focus performance.

`CompanionAnimationView(compact: true)` keeps the same scene readable inside the Queue “Now” card.

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
