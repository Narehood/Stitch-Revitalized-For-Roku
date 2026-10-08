' Explicit offline boundaries. No transport, credential or registry access.
function TwitchGraphQLRequest(params as object) as object
    return { data: { user: { stream: { playbackAccessToken: { value: "fixture/+?=&", signature: "fixture-sig" } } } } }
end function

function getTwitchSupportedCodecs(device as object) as string
    return "h264"
end function

function isTwitchVariantSupported(variant as object, device as object) as boolean
    return variant["VIDEO"] <> "reject-decoder"
end function

function get_user_setting(key as string, defaultValue = "" as dynamic) as dynamic
    if key = "proxy.url" then return m.top.fixtureProxy
    if key = "playback.video.quality" then return m.top.fixturePreference
    return defaultValue
end function

function HttpRequest(options as object) as object
    return {
        fixtureHost: m.top,
        requestOptions: options,
        Send: function() as object
            text = ""
            if m.requestOptions.url.InStr("https://usher.ttvnw.net/") = 0
                m.fixtureHost.fixtureUsherUrl = m.requestOptions.url
                text = m.fixtureHost.fixtureMaster
            else
                m.fixtureHost.fixtureProbes++
                if m.requestOptions.url.InStr("unknown-transport") >= 0
                    text = "<html>offline</html>"
                else if m.requestOptions.url.InStr("muxed") >= 0
                    text = "#EXTM3U" + Chr(10) + "#EXT-X-MAP:URI=" + Chr(34) + "init.mp4" + Chr(34)
                else
                    text = "#EXTM3U" + Chr(10) + "#EXTINF:2," + Chr(10) + "segment.ts"
                end if
            end if
            return {
                body: text,
                GetResponseCode: function() as integer
                    return 200
                end function,
                GetString: function() as string
                    return m.body
                end function
            }
        end function
    }
end function

sub captureException(error as dynamic, context as string)
    print "STITCH_SELECTION_FAIL: unexpected task exception in " + context; " "; FormatJSON(error)
    if m.top <> invalid then m.top.fixtureFailures++
end sub
