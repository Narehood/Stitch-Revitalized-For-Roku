sub main()
    m.count = 0
    now = CreateObject("roDateTime").AsSeconds()
    frame = { metadata: { message_id: "event-1", message_timestamp: CreateObject("roDateTime").ToISOString(), message_type: "notification", subscription_type: "channel.raid", subscription_version: "1" }, payload: { subscription: { id: "subscription-1", status: "enabled", type: "channel.raid", version: "1", condition: { from_broadcaster_user_id: "123" } }, event: { from_broadcaster_user_id: "123", to_broadcaster_user_id: "456", to_broadcaster_user_login: "Destination", to_broadcaster_user_name: "Destination Name" } } }
    result = raidNotification(frame, "123", "subscription-1", now)
    check(result <> invalid and result.login = "destination" and result.id = "456" and result.name = "Destination Name", "outgoing raid identity")
    timestamp = frame.metadata.message_timestamp
    frame.metadata.message_timestamp = "2026-10-29T12:00:00.634234626Z"
    eventTime = CreateObject("roDateTime")
    eventTime.FromISO8601String("2026-10-29T12:00:00.000")
    check(raidNotification(frame, "123", "subscription-1", eventTime.AsSeconds()) <> invalid, "literal Twitch nanosecond timestamp uses Roku's supported format")
    check(raidNotification(frame, "123", "subscription-1", eventTime.AsSeconds() + 121) = invalid, "literal Twitch timestamp still rejects stale events")
    check(raidNotification(frame, "123", "subscription-1", eventTime.AsSeconds() - 31) = invalid, "literal Twitch timestamp still rejects future events")
    frame.metadata.message_timestamp = timestamp
    for each kind in ["session_welcome", "session_keepalive", "USERNOTICE", "session_reconnect", "revocation"]
        bad = ParseJson(FormatJson(frame))
        bad.metadata.message_type = kind
        check(raidNotification(bad, "123", "subscription-1", now) = invalid, "only raid notifications")
    end for
    for each id in ["789", "", "another-subscription"]
        check(raidNotification(frame, id, "subscription-1", now) = invalid, "current source only")
        check(raidNotification(frame, "123", id, now) = invalid, "current subscription only")
    end for
    for each login in ["", "a/b", "name" + Chr(10), "https://evil.invalid", "long_login_more_than_twenty_five_characters"]
        bad = ParseJson(FormatJson(frame))
        bad.payload.event.to_broadcaster_user_login = login
        check(raidNotification(bad, "123", "subscription-1", now) = invalid, "invalid destination")
    end for
    bad = ParseJson(FormatJson(frame))
    bad.payload.event.to_broadcaster_user_id = "123"
    check(raidNotification(bad, "123", "subscription-1", now) = invalid, "no self raid")
    bad.payload.event.to_broadcaster_user_id = "bad"
    check(raidNotification(bad, "123", "subscription-1", now) = invalid, "numeric destination")
    check(raidNotification(frame, "123", "subscription-1", now + 121) = invalid, "stale event")
    check(raidNotification(frame, "123", "subscription-1", now - 31) = invalid, "future event")
    for each missing in ["metadata", "payload"]
        bad = ParseJson(FormatJson(frame))
        bad.Delete(missing)
        check(raidNotification(bad, "123", "subscription-1", now) = invalid, "missing envelope")
    end for
    for each bad in [invalid, "bad", [], 1, {}]
        check(raidNotification(bad, "123", "subscription-1", now) = invalid, "malformed frame")
    end for
    check(raidSocketUrl("wss://eventsub.wss.twitch.tv/ws?session=123"), "official reconnect URL")
    check(raidSocketUrl("wss://eventsub.wss.twitch.tv:443/ws"), "official TLS port")
    for each url in [invalid, "", "ws://eventsub.wss.twitch.tv/ws", "wss://eventsub.wss.twitch.tv.evil.invalid/ws", "wss://user@eventsub.wss.twitch.tv/ws", "wss://eventsub.wss.twitch.tv:444/ws", "wss://eventsub.wss.twitch.tv/ws" + Chr(10)]
        check(not raidSocketUrl(url), "reject foreign or unsafe reconnect URL")
    end for
    m.top = { account: "viewer", channelId: "123", stopRequested: false, raid: invalid }
    m.mockAccount = "viewer"
    m.token = "fixture-token"
    m.subscriptionId = "subscription-1"
    m.seen = []
    publishRaidFrame(frame)
    check(m.top.raid <> invalid, "actual worker publishes current raid")
    m.top.raid = invalid
    publishRaidFrame(frame)
    check(m.top.raid = invalid, "actual worker suppresses duplicate delivery")
    frame.metadata.message_id = "event-2"
    m.mockAccount = "other-viewer"
    publishRaidFrame(frame)
    check(m.top.raid = invalid, "actual worker rejects changed account")
    m.mockAccount = "viewer"
    m.top.stopRequested = true
    publishRaidFrame(frame)
    check(m.top.raid = invalid, "actual worker rejects stop-time publication")
    testRaidTransport(frame)
    print "RAID_PROTOCOL_PASS:"; m.count
