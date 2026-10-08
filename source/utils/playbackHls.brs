' RFC 8216 attribute lists contain quoted commas (CODECS, NAME, URI).
function parsePlaybackHlsAttributes(text as string) as object
    attributes = {}
    quoted = false
    start = 0
    for index = 0 to text.Len()
        char = ","
        if index < text.Len() then char = text.Mid(index, 1)
        if char = Chr(34) then quoted = not quoted
        if char = "," and not quoted
            item = text.Mid(start, index - start).Trim()
            equals = item.InStr("=")
            if equals > 0
                key = UCase(item.Left(equals).Trim())
                value = item.Mid(equals + 1).Trim()
                if value.Len() >= 2 and value.Left(1) = Chr(34) and value.Right(1) = Chr(34)
                    value = value.Mid(1, value.Len() - 2)
                end if
                attributes[key] = value
            end if
            start = index + 1
        end if
    end for
    return attributes
end function

function resolvePlaybackHlsUrl(base as string, reference as string) as string
    reference = reference.Trim()
    lower = LCase(reference)
    if lower.Left(8) = "https://" or lower.Left(7) = "http://" then return reference
    if reference = "" then return ""
    schemeEnd = base.InStr("://")
    if schemeEnd < 0 then return ""
    if reference.Left(2) = "//" then return base.Left(schemeEnd) + ":" + reference
    ' Same-document fragments inherit the complete path and query.
    if reference.Left(1) = "#" then return base.Split("#")[0] + reference
    if reference.InStr(":") >= 0 and reference.Split("/")[0].InStr(":") >= 0 then return ""
    withoutQuery = base.Split("?")[0].Split("#")[0]
    authorityEnd = withoutQuery.Mid(schemeEnd + 3).InStr("/")
    if authorityEnd < 0
        origin = withoutQuery
        path = "/"
    else
        authorityEnd += schemeEnd + 3
        origin = withoutQuery.Left(authorityEnd)
        path = withoutQuery.Mid(authorityEnd)
    end if
    if reference.Left(1) = "?" then return withoutQuery + reference
    if reference.Left(1) = "/"
        path = reference
    else
        parts = path.Split("/")
        parts.Pop()
        path = parts.Join("/") + "/" + reference
    end if
    suffix = ""
    marker = path.InStr("?")
    if marker < 0 then marker = path.InStr("#")
    if marker >= 0
        suffix = path.Mid(marker)
        path = path.Left(marker)
    end if
    normalized = []
    for each part in path.Split("/")
        if part = ".."
            if normalized.Count() > 0 then normalized.Pop()
        else if part <> "." and part <> ""
            normalized.Push(part)
        end if
    end for
    return origin + "/" + normalized.Join("/") + suffix
end function

function parsePlaybackHlsMaster(text as string, url as string) as object
    master = { variants: [], media: [], isTransmux: false }
    pending = invalid
    for each rawLine in text.Split(Chr(10))
        line = rawLine.Trim()
        if line.Left(18) = "#EXT-X-STREAM-INF:"
            pending = parsePlaybackHlsAttributes(line.Mid(18))
        else if line.Left(13) = "#EXT-X-MEDIA:"
            media = parsePlaybackHlsAttributes(line.Mid(13))
            if media["URI"] <> invalid then media["URI"] = resolvePlaybackHlsUrl(url, media["URI"])
            master.media.Push(media)
        else if line.Left(19) = "#EXT-X-TWITCH-INFO:"
            info = parsePlaybackHlsAttributes(line.Mid(19))
            if info["TRANSCODESTACK"] <> invalid and info["TRANSCODESTACK"].InStr("transmux") >= 0 then master.isTransmux = true
        else if line <> "" and line.Left(1) <> "#" and pending <> invalid
            pending["URL"] = resolvePlaybackHlsUrl(url, line)
            if pending["URL"] <> "" then master.variants.Push(pending)
            pending = invalid
        end if
    end for
    for each variant in master.variants
        variant["SEPARATE-AUDIO"] = false
        if variant["AUDIO"] <> invalid
            for each media in master.media
                if media["TYPE"] = "AUDIO" and media["GROUP-ID"] = variant["AUDIO"] and media["URI"] <> invalid
                    variant["SEPARATE-AUDIO"] = true
                end if
            end for
        end if
    end for
    return master
end function

