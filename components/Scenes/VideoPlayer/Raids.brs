sub startRaidWatch()
    if m.disposed or m.isExiting or m.raidTask <> invalid then return
    request = m.top.contentRequested
    if request = invalid or request.contentType <> "LIVE" then return
    if get_user_setting("playback.raids", "ask") = "off" then return
    account = get_setting("active_user", "$default$")
    if account = "$default$" or get_user_setting("access_token", "") = "" then return
    if not raidId(request.streamerId) then return
    m.raidAccount = account
    m.raidSource = request.streamerId
    m.raidTask = CreateObject("roSGNode", "RaidWatchTask")
    if m.raidTask = invalid then return
    m.raidTask.ObserveField("raid", "onOutgoingRaid")
    m.raidTask.channelId = m.raidSource
    m.raidTask.account = account
    m.raidTask.control = "run"
end sub

function raidOwnerCurrent() as boolean
    if m.disposed or m.isExiting or m.raidTask = invalid then return false
    if m.raidAccount <> get_setting("active_user", "$default$") then return false
    if get_user_setting("playback.raids", "ask") = "off" then return false
    request = m.top.contentRequested
    if request = invalid then return false
    return request.contentType = "LIVE" and request.streamerId = m.raidSource
end function

sub onOutgoingRaid(event as object)
    if not raidOwnerCurrent() then return
    if not event.GetRoSGNode().IsSameNode(m.raidTask) then return
    if m.raidOffer <> invalid then return
    raid = event.GetData()
    if GetInterface(raid, "ifAssociativeArray") = invalid then return
    if raid.sourceId <> m.raidSource then return
    stopRaidEndWait(true)
    scene = m.top.GetScene()
    if scene <> invalid and scene.dialog <> invalid and m.errorDialog <> invalid
        if scene.dialog.IsSameNode(m.errorDialog)
            closeErrorDialog()
            if m.video <> invalid then m.video.SetFocus(true)
        end if
    end if
    m.raidOffer = raid
    cancelRaidRecovery()
    m.raidOfferClock = CreateObject("roTimespan")
    tryRaidOffer()
    if m.raidOffer <> invalid and m.raidDialog = invalid and m.raidOfferTimer = invalid
        m.raidOfferTimer = createTimer(1, "tryRaidOffer", true)
    end if
end sub

' A raid never replaces another modal. A single deferred offer expires rather
' than opening later on an unrelated channel or account.
sub tryRaidOffer()
    if m.raidOffer = invalid or m.raidDialog <> invalid then return
    if not raidOwnerCurrent() or m.raidOfferClock.TotalMilliseconds() > 60000
        dismissRaidOffer()
        return
    end if
    scene = m.top.GetScene()
    if scene = invalid or scene.dialog <> invalid or m.video = invalid then return
    if not m.top.IsInFocusChain() then return
    if get_user_setting("playback.raids", "ask") = "auto"
        joinOutgoingRaid()
        return
    end if
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Streamer raid")
    dialog.message = [Substitute(tr("This streamer is raiding {0}. Join their stream?"), m.raidOffer.name)]
    dialog.buttons = [tr("Join raid"), tr("Stay here")]
    applyDialogPalette(dialog)
    m.raidDialog = dialog
    m.raidDialogMode = "offer"
    dialog.ObserveField("buttonSelected", "onRaidSelected")
    dialog.ObserveField("wasClosed", "onRaidClosed")
    m.video.CallFunc("setChannelActionsOpen", true)
    scene.dialog = dialog
    dialog.SetFocus(true)
    stopRaidOfferTimer()
end sub

sub onRaidSelected(event as object)
    if m.raidDialog = invalid then return
    if not event.GetRoSGNode().IsSameNode(m.raidDialog) then return
    scene = m.top.GetScene()
    if scene = invalid or scene.dialog = invalid then return
    if not scene.dialog.IsSameNode(m.raidDialog) then return
    if m.raidDialogMode = "end"
        requestBack()
        return
    end if
    if event.GetData() = 0 and raidOwnerCurrent()
        joinOutgoingRaid()
    else
        dismissRaidOffer()
    end if
end sub

sub onRaidClosed(event as object)
    if m.raidDialog = invalid then return
    if not event.GetRoSGNode().IsSameNode(m.raidDialog) then return
    dismissRaidOffer()
end sub

