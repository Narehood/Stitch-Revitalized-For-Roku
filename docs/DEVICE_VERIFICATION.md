# Roku verification record

Status: device access available; acceptance testing in progress. On October 8, a fresh test package was installed on a G204X 58-inch Roku TV running OS 15.3.4 build 2303. Its unique run marker identified the new package and all 120 Rooibos tests passed. The production package installed and loaded anonymous live listings. Native playback testing exposed the request-key casing defect described below. A separately marked diagnostic package with the playback variable keys quoted reached live AVC/AAC playback; the user confirmed normal moving video and clear audible sound. Follow-up testing reproduced and corrected the Savix decoder rejection and TheBurntPeanut bundled-audio/Automatic selection failures; the user confirmed picture and sound on the sampled direct and direct-Python paths described below. Chat, 1440p, VOD, complete native UI, sustained playback and latency acceptance remain open. Offline fixtures, compiler checks and synthetic MP4 tests verify only their stated contracts.

## Device record

For each device, record model name/number, Roku OS, display resolution, network type, reported AVC/HEVC decoder capabilities, proxy version/configuration, package commit and date. Exclude credentials, signed playback URLs and account identifiers.

| Capability group | Actual device / OS | Status |
|---|---|---|
| Existing OS 15.1-compatible device, AVC fallback | G204X, 6Series-58 TV, OS 15.3.4 build 2303 | Installation and 120-test run passed; diagnostic live AVC/AAC picture and sound confirmed for one stream |
| HEVC-capable device, genuine 1440p broadcast | G204X reports HEVC main and main 10 at level 5.0 supported | Actual 1440p broadcast playback pending |
| Device exposing native secure WebSocket IRC | G204X creates a native WebSocket object | TLS handshake and live message delivery pending |

One device can cover several groups. Unrepresented groups stay pending. Preserve the OS minimum unless verified evidence justifies a documented change.

Initial production artifact: application source `c928797`, SHA256 `03a1b1a7491e7602ac214d799a60d45330d9724ea2e6f88ce910dc18e87f5d4d`. The packaged playback task matches the reviewed source. The TV reports a 1080p UI plane, which does not establish video decoder capability. Fresh native test run ID: `33fbec29-807b-4a53-96dc-451aa47f6b66`. Connection credentials, account data and raw console artifacts remain private.

The initial live request returned HTTP 200 with a GraphQL error that required `skipPlayToken` was missing. Roku lowercases unquoted associative-array literal keys; the desktop interpreter and desktop request controls preserved their case. The corrected native experiment changed only the playback variable key quoting and private diagnostic prints. Twitch then returned the token, the player advanced through buffering to playing, and ECP reported live HLS with AVC video and AAC audio without a debugger stop. The user confirmed moving picture and clear sound. This establishes the authorization correction and this one-stream result, not sustained playback, actual video resolution, 1440p or end-to-end latency. Quoted keys are also applied to the matching VOD variables and existing persisted-query envelopes; authenticated follow/unfollow operations have not been exercised.

Savix reproduction: the device rejected the source's declared AVC High 5.0 and also returned false for the lower Main 3.1/3.2 queries, suggesting supported levels 4.1/4.2. The exact-level filter therefore discarded every quality. The corrected helper validates a bounded level-only suggestion list, rechecks the same codec/profile at a capacity at least as high as the immutable stream requirement, and requires an explicit positive result. The source remains excluded; four lower MPEG-TS qualities are retained. A native diagnostic using the actual navigation/player path selected a lower rendition and reached the playing state. The user confirmed normal moving picture and clear audio. This does not lower a source's declared requirement or accept a codec/profile substitution. The five-file correction passed both requested independent reviews and Windows/Ubuntu CI. A subsequent guard rejects comma-joined level names before querying; its expanded fixture passes 251 assertions, and the prior helper is rejected by the new negative cases.

TheBurntPeanut reproduction: actual sampled initialization segments contain combined AAC audio and AVC video in one CMAF file, with no external audio group. A demux service separates these tracks without transcoding. The updated version 0.2.0 Python service passed the Roku's real finite health check during a temporary diagnostic configuration; no saved Proxy URL was changed. Automatic playback returned HTTP502 before any segment requests: the service refetched the master and could not find the client's previously selected URLs. Two otherwise identical fresh requests returned the same five rendition descriptions but no matching URL paths. A private explicit-quality experiment then bypassed that Automatic selection failure, served separate audio/video segments, and advanced native 1920x1080 playback with AAC. The user confirmed moving picture and clear audio. The coordinated client/service0.3.0 descriptor fix passes local regression checks. A fresh native Automatic run passes the real health check, moves from buffering to playing, advances position and receives separate audio/video init/media responses without the earlier failure. The user confirmed both moving picture and audio for Automatic. Actual adaptation under changing bandwidth, sustained playback and other devices remain unverified. Docker is optional; these tests use Python directly, which still runs separately from the Roku.

