sub init()
    m.disposed = false
    m.worker = invalid
    m.video = invalid
    m.pending = invalid
    m.currentId = ""
    m.workerResult = invalid
    m.stopping = false
    m.transitioning = false
    m.readyReceived = false
    m.cleanupFailed = false
    m.blockedExitNotified = false
    m.blockedPendingId = ""
    m.cleanupClock = invalid
    m.cleanupTimer = m.top.findNode("cleanupTimer")
    if m.cleanupTimer <> invalid then m.cleanupTimer.observeField("fire", "onCleanupTick")
end sub

function startSession(descriptor as object) as string
    if m.disposed or m.top.cleanupBlocked then return ""
    if not rokuDemuxDescriptorValid(descriptor) then return ""
    ' Retain only the validated primitive snapshot while an older owner stops.
    descriptor = ParseJSON(FormatJSON(descriptor))
    sessionId = LCase(CreateObject("roDeviceInfo").GetRandomUUID()).Replace("-", "")
    if not sessionIdValid(sessionId) then return ""
    if m.worker <> invalid or m.transitioning
        previousPending = m.pending
        m.pending = { id: sessionId, descriptor: descriptor }
        if previousPending <> invalid then sessionEvent(previousPending.id, "cancelled", "superseded")
        if m.worker <> invalid then beginSessionStop()
    else
        beginSession(sessionId, descriptor)
    end if
    return sessionId
end function

function sessionIdValid(value as string) as boolean
    if value.Len() <> 32 then return false
    for index = 0 to 31
        if "0123456789abcdef".InStr(value.Mid(index, 1)) < 0 then return false
    end for
    return true
end function

sub beginSession(sessionId as string, descriptor as object)
    m.currentId = sessionId
    m.workerResult = invalid
    m.stopping = false
    m.readyReceived = false
    m.cleanupFailed = false
    m.blockedExitNotified = false
    m.blockedPendingId = ""
    m.cleanupClock = invalid
    m.worker = CreateObject("roSGNode", "RokuDemuxServer")
    if m.worker = invalid
        m.currentId = ""
        sessionEvent(sessionId, "failed", "worker_unavailable")
        return
    end if
    m.worker.observeField("ready", "onSessionReady")
    m.worker.observeField("result", "onSessionResult")
    m.worker.observeField("state", "onSessionWorkerState")
    m.worker.sessionId = sessionId
    m.worker.inputDescriptor = descriptor
    ' The player calls startSession only after its explicit experimental opt-in.
    m.worker.experimentalMode = true
    m.worker.cacheBudgetBytes = 16777216
    if descriptor["metadata"]["height"] > 720 then m.worker.cacheBudgetBytes = 33554432
    m.worker.listenPort = 0
    m.worker.stopRequested = false
    m.worker.functionName = "runServer"
    m.top.busy = true
    sessionEvent(sessionId, "starting", "")
    m.worker.control = "run"
end sub

function attachVideo(sessionId as string, video as object) as boolean
    if m.disposed or m.stopping or m.worker = invalid or sessionId <> m.currentId then return false
    if type(video) <> "roSGNode" then return false
    if not video.hasField("state") or not video.hasField("control") then return false
    if m.video <> invalid
        if not m.video.isSameNode(video) then return false
        return true
    end if
    m.video = video
    m.video.observeFieldScoped("state", "onSessionVideoState")
    return true
end function

sub stopSession(sessionId as string)
    if m.pending <> invalid
        if sessionId = "" or sessionId = m.pending.id
            cancelled = m.pending
            m.pending = invalid
            sessionEvent(cancelled.id, "cancelled", "cancelled_before_start")
        end if
    end if
    if m.worker <> invalid
        if sessionId = "" or sessionId = m.currentId then beginSessionStop()
    end if
end sub

