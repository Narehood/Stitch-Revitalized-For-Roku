' Offline only: production VideoPlayer receives inert task responses and
' creates the real wrappers. No media, device, registry or transport is used.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: { ChatOption: "false", ChatFontSize: "16" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()

    testLiveCounts()
    testMalformedCounts()
    testRecordedCounts()
    testRetainedControls()
    testRetainedPlayer()
    testStreamDetails()
    testQualityDetails()

    fixtureEnd()
end sub

sub testStreamDetails()
    player = createObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    player.contentRequested = request("LIVE")
    started = createObject("roDateTime")
    started.FromSeconds(TimeStamp() - 3661)
    details = response("LIVE", 2468)
    details.createdAt = started.ToISOString()
    details.gameDisplayName = "A very long category name that still needs to fit beside the live clock"
    details.gameBoxArtUrl = "pkg:/images/default_banner.png"
    details.contentTitle = "A deliberately long stream title that should scroll while controls are open and stop scrolling once the controls are hidden. A deliberately long stream title that should scroll."
    player.callFunc("fixtureRead").task.response = details
    video = player.callFunc("fixtureRead").video
    category = video.findNode("streamCategory")
    uptime = video.findNode("liveUptime")
    overlay = video.findNode("controlOverlay")
    check(video.findNode("videoTitle").text = details.contentTitle, "the actual wrapper title field populates its rendered EmojiLabel")
    check(category.visible and category.text = details.gameDisplayName, "actual playback content supplies the category label")
    check(video.findNode("categoryArt").visible and video.findNode("categoryArt").uri = details.gameBoxArtUrl and video.findNode("categoryArt").width = 84 and video.findNode("categoryArt").height = 112 and category.translation[0] = 164, "the larger category cover appears beside the category without covering it")
    check(uptime.visible and uptime.text.inStr("Live for 1:01:") = 0, "live duration starts at the broadcast time rather than opening the player")
    video.setFocus(true)
    press("ok")
    waitOverlay(overlay, true)
    check(video.findNode("videoTitle").repeatCount = -1, "an overflowing player title scrolls while controls are shown")
    pump(1100)
    for each chat in [false, true]
        video.chatIsVisible = chat
        width = 1280
        if chat then width = 960
        info = video.findNode("infoRow")
        art = video.findNode("categoryArt")
        check(info.translation[0] + art.translation[0] + art.width < video.findNode("controls").translation[0] and overlay.translation[1] + info.translation[1] + art.translation[1] + art.height <= 720, "the taller artwork clears the centered controls and fits the overlay")
        check(category.translation[0] + category.width + 24 <= uptime.translation[0], "category and live clock reserve separate horizontal space")
        check(info.translation[0] + uptime.translation[0] + uptime.width = width - 48, "live clock respects the current video area's right margin")
        check(info.translation[1] + category.translation[1] + category.height <= video.findNode("caption").translation[1], "the new metadata line clears the control captions")
    end for
    previous = uptime.text
    video.control = "pause"
    pump(1200)
    check(uptime.text <> previous, "the visible live clock advances independently of paused playback")
    title = video.findNode("videoTitle")
    check(Abs(title.findNode("testAnimation").duration - (title.width - title.maxWidth) / 40) < 0.02, "chat resizing restarts an active title at the readable overflow speed")
    press("down")
    waitOverlay(overlay, false)
    check(video.findNode("videoTitle").repeatCount = 0, "hiding player controls stops title scrolling")
    previous = uptime.text
    pump(1200)
    check(uptime.text = previous, "hiding controls stops the live clock timer")
    video.content = request("LIVE")
    check(not category.visible and not uptime.visible and not video.findNode("categoryArt").visible and category.text = "" and uptime.text = "", "new content without metadata clears the old labels and category art")
    details.gameDisplayName = ""
    details.gameName = "Fallback category"
    details.createdAt = "not a date"
    video.content = details
    check(category.text = "Fallback category" and category.visible and not uptime.visible, "category fallback remains available while invalid start times stay hidden")
    started.FromSeconds(TimeStamp() + 3600)
    details.createdAt = started.ToISOString()
    video.content = details
    check(not uptime.visible, "future stream timestamps never produce a negative live duration")
    closePlayer(player)
end sub

