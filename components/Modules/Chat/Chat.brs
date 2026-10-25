sub init()
    m.disposed = false
    m.chatPanel = m.top.findNode("chatPanel")
    m.chatBackground = m.top.findNode("chatBackground")
    m.chatStatus = m.top.findNode("chatStatus")
    m.hypePanel = m.top.findNode("hypePanel")
    m.hypeTitle = m.top.findNode("hypeTitle")
    m.hypeDetail = m.top.findNode("hypeDetail")
    m.hypeTrack = m.top.findNode("hypeTrack")
    m.hypeProgress = m.top.findNode("hypeProgress")
    m.hypeTimer = invalid
    m.hypeAge = invalid
    m.pinPanel = m.top.findNode("pinPanel")
    m.pinTitle = m.top.findNode("pinTitle")
    m.pinAuthor = m.top.findNode("pinAuthor")
    m.pinText = m.top.findNode("pinText")
    m.pinHint = m.top.findNode("pinHint")
    m.pinTitle.text = tr("Pinned message")
    m.pinHint.text = tr("Press Down to read the full message")
    m.pinTimer = invalid
    m.pinAge = invalid
    m.pinDialog = invalid
    m.pinModeration = []
    m.pinSuppressedMessageId = ""
    m.maskgroup = m.top.findNode("maskGroup")
    m.chat = invalid
    m.hasRenderedComment = false
    m.chatPresentationState = ""
    m.moderationSeq = 0
    m.EmoteJob = invalid
    m.emoteChannel = ""
    m.emoteChannelId = ""
    ' Rendering helpers built once per chat instance, not per message or word.
    m.hexColorRegex = CreateObject("roRegex", "^[A-Fa-f0-9]{6}$", "")
    m.urlRegex = CreateObject("roRegex", "https?:\/\/[a-zA-Z0-9\.]+", "i")
    m.bitsRegex = createObject("roRegex", "^[1-9][0-9]{0,8}$", "")
    m.nameColorCache = {}
    m.emojiRegex = invalid
    m.emojiRegexFailed = false
    m.failedChatImages = {}
    m.linkColor = "0xBF94FFFF"
    if m.global?.constants?.ui?.color?.link <> invalid then m.linkColor = m.global.constants.ui.color.link
    m.top.observeField("visible", "onInvisible")
    onBackgroundColorChange()
    setChatPanelSize()
    setSizingParameters()
    ' determines how far down the screen the first message will appear
    ' set to 700 to have first message at bottom of screen.
    m.translation = m.lower_bound - m.line_height
end sub

sub updatePanelTranslation()
    ' m.chatPanel.translation = [(m.top.width * 3), 0]
    if m.maskGroup = invalid or m.global = invalid or m.global.constants = invalid then return
    setChatPanelSize()
    setSizingParameters()
    m.maskGroup.maskSize = [(m.chatpanel.width * m.global.constants.maskScaleFactor), (m.chatPanel.height * m.global.constants.maskScaleFactor)]
    m.maskGroup.maskOffset = [0, 0]
    for each chatmessage in m.chatPanel.getChildren(-1, 0)
        removeChatMessage(chatmessage)
    end for
end sub

sub setSizingParameters()
    m.left_bound = m.font_size / 2
    m.right_bound = m.chatPanel.width - m.font_size
    m.badge_size = (m.font_size * 1.6)
    m.line_gap = m.font_size * 0.25
    m.line_height = (m.font_size * 1.4)

    m.message_height = (m.badge_size * 1.8)

    m.lower_bound = m.chatPanel.height - m.message_height
end sub

sub setChatPanelSize()
    m.chatPanel.width = m.top.width
    m.chatPanel.height = m.top.height
    m.chatBackground.width = m.top.width
    m.chatBackground.height = m.top.height
    m.chatStatus.width = m.top.width - 24
    m.hypePanel.width = m.top.width
    m.hypeTitle.width = m.top.width - 24
    m.hypeDetail.width = m.top.width - 24
    m.hypeTrack.width = m.top.width - 24
    m.pinPanel.width = m.top.width
    for each label in [m.pinTitle, m.pinAuthor, m.pinText, m.pinHint]
        label.width = m.top.width - 24
    end for
    updateHypeTrain()
    updatePinnedMessage()
    m.font_size = m.top.fontSize
    m.translation = m.chatPanel.height - m.font_size
    m.lower_bound = m.chatPanel.height - m.font_size
    m.right_bound = m.chatPanel.width - m.font_size
    m.upper_bound = 0 - (m.chatPanel.height - m.font_size)
end sub

