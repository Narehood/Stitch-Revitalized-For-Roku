function loopbackKeys(value as dynamic, keys as object) as boolean
    if type(value) <> "roAssociativeArray" then return false
    if value.Count() <> keys.Count() then return false
    for each key in keys
        if not value.DoesExist(key) then return false
    end for
    return true
end function

function loopbackDurationUs(text as dynamic) as integer
    if not loopbackString(text) then return -1
    if text.Len() < 1 or text.Len() > 9 then return -1
    parts = text.Split(".")
    if parts.Count() < 1 or parts.Count() > 2 then return -1
    whole = loopbackUnsigned(parts[0], 10)
    if whole < 0 then return -1
    fraction = 0
    if parts.Count() = 2
        digits = parts[1]
        if digits.Len() < 1 or digits.Len() > 6 then return -1
        fraction = loopbackUnsigned(digits, 999999)
        if fraction < 0 then return -1
        for i = digits.Len() to 5
            fraction *= 10
        end for
    end if
    micros = whole * 1000000 + fraction
    if micros < 1 or micros > 10000000 then return -1
    return micros
end function

function loopbackPublicationValid(pub as dynamic) as boolean
    if not loopbackKeys(pub, ["generation", "mediaSequence", "targetDuration", "initVideoId", "initAudioId", "durationUs", "sourceOffsetUs", "ended", "segments"]) then return false
    sessionId = loopbackAssetSession(pub.initVideoId)
    generationCap = 256&
    if sessionId <> "" then generationCap = 4294967295&
    if not loopbackInteger(pub.generation) or pub.generation < 1 or pub.generation > generationCap then return false
    if not loopbackInteger(pub.mediaSequence) or pub.mediaSequence < 0 or pub.mediaSequence > 4294967295 then return false
    if not loopbackInteger(pub.targetDuration) or pub.targetDuration < 1 or pub.targetDuration > 10 then return false
    if not loopbackInteger(pub.durationUs) or pub.durationUs < 1 or pub.durationUs > 80000000 then return false
    if not loopbackInteger(pub.sourceOffsetUs) or pub.sourceOffsetUs < m.config.sourceDelaySeconds * 1000000 then return false
    if not loopbackBoolean(pub.ended) then return false
    if not pub.ended and pub.durationUs < 6000000 then return false
    if not loopbackAssetId(pub.initVideoId) or not loopbackAssetId(pub.initAudioId) or pub.initVideoId = pub.initAudioId then return false
    if loopbackAssetSession(pub.initAudioId) <> sessionId then return false
    if type(pub.segments) <> "roArray" then return false
    if pub.segments.Count() < 1 or pub.segments.Count() > 8 then return false
    seen = {}
    seen[pub.initVideoId] = true
    seen[pub.initAudioId] = true
    sum = 0
    nextSequence = pub.mediaSequence
    for each segment in pub.segments
        if not loopbackKeys(segment, ["sequence", "duration", "durationUs", "videoId", "audioId"]) then return false
        if not loopbackInteger(segment.sequence) or segment.sequence <> nextSequence then return false
        if not loopbackInteger(segment.durationUs) or loopbackDurationUs(segment.duration) <> segment.durationUs then return false
        if segment.durationUs > pub.targetDuration * 1000000 then return false
        if segment.durationUs > 2000000 then return false
        if not loopbackAssetId(segment.videoId) or not loopbackAssetId(segment.audioId) then return false
        if loopbackAssetSession(segment.videoId) <> sessionId or loopbackAssetSession(segment.audioId) <> sessionId then return false
        if seen.DoesExist(segment.videoId) or seen.DoesExist(segment.audioId) or segment.videoId = segment.audioId then return false
        seen[segment.videoId] = true
        seen[segment.audioId] = true
        sum += segment.durationUs
        nextSequence += 1
    end for
    return sum = pub.durationUs
end function

