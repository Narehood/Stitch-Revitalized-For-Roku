sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: { ChatOption: "false", ChatFontSize: "16", "playback.lowLatency": "true" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.createScene("RokuPlayerHost")
    m.screen.show()
    testLateBindingAndOrdinaryPaths()
    testChoiceReadyAndBack()
    testCancelledStartAndDisposal()
    testDirectSwitch()
    testRepeatedRetainedQualityChoices()
    testQualityRecoveryLadder()
    testMixedAutomaticRecoveryChoice()
    testFailedRetryAndRecovery()
    testRefusalAndBlockedOwner()
    testDialogBackAndAttachRefusal()
    testCleanupFailureWhileWaiting()
    testBlockedCancelledReplacement()
    check(true, "failure-control anchor")
    fixtureEnd()
end sub

sub testMixedAutomaticRecoveryChoice()
    for each mode in ["buffer", "decode"]
        player = openPlayer("LIVE")
        session = sessionOf(player)
        metadata = [
            content("direct", "Automatic").getFields()
            content("roku-demux", "1080p60").getFields()
            content("direct", "720p60").getFields()
            content("roku-demux", "480p30").getFields()
        ]
        deliver(player, content("direct", "Automatic"), metadata)
        original = player.callFunc("fixtureRead").video
        if mode = "buffer"
            for checkNumber = 1 to 6
                player.callFunc("fixtureProlongedBufferCheck")
            end for
        else
            original.errorCode = 9
            original.errorStr = "fixture media decode error"
            original.state = "error"
        end if
        settle(40)
        check(player.content.QualityID = "480p30" and player.content.localPlaybackDescriptor.qualityId = "480p30", mode + " mixed-Automatic recovery retains the exact lower local descriptor")
        check(not player.callFunc("fixtureRead").chosen and calls(session, "start").count() = 0 and original.control = "stop", mode + " recovery waits for explicit Roku opt-in before starting local playback")
        chooseRoku(player)
        started = calls(session, "start")
        check(started.count() = 1 and started[0].descriptor.qualityId = "480p30", mode + " actual Try on Roku choice starts only the selected lower descriptor")
        ready(session, player.callFunc("fixtureRead").sessionId)
        video = player.callFunc("fixtureRead").video
        check(video.control = "play" and video.selectedQuality = "480p30" and video.content.localPlaybackDescriptor.qualityId = "480p30", mode + " opted-in mixed recovery plays the preserved lower selection")
        closePlayer(player)
    end for
end sub

function recoveryMetadata() as object
    return [
        { QualityID: "Automatic", url: "http://fixture.invalid/master", playbackTransport: "direct" }
        { QualityID: "1080p60", url: "http://fixture.invalid/1080p60", playbackTransport: "direct" }
        { QualityID: "720p60", url: "http://fixture.invalid/720p60", playbackTransport: "direct" }
        { QualityID: "480p30", url: "http://fixture.invalid/480p30", playbackTransport: "direct" }
    ]
end function

sub testQualityRecoveryLadder()
    for each mode in ["buffer", "decode"]
        for each quality in ["Automatic", "720p60", "480p30"]
            player = openPlayer("LIVE")
            metadata = recoveryMetadata()
            selected = content("direct", quality)
            deliver(player, selected, metadata)
            original = player.callFunc("fixtureRead").video
            expected = 3
            if quality = "480p30" then expected = invalid
            check(sameValue(player.callFunc("fixtureLowerQuality"), expected), mode + " actual lower-quality helper respects " + quality)

            if mode = "buffer"
                for checkNumber = 1 to 5
                    player.callFunc("fixtureProlongedBufferCheck")
                end for
                check(player.callFunc("fixtureRead").video.isSameNode(original) and player.callFunc("fixtureRead").recovery = 0, "five prolonged checks preserve " + quality + " playback before recovery")
                player.callFunc("fixtureProlongedBufferCheck")
                settle(40)
            else
                original.errorCode = 9
                original.errorStr = "fixture media decode error"
                original.state = "error"
                settle(40)
            end if

            video = player.callFunc("fixtureRead").video
            check(player.content.QualityID = "480p30" and video.selectedQuality = "480p30", mode + " recovery never promotes " + quality + " to the highest rung")
            if expected <> invalid
                check(not video.isSameNode(original) and player.content.url = metadata[3].url and player.callFunc("fixtureRead").recovery = 1, mode + " recovery plays the exact lowest metadata URL using one bounded attempt")
            else
                check(video.isSameNode(original) and player.content.url = selected.url, mode + " lowest rung has no lower quality replacement")
                if mode = "decode" then check(player.callFunc("fixtureRead").retryTimer <> invalid, "lowest decode failure keeps the existing bounded retry path")
                if mode = "buffer" then check(player.callFunc("fixtureRead").recovery = 0, "lowest buffering consumes no quality recovery attempt")
            end if
            closePlayer(player)
        end for
    end for

    ' Roku Automatic retains the exact fixed rendition in its descriptor.
    ' Use that rung as the baseline instead of the Automatic option index.
    player = openPlayer("LIVE")
    session = sessionOf(player)
    metadata = []
    for each quality in ["1080p60", "720p60", "480p30"]
        metadata.push(content("roku-demux", quality).getFields())
    end for
    fixed = content("roku-demux", "720p60")
    fixed.QualityID = "Automatic"
    metadata.unshift(fixed.getFields())
    deliver(player, fixed, metadata)
    chooseRoku(player)
    ready(session, player.callFunc("fixtureRead").sessionId)
    check(player.callFunc("fixtureLowerQuality") = 3, "fixed Automatic lowers below its actual 720 descriptor")
    recovery = player.callFunc("fixtureDecodeRecovery")
    check(recovery.shouldRetry and recovery.action = "change_quality" and recovery.newContent.index = 3 and recovery.newContent.qualityID = "480p30", "actual decode recovery planner lowers fixed Automatic below its retained rendition")
    for checkNumber = 1 to 6
        player.callFunc("fixtureProlongedBufferCheck")
    end for
    started = calls(session, "start")
    check(started.count() = 2 and started[1].descriptor.qualityId = "480p30" and player.content.QualityID = "480p30", "sixth actual fixed-Automatic buffer check starts the truly lower descriptor")
    closePlayer(player)

    for each fixedLowest in [false, true]
        player = openPlayer("LIVE")
        selected = content("direct", "Automatic")
        metadata = [selected.getFields(), content().getFields()]
        if fixedLowest
            selected.localPlaybackDescriptor = content("roku-demux", "480p30").localPlaybackDescriptor
            metadata = recoveryMetadata()
        end if
        deliver(player, selected, metadata)
        check(player.callFunc("fixtureLowerQuality") = invalid, "single concrete or fixed-lowest Automatic offers no verified lower rung")
        recovery = player.callFunc("fixtureDecodeRecovery")
        check(recovery.action = "retry" and recovery.newContent = invalid, "single concrete or fixed-lowest decode recovery never invents a lower rung")
        original = player.callFunc("fixtureRead").video
        for checkNumber = 1 to 6
            player.callFunc("fixtureProlongedBufferCheck")
        end for
        check(player.callFunc("fixtureRead").video.isSameNode(original) and player.callFunc("fixtureRead").recovery = 0 and player.content.QualityID = "Automatic", "Automatic with no lower rung keeps its current content and recovery budget")
        closePlayer(player)
    end for
end sub

function qualityFlagEvent(port as object) as dynamic
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 1000
        event = wait(20, port)
        if type(event) = "roSGNodeEvent"
            if event.getData() = true then return event
        end if
    end while
    return invalid
end function

sub testRepeatedRetainedQualityChoices()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    metadata = []
    for each quality in ["1080p60", "720p60", "480p30"]
        item = content("roku-demux", quality).getFields()
        metadata.push(item)
    end for
    deliver(player, content("roku-demux"), metadata)
    chooseRoku(player)
    originalId = player.callFunc("fixtureRead").sessionId
    ready(session, originalId)
    video = player.callFunc("fixtureRead").video
    flagPort = createObject("roMessagePort")
    video.observeField("QualityChangeRequestFlag", flagPort)
    requestPort = createObject("roMessagePort")
    video.observeField("QualityChangeRequest", requestPort)

    ' The engine cannot focus a child StandardMessageDialog. Its real
    ' buttonSelected field still invokes the unchanged wrapper handler.
    video.findNode("QualityDialog").buttonSelected = 1
    settle(60)
    firstEvent = wait(1000, requestPort)
    firstId = player.callFunc("fixtureRead").sessionId
    started = calls(session, "start")
    check(type(firstEvent) = "roSGNodeEvent" and firstEvent.getData() = 1, "first actual dialog pick emits its selected request index")
    check(firstId <> originalId and started.count() = 2 and started[1].descriptor.qualityId = "720p60", "first pick starts the exact 720 descriptor")
    check(player.callFunc("fixtureRead").video.isSameNode(video) and not video.QualityChangeRequestFlag, "consuming the first choice clears the flag on the same retained wrapper")

    video.findNode("QualityDialog").buttonSelected = 2
    settle(60)
    secondEvent = wait(1000, requestPort)
    secondId = player.callFunc("fixtureRead").sessionId
    started = calls(session, "start")
    secondDelivered = false
    if type(secondEvent) = "roSGNodeEvent" then secondDelivered = secondEvent.getData() = 2 and secondEvent.getRoSGNode().isSameNode(video)
    check(secondDelivered, "a second distinct pick on the retained wrapper delivers another actual event")
    check(player.callFunc("fixtureRead").video.isSameNode(video) and secondId <> firstId and started.count() = 3 and started[2].descriptor.qualityId = "480p30", "same retained wrapper starts the second exact 480 descriptor")
    check(not video.QualityChangeRequestFlag, "consuming the second choice also clears its retained-wrapper flag")
    check(player.content.QualityID = "480p30" and video.selectedQuality = "480p30", "second selection preserves its metadata index and selected label")

    video.QualityChangeRequestFlag = false
    settle(40)
    check(calls(session, "start").count() = 3, "a false flag notification is not a quality command")
    ready(session, firstId)
    check(player.callFunc("fixtureRead").video.isSameNode(video), "superseded first-choice ready cannot replace the retained wrapper")
    ready(session, secondId)
    replacement = player.callFunc("fixtureRead").video
    check(not replacement.isSameNode(video) and replacement.selectedQuality = "480p30" and replacement.control = "play", "only the latest exact selection publishes and plays")
    ' brs-engine dispatches the port observer after the parent clears a flag,
    ' so the queued flag notifications read false. The request index events
    ' above are stable; exact start calls prove both commands were consumed.
    ' After replacement the old node has no parent observer, letting us keep
    ' an actual true flag event to exercise the source guard without a fake.
    video.observeField("QualityChangeRequestFlag", flagPort)
    video.QualityChangeRequestFlag = true
    staleEvent = qualityFlagEvent(flagPort)
    check(type(staleEvent) = "roSGNodeEvent" and staleEvent.getData() and staleEvent.getRoSGNode().isSameNode(video), "old detached wrapper supplies a real true flag event for the source guard")
    player.callFunc("fixtureQualityEvent", staleEvent)
    check(calls(session, "start").count() = 3 and player.callFunc("fixtureRead").video.isSameNode(replacement), "an actual old-wrapper event cannot restart its replacement")
    player.callFunc("onDestroy")
    oldRequest = video.QualityChangeRequest
    oldQuality = video.selectedQuality
    video.findNode("QualityDialog").buttonSelected = 0
    player.callFunc("fixtureQualityEvent", staleEvent)
    player.callFunc("fixtureQualityEvent")
    check(video.QualityChangeRequest = oldRequest and video.selectedQuality = oldQuality and calls(session, "start").count() = 3, "disposed wrapper and player reject late selections and quality callbacks")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
    m.scene.localPlaybackSession = invalid
end sub

sub testBlockedCancelledReplacement()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    originalId = player.callFunc("fixtureRead").sessionId
    ready(session, originalId)
    player.callFunc("fixtureReconnect")
    player.callFunc("fixtureRead").reconnectTask.response = content("roku-demux")
    settle(60)
    pendingId = player.callFunc("fixtureRead").sessionId
    check(pendingId <> originalId and player.callFunc("fixtureRead").pendingContent <> invalid, "replacement descriptor has a distinct pending owned identity")
    session.cleanupBlocked = true
    session.event = { id: originalId, status: "failed" }
    settle(40)
    check(m.scene.dialog = invalid, "failed former current ID cannot act on the player's pending replacement")
    session.event = { id: pendingId, status: "cancelled" }
    settle(60)
    check(m.scene.dialog <> invalid and m.scene.dialog.buttons.count() = 1 and m.scene.dialog.buttons[0] = "Back", "matching cancelled pending ID reports cleanup blockage without retry")
    state = player.callFunc("fixtureRead")
    check(state.pendingContent = invalid and state.prepared = invalid and not state.deferred and session.busy, "blocked cancelled replacement clears pending playback without fabricating manager cleanup")
    check(state.sessionId = pendingId and calls(session, "attach").count() = 1, "blocked cancellation retains owned ID and never attaches the pending wrapper")
    closePlayer(player)
end sub

sub testDialogBackAndAttachRefusal()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    press("down")
    press("ok")
    settle(180)
    check(player.backPressed and player.state = "done" and m.scene.dialog = invalid, "the combined-format dialog's actual Back button leaves the player")
    check(calls(session, "start").count() = 0 and calls(session, "stop").count() = 0, "dialog Back never starts or stops an empty session")
    closePlayer(player)

    player = openPlayer("LIVE")
    session = sessionOf(player)
    session.allowAttach = false
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    ready(session, id)
    attached = calls(session, "attach")
    video = player.callFunc("fixtureRead").video
    check(attached.count() = 1 and not attached[0].allowed and attached[0].contentEmpty, "the actual wrapper is presented once to an explicit attach refusal")
    check(video.control <> "play" and video.content = invalid and m.scene.dialog <> invalid, "failed attach never assigns media or starts wrapper playback")
    stopped = calls(session, "stop")
    check(stopped.count() = 1 and stopped[0].id = id, "failed attach requests owned-session cleanup")
    closePlayer(player)
end sub

function request(kind as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ contentType: kind, contentId: "fixture-v1", streamerLogin: "fixturechannel", streamerDisplayName: "Fixture Channel", streamerId: "42", contentTitle: "Fixture title" })
    return node
