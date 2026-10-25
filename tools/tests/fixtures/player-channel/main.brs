' Real Hero, Player, ChannelPage and wrappers. Network, registry, socket and
' media-decoder I/O are inert boundaries; their ownership controllers run.
sub main()
    m.assertions = 0
    m.failures = 0
    m.port = CreateObject("roMessagePort")
    screen = CreateObject("roSGScreen")
    screen.SetMessagePort(m.port)
    m.global = screen.GetGlobalNode()
    setConstants()
    m.global.AddFields({ priorExitReason: "", fixtureRegistry: { "app/last_seen_version": "999.0.0", "app/active_user": "$default$", device_code: "canned-device", ChatOption: "true", ChatFontSize: "16", "chat.hypeTrain": "true", "chat.pinnedMessages": "true" }, fixtureHistory: [], fixtureContentTasks: 0, fixtureWrites: 0, fixtureDeletes: 0, emoteCache: {} })
    m.scene = screen.CreateScene("HeroScene")
    screen.Show()
    m.scene.CallFunc("fixtureOpenFollowing")
    settle(60)
    m.prior = hero().active
    check(m.prior.id = "Following", "actual anonymous Hero opens the pre-player page")
    for each kind in ["LIVE", "VOD", "CLIP"]
        request = channelRequest(kind)
        player = openPlayer(request)
        video = player.CallFunc("fixturePlayer").video
        chat = player.CallFunc("fixturePlayer").chat
        engagement = player.CallFunc("fixturePlayer").engagement
        if kind = "LIVE"
            check(chat.visible and chat.CallFunc("fixtureChat").job <> invalid and engagement <> invalid, "live playback owns actual chat and engagement before departure")
            check(video.width = 960 and video.viewersCount = 1234 and video.selectedQuality = "Automatic", "side chat retains viewers quality and video geometry")
        else
            check(not chat.visible and engagement = invalid, "recordings and clips retain hidden chat layout")
        end if
        original = player.contentRequested
        selectChannel(video, kind)
        page = hero().active
        verifyPage(player, page, original)
        check(chat.CallFunc("fixtureChat").disposed and chat.CallFunc("fixtureChat").job = invalid and chat.CallFunc("fixtureChat").emote = invalid, "departure explicitly closes visible or hidden chat ownership")
        if engagement <> invalid then check(engagement.stopRequested and engagement.control = "stop" and engagement.GetParent() = invalid, "departure stops and detaches the engagement worker")
        video.CallFunc("fixtureRepeatAction")
        video.channelActionsRequested = true
        player.channelRequested = channelRequest("STREAMER")
        m.scene.CallFunc("fixtureDeliverChannel", player)
        check(hero().active.IsSameNode(page) and hero().pages = 1 and hero().players = 0, "double Select disposed wrapper fields and stale root events cannot duplicate the profile")
        goBackToPrior()
    end for

    ' A valid login is enough for the actual anonymous ChannelPage query.
    request = channelRequest("VOD")
    request.streamerId = ""
    player = openPlayer(request)
    selectChannel(player.CallFunc("fixturePlayer").video, "VOD")
    check(hero().active.contentRequested.streamerId = "" and hero().active.CallFunc("fixtureChannel").task.request.params.id = "canned", "missing numeric ID uses the existing ChannelPage login contract without account login")
    goBackToPrior()

    for each kind in ["LIVE", "VOD", "CLIP"]
        request = channelRequest(kind)
        request.streamerLogin = ""
        if kind = "CLIP" then request.streamerId = ""
        if kind = "VOD" then request.streamerLogin = "bad/login"
        player = openPlayer(request)
        video = player.CallFunc("fixturePlayer").video
        check(not video.channelAvailable and not video.FindNode("channelGroup").visible, "missing or invalid query identity hides the channel action")
        video.channelActionsRequested = true
        check(hero().active.IsSameNode(player) and not player.backPressed and player.channelRequested = invalid, "forced action without identity cannot exit or route a recording ID")
        player.CallFunc("requestBack")
        settle(40)
        check(hero().active.IsSameNode(m.prior) and hero().players = 0, "missing identity still allows ordinary player Back")
    end for

    ' Overlay chat leaves full video width; replaced wrappers lose authority.
    set_user_setting("chat.layout", "overlay")
    player = openPlayer(channelRequest("LIVE"))
    oldVideo = player.CallFunc("fixturePlayer").video
    openActions(oldVideo, "LIVE")
    oldDialog = m.scene.dialog
    player.CallFunc("fixtureReplaceWrapper")
    video = player.CallFunc("fixturePlayer").video
    check(not oldVideo.IsSameNode(video) and oldVideo.CallFunc("fixtureOverlay").disposed, "quality-style wrapper replacement disposes its old action owner")
    oldVideo.channelActionsRequested = true
    oldDialog.buttonSelected = 1
    player.CallFunc("fixtureDeliverOpenChannel", oldVideo)
    check(hero().active.IsSameNode(player) and player.channelRequested = invalid and video.control = "play", "late old wrapper events cannot stop current playback")
    check(m.scene.dialog = invalid and not RW_IsPinned("canned"), "wrapper replacement closes its old dialog and rejects late pin actions")
    check(video.chatOverlayMode and video.width = 1280 and video.chatIsVisible, "overlay chat retains full video width with the channel action")
    selectChannel(video, "LIVE")
    check(hero().active.id = "ChannelPage", "replacement wrapper remote action still opens the channel")
    goBackToPrior()
    set_user_setting("chat.layout", "side")

    set_user_setting("ChatOption", "false")
    set_user_setting("playback.lowLatency", "true")
    player = openPlayer(channelRequest("LIVE"))
    relay = player.CallFunc("fixturePlayer").relay
    check(relay <> invalid and relay.control = "run", "actual lower latency controller owns a relay before ready")
    relay.status = { url: "http://127.0.0.1:49372/live.m3u8" }
    video = player.CallFunc("fixturePlayer").video
    check(video <> invalid and video.lowLatency and not video.chatIsVisible and video.FindNode("scrim").width = 1280, "relay live wrapper retains full controls width when chat is closed")
    selectChannel(video, "LIVE")
    check(hero().active.id = "ChannelPage" and relay.stopRequested and relay.control = "stop", "channel departure explicitly stops the active relay")
    goBackToPrior()
    set_user_setting("playback.lowLatency", "false")
    set_user_setting("ChatOption", "true")

    ' Returning from a recording to its retained profile never nests that same
    ' profile or loses the page/focus that preceded it.
    m.scene.CallFunc("fixtureSelectContent", channelRequest("STREAMER"), false)
    settle(40)
    profile = hero().active
    check(profile.id = "ChannelPage" and hero().footprints = 1, "real content selection opens the starting profile")
    player = openPlayer(channelRequest("CLIP"))
    selectChannel(player.CallFunc("fixturePlayer").video, "CLIP")
    check(hero().active.IsSameNode(profile) and hero().pages = 1 and hero().footprints = 1 and hero().players = 0, "same-channel profile is reused without a duplicate or phantom player")
    goBackToPrior()

    testPlayerPins()
    testPinDuringSeek()
    testSupersededDialog()

    ' Local LIVE and completed VOD use their actual production manager paths.
    for each kind in ["LIVE", "VOD"]
        manager = m.scene.CallFunc("fixtureNewManager")
        player = openPlayer(channelRequest(kind), true)
        owned = manager.CallFunc("fixtureManager")
        worker = owned.worker
        id = owned.currentId
        check(worker <> invalid and id <> "" and manager.busy, "local playback has one actual manager owner")
        worker.ready = readyFor(id, kind)
        settle(40)
        video = player.CallFunc("fixturePlayer").video
        if video = invalid then throw "local wrapper did not attach"
        video.state = "playing"
        openActions(video, kind)
        pinFromDialog()
        check(RW_IsPinned("canned") and manager.busy and not worker.stopRequested and video.control = "play", "local pin preserves the active worker and attached playing Video")
        openActions(video, kind)
        pinFromDialog()
        check(not RW_IsPinned("canned") and manager.CallFunc("fixtureManager").worker.IsSameNode(worker) and video.state = "playing", "local unpin preserves the same playback session")
        selectChannel(video, kind)
        check(hero().active.IsSameNode(player) and player.CallFunc("fixturePlayer").exitPending and manager.busy and player.channelRequested = invalid, "local channel action waits for the owned worker and Video")
        if not hero().active.IsSameNode(player) then exit for
        check(worker.stopRequested and worker.control = "run" and video.control = "stop" and not video.visible, "local channel action cooperates with worker and hides stopped video")
        check(player.CallFunc("fixturePlayer").chat.CallFunc("fixtureChat").disposed and player.CallFunc("fixturePlayer").engagement = invalid, "local wait already closes chat and engagement")
        snapshot = video.CallFunc("fixtureOverlay")
        video.CallFunc("fixtureRepeatAction")
        video.channelActionsRequested = true
        press("play")
        settle(250)
        check(video.control = "stop" and video.CallFunc("fixtureOverlay").fade = "stop" and snapshot.disposed, "disposed live or recorded wrapper cannot replay or restart fade during cleanup")
        worker.result = cleanupFor("00000000000000000000000000000000")
        check(manager.busy and hero().active.IsSameNode(player), "stale cleanup acknowledgment cannot publish a channel request")
        worker.result = cleanupFor(id)
        check(manager.busy and hero().active.IsSameNode(player), "cleanup flags alone cannot leave a running worker")
        worker.state = "stop"
        check(manager.busy and hero().active.IsSameNode(player), "worker STOP alone cannot leave the attached playing Video")
        video.state = "stopped"
        settle(40)
        check(not manager.busy and hero().active.id = "ChannelPage" and hero().players = 0, "matching flags Task STOP and Video STOP release profile navigation once")
        goBackToPrior()
    end for

    ' A blocked owner permits UI departure only when its actual Video stops;
    ' it retains the worker and safety latch after the profile opens.
    if m.failures = 0
        manager = m.scene.CallFunc("fixtureNewManager")
        player = openPlayer(channelRequest("LIVE"), true)
        owned = manager.CallFunc("fixtureManager")
        worker = owned.worker
        id = owned.currentId
        worker.ready = readyFor(id, "LIVE")
        video = player.CallFunc("fixturePlayer").video
        video.state = "playing"
        selectChannel(video, "LIVE")
        manager.CallFunc("fixtureTimeout")
        check(manager.busy and manager.cleanupBlocked and hero().active.IsSameNode(player) and player.channelRequested = invalid, "cleanup timeout preserves the blocked active owner before actual Video STOP")
        player.CallFunc("requestBack")
        check(hero().active.IsSameNode(player), "Back repeat cannot bypass blocked channel cleanup")
        video.state = "stopped"
        settle(40)
        check(hero().active.id = "ChannelPage" and manager.busy and manager.cleanupBlocked, "blocked UI can leave only after real Video STOP without claiming worker cleanup")
        check(manager.CallFunc("fixtureManager").worker.IsSameNode(worker) and manager.CallFunc("startSession", liveDescriptor()) = "", "profile departure retains unsafe worker ownership and refuses another writer")
        worker.result = cleanupFor(id)
        worker.state = "stop"
        check(not manager.busy and manager.cleanupBlocked, "late genuine acknowledgment releases owner without clearing cleanup blockage")
        goBackToPrior()
    end if

    m.scene.CallFunc("onDestroy")
    screen.Close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "CHANNEL_FAIL_SUMMARY: "; m.failures
    end if
