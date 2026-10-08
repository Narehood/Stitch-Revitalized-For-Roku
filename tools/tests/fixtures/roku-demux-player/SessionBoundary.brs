sub init()
    m.serial = 0
    m.top.calls = []
end sub

sub recordCall(item as object)
    calls = m.top.calls
    calls.push(item)
    m.top.calls = calls
end sub

function startSession(descriptor as object) as string
    m.serial += 1
    id = "fixture-session-" + m.serial.toStr()
    if m.top.refuseStart then id = ""
    recordCall({ action: "start", id: id, descriptor: descriptor })
    if id <> "" then m.top.busy = true
    return id
end function

function attachVideo(id as string, video as object) as boolean
    ' Capture the actual wrapper state at the call, before content/play.
    recordCall({ action: "attach", id: id, node: video, contentEmpty: video.content = invalid, control: video.control, allowed: m.top.allowAttach })
    return m.top.allowAttach
end function

sub stopSession(id as string)
    recordCall({ action: "stop", id: id })
    ' Busy stays true until the fixture explicitly supplies the manager ack.
end sub