end function

function content(transport = "direct" as string, quality = "1080p60" as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ url: "http://fixture.invalid/" + quality, QualityID: quality, streamFormat: "hls", contentTitle: "Fixture title", streamerDisplayName: "Fixture Channel", contentId: "fixture-v1", playbackTransport: transport })
    if transport = "roku-demux"
        node.isTransmux = true
        node.localPlaybackDescriptor = { qualityId: quality, mediaUrl: "https://fixture.invalid/combined.m3u8", bandwidth: 8000000, isHD: true, fixtureIdentity: "original-descriptor" }
    else if transport = "python"
        node.isTransmux = true
        node.isProxied = true
        node.ForwardQueryStringParams = false
    else if transport = "combined"
        node.isTransmux = true
    end if
    return node
end function

function openPlayer(kind as string, withOwner = true as boolean) as object
    m.scene.dialog = invalid
    session = invalid
    if withOwner then session = createObject("roSGNode", "SessionBoundary")
    m.scene.localPlaybackSession = invalid
    player = createObject("roSGNode", "VideoPlayer")
    check(player.callFunc("fixtureRead").session = invalid, "init without a scene owner leaves the session unbound")
    m.scene.localPlaybackSession = session
    m.scene.appendChild(player)
    player.setFocus(true)
    player.contentRequested = request(kind)
    settle(40)
    check(player.callFunc("fixtureRead").task <> invalid, "a real contentRequested callback creates a content task")
    return player
