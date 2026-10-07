sub init()
    m.top.functionName = "main"
end sub

sub publishEmoteCache(fetched as object)
    ' Merge after fetching so IRC emotes learned during the HTTP wait are retained.
    cache = m.global.emoteCache
    if cache = invalid then cache = {}
    m.global.setField("emoteCache", ircMergeEmoteCache(cache, fetched))
end sub

sub getGlobalTwitchEmotes()
    emoteCache = {}
    try
        ' ? "[EmoteJob] - getGlobalTwitchEmotes"
        access_token = ""
        if get_user_setting("access_token") <> invalid
            access_token = "Bearer " + get_user_setting("access_token")
        end if
        if access_token = "" then return
        link = "https://api.twitch.tv/helix/chat/emotes/global"
        req = HttpRequest({
            url: link.EncodeUri(),
            headers: {
                "Accept": "*/*",
                "Authorization": access_token,
                "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa"
            },
            timeout: 7000,
            retries: 1,
            method: "GET"
        })
        response_string = decodeJsonResponse(req.send())

        if response_string?.data <> invalid
            for each emote in response_string.data
                uri = emote.images.url_1x
                emoteCache[emote.name] = uri
            end for
        end if
    catch e
        ? "Error grabbing channelttv badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub getChannelTwitchEmotes(channel_id)
    emoteCache = {}
    try
        ' ? "[EmoteJob] - getChannelTwitchEmotes"
        access_token = ""
        if get_user_setting("access_token") <> invalid
            access_token = "Bearer " + get_user_setting("access_token")
        end if
        if access_token = "" or channel_id = "" then return
        link = "https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + channel_id
        req = HttpRequest({
            url: link.EncodeUri(),
            headers: {
                "Accept": "*/*",
                "Authorization": access_token,
                "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa"
            },
            timeout: 7000,
            retries: 1,
            method: "GET"
        })
        response_string = decodeJsonResponse(req.send())

        if response_string?.data <> invalid
            for each emote in response_string.data
                uri = emote.images.url_1x
                emoteCache[emote.name] = uri
            end for
        end if
    catch e
        ? "Error grabbing channelttv badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub getTwitchBadges()
    ' ? "[EmoteJob] - getTwitchBadges"
    badgelist = {}
    try
        access_token = ""
        device_code = ""
        ' doubled up here in stead of defaulting to "" because access_token is dependent on device_code
        if get_user_setting("device_code") <> invalid
            device_code = get_user_setting("device_code")
        end if
        req = HttpRequest({
            url: "https://gql.twitch.tv/gql",
            headers: {
                "Accept": "*/*",
                "Authorization": access_token,
                "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa",
                "Device-ID": device_code,
                "Origin": "https://android.tv.twitch.tv",
                "Referer": "https://android.tv.twitch.tv/"
            },
            timeout: 7000,
            retries: 1,
            method: "POST",
            data: {
                "operationName": "ChatList_Badges",
                "variables": {
                    "channelLogin": m.top.channel
                },
                "extensions": {
                    "persistedQuery": {
                        "version": 1,
                        "sha256Hash": "86f43113c04606e6476e39dcd432dee47c994d77a83e54b732e11d4935f0cd08"
                    }
                }
            }
        })
        rsp = decodeJsonResponse(req.send())
        if rsp?.data?.badges = invalid then return
        for each badge in rsp.data.badges
            identifier = badge.setID + "/" + badge.version
            badgelist[identifier] = badge.image2x
        end for
        if rsp.data.user <> invalid
            if rsp.data.user.broadcastBadges <> invalid
                for each badge in rsp.data.user.broadcastBadges
                    identifier = badge.setID + "/" + badge.version
                    badgelist[identifier] = badge.image2x
                end for
            end if
        end if
    catch e
        ? "Error grabbing twitch badges"
    end try
    if m.global.twitchBadges = invalid
        m.global.addFields({ twitchBadges: badgelist })
    else
        m.global.setField("twitchBadges", badgelist)
    end if
end sub

function invokerest(link as string) as object
    req = HttpRequest({
        url: link.EncodeUri(),
        headers: {
            "Accept": "*/*"
        },
        timeout: 7000,
        retries: 1,
        method: "GET"
    })
    response_string = decodeJsonResponse(req.send())
    ' ? "responseString: "; response_string
    return response_string
end function

sub getChannel7tvEmotes(channel_id)
    ' ? "[EmoteJob] - getChannel7tvEmotes"
    emoteCache = {}
    try
        temp = invokerest("https://7tv.io/v3/users/twitch/" + channel_id)
        if temp.emote_set <> invalid
            if temp.emote_set.emotes <> invalid
                for each emote in temp.emote_set.emotes
                    uri = irc7tvImage(emote)
                    if uri <> invalid then emoteCache[emote.name] = uri
                end for
            end if
        end if
    catch e
        ? "Error grabbing 7tv badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub getGlobal7tvEmotes()
    ' ? "[EmoteJob] - getGlobal7tvEmotes"
    emoteCache = {}
    try
        temp = invokerest("https://7tv.io/v3/emote-sets/global")
        for each emote in temp.emotes
            uri = irc7tvImage(emote)
            if uri <> invalid then emoteCache[emote.name] = uri
        end for
    catch e
        ? "Error grabbing global7tv badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub getGlobalTTVEmotes()
    ' ? "[EmoteJob] - getGlobalTTVEmotes"
    emoteCache = {}
    try
        temp = invokerest("https://api.betterttv.net/3/cached/emotes/global")
        for each emote in temp
            uri = ircBttvImage(emote)
            emoteCache[emote.code] = uri
        end for
    catch e
        ? "Error grabbing globalttv badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub getChannelTTVFrankerEmotes(channel_id)
    ' ? "[EmoteJob] - getChannelTTVFrankerEmotes"
    emoteCache = {}
    try
        temp = invokerest("https://api.betterttv.net/3/cached/frankerfacez/users/twitch/" + channel_id)
        for each emote in temp
            if emote?.images?["1x"] <> invalid then emoteCache[emote.code] = ircImageUrl(emote.images["1x"])
        end for
    catch e
        ? "Error grabbing channelttvfranker badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub getChannelTTVEmotes(channel_id)
    emoteCache = {}
    try
        ' ? "[EmoteJob] - getChannelTTVEmotes"
        temp = invokerest("https://api.betterttv.net/3/cached/users/twitch/" + channel_id)
        if temp.sharedEmotes <> invalid
            for each emote in temp.sharedEmotes
                uri = ircBttvImage(emote)
                emoteCache[emote.code] = uri
            end for
        end if
        if temp.channelEmotes <> invalid
            for each emote in temp.channelEmotes
                emoteCache[emote.code] = ircBttvImage(emote)
            end for
        end if
    catch e
        ? "Error grabbing channelttv badges"
    end try
    publishEmoteCache(emoteCache)
end sub

sub main()
    ' ? "[EmoteJob] - getAllEmotes"
    channel_id = m.top.channel_id
    getChannelTwitchEmotes(channel_id)
    getTwitchBadges()
    getGlobalTwitchEmotes()
    if get_user_setting("BetterTTVEmote", "true") = "true"
        getGlobalTTVEmotes()
        getChannelTTVEmotes(channel_id)
    end if
    if get_user_setting("FFZEmote", "true") = "true"
        getChannelTTVFrankerEmotes(channel_id)
    end if
    if get_user_setting("7tvEmote", "true") = "true"
        getGlobal7tvEmotes()
        getChannel7tvEmotes(channel_id)
    end if
end sub