sub onInvisible()
    if m.disposed then return
    if m.top.visible
        startChatJob()
        startEmoteJob()
    else
        stopJobs()
    end if
    updateHypeTrain()
    updatePinnedMessage()
end sub

sub onHypeTrainChange()
    if m.disposed then return
    m.hypeAge = createObject("roTimespan")
    updateHypeTrain()
end sub

' Polling data is only a snapshot. A missing refresh, hidden panel or expired
' provider deadline hides the banner rather than extrapolating train progress.
sub updateHypeTrain()
    if m.hypePanel = invalid then return
    hype = m.top.hypeTrain
    valid = not m.disposed and m.top.visible and m.hypeAge <> invalid and GetInterface(hype, "ifAssociativeArray") <> invalid
    if valid
        valid = GetInterface(hype.level, "ifInt") <> invalid and GetInterface(hype.percent, "ifInt") <> invalid
        valid = valid and (GetInterface(hype.expiresAt, "ifInt") <> invalid or GetInterface(hype.expiresAt, "ifDouble") <> invalid or GetInterface(hype.expiresAt, "ifLongInt") <> invalid)
        valid = valid and (GetInterface(hype.observedAt, "ifInt") <> invalid or GetInterface(hype.observedAt, "ifDouble") <> invalid or GetInterface(hype.observedAt, "ifLongInt") <> invalid)
    end if
    if valid
        nowSeconds = createObject("roDateTime").asSeconds()
        remaining = hype.expiresAt - nowSeconds
        sourceAge = nowSeconds - hype.observedAt
        valid = m.hypeAge.totalMilliseconds() <= 45000 and sourceAge >= -2 and sourceAge <= 45 and remaining > 0 and remaining <= 3600 and hype.level > 0 and hype.percent >= 0 and hype.percent <= 100
    end if
    m.hypePanel.visible = valid
    layoutChatHeaders()
    if not valid
        if m.hypeTimer <> invalid then m.hypeTimer.control = "stop"
        return
    end if
    title = tr("Hype Train · Level {0}")
    if hype.status = "ended" then title = tr("Hype Train ended · Level {0}")
    m.hypeTitle.text = title.replace("{0}", hype.level.toStr())
    seconds = (int(remaining) mod 60).toStr()
    if seconds.len() < 2 then seconds = "0" + seconds
    duration = int(remaining / 60).toStr() + ":" + seconds
    m.hypeDetail.text = tr("{0}% · {1} remaining").replace("{0}", hype.percent.toStr()).replace("{1}", duration)
    if hype.status = "ended" then m.hypeDetail.text = ""
    m.hypeProgress.width = (m.top.width - 24) * hype.percent / 100.0
    if m.hypeTimer = invalid
        m.hypeTimer = createObject("roSGNode", "Timer")
        m.hypeTimer.duration = 1
        m.hypeTimer.repeat = true
        m.top.appendChild(m.hypeTimer)
        m.hypeTimer.observeField("fire", "updateHypeTrain")
    end if
    if m.hypeTimer.control <> "start" then m.hypeTimer.control = "start"
end sub

sub layoutChatHeaders()
    offset = 0
    if m.hypePanel <> invalid and m.hypePanel.visible then offset = 76
    if m.pinPanel <> invalid
        m.pinPanel.translation = [0, offset]
        if m.pinPanel.visible then offset += 176
    end if
    if m.chatStatus <> invalid then m.chatStatus.translation = [12, offset + 12]
end sub

sub onPinnedMessageChange()
    if m.disposed then return
    m.pinAge = createObject("roTimespan")
    updatePinnedMessage()
end sub