end function

sub closePlayer(player as object)
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
    m.scene.dialog = invalid
    m.scene.localPlaybackSession = invalid
end sub

function sessionOf(player as object) as dynamic
    return player.callFunc("fixtureRead").session
end function

sub deliver(player as object, node as object, metadata = invalid as dynamic)
    task = player.callFunc("fixtureRead").task
    task.metadata = metadata
    task.response = node
    settle(60)
end sub

function calls(session as object, action as string) as object
    result = []
    for each item in session.calls
        if item.action = action then result.push(item)
    end for
    return result
end function

sub chooseRoku(player as object)
    dialog = m.scene.dialog
    check(dialog <> invalid and dialog.buttons.count() = 2 and dialog.buttons[0] = "Try on Roku" and dialog.buttons[1] = "Back", "eligible combined stream offers Try on Roku and Back")
    press("ok")
    settle(160)
    check(player.callFunc("fixtureRead").transmuxDialog = invalid, "the actual remote choice closes its owned combined-format dialog")
end sub

sub ready(session as object, id as string)
    session.event = { id: id, status: "ready", url: "http://127.0.0.1:49371/master.m3u8", metadata: { isHD: true, bandwidth: 8000000 } }
    settle(60)
end sub

sub testLateBindingAndOrdinaryPaths()
    for each kind in ["LIVE", "VOD", "CLIP"]
        player = openPlayer(kind)
        session = sessionOf(player)
        check(session <> invalid and session.isSameNode(m.scene.localPlaybackSession), "handleContent binds the scene owner after attachment")
        check(player.callFunc("fixtureRead").task.enableRokuDemux = (kind = "LIVE"), "only LIVE opts the fetch task into descriptor eligibility")
        direct = content()
        deliver(player, direct)
        video = player.callFunc("fixtureRead").video
        check(video <> invalid and video.control = "play", "ordinary playback creates and plays its actual wrapper")
        expected = "CustomVideo"
        if kind = "LIVE" then expected = "StitchVideo"
        check(video.subtype() = expected and video.content.url = direct.url, "ordinary LIVE/VOD/CLIP retains wrapper and original URL")
        check(calls(session, "start").count() = 0 and calls(session, "attach").count() = 0, "ordinary paths never start or attach a local session")
        closePlayer(player)
        check(calls(session, "stop").count() = 0, "ordinary destruction never stops an empty session ID")
    end for
    player = openPlayer("LIVE", false)
    check(not player.callFunc("fixtureRead").task.enableRokuDemux, "missing scene owner leaves LIVE descriptor opt-in off")
    deliver(player, content("combined"))
    check(m.scene.dialog.buttons.count() = 1 and m.scene.dialog.buttons[0] = "Back", "combined stream without owner keeps audio-service Back-only fallback")
    closePlayer(player)
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("python"))
    check(m.scene.dialog = invalid and player.callFunc("fixtureRead").video.control = "play", "Python proxied combined content follows ordinary playback without opt-in")
    check(player.content.isProxied and not player.content.ForwardQueryStringParams and calls(session, "start").count() = 0, "optional service flags remain intact")
    closePlayer(player)