end sub

sub testSupersededDialog()
    player = openPlayer(channelRequest("VOD"))
    video = player.CallFunc("fixturePlayer").video
    openActions(video, "VOD")
    oldDialog = m.scene.dialog
    player.CallFunc("fixturePlaybackError")
    recovery = m.scene.dialog
    check(recovery <> invalid and not recovery.IsSameNode(oldDialog) and recovery.title = "Canned playback error", "playback recovery supersedes the channel dialog")
    oldDialog.buttonSelected = 1
    oldDialog.wasClosed = true
    check(not RW_IsPinned("canned") and m.scene.dialog.IsSameNode(recovery) and hero().active.IsSameNode(player), "superseded channel buttons cannot pin navigate or steal the recovery dialog")
    recovery.buttonSelected = 1
    settle(40)
    check(hero().active.IsSameNode(m.prior) and hero().players = 0, "normal recovery Back retains explicit player cleanup")
end sub

sub testPinDuringSeek()
    player = openPlayer(channelRequest("VOD"))
    video = player.CallFunc("fixturePlayer").video
    video.duration = 180
    video.position = 60
    video.state = "playing"
    press("fastforward")
    settle(250)
    before = video.CallFunc("fixtureOverlay")
    check(before.preview and before.position = 70 and video.control = "pause", "recorded channel controls retain the first-press seek preview")
    openActions(video, "VOD")
    pinFromDialog()
    after = video.CallFunc("fixtureOverlay")
    check(RW_IsPinned("canned") and after.preview and after.position = 70 and video.control = "pause", "pinning preserves an unapplied seek preview and its paused state")
    press("back")
    settle(250)
    check(not video.CallFunc("fixtureOverlay").preview and video.control = "resume" and hero().active.IsSameNode(player), "Back still cancels the seek and resumes after pinning")
    registry_delete("pins", RW_Section())
    player.CallFunc("requestBack")
    settle(40)
