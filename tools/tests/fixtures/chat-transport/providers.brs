' All production provider handlers, lifecycle and JSON decoding execute.
' HTTP events and registry access are offline boundaries; no credentials are used.
sub main()
    m.assertions = 0
    m.failures = 0
    bttvChannel = "https://api.betterttv.net/3/cached/users/twitch/42"
    sevenChannel = "https://7tv.io/v3/users/twitch/42"
    cases = [
        { url: bttvChannel, body: "{}", name: "BTTV missing both arrays" }
        { url: bttvChannel, body: "{""channelEmotes"":[]}", name: "BTTV missing shared array" }
        { url: bttvChannel, body: "{""sharedEmotes"":[]}", name: "BTTV missing channel array" }
        { url: bttvChannel, body: "{""channelEmotes"":[],""sharedEmotes"":null}", name: "BTTV null shared array" }
        { url: bttvChannel, body: "{""channelEmotes"":[],""sharedEmotes"":{}}", name: "BTTV object shared array" }
        { url: bttvChannel, body: "{""channelEmotes"":null,""sharedEmotes"":[]}", name: "BTTV null channel array" }
        { url: bttvChannel, body: "{""channelEmotes"":{},""sharedEmotes"":[]}", name: "BTTV object channel array" }
        { url: sevenChannel, body: "{}", name: "7TV missing no-set envelope" }
        { url: sevenChannel, body: "{""emote_set"":{}}", name: "7TV missing emotes array" }
        { url: sevenChannel, body: "{""emote_set"":{""emotes"":null}}", name: "7TV null emotes array" }
        { url: sevenChannel, body: "{""emote_set"":{""emotes"":{}}}", name: "7TV object emotes array" }
        { url: "https://api.betterttv.net/3/cached/emotes/global", body: "{}", name: "BTTV global object instead of array" }
        { url: "https://api.betterttv.net/3/cached/frankerfacez/users/twitch/42", body: "{}", name: "FFZ object instead of array" }
        { url: "https://7tv.io/v3/emote-sets/global", body: "{""emotes"":{}}", name: "7TV global object instead of array" }
    ]
    for each fixtureCase in cases
        resetProviders()
        state = getGlobalAA()
        responses = state.providerResponses
        validBody = responses[fixtureCase.url]
        responses[fixtureCase.url] = fixtureCase.body
        state.providerResponses = responses
        runEmoteJob()
        check(m.fetchFailed and m.top.completed and not m.top.cacheComplete, fixtureCase.name + " must finish with retryable failure")
        check(state.providerRequests.count() = 6, fixtureCase.name + " does not prevent remaining providers")

        responses = state.providerResponses
        responses[fixtureCase.url] = validBody
        state.providerResponses = responses
        ' Reopening retries a cache only when the previous job left it incomplete.
        if not m.top.cacheComplete
            m.top.completed = false
            runEmoteJob()
        end if
        check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, fixtureCase.name + " succeeds on retry")
        check(state.providerRequests.count() = 12, fixtureCase.name + " is fetched again on retry")
    end for

    resetProviders()
    runEmoteJob()
    check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, "legitimate empty provider arrays complete the cache")
    check(getGlobalAA().publishedCache.IRC = "https://cdn.example/irc.png", "empty provider results preserve learned IRC emotes")

    resetProviders()
    responses = getGlobalAA().providerResponses
    responses[sevenChannel] = "{""emote_set"":null}"
    getGlobalAA().providerResponses = responses
    runEmoteJob()
    check(not m.fetchFailed and m.top.completed and m.top.cacheComplete, "explicit 7TV no-set completes the cache")

    resetProviders()
    getGlobalAA().cancelUrl = bttvChannel
    runEmoteJob()
    check(not m.top.completed and not m.top.cacheComplete and getGlobalAA().providerRequests.count() = 3, "stop during actual HTTP provider handling starts no later provider")
    check(getGlobalAA().cachePublications = 1, "stop during actual HTTP provider handling suppresses late cache publication")

    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

sub resetProviders()
    m.top = { stopRequested: false, channel_id: "42", channel: "fixture", completed: false, cacheComplete: false }
    m.global = { emoteCache: { IRC: "https://cdn.example/irc.png" }, twitchBadges: {}, setField: fixturePublishCache }
    state = getGlobalAA()
    state.providerRequests = []
    state.providerResponses = {
        "https://gql.twitch.tv/gql": "{""data"":{""badges"":[],""user"":null}}"
        "https://api.betterttv.net/3/cached/emotes/global": "[]"
        "https://api.betterttv.net/3/cached/users/twitch/42": "{""channelEmotes"":[],""sharedEmotes"":[]}"
        "https://api.betterttv.net/3/cached/frankerfacez/users/twitch/42": "[]"
        "https://7tv.io/v3/emote-sets/global": "{""emotes"":[]}"
        "https://7tv.io/v3/users/twitch/42": "{""emote_set"":{""emotes"":[]}}"
    }
    state.cachePublications = 0
    state.publishedCache = invalid
    state.cancelUrl = ""
end sub

function HttpRequest(params as object) as object
    state = getGlobalAA()
    requests = state.providerRequests
    requests.push(params.url)
    state.providerRequests = requests
    if params.url = state.cancelUrl then m.top.stopRequested = true
    return { url: params.url, send: fixtureHttpSend }
end function

function fixtureHttpSend() as object
    return { body: getGlobalAA().providerResponses[m.url], status: 200 }
end function

' Adapt the fake HTTP event to the unmodified production status/JSON decoder.
function decodeJsonResponse(event as object, allowHttpError = false as boolean) as dynamic
    return decodeJsonBody(event.body, event.status, allowHttpError)
end function

function get_user_setting(key as string, fallback = invalid as dynamic) as dynamic
    return fallback
end function

sub fixturePublishCache(field as string, cache as object)
    if field <> "emoteCache" then return
    getGlobalAA().cachePublications++
    getGlobalAA().publishedCache = cache
end sub

sub check(condition as boolean, message as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_CHAT_TRANSPORT_FAIL: " + message
    end if
end sub
