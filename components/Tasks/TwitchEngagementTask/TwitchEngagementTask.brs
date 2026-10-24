sub init()
    m.top.functionName = "main"
end sub

sub main()
    try
        runEngagement()
    catch e
        if not m.top.stopRequested
            m.top.response = { owner: m.top.owner, watchState: "unavailable", hypeState: "unavailable", hypeTrain: invalid, pinnedMessage: invalid, pinState: "unavailable" }
        end if
    end try
    m.top.control = "stop"
end sub

sub runEngagement()
    if m.top.stopRequested then return
    m.clock = createObject("roTimespan")
    m.port = createObject("roMessagePort")
    m.account = get_setting("active_user", "$default$")
    m.deviceId = get_user_setting("device_code", "")
    m.token = ""
    m.userId = ""
    m.beacon = invalid
    m.broadcastId = ""
    m.watch = engagementWatchState()
    m.hype = invalid
    m.pin = invalid
    m.pinState = "disabled"
    m.nextPinPoll = 0
    m.attempts = 0
    m.accepted = 0
    m.httpStatus = 0
    m.watchState = "disabled"
    m.hypeState = "disabled"
    m.nextPoll = 0
    m.nextDiscovery = 0
    m.snapshotValid = false
    m.lastAttemptMs = -60000
    m.pendingBroadcast = ""
    m.authExpiresMs = 0#
    m.nextValidationMs = 0#
    if not engagementLogin(m.top.channel) or not engagementId(m.top.channelId) or m.deviceId = ""
        m.watchState = "unavailable"
        publishEngagement()
        return
    end if
    if m.top.watchEnabled
        m.watchState = "signed_out"
        if m.account <> "$default$"
            m.token = get_user_setting("access_token", "")
            if m.token <> "" then validateEngagementAccount()
        end if
    end if
    publishEngagement()
    if m.userId = "" and not m.top.hypeEnabled and not m.top.pinsEnabled then return
    while not m.top.stopRequested
        if not engagementAccountCurrent()
            m.watchState = "account_changed"
            m.hype = invalid
            m.pin = invalid
            publishEngagement()
            exit while
        end if
        nowMs = m.clock.totalMilliseconds()
        if m.userId <> "" and nowMs >= m.nextValidationMs
            validateEngagementAccount()
            if m.userId = ""
                publishEngagement()
                exit while
            end if
        end if
        if nowMs >= m.nextPoll and (m.top.hypeEnabled or m.top.pinsEnabled or m.userId <> "")
            pollEngagement()
            interval = 30000
            if m.hype <> invalid then interval = 10000
            m.nextPoll = m.clock.totalMilliseconds() + interval
            publishEngagement()
        end if
        if m.top.pinsEnabled and m.clock.totalMilliseconds() >= m.nextPinPoll
            pollPinnedChat()
            m.nextPinPoll = m.clock.totalMilliseconds() + 15000
            publishEngagement()
        else if not m.top.pinsEnabled and m.pinState <> "disabled"
            m.pin = invalid
            m.pinState = "disabled"
            publishEngagement()
        end if
        if m.userId <> "" and m.top.watchEnabled and m.snapshotValid and m.broadcastId <> ""
            if m.beacon = invalid and nowMs >= m.nextDiscovery
                discoverEngagementBeacon()
                m.nextDiscovery = m.clock.totalMilliseconds() + 60000
                publishEngagement()
            end if
            if m.beacon <> invalid
                m.watch = engagementWatchStep(m.watch, m.top.sample)
                if m.watch.due then m.pendingBroadcast = m.broadcastId
                if m.pendingBroadcast <> "" and m.clock.totalMilliseconds() - m.lastAttemptMs >= 60000
                    ' Refresh the actual broadcast before any submission. A new
                    ' broadcast discards the old partial minute and pending send.
                    earnedBroadcast = m.pendingBroadcast
                    m.pendingBroadcast = ""
                    pollEngagement()
                    if m.snapshotValid and m.broadcastId = earnedBroadcast and engagementAccountCurrent() and not m.top.stopRequested
                        reportEngagementMinute()
                    end if
                    publishEngagement()
                end if
            end if
        else
            m.pendingBroadcast = ""
            watch = m.watch
            watch.last = invalid
            m.watch = watch
        end if
        if not m.top.hypeEnabled and m.hype <> invalid
            m.hype = invalid
            m.hypeState = "disabled"
            publishEngagement()
        end if
        wait(250, m.port)
    end while
    m.top.control = "stop"
