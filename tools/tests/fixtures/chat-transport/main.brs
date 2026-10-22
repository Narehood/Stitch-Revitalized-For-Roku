' Native object/time/wait/send and registry boundaries only. Production decisions execute.
sub main()
    m.assertions = 0
    m.failures = 0
    resetBoundary()
    transport = openChatTransport()
    check(transport <> invalid, "writable TCP with stale connected status must be usable")
    if transport <> invalid then check(not transport.secure, "fallback remains anonymous plaintext")
    check(getGlobalAA().socketCloses = 0 and getGlobalAA().waits = 0, "ready socket returns without an eight-second spin")
    check(not getGlobalAA().notifyWrite and getGlobalAA().notifyRead, "ready socket disables writable events and retains readable events")

    resetBoundary()
    getGlobalAA().readyAt = 2
    transport = openChatTransport()
    check(transport <> invalid and getGlobalAA().waits = 2, "pending connection waits for writable readiness")
    check(getGlobalAA().socketCloses = 0, "pending success keeps socket open for bounded login")

    resetBoundary()
    getGlobalAA().readyAt = 99
    transport = openChatTransport()
    check(transport = invalid, "connection deadline rejects never-writable sockets")
    check(getGlobalAA().socketCloses = 1 and getGlobalAA().waits < 9, "deadline closes socket once with bounded waits")

    resetBoundary()
    getGlobalAA().hardError = true
    transport = openChatTransport()
    check(transport = invalid and getGlobalAA().socketCloses = 1, "writable socket with hard error cannot start login")
    check(getGlobalAA().waits = 0, "hard failure does not spin until deadline")

    resetBoundary()
    m.top = { stopRequested: true }
    transport = openChatTransport()
    check(transport = invalid and getGlobalAA().socketCreated = 0, "stopped caller never creates a fallback socket")

    resetBoundary()
    getGlobalAA().readyAt = 99
    getGlobalAA().stopAt = 1
    transport = openChatTransport()
    check(transport = invalid and getGlobalAA().socketCloses = 1 and getGlobalAA().waits = 1, "stop during wait closes socket without retry")

    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    getGlobalAA().webSocketOpened = true
    transport = openChatTransport()
    check(transport <> invalid and transport.secure, "successful WebSocket keeps secure transport")
    check(getGlobalAA().socketCreated = 0 and getGlobalAA().webSocketCloses = 0, "secure success does not create or close a fallback")
    check(getGlobalAA().peerVerified and getGlobalAA().hostVerified and getGlobalAA().certificates, "secure transport retains certificate and peer/host verification")

    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    transport = openChatTransport()
    check(transport <> invalid and not transport.secure, "unavailable WebSocket falls back to usable TCP")
    check(getGlobalAA().webSocketCloses = 1 and getGlobalAA().socketCreated = 1, "failed WebSocket closes before single fallback creation")
    __CONNECTION_TESTS__
    __SEND_TESTS__
    __JOB_TESTS__
    __MODERATION_TESTS__
    if m.failures = 0 then print "__PASS_MARKER__: "; m.assertions; " assertions"
end sub

sub runConnectionTests()
    resetBoundary()
    getGlobalAA().readMode = "pending"
    getGlobalAA().stopAt = 3
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 3, "pending read must allow subsequent welcome and chat packet")
    check(getGlobalAA().waits = 3, "connection respects caller stop after pending/data reads")
    check(getGlobalAA().readSuccess, "later data clears the pending receive status")

    resetBoundary()
    getGlobalAA().readMode = "eof"
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 1 and getGlobalAA().waits = 1, "empty successful receive closes at actual EOF")

    resetBoundary()
    getGlobalAA().readMode = "error"
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 1 and getGlobalAA().waits = 1, "receive hard error ends without spinning")

    resetBoundary()
    m.top = { stopRequested: true }
    socket = fixtureCreateObject("roStreamSocket")
    runChatConnection({ socket: socket, secure: false })
    check(getGlobalAA().receiveCalls = 0 and getGlobalAA().waits = 0, "stopped connection never reads another packet")
end sub

