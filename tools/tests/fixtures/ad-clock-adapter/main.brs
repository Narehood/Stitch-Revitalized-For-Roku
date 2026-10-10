sub main()
    m.assertions = 0
    m.failures = 0
    print "STITCH_AD_CLOCK_BEGIN: __MARKER__"
    testNativeArithmetic()
    testSourceProjection()
    testBoundaries()
    testHeaders()
    testSourceEpochAgreement()
    print "STITCH_AD_CLOCK_END: __MARKER__ "; FormatJson({assertions: m.assertions, failures: m.failures})
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_AD_CLOCK_FAIL: __MARKER__ " + message
    end if
end sub

sub testNativeArithmetic()
    values = [1767225600#, 1767225600.125#, 1767225600.999999#, 1767225601.000001#, 1791583200.238999#, 1791583200.239#]
    goldens = [1767225600000000&, 1767225600125000&, 1767225600999999&, 1767225601000001&, 1791583200238999&, 1791583200239000&]
    for i = 0 to values.Count() - 1
        check(twitchAdClockUtc({epoch: 1, video: values[i]}) = goldens[i], "independent exact UTC microsecond golden " + i.ToStr())
    end for
    for each epoch in [0, 2, -1, 1.0, "1", invalid]
        check(twitchAdClockUtc({epoch: epoch, video: 1767225600#}) = invalid, "unproven/noninteger epoch refuses UTC")
    end for
    imprecise! = 1767225600#
    check(type(imprecise!, 3) = "Float", "negative control is actual single precision")
    for each video in [imprecise!, -1#, 2147483648#, "1767225600", invalid]
        check(twitchAdClockUtc({epoch: 1, video: video}) = invalid, "imprecise or invalid rendered value refuses UTC")
    end for
    check(twitchAdClockUtc(invalid) = invalid, "missing native frame refused")
    check(twitchAdClockUtc({epoch: 1}) = invalid, "missing native video track refused")
end sub

function sourceText() as string
    q = Chr(34)
    text = "#EXTM3U" + Chr(10) + "#EXT-X-TARGETDURATION:2" + Chr(10) + "#EXT-X-MEDIA-SEQUENCE:41" + Chr(10)
    text += "#EXT-X-MAP:URI=" + q + "init.mp4" + q + Chr(10)
    text += "#EXT-X-DATERANGE:ID=" + q + "PRIVATE_ID" + q + ",CLASS=" + q + "twitch-stitched-ad" + q + ",START-DATE=" + q + "2026-01-01T00:00:01.500001Z" + q + ",DURATION=4.250001,X-TV-TWITCH-AD-POD-LENGTH=2,X-TV-TWITCH-AD-POD-POSITION=0,X-TV-TWITCH-AD-URL=" + q + "https://private.invalid/SECRET" + q + Chr(10)
    for i = 0 to 3
        text += "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:0" + (i * 2).ToStr() + ".000000Z" + Chr(10)
        text += "#EXTINF:2.000," + Chr(10) + "private-segment-" + i.ToStr() + ".m4s" + Chr(10)
    end for
    return text
end function

function publication() as object
    segments = []
    for i = 0 to 3
        segments.Push({sequence: 41 + i, duration: "2.000", durationUs: 2000000, videoId: "live-" + (i * 2 + 3).ToStr(), audioId: "live-" + (i * 2 + 4).ToStr()})
    end for
    return {generation: 1, mediaSequence: 41, targetDuration: 2, initVideoId: "live-1", initAudioId: "live-2", durationUs: 8000000, sourceOffsetUs: 2000000, ended: false, segments: segments}
end function

sub testSourceProjection()
    m.config = {sourceDelaySeconds: 2, metadata: {bandwidth: 6000000, width: 1920, height: 1080, frameRate: "60.000", videoCodec: "avc1.64002a"}}
    text = sourceText()
    timeline = twitchAdClockTimeline(text)
    check(twitchAdClockTimelineValid(timeline), "actual explicit PDT media timeline accepted")
    if timeline = invalid then return
    check(timeline.segments.Count() = 4 and timeline.cues.Count() = 1, "four anchors/one exact ad range")
    for i = 0 to 3
        entry = timeline.segments[i]
        check(entry.Count() = 5 and entry.sequence = 41 + i and entry.epoch = 0 and entry.startUs = 1767225600000000& + i * 2000000&, "independent source sequence/UTC golden")
    end for
    cue = timeline.cues[0]
    check(cue.startUs = 1767225601500001& and cue.durationUs = 4250001& and cue.endUs = 1767225605750002&, "exact independent fractional ad timing")
    safe = FormatJson(timeline)
    check(safe.InStr("PRIVATE_ID") < 0 and safe.InStr("SECRET") < 0 and safe.InStr("private-segment") < 0 and safe.InStr("init.mp4") < 0, "provider URI/identity/tracking never retained")
    pub = publication()
    check(loopbackPublicationValid(pub), "actual unchanged publication validator accepts golden")
    original = FormatJson(pub)
    projection = twitchAdClockProject(timeline, pub, 0)
    check(projection <> invalid, "matching exact source epoch projects")
    check(twitchAdClockProject(timeline, pub, 1) = invalid, "wrong epoch projection refused")
    canonical = loopbackManifest("video", pub).ToAsciiString()
    projected = twitchAdClockManifest("video", pub, projection).ToAsciiString()
    check(projected.InStr("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00.000000Z") >= 0, "actual manifest has exact first anchor")
    check(projected.InStr("START-DATE=" + Chr(34) + "2026-01-01T00:00:01.500001Z" + Chr(34) + ",DURATION=4.250001") >= 0, "projected metadata round-trips exact fractional cue")
    check(projected.InStr("PRIVATE_ID") < 0 and projected.InStr("SECRET") < 0, "projected manifest has sanitized synthetic cue identity only")
    check(FormatJson(pub) = original and loopbackManifest("video", pub).ToAsciiString() = canonical, "canonical publication/bytes remain unchanged")
    check(twitchAdClockManifest("master", pub, projection).ToAsciiString() = loopbackManifest("master", pub).ToAsciiString(), "master remains canonical")
    reload = twitchAdClockTimeline(projected)
    check(reload <> invalid and twitchAdClockTimelineValid(reload), "actual projected media manifest can supply trusted cue Task")
    if reload <> invalid then check(FormatJson(reload.cues) = FormatJson(timeline.cues), "exact five-field cues round-trip")
    mutated = ParseJson(FormatJson(projection))
    mutated.segments[0].date = "2026-01-01T00:00:01.000000Z"
    check(twitchAdClockManifest("video", pub, mutated).ToAsciiString() = canonical, "projection mutation refuses overlay and preserves ordinary playback")
    short = publication()
    short.segments[0].durationUs = 1999999
    check(twitchAdClockProject(timeline, short, 0) = invalid, "duration mismatch refuses projection")
    wrong = publication()
    wrong.segments[0].sequence = 40
    check(twitchAdClockProject(timeline, wrong, 0) = invalid, "missing selected sequence refuses projection")
    for each bad in [text.Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00.000000Z", "# no anchor"), text.Replace("#EXT-X-MEDIA-SEQUENCE:41", "# no sequence"), text.Replace("00:00:02.000000Z", "00:00:01.999999Z"), text.Replace("#EXTINF:2.000,", "#EXTINF:bogus,"), text.Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:02.000000Z", "#EXT-X-DISCONTINUITY")]
        candidate = twitchAdClockTimeline(bad)
        check(not twitchAdClockTimelineValid(candidate), "missing/malformed/overlap/discontinuity anchor refused")
    end for
    crlf = twitchAdClockTimeline(text.Replace(Chr(10), Chr(13) + Chr(10)))
    check(FormatJson(crlf) = FormatJson(timeline), "LF/CRLF source timeline is identical")
    state = {sourceUrl: "https://test.ttvnw.net/current.m3u8", closed: false, phase: "segment", epoch: 0}
    twitchAdClockCapture(state, "playlist", text, state.sourceUrl)
    check(twitchAdClockTimelineValid(state.adClockTimeline), "captured timeline validated")
    check(state.adClockSource = state.sourceUrl, "captured source binding exact")
    check(twitchAdClockPublication(state, pub) <> invalid, "actual current source feed sidecar publication")
    twitchAdClockCapture(state, "playlist", text, "https://test.ttvnw.net/old.m3u8")
    check(twitchAdClockPublication(state, pub) = invalid, "stale signed-source feed cannot bind a cue")
    state.closed = true
    twitchAdClockCapture(state, "playlist", text, state.sourceUrl)
    check(twitchAdClockPublication(state, pub) = invalid, "closed source cannot publish metadata")
end sub

sub testBoundaries()
    bounds = [{startUs: 1767225600000000&, endUs: 1767225602000000&}]
    check(twitchAdClockBoundsValid(bounds), "strict sanitized anchor bounds")
    check(twitchAdClockInBounds(1767225600000000&, bounds), "exact first frame anchor included")
    check(twitchAdClockInBounds(1767225601999999&, bounds), "last actual frame included")
    check(not twitchAdClockInBounds(1767225602000000&, bounds), "half-open end refuses future frame")
    check(not twitchAdClockInBounds(1767225599999999&, bounds), "unanchored old frame refused")
    for each bad in [[{startUs: 0, endUs: 2000000, secret: "TOKEN"}], [{startUs: 1.0, endUs: 2000000}], [{startUs: 0, endUs: 0}], [{startUs: 0, endUs: 10000001}], [{startUs: 0, endUs: 2000000}, {startUs: 1999999, endUs: 4000000}], "raw body", invalid]
        check(not twitchAdClockBoundsValid(bad), "malformed/noninteger/secret/overlap bounds rejected")
    end for
    check(adMetadataSource("https://test.ttvnw.net/live.m3u8?sig=abc", "direct") = "https://test.ttvnw.net/live.m3u8?sig=abc", "exact trusted signed media source retained only inside Task")
    check(adMetadataSource("http://127.0.0.1:54321/master.m3u8", "loopback") = "http://127.0.0.1:54321/video.m3u8", "positively selected own loopback video path")
    for each bad in ["http://127.0.0.1:80/master.m3u8", "http://localhost:54321/master.m3u8", "http://127.0.0.1:54321/arbitrary", "http://127.0.0.1:54321/master.m3u8?secret=x", "https://test.ttvnw.net/live.m3u8#fragment", "https://test.ttvnw.net@evil.invalid/a", "https://evil.invalid/a"]
        check(adMetadataSource(bad, "direct") = "" and adMetadataSource(bad, "loopback") = "", "arbitrary/ambiguous URI rejected")
    end for
end sub

sub testHeaders()
    check(adMetadataHeaders([{ "Content-Length": "123" }], 200, 123), "exact complete identity response framing")
    check(adMetadataHeaders([{ "Content-Length": "123" }, { "Content-Encoding": "identity" }, { "Content-Range": "bytes 0-122/123" }], 206, 123), "complete exact finite range framing")
    for each bad in [[], [{ "Content-Length": "123" }, { "content-length": "123" }], [{ "Content-Length": "123" }, { "Location": "https://SECRET.invalid" }], [{ "Content-Length": "123" }, { "Transfer-Encoding": "chunked" }], [{ "Content-Length": "123" }, { "Content-Encoding": "gzip" }], [{ "Content-Length": "122" }], [{ "Content-Length": "123", "X": "duplicate-shape" }], [{ "Content-Length": "123" }, { "X-Bad": Chr(10) }], [{ "Content-Length": 123 }]]
        check(not adMetadataHeaders(bad, 200, 123), "malformed/redirect/duplicate/compressed/count/secret framing refused")
    end for
    check(not adMetadataHeaders([{ "Content-Length": "123" }, { "Content-Range": "bytes 0-122/124" }], 206, 123), "partial range cannot become trusted complete metadata")
    check(not adMetadataHeaders([{ "Content-Length": "123" }, { "Content-Range": "bytes 0-122/123" }], 200, 123), "unexpected Content-Range on full response refused")
    check(not adMetadataHeaders([{ "Content-Length": "123" }], 302, 123), "redirect response code cannot supply cues")
    check(not adMetadataHeaders([{ "Content-Length": "262145" }], 200, 262145), "retained framing count bound unchanged")
end sub

sub testSourceEpochAgreement()
    for each prefix in ["", "#EXT-X-DISCONTINUITY-SEQUENCE:27" + Chr(10)]
        source = sourceText().Replace("#EXT-X-MEDIA-SEQUENCE:41" + Chr(10), "#EXT-X-MEDIA-SEQUENCE:41" + Chr(10) + prefix)
        source = source.Replace("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:04.000000Z", "#EXT-X-DISCONTINUITY" + Chr(10) + "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:04.000000Z")
        for each suffix in ["08", "10"]
            source += "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:" + suffix + ".000000Z" + Chr(10) + "#EXTINF:2.000," + Chr(10) + "extra" + suffix + ".m4s" + Chr(10)
        end for
        original = nativeLiveParsePlaylist(source, "https://test.ttvnw.net/current.m3u8")
        observational = twitchAdClockTimeline(source)
        check(twitchAdClockTimelineValid(observational), "explicit original discontinuity source timeline is valid")
        for i = 0 to 3
            check(original.segments[i].epoch = observational.segments[i].epoch and original.segments[i].sequence = observational.segments[i].sequence and original.segments[i].durationUs = observational.segments[i].durationUs, "actual unchanged Core parser and sidecar agree on source epoch/seq/duration")
        end for
        pub = publication()
        selected = pub.segments
        selected.Shift(): selected.Shift()
        pub.segments = selected
        selectedSource = original.segments
        selectedSource.Shift(): selectedSource.Shift()
        original.segments = selectedSource
        actualSelected = nlWindow(original, 0&)
        check(twitchAdClockProject(observational, pub, actualSelected.epoch) <> invalid, "actual selected-window source epoch supports matching sidecar")
        check(twitchAdClockProject(observational, pub, 1&) = invalid or actualSelected.epoch = 1&, "native Video UTC epoch must not substitute for source-window epoch")
    end for
end sub