function isMuxedPlaybackCmaf(variant as object, playlist as string) as dynamic
    if playlist.Trim().Left(7) <> "#EXTM3U" then return invalid
    if playlist.InStr("#EXT-X-MAP:") < 0 then return false
    if variant["SEPARATE-AUDIO"] = true then return false
    codecs = variant["CODECS"]
    if codecs = invalid then return invalid
    ' The media uses fMP4 and its combined rendition declares video and AAC,
    ' with no external audio URI. MAP alone is not evidence of muxed audio.
    if LCase(codecs).InStr("mp4a") >= 0 then return true
    return invalid
end function

function playbackQualityLabel(variant as object) as string
    label = variant["RESOLUTION"].Split("x")[1] + "p"
    if variant["FRAME-RATE"] <> invalid
        fps = Int(Val(variant["FRAME-RATE"]))
        if fps > 30 then label += fps.ToStr()
    end if
    name = variant["VIDEO"]
    if name = invalid then name = variant["STABLE-VARIANT-ID"]
    if name <> invalid and (name = "chunked" or name.InStr("source") >= 0) then label += " (Source)"
    if variant["CODECS"] <> invalid
        if variant["CODECS"].InStr("hvc1") >= 0 or variant["CODECS"].InStr("hev1") >= 0 then label += " HEVC"
    end if
    return label
end function

function buildProxyM3u8Url(proxyUrl as string, streamUrl as string, hints as dynamic) as string
    url = proxyUrl + "/m3u8?u=" + streamUrl.EncodeUriComponent()
    if hints = invalid then return url
    for each pair in [["CODECS", "codecs"], ["BANDWIDTH", "bw"], ["RESOLUTION", "res"]]
        value = hints[pair[0]]
        if value <> invalid and value <> "" then url += "&" + pair[1] + "=" + value.EncodeUriComponent()
    end for
    return url
end function

' A quality entry is a complete playback contract, not just a display label.
function playbackQualityEntry(variant as object, url as string, isTransmux as boolean, isProxied as boolean) as object
    quality = playbackQualityLabel(variant)
    bitrate = 0
    if variant["BANDWIDTH"] <> invalid then bitrate = Int(Val(variant["BANDWIDTH"]) / 1000)
    hd = Val(variant["RESOLUTION"].Split("x")[1]) >= 720
    return {
        QualityID: quality,
        url: url,
        streamFormat: "hls",
        StreamUrls: [url],
        Streams: [{ url: url, stickyredirects: false, quality: hd, contentid: quality, bitrate: bitrate }],
        StreamQualities: [hd],
        StreamContentIds: [quality],
        StreamBitrates: [bitrate],
        StreamStickyHttpRedirects: [false],
        isTransmux: isTransmux,
        isProxied: isProxied,
        playbackNotice: "",
        ForwardQueryStringParams: not isProxied
    }
end function

function playbackAutomaticEntry(metadata as object, masterUrl as string, proxyUrl as string, allowedUrls as object, allSupported as boolean, hasMuxed as boolean, hasSeparateAudio as boolean, demuxUrls = invalid as dynamic) as dynamic
    if metadata.Count() = 0 then return invalid
    entry = {}
    entry.Append(metadata[0])
    entry.QualityID = "Automatic"
    if proxyUrl <> "" and (hasMuxed or hasSeparateAudio or not allSupported)
        entry.url = buildProxyM3u8Url(proxyUrl, masterUrl, invalid) + "&variants=" + FormatJSON(allowedUrls).EncodeUriComponent()
        if demuxUrls <> invalid then entry.url += "&demuxVariants=" + FormatJSON(demuxUrls).EncodeUriComponent()
        entry.StreamUrls = [entry.url]
        entry.isTransmux = false
        entry.isProxied = true
        entry.ForwardQueryStringParams = false
    else if allSupported and not hasMuxed
        entry.url = masterUrl
        entry.StreamUrls = [masterUrl]
    end if
    entry.Streams = [{ url: entry.url, stickyredirects: false, quality: entry.StreamQualities[0], contentid: "Automatic", bitrate: entry.StreamBitrates[0] }]
    if proxyUrl = "" and (not allSupported or hasMuxed)
        entry.playbackNotice = "Automatic selected a compatible quality for this Roku. Configure the audio service to adapt across a filtered quality ladder."
    else if proxyUrl = "" and hasSeparateAudio
        entry.playbackNotice = "Automatic preserves this stream's separate audio. Configure the audio service to choose a manual quality."
    end if
    return entry
end function
