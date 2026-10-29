sub init()
    m.top.functionName = "main"
end sub

sub main()
    m.socket = invalid
    m.candidate = invalid
    m.transfer = invalid
    try
        runRaidWatch()
    catch e
        ' Never publish errors containing OAuth headers or a provider response.
        m.top.status = "unavailable"
    end try
    closeRaidSockets()
    if m.transfer <> invalid then m.transfer.AsyncCancel()
    m.top.control = "stop"
end sub

function raidWatchCurrent() as boolean
    if m.top.stopRequested then return false
    if get_setting("active_user", "$default$") <> m.top.account then return false
    return get_user_setting("access_token", "") = m.token
end function

function openRaidSocket(url as string) as dynamic
    if not raidSocketUrl(url) then return invalid
    componentType = "roWebSocket"
    socket = CreateObject(componentType)
    if socket = invalid
        m.unsupported = true
        return invalid
    end if
    socket.SetMessagePort(m.port)
    socket.SetCertificatesFile("common:/certs/ca-bundle.crt")
    socket.EnablePeerVerification(true)
    socket.EnableHostVerification(true)
    socket.SetAutoPingReply(true)
    socket.SetUrl(url)
    if socket.Open(5000) then return socket
    socket.Close()
    return invalid
end function

sub closeRaidSockets()
    if m.socket <> invalid then m.socket.Close()
    if m.candidate <> invalid then m.candidate.Close()
    m.socket = invalid
    m.candidate = invalid
end sub

sub runRaidWatch()
    m.token = get_user_setting("access_token", "")
    if m.top.account = "$default$" or not raidString(m.token, 2048) or not raidId(m.top.channelId) then return
    if not raidWatchCurrent() then return
    m.port = CreateObject("roMessagePort")
    m.seen = []
    m.unsupported = false
    failures = 0
    while raidWatchCurrent() and failures < 3
        m.top.status = "connecting"
        m.socket = openRaidSocket("wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30")
        if m.unsupported
            m.top.status = "unavailable"
            return
        end if
        lifetime = CreateObject("roTimespan")
        if m.socket <> invalid then runRaidSession()
        closeRaidSockets()
        if m.terminal then exit while
        if lifetime.TotalMilliseconds() >= 60000 then failures = 0
        failures++
        delay = CreateObject("roTimespan")
        while raidWatchCurrent() and delay.TotalMilliseconds() < failures * 1000
            wait(100, m.port)
        end while
    end while
    m.top.status = "unavailable"
end sub

' Subscription registration shares the socket port so early notifications are
' retained until the HTTP response supplies the subscription ID. No redirects
' or third-party URLs receive credentials.
function subscribeRaid(sessionId as string) as string
    request = CreateObject("roUrlTransfer")
    m.transfer = request
    request.SetMessagePort(m.port)
    request.SetUrl("https://api.twitch.tv/helix/eventsub/subscriptions")
    request.SetCertificatesFile("common:/certs/ca-bundle.crt")
    request.EnablePeerVerification(true)
    request.EnableHostVerification(true)
    request.SetHeaders({ "Authorization": "Bearer " + m.token, "Client-Id": "ue6666qo983tsx6so1t0vnawi233wa", "Content-Type": "application/json" })
    body = { type: "channel.raid", version: "1", condition: { "from_broadcaster_user_id": m.top.channelId }, transport: { method: "websocket", "session_id": sessionId } }
    if not request.AsyncPostFromString(FormatJson(body)) then return ""
    deadline = CreateObject("roTimespan")
    while raidWatchCurrent() and deadline.TotalMilliseconds() < 8000
        event = wait(100, m.port)
        if type(event) = "roUrlEvent" and event.GetSourceIdentity() = request.GetIdentity()
            code = event.GetResponseCode()
            if code = 400 or code = 401 or code = 403 then m.terminal = true
            text = event.GetString()
            if code <> 202 or text.len() > 65536 then exit while
            data = ParseJson(text)
            if GetInterface(data, "ifAssociativeArray") = invalid then exit while
            if GetInterface(data.data, "ifArray") = invalid or data.data.Count() <> 1 then exit while
            subscription = data.data[0]
            if GetInterface(subscription, "ifAssociativeArray") = invalid then exit while
            if raidString(subscription.id) then return subscription.id
            exit while
        else if type(event) = "roWebSocketEvent" and event.GetSocketId() = m.socket.GetSocketId()
            if event.GetType() = 2 or event.GetType() = 3 then exit while
            if event.GetType() = 5 and m.earlyFrames.Count() < 8
                info = event.GetInfo()
                if GetInterface(info, "ifAssociativeArray") <> invalid and raidString(info.text, 65536) then m.earlyFrames.Push(info.text)
            end if
        end if
    end while
    request.AsyncCancel()
    return ""
