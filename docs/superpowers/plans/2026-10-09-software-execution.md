# Software execution plan — 2026-10-09

Approved baseline: `DESIGN.md` and `2026-10-08-wrist-magic.md`. Current user authorizes complete software implementation, tests, compilation and repository push. Physical-device acceptance is deferred to the user's Mac mini. All original requirements remain; the work is grouped into software integration units so cross-cutting interfaces are reviewed together.

## Global constraints

Swift 6, iOS 17, watchOS 10, no runtime dependencies. Foreground only. Watch authority for spell/charge, phone authority for sessions/recording. No cross-device clock comparison. Single-use permits, bounded dedupe, no persistent cast queue. ARKit + Metal same frame preview/export, portrait 720x1280 SDR H264 MP4 at 30fps. Three-second countdown, six-second clip, 4.5-second cast cutoff, 1.5-second tail. No microphone. Native UI, approved obsidian/gold tokens, Dynamic Type, accessibility alternative obeys same permit. Hardware metrics never inferred from synthetic tests.

## S01 — Native workspace and verification infrastructure
Original T01. Paired targets, package, schemes, scripts, macOS CI and Linux core toolchain. Produce a checked-in real Xcode project and honest environment evidence. Do not claim hardware installation.

## S02 — Deterministic shared domain
Original T03/T05 plus pure portions of T02/T04/T12/T13/T18. Implement the exact public domain/protocol types from DESIGN §8, cast reducer, quaternion calibration and gesture gating, clip/effect timelines, recovery rules. Unit-test invalid values, state transitions, negative gestures, gaps/cooldown, malformed messages, duplicate/replay/expired tokens, monotonic times and capture boundaries. Synthetic profiles must be clearly experimental, never claim trained thresholds or recognition accuracy. Hardware-adapter portions remain S03/S04.

## S03 — Foreground Watch and live session transport
Original T02/T06/T09. Implement Core Motion adapter and calibration, WatchConnectivity adapters on both platforms, handshake and request/ACK lifecycle, bounded retry and timeout, settings revisions, Watch model and complete Crown/gesture/haptic/sound/VoiceOver flow. iPhone SessionCoordinator is the permit authority and exposes typed hooks for S05. Tests cover cancellation, late replies, disconnect/reconnect, settings and local practice. No background sensor or cast delivery.

## S04 — AR renderer and media pipeline
Original T07/T11/T12/T13/T14/T16. ARFrameSource, portrait transforms, fixed world anchor, deterministic three-spell Metal compositing, shared preview/encoding frame, bounded GPU buffers, AVAssetWriter, validation, timed application audio, atomic recoverable ClipStore and share leases. Integration tests must exercise generated pixel buffers / media, real file IO, duration/PTS/backpressure and composition audio placement. Preserve source on audio failure. Follow original interfaces and specs; no snapshot video or camera-only export.

## S05 — iPhone orchestration and end-to-end flows
Original T10/T15/T17/T18. AppModel, native entry/tutorial/home/settings/recovery, Reality and fixed composition Show Off coordination, first-frame permission, countdown, one cast, movement invalidation, cancellation/interruption and partial clips, playback/save/add-only permission/system share. Test state transitions with injected clocks/dependencies. Wire all S03/S04 production adapters; no disconnected showcase UI. Progress and errors must reflect real operations. Persist settings, tutorial and latest review recovery.

## S06 — Shared visual assets and accessibility regression
Original T08/T19/T21 software portions. Exact tokens and native components, independent procedural artwork/sound resources with provenance, three distinct effects, accessibility IDs/values, Dynamic Type, reduce motion, full screen-state coverage. Add XCUI test target/flows and screenshot matrix. Run static verifier, simulator/UI tests where available; runtime visuals and hardware feel not seen remain pending. Do not crop prototype screenshots into UI.

## S07 — Review, build closure and handoff
Original T20/T22 and remaining software validation. Fresh core/debug/release builds, iOS/watch simulator and integration tests, CI compilation of both targets and shaders. Resolve review/build failures. Update README, INSTALL, DEVELOPMENT progress, RELEASE-CHECKLIST and Evidence index with actual outputs and exact remaining physical tests. Push authorized repository branch; ensure default branch is usable for fresh clone of this initially empty repo. No App Store publication.

## Acceptance tracking

Each original T01–T22 receives separate code/test/hardware status in the final handoff. Original hardware checkboxes remain unchecked. Functional gaps must be recorded as unfinished code, never hidden as physical testing. Completed software requires evidence; compilation is a distinct gate from source review.