sub runSendTests()
    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    socket = fixtureCreateObject("roWebSocket")
    sent = sendChatLine({ socket: socket, secure: true }, "CAP REQ :twitch.tv/tags")
    check(not sent and getGlobalAA().sendCalls = 1, "invalid secure send must not count as sent")
    check(getGlobalAA().sendTimeout = 1000, "secure send preserves its finite one-second wait")
    check(getGlobalAA().sentText = "CAP REQ :twitch.tv/tags" + chr(13) + chr(10), "secure send passes exactly one framed IRC line")

    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    socket = fixtureCreateObject("roWebSocket")
    check(not loginToChat({ socket: socket, secure: true }), "invalid secure send must fail login before credentials are sent")
    check(getGlobalAA().sendCalls = 1 and getGlobalAA().sentText.instr("oauth:") < 0, "failed CAP aborts login before PASS NICK and JOIN")
    check(getGlobalAA().registryReads = 2, "secure authenticated login reads only its account settings")

    resetBoundary()
    getGlobalAA().clockStep = 10
    getGlobalAA().writeLimit = 4
    socket = fixtureCreateObject("roStreamSocket")
    sent = sendChatLine({ socket: socket, secure: false }, "PONG :fixture")
    check(sent and getGlobalAA().sendCalls > 1, "TCP partial writes must complete the actual line")
    check(getGlobalAA().sentText = "PONG :fixture" + chr(13) + chr(10), "TCP partial writes preserve every byte and final CRLF")

    resetBoundary()
    getGlobalAA().clockStep = 10
    getGlobalAA().sendHardError = true
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "JOIN #canned"), "TCP send hard error fails immediately")
    check(getGlobalAA().sendCalls = 1 and getGlobalAA().sleeps = 0, "TCP hard error never sleeps until the deadline")

    resetBoundary()
    getGlobalAA().clockStep = 100
    getGlobalAA().readyAt = 99
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "PONG :fixture"), "TCP stalled send expires")
    check(getGlobalAA().sendCalls = 0 and getGlobalAA().sleeps > 0 and getGlobalAA().sleeps < 10, "TCP stalled send remains finite")

    resetBoundary()
    m.top.stopRequested = true
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "JOIN #canned"), "stopped TCP send fails without another write")
    check(getGlobalAA().sendCalls = 0, "stopped TCP send never writes")

    resetBoundary()
    getGlobalAA().clockStep = 10
    socket = fixtureCreateObject("roStreamSocket")
    check(loginToChat({ socket: socket, secure: false }), "plaintext login preserves anonymous read-only access")
    check(getGlobalAA().registryReads = 0, "plaintext login never reads account credentials")
    check(getGlobalAA().sentText.instr("PASS SCHMOOPIIE") >= 0 and getGlobalAA().sentText.instr("NICK justinfan") >= 0, "plaintext login uses only anonymous credentials")
    check(getGlobalAA().sentText.instr("oauth:") < 0 and getGlobalAA().sentText.instr("FixtureSentinelA1") < 0, "plaintext login never writes an OAuth token")

    resetBoundary()
    getGlobalAA().clockStep = 10
    socket = fixtureCreateObject("roStreamSocket")
    check(not sendChatLine({ socket: socket, secure: false }, "PONG :fixture" + chr(13) + chr(10) + "JOIN #other"), "IRC line injection fails before sending")
    check(getGlobalAA().sendCalls = 0, "rejected IRC line injection writes no bytes")
end sub

sub runJobTests()
    resetBoundary()
    getGlobalAA().webSocketAvailable = true
    getGlobalAA().webSocketOpened = true
    runChatJob()
    check(m.top.connectionState = "unavailable", "failed login exhausts the actual finite retry budget")
    check(getGlobalAA().sendCalls = 6 and getGlobalAA().webSocketCloses = 6, "failed login closes each of six connection attempts")
    check(m.connectionLifetime = invalid and getGlobalAA().receiveCalls = 0, "failed login never starts the connection loop")
    check(getGlobalAA().sentText.instr("oauth:") < 0 and getGlobalAA().sentText.instr("FixtureSentinelA1") < 0, "failed first send never transmits account credentials")
end sub