end function

sub runRaidSession()
    m.terminal = false
    m.subscriptionId = ""
    m.earlyFrames = []
    m.keepaliveMs = 10000
    m.activity = CreateObject("roTimespan")
    while raidWatchCurrent()
        if m.activity.TotalMilliseconds() > m.keepaliveMs then return
        if m.candidate <> invalid and m.migrationClock.TotalMilliseconds() > 10000 then return
        ' Socket events wake this immediately; idle checks need no 10 Hz
        ' registry reads alongside video decoding and chat.
        event = wait(1000, m.port)
        if type(event) <> "roWebSocketEvent" then continue while
        isCurrent = event.GetSocketId() = m.socket.GetSocketId()
        isCandidate = false
        if m.candidate <> invalid then isCandidate = event.GetSocketId() = m.candidate.GetSocketId()
        if not isCurrent and not isCandidate then continue while
        kind = event.GetType()
        if kind = 2 or kind = 3 then return
        if kind <> 5 then continue while
        info = event.GetInfo()
        if GetInterface(info, "ifAssociativeArray") = invalid or not raidString(info.text, 65536) then return
        frame = ParseJson(info.text)
        if GetInterface(frame, "ifAssociativeArray") = invalid then return
        if GetInterface(frame.metadata, "ifAssociativeArray") = invalid then return
        messageType = frame.metadata.message_type
        if messageType = "session_welcome"
            if GetInterface(frame.payload, "ifAssociativeArray") = invalid then return
            session = frame.payload.session
            if GetInterface(session, "ifAssociativeArray") = invalid then return
            if not raidString(session.id) or GetInterface(session.keepalive_timeout_seconds, "ifInt") = invalid then return
            timeout = Val(session.keepalive_timeout_seconds.ToStr())
            if timeout < 10 or timeout > 600 then return
            m.keepaliveMs = (timeout + 1) * 1000
            m.activity.Mark()
            if isCandidate
                m.socket.Close()
                m.socket = m.candidate
                m.candidate = invalid
            else
                if m.subscriptionId <> "" then return
                m.subscriptionId = subscribeRaid(session.id)
                if m.subscriptionId = "" then return
                for each text in m.earlyFrames
                    publishRaidFrame(ParseJson(text))
                end for
                m.earlyFrames = []
            end if
            m.top.status = "listening"
        else if isCurrent and m.subscriptionId <> ""
            if messageType = "notification" or messageType = "session_keepalive" then m.activity.Mark()
            if messageType = "notification"
                publishRaidFrame(frame)
            else if messageType = "revocation"
                m.terminal = true
                return
            else if messageType = "session_reconnect" and m.candidate = invalid
                if GetInterface(frame.payload, "ifAssociativeArray") = invalid then return
                session = frame.payload.session
                if GetInterface(session, "ifAssociativeArray") = invalid then return
                if not raidSocketUrl(session.reconnect_url) then return
                m.candidate = openRaidSocket(session.reconnect_url)
                if m.candidate = invalid then return
                m.migrationClock = CreateObject("roTimespan")
            end if
        end if
    end while
end sub

sub publishRaidFrame(frame as dynamic)
    if not raidWatchCurrent() then return
    raid = raidNotification(frame, m.top.channelId, m.subscriptionId, CreateObject("roDateTime").AsSeconds())
    if raid = invalid then return
    for each id in m.seen
        if id = raid.messageId then return
    end for
    m.seen.Push(raid.messageId)
    if m.seen.Count() > 32 then m.seen.Shift()
    m.top.raid = raid
end sub
