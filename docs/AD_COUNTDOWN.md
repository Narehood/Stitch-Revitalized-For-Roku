# Ad countdown integration

Status: the parser and reusable corner badge are implemented and tested. They are not yet attached to playback. Actual cue delivery, a precise presented UTC clock and native behavior remain integration gates.

The badge shows the remaining time of the current ad, with its position in the pod when the source provides a count and position. It never guesses the duration of an entire ad pod. It stays inside the current video area, including beside chat, and does not take remote focus or control playback.

`twitchAdCountdownRanges` accepts bounded, observed Twitch stitched-ad DATERANGEs and retains only five numeric fields per cue: start, end, duration, pod count and pod position. Session identifiers, signed URLs and tracking attributes are not retained. Other metadata classes do not become ads. Duplicate cues are collapsed; conflicting intervals are rejected conservatively.

The `AdCountdown` component exports `beginContent`, `setCues`, `updatePresented`, `clear` and `onDestroy`. The host supplies a local current-content owner, the sanitized cue array, localized labels and the video-area width. It must pass UTC microseconds from the actual presented media, including the frozen frame during pause or buffering. Invalid/missing clocks, terminal states, stale owners and disposal hide the badge. The component has no clock extrapolation, network task or timer.

The existing Roku-only live protocol currently omits source program dates and ad cues. Native diagnostics returned relative rendered positions with no usable UTC offset. Those positions cannot be interpreted as current wall time. A source-to-player adapter must preserve verified timing and ownership before the badge can be enabled; native countdown, pause, buffering, replacement and cleanup then require fresh verification.

Portable regressions execute the actual BrightScript parser and SceneGraph component, including rendered labels, fractional countdowns, cue numbering, bounded layout, ownership, pause/buffer inputs and permanent disposal. Genuine normally exiting mutations and child timeout/output/crash controls are rejected. These checks establish the stated component contracts, not native ad delivery or a working TV countdown.
