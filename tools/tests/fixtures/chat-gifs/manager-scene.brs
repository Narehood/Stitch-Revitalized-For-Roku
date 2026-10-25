sub init()
    initChatAnimations()
    m.disposed = false
    m.chatPanel = createObject("roSGNode", "Group")
    m.chatPanel.addFields({ width: 600.0, height: 400.0 })
    m.top.appendChild(m.chatPanel)
    m.hypePanel = createObject("roSGNode", "Group")
    m.hypePanel.visible = false
    m.pinPanel = createObject("roSGNode", "Group")
    m.pinPanel.visible = false
    m.checks = 0
    m.failures = 0
end sub

sub runFixture()
    m.animateChatEmotes = true
    uri = "https://media4.giphy.com/media/joSNxeswxuc74Juo8X/giphy.gif?cid=095d7a5dzizsiwgabonagkmigggv8v1spfai91ac3x0dsiy0&ep=v1_gifs_trending&rid=giphy.gif&ct=g"
    m.animatedEmotes[uri] = { provider: "twitch-gif", uri: uri, format: "gif" }
    owner = fixtureWrapper(uri, 0)
    duplicate = fixtureWrapper(uri, 110)
    syncChatAnimation()
    check(m.animationOwner.isSameNode(owner), "first visible occurrence owns the slot")
    check(m.animationTask.request.uri = uri and m.animationTask.request.path.right(10) = "/emote.gif", "GIF descriptor retains full URI and selects local .gif")
    check(owner.getChild(0).visible and owner.getChild(0).getChild(0).text = "[GIF title]", "readable Group fallback remains during load")
    fixtureComplete({ format: "gif", bytes: 998959, width: 480, height: 480, loadWidth: 64, loadHeight: 64 })
    native = m.animationNative
    check(native <> invalid and native.uri.right(4) = ".gif" and native.mimeType = "", "GIF relies on local extension/autodetection without invented MIME hint")
    check(native.width = 96 and native.height = 96 and native.loadWidth = 64 and native.loadHeight = 64, "Group display fields are independent of decode cap")
    native.state = "first"
    check(not owner.getChild(0).visible and duplicate.getChild(0).visible, "scripted native readiness hides only the owner's Group fallback")
    syncChatAnimation()
    check(m.animationNative.isSameNode(native) and m.animationOwner.isSameNode(owner), "duplicate URI cannot hop/restart native owner")
    native.state = "error"
    check(owner.getChild(0).visible and owner.getChild(0).getChild(0).text = "[GIF title]", "runtime error restores the retained readable title")
    check(m.animationNative = invalid and native.getParent() = invalid and m.animationFailed.doesExist(uri), "failed native occurrence is removed and suppressed")
    fixtureComplete(invalid)
    check(m.animationCache.count() = 0 and m.animationPartials.count() = 0 and m.global.chatAnimationStorageOwners.count() = 0, "acknowledged cleanup releases existing global reservation")
    m.chatPanel.removeChildrenIndex(-1, 0)
    staticUri = "https://cdn.betterttv.net/emote/example/static/1x.webp"
    m.animatedEmotes[staticUri] = { uri: "https://cdn.betterttv.net/emote/example/1x.webp" }
    owner = fixtureWrapper(staticUri, 0)
    syncChatAnimation()
    check(m.animationTask.request.path.right(11) = "/emote.webp", "existing provider descriptor keeps WebP path")
    fixtureComplete({ bytes: 3842, loadWidth: 32, loadHeight: 32 })
    check(m.animationNative.mimeType = "video/webp", "existing WebP MIME hint preserved")
    m.animationNative.state = "error"
    fixtureComplete(invalid)
    check(owner.getChild(0).visible and m.global.chatAnimationStorageOwners.count() = 0, "WebP runtime fallback/cleanup remain unchanged")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
end sub

function fixtureWrapper(uri as string, x as integer) as object
    wrapper = createObject("roSGNode", "Group")
    wrapper.translation = [x, 0]
    wrapper.addFields({ chatImageUri: uri })
    fallback = createObject("roSGNode", "Group")
    fallback.addFields({ width: 96.0, height: 96.0 })
    label = createObject("roSGNode", "Label")
    label.text = "[GIF title]"
    fallback.appendChild(label)
    wrapper.appendChild(fallback)
    m.chatPanel.appendChild(wrapper)
    return wrapper
end function

' No worker/decoder runs here. The production manager handles native state and
' completion boundaries; Task filesystem/network behavior has its own suite.
function fixtureAssetTask() as object
    task = createObject("roSGNode", "Group")
    task.addFields({ request: {}, response: {}, state: "", control: "", stopRequested: false })
    return task
end function

sub fixtureComplete(info as dynamic)
    task = m.animationTask
    check(task <> invalid, "expected bounded worker/cleanup slot")
    if task = invalid then return
    request = task.request
    task.response = { generation: request.generation, uri: request.uri, path: request.path, info: info, removed: request.paths, cleanupOk: true }
    task.state = "done"
end sub

sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
