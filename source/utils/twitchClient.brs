' Centralized Twitch client identity, request helpers, and device decode capability probes.
' Playback still relies on Twitch GQL + Usher (unofficial); keep Client-IDs in one place.

function TwitchClientIds() as object
    return {
        androidTv: "ue6666qo983tsx6so1t0vnawi233wa"
        web: "kimne78kx3ncx6brgo4mv6wki5h1ko"
        helix: "cf9fbjz6j9i6k6guz3dwh6qff5dluz"
    }
end function

function TwitchGetDeviceLocale() as string
    di = CreateObject("roDeviceInfo")
    return di.GetCurrentLocale().Replace("_", "-")
end function

function TwitchGetDeviceId() as string
    deviceCode = get_user_setting("device_code", "")
    if deviceCode <> ""
        return deviceCode
    end if
    return CreateObject("roDeviceInfo").GetRandomUUID()
end function

function TwitchAuthHeader() as dynamic
    accessToken = get_user_setting("access_token", "")
    if accessToken <> ""
        return "OAuth " + accessToken
    end if
    return invalid
end function

function TwitchDefaultHeaders(clientKey = "androidTv" as string) as object
    ids = TwitchClientIds()
    clientId = ids.androidTv
    if clientKey = "web"
        clientId = ids.web
    else if clientKey = "helix"
        clientId = ids.helix
    end if

    headers = {
        "Accept": "*/*"
        "Client-Id": clientId
        "Device-ID": TwitchGetDeviceId()
        "Origin": "https://android.tv.twitch.tv"
        "Referer": "https://android.tv.twitch.tv/"
        "Accept-Language": TwitchGetDeviceLocale()
        "User-Agent": "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36"
    }

    auth = TwitchAuthHeader()
    if auth <> invalid
        headers["Authorization"] = auth
    end if

    return headers
end function

function TwitchWebPlaybackHeaders(includeLowLatency = false as boolean) as object
    ids = TwitchClientIds()
    headers = {
        "Accept": "*/*"
        "Origin": "https://android.tv.twitch.tv"
        "Referer": "https://android.tv.twitch.tv/"
        "User-Agent": "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36"
        "Client-ID": ids.web
        "Device-ID": TwitchGetDeviceId()
    }
    if includeLowLatency
        headers["Cache-Control"] = "no-cache"
        headers["Connection"] = "keep-alive"
        headers["X-Low-Latency"] = "1"
    end if
    return headers
end function

function TwitchClipPlaybackHeaders() as object
    ids = TwitchClientIds()
    headers = {
        "Accept": "video/mp4,video/webm,video/*,*/*"
        "Accept-Encoding": "identity"
        "Accept-Language": "en-US,en;q=0.9"
        "Cache-Control": "no-cache"
        "Connection": "keep-alive"
        "Origin": "https://www.twitch.tv"
        "Pragma": "no-cache"
        "Referer": "https://www.twitch.tv/"
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        "Client-ID": ids.web
        "X-Device-Id": TwitchGetDeviceId()
    }
    authToken = get_user_setting("auth_token", "")
    if authToken = ""
        authToken = get_user_setting("access_token", "")
    end if
    if authToken <> ""
        headers["Authorization"] = "Bearer " + authToken
    end if
    return headers
end function

' HttpRequest.send() returns roUrlEvent — always extract the body string first.
function TwitchResponseBody(event as dynamic) as dynamic
    if event = invalid
        return invalid
    end if
    if GetInterface(event, "ifString") <> invalid
        if event = ""
            return invalid
        end if
        return event
    end if
    if type(event) = "roUrlEvent"
        body = event.getString()
        if body = invalid or body = ""
            return invalid
        end if
        return body
    end if
    return invalid
end function

function TwitchParseJsonResponse(event as dynamic) as dynamic
    body = TwitchResponseBody(event)
    if body = invalid
        return invalid
    end if
    return ParseJSON(body)
end function

' GraphQL helper with retries. Returns parsed JSON object or invalid.
function TwitchGraphQLRequest(data as object, retries = 3 as integer) as dynamic
    deviceCode = get_user_setting("device_code", "")
    if deviceCode = ""
        return invalid
    end if

    headers = TwitchDefaultHeaders("androidTv")
    attempt = 0
    while attempt < retries
        attempt = attempt + 1
        req = HttpRequest({
            url: "https://gql.twitch.tv/gql"
            headers: headers
            method: "POST"
            data: data
            timeout: 15000
            retries: 1
        })
        rsp = TwitchParseJsonResponse(req.send())
        if rsp <> invalid
            if rsp.errors <> invalid and rsp.errors.Count() > 0
                ' Retry transient failures; surface last response if all attempts fail
                if attempt >= retries
                    return rsp
                end if
            else
                return rsp
            end if
        end if
        sleep(250 * attempt)
    end while
    return invalid
end function

function TwitchHttpGet(url as string, headers as object, retries = 3 as integer) as dynamic
    attempt = 0
    while attempt < retries
        attempt = attempt + 1
        req = HttpRequest({
            url: url
            headers: headers
            method: "GET"
            timeout: 15000
            retries: 1
        })
        body = TwitchResponseBody(req.send())
        if body <> invalid
            return body
        end if
        sleep(200 * attempt)
    end while
    return invalid
end function

function canDecodeVideoAt(width as integer, height as integer, codec = "h264" as string) as boolean
    di = CreateObject("roDeviceInfo")
    result = di.CanDecodeVideo({
        Codec: codec
        Width: width
        Height: height
    })
    if result <> invalid and result.Result = true
        return true
    end if
    return false
end function

' Max video decode height the device can handle (not UI graphics resolution).
function getMaxVideoDecodeHeight() as integer
    di = CreateObject("roDeviceInfo")
    codecs = ["hevc", "h264"]
    heights = [
        { w: 3840, h: 2160 }
        { w: 2560, h: 1440 }
        { w: 1920, h: 1080 }
        { w: 1280, h: 720 }
    ]

    for each sizeInfo in heights
        for each codec in codecs
            if canDecodeVideoAt(sizeInfo.w, sizeInfo.h, codec)
                return sizeInfo.h
            end if
        end for
    end for

    ' Fallback: display size, never below 720 for modern Twitch clients
    display = di.GetDisplaySize()
    if display <> invalid and display.h <> invalid and display.h >= 720
        return display.h
    end if
    return 1080
end function

function getMaxVideoDecodeResolutionLabel() as string
    height = getMaxVideoDecodeHeight()
    if height >= 2160
        return "2160p"
    else if height >= 1440
        return "1440p"
    else if height >= 1080
        return "1080p"
    end if
    return "720p"
end function

' Codecs string for Usher supported_codecs (comma-separated FourCC-ish tokens Twitch accepts).
function getSupportedStreamCodecs() as string
    di = CreateObject("roDeviceInfo")
    parts = ["avc1"]
    if di.CanDecodeVideo({ Codec: "hevc" }).Result = true
        parts.Push("hvc1")
        parts.Push("hev1")
    end if
    if di.CanDecodeVideo({ Codec: "av1" }).Result = true
        parts.Push("av01")
    end if
    result = parts[0]
    for i = 1 to parts.Count() - 1
        result = result + "," + parts[i]
    end for
    return result
end function

function isStreamHeightPlayable(height as integer) as boolean
    if height <= 0
        return false
    end if
    return height <= getMaxVideoDecodeHeight()
end function
