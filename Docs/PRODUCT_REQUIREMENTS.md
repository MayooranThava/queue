# Queue Product Requirements

## Promise

**One task at a time. Small tasks. Real progress.**

Queue helps people stop procrastinating by combining a FIFO task queue, a gentle focus timer, and a calm companion with XP rewards.

## Target users

- Professionals balancing meetings and deep work
- Students managing assignments and study sessions
- Developers and knowledge workers
- People who struggle with procrastination
- Anyone who wants a simpler alternative to complex productivity tools

## Core principles

1. **One task is active** — others remain visible but secondary
2. **Completion is satisfying** — polished celebration, meaningful reward
3. **Time is guidance, not punishment** — missing an estimate never erases work
4. **User stays in control** — recommendations never silently reorder
5. **Minimal by default** — calm, spacious, adult-friendly

## Daily loop (P0)

Open Queue → See one task → Focus → Finish → Celebrate → Advance

## Feature scope by phase

| Capability | MVP priority | Phase |
| --- | --- | --- |
| FIFO queue create/edit/reorder/persist | P0 | 1 |
| Focus timer + lifecycle restore | P0 | 2 |
| Companion + XP + Progress | P0 | 3 |
| Onboarding | P0 | 1–3 |
| Apple Calendar + Smart Gaps | P1 | 4 |
| Outlook (MSAL/Graph) | P2 | 5 |
| StoreKit Pro | P2 | 6+ |
| Rive companion asset | P2 | 6 |
| AI / LLM features | Out of scope | — |
| Custom backend | Avoid unless justified | — |

## Screens (required)

- Onboarding (welcome, explanation, motivation style, optional calendar, notifications rationale, first task)
- Queue (active task, countdown, companion, upcoming, quick add, reorder, detail, review)
- Focus (title, remaining, companion, controls, complete/extend/pause, exit confirm)
- Completion (celebration, XP, streak, next task)
- Calendar (agenda, sources, Smart Gaps)
- Progress (completions, focus minutes, XP/level, streaks, trends, achievements)
- Settings (calendars, notifications, motivation, companion, motion, privacy, data, purchases)

Every screen: loading, empty, error, populated states.

## Accessibility (launch requirement)

Dynamic Type, VoiceOver, contrast, Reduce Motion, Dark Mode, accessible labels, adequate touch targets, non-color status indicators, timer announcements.

## Privacy

- Local-first task data
- Calendar read-only; no email scopes
- Local analytics interface first — no paid analytics SDK without an explicit privacy decision
- Clear permission copy before system prompts

## Monetization hypothesis

| Free | Pro (one-time, hypothesis) |
| --- | --- |
| Core FIFO, timer, basic companion, basic XP, basic calendar visibility | Advanced analytics, companion themes, Smart Gaps prefs, deeper insights |

Never paywall accessibility, basic completion, or access to existing tasks.

## Non-goals (initial release)

- Project management / multi-assignee workflows
- Harsh streak-loss guilt notifications
- Negative XP
- Silent auto-start of next timer (unless user enables preference)
- Backend sync accounts
- AI scheduling