sub dismissRaidOffer()
    ended = m.raidDialogMode = "end"
    closeRaidDialog()
    clearRaidOffer()
    if m.disposed or m.isExiting then return
    if m.video <> invalid then ended = ended or m.video.state = "finished" or m.video.state = "error"
    if ended
        requestBack()
    else
        onVideoStateChange()
        if nativeStartupPending() and m.bufferCheckTimer = invalid
            startBufferCheckTimer(25 - m.playbackInitTime.TotalMilliseconds() / 1000.0)
        end if
    end if
end sub

sub joinOutgoingRaid()
    if not raidOwnerCurrent() or m.raidOffer = invalid then return
    target = m.raidOffer
    closeRaidDialog(false)
    clearRaidOffer()
    content = CreateObject("roSGNode", "TwitchContentNode")
    content.contentType = "LIVE"
    content.contentId = target.login
    content.streamerId = target.id
    content.streamerLogin = target.login
    content.streamerDisplayName = target.name
    content.contentTitle = target.name
    m.pendingRaid = content
    m.allowBreak = true
    m.PlayVideo = destroyTask(m.PlayVideo, "response")
    ' Normal exit includes the acknowledged local-demux stop barrier. The root
    ' receives this new request only after the old playback owner is done.
    exitPlayer()
end sub

sub stopRaidOfferTimer()
    if m.raidOfferTimer = invalid then return
    m.raidOfferTimer.control = "stop"
    m.raidOfferTimer.UnobserveField("fire")
    m.raidOfferTimer = invalid
end sub

sub clearRaidOffer()
    stopRaidOfferTimer()
    m.raidOffer = invalid
end sub

sub closeRaidDialog(restoreFocus = true as boolean)
    dialog = m.raidDialog
    if dialog = invalid then return
    m.raidDialog = invalid
    m.raidDialogMode = ""
    dialog.UnobserveField("buttonSelected")
    dialog.UnobserveField("wasClosed")
    scene = m.top.GetScene()
    ownsFocus = false
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.IsSameNode(dialog)
            scene.dialog = invalid
            ownsFocus = true
        end if
    end if
    if m.video <> invalid
        m.video.CallFunc("setChannelActionsOpen", false)
        if restoreFocus and ownsFocus and not m.disposed and not m.isExiting then m.video.SetFocus(true)
    end if
end sub

sub stopRaidWatch()
    stopRaidEndWait()
    closeRaidDialog(false)
    clearRaidOffer()
    m.raidTask = destroyTask(m.raidTask, "raid", true)
end sub

function beginRaidEndWait() as boolean
    if not raidOwnerCurrent() then return false
    if m.raidWaiting or m.raidOffer <> invalid then return true
    if m.raidTask.status <> "listening" then return false
    cancelRaidRecovery()
    m.raidWaiting = true
    m.raidEndTimer = createTimer(120, "onRaidEndTimeout")
    scene = m.top.GetScene()
    if scene = invalid or scene.dialog <> invalid then return true
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Stream ended")
    dialog.message = [tr("Waiting up to two minutes for a raid. Press Back to leave.")]
    dialog.buttons = [tr("Back to browsing")]
    m.raidDialog = dialog
    m.raidDialogMode = "end"
    applyDialogPalette(dialog)
    dialog.ObserveField("buttonSelected", "onRaidSelected")
    dialog.ObserveField("wasClosed", "onRaidClosed")
    m.video.CallFunc("setChannelActionsOpen", true)
    scene.dialog = dialog
    dialog.SetFocus(true)
    return true
end function

sub cancelRaidRecovery()
    m.liveReconnect = invalid
    for each field in ["retryTimer", "reconnectTimer", "bufferCheckTimer"]
        timer = m[field]
        if timer <> invalid
            timer.control = "stop"
            timer.UnobserveField("fire")
            m[field] = invalid
        end if
    end for
    cleanupReconnectTask()
end sub

sub onRaidEndTimeout(event as object)
    if m.disposed or m.isExiting or not m.raidWaiting or m.raidEndTimer = invalid then return
    if not event.GetRoSGNode().IsSameNode(m.raidEndTimer) then return
    requestBack()
end sub

sub stopRaidEndWait(restoreFocus = false as boolean)
    if m.raidEndTimer <> invalid
        m.raidEndTimer.control = "stop"
        m.raidEndTimer.UnobserveField("fire")
        m.raidEndTimer = invalid
    end if
    m.raidWaiting = false
    if m.raidDialogMode = "end" then closeRaidDialog(restoreFocus)
end sub