end sub

sub testRaidTransport(frame as object)
    m.top = { account: "viewer", channelId: "123", stopRequested: false, raid: invalid }
    m.top.ObserveField = sub(field as string, port as object)
        m.observed = field
    end sub
    m.top.UnobserveField = sub(field as string)
        m.unobserved = field
    end sub
    m.mockAccount = "viewer"
    m.events = []
    state = { opens: 0, closed: [], posts: [], canceled: 0, tls: 0 }
    GetGlobalAA().raidFixture = state
    welcome = { metadata: { message_type: "session_welcome" }, payload: { session: { id: "session-1", keepalive_timeout_seconds: 30 } } }
    reconnect = { metadata: { message_type: "session_reconnect" }, payload: { session: { reconnect_url: "wss://eventsub.wss.twitch.tv/ws?session=migrate" } } }
    frame.metadata.message_id = "first"
    m.events.Push(raidFixtureEvent("ws", 1, 5, FormatJson(welcome)))
    m.events.Push(raidFixtureEvent("ws", 1, 5, FormatJson(frame)))
    m.events.Push(raidFixtureEvent("http", 99, 202, "{""data"":[{""id"":""subscription-1""}]}"))
    m.events.Push(raidFixtureEvent("ws", 1, 5, FormatJson(frame)))
    m.events.Push(raidFixtureEvent("ws", 1, 5, FormatJson(reconnect)))
    m.events.Push(raidFixtureEvent("ws", 2, 5, FormatJson(welcome)))
    frame.metadata.message_id = "second"
    m.events.Push(raidFixtureEvent("ws", 2, 5, FormatJson(frame)))
    raidWorkerMain()
    captured = GetGlobalAA().raidFixture
    check(captured.opens = 2 and captured.posts.Count() = 1, "migration opens replacement but never resubscribes")
    body = ParseJson(captured.posts[0].body)
    check(body.type = "channel.raid" and body.condition.from_broadcaster_user_id = "123" and body.transport.session_id = "session-1", "actual POST native wire keys identify outgoing source and session")
    check(captured.posts[0].url = "https://api.twitch.tv/helix/eventsub/subscriptions", "credentials go only to fixed Twitch API endpoint")
    check(captured.tls = 6, "initial and migrating sockets and HTTP all enable both TLS checks")
    check(m.seen.Count() = 2 and m.top.raid.messageId = "second", "early notification, duplicate and migrated delivery execute real worker")
    check(captured.closed.Count() = 2, "migration and stop close both socket owners")
    check(m.top.observed = "stopRequested" and m.top.unobserved = "stopRequested" and captured.canceled = 1 and m.top.control = "stop", "worker observes stop wakeup and releases HTTP before stopping itself")

    m.top.stopRequested = false
    m.events = [raidFixtureEvent("ws", 3, 5, FormatJson(welcome)), raidFixtureEvent("http", 99, 401, "unauthorized")]
    runRaidWatch()
    captured = GetGlobalAA().raidFixture
    check(captured.opens = 3 and captured.posts.Count() = 2 and m.terminal, "HTTP authorization refusal is terminal without retry churn")
    m.top.account = "$default$"
    runRaidWatch()
    check(GetGlobalAA().raidFixture.opens = 3, "signed-out worker never opens a connection")

    m.top.account = "viewer"
    m.top.stopRequested = false
    m.Delete("terminal")
    m.events = []
    state = GetGlobalAA().raidFixture
    state.failOpen = true
    GetGlobalAA().raidFixture = state
    runRaidWatch()
    check(GetGlobalAA().raidFixture.opens = 4 and m.top.stopRequested and m.terminal = false, "failed first socket reaches cancellable retry wait with a Boolean terminal flag")

    m.top.stopRequested = false
    state = { opens: 0, closed: [], posts: [], canceled: 0, tls: 0, failOpens: 4, skipRetryWait: true }
    GetGlobalAA().raidFixture = state
    m.events = [raidFixtureEvent("ws", 5, 5, FormatJson(welcome))]
    m.events.Push(raidFixtureEvent("http", 99, 202, "{""data"":[{""id"":""subscription-1""}]}"))
    runRaidWatch()
    captured = GetGlobalAA().raidFixture
    check(captured.opens = 5 and captured.posts.Count() = 1, "four opening failures still reconnect and subscribe for the current live owner")
