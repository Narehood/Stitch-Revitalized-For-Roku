function fixturePlayer() as object
    return { task: m.PlayVideo, video: m.video, chat: m.chatWindow, engagement: m.engagementTask, relay: m.lowLatencyRelay, sessionId: m.rokuSessionId, exitPending: m.rokuExitPending, disposed: m.disposed }
end function

sub fixtureReplaceWrapper()
    playContent()
end sub

sub fixturePlaybackError()
    showErrorDialog("Canned playback error", "Canned recovery advice")
end sub

sub fixtureDeliverOpenChannel(video as object)
    event = { owner: video, getRoSGNode: function() as object
        return m.owner
    end function }
    onChannelActionsRequested(event)
end sub