sub updatePinnedMessage()
    if m.pinPanel = invalid then return
    pin = m.top.pinnedMessage
    valid = not m.disposed and m.top.visible and m.pinAge <> invalid and GetInterface(pin, "ifAssociativeArray") <> invalid
    if valid
        valid = GetInterface(pin.id, "ifString") <> invalid and GetInterface(pin.senderName, "ifString") <> invalid and GetInterface(pin.text, "ifString") <> invalid
        valid = valid and (GetInterface(pin.observedAt, "ifInt") <> invalid or GetInterface(pin.observedAt, "ifDouble") <> invalid or GetInterface(pin.observedAt, "ifLongInt") <> invalid)
        valid = valid and (GetInterface(pin.updatedAt, "ifInt") <> invalid or GetInterface(pin.updatedAt, "ifDouble") <> invalid or GetInterface(pin.updatedAt, "ifLongInt") <> invalid)
        valid = valid and GetInterface(pin.messageId, "ifString") <> invalid and GetInterface(pin.userId, "ifString") <> invalid and GetInterface(pin.login, "ifString") <> invalid
    end if
    if valid
        nowSeconds = createObject("roDateTime").asSeconds()
        age = nowSeconds - pin.observedAt
        valid = pin.text <> "" and pin.text.len() <= 1500 and pin.senderName.len() <= 128 and pin.id <> "" and age >= -2 and age <= 45 and m.pinAge.totalMilliseconds() <= 45000
        if pin.expiresAt <> invalid
            numericExpiry = GetInterface(pin.expiresAt, "ifInt") <> invalid or GetInterface(pin.expiresAt, "ifDouble") <> invalid or GetInterface(pin.expiresAt, "ifLongInt") <> invalid
            valid = valid and numericExpiry
            if numericExpiry then valid = valid and pin.expiresAt > nowSeconds
        end if
        if valid
            if pinnedMessageModerated(pin) then m.pinSuppressedMessageId = pin.messageId
            valid = pin.messageId <> m.pinSuppressedMessageId
        end if
    end if
    m.pinPanel.visible = valid
    layoutChatHeaders()
    if not valid
        closePinnedMessage()
        if m.pinTimer <> invalid then m.pinTimer.control = "stop"
        return
    end if
    key = pin.id + ":" + pin.updatedAt.toStr()
    if m.pinDialog <> invalid and m.pinDialogKey <> key then closePinnedMessage()
    m.pinAuthor.text = pin.senderName
    m.pinText.text = pin.text
    if m.pinTimer = invalid
        m.pinTimer = createObject("roSGNode", "Timer")
        m.pinTimer.duration = 1
        m.pinTimer.repeat = true
        m.top.appendChild(m.pinTimer)
        m.pinTimer.observeField("fire", "updatePinnedMessage")
    end if
    if m.pinTimer.control <> "start" then m.pinTimer.control = "start"
end sub

function pinnedMessageModerated(pin as object) as boolean
    if GetInterface(pin.sentAt, "ifInt") = invalid and GetInterface(pin.sentAt, "ifLongInt") = invalid and GetInterface(pin.sentAt, "ifDouble") = invalid then return true
    identity = { id: pin.messageId, userId: pin.userId, login: pin.login }
    for each event in m.pinModeration
        if event.kind = "message"
            if moderationMatches(identity, event) then return true
        else if pin.sentAt <= event.at and moderationMatches(identity, event)
            return true
        end if
    end for
    return false
end function

function showPinnedMessage() as boolean
    updatePinnedMessage()
    if not m.pinPanel.visible then return false
    scene = m.top.getScene()
    if scene = invalid or scene.dialog <> invalid then return false
    pin = m.top.pinnedMessage
    focus = scene
    for i = 0 to 31
        child = focus.focusedChild
        if child = invalid then exit for
        if child.isSameNode(focus) then exit for
        focus = child
    end for
    m.pinLastFocus = focus
    dialog = createObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Pinned message")
    dialog.message = [pin.senderName, pin.text]
    dialog.buttons = [tr("Continue watching")]
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "closePinnedMessage")
    dialog.observeField("wasClosed", "closePinnedMessage")
    m.pinDialog = dialog
    m.pinDialogKey = pin.id + ":" + pin.updatedAt.toStr()
    scene.dialog = dialog
    return true
end function

sub closePinnedMessage()
    dialog = m.pinDialog
    if dialog = invalid then return
    m.pinDialog = invalid
    m.pinDialogKey = ""
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.isSameNode(dialog) then scene.dialog = invalid
    end if
    focus = m.pinLastFocus
    m.pinLastFocus = invalid
    if not m.disposed and m.top.visible and scene <> invalid and focus <> invalid
        if scene.dialog = invalid and focus.getScene() <> invalid then focus.setFocus(true)
    end if
end sub

sub onBackgroundColorChange()
    if m.chatPanel <> invalid then m.chatPanel.color = m.top.backgroundColor
    if m.chatBackground <> invalid then m.chatBackground.color = m.top.backgroundColor
    ' Readable name colors depend on the background.
    m.nameColorCache = {}
end sub

' Stops the ChatJob (IRC) and EmoteJob tasks and releases their observers.
' Called from VideoPlayer.exitPlayer() so the IRC socket loop and emote
' fetcher are torn down at user-initiated exit and explicit component disposal.
'
' Uses destroyTask() per AGENTS.md: unobserve first so any in-flight
' nextCommentObj callback is suppressed before the task thread halts.
sub stopJobs()
    stopChatJob()
    stopEmoteJob()
end sub

