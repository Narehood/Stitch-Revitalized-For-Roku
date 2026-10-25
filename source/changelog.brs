' Changelog entries keyed by version string ("major.minor.build").
' Add a new entry here with every release.
' Versions are displayed in ascending order; multiple versions are shown when the user skipped an update.
function getChangelog() as object
    return {
        "3.0.9": [
            "3.0.7 release (Roku package version 3.0.9)",
            "New: Pin streamers with Options; pinned channels stay first in the left rail",
            "Pins: Author badges and emotes refresh independently of chat sync",
            "New: Save a preferred startup resolution with a lower-quality fallback",
            "New: Choose chat timing: Match video or Live",
            "Fix: Chat shows when it is waiting or syncing, and stays stopped while hidden",
            "Fix: Unicode emoji and BTTV/7TV images, including recent-channel emotes",
            "New: Animate one visible BTTV or 7TV emote at a time on compatible Roku devices",
            "New: Twitch subscriber GIF attachments with readable title fallbacks",
            "New: Translucent chat over full-size video with four corner positions",
            "Fix: Pinned emotes, mention highlighting and invisible chat characters",
            "Improved: Settings scroll indicators and player controls dismissal hints",
            "Fix: Channel live thumbnails, player viewer counts and recent-avatar focus alignment",
            "Fix: Playback recovery allows startup time and cancels retries after playback resumes",
            "Fix: Lower live latency refreshes advancing short segments more frequently",
            "Fix: Stale playlists cannot rewind the Roku-only media window",
            "Fix: Backward live timeline changes no longer trigger a false stall",
            "Fix: Settings opens on the saved choice and honors Audio Splitter Off",
            "Improved: Clear connection and upgrade messages for the optional audio service",
            "Fix: Sign-out request safety and optional diagnostics startup delivery",
            "Retains the redesigned interface and experimental feature defaults"
        ],
        "3.0.8": [
            "3.0.6 release (Roku package version 3.0.8)",
            "New: Subscription, gift, raid, Bits and reward notices in live chat",
            "Experimental: Signed-in Twitch watch credit for live streams",
            "Experimental: Hype Train banners and pinned messages above live chat",
            "Pins: Press Down with player controls hidden to read the full message",
            "Enable watch credit, Hype Trains and pins separately in Settings; all three default to off",
            "Watch streaks and annual recap credit remain unverified"
        ],
        "3.0.7": [
            "3.0.5 release (Roku package version 3.0.7)",
            "Maintenance: Updated build tools and optional audio service dependencies",
            "No intended playback or interface changes from 3.0.4"
        ],
        "3.0.6": [
            "3.0.4 release (Roku package version 3.0.6)",
            "Fix: Roku Back closes the player quality menu",
            "Fix: Channel selection, live cards, loading and Retry focus",
            "Fix: Account changes, chat deletions and long title scrolling",
            "Fix: Signed-in VOD playback waits briefly for saved bookmarks",
            "Improved: Recovery from temporary live stream errors",
            "Improved: Shorter Roku-only low-latency window; experimental and off by default"
        ],
        "3.0.5": [
            "3.0.3 release (Roku package version 3.0.5)",
            "Maintenance: Updated build and test tooling",
            "No playback or interface changes from 3.0.2"
        ],
        "3.0.4": [
            "3.0.2 release (Roku package version 3.0.4)",
            "Improved: Ad timing is preserved across supported Roku-only stream transitions",
            "Improved: Lower live latency counts stream processing time toward its next playlist refresh",
            "Updated: Upstream donation prompts are removed and What's New links to this project's issues",
            "Lower live latency stays experimental and off by default"
        ],
        "3.0.3": [
            "3.0.1 release (Roku package version 3.0.3)",
            "New: Lower live latency now reduces delay using the Roku itself, without another computer",
            "Measured on one TV: direct playback about 8-11 seconds behind live, down from about 21",
            "Improved: Relay fallback, recovery, quality changes and stream switching",
            "Fix: Sign-in is kept when Twitch issues a non-expiring token",
            "Lower live latency stays experimental and off by default; slower networks may buffer more"
        ],
        "3.0.2": [
            "3.0.0 release (Roku shows version 3.0.2 because 3.0.0 and 3.0.1 were alpha previews)",
            "New: Twitch-inspired design with clearer focus, status messages and named player controls",
            "New: Combined-audio streams and eligible recordings play on this Roku automatically, with no extra computer",
            "New: A corner countdown shows Twitch ad timing when it is available",
            "Improved: Ad breaks no longer end Roku-only playback; it can pause briefly and reconnects after about ten seconds",
            "Improved: Faster stream processing, no early freeze, and automatic recovery from network hiccups",
            "Improved: Quality selection, 1440p on capable devices, and live chat reliability",
            "Note: Roku-only streams run further behind live than direct playback; lower latency is experimental and off"
        ],
        "2.6.0": [
            "New: Recently Watched sidebar now shows a live indicator — a red dot appears on streamers who are currently live",
            "Improved: Top bar and left sidebar are now smaller, giving more screen space to content",
            "Improved: Stream category and streamer name are now on the same line in stream cards"
        ],
        "2.5.1": [
            "Fix: Streams no longer buffer every 30-40 seconds after the v2.5 latency update",
            "Fix: Removed the brief spinner flash that appeared right after a stream started",
            "Improved: Smarter live-edge correction — skipped when the stream already starts near the live edge"
        ],
        "2.5.0": [
            "Experimental: Lower live latency is available in Settings; it is off by default and improvement remains unmeasured",
            "Fix: Focus highlight now visible on channel pages and all grid views",
            "Fix: Error tracking now includes more detail to help diagnose crashes faster"
        ],
        "2.4.0": [
            "New: Following + Browse — simpler 2-tab layout (was 4 tabs)",
            "New: Recently Watched sidebar — quickly rejoin streams you've been to",
            "New: Sign in with a QR code — scan with your phone instead of typing the device code",
            "New: Search tab in the top menu — dedicated destination for finding channels and games",
            "New: Streams now auto-reconnect after ad breaks instead of freezing",
            "New: Settings → Log Out",
            "New: Optional diagnostics in Settings; now off by default until you opt in",
            "Fix: Chat connection now closes properly when leaving a stream",
            "Fix: Several crashes on scene transitions and network failures"
        ]
    }
