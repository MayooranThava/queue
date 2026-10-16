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

| State | Extra motion |
| --- | --- |
| preparing | Soft settle bob + screen warm-up |
| working | Typing hands, laptop glow, lean, blink |
| paused | Slower breath, dim screen, slight lean-back |
| timerExpired | Soft thought bubble, narrowed eyes (never angry) |
| celebrating | Hop + restrained orbit sparkles + smile |
| levelUp | Stronger sparkles + floating badge |

Completion: staged entrance → XP count (`motion.xpCount`) → level bar fill → optional level-up badge (`motion.levelUp`). All skippable; Reduce Motion uses cross-fade/static.

## Visual language reminders

- Off-white / warm ivory light backgrounds; deep charcoal Focus
- Sage secondary surfaces; yellow-green reward accents
- No heavy gradients, excessive shadows, or constant motion
- Companion must not obscure task title or primary controls
