' Metadata is informational. A malformed projection falls back to canonical
' bytes; it must never reject otherwise valid playback or alter a media URI.
function twitchAdClockManifest(track as string, publication as dynamic, projection as dynamic) as dynamic
    canonical = loopbackManifest(track, publication)
    if canonical = invalid or track = "master" or projection = invalid then return canonical
    if not twitchAdClockTimelineValid(projection) then return canonical
    checked = twitchAdClockProject(projection, publication, projection.segments[0].epoch)
    if checked = invalid then return canonical
    text = canonical.ToAsciiString()
    lines = text.Split(Chr(10))
    output = ""
    at = 0
    for each line in lines
        if line.Left(8) = "#EXTINF:"
            if at >= projection.segments.Count() then return canonical
            output += "#EXT-X-PROGRAM-DATE-TIME:" + projection.segments[at].date + Chr(10)
            if at = 0 then output += twitchAdClockCueTags(projection.cues)
            at += 1
        end if
        if line <> "" then output += line + Chr(10)
    end for
    if at <> projection.segments.Count() then return canonical
    return loopbackAsciiBuffer(output)
end function
