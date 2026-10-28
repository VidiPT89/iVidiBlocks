# Gameplay review, 2026-10-28

Follow-up to the general review of 2026-10-27, completed after a session interruption.

## Improvements shipped

- Horizontal repeat now begins at DAS, preserving the remainder of a frame crossing
  that boundary. It previously waited another ARR interval and discarded elapsed time.
- Opposite held buttons use the latest press. Releasing one no longer releases the
  other, and releasing the latest restores the other held direction.
- Scene callbacks carry their source engine identity. Delayed events from an old
  run cannot finish, record or show a banner over a restarted run. Weak captures
  avoid retaining the view model through the scene; callbacks are detached on exit.
- The hold panel is now a tappable control and dims when holding is unavailable.
- Clear banners show points and both chain bonuses together.
- Marathon no longer publishes an unused clock every frame. Ultra only publishes
  the whole seconds shown by its HUD; the engine retains precise timing for results.
- HUD panel headings stay on one line. Gameplay content is capped at 600 points
  on wide layouts while retaining the narrow-screen control fallback.
- Removed the unused banner UUID and its unused identity/equality conformances.
  Reference inspection found no further unreferenced production helpers. Framework
  callbacks and the test-only start entry point are intentional.

## Verification

- 133 XCTest tests pass on iPhone 17e, iOS 26.5 Simulator.
- New coverage includes precise DAS timing, invalid frame durations, stale events
  after restart, opposite held controls, hold availability and banner details.
- A deterministic mixed-input test covers 20 seeds in each of the three modes,
  checking placement, ghost landing, board size, pause and monotonic score/lines.
- Layout tests render actual SwiftUI/SpriteKit views at 320x568 and 768x1024 points,
  with Portuguese, dark/right-handed and light/left-handed configurations. Captures
  were visually inspected, including an active piece and ghost. This is a sized
  hosting-window check on the iPhone simulator, not a native iPad device run.
- Release generic iOS build (signing disabled) and Xcode static analysis pass.
- The first simulator failed during test bootstrapping with an audio service error;
  the successful rerun used a different simulator. No failed test was hidden or removed.

The snapshots do not prove gesture accuracy, VoiceOver navigation, all text sizes,
physical haptic feel or interruption behavior on real hardware. Those checks remain.
No archive, App Store submission or physical-device session was performed.

## Product direction

Keep Marathon, Sprint and Ultra, and retain the existing gameplay rules and local
records. The most valuable next addition is persistence of an unfinished run across
app termination, with validated versioned state and explicit resume/discard controls.
A guided practice mode could follow to teach rotation, hold, combos and T-spins.
Neither feature was implemented in this review. Cloud services or extra game modes
would add scope before these everyday usability improvements are finished.

## Follow-up: saved runs

The recommended persistence was implemented afterwards. An unfinished run is saved
as versioned JSON when the app leaves the foreground or the player quits to the
menu. The menu then offers Continue or Discard; starting another mode asks before
discarding it. A restored run opens on the pause screen with the board, piece,
hold, queue, counters, clock and pending clear intact. DAS, ARR and the ghost follow
the current settings. Files from another version, or states the engine could not
have produced, are deleted instead of being offered. Finishing or restarting a run
removes the save. Guided practice remains a possible future addition.

Verification: 145 XCTest tests pass on iPhone 17 Pro, iOS 26.5 Simulator, including
round-trip, mid-clear, deterministic continuation and rejected-file cases. Release
generic iOS build (signing disabled) and static analysis pass. Two earlier runs failed
before testing because the simulator refused to launch the app while still booting.
Resuming after the app is closed still needs a physical-device check.