' Twitch moderation through the actual parser, connection loop and publisher.
' The socket returns scripted lines; the wait boundary stands in for the renderer.
sub runModerationTests()
    deleted = ircModerationEvent(ircParseMessage("@login=bob;room-id=1;target-msg-id=B2-ID :tmi.twitch.tv CLEARMSG #canned :FixtureDeletedText"))
    check(deleted <> invalid and deleted.kind = "message" and deleted.id = "b2-id", "CLEARMSG targets one normalized message ID")
    check(ircModerationEvent(ircParseMessage("@login=bob;room-id=1 :tmi.twitch.tv CLEARMSG #canned :FixtureDeletedText")) = invalid, "CLEARMSG without a target is ignored")
    room = ircModerationEvent(ircParseMessage("@room-id=1;tmi-sent-ts=1642715695392 :tmi.twitch.tv CLEARCHAT #canned"))
    check(room <> invalid and room.kind = "room", "CLEARCHAT naming nobody clears the room")
    purge = ircModerationEvent(ircParseMessage("@ban-duration=350;room-id=1;target-user-id=202 :tmi.twitch.tv CLEARCHAT #canned :Bob"))
    check(purge <> invalid and purge.kind = "user" and purge.userId = "202" and purge.login = "bob", "CLEARCHAT naming a user purges by ID and login")
    check(ircModerationEvent(ircParseMessage(":tmi.twitch.tv CLEARCHAT #canned :bad login")) = invalid, "a malformed purge target is ignored, never widened to the room")
    check(ircModerationEvent(ircParseMessage("@target-user-id= :tmi.twitch.tv CLEARCHAT #canned")) = invalid, "an empty purge target is ignored, never widened to the room")
    check(ircModerationEvent(ircParseMessage(":a!a@a PRIVMSG #canned :hi")) = invalid, "chat messages are not moderation")
    tagless = ircMessageIdentity(ircParseMessage(":Fallback!fallback@host PRIVMSG #canned :no tags"))
    check(tagless.id = "" and tagless.userId = "" and tagless.login = "fallback", "tagless messages keep only their login identity")
    check(not ircModerationMatches(tagless, { kind: "message", id: "", userId: "", login: "" }), "an absent message ID matches no deletion")
    check(not ircModerationMatches(tagless, { kind: "user", id: "", userId: "", login: "other" }), "a purge of another login keeps the message")
    check(ircModerationMatches(tagless, { kind: "user", id: "", userId: "202", login: "fallback" }), "a purge without a retained user ID falls back to login")
    check(ircModerationMatches(invalid, room) and not ircModerationMatches(invalid, purge), "only a room clear matches a message without identity")

    ' Messages wait behind a 60-second delay while the renderer is busy. Deletion,
    ' purge, unknown and malformed notices arrive; later messages must survive.
    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.clockStep = 10
    state.liveAt = 8
    state.stopAt = 60
    m.top.delaySeconds = 60
    state.script = [
        ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
        privmsg("a1", "101", "alice", "first") + privmsg("b2", "202", "bob", "spam") + privmsg("c3", "303", "carol", "keep")
        "@login=bob;room-id=1;target-msg-id=b2 :tmi.twitch.tv CLEARMSG #canned :FixtureDeletedText" + chr(13) + chr(10) + "@login=x;target-msg-id=ffff-unknown :tmi.twitch.tv CLEARMSG #canned :gone" + chr(13) + chr(10) + ":tmi.twitch.tv CLEARMSG #canned :untargeted" + chr(13) + chr(10) + ":tmi.twitch.tv CLEARCHAT #canned :bad login" + chr(13) + chr(10)
        privmsg("d4", "202", "bob", "again") + privmsg("e5", "404", "dave", "hello") + "@ban-duration=60;room-id=1;target-user-id=202 :tmi.twitch.tv CLEARCHAT #canned :bob" + chr(13) + chr(10)
        privmsg("f6", "202", "bob", "after timeout")
    ]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(state.publishedBeforeLive = 3, "moderation publishes while the renderer is busy and the delay holds every message")
    check(deliveredIds() = "a1,c3,e5,f6", "deleted queued message must never be delivered; purge removes only earlier messages")
    check(stampsEqual(3), "delivered comments carry the moderation they survived")
    events = publishedEvents()
    check(publishedSeq() = 3 and events.count() = 3, "malformed notices publish nothing")
    if events.count() = 3
        check(events[0].kind = "message" and events[0].id = "b2" and events[0].seq = 1, "deletion publishes its message ID first")
        check(events[1].kind = "message" and events[1].id = "ffff-unknown", "an unknown ID still reaches displayed messages harmlessly")
        check(events[2].kind = "user" and events[2].userId = "202" and events[2].login = "bob" and events[2].seq = 3, "purge publishes user ID and login in order")
    end if

    ' A room clear empties the queue; a message after it is delivered.
    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.clockStep = 10
    state.liveAt = 5
    state.stopAt = 30
    m.top.delaySeconds = 60
    state.script = [
        ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
        privmsg("a1", "101", "alice", "first") + privmsg("b2", "202", "bob", "second") + "@room-id=1 :tmi.twitch.tv CLEARCHAT #canned" + chr(13) + chr(10) + privmsg("g7", "505", "erin", "after clear")
    ]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(deliveredIds() = "g7", "room clear removes every queued message and keeps later ones")
    events = publishedEvents()
    check(publishedSeq() = 1 and events.count() = 1 and stampsEqual(1), "room clear is published before later delivery")
    if events.count() = 1 then check(events[0].kind = "room", "room clear publishes a room event")

    ' The published window stays bounded; numbering continues across reconnects.
    resetBoundary()
    state = getGlobalAA()
    state.readMode = "script"
    state.stopAt = 3
    burst = ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
    for index = 1 to 40
        burst += "@target-msg-id=m" + index.toStr() + " :tmi.twitch.tv CLEARMSG #canned :x" + chr(13) + chr(10)
    end for
    state.script = [burst]
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    events = publishedEvents()
    check(m.moderationLog.count() = 32 and events.count() = 32 and publishedSeq() = 40, "the moderation window holds the latest 32 events")
    if events.count() = 32 then check(events[0].seq = 9 and events[0].id = "m9" and events[31].id = "m40", "the window drops only the oldest events")
    state.receiveCalls = 0
    state.waits = 0
    state.readMode = "script"
    state.script = ["@target-msg-id=late :tmi.twitch.tv CLEARMSG #canned :x" + chr(13) + chr(10)]
    m.top.stopRequested = false
    runChatConnection({ socket: fixtureCreateObject("roStreamSocket"), secure: false })
    check(publishedSeq() = 41 and m.moderationLog.count() = 32, "a reconnect continues numbering instead of repeating applied sequences")