sub stopEmoteJob()
    if m.EmoteJob <> invalid
        emoteJob = m.EmoteJob
        m.EmoteJob = invalid
        if emoteJob.completed and emoteJob.cacheComplete
            m.emoteChannel = emoteJob.channel
            m.emoteChannelId = emoteJob.channel_id
        end if
        emoteJob.stopRequested = true
        destroyTask(emoteJob, "completed")
        m.top.removeChild(emoteJob)
    end if
end sub

sub onVideoChange()
    if m.disposed then return
    stopChatJob()
    if m.top.control and m.top.visible then startChatJob()
end sub

sub onEnterChannel()
    if m.disposed then return
    m.top.hypeTrain = invalid
    m.top.pinnedMessage = invalid
    m.pinModeration = []
    m.pinSuppressedMessageId = ""
    stopJobs()
    for each message in m.chatPanel.getChildren(-1, 0)
        removeChatMessage(message)
    end for
    m.failedChatImages = {}
    m.translation = m.lower_bound - m.line_height
    m.emoteChannel = ""
    m.emoteChannelId = ""
    if m.top.channel = "" then return
    m.global.setField("emoteCache", {})
    if m.top.visible then startChatJob()
    startEmoteJob()
end sub

sub startChatJob()
    if m.disposed or not m.top.visible then return
    if m.chat <> invalid or m.top.channel = "" then return
    m.chat = createObject("roSGNode", "ChatJob")
    m.top.appendChild(m.chat)
    m.moderationSeq = 0
    m.hasRenderedComment = false
    m.chat.forceLive = m.top.forceLive
    m.chat.delaySeconds = m.top.delaySeconds
    m.chat.observeField("nextCommentObj", "onNewCommentObj")
    m.chat.observeField("moderation", "onModeration")
    m.chat.observeField("connectionState", "onConnectionStateChange")
    m.chat.observeField("deliveryState", "onDeliveryStateChange")
    m.chat.channel = m.top.channel
    updateChatStatus("connecting")
    m.chat.control = "run"
end sub

sub stopChatJob()
    if m.chat <> invalid
        chat = m.chat
        m.chat = invalid
        chat.stopRequested = true
        destroyTask(chat, "nextCommentObj")
        destroyTask(chat, "moderation")
        destroyTask(chat, "connectionState")
        destroyTask(chat, "deliveryState")
        m.top.removeChild(chat)
    end if
    if m.top.connectionState <> "stopped" then m.top.connectionState = "stopped"
    updateChatStatus("stopped")
end sub

function currentChatEvent(event as dynamic) as boolean
    if m.disposed or not m.top.visible or m.chat = invalid then return false
    if event <> invalid then return event.getRoSGNode().isSameNode(m.chat)
    return true
end function

sub onConnectionStateChange(event = invalid as dynamic)
    if not currentChatEvent(event) then return
    state = m.chat.connectionState
    if state = "connecting" or state = "reconnecting" then m.hasRenderedComment = false
    if m.top.connectionState <> state then m.top.connectionState = state
    updateChatStatus(state)
end sub

sub onDeliveryStateChange(event = invalid as dynamic)
    if not currentChatEvent(event) then return
    updateChatStatus(m.chat.connectionState)
end sub

sub updateChatStatus(state as string)
    if m.chatStatus = invalid then return
    if state = "connected" and not m.hasRenderedComment
        state = "waiting"
        if m.chat <> invalid and m.chat.deliveryState = "syncing" then state = "syncing"
    end if
    if m.chatPresentationState = state then return
    m.chatPresentationState = state
    m.chatStatus.visible = state <> "connected" and state <> "stopped"
    if state = "connecting"
        m.chatStatus.text = tr("Connecting to chat…")
    else if state = "reconnecting"
        m.chatStatus.text = tr("Chat disconnected. Reconnecting…")
    else if state = "unavailable"
        m.chatStatus.text = tr("Chat is unavailable. Close and reopen chat to retry.")
    else if state = "waiting"
        m.chatStatus.text = tr("Waiting for new messages…")
    else if state = "syncing"
        m.chatStatus.text = tr("Syncing chat with video…")
    end if
end sub

sub onChatTimingChange()
    if m.chat <> invalid
        m.chat.forceLive = m.top.forceLive
        m.chat.delaySeconds = m.top.delaySeconds
    end if
end sub

