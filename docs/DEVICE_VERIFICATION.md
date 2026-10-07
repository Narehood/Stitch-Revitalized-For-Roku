# Roku verification record

Status: pending device access. No physical Roku was deployed to or tested during the initial audit. Offline fixtures, compiler checks and synthetic MP4 tests verify only their stated contracts. Do not mark hardware checks passed using those results.

## Device record

For each device, record model name/number, Roku OS, display resolution, network type, reported AVC/HEVC decoder capabilities, proxy version/configuration, package commit and date. Exclude credentials, signed playback URLs and account identifiers.

| Capability group | Actual device / OS | Status |
|---|---|---|
| Existing OS 15.1-compatible device, AVC fallback | Awaiting device details | Pending |
| HEVC-capable device, genuine 1440p broadcast | Awaiting device details and broadcast | Pending |
| Device exposing native secure WebSocket IRC | Awaiting device details | Pending |

One device can cover several groups. Unrepresented groups stay pending. Preserve the OS minimum unless verified evidence justifies a documented change.

## Playback and audio

Record packaging, codec, resolution, frame rate and whether the service was used. Use public streams and legitimate signed-in access where required; never bypass access restrictions.

| Check | Expected behavior | Result / evidence |
|---|---|---|
| Ordinary AVC live, no proxy | Picture and audible audio; startup and sustained playback | Pending |
| Bundled CMAF live through service | Separated video/audio; audible sound, A/V sync, no error 970 | Pending |
| Genuine HEVC 1440p live | Offered only on capable device; picture and sound | Pending |
| Device unable to decode source quality | Compatible AVC options retained; clear failure if none exist | Pending |
| Auto / highest / lowest / manual quality | Correct options, audible audio, compatible adaptive ladder | Pending |
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