sub testQualityDetails()
    player = createObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    player.contentRequested = request("LIVE")
    details = response("LIVE", 2468)
    started = createObject("roDateTime")
    started.FromSeconds(TimeStamp() - 3600)
    details.createdAt = started.ToISOString()
    details.contentTitle = "Updated stream title from playback metadata with enough text to keep its marquee running while changing resolutions. Updated stream title from playback metadata with enough text to keep its marquee running."
    details.gameDisplayName = "Updated category"
    details.gameBoxArtUrl = "pkg:/images/default_banner.png"
    task = player.callFunc("fixtureRead").task
    task.metadata = [{ QualityID: "source", url: "", streamFormat: "hls", isTransmux: false, isProxied: false }, { QualityID: "720p60", url: "", streamFormat: "hls", isTransmux: false, isProxied: false }]
    task.response = details
    for each index in [1, 0, 1]
        previous = player.callFunc("fixtureRead").video
        oldTitle = previous.findNode("videoTitle")
        oldTitle.repeatCount = -1
        previous.QualityChangeRequest = index
        previous.QualityChangeRequestFlag = true
        video = player.callFunc("fixtureRead").video
        check(not video.isSameNode(previous) and video.selectedQuality = player.metadata[index].QualityID, "actual quality callback replaces the wrapper with the chosen resolution")
        check(video.videoTitle = details.contentTitle and video.findNode("videoTitle").text = details.contentTitle and video.findNode("videoTitle").callFunc("getAllComponents").count() > 0, "quality changes preserve the current title field and its rendered text")
        check(video.findNode("streamCategory").text = details.gameDisplayName and video.findNode("categoryArt").uri = details.gameBoxArtUrl and video.findNode("liveUptime").visible, "quality changes preserve refreshed category art and the broadcast clock")
        check(oldTitle.findNode("scrollStartTimer").control = "stop" and oldTitle.callFunc("getAllComponents").count() = 0, "replaced wrappers dispose the old title and cancel its pending marquee")
    end for
    closePlayer(player)
end sub

sub testRetainedPlayer()
    player = openPlayer("LIVE", 2468)
    previous = player.callFunc("fixtureRead").video
    for each sample in [{ count: invalid, typed: false, text: "" }, { count: 0, typed: true, text: "0 viewers" }, { count: 12345, typed: true, text: "12.3K viewers" }]
        player.contentRequested = request("LIVE")
        player.callFunc("fixtureRead").task.response = response("LIVE", sample.count, sample.typed)
        video = player.callFunc("fixtureRead").video
        label = video.findNode("viewerCount")
        check(previous.getParent() = invalid and not video.isSameNode(previous), "a retained player replaces the old controls when content is refreshed")
        check(label.text = sample.text and label.visible = (sample.text <> ""), "a retained player renders only the refreshed snapshot including unknown and zero")
        previous = video
    end for
    closePlayer(player)
end sub

function request(kind as string) as object
    node = createObject("roSGNode", "TwitchContentNode")
    node.setFields({ contentType: kind, contentId: "fixture-id", streamerLogin: "fixturechannel", streamerDisplayName: "Fixture Channel", streamerId: "42", contentTitle: "A long stream title for checking the title and viewers occupy separate spaces" })
    return node
end function

function response(kind as string, count as dynamic, typed = true as boolean) as object
    if typed
        node = request(kind)
        node.viewersCount = count
    else
        ' Generic nodes retain malformed types instead of coercing to the
        ' production TwitchContentNode's int before the boundary guard runs.
        node = createObject("roSGNode", "ContentNode")
        node.addFields(request(kind).getFields())
        node.removeField("viewersCount")
        if count <> invalid then node.addFields({ viewersCount: count })
    end if
    node.setFields({ url: "", QualityID: "source", streamFormat: "hls" })
    return node
end function

function openPlayer(kind as string, count as dynamic, typed = true as boolean) as object
    player = createObject("roSGNode", "VideoPlayer")
    m.scene.appendChild(player)
    player.contentRequested = request(kind)
    player.callFunc("fixtureRead").task.response = response(kind, count, typed)
    check(player.callFunc("fixtureRead").video <> invalid, kind + " response creates a wrapper")
    check(player.callFunc("fixtureRead").video.width = 1280 and player.callFunc("fixtureRead").video.height = 720, kind + " wrapper starts in the logical viewport when chat is hidden")
    return player
end function

sub closePlayer(player as object)
    player.callFunc("onDestroy")
    m.scene.removeChild(player)
end sub

