# Follow-up work

Active scope, owners and acceptance criteria are in [the plan](docs/MODERNIZATION_PLAN.md). These follow-ups do not replace the playback, audio, chat, compatibility and UI release gates.

| Priority | Work | Evidence / acceptance |
|---|---|---|
| P1 | Complete hardware playback, audio, chat and latency validation | [Verification record](docs/DEVICE_VERIFICATION.md); no hardware claims from simulator output |
| P1 | Finish Opus interface and Kimi/Grok review rounds | Preserve nondeprecated features; actual checked files required |
| P1 | Remove temporary build dependency exception when patched | Exact policy expires November 6, 2026; new advisory/version/patch fails CI until reviewed |
| P2 | Handle declared external launch/deep-link input | Manifest advertises input launch; main does not dispatch launch content |
| P2 | Expand demux layouts and verified historical VOD CDN coverage | Captured streams and fail-closed fixtures before widening support |
| P2 | Review OAuth refresh and account renewal | Stored refresh metadata is not a background renewal flow; preserve anonymous playback |
| P2 | Reduce remaining simulator dependency advisories | Inspect compatible fixes; avoid overrides breaking CommonJS consumers |
| P2 | Complete locale coverage for new status and recovery copy | Inventory translations and verify long-string layouts |
| P3 | Investigate maintained VOD chat replay | No stable verified implementation in scope; retain unavailable notice |
| P3 | Profile animated emotes and optional audio-only playback | Measure older-device performance; verify actual audio rendition |
| P3 | Assess a future FHD-native interface | Keep current HD layout until broad hardware/focus validation |