end sub

sub testChoiceReadyAndBack()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    original = content("roku-demux")
    deliver(player, original)
    check(player.callFunc("fixtureRead").video = invalid and calls(session, "start").count() = 0, "descriptor alone never starts experimental playback")
    chooseRoku(player)
    started = calls(session, "start")
    check(started.count() = 1 and started[0].descriptor.fixtureIdentity = "original-descriptor", "explicit choice starts exactly one session with the retained descriptor")
    id = started[0].id
    player.callFunc("fixtureChoiceAgain")
    player.control = "play"
    settle(40)
    check(calls(session, "start").count() = 1, "duplicate dialog/control choices do not duplicate pending start")
    ready(session, "stale-id")
    check(player.callFunc("fixtureRead").video = invalid and calls(session, "attach").count() = 0, "a stale ready event cannot publish or play")
    ready(session, id)
    video = player.callFunc("fixtureRead").video
    attached = calls(session, "attach")
    check(video <> invalid and attached.count() = 1 and attached[0].id = id and attached[0].node.isSameNode(video), "matching ready attaches the real wrapper to the exact session")
    check(attached[0].contentEmpty and attached[0].control <> "play", "attachment occurs before wrapper content assignment and play")
    check(video.control = "play" and video.content.url = "http://127.0.0.1:49371/master.m3u8", "matching ready publishes and plays only the local URL")
    check(player.content.StreamUrls.count() = 1 and player.content.StreamUrls[0] = "http://127.0.0.1:49371/master.m3u8", "actual supported StreamUrls contains only the local rendition")
    check(player.content.localPlaybackDescriptor.fixtureIdentity = "original-descriptor" and player.content.localPlaybackDescriptor.mediaUrl = original.localPlaybackDescriptor.mediaUrl, "local playable content retains the original descriptor")
    check(player.content.QualityID = "1080p60" and video.selectedQuality = "1080p60", "local playable content and wrapper retain selected quality")
    check(not player.content.isTransmux and not player.content.isProxied and not player.content.ForwardQueryStringParams, "local route disables external proxy/transmux/query-forwarding flags")
    check(video.suppressStartupSeek, "local playback suppresses the experimental live-edge seek even when its preference is enabled")
    check(player.content.playbackNotice.instr("1080p60") >= 0, "local playback notice includes its fixed quality")
    player.callFunc("fixtureEventAgain")
    ready(session, id)
    check(calls(session, "attach").count() = 1 and player.callFunc("fixtureRead").video.isSameNode(video), "duplicate ready events never create or attach another wrapper")
    player.callFunc("fixtureBack")
    settle(40)
    check(player.callFunc("fixtureRead").exitPending and not player.backPressed and player.state <> "done", "Back waits while the modeled manager remains busy")
    stopCalls = calls(session, "stop")
    check(stopCalls.count() > 0 and stopCalls[stopCalls.count() - 1].id = id, "Back requests stop only for the player's own ID")
    ready(session, id)
    check(calls(session, "attach").count() = 1, "late ready during Back cannot restart playback")
    session.busy = false
    settle(40)
    check(player.backPressed and player.state = "done" and player.callFunc("fixtureRead").sessionId = "", "busy false acknowledges cleanup and completes Back")
    before = calls(session, "stop").count()
    closePlayer(player)
    check(calls(session, "stop").count() = before, "destruction after acknowledged Back never stops an empty ID")
