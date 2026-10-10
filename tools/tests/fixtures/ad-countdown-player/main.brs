sub main()
    m.assertions = 0
    m.failures = 0
    m.port = CreateObject("roMessagePort")
    m.screen = CreateObject("roSGScreen")
    m.screen.SetMessagePort(m.port)
    m.global = m.screen.getGlobalNode()
    m.global.addFields({fixtureRegistry: {}})
    setConstants()
    m.scene = m.screen.CreateScene("AdClockHost")
    m.screen.Show()
    print "STITCH_AD_PLAYER_BEGIN: __MARKER__"
    for each name in ["StitchVideo", "CustomVideo"]
        testRealWrapper(name)
    end for
    testOwnerReplacement()
    testOwnerFailure("no-response")
    testOwnerFailure("unsafe")
    testOwnerDeadline()
    m.screen.Close()
    print "STITCH_AD_PLAYER_END: __MARKER__ "; FormatJson({assertions: m.assertions, failures: m.failures})
end sub

sub check(ok as boolean, message as string)
    m.assertions += 1
    if not ok
        m.failures += 1
        print "STITCH_AD_PLAYER_FAIL: __MARKER__ " + message
    end if
end sub

sub settle(duration as integer)
    clock = CreateObject("roTimespan")
    while clock.TotalMilliseconds() < duration
        wait(10, m.port)
    end while
end sub

function video(name as string) as object
    result = CreateObject("roSGNode", name)
    m.scene.appendChild(result)
    result.video_type = "VOD"
    result.duration = 600
    if result.hasField("suppressStartupSeek") then result.suppressStartupSeek = true
    content = CreateObject("roSGNode", "ContentNode")
    content.url = "https://test.ttvnw.net/current.m3u8"
    result.content = content
    result.state = "playing"
    settle(60)
    return result
end function

function cue() as object
    return {startUs: 1767225601000000&, endUs: 1767225605500001&, durationUs: 4500001&, podCount: 2, podPosition: 0}
end function

function bounds() as object
    return [{startUs: 1767225600000000&, endUs: 1767225608000000&}]
end function

sub shown(node as object, time as string, message as string)
    read = node.callFunc("fixtureAdRead")
    check(read.badgeVisible and read.title = "Ad 1 of 2" and read.time = Chr(183) + " " + time, message)
end sub

sub hidden(node as object, message as string)
    read = node.callFunc("fixtureAdRead")
    check(not read.badgeVisible and read.title = "" and read.time = "", message)
end sub

sub destroyVideo(node as object)
    node.callFunc("onDestroy")
    m.scene.removeChild(node)
end sub

