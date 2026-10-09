# Stitch Revitalized for Roku

Stitch is a community Twitch viewer built with BrightScript and Roku SceneGraph. It includes Following, Browse, Search, channel and category pages, recent channels, live streams, VODs, clips, bookmarks, quality selection, chat and emotes.

The planned modernization release is **3.0.0 Alpha 1**. The Twitch-inspired native interface is implemented, and bounded Roku-only picture/audio and anonymous chat tests pass on the test TV. The [plan](docs/MODERNIZATION_PLAN.md) and [device verification record](docs/DEVICE_VERIFICATION.md) distinguish those results from remaining 1440p, VOD, broader-device, native UI and latency acceptance. Further Kimi/Grok review rounds are deferred at the maintainer's request.

This checkout incorporates work from [jeremy-albinet's maintained fork](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku). Existing contributions and licensing remain intact.

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

Some Enhanced Broadcasting streams combine audio and video in CMAF fragments. Eligible clear AVC/AAC live streams offer **Try on Roku**, an opt-in experimental splitter that runs on the Roku without another computer or container. This path has bounded full-app picture/audio confirmation on one TV; broader source/device and long-term acceptance remain open. The optional demux service below remains available as a fallback. Ordinary compatible streams play directly. Twitch controls which renditions are available, and its playback interfaces can change independently of Stitch.

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
