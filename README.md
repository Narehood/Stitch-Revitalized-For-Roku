[![stars - Stitch-Revitalized-For-Roku](https://img.shields.io/github/stars/Narehood/Stitch-Revitalized-For-Roku?style=social)](https://github.com/Narehood/Stitch-Revitalized-For-Roku)
[![forks - Stitch-Revitalized-For-Roku](https://img.shields.io/github/forks/Narehood/Stitch-Revitalized-For-Roku?style=social)](https://github.com/Narehood/Stitch-Revitalized-For-Roku)
[![GitHub release](https://img.shields.io/github/release/Narehood/Stitch-Revitalized-For-Roku?include_prereleases=&sort=semver&color=blue)](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases/)
[![License](https://img.shields.io/badge/License-Unlicense-blue)](https://github.com/Narehood/Stitch-Revitalized-For-Roku/blob/main/LICENSE)
![Roku](https://img.shields.io/badge/roku-6f1ab1?style=for-the-badge&logo=roku&logoColor=white)
![Twitch](https://img.shields.io/badge/Twitch-9347FF?style=for-the-badge&logo=twitch&logoColor=white)

# Stitch Revitalized (for Roku)

Stitch Revitalized is a Roku channel that aims to provide an actively maintained, reasonably feature-complete Twitch experience while respecting Twitch's business model (ads, monetization, and the like). This channel is based on the now archived Stitch channel https://github.com/0xW1sKy/Stitch-For-Roku.

**v2.2 revitalization highlights**
- Playback gated on **video decode capability** (not UI graphics resolution), so 1440p-enabled channels remain watchable at lower qualities
- Live **low-latency** settings applied to the actual `StitchVideo` player path
- Centralized Twitch client helpers (`source/utils/twitchClient.brs`) for GQL/Usher/Helix headers and retries
- Refreshed channel art, splash screens, and in-app icons

## Side Loading

### Easy (release ZIP)

1. Download the latest release ZIP from [Releases](https://github.com/Narehood/Stitch-Revitalized-For-Roku/releases)
2. Enable Developer Mode on your Roku (Home ×3, Up ×2, Right, Left, Right, Left, Right)
3. Note the IP address and developer password shown on the Roku
4. In a browser, open `http://<ROKU_IP>` and upload the ZIP

### Manual compile (VS Code)

1. Clone this repository
2. Install Node.js, then from the repo root run `npm install`
3. Copy `bsconfig.json.example` to `bsconfig.json` and set your Roku IP + developer password
4. Install the BrightScript Language extension in VS Code
5. Enable Developer Mode on your Roku
6. Run **Run → Start Debugging**, or package with:

```bash
npm run package
```

The packaged channel ZIP is written under `out/`.

### Sideload validation checklist

After installing, confirm:

1. Device login (Twitch device code flow)
2. Discover / Following / Categories load
3. A live stream starts (try a 1440p-capable channel and force 720p/1080p)
4. Quality picker lists playable rungs only
5. Low Latency vs Normal latency setting changes player behavior
6. Chat opens and receives messages when enabled

## Playback notes (1440p & latency)

- Stream variants are filtered with `roDeviceInfo.CanDecodeVideo` height probes (`getMaxVideoDecodeHeight()`), **not** `GetSupportedGraphicsResolutions()`.
- Choosing a specific quality uses that media playlist alone, so an unplayable Source/1440p rung cannot poison forced 720p/1080p playback.
- Low latency requests Usher LL parameters and configures LL-HLS / buffering on live `StitchVideo` nodes when the firmware supports those fields.

## Twitch API health

This app uses Twitch GraphQL + Usher (unofficial Android TV / web client IDs). Those surfaces change without notice.

If browse or playback breaks:

1. Confirm login still completes (`getRendezvouzToken` / `getOauthToken`)
2. Confirm homepage / following GQL queries in `TwitchApiTask.bs` still return data
3. Confirm `GetTwitchContent` can fetch an Usher playlist for a live login
4. Update operation documents / persisted query hashes as needed — client IDs live in `source/utils/twitchClient.brs`

## Contributing

Report bugs or request features via [GitHub Issues](https://github.com/Narehood/Stitch-Revitalized-For-Roku/issues). Pull Requests are welcome. All contributions must be made [under the Unlicense](./LICENSE).

## Data Collection

I do not collect any data from this app, but Roku and Twitch may do so. If this is a concern you should read their policies on data collection. The data Roku collects may be in whole or in part accessible by myself, but I, nor anyone working with me or on my behalf will use this data for any purpose except for fixing bugs/errors if they are reported.

## Authorship and License

Stitch Revitalized exists because Twitch does not presently have any official channel for Roku. If Stitch becomes active or Twitch makes an official app, this project will no longer be maintained.

Stitch (and now Stitch Revitalized) began as a hard fork of [Twoku](https://github.com/worldreboot/twitch-reloaded-roku), due to that application's apparent abandonment. Since then Stitch has been almost completely rewritten.

Twoku was released without an explicit license, but, as a non-cleanroom rewrite, all subsequent contributions to Stitch are released [under the Unlicense](./LICENSE).

If license encumbrance is an issue for you, you can compare [the final upstream commit to this repository](https://github.com/0xW1sKy/Stitch-For-Roku/commit/268187c63e1eaf3922f577a2dab6ccb6a2e089f8) to see what code is unclearly licensed.

While removing any residual upstream code is not a priority for Stitch, Pull Requests replacing unclearly licensed code with unencumbered code are welcome.

Stitch Revitalized is released on a non-commercial basis and derives no revenue. If you work for Twitch, please feel free to use the license-unencumbered portions of this repository as the basis for an official Twitch app.