sub beginSessionStop()
    if m.worker = invalid then return
    if not m.stopping
        m.stopping = true
        m.cleanupClock = CreateObject("roTimespan")
        if m.cleanupTimer <> invalid then m.cleanupTimer.control = "start"
        sessionEvent(m.currentId, "stopping", "")
    end if
    if m.video <> invalid then m.video.control = "stop"
    m.worker.stopRequested = true
    checkSessionCleanup()
end sub

sub onSessionReady()
    if m.disposed or m.stopping or m.readyReceived or m.worker = invalid then return
    ready = m.worker.ready
    if type(ready) <> "roAssociativeArray" then return
    if not rokuDemuxString(ready.sessionId) then return
    if ready.sessionId <> m.currentId then return
    if not validSessionReady(ready)
        sessionEvent(m.currentId, "failed", "invalid_ready")
        beginSessionStop()
        return
    end if
    m.readyReceived = true
    m.top.event = { id: m.currentId, status: "ready", reason: "", url: "http://127.0.0.1:" + ready.boundPort.ToStr() + "/master.m3u8", metadata: ready.metadata }
end sub

function validSessionReady(ready as object) as boolean
    if not rokuDemuxString(ready.sessionId) then return false
    if not sessionIdValid(ready.sessionId) then return false
    kind = type(ready.boundPort, 3)
    if kind <> "Integer" and kind <> "LongInteger" and kind <> "roInt" then return false
    if ready.boundPort < 49152 or ready.boundPort > 65535 then return false
    if not rokuDemuxString(ready.boundAddressText) then return false
    if ready.boundAddressText <> "127.0.0.1" and ready.boundAddressText <> "127.0.0.1:" + ready.boundPort.ToStr() and ready.boundAddressText <> "127.0.0.1:" + (ready.boundPort - 65536).ToStr() then return false
    if type(ready.decoderApproved, 3) <> "Boolean" and type(ready.decoderApproved, 3) <> "roBoolean" then return false
    if not ready.decoderApproved then return false
    if type(ready.actualInitValidated, 3) <> "Boolean" and type(ready.actualInitValidated, 3) <> "roBoolean" then return false
    if not ready.actualInitValidated then return false
    if type(ready.metadata) <> "roAssociativeArray" then return false
    return true
end function

sub onSessionResult()
    if m.worker = invalid then return
    result = m.worker.result
    if type(result) <> "roAssociativeArray" then return
    if not rokuDemuxString(result.sessionId) then return
    if result.sessionId <> m.currentId then return
    m.workerResult = result
    if not m.stopping
        sessionEvent(m.currentId, "failed", "worker_finished")
        beginSessionStop()
    end if
    checkSessionCleanup()
end sub

sub onSessionWorkerState()
    if m.worker = invalid then return
    if m.worker.state = "stop" and not m.stopping
        sessionEvent(m.currentId, "failed", "worker_stopped")
        beginSessionStop()
    end if
    checkSessionCleanup()
end sub

sub onSessionVideoState()
    owner = m.worker
    ownerId = m.currentId
    checkSessionCleanup()
    if owner = invalid or m.worker = invalid or not m.top.cleanupBlocked then return
    if m.currentId <> ownerId or not m.worker.isSameNode(owner) then return
    if m.blockedExitNotified or not canLeaveBlockedSession(ownerId) then return
    m.blockedExitNotified = true
    cancelledId = m.blockedPendingId
    sessionEvent(ownerId, "failed", "cleanup_blocked")
    if cancelledId <> "" and m.worker <> invalid
        if m.currentId = ownerId and m.worker.isSameNode(owner) then sessionEvent(cancelledId, "failed", "cleanup_blocked")
    end if
end sub

' UI navigation does not release the stopped Video or the retained Task owner.
function canLeaveBlockedSession(sessionId as string) as boolean
    if not m.top.cleanupBlocked or not m.stopping or m.worker = invalid then return false
    if sessionId <> m.currentId
        if m.blockedPendingId = "" or sessionId <> m.blockedPendingId then return false
    end if
    if m.video <> invalid
        if m.video.state <> "stopped" then return false
    end if
    return true
