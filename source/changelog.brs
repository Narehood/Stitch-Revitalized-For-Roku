' Changelog entries keyed by version string ("major.minor.build").
' Add a new entry here with every release.
' Versions are displayed in ascending order; multiple versions are shown when the user skipped an update.
function getChangelog() as object
    return {
        "3.0.1": [
            "3.0.0 Alpha 2: Eligible recorded videos can now offer Try on Roku without a container",
            "New: A corner ad countdown uses reliable Twitch cues and actual playback timing",
            "Improved: Buffered ad timing history and continued polling when timing is unavailable",
            "Improved: Live recovery budgets and eligible manual quality selection",
            "Unsupported media can still use the optional audio service",
            "Long-session stability, real-ad readability, Roku-only VOD audio/video and genuine 1440p still need verification",
            "Source transitions remain disabled; lower live latency is experimental and off by default"
        ],
        "3.0.0": [
            "3.0.0 Alpha 1: An early preview; some streams and devices still need testing",
            "New: Twitch-inspired design, clearer focus, and named video controls",
            "Improved: Stream quality selection, recovery, and live chat connections",
            "Experimental: Try on Roku offers live playback without a separate computer",
            "Chat: Recorded videos show a notice when chat is unavailable",
            "Privacy: Diagnostics are off unless you opt in",
            "Lower live latency is experimental and off by default; improvement is not yet measured"
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
            "New: Donate via Buy Me a Coffee — find the QR code in Settings",
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
