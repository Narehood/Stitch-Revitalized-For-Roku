# Stitch modernization plan

Baseline: `3747337`, audited October 6–7, 2026. Work branch: `modernize/stitch-playback-and-ui`.

## Status and scope

The playback, chat, proxy, build, and dependency audits are complete. Their source findings have been checked and disputed conclusions corrected. Claude Opus 5.5's interface audit remains incomplete: its resumed run reached another session limit before producing a report. Its source-inspection work and private probe tooling have been preserved. The next retry is October 7 at 5:55 a.m. Eastern, after the provider's 5:50 a.m. reset. This plan authorizes independent correctness work; the interface specification and acceptance results will be added when that audit finishes. The project is not yet declared usable or ready for release.

The target is a maintained native Roku SceneGraph application with working live and VOD video and audio, reliable live text chat, and an explanation when VOD or clip chat is unavailable. Offer 1440p when the Roku decoder and stream transport support it. Preserve existing features and currently supported devices. Explore lower live latency as an opt-in experiment and measure it on hardware before making claims.

The user will provide developer-mode Roku access tomorrow. Local compilation, fixtures, and simulation cannot establish HEVC playback, audible sound, hardware performance, or real latency. Those remain release gates. No minimum OS or device requirement is raised by this plan.

## Baseline evidence and important corrections

- Stream selection currently compares video height with `GetSupportedGraphicsResolutions()`. That describes the UI plane and incorrectly excludes video a Roku can decode. `source/constants.brs` does assign the global; a claim that the filter is inactive was rejected.
- The live Usher URL advertises AVC only. Current Streamlink's own Twitch integration uses Usher codec names such as `h264`, distinct from HLS `avc1` codec strings. Verify exact negotiation instead of assuming that adding `hvc1` to the URL works.
- Proxy rewriting changes selected content URLs but leaves quality metadata unmodified. Rebuilding content from that metadata loses the proxy and playback flags.
- A failed content task can leave the player on its loading overlay indefinitely. Shared HTTP waits and OAuth device polling are unbounded.
- The proxy currently returns original muxed media if no init track map is cached. A media-first request, eviction, or discontinuity can therefore produce an unplayable rendition.
- Chat sends stored OAuth credentials over plaintext TCP and polls an idle socket continuously. The renderer is read-only, so an anonymous fallback can preserve old-device support without exposing those credentials.
- `ParseJSON(roUrlEvent)` is supported through `ifString` and was verified with an actual local HTTP fixture. Explicit decoding and status checks improve maintenance; implicit coercion is not a confirmed playback defect.
- There is no verified official VOD chat replay API here. A third-party persisted-query hash is insufficient evidence for a working replay implementation. The requested unavailable-chat notice meets the initial scope.
- The checked-out project already compiles and the proxy's 93 baseline tests pass. That does not prove live Twitch or Roku playback works.
- SceneGraph removal does not define an automatic application `onDestroy` callback. A retained-node simulator probe left a repeating Timer running after detachment; an explicit exported cleanup call stopped it. Permanent removals need explicit cleanup, while retained back-stack screens remain reusable.