end sub

sub testCleanupFailureWhileWaiting()
    for each mode in ["back", "direct"]
        player = openPlayer("LIVE")
        session = sessionOf(player)
        metadata = [{ QualityID: "1080p60", url: "http://fixture.invalid/combined", isTransmux: true, playbackTransport: "roku-demux", localPlaybackDescriptor: content("roku-demux").localPlaybackDescriptor }, { QualityID: "720p60", url: "http://fixture.invalid/direct720", isTransmux: false, playbackTransport: "direct" }]
        deliver(player, content("roku-demux"), metadata)
        chooseRoku(player)
        id = player.callFunc("fixtureRead").sessionId
        ready(session, id)
        if mode = "back"
            player.callFunc("fixtureBack")
        else
            video = player.callFunc("fixtureRead").video
            video.QualityChangeRequest = 1
            video.QualityChangeRequestFlag = true
        end if
        session.cleanupBlocked = true
        session.event = { id: id, status: "failed" }
        settle(60)
        dialog = m.scene.dialog
        check(dialog <> invalid, "cleanup failure during " + mode + " wait remains visible and actionable")
        if dialog <> invalid
            check(dialog.buttons.count() = 1 and dialog.buttons[0] = "Back", "failed cleanup offers no false retry")
            text = ""
            for each part in dialog.message
                text += part
            end for
            check(lcase(text).instr("restart stitch") >= 0, "failed cleanup explains the required restart")
        end if
        check(session.busy and not player.backPressed and player.state <> "done", "failed cleanup never fabricates an acknowledgment")
        check(not player.callFunc("fixtureRead").deferred, "failed cleanup cancels deferred direct playback")
        closePlayer(player)
    end for