end sub

function privmsg(id as string, userId as string, login as string, text as string) as string
    return "@display-name=" + login + ";id=" + id + ";user-id=" + userId + " :" + login + "!" + login + "@" + login + ".tmi.twitch.tv PRIVMSG #canned :" + text + chr(13) + chr(10)
end function

' Stands in for Chat.onNewCommentObj: records each delivery and acknowledges it.
sub scriptedRenderer(state as object)
    if state.waits < state.liveAt and m.top.moderation <> invalid then state.publishedBeforeLive = m.top.moderation.seq
    if m.top.nextCommentObj <> invalid
        delivered = state.delivered
        delivered.push(m.top.nextCommentObj)
        state.delivered = delivered
        m.top.nextCommentObj = invalid
        m.top.readyForNextComment = true
    end if
    if state.waits = state.liveAt
        m.top.forceLive = true
        m.top.readyForNextComment = true
    end if
    if state.waits >= state.stopAt then m.top.stopRequested = true
end sub

function publishedEvents() as object
    if m.top.moderation = invalid then return []
    return m.top.moderation.events
end function

function publishedSeq() as integer
    if m.top.moderation = invalid then return 0
    return m.top.moderation.seq
end function

function deliveredIds() as string
    ids = []
    for each comment in getGlobalAA().delivered
        ids.push(comment.identity.id)
    end for
    return ids.join(",")
end function

function stampsEqual(seq as integer) as boolean
    delivered = getGlobalAA().delivered
    if delivered.count() = 0 then return false
    for each comment in delivered
        if comment.moderationSeq <> seq then return false
    end for
    return true
end function

sub resetBoundary()
    m.top = { stopRequested: false, readyForNextComment: false, delaySeconds: 0, forceLive: false, channel: "canned", connectionState: "connecting" }
    m.port = invalid
    m.anonymousOnly = false
    m.moderationSeq = 0
    m.moderationLog = []
    state = getGlobalAA()
    state.socketCreated = 0
    state.socketCloses = 0
    state.webSocketCloses = 0
    state.webSocketAvailable = false
    state.webSocketOpened = false
    state.clock = 0
    state.clockStep = 1000
    state.waits = 0
    state.readyAt = 0
    state.stopAt = 99
    state.hardError = false
    state.notifyRead = false
    state.notifyWrite = true
    state.peerVerified = false
    state.hostVerified = false
    state.certificates = false
    state.readMode = ""
    state.receiveCalls = 0
    state.readSuccess = false
    state.sendCalls = 0
    state.sendTimeout = 0
    state.sentText = ""
    state.sendHardError = false
    state.writeLimit = 4096
    state.sleeps = 0
    state.registryReads = 0
    state.script = []
    state.liveAt = 0
    state.delivered = []
    state.publishedBeforeLive = 0
end sub