end sub

sub testPlayerPins()
    for each kind in ["LIVE", "VOD", "CLIP"]
        player = openPlayer(channelRequest(kind))
        state = player.CallFunc("fixturePlayer")
        video = state.video
        chat = state.chat
        job = chat.CallFunc("fixtureChat").job
        contentTasks = m.global.fixtureContentTasks
        openActions(video, kind)
        dialog = m.scene.dialog
        check(dialog.buttons[1] = "Pin streamer" and video.control = "play", "current unpinned channel offers Pin without pausing video")
        video.CallFunc("fixtureRepeatAction")
        check(m.scene.dialog.IsSameNode(dialog), "repeated channel action keeps a single dialog")
        pinFromDialog()
        check(RW_IsPinned("canned") and RW_LoadPins().Count() = 1, "actual player pin action persists one channel via shared helper")
        check(hero().active.IsSameNode(player) and player.CallFunc("fixturePlayer").video.IsSameNode(video) and video.control = "play" and video.IsInFocusChain(), "pin action retains active Video playback and focus")
        check(m.global.fixtureContentTasks = contentTasks and not video.QualityChangeRequestFlag, "pinning neither reloads content nor requests a quality change")
        if job <> invalid then check(chat.CallFunc("fixtureChat").job.IsSameNode(job) and job.control = "run", "pin action preserves the running chat transport")
        railData = railEntry("canned")
        check(railData <> invalid and railData.pinned and railData.id = "987654" and railData.displayName = "Canned", "player pin refreshes actual rail with broadcaster metadata")
        writes = m.global.fixtureWrites
        dialog.buttonSelected = 1
        check(m.global.fixtureWrites = writes and RW_IsPinned("canned"), "late duplicate pin selection cannot toggle or repeat a write")
        openActions(video, kind)
        check(m.scene.dialog.buttons[1] = "Unpin streamer" and m.scene.dialog.message[0] = "Canned · PINNED", "reopened menu refreshes current pin label and visible PINNED state")
        pinFromDialog()
        check(not RW_IsPinned("canned") and RW_LoadPins().Count() = 0 and railEntry("canned") = invalid, "actual unpin action removes the pin and refreshes the empty rail")
        check(hero().active.IsSameNode(player) and video.control = "play" and not player.backPressed and video.CallFunc("fixtureOverlay").fade = "start", "unpin preserves playback and restarts control fade")
        openActions(video, kind)
        press("back")
        settle(250)
        check(m.scene.dialog = invalid and hero().active.IsSameNode(player) and video.control = "play" and video.IsInFocusChain(), "native dialog Back closes channel actions without leaving or pausing playback")
        player.CallFunc("requestBack")
        settle(40)
    end for

    ' A menu opened for anonymous storage cannot change Alice's pins.
    player = openPlayer(channelRequest("VOD"))
    video = player.CallFunc("fixturePlayer").video
    openActions(video, "VOD")
    stale = m.scene.dialog
    writes = m.global.fixtureWrites
    set_setting("active_user", "alice")
    stale.buttonSelected = 1
    check(not RW_IsPinned("canned") and m.global.fixtureWrites = writes and video.control = "play", "old account dialog cannot pin into the new active account")
    result = RW_SetPinned({ login: "canned", displayName: "Canned", id: "987654" }, true)
    openActions(video, "VOD")
    check(m.scene.dialog.buttons[1] = "Unpin streamer", "menu reads pin state from the current account when opened")
    pinFromDialog()
    check(not RW_IsPinned("canned"), "current account unpin uses the shared account helper")
    set_setting("active_user", "$default$")
    check(not RW_IsPinned("canned"), "player account actions preserve anonymous pins independently")

    for i = 1 to RW_MaxItems()
        result = RW_SetPinned({ login: "other_" + i.ToStr(), displayName: "Other", id: i.ToStr() }, true)
    end for
    openActions(video, "VOD")
    pinFromDialog()
    check(RW_LoadPins().Count() = 12 and not RW_IsPinned("canned"), "player respects the existing pin limit without evicting channels")
    check(video.FindNode("messageText").text = "Pin limit reached (12). Unpin a channel first." and video.control = "play", "pin limit is readable while video keeps playing")
    registry_delete("pins", RW_Section())
    player.CallFunc("requestBack")
    settle(40)

    request = channelRequest("CLIP")
    request.streamerId = ""
    player = openPlayer(request)
    video = player.CallFunc("fixturePlayer").video
    openActions(video, "CLIP")
    pinFromDialog()
    check(RW_IsPinned("canned") and RW_LoadPins()[0].id = "" and RW_LoadPins()[0].login = "canned", "login-only clip pin never persists clip slug or recording ID")
    registry_delete("pins", RW_Section())
    player.CallFunc("requestBack")
    settle(40)