end sub

sub testCancelledStartAndDisposal()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    player.callFunc("fixtureBack")
    ready(session, id)
    check(player.callFunc("fixtureRead").video = invalid and calls(session, "attach").count() = 0, "cancelled start ignores its later ready event")
    session.busy = false
    settle(40)
    check(player.backPressed, "cancelled start completes Back only on manager acknowledgment")
    closePlayer(player)

    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    player.callFunc("onDestroy")
    stops = calls(session, "stop")
    check(stops.count() = 1 and stops[0].id = id, "permanent disposal stops precisely its nonempty owned session")
    ready(session, id)
    session.busy = false
    player.callFunc("fixtureEventAgain")
    player.callFunc("fixtureRetry")
    settle(40)
    check(player.callFunc("fixtureRead").disposed and player.callFunc("fixtureRead").video = invalid and calls(session, "attach").count() = 0, "disposed player ignores stale events and explicit retry")
    player.callFunc("onDestroy")
    check(calls(session, "stop").count() = 1, "permanent destruction is idempotent")
    m.scene.removeChild(player)
    m.scene.localPlaybackSession = invalid
end sub

sub testDirectSwitch()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    metadata = [{ QualityID: "1080p60", url: "http://fixture.invalid/combined", isTransmux: true, playbackTransport: "roku-demux", localPlaybackDescriptor: content("roku-demux").localPlaybackDescriptor }, { QualityID: "720p60", url: "http://fixture.invalid/direct720", isTransmux: false, playbackTransport: "direct", isProxied: false, ForwardQueryStringParams: true }]
    deliver(player, content("roku-demux"), metadata)
    chooseRoku(player)
    id = player.callFunc("fixtureRead").sessionId
    ready(session, id)
    video = player.callFunc("fixtureRead").video
    video.QualityChangeRequest = 1
    video.QualityChangeRequestFlag = true
    settle(60)
    check(player.callFunc("fixtureRead").deferred and player.callFunc("fixtureRead").video.isSameNode(video), "switch to direct quality waits for local owner cleanup")
    ready(session, id)
    check(player.callFunc("fixtureRead").video.isSameNode(video), "stale local ready cannot override the pending direct quality")
    session.busy = false
    settle(60)
    direct = player.callFunc("fixtureRead").video
    check(not direct.isSameNode(video) and direct.content.url = "http://fixture.invalid/direct720" and direct.selectedQuality = "720p60", "cleanup acknowledgment recreates direct playback at selected quality")
    check(player.callFunc("fixtureRead").sessionId = "" and calls(session, "start").count() = 1 and calls(session, "attach").count() = 1, "direct switch clears local ownership and starts no new local worker")
    closePlayer(player)