A private Task-local loopback HTTP prototype passed two freshly packaged native runs on this TV. The exchange run served the exact finite payload with HTTP200, acknowledged socket/transfer cleanup and rejected a new connection after closing. The stop-before-client run bound/listened, cooperatively cancelled with zero clients accepted, acknowledged cleanup and likewise rejected a new connection. Subsequent freshly marked Video packages played fixed separated fMP4 audio/video from the Roku-only loopback server with the external Python service stopped. The watched eight-second 1920x1080 replay served 13 assets (about 7.7 MB), completed normally with positive audio/video rendered positions and no Video error, acknowledged stopped/socket cleanup and rejected a newly constructed connection after closure. The user explicitly confirmed sharp moving picture and clear audio. A separate 284x160 active-stop run also passed cleanup. These samples were split before packaging: actual on-device conversion and live integration remain unverified. Back while playing, sustained CPU/memory behavior and other devices remain open. The canonical application was restored afterward and saved preferences were unchanged. The private prototype is not included in the release; removing the separate conversion process is not yet justified.

## Playback and audio

Record packaging, codec, resolution, frame rate and whether the service was used. Use public streams and legitimate signed-in access where required; never bypass access restrictions.

| Check | Expected behavior | Result / evidence |
|---|---|---|
| Ordinary AVC live, no proxy | Picture and audible audio; startup and sustained playback | Jynxzi/Savix sampled picture and audio confirmed; sustained acceptance pending |
| Bundled CMAF live through service | Separated video/audio; audible sound, A/V sync, no error 970 | TheBurntPeanut explicit1080p/Automatic picture and audio confirmed through direct Python0.3; sustained A/V acceptance pending |
| Genuine HEVC 1440p live | Offered only on capable device; picture and sound | Pending |
| Device unable to decode source quality | Compatible AVC options retained; clear failure if none exist | Pending |
| Auto / highest / lowest / manual quality | Correct options, audible audio, compatible adaptive ladder | Automatic/explicit1080p sampled; switching/adaptation and remaining choices pending |
| VOD start, seek and bookmark resume | Correct position, audible sound and A/V sync | Pending |
| Clips | Correct clip and audible sound; clear failure if unavailable | Pending |
| Proxy unavailable / restored | Bounded failure and recovery; direct compatible streams still work | Pending |
| Repeated quality changes and player open/close | No abandoned timers, tasks or connections | Pending |
| Sustained playback | Record duration, stalls, memory/task behavior and errors | Pending |

Proxy health proves reachability. Synthetic demux tests cannot establish decoder acceptance of a real stream.

## Chat, accounts and remote navigation

| Check | Expected behavior | Result / evidence |
|---|---|---|
| Anonymous live chat | Messages/emotes; readable status and bounded reconnect | Pending |
| Signed-in secure chat | Credentials used only by secure transport; correct account state | Pending |
| Older anonymous IRC fallback | No account token sent; usable chat | Pending |
| Hide/show, channel changes and network interruption | Correct channel, one active connection, no stale messages | Pending |
| VOD/clip chat button | Unavailable-chat notice; no recorded playback joined to live chat | Pending |
| Login pending / denied / expired / network error | Useful retry/browse options; no endless poll | Pending |
| Validation interruption and sign-out | Temporary failure preserves account; sign-out preserves preferences | Pending |
| All pages and recent rail | Visible D-pad focus, reliable Back and focus restoration | Pending |
| Settings, proxy entry, dialogs and player overlays | No trapped focus, clipped text or inaccessible actions | Pending |
| Child quality dialog Up/Down/OK/Back, then player Back | Correct option/index, Cancel and exit behavior; simulator key routing diverges | Pending |
| Recorded seek tap/hold/apply/cancel while playing and paused | One tap is ten seconds; held press accelerates after initial delay; prior play state restored | Pending |
| Account own-channel/Back and delayed sign-in failure | Correct live channel route; retained page/focus; late failure preserves menu focus | Pending |
| Archivo text, long strings, chat contrast and overscan | Readable at couch distance on lowest available device; no clipped targets or scrolling regression | Pending |
| Repeated permanent and back-stack transitions | Permanent scenes clean up; retained scenes remain reusable | Pending |

## Low-latency comparison

Use the same broadcast/device for default and experimental modes. Record actual segment duration and whether partial segments are advertised. A setting change or preserved LL-HLS tag is not a measured improvement.

Measure startup time, observable broadcast-to-display delay, chat alignment, stalls, rebuffering, live-edge recovery and A/V sync. Use a broadcaster clock or comparable visible cue where available. Repeat runs to distinguish stable improvement from network variation; record conditions and sample count.

| Mode | Startup | Display delay | Stalls / duration | Chat alignment / A/V sync | Evidence |
|---|---|---|---|---|---|
| Default | Pending | Pending | Pending | Pending | Pending |
| Experimental | Pending | Pending | Pending | Pending | Pending |

Keep the experiment off by default. If unreliable on a capability group, adjust or disable it there.

## Release decision

Complete the native UI, both requested independent reviews, CI and this record before describing the modernization as usable on tested hardware. Record untested device groups and limitations in the PR. Keep the PR draft while required checks are pending; do not merge automatically.
