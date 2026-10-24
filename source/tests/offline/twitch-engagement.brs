' @include source/utils/twitchAdCountdown.brs
' @include source/utils/twitchEngagement.brs
sub main()
    state = engagementWatchState()
    state = engagementWatchStep(state, sample(0, 0, 0))
    for i = 1 to 119
        state = engagementWatchStep(state, sample(i, i * 500, i / 2.0))
        if not engagementAssert(not state.due, "a partial minute cannot report") then return
    end for
    state = engagementWatchStep(state, sample(120, 60000, 60))
    if not engagementAssert(state.due and state.minutes = 1 and state.elapsedMs = 0, "one real minute produces one report") then return
    state = engagementWatchStep(state, sample(120, 60000, 60))
    if not engagementAssert(not state.due and state.minutes = 1, "a coalesced or duplicate sample cannot repeat a report") then return

    state = engagementWatchState()
    for i = 0 to 180
        state = engagementWatchStep(state, sample(i, i * 1000, 100))
    end for
    if not engagementAssert(state.minutes = 0 and state.elapsedMs = 0, "a playing-but-stalled Video earns nothing") then return

    state = engagementWatchState()
    state = engagementWatchStep(state, sample(0, 0, 0))
    for i = 1 to 30
        state = engagementWatchStep(state, sample(i, i * 1000, i))
    end for
    paused = sample(31, 31000, 30)
    paused.playing = false
    state = engagementWatchStep(state, paused)
    state = engagementWatchStep(state, sample(32, 120000, 30))
    if not engagementAssert(state.elapsedMs = 30000, "pause and its resume baseline add no time") then return
    for i = 1 to 30
        state = engagementWatchStep(state, sample(32 + i, 120000 + i * 1000, 30 + i))
    end for
    if not engagementAssert(state.due and state.minutes = 1, "actual partial minutes survive an ordinary pause") then return

    state = engagementWatchState()
    state = engagementWatchStep(state, sample(0, 0, 0))
    state = engagementWatchStep(state, sample(1, 1000, 120))
    state = engagementWatchStep(state, sample(2, 2000, 50))
    state = engagementWatchStep(state, sample(3, 40000, 88))
    replaced = sample(4, 41000, 89)
    replaced.generation = 2
    state = engagementWatchStep(state, replaced)
    if not engagementAssert(state.elapsedMs = 0, "seeks, backwards progress, stale gaps and wrapper replacements add no time") then return
    state = engagementWatchStep(state, { sequence: 5, timeMs: 42000, generation: 2, position: "90", playing: true })
    state = engagementWatchStep(state, { sequence: 6, timeMs: 43000, generation: 2, position: 91, playing: true })
    if not engagementAssert(state.elapsedMs = 0, "bad position invalidates the next baseline") then return

    state = engagementWatchState()
    state = engagementWatchStep(state, sample(0, 0, 0))
    for i = 1 to 60
        state = engagementWatchStep(state, sample(i, i * 1000, i * 1.1))
    end for
    if not engagementAssert(state.minutes = 1 and state.elapsedMs = 0, "faster playback cannot create more than wall-clock viewing") then return

    for each id in [invalid, "", "0", "000", "0123", "x", "1.0", "-1", "12345678901234567", 123]
        if not engagementAssert(not engagementId(id), "malformed account/channel/broadcast identifier refused") then return
    end for
    if not engagementAssert(engagementId("320962903648"), "real broadcast IDs remain strings without 32-bit truncation") then return
    if not engagementAssert(engagementSettingsUrl("https://evil.test/config/settings.1234567890abcdef.js") = invalid, "discovery cannot select another settings host") then return
    settings = engagementSettingsUrl("<script src='https://assets.twitch.tv/config/settings.a346c0e26e35ab87386587f3d6bd61f2.js'></script>")
    if not engagementAssert(settings = "https://assets.twitch.tv/config/settings.a346c0e26e35ab87386587f3d6bd61f2.js", "current public discovery shape accepted") then return
    if not engagementAssert(engagementBeaconUrl(chr(34) + "beacon_url" + chr(34) + ":" + chr(34) + "https://evil.test/track" + chr(34)) = invalid, "telemetry cannot redirect to another host") then return
    if not engagementAssert(engagementBeaconUrl(chr(34) + "beacon_url" + chr(34) + ":" + chr(34) + "https://beacon.twitch.tv/track" + chr(34)) = "https://beacon.twitch.tv/track", "current advertised telemetry destination accepted") then return
    body = engagementMinuteBody("4294967297", "472066926", "320962903648", "theburntpeanut", "session", 1)
    if not engagementAssert(body <> invalid and body.left(5) = "data=", "minute event is form encoded") then return
    bytes = createObject("roByteArray")
    bytes.fromBase64String(body.mid(5).replace("%3D", "=").replace("%2B", "+").replace("%2F", "/"))
    payload = parseJson(bytes.toAsciiString())
    if not engagementAssert(payload.count() = 1 and payload[0].event = "minute-watched", "exactly one telemetry event") then return
    properties = payload[0].properties
    if not engagementAssert(properties.user_id = 4294967297& and properties.broadcast_id = "320962903648", "wire payload preserves numeric account IDs above 32 bits and full broadcast identity") then return
    if not engagementAssert(properties.backend = "roku_scenegraph" and properties.live and properties.minutes_logged = 1, "compatibility event identifies the actual backend") then return
    if not engagementAssert(not properties.doesExist("access_token") and not properties.doesExist("device_id"), "no credentials in telemetry") then return

    ' Public viewer response observed on Oct 24 UTC; evaluate at a frozen instant.
    nowSeconds = engagementUtcSeconds("2026-10-24T03:45:00Z")
    execution = { id: "3aa2fce9-007e-4f13-8f9f-b1041acbd7fe", startedAt: "2026-10-24T03:40:35.475576542Z", expiresAt: "2026-10-24T03:48:12.519249618Z", endedAt: invalid, endReason: invalid, progress: { goal: 5300, level: { goal: 12300, value: 3 }, progression: 1000, total: 8000 }, sharedHypeTrainDetails: invalid }
    hype = engagementHypeTrain(execution, nowSeconds)
    if not engagementAssert(hype <> invalid and hype.level = 3 and hype.percent = 18 and hype.status = "active", "real viewer Hype Train progress normalized") then return
    if not engagementAssert(hype.expiresAt - nowSeconds = 192, "provider nanoseconds accepted without extending expiry") then return
    if not engagementAssert(hype.observedAt = nowSeconds, "snapshot freshness records the actual successful fetch time") then return
    if not engagementAssert(engagementHypeTrain(execution, hype.expiresAt) = invalid, "an expired snapshot is hidden") then return
    execution.progress = { goal: 1, level: { value: 3.0 }, progression: 1000000000000# }
    capped = engagementHypeTrain(execution, nowSeconds)
    if not engagementAssert(capped <> invalid and capped.percent = 100 and GetInterface(capped.level, "ifInt") <> invalid, "whole numeric levels normalize and oversized progress caps before integer conversion") then return
    execution.endedAt = "2026-10-24T03:44:55Z"
    hype = engagementHypeTrain(execution, nowSeconds)
    if not engagementAssert(hype <> invalid and hype.status = "ended" and hype.expiresAt = nowSeconds + 15, "an explicit recent end remains visible briefly") then return
    if not engagementAssert(engagementUtcSeconds("2026-02-30T03:45:00Z") = invalid, "invalid provider calendar refused") then return
    snapshot = engagementSnapshot({ data: { user: { id: "472066926", stream: { id: "320962903648" } } } }, "472066926", nowSeconds)
    if not engagementAssert(snapshot <> invalid and snapshot.broadcastId = "320962903648" and snapshot.hypeTrain = invalid, "watch-only metadata does not need Hype Train data") then return
    if not engagementAssert(engagementSnapshot({ errors: [{ message: "failed" }], data: { user: { id: "472066926" } } }, "472066926", nowSeconds) = invalid, "GraphQL errors cannot become valid empty metadata") then return
    if not engagementAssert(engagementSnapshot({ data: { user: { id: "123" } } }, "472066926", nowSeconds) = invalid, "a mismatched channel cannot own a snapshot") then return
    if not checkPinnedSnapshots(nowSeconds) then return
    print "STITCH_TEST_PASS: Twitch engagement"
end sub

function checkPinnedSnapshots(nowSeconds as double) as boolean
    node = pinNode("2026-10-24T03:48:00Z")
    pin = engagementPinnedMessage(node, nowSeconds)
    if not engagementAssert(pin <> invalid and pin.text = "Read this first" and pin.senderName = "Moderator" and pin.messageId = "message-1", "timed viewer pin preserves original author, text and message identity") then return false
    if not engagementAssert(pin.observedAt = nowSeconds and pin.expiresAt = nowSeconds + 180, "pin freshness and provider expiry stay independent") then return false
    node.endsAt = invalid
    pin = engagementPinnedMessage(node, nowSeconds)
    if not engagementAssert(pin <> invalid and pin.expiresAt = invalid, "explicit null expiry supports until-stream-end pins") then return false
    node.delete("endsAt")
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "a missing expiry cannot silently become indefinite") then return false
    node = pinNode("2026-10-24T03:44:59Z")
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "expired pins are withheld") then return false
    node = pinNode("not-a-date")
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "malformed expiry is withheld") then return false
    node = pinNode(invalid)
    node.updatedAt = "2026-10-24T03:46:00Z"
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "future updates are withheld") then return false
    node = pinNode(invalid)
    node.type = "CHEER"
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "paid pins cannot masquerade as moderator pins") then return false
    node = pinNode(invalid)
    message = node.pinnedMessage
    message.content = { text: "" }
    node.pinnedMessage = message
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "empty pins are withheld") then return false
    longText = ""
    for i = 0 to 1500
        longText += "x"
    end for
    message.content = { text: longText }
    node.pinnedMessage = message
    if not engagementAssert(engagementPinnedMessage(node, nowSeconds) = invalid, "oversized pins are withheld") then return false
    body = { data: { channel: { id: "101", pinnedChatMessages: { edges: [{ node: pinNode(invalid) }] } } } }
    snapshot = engagementPinSnapshot(body, "101", nowSeconds)
    if not engagementAssert(snapshot <> invalid and snapshot.pinnedMessage.id = "pin-1", "viewer pin response is flattened at the worker boundary") then return false
    if not engagementAssert(engagementPinSnapshot(body, "102", nowSeconds) = invalid, "a different channel cannot own a pin") then return false
    empty = engagementPinSnapshot({ data: { channel: { id: "101", pinnedChatMessages: { edges: [] } } } }, "101", nowSeconds)
    if not engagementAssert(empty <> invalid and empty.pinnedMessage = invalid, "an explicit empty connection clears an unpinned message") then return false
    for each malformed in [invalid, "bad", {}, { data: "bad" }, { data: {} }, { data: { channel: "bad" } }, { data: { channel: { id: "101", pinnedChatMessages: {} } } }, { errors: [], data: body.data }]
        if not engagementAssert(engagementPinSnapshot(malformed, "101", nowSeconds) = invalid, "malformed pin metadata is a failure rather than a valid empty connection") then return false
    end for
    return true
end function

function pinNode(endsAt as dynamic) as object
    return { id: "pin-1", type: "MOD", startsAt: "2026-10-24T03:44:00Z", updatedAt: "2026-10-24T03:44:00Z", endsAt: endsAt, pinnedMessage: { id: "message-1", sentAt: "2026-10-24T03:43:00Z", content: { text: "Read this first" }, sender: { id: "202", login: "moderator", displayName: "Moderator" } } }
end function

function sample(sequence as integer, timeMs as double, position as double) as object
    return { sequence: sequence, generation: 1, timeMs: timeMs, position: position, playing: true }
end function

function engagementAssert(condition as boolean, description as string) as boolean
    if not condition then print "STITCH_TEST_FAIL: Twitch engagement " + description
    return condition
end function
