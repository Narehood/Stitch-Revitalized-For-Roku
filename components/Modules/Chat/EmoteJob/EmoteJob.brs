sub init()
    m.top.functionName = "main"
end sub

function getGlobalTwitchEmotes()
    emoteCache = m.global.emoteCache
    try
        ? "[EmoteJob] - getGlobalTwitchEmotes"
        ids = TwitchClientIds()
        access_token = ""
        if get_user_setting("access_token", "") <> ""
            access_token = "Bearer " + get_user_setting("access_token")
        end if
        link = "https://api.twitch.tv/helix/chat/emotes/global"
        req = HttpRequest({
            url: link.EncodeUri()
            headers: {
                "Accept": "*/*"
                "Authorization": access_token
                "Client-Id": ids.helix
            }
            method: "GET"
            timeout: 15000
            retries: 2
        })
        body = req.send()
        if body <> invalid
            response_string = ParseJSON(body)
            if response_string?.data <> invalid
                for each emote in response_string.data
                    uri = emote.images.url_1x
                    emoteCache[emote.name] = uri
                end for
            end if
        end if
    catch e
        ? "Error grabbing channelttv badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end function

function getChannelTwitchEmotes(channel_id)
    emoteCache = m.global.emoteCache
    try
        ? "[EmoteJob] - getChannelTwitchEmotes"
        ids = TwitchClientIds()
        access_token = ""
        if get_user_setting("access_token", "") <> ""
            access_token = "Bearer " + get_user_setting("access_token")
        end if
        link = "https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + channel_id
        req = HttpRequest({
            url: link.EncodeUri()
            headers: {
                "Accept": "*/*"
                "Authorization": access_token
                "Client-Id": ids.helix
            }
            method: "GET"
            timeout: 15000
            retries: 2
        })
        body = req.send()
        if body <> invalid
            response_string = ParseJSON(body)
            if response_string?.data <> invalid
                for each emote in response_string.data
                    uri = emote.images.url_1x
                    emoteCache[emote.name] = uri
                end for
            end if
        end if
    catch e
        ? "Error grabbing channelttv badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end function

function getTwitchBadges()
    ? "[EmoteJob] - getTwitchBadges"
    badgelist = {}
    try
        reqHeaders = TwitchDefaultHeaders("androidTv")
        req = HttpRequest({
            url: "https://gql.twitch.tv/gql"
            headers: reqHeaders
            method: "POST"
            timeout: 15000
            retries: 2
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
        rsp = ParseJSON(req.send())
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
end function

function invokerest(link as string) as object
    req = HttpRequest({
        url: link.EncodeUri()
        headers: {
            "Accept": "*/*"
        }
        method: "GET"
    })
    response_string = ParseJSON(req.send())
    ' ? "responseString: "; response_string
    return response_string
end function

sub getChannel7tvEmotes(channel_id)
    ? "[EmoteJob] - getChannel7tvEmotes"
    emoteCache = m.global.emoteCache
    try
        temp = invokerest("https://7tv.io/v3/users/twitch/" + channel_id)
        if temp.emote_set <> invalid
            if temp.emote_set.emotes <> invalid
                for each emote in temp.emote_set.emotes
                    uri = "https://cdn.7tv.app/emote/" + emote.id + "/1x.gif"
                    emoteCache[emote.name] = uri
                end for
            end if
        end if
    catch e
        ? "Error grabbing 7tv badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end sub

sub getGlobal7tvEmotes()
    ? "[EmoteJob] - getGlobal7tvEmotes"
    emoteCache = m.global.emoteCache
    try
        temp = invokerest("https://7tv.io/v3/emote-sets/global")
        for each emote in temp.emotes
            uri = "https://cdn.7tv.app/emote/" + emote.id + "/1x.gif"
            emoteCache[emote.name] = uri
        end for
    catch e
        ? "Error grabbing global7tv badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end sub

function getGlobalTTVEmotes()
    ? "[EmoteJob] - getGlobalTTVEmotes"
    emoteCache = m.global.emoteCache
    try
        temp = invokerest("https://api.betterttv.net/3/cached/emotes/global")
        for each emote in temp
            uri = "https://cdn.betterttv.net/emote/" + emote.id + "/1x.gif"
            emoteCache[emote.code] = uri
        end for
    catch e
        ? "Error grabbing globalttv badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end function

function getChannelTTVFrankerEmotes(channel_id)
    ? "[EmoteJob] - getChannelTTVFrankerEmotes"
    emoteCache = m.global.emoteCache
    try
        temp = invokerest("https://api.betterttv.net/3/cached/frankerfacez/users/twitch/" + channel_id)
        for each emote in temp
            emoteCache[emote.code] = emote.images["1x"]
        end for
    catch e
        ? "Error grabbing channelttvfranker badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end function

function getChannelTTVEmotes(channel_id)
    emoteCache = m.global.emoteCache
    try
        ? "[EmoteJob] - getChannelTTVEmotes"
        temp = invokerest("https://api.betterttv.net/3/cached/users/twitch/" + channel_id)
        if temp.sharedEmotes <> invalid
            for each emote in temp.sharedEmotes
                uri = "https://cdn.betterttv.net/emote/" + emote.id + "/1x.gif"
                emoteCache[emote.code] = uri
            end for
        end if
    catch e
        ? "Error grabbing channelttv badges"
    end try
    m.global.setField("emoteCache", emoteCache)
end function

function main()
    ? "[EmoteJob] - getAllEmotes"
    m.global.setField("emoteCache", {})
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
end function