function loopbackSafeDiagnostics(value as dynamic, cacheBudgetBytes = 16777216& as dynamic, steadyMode = false as dynamic) as dynamic
    if not loopbackInteger(cacheBudgetBytes) then return invalid
    if cacheBudgetBytes <> 16777216& and cacheBudgetBytes <> 25165824& and cacheBudgetBytes <> 33554432& then return invalid
    if not loopbackBoolean(steadyMode) then return invalid
    fields = ["phase", "failed", "failureCategory", "generation", "cacheBytes", "peakCacheBytes", "assetCount", "fetchCount", "playlistCount", "initPairCount", "segmentPairCount", "transferActive", "inputRetained", "inputFilePresent", "closed"]
    if not loopbackKeys(value, fields) then return invalid
    if not loopbackString(value.phase) or value.phase.Len() < 1 or value.phase.Len() > 32 then return invalid
    phases = ",playlist,init,init-rotation,segment,init-video,init-audio,segment-video,segment-audio,ready,ended,failed,stopped,"
    if value.phase.InStr(",") >= 0 or phases.InStr("," + value.phase + ",") < 0 then return invalid
    for each name in ["failed", "transferActive", "inputRetained", "inputFilePresent", "closed"]
        if not loopbackBoolean(value[name]) then return invalid
    end for
    for each name in ["failureCategory", "generation", "cacheBytes", "peakCacheBytes", "assetCount", "fetchCount", "playlistCount", "initPairCount", "segmentPairCount"]
        if not loopbackInteger(value[name]) or value[name] < 0 then return invalid
        cap = 1024&
        if steadyMode then cap = 4294967295&
        if name = "cacheBytes" or name = "peakCacheBytes" then cap = cacheBudgetBytes
        if name = "assetCount" then cap = 256&
        if name = "generation" and not steadyMode then cap = 256&
        if name = "failureCategory" then cap = 2
        if value[name] > cap then return invalid
    end for
    return value
end function

function loopbackAsciiBuffer(text as string) as dynamic
    if text.Len() < 1 or text.Len() > 16384 then return invalid
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    if bytes.Count() <> text.Len() then return invalid
    return bytes
end function

function loopbackManifest(track as string, publication as dynamic) as dynamic
    nl = Chr(10)
    quote = Chr(34)
    if track = "master"
        meta = m.config.metadata
        text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-INDEPENDENT-SEGMENTS" + nl
        text += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=" + quote + "audio" + quote + ",NAME=" + quote + "Audio" + quote + ",DEFAULT=YES,AUTOSELECT=YES,URI=" + quote + "/audio.m3u8" + quote + nl
        text += "#EXT-X-STREAM-INF:BANDWIDTH=" + meta.bandwidth.ToStr() + ",RESOLUTION=" + meta.width.ToStr() + "x" + meta.height.ToStr() + ",FRAME-RATE=" + meta.frameRate + ",CODECS=" + quote + meta.videoCodec + ",mp4a.40.2" + quote + ",AUDIO=" + quote + "audio" + quote + nl + "/video.m3u8" + nl
        return loopbackAsciiBuffer(text)
    end if
    if track <> "video" and track <> "audio" then return invalid
    if not loopbackPublicationValid(publication) then return invalid
    initId = publication.initVideoId
    if track = "audio" then initId = publication.initAudioId
    text = "#EXTM3U" + nl + "#EXT-X-VERSION:7" + nl + "#EXT-X-TARGETDURATION:2" + nl
    text += "#EXT-X-MEDIA-SEQUENCE:" + publication.mediaSequence.ToStr() + nl
    text += "#EXT-X-MAP:URI=" + quote + "/asset/" + initId + quote + nl
    for each segment in publication.segments
        id = segment.videoId
        if track = "audio" then id = segment.audioId
        text += "#EXTINF:" + segment.duration + "," + nl + "/asset/" + id + nl
    end for
    if publication.ended then text += "#EXT-X-ENDLIST" + nl
    return loopbackAsciiBuffer(text)
end function