sub startEmoteJob()
    if m.disposed or not m.top.visible or m.top.channel = "" then return
    if m.EmoteJob <> invalid then return
    if m.emoteChannel = m.top.channel and m.emoteChannelId = m.top.channel_id then return
    m.EmoteJob = createObject("roSGNode", "EmoteJob")
    m.top.appendChild(m.EmoteJob)
    m.EmoteJob.channel_id = m.top.channel_id
    m.EmoteJob.channel = m.top.channel
    m.EmoteJob.observeField("completed", "onEmotesCompleted")
    m.EmoteJob.control = "run"
end sub

sub onEmoteChannelIdChange()
    if m.disposed then return
    stopEmoteJob()
    startEmoteJob()
end sub

sub onEmotesCompleted(event = invalid as dynamic)
    if m.disposed or not m.top.visible or m.EmoteJob = invalid then return
    if event <> invalid
        if not event.getRoSGNode().isSameNode(m.EmoteJob) then return
    end if
    if not m.EmoteJob.completed then return
    emoteJob = m.EmoteJob
    m.EmoteJob = invalid
    if emoteJob.cacheComplete
        m.emoteChannel = emoteJob.channel
        m.emoteChannelId = emoteJob.channel_id
    end if
    destroyTask(emoteJob, "completed")
    m.top.removeChild(emoteJob)
end sub

function extractMessage(section) as object
    m.userstate_change = false
    words = section.Split(" ")
    if words[2] = "USERSTATE"
        m.userstate_change = true
    end if
    message = ""
    for i = 4 to words.Count() - 1
        message += words[i] + " "
    end for
    return message
end function

function buildBadges(badges)
    group = createObject("roSGNode", "Group")
    group.visible = true
    badge_translation = 0
    for each badge in badges
        if badge <> invalid and badge <> ""
            if m.global.twitchBadges <> invalid
                if m.global.twitchBadges[badge] <> invalid
                    poster = createObject("roSGNode", "Poster")
                    poster.uri = m.global.twitchBadges[badge]
                    poster.width = m.badge_size
                    poster.height = m.badge_size
                    poster.visible = true
                    poster.translation = [badge_translation, 0]
                    group.appendChild(poster)
                    badge_translation += (m.badge_size + (m.badge_size / 6))
                end if
            end if
        end if
    end for
    return group
end function

function buildEmote(posterUri, fallbackText = "[emoji]" as string)
    poster = createObject("roSGNode", "Poster")
    poster.addFields({ chatFallbackText: fallbackText })
    poster.observeField("loadStatus", "onChatImageStatus")
    poster.uri = posterUri
    poster.visible = true
    bounding_rect = poster.localBoundingRect()
    poster_width = bounding_rect.width
    poster_height = bounding_rect.height
    ratio = 1
    if poster_height <> 0
        ratio = m.badge_size / poster_height
        poster.height = (poster_height * ratio)
    else
        poster.height = m.badge_size
    end if
    if poster_width <> 0
        poster.width = (poster_width * ratio)
    else
        poster.width = m.badge_size
    end if
    return poster
end function

function buildUsername(display_name, color)
    username = createObject("roSGNode", "SimpleLabel")
    username.text = display_name
    username.color = "0x" + readableNameColor(color) + "FF"
    username.visible = true
    username.fontSize = m.font_size
    username.fontUri = "pkg:/fonts/Archivo-Bold.otf"
    return username
end function

' Twitch name colors are chosen by each user. Colors below 4.5:1 against the
' chat background are lightened toward white just enough to reach it, keeping
' their hue. Results are cached per chat instance; the cache holds at most
' 128 colors and starts over when full. Unset or malformed colors stay white.
function readableNameColor(color as dynamic) as string
    if color = invalid or GetInterface(color, "ifString") = invalid then return "FFFFFF"
    if not m.hexColorRegex.isMatch(color) then return "FFFFFF"
    key = UCase(color)
    cached = m.nameColorCache[key]
    if cached <> invalid then return cached
    readable = uiReadableColor(key, m.top.backgroundColor, 4.5)
    if readable = "" then readable = "FFFFFF"
    if m.nameColorCache.count() >= 128 then m.nameColorCache = {}
    m.nameColorCache[key] = readable
    return readable
end function

function buildColon()
    colon = createObject("roSGNode", "SimpleLabel")
    colon.fontSize = m.font_size
    colon.fontUri = "pkg:/fonts/Archivo-Regular.otf"
    colon.color = "0xFFFFFFFF"
    colon.visible = true
    colon.text = ": "
    return colon
end function