function fixtureCreateObject(name as string) as dynamic
    state = getGlobalAA()
    if name = "roWebSocket"
        if not state.webSocketAvailable then return invalid
        return {
            setMessagePort: noop
            setCertificatesFile: setCertificates
            enablePeerVerification: peerVerification
            enableHostVerification: hostVerification
            setAutoPingReply: noop
            setUrl: noop
            open: openWebSocket
            send: sendData
            close: closeWebSocket
        }
    else if name = "roStreamSocket"
        state.socketCreated++
        return {
            setMessagePort: noop
            setSendToAddress: noop
            notifyReadable: notifyRead
            notifyWritable: notifyWrite
            connect: accepted
            isConnected: staleConnected
            isWritable: writable
            eOK: okay
            eSuccess: receiveSuccess
            isReadable: accepted
            getCountRcvBuf: emptyCount
            receiveStr: receiveData
            send: sendData
            close: closeSocket
        }
    else if name = "roSocketAddress"
        return { setAddress: noop }
    else if name = "roTimespan"
        return { totalMilliseconds: elapsed, mark: markClock }
    else if name = "roByteArray" or name = "roMessagePort"
        return createObject(name)
    end if
    print "STITCH_CHAT_TRANSPORT_FAIL: unexpected object " + name
    return invalid
end function

sub fixtureSleep(milliseconds as integer)
    getGlobalAA().sleeps++
end sub

function sendData(data as dynamic, first as integer, length = -1 as integer) as dynamic
    state = getGlobalAA()
    state.sendCalls++
    if length < 0
        state.sendTimeout = first
        state.sentText += data
        return invalid
    end if
    if state.sendHardError
        state.hardError = true
        return 0
    end if
    written = length
    if written > state.writeLimit then written = state.writeLimit
    state.sentText += data.toAsciiString().mid(first, written)
    return written
end function

function get_user_setting(key as string, fallback as dynamic) as string
    getGlobalAA().registryReads++
    if key = "login" then return "fixtureuser"
    if key = "access_token" then return "FixtureSentinelA1"
    return fallback
end function

function fixtureWait(milliseconds as integer, port as dynamic) as dynamic
    state = getGlobalAA()
    state.waits++
    if state.readMode = "script"
        scriptedRenderer(state)
        return invalid
    end if
    if state.waits >= state.stopAt then m.top = { stopRequested: true, readyForNextComment: false, delaySeconds: 0, forceLive: false }
    return invalid
end function

sub noop(value as dynamic)
end sub

function accepted() as boolean
    return true
end function

function staleConnected() as boolean
    return false
end function

function writable() as boolean
    state = getGlobalAA()
    return state.waits >= state.readyAt
end function

function okay() as boolean
    return not getGlobalAA().hardError
end function

function emptyCount() as integer
    return 0
end function

function receiveSuccess() as boolean
    return getGlobalAA().readSuccess
end function

function receiveData(limit as integer) as string
    state = getGlobalAA()
    state.receiveCalls++
    state.readSuccess = false
    if state.readMode = "script"
        ' Past the script every read is EAGAIN, never EOF.
        if state.receiveCalls > state.script.count() then return ""
        state.readSuccess = true
        return state.script[state.receiveCalls - 1]
    end if
    if state.readMode = "error"
        state.hardError = true
        return ""
    end if
    if state.readMode = "pending" and state.receiveCalls = 1 then return ""
    state.readSuccess = true
    if state.readMode = "eof" then return ""
    if state.receiveCalls = 2 then return ":tmi.twitch.tv 001 justinfan12345 :Welcome" + chr(13) + chr(10)
    return "@display-name=FixtureUser :fixtureuser!fixtureuser@fixtureuser.tmi.twitch.tv PRIVMSG #canned :hello" + chr(13) + chr(10)
end function

sub notifyRead(value as boolean)
    getGlobalAA().notifyRead = value
end sub

sub notifyWrite(value as boolean)
    getGlobalAA().notifyWrite = value
end sub

sub closeSocket()
    getGlobalAA().socketCloses++
end sub

sub closeWebSocket()
    getGlobalAA().webSocketCloses++
end sub

function elapsed() as integer
    state = getGlobalAA()
    state.clock += state.clockStep
    return state.clock
end function

sub markClock()
    getGlobalAA().clock = 0
end sub

function openWebSocket(timeout as integer) as boolean
    return getGlobalAA().webSocketOpened
end function

sub setCertificates(value as string)
    getGlobalAA().certificates = value = "common:/certs/ca-bundle.crt"
end sub

sub peerVerification(value as boolean)
    getGlobalAA().peerVerified = value
end sub

sub hostVerification(value as boolean)
    getGlobalAA().hostVerified = value
end sub

sub check(condition as boolean, description as string)
    m.assertions++
    if not condition
        m.failures++
        print "STITCH_CHAT_TRANSPORT_FAIL: " + description
    end if
end sub