Primary references: [Roku media support](https://developer.roku.com/dev/docs/specs/media), [device capabilities](https://developer.roku.com/dev/docs/ifdeviceinfo), [Video node](https://developer.roku.com/dev/docs/video), [Roku releases](https://developer.roku.com/dev/docs/release-notes), [Twitch IRC](https://dev.twitch.tv/docs/chat/irc/), [Twitch device authentication](https://dev.twitch.tv/docs/authentication/getting-tokens-oidc/), [Streamlink Twitch source](https://github.com/streamlink/streamlink/blob/master/src/streamlink/plugins/twitch.py), and [Twitch 2K announcement](https://blog.twitch.tv/en/2026/06/17/introducing-dual-format-and-2k-streaming-on-twitch/).

## Decisions

### Compatibility and 1440p

Keep the existing 720p UI coordinate system during this modernization; it is independent of video resolution. Use the documented decoder query for AVC and HEVC support and conservative codec/profile/level/resolution/frame-rate checks for each offered rendition. A 4K-capable decoder may support 1440p even when its UI or connected display is 1080p. The firmware manifest entry is informational, not proof of an enforced support floor.

Negotiate HEVC only on capable devices. Apply capability filtering to live and VOD consistently. Older devices retain compatible AVC qualities. Retain automatic, highest, lowest, source, and manual quality selection; automatic mode must contain only playable URLs. Do not advertise AV1 solely because some Roku hardware decodes it.

### Audio service and Docker

Keep the optional fMP4 demux service. Roku's HLS CMAF support requires separate audio and video, while the relevant Twitch Enhanced Broadcasting media combines tracks. The service splits existing samples without transcoding; this preserves video quality and avoids the cost of a general media transcoder. A BrightScript-only equivalent cannot hand demuxed in-memory media to the Roku Video node.

Docker is a deployment convenience, not a requirement. Document direct Python execution as well as the container. Compatible TS streams bypass the service. Preserve already-separated audio relationships rather than treating every `EXT-X-MAP` as proof of muxed tracks. If the service is unavailable, use a compatible native fallback when one exists and otherwise explain the requirement with an actionable error.

### Chat and authentication

Preserve Twitch, BTTV, FFZ, and 7TV emote support and existing chat controls. Prefer secure native WebSocket transport where the OS exposes it; older Roku devices may use anonymous read-only TCP. Never send OAuth on plaintext TCP. Do not increase the minimum OS to get WebSockets. Show a VOD/clip notice rather than an empty chat panel.

Anonymous browsing and playback remain supported. Device identity and an account OAuth token are separate credentials. Validate HTTP status and JSON shape, bound device-code polling by expiry, honor pending/slow-down/denial states, and preserve preferences and account state during temporary network failures.

### Low latency

Keep stable playback as the default. Add an explicit experimental setting only around documented controls and bounded live-edge behavior. Do not invent player flags, promise LL-HLS support, or equate lowest quality with guaranteed low latency. Use measured segment latency where available for chat synchronization. Compare stable and experimental modes on the same device/network/broadcast, including rebuffering and recovery.

## Implementation order

### 1. Playback correctness and stream selection — highest priority

Owner: playback implementation agent. Files: `GetTwitchContent`, `VideoPlayer`, `StitchVideo`, `CustomVideo`, `VideoErrorHandler`, `TwitchContentNode`, and a replacement device-capability/HLS helper. Shared HTTP/auth and settings schema are owned by the parent.

- Replace the graphics-resolution filter with decoder-aware selection and verified Usher codec negotiation.
- Parse quoted HLS attributes, CRLF, relative URLs, missing attributes, and rendition relationships robustly. Keep metadata separate from UI labels and preserve source/automatic behavior.
- Keep proxy URLs and transport flags in every manual/automatic/recovery quality entry. Preserve restart position for VODs.
- Bound manifest and fMP4 detection requests. Resolve clip GraphQL URLs first; constrain legacy fallback probing to a small total budget.
- Treat invalid task results as user-visible load failures, preserve useful restricted/expired/missing notices, and avoid silent error-970 exits.
- Bound reconnect/watchdog recovery over the playback session rather than resetting counters on every retry.
- Use supported start-position metadata for VOD bookmarks and retain seeking, time-travel, thumbnail previews, recent channels, and channel actions.
- Explain unavailable VOD/clip chat; preserve live chat toggle behavior. Keep UI layout changes for Opus after playback contracts stabilize.
- Implement the opt-in latency experiment if it can be supported without compromising recovery; hardware acceptance remains pending.

Acceptance: executable manifest/capability fixtures cover 1080p on a 720p UI device, HEVC 1440p inclusion/exclusion, quoted codecs, relative URLs, proxy-preserving quality changes, failure behavior, and codec fallback. Compilation and existing feature contracts remain valid.

### 2. Proxy correctness, resource bounds, and deployment

Owner: proxy implementation agent. Files: `fmp4-demux-proxy/` only. Parent owns workflows.

- Carry exact init identity and necessary input byte ranges into rewritten segment URLs. Each media request resolves its init independently; coalesce concurrent work. Track maps cannot depend on request order or media directory names.
- Fail explicitly when tracks or unsupported fragment shapes cannot be split. Never label unchanged muxed bytes as a separated rendition.
- Test discontinuities, init eviction, concurrent audio/video fetches, out-of-order requests, and deterministic sample/offset preservation.
- Correct nested master/rendition/audio relationships and propagate track hints through rendition reports. Handle byte ranges correctly or fail with a descriptive unsupported response rather than returning corrupt media.
- Validate redirect targets before connecting; restrict upstream destinations and private/local addresses by default. Keep a narrowly explicit unsafe option for local fixtures/development, never enabled in production examples.
- Add finite deadlines, response-size limits, byte-based cache bounds, and bounded concurrency/in-flight bookkeeping.
- Redact signed upstream URLs and request queries from application/access logs. Require explicit trusted public URL behavior instead of trusting forwarded host/protocol headers from any caller.
- Keep locked dependencies, nonroot execution, health checks, and simple direct Python/container instructions. Update the container/tooling where justified and test supported Python versions.

Acceptance: proxy lint, formatting, and meaningful pytest cases pass. CI builds the image and checks `/health`. Local Docker execution is currently unavailable and must be reported accurately.

### 3. Live chat reliability

Owner: chat implementation agent. Files: `components/Modules/Chat/` plus a pure IRC helper and its fixtures. Parent owns the shared HTTP helper and emote-task HTTP decoding integration if necessary.

- Implement safe capability-gated transport, connection readiness, finite connect/reconnect backoff, PING/PONG and server RECONNECT handling.
- Read buffered chunks and assemble fragmented lines with bounded buffers/queues. Wait or back off while idle; never spin forever waiting for a newline.
- Fix the confirmed parser substring-length defect and timestamp trailing space. Support IRC tag escaping and malformed tags/emote ranges without crashes.
- Synchronize messages to a bounded measured delay when available, with an immediate mode; do not advertise the old empirical 23-second figure as newly measured.
- Handle hide/show/destroy without duplicate jobs or observers, and preserve configured font and emote behavior.

Acceptance: actual parser fixtures include tagged messages, source prefixes, embedded colons, escaped display names, malformed emotes, PING, RECONNECT, and fragmented lines. Inspect all outbound legacy messages to establish that no user token can be transmitted. Live server/device behavior still needs hardware verification.

### 4. Shared networking, account state, diagnostics, and maintenance

Owner: parent.

- Give the shared request helper finite defaults, capped retries, cancellation and invalid-input handling while preserving its `roUrlEvent` return contract.
- Add guarded explicit JSON/status decoding; apply it to GraphQL, Helix, auth, and emote callers without changing boundary/raw task response contracts.
- Correct device-flow expiry/interval/error handling and ensure every validation task completes. Distinguish invalid credentials from indeterminate network results; avoid wiping user preferences on either temporary failure or account sign-out.
- Remove fork-specific default-enabled telemetry. Keep optional diagnostics only with explicit opt-in/configuration; avoid leaking signed playback URLs or credentials in logs.
- Upgrade compatible compiler/linter/formatter/test dependencies and use supported Node 24. Remove demonstrably unused package-manager scaffolding; declare tools used directly by scripts.
- Make package naming deterministic and fix Windows-compatible test deployment/console reporting. Test commands must fail on deployment, timeout, or suite failure instead of always exiting successfully.
- Add meaningful offline BrightScript fixtures and regression coverage; compile Rooibos tests separately from physical deployment.
- Make PR container builds read-only and unpublished. Publish only authorized main/tag events; remove the broad PR-close image cleanup. No image is published as an incidental local action.
- Replace the unmaintained README with current build, test, compatibility, service, and verification documentation. Keep developer credentials and private audit artifacts out of commits.

Security acceptance: update all available compatible patches and inspect the dependency graph. The current `braces` advisory has no published patched release; do not invent one, silently disable the audit, or downgrade unrelated tools via `audit fix --force`. Any remaining build-only exception must be narrow, documented, reviewed, and separated from runtime exposure.

### 5. Native interface modernization — Opus 5.5 xHigh

Owner: Claude Opus 5.5 using the local `frontend-design` skill, adapted to SceneGraph, TV viewing distance, and D-pad control. Skill: `C:/Users/Michael/.claude/plugins/marketplaces/claude-plugins-official/plugins/frontend-design/skills/frontend-design/SKILL.md`.

Complete the interrupted audit first and update this plan with its finished specification. Preserve Following, Browse, Search, channel/category pages, recent channels, login/account management, all settings, bookmarks, clips/VODs, playback controls, seeking, quality selection, chat/emotes, and proxy setup unless a feature is proven deprecated.

Starting concerns recovered from the partial audit: tiny player typography; poor contrast for some chat usernames; icon-only actions; unclear account status; loading/empty/error screens without recovery guidance; Back behavior in the recent-channel rail; and settings descriptions that conflate quality and latency. These are leads, not a completed design report.

Build a cohesive token system using existing bundled fonts and intentional focus/status colors, visible remote focus, TV-safe margins, readable text, clear account/proxy setup, and predictable focus restoration. Validate signed-out and signed-in navigation, every overlay, Back behavior, search keyboard, settings dialogs, retries, and repeated transitions. Preserve performance on older devices. Do not replace the native app with a web page.

Ownership: non-player scenes and navigation/modules/theme first. Parent finishes auth/telemetry changes to `heroScene` and LoginPage before Opus edits those files. Opus modernizes player overlays only after the playback agent releases those files. No concurrent editing of the same files.

Completion requires actual implementation, feature comparison, compilation/lint/format checks, and visual/remote review where simulation is available. A rate limit or incomplete report is recorded as incomplete, resumed after reset, and never counted as design completion.

## Deprecation and follow-up queue

The Jellyfin capability/profile scaffold was replaced by focused Roku decoder checks. The unused `PlayerTask`, SDK `player.bs` and its three external GraphQL files were removed after checking XML/runtime references; active playback queries remain in GetTwitchContent. Remove other orphan handlers or unused chat-send fields only with the same caller evidence. Preserve user-facing functions.

Investigate separately: deep links (`supports_input_launch` is declared but launch parameters are ignored), animated-emote performance, genuine audio-only listening, VOD chat replay if a maintainable API becomes available, broader captured fMP4 layouts, additional verified Twitch CDN hosts, locale completeness, and a future 1080p-native UI. These are worthwhile follow-ups but must not substitute for fixing current video/audio/chat usability.

## Validation and release gates

1. Offline: deterministic package, lint, formatting, compiler and test compilation; executed HLS/decoder/HTTP/auth/IRC fixtures; locked proxy lint/format/pytest; dependency audit adjudication; container health in CI.
2. Simulator: launch, browse/search/following, account/proxy settings, focus and Back, player/chat notices, error recovery and repeated open/close. No simulator is currently listening on the expected ports; set one up if feasible and clearly distinguish simulation from hardware.
3. Hardware: record model, OS, decoder/display capabilities and network. Verify native AVC live with sound; HEVC 1440p live with sound through the service; older-device AVC fallback; VOD sound, bookmark resume and seek; clips; quality changes; proxy down/up; anonymous and signed-in chat; chat hide/show/reconnect; unavailable-chat notices; complete remote navigation. Run several sustained streams and repeated transitions.
4. Latency: compare default and opt-in modes on the same broadcast, measuring stream delay, chat alignment, startup, stalls, live-edge recovery, and A/V sync. Report measured results and limits.
5. Independent review: ask Kimi K3 and Grok 4.7 to review the finished diff and this plan. Each round includes the original scope, previous findings, evidence and responses. Fix valid findings; record rejected findings with source or test evidence. Repeat until no valid blocking findings remain.
6. PR: make conventional, reviewable commits after mandatory formatting; create and link the PR. Keep it draft while design, checks, or hardware gates are incomplete. Wait for remote review/checks using the app's PR watcher; assess every finding, fix valid ones, update, and repeat. Do not merge without a user request.

## Progress log

- Core audits complete; baseline checks recorded. Grok's failed initial startup was retried successfully.
- Opus interface audit remains incomplete after another provider session limit; its next retry is October 7, 5:55 a.m. Eastern. Recovered source inspection, font-glyph checks and private fixture tooling will carry forward. Independent validation support is improving the local probes; native UI design and implementation remain assigned to Opus. The temporary daily timer will be disabled when its audit and UI implementation are actually complete.
- Playback, chat and explicit scene lifecycle implementations are released. HTTP/auth, opt-in diagnostics, Node 24 tooling, portable test deployment, workflows and build/use documentation are implemented.
- Proxy implementation is released: 183 tests pass on Python 3.12 and 3.14, ruff checks and wheel build pass, and the strict locked runtime dependency audit reports no known vulnerabilities. The hardened container builds and returns version 0.2.0 from `/health` in CI.
- Full-project format/check, lint, package and Rooibos compilation pass, along with seven offline suites and twelve Node regressions including actual playback recovery and SceneGraph navigation/disposal. A bounded anonymous Twitch request returned a native AVC TS ladder; it did not offer HEVC and does not verify audible sound or hardware decoding.
- Direct Python service startup and version 0.2.0 health response pass. All four updated workflows pass actionlint. The npm policy reports remaining build-only advisories explicitly.
- Full-app simulator launch uncovered a preexisting MenuBar crash from missing internal Button children; nil guards fixed it. The app now renders and exits normally in brs-node, but initial network-failure recovery and simulator layout limitations remain for Opus. Focused fixture success does not establish a working whole interface.
- Windows/Linux builds, both Python test/audit jobs and container health pass on `9054da7`; PR image publishing is intentionally skipped. Portable double-quoted formatter patterns now reject malformed source on Windows, and BrightScript line endings are consistent across platforms.
- Draft [PR #119](https://github.com/Narehood/Stitch-Revitalized-For-Roku/pull/119) is open and monitored. Grok 4.7 and Kimi K3 completed their core reviews without confirmed blockers. Small valid chat, buffering and root-exit findings are fixed for follow-up review, with malformed-frame, repeat-buffering and root-exit regressions. The unused buffering action and unreachable playback override were removed; the stall-count reset uses an explicit two-minute policy rather than a millisecond value compared with seconds. Kimi's suggested codec-level changes were rejected after checking FFmpeg's [H.264](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/h264_levels.c) and [H.265](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/h265_profile_level.c) level tables; the existing decoder calculations are correct at those boundaries.
- Interface completion, review of the final diff and physical device verification remain release gates.