end sub

sub pinFromDialog()
    dialog = m.scene.dialog
    press("down")
    settle(250)
    press("ok")
    settle(250)
    ' brs-node's StandardMessageDialog does not reliably route its native
    ' button keys. Supply only that widget event; production selection runs.
    if m.scene.dialog <> invalid
        if m.scene.dialog.IsSameNode(dialog) then dialog.buttonSelected = 1
    end if
end sub

function railEntry(login as string) as object
    for each child in hero().rail.GetChildren(-1, 0)
        if child.IsSubtype("RecentlyWatchedItem")
            if child.itemData.login = login then return child.itemData
        end if
    end for
    return invalid
end function

function channelRequest(kind as string) as object
    node = CreateObject("roSGNode", "TwitchContentNode")
    node.SetFields({ contentType: kind, contentId: "123456789", clipSlug: "RecordingSlug", streamerLogin: "canned", streamerId: "987654", streamerDisplayName: "Canned", streamerProfileImageUrl: "pkg:/images/default_banner.png", viewersCount: 1234 })
    return node
end function

function openPlayer(request as object, local = false as boolean) as object
    m.scene.CallFunc("fixtureSelectContent", request, true)
    player = hero().active
    check(player.id = "VideoPlayer", "actual content selection opens one player")
    task = player.CallFunc("fixturePlayer").task
    node = CreateObject("roSGNode", "TwitchContentNode")
    fields = request.GetFields()
    fields.url = "https://use14.playlist.ttvnw.net/canned/720.m3u8?token=canned%2B"
    fields.streamFormat = "hls"
    fields.QualityID = "Automatic"
    if local
        fields.isTransmux = true
        fields.playbackTransport = "roku-demux"
        fields.localPlaybackDescriptor = liveDescriptor()
        if request.contentType = "VOD" then fields.localPlaybackDescriptor = vodDescriptor()
    end if
    node.SetFields(fields)
    task.metadata = [{ qualityID: "Automatic", url: fields.url }, { qualityID: "720p60", url: fields.url }]
    task.response = node
    settle(40)
    return player
