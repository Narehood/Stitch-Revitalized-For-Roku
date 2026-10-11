' Opt-in lower live latency: direct Twitch live playback goes through a
' loopback relay that trims the playlists (see LowLatencyRelay). One relay
' serves one Video, so every restart begins near the live edge again.
sub initLowLatencyPlayback()
    m.lowLatencyRelay = invalid
    m.lowLatencyReadyUrl = ""
    m.lowLatencyRecovery = false
    m.lowLatencyUnavailable = false
end sub

function lowLatencyEligible() as boolean
    if m.lowLatencyUnavailable or m.rokuSessionId <> "" then return false
    if m.top.contentRequested = invalid or m.top.content = invalid then return false
    if m.top.contentRequested.contentType <> "LIVE" then return false
    if m.top.content.isProxied or m.top.content.isTransmux then return false
    url = m.top.content.url
    if GetInterface(url, "ifString") = invalid then return false
    if url.Left(8) <> "https://" then return false
    return get_user_setting("playback.lowLatency", "false") = "true"
end function

' True means playContent waits for a fresh relay to report its local URL.
function prepareLowLatencyPlayback(isRecovery as boolean) as boolean
    if m.lowLatencyReadyUrl <> "" then return false
    stopLowLatencyRelay()
    if not lowLatencyEligible() then return false
    m.lowLatencyRelay = CreateObject("roSGNode", "LowLatencyRelay")
    if m.lowLatencyRelay = invalid
        m.lowLatencyUnavailable = true
        return false
    end if
    m.lowLatencyRecovery = isRecovery
    m.lowLatencyRelay.observeField("status", "onLowLatencyStatus")
    m.lowLatencyRelay.sourceUrl = m.top.content.url
    m.lowLatencyRelay.control = "run"
    return true
end function

sub onLowLatencyStatus(event as object)
    if m.disposed or m.isExiting or m.lowLatencyRelay = invalid then return
    if not event.getRoSGNode().isSameNode(m.lowLatencyRelay) then return
    status = event.getData()
    if type(status) <> "roAssociativeArray" then return
    if GetInterface(status.url, "ifString") <> invalid
        m.lowLatencyReadyUrl = status.url
        playContent(m.lowLatencyRecovery)
    else if m.lowLatencyReadyUrl = "" and (m.video = invalid or not m.video.lowLatency)
        ' Refused before use (for example separate audio): play directly.
        ? getLogTimestamp(); " [VideoPlayer] Lower latency unavailable: "; status.failure
        m.lowLatencyUnavailable = true
        stopLowLatencyRelay()
        playContent(m.lowLatencyRecovery)
    end if
end sub

' Consumes the ready URL: the returned copy plays through the relay, while
' m.top.content keeps the signed Twitch source for refreshes and switches.
function lowLatencyContent(original as object) as object
    url = m.lowLatencyReadyUrl
    m.lowLatencyReadyUrl = ""
    fields = original.getFields()
    fields.Delete("change")
    fields.Delete("focusedChild")
    fields.url = url
    fields.StreamUrls = [url]
    stream = { "quality": true, "bitrate": 0 }
    if type(fields.Streams) = "roArray"
        if fields.Streams.Count() > 0 then stream.Append(fields.Streams[0])
    end if
    stream.url = url
    fields.Streams = [stream]
    playable = CreateObject("roSGNode", "TwitchContentNode")
    playable.setFields(fields)
    return playable
end function

sub stopLowLatencyRelay()
    if m.lowLatencyRelay <> invalid then m.lowLatencyRelay.stopRequested = true
    m.lowLatencyRelay = destroyTask(m.lowLatencyRelay, "status")
    m.lowLatencyReadyUrl = ""
end sub