end sub

function engagementAccountCurrent() as boolean
    if get_setting("active_user", "$default$") <> m.account then return false
    if not m.top.watchEnabled or m.token = "" then return true
    if m.userId <> "" and m.clock.totalMilliseconds() >= m.authExpiresMs then return false
    return get_user_setting("access_token", "") = m.token
end function

sub validateEngagementAccount()
    m.userId = ""
    m.watchState = "identity_unavailable"
    rsp = engagementHttp("https://id.twitch.tv/oauth2/validate", "GET", { Authorization: "OAuth " + m.token }, invalid, 32768)
    if rsp = invalid or rsp.status <> 200 then return
    identity = parseJson(rsp.body)
    if GetInterface(identity, "ifAssociativeArray") = invalid then return
    if not engagementId(identity.user_id) then return
    if identity.client_id <> "ue6666qo983tsx6so1t0vnawi233wa" or identity.login <> m.account then return
    if not engagementNumber(identity.expires_in) then return
    if identity.expires_in > 0 and identity.expires_in < 60 then return
    ' The TV grant can validate with a zero expiry. Trust the successful
    ' validation for a bounded hour and revalidate before that lease ends.
    lifetime = identity.expires_in
    if lifetime = 0 then lifetime = 3600
    m.userId = identity.user_id
    m.authExpiresMs = m.clock.totalMilliseconds() + (lifetime - 30) * 1000#
    m.nextValidationMs = m.clock.totalMilliseconds() + 3300000#
    m.watchState = "initializing"
end sub

sub pollEngagement()
    if m.top.stopRequested then return
    headers = { "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa", "Device-ID": m.deviceId, "Content-Type": "application/json" }
    rsp = engagementHttp("https://gql.twitch.tv/gql", "POST", headers, formatJson({
        "query": "query StitchEngagement($login: String!, $includeHype: Boolean!) { user(login: $login) { id stream { id } channel @include(if: $includeHype) { hypeTrain { execution { id startedAt expiresAt endedAt endReason progress { progression goal total level { value goal } } sharedHypeTrainDetails { id } } } } } }",
        "variables": { "login": m.top.channel, "includeHype": m.top.hypeEnabled }
    }), 131072)
    snapshot = invalid
    if rsp <> invalid and rsp.status = 200
        snapshot = engagementSnapshot(parseJson(rsp.body), m.top.channelId, createObject("roDateTime").asSeconds())
    end if
    m.snapshotValid = snapshot <> invalid
    if snapshot = invalid
        m.hype = invalid
        m.pin = invalid
        if m.top.pinsEnabled then m.pinState = "unavailable"
        m.hypeState = "unavailable"
        watch = m.watch
        watch.last = invalid
        m.watch = watch
        return
    end if
    if m.broadcastId <> snapshot.broadcastId
        m.broadcastId = snapshot.broadcastId
        m.watch = engagementWatchState()
        m.pendingBroadcast = ""
        m.pin = invalid
        m.nextPinPoll = 0
    end if
    if m.userId <> "" and m.broadcastId = "" then m.watchState = "stream_offline"
    m.hype = snapshot.hypeTrain
    m.hypeState = "inactive"
    if not m.top.hypeEnabled then m.hypeState = "disabled"
    if m.hype <> invalid then m.hypeState = m.hype.status
end sub

' Pin failures never invalidate the separate playback/broadcast snapshot.
sub pollPinnedChat()
    m.pin = invalid
    m.pinState = "unavailable"
    if m.top.stopRequested then return
    if not m.snapshotValid or m.broadcastId = "" then return
    try
        headers = { "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa", "Device-ID": m.deviceId, "Content-Type": "application/json" }
        rsp = engagementHttp("https://gql.twitch.tv/gql", "POST", headers, formatJson({
            "query": "query StitchPinnedChat($channelID: ID!) { channel(id: $channelID) { id pinnedChatMessages(first: 1, messageType: MOD) { edges { node { id type startsAt updatedAt endsAt pinnedMessage { id sentAt content { text } sender { id login displayName } } } } } } }",
            "variables": { "channelID": m.top.channelId }
        }), 131072)
        if rsp = invalid or rsp.status <> 200 then return
        snapshot = engagementPinSnapshot(parseJson(rsp.body), m.top.channelId, createObject("roDateTime").asSeconds())
        if snapshot = invalid then return
        m.pin = snapshot.pinnedMessage
        m.pinState = "inactive"
        if m.pin <> invalid then m.pinState = "active"
    catch e
        m.pin = invalid
        m.pinState = "unavailable"
    end try
