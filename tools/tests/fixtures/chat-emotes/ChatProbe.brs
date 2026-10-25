function fixtureBuild(text as string, start = -1 as float) as object
    if start < 0 then start = m.left_bound
    group = buildMessage(text, start)
    m.top.appendChild(group)
    return group
end function

function fixtureState() as object
    builds = 0
    if m.fixtureBuilds <> invalid then builds = m.fixtureBuilds
    return { left: m.left_bound, right: m.right_bound, failed: m.failedChatImages.count(), builds: builds, compiled: m.emojiRegex <> invalid, panel: m.chatPanel, job: m.chat }
end function

sub fixturePrune(group as object)
    releaseChatImages(group)
    m.top.removeChild(group)
end sub

sub fixtureImageStatus(poster as object, status as string)
    onChatImageStatus({ node: poster, status: status, getRoSGNode: fixtureEventNode, getData: fixtureEventData })
end sub

function fixtureEventNode() as object
    return m.node
end function

function fixtureEventData() as string
    return m.status
end function

sub fixtureModerateRoom()
    removeModerated({ kind: "room", id: "", userId: "", login: "" })
end sub