end sub

sub testFailedRetryAndRecovery()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    first = player.callFunc("fixtureRead").sessionId
    session.event = { id: first, status: "failed" }
    settle(60)
    check(m.scene.dialog <> invalid and m.scene.dialog.buttons[0] = "Try again", "matching session failure opens an actionable retry dialog")
    before = m.global.fixtureContentTasks
    press("ok")
    settle(160)
    task = player.callFunc("fixtureRead").task
    check(task <> invalid and task.enableRokuDemux and player.callFunc("fixtureRead").pending, "manual retry requests one fresh LIVE descriptor")
    player.callFunc("fixtureRetry")
    check(m.global.fixtureContentTasks = before + 1, "duplicate manual retry while pending starts no second fetch")
    deliver(player, content("roku-demux"))
    second = player.callFunc("fixtureRead").sessionId
    check(second <> first and calls(session, "start").count() = 2, "answered manual retry keeps user opt-in and requests a new session identity")
    ready(session, first)
    check(calls(session, "attach").count() = 0, "old ready cannot bind the retried session")
    ready(session, second)
    player.callFunc("fixtureRecovery", 3)
    player.callFunc("fixtureReconnect")
    task = player.callFunc("fixtureRead").reconnectTask
    check(task <> invalid and task.enableRokuDemux, "automatic reconnect retains LIVE descriptor opt-in")
    task.response = content("roku-demux")
    settle(60)
    third = player.callFunc("fixtureRead").sessionId
    check(third <> second and calls(session, "start").count() = 3, "automatic refreshed descriptor requests one replacement session")
    ready(session, third)
    check(player.callFunc("fixtureRead").video.suppressStartupSeek and player.callFunc("fixtureRead").recovery = 3 and player.callFunc("fixtureRead").reconnect = 3, "recovery preserves spent automatic budgets and startup-seek suppression")
    closePlayer(player)
end sub

sub testRefusalAndBlockedOwner()
    player = openPlayer("LIVE")
    session = sessionOf(player)
    session.refuseStart = true
    deliver(player, content("roku-demux"))
    chooseRoku(player)
    check(player.callFunc("fixtureRead").sessionId = "" and player.callFunc("fixtureRead").video = invalid and m.scene.dialog <> invalid, "synchronous empty start refusal creates no wrapper and presents retry")
    closePlayer(player)
    check(calls(session, "stop").count() = 0, "start refusal never sends empty-ID stop")

    player = openPlayer("LIVE")
    session = sessionOf(player)
    session.cleanupBlocked = true
    player.contentRequested = request("LIVE")
    check(not player.callFunc("fixtureRead").task.enableRokuDemux, "blocked cleanup owner cannot enable new descriptors")
    deliver(player, content("roku-demux"))
    check(m.scene.dialog.buttons.count() = 1 and m.scene.dialog.buttons[0] = "Back" and calls(session, "start").count() = 0, "blocked owner offers Back-only fallback without start")
    closePlayer(player)
end sub

