sub main()
    fixtureBegin()
    m.global.AddFields({ fixtureRegistry: { ChatOption: "false", ChatFontSize: "16", "chat.enabled": "false" }, fixtureContentTasks: 0, emoteCache: {} })
    m.scene = m.screen.CreateScene("PhaseTwoHost")
    m.screen.Show()
    set_setting("active_user", "raid-viewer")
    set_user_setting("access_token", "fixture-token")

    for each mode in ["ask", "auto", "off"]
        set_user_setting("playback.raids", mode)
        player = openPlayer("LIVE")
        contentTask(player).response = playable("source")
        video = waitVideo(player, invalid)
        job = player.CallFunc("fixtureRead").raidTask
        if mode = "off"
            check(job = invalid and m.scene.dialog = invalid, "Off starts no worker")
        else
            check(job <> invalid and not video.chatIsVisible, "raid worker is independent of hidden disabled chat")
            job.raid = raidEvent(job.channelId)
            settle(100)
            if mode = "ask"
                check(m.scene.dialog <> invalid and m.scene.dialog.buttons[0] = "Join raid", "default asks before navigating")
                check(player.state <> "done" and player.raidRequested = invalid, "prompt keeps current playback owner")
                check(player.CallFunc("fixtureRead").raidOfferTimer = invalid, "visible Ask prompt does not recreate the deferred-offer timer")
                player.CallFunc("fixtureExpireRaidOffer")
                check(player.CallFunc("fixtureRead").raidOffer <> invalid and m.scene.dialog <> invalid, "elapsed deferred deadline cannot erase a visible destination")
                laterRaid = raidEvent(job.channelId)
                laterRaid.login = "another_destination"
                job.raid = laterRaid
                check(player.CallFunc("fixtureRead").raidOffer.login = "destination", "later event cannot silently replace the displayed destination")
                dialog = m.scene.dialog
                dialog.buttonSelected = 1
                settle(250)
                check(m.scene.dialog = invalid and player.raidRequested = invalid and player.state <> "done", "Stay keeps playback")
                ' A second distinct event can be accepted explicitly.
                job.raid = raidEvent(job.channelId)
                settle(100)
                player.CallFunc("fixtureExpireRaidOffer")
                m.scene.dialog.buttonSelected = 0
            end if
            settle(250)
            check(player.state = "done" and player.raidRequested <> invalid, "join publishes only after normal exit")
            destination = player.raidRequested
            check(destination.contentType = "LIVE" and destination.streamerLogin = "destination" and destination.streamerId = "456", "handoff creates destination identity")
            check(job.stopRequested and job.control = "run", "handoff stops worker")
        end if
        closePlayer(player)
    end for
    set_user_setting("playback.raids", "ask")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("source")
    video = waitVideo(player, invalid)
    job = player.CallFunc("fixtureRead").raidTask
    video.state = "playing"
    player.CallFunc("fixtureRaidStartup", true)
    job.raid = raidEvent(job.channelId)
    check(player.CallFunc("fixtureRead").bufferTimer = invalid, "raid offer cancels the pending native startup timer")
    m.scene.dialog.buttonSelected = 1
    timer = player.CallFunc("fixtureRead").bufferTimer
    check(timer <> invalid and timer.duration = 15 and timer.control = "start", "Stay restores the remaining absolute startup deadline even when Video reports playing")
    player.CallFunc("fixtureRaidStartup", false)
    closePlayer(player)

    for each endState in ["finished", "error"]
        for each outcome in ["raid", "stay", "dismiss", "back", "timeout", "resume"]
            player = openPlayer("LIVE")
            contentTask(player).response = playable("source")
            video = waitVideo(player, invalid)
            job = player.CallFunc("fixtureRead").raidTask
            video.state = endState
            settle(50)
            timer = player.CallFunc("fixtureRead").raidEndTimer
            check(player.state <> "done" and timer <> invalid and timer.duration = 120 and m.scene.dialog.title = "Stream ended", "finished or error stream retains a bounded connected raid watcher")
            if outcome = "raid" or outcome = "stay" or outcome = "dismiss"
                job.raid = raidEvent(job.channelId)
                check(m.scene.dialog.title = "Streamer raid" and timer.control = "stop", "completed raid replaces the owned end notice")
                if outcome = "raid"
                    m.scene.dialog.buttonSelected = 0
                    check(player.raidRequested <> invalid and player.state = "done", "raid after stream end still hands off")
                else
                    if outcome = "stay"
                        m.scene.dialog.buttonSelected = 1
                    else
                        m.scene.dialog.wasClosed = true
                    end if
                    check(player.state = "done" and player.raidRequested = invalid and job.stopRequested and job.control = "run", "declined post-end raid exits and stops its watcher")
                end if
            else if outcome = "back"
                player.CallFunc("requestBack")
                check(player.state = "done" and timer.control = "stop", "Back leaves the waiting player immediately")
            else if outcome = "timeout"
                player.CallFunc("fixtureRaidExpire")
                check(player.state = "done" and timer.control = "stop", "waiting timeout leaves through normal cleanup")
            else
                video.state = "playing"
                check(timer.control = "stop" and m.scene.dialog = invalid and video.IsInFocusChain(), "resumed playback cancels the waiting timer and restores focus")
            end if
            closePlayer(player)
        end for
    end for
    for each action in ["join", "stay"]
        player = openPlayer("LIVE")
        contentTask(player).response = playable("source")
        video = waitVideo(player, invalid)
        job = player.CallFunc("fixtureRead").raidTask
        player.CallFunc("fixtureRecovery", "stall")
        pending = player.CallFunc("fixtureRead").reconnectTimer
        job.raid = raidEvent(job.channelId)
        dialog = m.scene.dialog
        check(pending <> invalid and pending.control = "stop" and player.CallFunc("fixtureRead").reconnectTimer = invalid, "raid arrival cancels scheduled recovery before it can replace the prompt")
        video.state = "error"
        player.CallFunc("fixtureRecoverNow")
        check(m.scene.dialog.IsSameNode(dialog) and player.CallFunc("fixtureRead").video.IsSameNode(video) and player.CallFunc("fixtureRead").reconnectTask = invalid, "error after raid preserves prompt and Video without starting recovery")
        if action = "join"
            dialog.buttonSelected = 0
            check(player.state = "done" and player.raidRequested <> invalid, "Join works after raid then error")
        else
            dialog.buttonSelected = 1
            check(player.state = "done" and player.raidRequested = invalid and job.stopRequested, "Stay after raid then error exits normally")
        end if
        closePlayer(player)
    end for
    player = openPlayer("LIVE")
    contentTask(player).response = playable("source")
    video = waitVideo(player, invalid)
    job = player.CallFunc("fixtureRead").raidTask
    modal = CreateObject("roSGNode", "StandardMessageDialog")
    modal.title = "Other modal"
    modal.buttons = ["Continue"]
    m.scene.dialog = modal
    modal.SetFocus(true)
    video.state = "finished"
    job.raid = raidEvent(job.channelId)
    check(player.CallFunc("fixtureRead").raidOfferTimer <> invalid and m.scene.dialog.IsSameNode(modal), "post-end raid stays deferred behind a foreign modal")
    player.CallFunc("fixtureExpireRaidOffer")
    check(player.state = "done" and job.stopRequested and job.control = "run", "expired deferred post-end offer exits and stops the watcher")
    check(m.scene.dialog.IsSameNode(modal), "expiring a deferred offer never replaces the foreign modal")
    closePlayer(player)
    player = openPlayer("LIVE")
    contentTask(player).response = playable("source")
    video = waitVideo(player, invalid)
    job = player.CallFunc("fixtureRead").raidTask
    modal = CreateObject("roSGNode", "StandardMessageDialog")
    modal.title = "Other modal"
    modal.buttons = ["Continue"]
    m.scene.dialog = modal
    modal.SetFocus(true)
    job.raid = raidEvent(job.channelId)
    settle(100)
    check(m.scene.dialog.IsSameNode(modal), "raid never replaces another modal")
    m.scene.dialog = invalid
    player.SetFocus(true)
    player.CallFunc("fixtureRaidOffer")
    check(m.scene.dialog <> invalid and m.scene.dialog.title = "Streamer raid", "offer resumes after other modal")
    set_setting("active_user", "another-viewer")
    m.scene.dialog.buttonSelected = 0
    settle(100)
    check(player.raidRequested = invalid, "changed account cannot join old offer")
    closePlayer(player)
    check(job.stopRequested and job.control = "run", "destruction stops worker")
    job.raid = raidEvent(job.channelId)
    settle(100)
    check(m.scene.dialog = invalid and player.raidRequested = invalid, "late worker delivery after destruction is ignored")

    set_setting("active_user", "$default$")
    player = openPlayer("LIVE")
    contentTask(player).response = playable("source")
    video = waitVideo(player, invalid)
    check(player.CallFunc("fixtureRead").raidTask = invalid, "signed-out playback requires no raid auth")
    closePlayer(player)
    fixtureEnd()
end sub

function raidEvent(source as string) as object
    return { sourceId: source, messageId: "raid-" + m.assertions.ToStr(), id: "456", login: "destination", name: "Destination" }
end function