end sub

sub discoverEngagementBeacon()
    m.watchState = "discovery_failed"
    page = engagementHttp("https://www.twitch.tv/" + m.top.channel, "GET", {}, invalid, 2097152)
    if page = invalid or page.status <> 200 then return
    settingsUrl = engagementSettingsUrl(page.body)
    if settingsUrl = invalid then return
    settings = engagementHttp(settingsUrl, "GET", {}, invalid, 2097152)
    if settings = invalid or settings.status <> 200 then return
    m.beacon = engagementBeaconUrl(settings.body)
    if m.beacon <> invalid then m.watchState = "ready"
end sub

sub reportEngagementMinute()
    if not m.top.watchEnabled or m.top.sample?.playing <> true or not engagementAccountCurrent() or m.top.stopRequested then return
    nowMs = m.clock.totalMilliseconds()
    ' No replay, catch-up burst or retry of an ambiguous POST.
    if nowMs - m.lastAttemptMs < 60000 then return
    body = engagementMinuteBody(m.userId, m.top.channelId, m.broadcastId, m.top.channel, m.top.owner, m.watch.minutes)
    if body = invalid then return
    m.lastAttemptMs = nowMs
    m.attempts++
    m.httpStatus = 0
    rsp = engagementHttp(m.beacon, "POST", { "Content-Type": "application/x-www-form-urlencoded" }, body, 4096)
    m.watchState = "network_error"
    if rsp = invalid then return
    m.httpStatus = rsp.status
    m.watchState = "telemetry_refused"
    if rsp.status >= 200 and rsp.status < 300
        m.accepted++
        m.watchState = "telemetry_accepted"
    end if
end sub

sub publishEngagement()
    if m.top.stopRequested then return
    summary = m.watchState + ":" + m.attempts.toStr() + ":" + m.accepted.toStr() + ":" + m.hypeState + ":" + m.pinState
    if summary <> m.lastPublishedSummary
        ? "[TwitchEngagement] watch="; m.watchState; " completed="; m.watch.minutes; " attempted="; m.attempts; " accepted="; m.accepted; " http="; m.httpStatus; " hype="; m.hypeState; " pin="; m.pinState
        m.lastPublishedSummary = summary
    end if
    m.top.response = { owner: m.top.owner, watchState: m.watchState, completedMinutes: m.watch.minutes, attemptedMinutes: m.attempts, acceptedMinutes: m.accepted, lastHttpStatus: m.httpStatus, hypeState: m.hypeState, hypeTrain: m.hype, pinState: m.pinState, pinnedMessage: m.pin }
end sub

' Only Task-local asynchronous transfers. Credentials are sent solely to the
' fixed OAuth validation endpoint, never to a discovered destination.
function engagementHttp(url as string, method as string, headers as object, body as dynamic, maxBytes as integer) as dynamic
    if m.top.stopRequested then return invalid
    transfer = createObject("roUrlTransfer")
    if transfer = invalid then return invalid
    transfer.setMessagePort(m.port)
    transfer.setCertificatesFile("common:/certs/ca-bundle.crt")
    if not transfer.enablePeerVerification(true) or not transfer.enableHostVerification(true) then return invalid
    transfer.setUrl(url)
    transfer.setHeaders(headers)
    transfer.setRequest(method)
    transfer.retainBodyOnError(true)
    deadline = createObject("roTimespan")
    started = false
    if body = invalid
        started = transfer.asyncGetToString()
    else
        started = transfer.asyncPostFromString(body)
    end if
    if not started then return invalid
    while not m.top.stopRequested and deadline.totalMilliseconds() < 6000
        event = wait(100, m.port)
        if deadline.totalMilliseconds() >= 6000 then exit while
        if type(event) = "roUrlEvent" and event.getSourceIdentity() = transfer.getIdentity()
            text = event.getString()
            if GetInterface(text, "ifString") = invalid then return invalid
            if text.len() > maxBytes then return invalid
            return { status: event.getResponseCode(), body: text }
        end if
    end while
    transfer.asyncCancel()
    return invalid
end function