function wordOrImage(word, isUrl = false, isNotice = false)
    if not isNotice and m.global.emoteCache.DoesExist(word)
        uri = m.global.emoteCache[word]
        if not m.failedChatImages.doesExist(uri) then return buildEmote(uri, word)
        return chatTextNode(word + " ", isUrl)
    else
        message_text = createObject("roSGNode", "SimpleLabel")
        message_text.fontSize = m.font_size
        message_text.fontUri = "pkg:/fonts/Archivo-Regular.otf"
        message_text.visible = true
        message_text.text = word + " "
        if isUrl or isNotice
            message_text.color = m.linkColor
        end if
        return message_text
    end if
end function

function chatTextNode(text as string, highlighted = false as boolean) as object
    node = createObject("roSGNode", "SimpleLabel")
    node.fontSize = m.font_size
    node.fontUri = "pkg:/fonts/Archivo-Regular.otf"
    node.text = text
    if highlighted then node.color = m.linkColor
    return node
end function

function chatWordParts(word as string, highlighted as boolean, isNotice as boolean) as object
    ' Provider names are matched as whole words, before any Unicode splitting.
    if not isNotice and m.global.emoteCache.doesExist(word)
        uri = m.global.emoteCache[word]
        if m.failedChatImages.doesExist(uri) then return [chatTextNode(word, highlighted)]
        return [buildEmote(uri, word)]
    end if
    parts = []
    for each segment in emojiTextRuns(word)
        if segment.uri = ""
            parts.push(chatTextNode(segment.text, highlighted))
        else if m.failedChatImages.doesExist(segment.uri)
            parts.push(chatTextNode(emojiFallback(segment.text), highlighted))
        else
            parts.push(buildEmote(segment.uri, emojiFallback(segment.text)))
        end if
    end for
    return parts
end function

function buildMessage(message, x_translation, isNotice = false)
    message_group = createObject("roSGNode", "Group")
    message_group.addFields({ chatMessageText: message, chatMessageX: x_translation, chatNotice: isNotice })
    x = x_translation
    line = 0
    lineWidth = m.right_bound - m.left_bound
    for each word in message.split(" ")
        highlighted = isNotice or m.urlRegex.isMatch(word)
        parts = chatWordParts(word, highlighted, isNotice)
        width = 0
        for each part in parts
            width += part.localBoundingRect().width
        end for
        ' Keep words together when possible; long words wrap at whole code points.
        if width <= lineWidth and x + width > m.right_bound and x > m.left_bound
            line++
            x = m.left_bound
        end if
        nodes = []
        for each part in parts
            if part.subtype() = "SimpleLabel" and part.localBoundingRect().width > lineWidth
                for each char in emojiCharacters(part.text)
                    nodes.push(chatTextNode(char, highlighted))
                end for
            else
                nodes.push(part)
            end if
        end for
        nodes.push(chatTextNode(" ", highlighted))
        for each node in nodes
            nodeWidth = node.localBoundingRect().width
            if x + nodeWidth > m.right_bound and x > m.left_bound
                line++
                x = m.left_bound
            end if
            node.translation = [x, line * (m.badge_size + m.line_gap)]
            message_group.appendChild(node)
            x += nodeWidth
        end for
    end for
    return message_group
end function

' Image decoding can fail even after HTTP 200. Rebuild only this text block
' with supported text, then account for any changed row height.
sub onChatImageStatus(event as object)
    poster = event.getRoSGNode()
    status = event.getData()
    if status <> "ready" and status <> "failed" then return
    poster.unobserveField("loadStatus")
    if m.disposed or status = "ready" then return
    if poster.getScene() = invalid then return
    block = poster.getParent()
    while block <> invalid
        if block.hasField("chatMessageText") then exit while
        block = block.getParent()
    end while
    if block = invalid then return
    parent = block.getParent()
    if parent = invalid then return
    if m.failedChatImages.count() >= 256 then m.failedChatImages = {}
    m.failedChatImages[poster.uri] = true
    replacement = buildMessage(block.chatMessageText, block.chatMessageX, block.chatNotice)
    releaseChatImages(block)
    for index = 0 to parent.getChildCount() - 1
        if parent.getChild(index).isSameNode(block)
            parent.replaceChild(replacement, index)
            exit for
        end if
    end for
    row = parent
    while row <> invalid
        if row.hasField("chatIdentity") then exit while
        row = row.getParent()
    end while
    if row = invalid then return
    if row.getChildCount() = 2
        body = row.getChild(1)
        body.translation = [0, row.getChild(0).localBoundingRect().height + m.line_gap]
    end if
    advance = row.localBoundingRect().height + m.line_gap
    delta = advance - row.chatAdvance
    row.chatAdvance = advance
    found = false
    rows = m.chatPanel.getChildren(-1, 0)
    for each item in rows
        if found then item.translation = [item.translation[0], item.translation[1] + delta]
        if item.isSameNode(row) then found = true
    end for
    m.translation += delta
    if rows.count() > 0
        last = rows[rows.count() - 1]
        overflow = last.translation[1] + last.chatAdvance - m.lower_bound
        if overflow > 0
            for each item in rows
                item.translation = [item.translation[0], item.translation[1] - overflow]
                if item.translation[1] + item.localBoundingRect().height < 0 then removeChatMessage(item)
            end for
            m.translation -= overflow
        end if
    end if
