# Stitch Revitalized for Roku

Stitch is a community Twitch viewer built with BrightScript and Roku SceneGraph. It includes Following, Browse, Search, channel and category pages, recent channels, live streams, VODs, clips, bookmarks, quality selection, chat and emotes.

**[3.1.0](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases/tag/v3.1.0)** adds pinned streamers, preferred startup resolutions, richer chat and player channel actions, and reconciles community fixes for playback, Settings and the optional audio service while retaining the redesigned interface. Download `Stitch-Revitalized-For-Roku.zip` from its release assets to sideload the channel on a developer-mode Roku running OS 15.1 or later. Roku reports the package as version 3.1.0.

**[Download the 3.1.0 ZIP](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases/download/v3.1.0/Stitch-Revitalized-For-Roku.zip).** Earlier releases, including the 3.0.0 Alpha previews, remain on the [Releases page](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases).

This checkout incorporates work from [jeremy-albinet's maintained fork](https://github.com/jeremy-albinet/Stitch-Revitalized-For-Roku). Existing contributions and licensing remain intact.

## What's new in 3.1.0

- **Pinned streamers:** press **Options** on a sidebar streamer or their channel page, or use **Channel actions** in the player, to pin or unpin them. The sidebar separates **Pinned** channels from **Live** recent channels, with labels outside the avatars. **Remove from sidebar** clears an individual channel's local pin and history without changing Twitch follows. Watching it again can add it back to recent history. Each profile, including anonymous viewing, keeps its own pins.
- **Player channel actions:** open the streamer's channel to browse VODs and clips, pin or unpin them, or check Follow/Unfollow status. Opening a channel waits for playback cleanup; pinning keeps the stream playing.
- **Startup quality:** choose a preferred resolution in **Settings → Video quality**. Stitch selects the closest lower supported resolution if that choice is unavailable, or the lowest available when none is lower. Automatic, Highest and Lowest remain available.
- **Chat timing:** **Match video** keeps messages synchronized with playback; **Live (no added delay)** displays new messages as they arrive. Chat shows when it is waiting or syncing, and hidden chat stops its chat and emote workers.
- **Chat layout:** Keep chat beside the video or choose **Over video** in Settings to retain full-size video. Choose a corner and background opacity; chat text and emotes remain opaque. Settings shows your position in scrollable lists, and player controls show how to hide them.
- **Chat emotes:** Unicode emoji use image runs, including combined sequences. User mentions are highlighted, and invisible formatting joiners no longer draw missing-glyph boxes. **Animate chat emotes** enables one visible BTTV or 7TV animation at a time on compatible Roku devices; other emotes keep their static images. Unsupported devices and failed emote animations retain static fallbacks. Twitch subscriber GIF attachments share the one-visible-animation limit and keep their supplied title when motion is disabled, unavailable or outside the supported resource limits. Channel IDs survive recent-channel launches, and failed images have readable fallbacks.
- **Live playback:** the opt-in lower-latency splitter refreshes advancing short fragments more frequently, rejects stale windows and retries timed-out transfers consistently. Recovery allows a separate startup interval and cancels obsolete retries when playback resumes. Backward timeline corrections reset stall tracking while recovery limits still require sustained forward progress. These changes do not guarantee a particular delay relative to mobile or desktop.
- **Live details:** channel pages restore missing live thumbnails, live player controls show a viewer-count snapshot, and the recent-channel focus ring is centered around its avatar.
- **Settings:** choice lists open on the saved value, and a saved **Audio Splitter Off** preference is honored. New installations retain the existing On default.
- **Optional audio service:** the channel verifies selected-master support before starting service playback and distinguishes connection failures from required upgrades. CloudFront hosts retain URL, DNS and redirect checks. Mixed MPEG-TS ads inside separated CMAF remain unsupported; native TS playback is preserved.
- **Proxy container:** version 0.3.2 pins an updated Debian 13/Python base, refreshes CA certificates and verifies the patched Debian package and active trust store during image build and container CI. The checks reject emSign ECC Root CA - G3 and AAA Certificate Services; other emSign roots remain accepted.
- **Account requests and diagnostics:** credentials are read once per request, startup diagnostics are delivered when opted in, and successful identification is deduplicated within the session.

### Also included from 3.0.6

- **Live chat events:** subscription/resubscription, gifted-sub and raid notices now appear with Twitch's system text and optional viewer message. Bits and Channel Points reward messages show their context while preserving text, emotes and moderation.
- **Twitch watch credit:** an opt-in experiment reports actual signed-in live viewing. Pauses, stalls and seeks add no watch time. Pokémon reward progress advanced in a bounded Roku test; other campaigns, watch streaks, Channel Points and annual recap credit remain unverified.
- **Hype Trains in chat:** an optional banner shows the current level, progress and remaining time. It works without signing in.
- **Pinned messages in chat:** an optional panel shows the current moderator pin and author. Press **Down** with player controls hidden to read the full text, then **Back** or **Continue watching** to close it. Provider emotes, Unicode emoji and mentions use the same renderer as ordinary chat in both the preview and full message. Updates can take about 15 seconds.
- **Recovery:** temporary validation failures retry without ending public chat polling. Earned minutes survive failed pre-submit checks and pauses, and unrelated metadata failures preserve a fresh pin.

Enable **Twitch watch credit**, **Hype Trains in chat** and **Pinned messages in chat** separately in Settings, then reopen a live stream. All three default to off. The viewer interfaces are undocumented and can change independently of Stitch. See the [watch-credit and chat-event notes](docs/TWITCH_WATCH_CREDIT.md) for evidence and limitations.

### Also included from 3.0.5

- **Build and test tools:** BrighterScript 0.73.8, bslint 0.8.47, brs-node 2.6.2 and commitlint 21.2.4. The simulator now handles numeric byte reads correctly without the old fixture workaround.
- **Optional audio service:** aiohttp 3.14.5 and refreshed Python dependencies, with uv 0.13.5 used in CI and Docker.
- **Dependency audits:** a scoped patched-Zod override is covered by an actual image-rendering regression. The withdrawn braces advisory's temporary exception is removed; the npm policy now grants no exceptions.
- **Channel behavior:** no intended playback, interface or settings changes from 3.0.4. Lower live latency remains experimental and off by default.

### Also included from 3.0.4

- **Player menus and navigation:** Roku Back closes the quality picker, channel selections preserve the correct playback intent, and Live now cards show the current stream title, viewers and category. Browse row sizing and automatic Retry focus are repaired.
- **Accounts and API responses:** late account lookups cannot restore old avatars, and failed requests stay distinct from valid empty results.
- **Chat and titles:** moderator deletions and purges also remove queued messages, and long titles scroll without blocking the interface.
- **VOD bookmarks:** signed-in recordings wait briefly for saved bookmarks, with bounded fallback and no late restart.
- **Live playback:** selected temporary upstream failures can reconnect through bounded recovery. The opt-in Roku-only low-latency window is shorter and requests its complete available startup window. Lower latency remains experimental and off by default; the adjusted startup request still needs native verification.
- **Release validation:** channel releases now run the full checks before publishing their package, and proxy publication requires Python validation and container health checks.

### Also included from 3.0.3

- **Toolchain maintenance:** builds use BrighterScript 0.73.6 and brighterscript-formatter 1.8.4, and offline tests run on brs-node 2.6.1. Playback, interface and settings are unchanged from 3.0.2.

### Also included from 3.0.2

- **Ad timing across stream transitions:** supported Roku-only playback retains verified timestamps and ad cues on both tracks across accepted segment changes. Ambiguous optional timing falls back to ordinary playback. Seamless ad transitions and wider device coverage remain under verification.
- **Opt-in playlist refreshes:** processing time now counts toward the next source reload, with source-derived refresh intervals and existing resource limits preserved. A further reduction in displayed delay is still being measured.
- **Donation prompts removed:** the upstream support row and QR image are gone; What's New points directly to this project's GitHub issues page.

Playback-speed catch-up remains separate research and is not enabled in this release.

### Also included from 3.0.1

- **Lower live latency without another computer:** the opt-in setting now serves trimmed live playlists from the Roku while media downloads directly from Twitch. On one Roku TV, direct playback measured about 8–11 seconds behind live rather than about 21; Roku-only streams measured about 16–17 rather than about 25. It remains experimental and off by default, with ad breaks, slower networks and wider devices still under verification.
- **Playback and sign-in follow-ups:** relay failures fall back to the direct source, transient failures can retry, and stream/quality changes retain bounded recovery. Sign-in is preserved when Twitch reports a non-expiring token.

The release also retains the 3.0.0 modernization:

- **Playback without Docker or another computer:** compatible streams play directly. Twitch Enhanced Broadcasting streams, which combine audio and video, are split on the Roku itself and now start automatically when no optional audio service is configured. Eligible completed recordings use the same on-device path, with seek, pause and resume.
- **Ad breaks no longer end Roku-only playback:** the on-Roku server carries ad and encoder-restart segments forward instead of refusing them. Roku's player can still pause briefly at the start and end of an ad; Stitch reconnects automatically after about ten seconds. A corner countdown shows reliable Twitch ad timing when it is available.
- **Steadier playback:** no freeze about 20 seconds into a stream, much faster on-device stream processing, a retry for stalled downloads, and automatic reconnection that recovers repeatedly over long sessions.
- **Twitch-inspired native interface:** dark surfaces, purple focus, redesigned navigation and cards, clearer loading and error states, current-value Settings, and named player controls. Browsing, account, bookmarks, quality, chat and emote features are retained.
- **Quality and 1440p:** decoder-aware quality filtering, corrected HEVC negotiation and Twitch request formatting, and manual qualities that stay available. 1440p, including 60 fps, is offered when the device can decode it.
- **Clearer chat:** live connection status, bounded reconnection, readable name colors and preserved emotes. VODs and clips explain that chat replay is unavailable.
- **Maintained tooling:** current Node/Python dependencies, Windows and Linux CI, a patched decoder dependency, explicit cleanup of tasks and observers, and diagnostics and experimental lower latency off by default.

## Known limitations

- **Watch credit and chat banners:** the three engagement settings remain experimental and off by default. Watch streaks and annual recap inclusion are unverified; the native reward result does not establish every Drops campaign or device. Pins currently display text, with polling delays.
- **Ad transitions on Roku-only live streams:** at the start and end of an ad, Roku's player can briefly stop and Stitch reconnects automatically after about ten seconds. Making these transitions seamless is the next planned improvement.
- **Delay behind live:** measured on one Roku TV, direct playback runs about 21 seconds behind Twitch's broadcast timestamps and Roku-only streams about 25 seconds. The opt-in **Lower live latency** setting brings these to about 8–11 and 16–17 seconds.
- **Formats:** the on-device splitter supports clear AVC/AAC media within its resource bounds. Bundled HEVC and other unsupported recordings or layouts can still require the optional Python service below; Docker is optional for that service.
- **Still under verification:** genuine 1440p hardware playback, signed-in secure chat, lower latency across ad breaks and slower connections, and wider device coverage. See the [verification record](docs/DEVICE_VERIFICATION.md) and [follow-up work](TODO.md).

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

Some Enhanced Broadcasting streams and completed recordings combine audio and video in CMAF fragments. Eligible clear AVC/AAC sources start an experimental splitter that runs on the Roku without another computer or container; a configured audio service takes precedence. For live playback, Automatic selects one offered quality, preferring at most 720p; use manual quality selection for higher supported qualities. Roku-only live playback has bounded full-app picture/audio confirmation on one TV; the new VOD path still needs human confirmation. Broader source/device and long-term acceptance remain open. The optional demux service below remains available for unsupported bundled media. Ordinary compatible streams and VODs play directly. Twitch controls which renditions are available, and its playback interfaces can change independently of Stitch.

Live chat uses secure WebSocket IRC when that component is available on the device. Older devices retain anonymous IRC chat without sending account credentials over its plaintext connection. Chat has bounded reconnection and visible connection status. **Settings → Chat timing** defaults to **Match video**; **Live (no added delay)** can reveal reactions before the video. Opening chat starts a new connection without message history, so quiet channels can still take time to show their first message. VODs and clips show an unavailable-chat notice when chat is opened.

**Lower live latency** is an opt-in experiment in Settings. Roku's player has no low-latency mode: it starts about 18 seconds before the end of Twitch's playlist and ignores requested start positions. With the setting on, Stitch serves the player a copy of the playlist trimmed to its newest segments from the Roku itself; video still downloads directly from Twitch. On a G204X this measured about 8–11 seconds behind Twitch instead of about 21, and about 16–17 seconds instead of about 25 for Roku-only streams. The smaller buffer can pause more often on slow connections. Twitch's low-latency prefetch segments are not used: on Roku they delayed startup and pushed Automatic quality to its lowest rendition.

The **Built-in Enhanced Broadcasting Splitter** setting defaults to On for new installations. An existing Off preference is preserved. Changes take effect when opening a stream; a configured external service still takes precedence.

## Optional audio demux service

Use service version 0.3.0 or a compatible selected-master protocol. Settings and playback distinguish older services that need an update from connection or invalid-health failures. Clearing the service URL restores eligible direct/on-device playback.

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