sub testRealWrapper(name as string)
    node = video(name)
    check(node.callFunc("beginAdCountdown", "contentA"), name + " actual wrapper begins local owner")
    check(node.callFunc("setAdMetadata", "contentA", [cue()], bounds()), name + " sanitized cues and anchors accepted")
    hidden(node, name + " cues alone cannot invent frame time")
    node.positionInfo = {epoch: 1, video: 1767225601#, audio: 1767225601#}
    settle(50)
    shown(node, "0:05", name + " actual positionInfo starts fractional countdown")
    node.position = 500
    node.seek = 500
    settle(50)
    shown(node, "0:05", name + " requested seek/position cannot substitute for rendered UTC")
    node.state = "paused"
    settle(150)
    shown(node, "0:05", name + " pause freezes the actual frame without a timer")
    node.state = "buffering"
    settle(120)
    shown(node, "0:05", name + " buffering does not advance presented time")
    node.positionInfo = {epoch: 1, video: 1767225602.500001#, audio: 1767225602.500001#}
    settle(50)
    shown(node, "0:03", name + " an actually presented seek frame updates countdown")
    check(not node.callFunc("setAdMetadata", "old", [cue()], bounds()), name + " stale metadata refuses before UI")
    shown(node, "0:03", name + " stale owner does not hide current valid badge")
    node.chatIsVisible = true
    settle(50)
    read = node.callFunc("fixtureAdRead")
    check(read.x + read.width = 912, name + " badge fits actual 960px video beside chat")
    node.chatIsVisible = false
    settle(50)
    read = node.callFunc("fixtureAdRead")
    check(read.x + read.width = 1232, name + " badge follows full video geometry")
    node.positionInfo = {epoch: 0, video: 4.5#}
    settle(40)
    hidden(node, name + " unknown relative clock hides badge")
    node.positionInfo = {epoch: 1, video: 1767225608#}
    settle(40)
    hidden(node, name + " unanchored exact segment end hides badge")
    node.positionInfo = {epoch: 1, video: 1767225603#}
    settle(40)
    shown(node, "0:03", name + " exact real frame recovers truthful display")
    node.state = "error"
    settle(40)
    hidden(node, name + " terminal playback error clears owner/badge")
    check(node.callFunc("fixtureAdRead").owner = "", name + " terminal owner cleared")
    node.state = "playing"
    node.callFunc("beginAdCountdown", "contentB")
    node.callFunc("setAdMetadata", "contentB", [cue()], bounds())
    node.positionInfo = {epoch: 1, video: 1767225602#}
    settle(40)
    shown(node, "0:04", name + " new content owner receives its own frame")
    replacement = CreateObject("roSGNode", "ContentNode")
    replacement.url = "https://test.ttvnw.net/replacement.m3u8"
    node.content = replacement
    settle(40)
    hidden(node, name + " actual content replacement clears clock/cues")
    node.callFunc("onDestroy")
    check(not node.callFunc("beginAdCountdown", "disposed"), name + " disposed wrapper refuses new countdown")
    check(not node.callFunc("setAdMetadata", "contentB", [cue()], bounds()), name + " disposed callback cannot revive UI")
    m.scene.removeChild(node)
end sub

function owner() as object
    result = CreateObject("roSGNode", "AdMetadataOwner")
    m.scene.appendChild(result)
    return result
end function

function response(token as string) as object
    return {owner: token, cues: [cue()], bounds: bounds()}
end function

sub awaitIdle(ownerNode as object)
    clock = CreateObject("roTimespan")
    while ownerNode.busy and clock.TotalMilliseconds() < 2000
        settle(10)
    end while
    check(not ownerNode.busy, "actual cooperative worker is idle within finite fixture deadline")
end sub

sub testOwnerReplacement()
    manager = owner()
    first = video("StitchVideo")
    token = manager.callFunc("beginContent", first, first.content.url, "direct")
    check(tadOwner(token) and manager.busy, "retained owner starts one actual Task")
    state = manager.callFunc("fixtureAdOwnerRead")
    oldWorker = state.worker
    oldWorker.fixtureHoldStop = true
    check(oldWorker <> invalid and oldWorker.subtype() = "TwitchAdMetadata", "actual worker boundary is explicit")
    manager.callFunc("fixtureDeliverAd", response("old"))
    settle(50)
    check(first.callFunc("fixtureAdRead").bounds = 0, "wrong Task owner cannot deliver metadata")
    manager.callFunc("fixtureDeliverAd", {owner: token, cues: [cue()], bounds: bounds(), rawUrl: "SECRET"})
    settle(50)
    check(first.callFunc("fixtureAdRead").bounds = 0, "extra provider payload refused at scene boundary")
    manager.callFunc("fixtureDeliverAd", response(token))
    first.positionInfo = {epoch: 1, video: 1767225602#}
    settle(70)
    shown(first, "0:04", "actual owner response reaches actual wrapper clock/badge")
    replacementVideo = video("CustomVideo")
    skippedToken = manager.callFunc("beginContent", replacementVideo, replacementVideo.content.url, "direct")
    newToken = manager.callFunc("beginContent", replacementVideo, replacementVideo.content.url, "direct")
    check(newToken <> skippedToken, "rapid replacement has independent current owners")
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.video = invalid and state.stopping, "old video reference dropped immediately before replacement")
    check(oldWorker.stopRequested, "actual old worker receives typed stop")
    for each malformed in [{owner:token,cues:[],bounds:[],closed:"true",cleanupOk:true}, {owner:token,cues:[],bounds:[],closed:true,cleanupOk:1}, {owner:token,cues:[],bounds:[],closed:false,cleanupOk:true}]
        manager.callFunc("fixtureDeliverAd", malformed)
        settle(20)
        check(not manager.callFunc("fixtureAdOwnerRead").acknowledged and manager.busy, "non-Boolean or false closed acknowledgment cannot release native owner")
    end for
    manager.callFunc("fixtureDeliverAd", {owner: token, cues: [], bounds: [], closed: true, cleanupOk: true})
    settle(40)
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.acknowledged and manager.busy and state.worker.isSameNode(oldWorker) and oldWorker.state <> "stop", "closed response alone retains running old Task and pending replacement")
    currentPendingOwner = ""
    if state.pending <> invalid then currentPendingOwner = state.pending.owner
    check(currentPendingOwner = newToken, "one replaceable pending request coalesces rapid content changes")
    oldWorker.fixtureHoldStop = false
    settle(250)
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.owner = newToken and state.worker <> invalid and not state.worker.isSameNode(oldWorker), "new worker starts only after old safe acknowledgement")
    check(oldWorker.fixtureReceivedStop and oldWorker.state = "stop", "old Task actually stopped cooperatively")
    hidden(first, "old wrapper badge cleared on source replacement")
    manager.callFunc("fixtureDeliverAd", response(token))
    settle(40)
    check(replacementVideo.callFunc("fixtureAdRead").bounds = 0, "old callback cannot cross new content owner")
    manager.callFunc("endContent", newToken)
    awaitIdle(manager)
    check(not manager.cleanupBlocked, "safe cleanup remains available")
    manager.callFunc("onDestroy")
    check(manager.closed and not manager.busy, "permanent owner disposal pairs timer/Task cleanup")
    check(manager.callFunc("beginContent", replacementVideo, replacementVideo.content.url, "direct") = "", "permanent owner cannot restart")
    destroyVideo(first)
    destroyVideo(replacementVideo)
    m.scene.removeChild(manager)
end sub

sub testOwnerFailure(mode as string)
    manager = owner()
    node = video("CustomVideo")
    token = manager.callFunc("beginContent", node, node.content.url, "direct")
    manager.callFunc("fixtureWorkerMode", mode)
    manager.callFunc("endContent", token)
    awaitIdle(manager)
    check(manager.cleanupBlocked, "stop/no-response or unsafe acknowledgement permanently refuses restart: " + mode)
    check(manager.callFunc("beginContent", node, node.content.url, "direct") = "", "unsafe worker cannot authorize overlap")
    manager.callFunc("onDestroy")
    check(manager.closed, "stopped unsafe owner can dispose without claiming clean success")
    destroyVideo(node)
    m.scene.removeChild(manager)
end sub

sub testOwnerDeadline()
    manager = owner()
    node = video("CustomVideo")
    token = manager.callFunc("beginContent", node, node.content.url, "direct")
    held = manager.callFunc("fixtureAdOwnerRead").worker
    held.fixtureHoldStop = true
    ' The actual cleanup handler sees a fake clock at its original deadline;
    ' native Task and timer state remain real. No budget is raised.
    manager.callFunc("endContent", token)
    manager.callFunc("fixtureExpireAdCleanup")
    check(manager.cleanupBlocked, "actual five-second cleanup deadline refuses progress")
    state = manager.callFunc("fixtureAdOwnerRead")
    check(state.timerControl = "stop", "deadline stops timer instead of polling forever")
    check(manager.busy and state.worker.isSameNode(held), "deadline cannot force-stop or release pending file owner")
    held.fixtureHoldStop = false
    awaitIdle(manager)
    check(manager.cleanupBlocked, "late safe acknowledgement cannot erase prior unsafe deadline")
    manager.callFunc("onDestroy")
    destroyVideo(node)
    m.scene.removeChild(manager)
end sub