end function

' Returns a sorted list of version strings present in the changelog AA,
' ordered from oldest to newest (ascending semver).
function getSortedChangelogVersions(changelog as object) as object
    versions = []
    for each v in changelog
        versions.push(v)
    end for

    ' Bubble sort ascending by semver
    n = versions.count()
    for i = 0 to n - 2
        for j = 0 to n - 2 - i
            if compareVersions(versions[j], versions[j + 1]) > 0
                tmp = versions[j]
                versions[j] = versions[j + 1]
                versions[j + 1] = tmp
            end if
        end for
    end for

    return versions
end function

' Returns -1 / 0 / 1 for a < b / a = b / a > b.
function compareVersions(a as string, b as string) as integer
    pa = parseVersion(a)
    pb = parseVersion(b)
    if pa.major <> pb.major then return sgn(pa.major - pb.major)
    if pa.minor <> pb.minor then return sgn(pa.minor - pb.minor)
    if pa.build <> pb.build then return sgn(pa.build - pb.build)
    return 0
end function

function parseVersion(v as string) as object
    parts = v.tokenize(".")
    major = 0
    minor = 0
    build = 0
    if parts.count() > 0 then major = parts[0].toInt()
    if parts.count() > 1 then minor = parts[1].toInt()
    if parts.count() > 2 then build = parts[2].toInt()
    return { major: major, minor: minor, build: build }
end function