end sub

function raidFixtureRetryMilliseconds(clock as object) as integer
    if GetGlobalAA().raidFixture.skipRetryWait = true then return 30000
    return clock.TotalMilliseconds()
end function

' Model the documented native parser boundary; the simulator accepts extra formats.
sub raidFixtureFromISO(date as object, text as string)
    if CreateObject("roRegex", "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}$", "").IsMatch(text)
        date.FromISO8601String(text)
    end if
end sub

function raidFixtureWait(timeout as integer, port as object) as dynamic
    if m.events.Count() = 0
        m.top.stopRequested = true
        return invalid
    end if
    return m.events.Shift()
end function

function raidFixtureType(event as dynamic) as string
    if event = invalid then return "Invalid"
    if event.fixtureType = "ws" then return "roWebSocketEvent"
    return "roUrlEvent"
end function

function raidFixtureEvent(kind as string, id as integer, code as integer, text as string) as object
    return { fixtureType: kind, id: id, code: code, text: text,
        GetSocketId: function() as integer
            return m.id
        end function,
        GetSourceIdentity: function() as integer
            return m.id
        end function,
        GetType: function() as integer
            return m.code
        end function,
        GetResponseCode: function() as integer
            return m.code
        end function,
        GetString: function() as string
            return m.text
        end function,
        GetInfo: function() as object
            return { text: m.text }
        end function }
end function

function raidFixtureSocket() as object
    state = GetGlobalAA().raidFixture
    state.opens++
    GetGlobalAA().raidFixture = state
    socket = raidFixtureTransfer()
    socket.id = state.opens
    socket.GetSocketId = socket.GetIdentity
    socket.Open = function(timeout as integer) as boolean
        if GetGlobalAA().raidFixture.failOpen = true then return false
        state = GetGlobalAA().raidFixture
        if state.failOpens <> invalid and state.failOpens > 0
            state.failOpens--
            GetGlobalAA().raidFixture = state
            return false
        end if
        return true
    end function
    socket.Close = sub()
        state = GetGlobalAA().raidFixture
        state.closed.Push(m.id)
        GetGlobalAA().raidFixture = state
    end sub
    return socket
end function

function raidFixtureTransfer() as object
    return { id: 99, url: "",
        SetMessagePort: sub(port as object)
        end sub,
        SetCertificatesFile: sub(file as string)
        end sub,
        EnablePeerVerification: sub(enabled as boolean)
            if enabled
                state = GetGlobalAA().raidFixture
                state.tls++
                GetGlobalAA().raidFixture = state
            end if
        end sub,
        EnableHostVerification: sub(enabled as boolean)
            if enabled
                state = GetGlobalAA().raidFixture
                state.tls++
                GetGlobalAA().raidFixture = state
            end if
        end sub,
        SetAutoPingReply: sub(enabled as boolean)
        end sub,
        SetUrl: sub(url as string)
            m.url = url
        end sub,
        SetHeaders: sub(headers as object)
        end sub,
        GetIdentity: function() as integer
            return m.id
        end function,
        AsyncPostFromString: function(body as string) as boolean
            state = GetGlobalAA().raidFixture
            state.posts.Push({ url: m.url, body: body })
            GetGlobalAA().raidFixture = state
            return true
        end function,
        AsyncCancel: sub()
            state = GetGlobalAA().raidFixture
            state.canceled++
            GetGlobalAA().raidFixture = state
        end sub }
end function

function get_setting(key as string, fallback as dynamic) as dynamic
    return m.mockAccount
end function

function get_user_setting(key as string, fallback as dynamic) as dynamic
    return "fixture-token"
end function

sub check(condition as boolean, label as string)
    if not condition
        print "RAID_PROTOCOL_FAIL:" + label
        stop
    end if
    m.count++
end sub