end sub

sub releaseChatImages(node as object)
    if node.subtype() = "Poster" and node.hasField("chatFallbackText") then node.unobserveField("loadStatus")
    for each child in node.getChildren(-1, 0)
        releaseChatImages(child)
    end for
end sub

sub removeChatMessage(message as object)
    releaseChatImages(message)
    m.chatPanel.removeChild(message)
end sub

sub onNewCommentObj(event = invalid as dynamic)
    if not currentChatEvent(event) then return
    chat = m.chat
    chat.readyForNextComment = false
    try
        renderComment()
    catch e
        ' A malformed message or unavailable font must not stall every subsequent message.
    end try
    if currentChatEvent(event)
        if chat.isSameNode(m.chat) then chat.readyForNextComment = true
    end if
end sub

' Moderation applies to displayed messages at once, independent of the stream
' delay. A gap before the published window cannot be resolved, so it clears all.
sub onModeration(event = invalid as dynamic)
    if not currentChatEvent(event) then return
    update = m.chat.moderation
    if update = invalid or update.events = invalid then return
    events = update.events
    if events.count() > 0 and events[0].seq > m.moderationSeq + 1 then removeModerated({ kind: "room" })
    for each event in events
        if event.seq > m.moderationSeq
            m.moderationSeq = event.seq
            removeModerated(event)
        end if
    end for
end sub

' Older messages move down by the space each removed message used, so the
' newest message stays anchored where the next one is placed.
sub removeModerated(event as object)
    m.pinModeration.push({ kind: event.kind, id: event.id, userId: event.userId, login: event.login, at: createObject("roDateTime").asSeconds() })
    if m.pinModeration.count() > 32 then m.pinModeration.shift()
    updatePinnedMessage()
    if event.kind = "room"
        for each message in m.chatPanel.getChildren(-1, 0)
            removeChatMessage(message)
        end for
        m.translation = m.lower_bound - m.line_height
        return
    end if
    children = m.chatPanel.getChildren(-1, 0)
    shift = 0
    for index = children.count() - 1 to 0 step -1
        message = children[index]
        if moderationMatches(message.chatIdentity, event)
            shift += message.chatAdvance
            removeChatMessage(message)
        else if shift > 0
            message.translation = [message.translation[0], message.translation[1] + shift]
        end if
    end for
end sub

' Mirrors ircModerationMatches in the transport, whose parser this component does not load.
function moderationMatches(identity as dynamic, event as object) as boolean
    if event.kind = "room" then return true
    if identity = invalid then return false
    if event.kind = "message" then return event.id <> "" and identity.id = event.id
    if event.userId <> "" and identity.userId = event.userId then return true
    return event.login <> "" and identity.login = event.login
end function

' A comment can be in flight when moderation arrives. The transport stamps the
' last moderation it applied to its queue, so only newer events can still match.
function moderatedInFlight(comment as object) as boolean
    delivered = comment.moderationSeq
    update = m.chat.moderation
    if delivered = invalid or update = invalid or update.events = invalid then return false
    events = update.events
    ' Events that left the bounded window cannot be checked; withhold the comment.
    if events.count() > 0 and events[0].seq > delivered + 1 then return true
    for each event in events
        if event.seq > delivered and moderationMatches(comment.identity, event) then return true
    end for
    return false
end function