sub testLiveCounts()
    for each sample in [{ count: 2468, text: "2.4K viewers" }, { count: 0, text: "0 viewers" }, { count: 1200000, text: "1.2M viewers" }]
        player = openPlayer("LIVE", sample.count)
        video = player.callFunc("fixtureRead").video
        label = video.findNode("viewerCount")
        overlay = video.findNode("controlOverlay")
        info = video.findNode("infoRow")
        check(video.subtype() = "StitchVideo" and video.viewersCount = sample.count, "live response forwards the typed count to StitchVideo")
        check(label.visible and label.text = sample.text, "live label uses numberToText and the existing localized Viewers suffix")
        ' brs-engine does not apply XML aliases to child labels. Set the
        ' real EmojiLabel text directly to exercise its production renderer.
        video.findNode("videoTitle").text = player.content.contentTitle
        video.findNode("channelUsername").text = player.content.streamerDisplayName
        check(label.getParent().isSameNode(info) and info.getParent().isSameNode(overlay), "the controls overlay owns the counter")
        check(not overlay.visible, "a known count does not reveal hidden controls")
        video.setFocus(true)
        press("ok")
        waitOverlay(overlay, true)
        check(overlay.visible and label.visible, "revealing controls exposes the live count")
        for each chat in [false, true]
            video.chatIsVisible = chat
            verifyLayout(video)
        end for
        press("down")
        waitOverlay(overlay, false)
        check(not overlay.visible, "hiding controls also hides the counter")
        closePlayer(player)
    end for
end sub

sub waitOverlay(overlay as object, visible as boolean)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 3000
        if overlay.visible = visible then return
        pump(20)
    end while
    fail("timed out waiting for overlay visible=" + visible.toStr())
end sub

sub verifyLayout(video as object)
    width = 1280
    if video.chatIsVisible then width = 960
    info = video.findNode("infoRow")
    label = video.findNode("viewerCount")
    title = video.findNode("videoTitle")
    labelX = info.translation[0] + label.translation[0]
    titleX = info.translation[0] + title.translation[0]
    check(labelX + label.width = width - 48, "viewer label stays at the video area's right safe margin")
    check(titleX + title.maxWidth + 24 <= labelX, "title reserves the actual viewer label width and a 24 px gap")
    parts = title.callFunc("getAllComponents")
    check(parts.count() > 0 and title.clippingRect.width = title.maxWidth, "the rendered EmojiLabel clips the title at the reserved boundary")
    check(info.translation[1] + label.translation[1] = info.translation[1] + title.translation[1] - 14, "viewer label and the centered EmojiLabel share the secondary line")
    tag = video.findNode("latencyTag")
    check(tag.translation[1] + tag.height <= info.translation[1] + label.translation[1], "the latency tag finishes above the viewer line")
    caption = video.findNode("caption")
    check(info.translation[1] + label.translation[1] + label.height <= caption.translation[1], "viewers finish above captions and controls")
    bounds = label.sceneBoundingRect()
    check(bounds.width > 0 and bounds.height > 0 and bounds.x + bounds.width <= width - 48, "the actual viewer label node renders inside the right margin")
end sub

sub testMalformedCounts()
    for each count in [-1, -5, invalid, "2468", "malformed", true, {}, [], 2.5]
        player = openPlayer("LIVE", count, false)
        video = player.callFunc("fixtureRead").video
        label = video.findNode("viewerCount")
        check(not label.visible and label.text = "" and video.viewersCount = -1, "missing, negative and malformed counts stay hidden without crashing")
        closePlayer(player)
    end for
end sub

sub testRecordedCounts()
    for each kind in ["VOD", "CLIP"]
        player = openPlayer(kind, 2468)
        video = player.callFunc("fixtureRead").video
        check(video.subtype() = "CustomVideo" and video.findNode("viewerCount") = invalid, kind + " keeps recorded controls without a live viewers label")
        closePlayer(player)
    end for
end sub

sub testRetainedControls()
    player = openPlayer("LIVE", 2468)
    video = player.callFunc("fixtureRead").video
    label = video.findNode("viewerCount")
    video.content = response("LIVE", 9876)
    check(not label.visible and label.text = "" and video.viewersCount = -1, "new content clears the previous snapshot before metadata is forwarded")
    video.viewersCount = 9876
    check(label.visible and label.text = "9.8K viewers", "a runtime field update renders the refreshed count")
    video.lowLatency = true
    video.content = response("LIVE", 9876)
    video.viewersCount = 9876
    check(video.findNode("latencyTag").visible and label.visible, "the latency tag and viewer snapshot can be visible together")
    verifyLayout(video)
    video.chatIsVisible = true
    verifyLayout(video)
    video.viewersCount = 0
    check(label.visible and label.text = "0 viewers", "a runtime zero remains a valid count")
    video.viewersCount = -1
    check(not label.visible and label.text = "", "an unknown snapshot clears the retained text")
    video.viewersCount = 2468
    video.video_type = "VOD"
    check(not label.visible and label.text = "", "changing to non-LIVE metadata hides the counter")
    video.video_type = "LIVE"
    video.content = invalid
    check(not label.visible and label.text = "" and video.viewersCount = -1, "clearing content never leaves a stale viewer count")
    closePlayer(player)
end sub
