# Follow-up work

Active scope, owners and acceptance criteria are in [the plan](docs/MODERNIZATION_PLAN.md). These follow-ups do not replace the playback, audio, chat, compatibility and UI release gates.

| Priority | Work | Evidence / acceptance |
|---|---|---|
| P1 | Complete hardware playback, audio, chat and latency validation | [Verification record](docs/DEVICE_VERIFICATION.md); no hardware claims from simulator output |
| P1 | Remove temporary build dependency exception when patched | Exact policy expires November 6, 2026; new advisory/version/patch fails CI until reviewed |
| P2 | Handle declared external launch/deep-link input | Manifest advertises input launch; main does not dispatch launch content |
| P2 | Expand demux layouts and verified historical VOD CDN coverage | Captured streams and fail-closed fixtures before widening support |
| P2 | Review OAuth refresh and account renewal | Stored refresh metadata is not a background renewal flow; preserve anonymous playback |
| P2 | Check identity preservation during overlapping startup and login | A late launch rendezvous can replace the device code promoted by login; no resulting failure is established. Test the overlap before adding a guard |
| P2 | Reduce remaining simulator dependency advisories | Inspect compatible fixes; avoid overrides breaking CommonJS consumers |
| P2 | Make tagged channel releases validate their exact source | Release currently relies on main CI; gate tag artifacts on lint/audit/tests/package checks |
| P2 | Expand production resolver and container reproducibility coverage | Add create_app resolver-wiring regression; consider digest-pinned Python base image |
| P2 | Measure native UI rendering and per-instance regex caching | Actual TV typography/contrast/overscan, older-device scrolling and before/after card recycle timing; simulator gaps remain unproven |
| P2 | Review Spanish/Portuguese interface strings and native long-string fit | All new copy is covered; phase-two translations remain flagged for native-speaker review |
| P2 | Verify own-channel navigation and live playback on Roku | Account emits LIVE content by login; actual handler/Back regressions pass, native playback remains pending |
| P2 | Verify delayed sign-in failure focus on Roku | Minimal focus guard and tracked late-failure/menu/return/Retry/disposal regressions pass; confirm native focus |
| P2 | Verify recorded seek tap/hold timing on physical and mobile remotes | One tap advances ten seconds; a 0.4-second initial delay precedes accelerated repeats. Actual engine regressions pass; hardware timing remains pending |
| P2 | Verify native child quality-dialog keys | Simulator diverges on child StandardMessageDialog Up/Down/OK/Back; option/index semantics pass, native keys remain a release gate |
| P2 | Refresh the first-launch release notes | Native What's New still describes analytics as opt-out and claims reduced latency; align the historical copy with explicit consent and unmeasured experimental latency |
| P3 | Supply storyboard thumbnails after capturing a supported source | Thumbnail consumer is preserved; no producer exists at baseline or current source. Do not widen playback queries without verified evidence |
| P3 | Keep row geometry arrays aligned for future content types | Push labels, sizes and heights together only for supported rows; current produced types are covered |
| P3 | Investigate maintained VOD chat replay | No stable verified implementation in scope; retain unavailable notice |
| P3 | Profile animated emotes and optional audio-only playback | Measure older-device performance; verify actual audio rendition |
| P3 | Profile emote-ID parser regex reuse on busy chats | The task thread compiles this pattern per tagged message; measure older-device CPU before adding a per-task cache |
| P3 | Assess a future FHD-native interface | Keep current HD layout until broad hardware/focus validation |
| P3 | Track the simulator's ButtonGroup role-font boundary | Font role nodes become focusable children in brs-engine; tests/probes remove those nodes explicitly. Keep production fonts and verify native rendering |
| P3 | Recheck menu callback timing on native hardware | One recovery probe printed a menu callback before its single Following build, with no visible failure; the probe does not establish a production defect |