sub renderComment()
    if m.chat.nextCommentObj <> invalid
        comment = m.chat.nextCommentObj
        if moderatedInFlight(comment) then return
        display_name = comment.tags.display_name
        message = comment.parameters
        color = ""
        if comment?.tags?.color <> invalid
            color = comment.tags.color.replace("#", "")
        end if
        badges = []
        if comment?.tags?.badges <> invalid
            for each key in comment.tags.badges
                badgeID = key
                badges.push(badgeID)
            end for
        end if
        emote_set = {}
        if comment?.tags?.emotes <> invalid
            for each emote in comment.tags.emotes.Items()
                value = { starts: [], length: 0 }
                for each emote_instance in emote.value
                    value.starts.push(emote_instance.startposition)
                    value.length = (emote_instance.endposition - emote_instance.startposition) + 1
                end for
                emote_set[emote.key] = value
            end for
        end if

        ' Preserve original character offsets until Twitch emote ranges have been consumed.
        for each emoticon in emote_set.Items()
            e_start = emoticon.value.starts[0]
            emote_word = ircEmoteText(message, e_start, emoticon.value.length)
            if emote_word <> "" and not m.global.emoteCache.DoesExist(emote_word) and m.global.emoteCache.count() < 10000
                emoteCache = m.global.emoteCache
                if not emoteCache.DoesExist(emote_word)
                    emoteCache[emote_word] = "https://static-cdn.jtvnw.net/emoticons/v2/" + emoticon.key + "/static/light/1.0"
                end if
                m.global.setField("emoteCache", emoteCache)
            end if
        end for

        systemMessage = ""
        if comment.command.command = "USERNOTICE" and comment.tags.system_msg <> invalid
            systemMessage = comment.tags.system_msg.replace(chr(13), " ").replace(chr(10), " ").trim()
        else if comment.command.command = "PRIVMSG"
            if GetInterface(comment.tags.bits, "ifString") <> invalid and m.bitsRegex.isMatch(comment.tags.bits)
                systemMessage = tr("{0} Bits").replace("{0}", comment.tags.bits)
            else if comment.tags.custom_reward_id <> invalid and comment.tags.custom_reward_id <> ""
                systemMessage = tr("Channel Points reward")
            end if
        end if
        hasUserMessage = display_name <> "" and message <> ""
        if systemMessage = "" and not hasUserMessage
            return
        end if

        group = createObject("roSGNode", "Group")
        messageOffset = 0
        if systemMessage <> ""
            notice = buildMessage(systemMessage, m.left_bound, true)
            group.appendChild(notice)
            messageOffset = notice.localBoundingRect().height + m.line_gap
        end if
        ' Keep the user's text separate: Twitch emote offsets refer only to it.
        if hasUserMessage
            x_translation = m.left_bound
            body = createObject("roSGNode", "Group")
            badge_group = buildBadges(badges)
            badge_group.translation = [x_translation, 0]
            x_translation += badge_group.localBoundingRect().width + 1

            username = buildUsername(display_name, color)
            username.translation = [x_translation, 0]
            x_translation += username.localBoundingRect().width + 1

            colon = buildColon()
            colon.translation = [x_translation, 0]
            x_translation += colon.localBoundingRect().width + 1

            message_group = buildMessage(message, x_translation)
            body.appendChild(badge_group)
            body.appendChild(username)
            body.appendChild(colon)
            body.appendChild(message_group)
            body.translation = [0, messageOffset]
            group.appendChild(body)
        end if
        group.translation = [m.left_bound, m.translation]
        m.chatPanel.appendChild(group)
        if m.chatPanel.getChildCount() > 160
            removeChatMessage(m.chatPanel.getChild(0))
        end if
        y_translation = group.localBoundingRect().height + m.line_gap
        identity = comment.identity
        if identity = invalid then identity = { id: "", userId: "", login: "" }
        ' Moderation finds this message by identity and closes the space it used.
        group.addFields({ chatIdentity: identity, chatAdvance: y_translation })
        if m.translation + y_translation > m.chatPanel.height
            for each chatmessage in m.chatPanel.getChildren(-1, 0)
                if (chatmessage.translation[1] + chatmessage.localBoundingRect().height) < 0 ' Wait until it's off the screen to remove it.
                    removeChatMessage(chatmessage)
                else
                    chatmessage.translation = [chatmessage.translation[0], (chatmessage.translation[1] - y_translation)]
                end if
            end for
        else
            m.translation += (y_translation)
        end if
        m.hasRenderedComment = true
        updateChatStatus(m.chat.connectionState)
    end if
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    closePinnedMessage()
    if m.pinTimer <> invalid
        m.pinTimer.control = "stop"
        m.pinTimer.unobserveField("fire")
        m.top.removeChild(m.pinTimer)
        m.pinTimer = invalid
    end if
    m.pinPanel.visible = false
    m.pinModeration = []
    if m.hypeTimer <> invalid
        m.hypeTimer.control = "stop"
        m.hypeTimer.unobserveField("fire")
        m.top.removeChild(m.hypeTimer)
        m.hypeTimer = invalid
    end if
    m.hypePanel.visible = false
    m.top.unobserveField("visible")
    stopJobs()
    releaseChatImages(m.chatPanel)
    m.emojiRegex = invalid
    m.failedChatImages = {}
    m.nameColorCache = {}
end sub
