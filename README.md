# Stitch Revitalized for Roku

Stitch is a community Twitch viewer built with BrightScript and Roku SceneGraph. It includes Following, Browse, Search, channel and category pages, recent channels, live streams, VODs, clips, bookmarks, quality selection, chat and emotes.

**[3.0.0 Alpha 1](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases/tag/v3.0.0-alpha.1)** is the first preview of the modernization. Download `Stitch-Revitalized-For-Roku.zip` from its release assets to sideload the channel on a developer-mode Roku. Alpha 1 is a prerelease: compatibility and longer playback sessions still need testing.

**[Download the latest preview ZIP](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases/download/v3.0.0-alpha.1/Stitch-Revitalized-For-Roku.zip).** GitHub's “Latest” badge links to the last stable release; Alpha 1 is listed as a prerelease on the [Releases page](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases).

This checkout incorporates work from [jeremy-albinet's maintained fork](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku). Existing contributions and licensing remain intact.

## What's new in 3.0.0 Alpha 1

- **Twitch-inspired native interface:** dark surfaces, purple focus indicators, redesigned navigation and content cards, clearer connection/loading/error states, current-value Settings, and updated player controls. Existing browsing, account, bookmarks, quality, chat and emote features are retained.
- **Live playback without a container:** ordinary compatible streams play directly. Eligible Enhanced Broadcasting live streams can split audio/video on the Roku itself through **Try on Roku**, without Docker or a separate computer. This experimental option is selected explicitly for an eligible stream.
- **1440p stream support:** corrected HEVC negotiation, level checks and quality filtering support 1440p, including 60 fps, when the device can decode the offered format. Compatible lower AVC qualities remain available. Genuine 1440p hardware playback verification is still pending; bundled HEVC media can require the optional service.
- **Playback and audio repairs:** corrected native Twitch request formatting, decoder filtering and quality selection. Eligible manual qualities stay available beside direct Automatic playback, recovery avoids jumping from Automatic to the highest bitrate, and repeated quality changes are delivered. Live and compatible recorded playback have picture/audio confirmation on a physical Roku.
- **Clearer chat:** live connection status, bounded reconnection, improved text contrast and preserved emote support. Opening chat for a VOD or clip shows an unavailable-chat notice. Anonymous full-player live chat has been confirmed readable on the TV; secure/signed-in and longer-session coverage remain open.
- **Maintained tooling and defaults:** updated Node/Python dependencies and Windows/Linux CI, explicit observer/task cleanup, optional diagnostics off by default, and experimental lower latency off by default.

## Known Alpha 1 limitations

The on-device audio/video splitter currently supports eligible **live AVC/AAC** streams. Some VODs combine their tracks in CMAF and still show **Audio service needed**: those recordings need the optional Python service below. Docker is optional even for that service. Extending Roku-only splitting to recorded playback is follow-up work; Alpha 1 does not claim container-free playback of every VOD or stream format.

A live session was observed to rebuffer and stop after about twelve minutes; **Try again** restarted it. Its cause is still under investigation. Wider source/device compatibility, sustained stability, VOD seek/bookmark behavior, native recorded-chat notice navigation and measured low latency remain under verification. Keep the optional service available if a format is unsupported on-device, and see the [verification record](docs/DEVICE_VERIFICATION.md) and [follow-up work](TODO.md) for current coverage.

## Build

Use Node.js 24 and npm:

```sh
npm ci
npm run lint
npm run fmt:check
npm test
npm run test:compile
npm run package
```

The channel package is `out/Stitch-Revitalized-For-Roku.zip`. `npm test` executes offline BrightScript fixtures and Node tooling regressions. `test:compile` packages the separate Rooibos device tests; it does not deploy them. CI runs these checks on Windows and Linux.

For development, `npm run build` compiles without a package and `npm run watch` watches source changes. Run `npm run fmt` and `npm run fmt:check` before committing. Keep device credentials outside tracked files; `bsconfig.json.example` shows a local development override.

## Device compatibility and playback

The existing manifest minimum remains Roku OS 15.1 with an HD SceneGraph layout. Video selection uses decoder capabilities rather than UI resolution. A device must support the stream's codec, profile, level and dimensions to receive that quality; 1440p is not enabled indiscriminately on every Roku. Unsupported qualities are filtered, with compatible AVC alternatives retained when Twitch supplies them.

Some Enhanced Broadcasting streams combine audio and video in CMAF fragments. Eligible clear AVC/AAC live streams offer **Try on Roku**, an opt-in experimental splitter that runs on the Roku without another computer or container. Its Automatic mode selects one offered quality, preferring at most 720p; use manual quality selection for higher supported qualities. It has bounded full-app picture/audio confirmation on one TV; broader source/device and long-term acceptance remain open. The optional demux service below remains available for unsupported bundled media, including some VODs. Ordinary compatible streams and VODs play directly. Twitch controls which renditions are available, and its playback interfaces can change independently of Stitch.

Live chat uses secure WebSocket IRC when that component is available on the device. Older devices retain anonymous IRC chat without sending account credentials over its plaintext connection. Chat has bounded reconnection and visible connection status. VODs and clips show an unavailable-chat notice when chat is opened.

**Lower live latency** is an opt-in experiment in Settings. It may increase buffering. It does not promise a specific delay or native LL-HLS support; measured comparison on real devices is a release gate.

## Optional audio demux service

**Docker is optional.** The Python service separates bundled audio and video without transcoding. It preserves stream quality but cannot add codec support to a Roku.

With Python 3.12+ and uv installed, run from `fmp4-demux-proxy`:

```sh
uv sync --locked --no-dev
uv run --locked python -m fmp4_demux_proxy
```

In Stitch Settings, set **Proxy URL** to the computer's Roku-reachable address, such as `http://192.168.1.50:8080`. Check `/health` at that address. The computer must stay running for streams using the service. Leave Proxy URL empty to disable it.

For Docker, configuration, host policy, limitations and tests, see the [service README](fmp4-demux-proxy/README.md). Container build and health checks run in CI; PR builds do not publish images.

## Simulator and device tests

The default interactive target is a local BrightScript simulator. The test deployer expects its sideload endpoint on port 8888 and debug console on port 8085:

```sh
npm run test:device
```

Physical testing requires developer mode and explicit device access. Set `ROKU_HOST` and `ROKU_PASSWORD` privately in the shell, then run `npm run test:device`. Physical sideloading defaults to port 80. `ROKU_SIDELOAD_PORT`, `ROKU_CONSOLE_PORT`, and `ROKU_TEST_TIMEOUT_MS` can override endpoints and the test deadline. The deployer rejects failed installation, stale console output, failed tests, crashes and timeouts.

A simulator verifies code and navigation; it does not establish Roku hardware decoding, audio, secure chat transport or measured latency. Use the [device verification matrix](docs/DEVICE_VERIFICATION.md) for those checks.

## Diagnostics and security

Optional diagnostics are off by default and require fresh user consent plus an explicitly configured HTTPS endpoint. No fork-specific endpoint or key is bundled. Account sign-out preserves preferences and the independent anonymous device identity. Credentials and signed playback URLs must not be included in logs or issue reports.

`npm run audit` applies the documented [dependency policy](docs/SECURITY.md). A temporary, exact build-tool exception remains for an advisory with no published patch; the command does not claim a clean dependency graph. Python runtime dependencies are checked separately in proxy CI.

See [TODO.md](TODO.md) for deferred work and [LICENSE](LICENSE) for licensing.