end function

sub openActions(video as object, kind as string)
    video.SetFocus(true)
    if not video.FindNode("controlOverlay").visible
        press("ok")
        settle(250)
        check(video.FindNode("controlOverlay").visible and hero().active.id = "VideoPlayer" and m.scene.dialog = invalid, "first remote Select only reveals controls")
    end if
    target = 6
    if kind = "LIVE" then target = 4
    for i = 1 to 7
        if video.CallFunc("fixtureOverlay").focused = target then exit for
        press("right")
        settle(250)
    end for
    check(video.FindNode("channelFocus").visible and video.FindNode("captionLabel").text = "Channel actions", "remote navigation clearly captions the channel actions control")
    press("ok")
    settle(250)
    check(m.scene.dialog <> invalid and m.scene.dialog.title = "Channel actions" and video.CallFunc("fixtureOverlay").fade = "stop", "actual channel dialog opens without letting controls fade")
end sub

sub selectChannel(video as object, kind as string)
    openActions(video, kind)
    dialog = m.scene.dialog
    check(m.scene.dialog.buttons[0] = "Open channel", "channel dialog clearly labels profile navigation")
    press("ok")
    settle(250)
    if m.scene.dialog <> invalid
        if m.scene.dialog.IsSameNode(dialog) then dialog.buttonSelected = 0
    end if
