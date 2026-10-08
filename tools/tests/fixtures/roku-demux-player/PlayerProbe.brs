' Read-only inspection and direct calls to actual production handlers.
function fixtureRead() as object
    return { task: m.PlayVideo, video: m.video, session: m.rokuSession, sessionId: m.rokuSessionId, chosen: m.rokuChosen, pendingContent: m.rokuPendingContent, prepared: m.rokuPreparedContent, deferred: m.rokuDeferredPlay, exitPending: m.rokuExitPending, pending: m.manualRetryPending, errorDialog: m.errorDialog, transmuxDialog: m.transmuxDialog, recovery: m.recoveryAttempts, reconnect: m.reconnectAttempts, reconnectTask: m.reconnectTask, retryTimer: m.retryTimer, disposed: m.disposed }
end function
sub fixtureChoiceAgain()
    onTransmuxDialogButton()
end sub
sub fixtureEventAgain()
    onRokuSessionEvent()
end sub
sub fixtureRetry()
    retryAfterError()
end sub
sub fixtureReconnect()
    doLiveReconnect()
end sub
sub fixtureRecovery(count as integer)
    m.recoveryAttempts = count
    m.reconnectAttempts = count
end sub
sub fixtureBack()
    ignored = onKeyEvent("back", true)
end sub
