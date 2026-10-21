# Queue Companion Animation — Production Plan

Status: **Phase 1 in progress; animated character art NOT approved for release.**
Owner: Queue iOS app. Baseline: stable post-warp-rollback build.

## Definition of done

A 5–10 second screen recording of a running Focus task visibly shows paws pressing the keyboard, occasional natural blinking, and steam rising from the mug. The desk, lamp, laptop, plant, mug and books remain pixel-stationary. The loop has no popping, ghosting, detached shapes, or visible seams. Pause, resume, background/foreground, completion, and Reduce Motion work without a crash. Xcode Cloud archives successfully and the actual TestFlight build passes on-device review.

## Findings from repository audit

- `Working.atlas` and `DeepFocus.atlas` currently contain 12 full-scene images each. These are near-static character poses, not a usable articulated typing sequence.
- The previous `Typing.atlas` contains 20 procedural oval-paw PNGs that floated near the mug. It is deliberately excluded from `project.yml` and **must not** be shipped or re-enabled.
- Runtime `SKWarpGeometryGrid` deformation was rolled back after a task-start crash. Do not restore this path.
- `CompanionSpriteScene` is reusable across timer ticks; `CompanionSpriteView` owns the scene through its coordinator.
- `CompanionAnimationClip` uses static playback for pause/idle/Reduce Motion. Validate this behavior before interpreting a still image as a playback failure.
- This repository has a **committed `Queue.xcodeproj`** as well as `project.yml`. Changes to resource inclusion must be reflected in the project used by Xcode Cloud, not just the YAML.

## Phase 1 — Asset inventory and playback audit

1. Preserve a known stable TestFlight baseline and record its commit SHA.
2. Inspect source illustration at full resolution and determine whether there is an editable layered master, 3D scene, or only flattened PNGs.
3. Establish exact coordinates for hands, face, keyboard, and mug in source-image pixel space.
4. Confirm the Focus view's `shouldAnimate`, `isSceneActive`, state transitions and Reduce Motion behavior.
5. Run the atlas validator in `Scripts/validate_companion_frames.py` on any proposed frame pack.

**Gate:** no animation changes until an approved moving preview exists.

## Phase 2 — Produce actual animation-ready art

Preferred: obtain the original layered illustration or 3D model and animate the hands there. Keep the stationary scene in a single base image; export only changing character regions with identical dimensions and anchor points. If only flattened art exists, carefully reconstruct the hand/keyboard occlusion as layers before rendering. Do not fake movement with white ovals or whole-scene transforms.

- Working: 20 RGBA frames, `typing_000.png` through `typing_019.png`, same size, with distinct hand poses and a seamless first/last transition.
- Blinking: separate face/eye overlay with neutral, closing, closed, opening poses.
- Steam: independent alpha animation above the mug, without affecting the character atlas.
- Produce an MP4/GIF contact-sheet preview at the **actual rendered size** of the Focus screen.
- Run automated checks for dimensions, alpha, non-identical frames, and stationary pixels. Manually inspect frame-to-frame hand positions and occlusion.

**Gate:** approve the moving preview before changing shipped assets.

## Phase 3 — SpriteKit integration

- Keep base scene static; overlay correctly registered hand/eye sprites with fixed anchors and z-order.
- Use `SKTextureAtlas` and `SKAction.animate(with:timePerFrame:resize:restore:)` for the 20-frame hand loop, ~16–20 FPS.
- Do not recreate actions on each countdown tick. Only transition when clip/state changes.
- Pause animation when requested; respect Reduce Motion; resume after app foregrounding.
- Keep steam and blink loops independent, with non-synchronized cadence.
- Remove all obsolete procedural paw and warp paths before release.

## Phase 4 — Test matrix

- Cold launch; start task; 2-minute playback; pause/resume; background/foreground; add five minutes; complete; restart.
- Idle, working, deep focus, completed, expired and Reduce Motion.
- Verify no crashes, action buildup, memory growth, or frame jitter.
- Verify full-scene stationary objects against a pixel-difference mask.
- Verify project resources are included in the **committed Xcode project** and the Xcode Cloud workflow.

## Phase 5 — Release gate

1. Commit reviewed artwork and code in a traceable change.
2. Xcode Cloud build **success** for that exact SHA.
3. Install that build in TestFlight and record the Focus scene.
4. Confirm visible typing, blink, steam, stationary props, smooth loop, and task stability.
5. Only then mark animation **done** in README/ANIMATION_SPEC.

## Explicit non-goals / safety rules

- Do not substitute code-generated circles or warping of the entire illustration.
- Do not call a passing CI build visual validation.
- Do not claim production-ready without viewing a moving build.
- If a source asset is unavailable, report that blocker instead of silently inventing mismatched frames.