end sub

sub verifyPage(player as object, page as object, original as object)
    check(page.id = "ChannelPage" and hero().pages = 1 and hero().players = 0 and hero().footprints = 1, "channel replaces player without a playable back-stack entry")
    check(player.GetParent() = invalid and player.CallFunc("fixturePlayer").disposed, "root permanently disposes the finished player")
    content = page.contentRequested
    check(not content.IsSameNode(original) and content.contentType = "STREAMER" and content.contentId = "987654", "profile gets an immutable fresh broadcaster identity node")
    check(content.streamerLogin = "canned" and content.streamerId = "987654" and content.streamerDisplayName = "Canned" and content.streamerProfileImageUrl = "pkg:/images/default_banner.png", "channel identity and display metadata survive navigation")
    check(content.clipSlug = "" and content.url = "" and content.localPlaybackDescriptor = invalid and original.contentId = "123456789" and original.clipSlug = "RecordingSlug", "route omits playback and clip identifiers without mutating the original")
    check(page.CallFunc("fixtureChannel").task.request.params.id = "canned" and page.CallFunc("fixtureChannel").shell.request.params.id = "canned", "actual ChannelPage queries use broadcaster login")
end sub

sub goBackToPrior()
    page = hero().active
    press("back")
    settle(250)
    check(hero().active.IsSameNode(m.prior) and hero().footprints = 0 and hero().players = 0 and hero().pages = 0, "Back from profile restores the pre-player stack without replay")
    check(m.prior.IsInFocusChain() and not m.scene.exitApp, "Back restores pre-player focus and does not request app exit")
    if m.prior.lastFocus <> invalid then check(m.prior.lastFocus.IsInFocusChain(), "remembered pre-player child regains focus")
end sub

function liveDescriptor() as object
    return { version: 1, sourceUrl: "https://use14.playlist.ttvnw.net/canned/720.m3u8?token=canned%2B", qualityId: "720p60", approvedOrigins: ["https://use14.playlist.ttvnw.net"], metadata: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 3322199, isHD: true } }
end function

function vodDescriptor() as object
    return { version: 2, mode: "vod", vodId: "123456789", usherUrl: "https://usher.ttvnw.net/vod/v2/123456789.m3u8?nauth=fixture", sourceUrl: "https://d123.cloudfront.net/vod/720.m3u8?fixture=exact%2B", qualityId: "720p60", approvedOrigin: "https://d123.cloudfront.net", metadata: { videoCodec: "avc1.4D4020", audioCodec: "mp4a.40.2", width: 1280, height: 720, frameRate: "60.000", bandwidth: 4000000, isHD: true } }
end function

function readyFor(id as string, kind as string) as object
    if kind = "VOD"
        meta = vodDescriptor().metadata
        format = twitchVariantVideoFormat({ CODECS: meta.videoCodec + "," + meta.audioCodec, RESOLUTION: meta.width.ToStr() + "x" + meta.height.ToStr(), "FRAME-RATE": meta.frameRate, BANDWIDTH: meta.bandwidth.ToStr() })
        return { sessionId: id, boundAddressText: "127.0.0.1", boundPort: 49371, metadata: meta, decoderApproved: true, actualInitValidated: true, requestedDecoderFormat: format, mode: "vod", totalDurationUs: 73760000000&, masterPath: "/vod/" + id + "/master.m3u8" }
    end if
    return { sessionId: id, boundPort: 49371, boundAddressText: "127.0.0.1", actualInitValidated: true, decoderApproved: true, metadata: liveDescriptor().metadata }
end function

function cleanupFor(id as string) as object
    return { sessionId: id, cleanupOk: true, listenerClosed: true, connectionClosed: true, helperClosed: true, cacheReferencesReleased: true }
end function

function hero() as object
    return m.scene.CallFunc("fixtureHero")
end function

sub press(key as string)
    print "FIXTURE_KEY:" + key
end sub

sub settle(duration as integer)
    timer = CreateObject("roTimespan")
    while timer.TotalMilliseconds() < duration
        ignored = Wait(10, m.port)
    end while
end sub

sub check(ok as boolean, label as string)
    m.assertions++
    if not ok
        m.failures++
        print "CHANNEL_ASSERT_FAIL: " + label
    end if
end sub