end function

function sessionCleanupAcknowledged() as boolean
    if not m.stopping or m.worker = invalid or m.workerResult = invalid then return false
    if m.worker.state <> "stop" then return false
    if m.video <> invalid
        if m.video.state <> "stopped" then return false
    end if
    return true
end function

function sessionCleanupSafe() as boolean
    for each field in ["cleanupOk", "listenerClosed", "connectionClosed", "helperClosed", "cacheReferencesReleased"]
        if type(m.workerResult[field], 3) <> "Boolean" and type(m.workerResult[field], 3) <> "roBoolean" then return false
        if not m.workerResult[field] then return false
    end for
    return true
end function

sub checkSessionCleanup()
    if m.transitioning then return
    if not sessionCleanupAcknowledged() then return
    if not sessionCleanupSafe()
        blockSessionCleanup("cleanup_failed")
        ' Actual Task/Video stop is acknowledged, so the UI may leave. Unsafe
        ' resource references remain owned and replacement sessions stay blocked.
        if m.cleanupTimer <> invalid then m.cleanupTimer.control = "stop"
        m.cleanupClock = invalid
        m.top.busy = false
        return
    end if
    previousId = m.currentId
    m.transitioning = true
    if m.cleanupTimer <> invalid then m.cleanupTimer.control = "stop"
    if m.video <> invalid then m.video.unobserveFieldScoped("state")
    m.video = invalid
    ' Cleanup and actual state=stop are already acknowledged; no resource owner is force-stopped.
    stoppedWorker = m.worker
    ignored = destroyTask(stoppedWorker, "ready")
    ignored = destroyTask(stoppedWorker, "result")
    m.worker = destroyTask(stoppedWorker, "state")
    m.workerResult = invalid
    m.currentId = ""
    m.stopping = false
    m.cleanupClock = invalid
    m.top.busy = false
    sessionEvent(previousId, "stopped", "")
    m.transitioning = false
    if m.disposed or m.cleanupFailed or m.top.cleanupBlocked
        m.pending = invalid
        if m.disposed and m.cleanupTimer <> invalid then m.cleanupTimer.unobserveField("fire")
        return
    end if
    nextRequest = m.pending
    m.pending = invalid
    if nextRequest <> invalid then beginSession(nextRequest.id, nextRequest.descriptor)
end sub

sub onCleanupTick()
    if not m.stopping or m.worker = invalid then return
    owner = m.worker
    ownerId = m.currentId
    checkSessionCleanup()
    ' Cleanup may synchronously start the queued replacement. This tick belongs
    ' only to its original stopping owner, never the new worker or its clock.
    if not m.stopping or m.worker = invalid or m.cleanupClock = invalid then return
    if m.currentId <> ownerId or not m.worker.isSameNode(owner) then return
    if m.cleanupClock.TotalMilliseconds() >= 15000 then blockSessionCleanup("cleanup_deadline")
    owner.stopRequested = true
end sub

sub blockSessionCleanup(reason as string)
    if m.cleanupFailed then return
    m.cleanupFailed = true
    m.top.cleanupBlocked = true
    cancelled = m.pending
    m.pending = invalid
    if cancelled <> invalid then m.blockedPendingId = cancelled.id
    if cancelled <> invalid then sessionEvent(cancelled.id, "cancelled", "cleanup_blocked")
    m.blockedExitNotified = canLeaveBlockedSession(m.currentId)
    sessionEvent(m.currentId, "failed", reason)
    ' Retain actual worker/video references and observers until their safe stop, even after timeout.
end sub

sub sessionEvent(sessionId as string, status as string, reason as string)
    m.top.event = { id: sessionId, status: status, reason: reason }
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    stopSession("")
    if m.worker = invalid and m.cleanupTimer <> invalid
        m.cleanupTimer.control = "stop"
        m.cleanupTimer.unobserveField("fire")
    end if
end sub
