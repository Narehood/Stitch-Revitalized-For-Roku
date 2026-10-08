sub handleContent()
    if m.disposed then return
    if m.top.contentRequested = invalid then return
    stopPlaybackForDialog()
    m.PlayVideo = destroyTask(m.PlayVideo, "response")
    m.reconnectAttempts = 0
    m.recoveryAttempts = 0
    m.resumePosition = invalid
    m.nativeFallbackTried = false
    m.manualRetryPending = false
    m.preferredQuality = invalid
    m.errorHandler.callFunc("resetErrorState")
    m.top.chatStarted = false
    if m.chatWindow <> invalid
        m.chatWindow.callFunc("stopJobs")
        m.chatWindow.visible = false
    end if
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = m.top.contentRequested.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end sub

sub onResponse()
    if m.disposed or m.PlayVideo = invalid then return
    m.manualRetryPending = false
    if m.PlayVideo.response = invalid
        m.PlayVideo = destroyTask(m.PlayVideo, "response")
        showErrorDialog(tr("Couldn't load this video"), tr("Twitch didn't return a playlist for it. Check your connection, then try again."))
        return
    end if
    if m.PlayVideo.response <> invalid and m.PlayVideo.response.contentType = "ERROR"
        ' Display error message to user
        errorTitle = tr("Couldn't load this video")
        errorMessage = tr("Twitch couldn't provide this video.")
        ' Restricted, expired and deleted videos cannot succeed on retry.
        canRetry = true

        if m.PlayVideo.response.description <> invalid and m.PlayVideo.response.description <> ""
            errorMessage = m.PlayVideo.response.description
        end if

        if m.PlayVideo.response.errorCode <> invalid
            if m.PlayVideo.response.errorCode = "vod_manifest_restricted"
                errorMessage = tr("This video is only available to subscribers")
                canRetry = false
            else if m.PlayVideo.response.errorCode = "vod_manifest_expired"
                errorMessage = tr("This video has expired and is no longer available")
                canRetry = false
            else if m.PlayVideo.response.errorCode = "vod_manifest_missing"
                errorMessage = tr("This video has been deleted")
                canRetry = false
            end if
        end if

        trackEvent("video_load_error", {
            error_code: m.PlayVideo.response.errorCode,
            error_message: errorMessage,
            streamer_login: m.top.contentRequested?.streamerLogin,
            content_type: m.top.contentRequested?.contentType
        })
        showErrorDialog(errorTitle, errorMessage, canRetry)
        m.PlayVideo = destroyTask(m.PlayVideo, "response")
        return
    end if

    m.top.content = m.PlayVideo.response
    m.top.metadata = m.PlayVideo.metadata
    applyPreferredQuality()
    m.PlayVideo = destroyTask(m.PlayVideo, "response")

    ' Warn before playing Enhanced Broadcasting (transmux) streams
    if m.top.content <> invalid and m.top.content.isTransmux = true
        if m.top.content.isProxied = true
            playContent()
        else
            showTransmuxWarning()
        end if
        return
    end if

    playContent()
end sub

sub controlChanged()
    if m.disposed then return
    control = m.top.control
    if control = "play"
        playContent()
    else if control = "stop"
        exitPlayer()
    end if
end sub

sub initChat()
    if not m.top.chatStarted
        m.top.chatStarted = true
        m.chatWindow.channel_id = m.top.contentRequested.streamerId
        m.chatWindow.channel = m.top.contentRequested.streamerLogin
        if get_user_setting("ChatOption", "true") = "true"
            m.chatWindow.visible = true
            m.video.chatIsVisible = m.chatWindow.visible
        else
            m.chatWindow.visible = false
        end if
    end if
end sub

sub onQualityChangeRequested()
    if m.video = invalid or m.top.metadata = invalid then return
    request = m.video.qualityChangeRequest
    index = -1
    if GetInterface(request, "ifInt") <> invalid
        index = request
    else
        for item = 0 to m.top.metadata.Count() - 1
            if m.top.metadata[item].QualityID = request then index = item
        end for
    end if
    if index < 0 or index >= m.top.metadata.Count() then return
    if m.top.contentRequested.contentType <> "LIVE" then m.resumePosition = m.video.position
    new_content = CreateObject("roSGNode", "TwitchContentNode")
    new_content.setFields(m.top.contentRequested.getFields()) ' Preserve original request fields
    new_content.setFields(m.top.metadata[index]) ' Includes URL, proxy flags and query forwarding
    m.top.content = new_content ' Update the main content node for VideoPlayer
    m.allowBreak = false
    exitPlayer() ' This will clean up the old video
    playContent() ' This will play the new m.top.content
    m.allowBreak = true
end sub

function FormatSeconds(seconds as integer) as string
    if seconds < 10
        return "0" + seconds.toStr()
    else
        return seconds.toStr()
    end if
end function

' isRecovery=true is set by internal recovery paths (watchdog reconnect,
' error-driven retryPlayback). It tells the freshly-created StitchVideo node
' to skip its startup live-edge seek so we don't immediately re-anchor at the
' live edge after a stall — which would shrink buffer headroom and feed the
' next stall. User-initiated entry points (first open, re-open, quality
' change) leave isRecovery=false so they get the low-latency seek.
sub playContent(isRecovery = false as boolean)
    if m.disposed then return
    ' Reset reconnect/watchdog state on every (re)start so stale values
    ' from a prior playback session don't cause false triggers.
    m.isExiting = false
    m.compatibilityNoticeShown = false
    m.lastGoodPosition = invalid
    m.stallSeconds = 0
    if m.top.content = invalid
        showErrorDialog(tr("Couldn't load this video"), tr("Select the video again from Browse."))
        return
    end if

    ' Reset buffering state so stale timers from prior attempts don't persist
    m.bufferStartTime = 0
    m.lastBufferState = ""
    if m.bufferCheckTimer <> invalid
        m.bufferCheckTimer.control = "stop"
        m.bufferCheckTimer.unobserveField("fire")
        m.bufferCheckTimer = invalid
    end if

    ' Stamp when this playback attempt started (used for grace period)
    m.playbackInitTime = CreateObject("roTimeSpan")
    m.playbackInitTime.Mark()

    ' Only run user-facing side effects on user-initiated plays — internal
    ' reconnects (m.allowBreak = false) must not re-add the stream to the
    ' recently-watched history.
    if m.allowBreak and m.top.contentRequested <> invalid
        ' Record to recently watched history (LIVE and VOD; skip clips)
        contentType = m.top.contentRequested.contentType
        if contentType = "LIVE" or contentType = "VOD"
            streamerLogin = m.top.contentRequested.streamerLogin
            if streamerLogin <> invalid and streamerLogin <> ""
                rwTask = CreateObject("roSGNode", "RW_AddTask")
                rwTask.entry = {
                    login: streamerLogin,
                    displayName: m.top.contentRequested.streamerDisplayName,
                    iconUrl: m.top.contentRequested.streamerProfileImageUrl
                }
                rwTask.control = "run"
            end if
        end if
    end if

    ' Clean up existing video node and its observers
    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        m.video.unobserveField("QualityChangeRequestFlag") ' StitchVideo specific
        m.video.unobserveField("qualityChangeRequest") ' StitchVideo specific
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("duration")
        m.video.unobserveField("back") ' CustomVideo specific
        m.video.callFunc("onDestroy")
        m.video.control = "stop"
        m.top.removeChild(m.video)
        m.video = invalid
    end if

    isLiveContent = (m.top.contentRequested.contentType = "LIVE")
    isClipContent = (m.top.contentRequested.contentType = "CLIP")

    if isLiveContent
        quality_options = []
        if m.top.metadata <> invalid
            for each quality_option in m.top.metadata
                quality_options.push(quality_option.qualityID)
            end for
        end if
        m.video = m.top.CreateChild("StitchVideo")
        m.video.qualityOptions = quality_options
        ' StitchVideo will observe its own selectedQuality field
    else
        m.video = m.top.CreateChild("CustomVideo")
    end if

    httpAgent = CreateObject("roHttpAgent")
    httpAgent.setCertificatesFile("common:/certs/ca-bundle.crt")
    httpAgent.InitClientCertificates()
    httpAgent.enableCookies()

    if isClipContent
        httpAgent.addheader("Accept", "video/mp4,video/webm,video/*,*/*")
        httpAgent.addheader("Accept-Encoding", "identity")
        httpAgent.addheader("Accept-Language", "en-US,en;q=0.9")
        httpAgent.addheader("Cache-Control", "no-cache")
        httpAgent.addheader("Connection", "keep-alive")
        httpAgent.addheader("DNT", "1")
        httpAgent.addheader("Origin", "https://www.twitch.tv")
        httpAgent.addheader("Pragma", "no-cache")
        httpAgent.addheader("Referer", "https://www.twitch.tv/")
        httpAgent.addheader("Sec-Ch-Ua", chr(34) + "Not_A Brand" + chr(34) + ";v=" + chr(34) + "8" + chr(34) + ", " + chr(34) + "Chromium" + chr(34) + ";v=" + chr(34) + "120" + chr(34) + ", " + chr(34) + "Google Chrome" + chr(34) + ";v=" + chr(34) + "120" + chr(34))
        httpAgent.addheader("Sec-Ch-Ua-Mobile", "?0")
        httpAgent.addheader("Sec-Ch-Ua-Platform", chr(34) + "Windows" + chr(34))
        httpAgent.addheader("Sec-Fetch-Dest", "video")
        httpAgent.addheader("Sec-Fetch-Mode", "cors")
        httpAgent.addheader("Sec-Fetch-Site", "cross-site")
        httpAgent.addheader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        httpAgent.addheader("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
    else ' Live/VOD
        httpAgent.addheader("Accept", "*/*")
        httpAgent.addheader("Origin", "https://android.tv.twitch.tv")
        httpAgent.addheader("Referer", "https://android.tv.twitch.tv/")
        httpAgent.addheader("User-Agent", "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36")
        httpAgent.addheader("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
    end if
    m.video.setHttpAgent(httpAgent)

    m.video.notificationInterval = 0.5 ' fire position/bufferingStatus every 500ms

    ' Add observers to the new video node
    m.video.observeField("toggleChat", "onToggleChat")
    if isLiveContent
        m.video.observeField("QualityChangeRequestFlag", "onQualityChangeRequested") ' StitchVideo specific
    else
        m.video.observeField("back", "onVideoBack") ' CustomVideo specific
    end if
    m.video.observeField("position", "onPositionChanged")
    m.video.observeField("state", "onVideoStateChange")
    m.video.observeField("duration", "onDurationChanged")
    ' A wrapper recreated for a quality change, recovery or Try again lays
    ' out its controls beside chat that is already open.
    if m.chatWindow <> invalid and m.chatWindow.visible then onChatVisibilityChange()

    videoBookmarks = get_user_setting("VideoBookmarks", "")
    m.video.video_type = m.top.contentRequested.contentType
    m.video.video_id = m.top.contentRequested.contentId
    if isLiveContent then m.video.selectedQuality = m.top.content.QualityID

    if videoBookmarks <> ""
        m.video.videoBookmarks = ParseJSON(videoBookmarks)
    else
        m.video.videoBookmarks = {}
    end if
    if m.video.videoBookmarks = invalid then m.video.videoBookmarks = {}

    contentNodeToPlay = m.top.content ' This is the TwitchContentNode
    if contentNodeToPlay <> invalid
        if isLiveContent
            contentNodeToPlay.ignoreStreamErrors = false ' Important for HLS error reporting
            contentNodeToPlay.switchingStrategy = "full-adaptation"
            ' Roku clips this start position to the availability window.
            ' The opt-in startup seek is separate and needs hardware measurements.
            ' https://developer.roku.com/dev/docs/specs/media (live edge spec)
            contentNodeToPlay.PlayStart = 2147483647
        else if isClipContent
            contentNodeToPlay.ignoreStreamErrors = false
            contentNodeToPlay.switchingStrategy = "no-adaptation"
            contentNodeToPlay.enableTrickPlay = false
        else ' VOD
            contentNodeToPlay.ignoreStreamErrors = false
            contentNodeToPlay.switchingStrategy = "full-adaptation" ' Typically ABR for VODs
            if m.resumePosition <> invalid
                contentNodeToPlay.PlayStart = Int(m.resumePosition)
            else if m.video.videoBookmarks.DoesExist(m.video.video_id)
                contentNodeToPlay.PlayStart = Int(Val(m.video.videoBookmarks[m.video.video_id]))
            end if
        end if

        ' Invariant: m.video is a fresh StitchVideo node here. exitPlayer()
        ' tears down the previous instance, so this assignment runs on a
        ' newly created node with init() defaults (startupSeekFired=false,
        ' recentSeekTimestamp=0). Do NOT optimize this path to reuse an
        ' existing m.video across reconnects without also explicitly
        ' resetting those latches — otherwise the startup seek will be
        ' suppressed on the new stream.
        '
        ' On recovery paths (watchdog reconnect / error retry) mark the new
        ' node so it skips the startup live-edge seek. Must be set BEFORE the
        ' content assignment because state=playing can race through quickly
        ' after content is applied, and the gate is checked in
        ' StitchVideo's onVideoStateChange.
        if isLiveContent
            m.video.suppressStartupSeek = isRecovery or get_user_setting("playback.lowLatency", "false") <> "true"
        end if
        m.video.content = contentNodeToPlay

        if contentNodeToPlay.streamerProfileImageUrl <> invalid
            m.video.channelAvatar = contentNodeToPlay.streamerProfileImageUrl
        end if
        if contentNodeToPlay.streamerDisplayName <> invalid
            m.video.channelUsername = contentNodeToPlay.streamerDisplayName
        end if
        if contentNodeToPlay.contentTitle <> invalid
            m.video.videoTitle = contentNodeToPlay.contentTitle
        end if

        m.video.visible = true
        m.video.control = "play"
        m.video.SetFocus(true)

        if isLiveContent
            initChat()
        end if
    end if
end sub

sub exitPlayer()
    ' If allowBreak is true, this is a real user/back exit. During internal
    ' reconnects we set allowBreak=false before calling exitPlayer().
    if m.allowBreak
        m.isExiting = true
        m.bookmarksTask = destroyTask(m.bookmarksTask, "response")
        ' Stop chat immediately so the IRC connection and ChatJob task are
        ' released before the scene tears down, regardless of chat visibility.
        if m.chatWindow <> invalid
            m.chatWindow.callFunc("stopJobs")
            m.chatWindow.callFunc("onDestroy")
        end if
        closeOwnedPlayerDialogs()
    end if

    ' Stop watchdog/reconnect timers and clean up any in-flight reconnect task
    if m.watchdogTimer <> invalid
        m.watchdogTimer.control = "stop"
    end if
    if m.reconnectTimer <> invalid
        m.reconnectTimer.control = "stop"
        m.reconnectTimer.unobserveField("fire")
        m.reconnectTimer = invalid
    end if
    if m.retryTimer <> invalid
        m.retryTimer.control = "stop"
        m.retryTimer.unobserveField("fire")
        m.retryTimer = invalid
    end if
    cleanupReconnectTask()

    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        if m.video.isSubtype("StitchVideo")
            m.video.unobserveField("QualityChangeRequestFlag")
        else if m.video.isSubtype("CustomVideo")
            m.video.unobserveField("back")
        end if
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("duration")
        m.video.callFunc("onDestroy")
        m.video.control = "stop"
        m.video.visible = false
    end if

    if m.allowBreak
        m.top.state = "done"
        m.top.backpressed = true ' Ensure this signals back correctly
    end if
end sub

function onKeyEvent(key, press) as boolean
    if press
        if key = "back"
            m.allowBreak = true ' Ensure exitPlayer signals upwards
            exitPlayer()
            return true
        end if
    end if
    return false ' Let child video component (StitchVideo/CustomVideo) handle other keys
end function

sub init()
    m.disposed = false
    m.bookmarksTask = m.top.findNode("bookmarksTask")
    m.chatWindow = m.top.findNode("chat")
    if m.chatWindow <> invalid
        m.chatWindow.fontSize = get_user_setting("ChatFontSize")
        m.chatWindow.observeField("visible", "onChatVisibilityChange")
    end if
    m.allowBreak = true ' Default to allowing break unless in quality change

    ' Initialize error handler
    m.errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    m.bufferCheckTimer = invalid
    m.lastBufferState = ""
    m.bufferStartTime = 0

    ' ===== Robust LIVE stall watchdog / reconnect =====
    ' Detects the common Twitch post-ad freeze where state stays "playing"
    ' but position stops advancing. When detected, it re-fetches the Twitch
    ' playlist/auth (GetTwitchContent) and restarts playback with backoff.
    m.isExiting = false
    m.reconnectAttempts = 0
    m.maxReconnectAttempts = 6
    m.recoveryAttempts = 0
    m.maxRecoveryAttempts = 6
    m.resumePosition = invalid
    m.reconnectCooldownSec = 45
    m.lastReconnectSuccessSec = 0
    m.lastGoodPosition = invalid
    m.stallSeconds = 0
    m.reconnectTimer = invalid
    m.retryTimer = invalid
    m.playbackInitTime = invalid ' tracks when current playback attempt started

    m.watchdogTimer = CreateObject("roSGNode", "Timer")
    m.watchdogTimer.repeat = true
    m.watchdogTimer.duration = 2 ' seconds
    m.watchdogTimer.observeField("fire", "onWatchdogFire")
end sub

sub onToggleChat()
    if m.video = invalid then return
    if m.video.toggleChat = true ' Check the field on the video component
        if m.top.contentRequested.contentType <> "LIVE"
            m.video.toggleChat = false
            showChatUnavailableNotice()
            return
        end if
        if m.chatWindow <> invalid
            m.chatWindow.visible = not m.chatWindow.visible
            m.video.chatIsVisible = m.chatWindow.visible ' Update video component's knowledge
        end if
        m.video.toggleChat = false ' Reset the flag on the video component
    end if
end sub

sub onChatVisibilityChange()
    if m.chatWindow <> invalid and m.video <> invalid
        if m.chatWindow.visible
            ' Example: Chat takes up 320px, video takes remaining width
            m.chatWindow.translation = [1280 - 320, 0] ' Position chat on the right
            m.chatWindow.height = 720 ' Full height
            m.chatWindow.width = 320

            m.video.width = 1280 - 320 ' Video width adjusted
            m.video.height = 720 ' Video full height
            m.video.translation = [0, 0] ' Video on the left
            m.video.chatIsVisible = true
        else
            m.video.width = 1280 ' Video full width
            m.video.height = 720
            m.video.translation = [0, 0]
            m.video.chatIsVisible = false
        end if
    end if
end sub

' Placeholder for onPositionChanged, onVideoStateChange, onVideoError, onDurationChanged
' These are observed on m.video, but their handlers can be minimal here if
' StitchVideo/CustomVideo handle their own UI updates based on these.
' However, some global actions might be needed here.

sub onPositionChanged()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onPositionChange for UI.
    ' Can be used for global logic if needed, e.g. global bookmarking not tied to UI.

    ' LIVE watchdog: keep track of forward progress (post-ad freezes often stop position)
    if m.video <> invalid and m.top.contentRequested <> invalid and m.top.contentRequested.contentType = "LIVE"
        delaySeconds = 0.0
        segment = m.video.streamingSegment
        if segment <> invalid and segment.latency <> invalid
            delaySeconds = segment.latency / 1000
            if delaySeconds < 0 or delaySeconds > 60 then delaySeconds = 0.0
        end if
        if m.chatWindow <> invalid then m.chatWindow.delaySeconds = delaySeconds
        if m.lastGoodPosition = invalid
            m.lastGoodPosition = m.video.position
            m.stallSeconds = 0
        else if m.video.position > m.lastGoodPosition
            m.lastGoodPosition = m.video.position
            m.stallSeconds = 0
        end if
    end if

end sub

sub onVideoStateChange()
    if m.video = invalid or m.isExiting then return
    if m.chatWindow <> invalid and m.video.state <> "playing" then m.chatWindow.delaySeconds = 0
    if m.video.state = "playing" and not m.compatibilityNoticeShown
        m.compatibilityNoticeShown = true
        if m.top.content <> invalid and m.top.content.playbackNotice <> ""
            m.video.callFunc("showMessage", "Playback quality", m.top.content.playbackNotice, 8)
        end if
    end if

    ' Handle buffering states
    if m.video.state = "buffering"
        handleBufferingState()
    else if m.lastBufferState = "buffering" and m.video.state = "playing"
        m.bufferStartTime = 0
        ' Recovered from buffering — cancel all pending retry/buffer timers
        if m.bufferCheckTimer <> invalid
            m.bufferCheckTimer.control = "stop"
            m.bufferCheckTimer.unobserveField("fire")
            m.bufferCheckTimer = invalid
        end if
        if m.retryTimer <> invalid
            m.retryTimer.control = "stop"
            m.retryTimer.unobserveField("fire")
            m.retryTimer = invalid
        end if
    end if

    m.lastBufferState = m.video.state

    ' Start/stop LIVE watchdog based on video state (single decision point)
    if m.top.contentRequested <> invalid and m.top.contentRequested.contentType = "LIVE" and m.watchdogTimer <> invalid
        if m.video.state = "playing"
            if m.lastGoodPosition = invalid then m.lastGoodPosition = m.video.position
            m.stallSeconds = 0
            m.watchdogTimer.control = "start"
        else
            m.watchdogTimer.control = "stop"
        end if
    end if

    if m.video.state = "finished" and m.allowBreak
        exitPlayer()
    else if m.video.state = "error"
        ? getLogTimestamp(); " [VideoPlayer] video.state=error code="; m.video.errorCode

        errorCode = m.video.errorCode
        errorMsg = m.video.errorStr
        if errorMsg = invalid then errorMsg = ""

        ' A demux error must remain actionable rather than silently exiting.
        if errorMsg.InStr("buffer:loop:demux") > -1 or errorMsg.InStr("970") > -1
            if tryNativePlaybackFallback() then return
            if m.top.content.isProxied
                showErrorDialog(tr("Audio/video format problem"), tr("The demux service could not provide playable audio and video. Check the service connection and version, then try again."))
            else
                ' Fails closed: retrying cannot help until the service is set up.
                showErrorDialog(tr("Video format needs the audio service"), tr("This stream uses combined audio/video CMAF segments. Configure the optional demux service in Settings, or choose another stream."), false)
            end if
            return
        end if

        handleStreamError(errorMsg)
    end if
end sub

sub handleStreamError(errorStr = invalid as dynamic)
    if m.video = invalid or m.isExiting or m.errorDialog <> invalid then return
    if m.retryTimer <> invalid or m.reconnectTask <> invalid then return
    if m.errorHandler = invalid
        m.errorHandler = CreateObject("roSGNode", "VideoErrorHandler")
    end if

    errorCode = m.video.errorCode
    errorMessage = errorStr
    if errorMessage = invalid then errorMessage = m.video.errorStr
    if errorMessage = invalid then errorMessage = "Unknown error"

    ' Get error classification for user-friendly messages
    errorType = m.errorHandler.callFunc("classifyError", errorCode, errorMessage)
    if tryNativePlaybackFallback() then return

    trackEvent("video_error", {
        error_code: errorCode,
        error_type: errorType,
        streamer_login: m.top.contentRequested?.streamerLogin,
        content_type: m.top.contentRequested?.contentType
    })

    recovery = m.errorHandler.callFunc("handleVideoError", errorCode, errorMessage, m.video, m.top.contentRequested)
    if m.recoveryAttempts >= m.maxRecoveryAttempts
        recovery.shouldRetry = false
    else if recovery.shouldRetry
        m.recoveryAttempts++
    end if

    if recovery.shouldRetry
        if recovery.action = "retry"
            ? getLogTimestamp(); " [VideoPlayer] Retry delay="; recovery.delay; " code="; errorCode
            showTemporaryMessage(tr("Reconnecting…"))

            ' Cancel any in-flight retry timer before creating a new one
            if m.retryTimer <> invalid
                m.retryTimer.control = "stop"
                m.retryTimer.unobserveField("fire")
                m.retryTimer = invalid
            end if
            m.retryTimer = CreateObject("roSGNode", "Timer")
            m.retryTimer.duration = recovery.delay / 1000
            m.retryTimer.repeat = false
            m.retryTimer.observeField("fire", "retryPlayback")
            m.retryTimer.control = "start"

        else if recovery.action = "change_quality" and recovery.newContent <> invalid
            ' Show quality change message
            showTemporaryMessage(tr("Switching to a lower quality…"))

            ' Switch to different quality
            m.video.qualityChangeRequest = recovery.newContent.index
            onQualityChangeRequested()

        else if recovery.action = "refresh_auth"
            ' Show auth message
            showTemporaryMessage(tr("Refreshing video access…"))

            ' Refresh authentication and retry
            refreshAuthAndRetry()

        else if recovery.action = "force_lower_quality"
            ' Show quality message
            showTemporaryMessage(tr("Adjusting quality for smoother playback…"))

            ' Force switch to lowest available quality
            if m.video.qualityOptions <> invalid and m.video.qualityOptions.count() > 0
                lowestQuality = m.video.qualityOptions.count() - 1
                m.video.qualityChangeRequest = lowestQuality
                onQualityChangeRequested()
            end if
        else if recovery.action = "fail_immediately"
            ' Get user-friendly error message
            errorInfo = m.errorHandler.callFunc("getUserFriendlyErrorMessage", errorCode, errorType)
            showErrorDialog(errorInfo.title, errorInfo.message + Chr(10) + errorInfo.suggestion)
        end if
    else
        errorInfo = m.errorHandler.callFunc("getUserFriendlyErrorMessage", errorCode, errorType)
        ' Only say recovery ran out when it did; other errors get the advice.
        detail = errorInfo.suggestion
        if recovery.action = "fail" or m.recoveryAttempts >= m.maxRecoveryAttempts then detail = tr("Playback stopped after several recovery attempts.")
        showErrorDialog(errorInfo.title, errorInfo.message + Chr(10) + detail)
    end if
end sub

sub handleBufferingState()
    if m.bufferStartTime = 0
        m.bufferStartTime = CreateObject("roDateTime").AsSeconds()
    end if

    ' Check for excessive buffering
    currentTime = CreateObject("roDateTime").AsSeconds()
    bufferDuration = currentTime - m.bufferStartTime

    if bufferDuration > 10 ' More than 10 seconds of buffering
        recovery = m.errorHandler.callFunc("handleBufferStall", m.video)

        if recovery.shouldRecover
            if recovery.action = "reduce_quality"
                ' Switch to lower quality
                lowerQuality = findLowerQuality()
                if lowerQuality <> invalid
                    if m.recoveryAttempts >= m.maxRecoveryAttempts
                        showErrorDialog(tr("Playback interrupted"), tr("This video kept buffering after several recovery attempts. Check your connection, then try again."))
                        return
                    end if
                    m.recoveryAttempts++
                    m.video.qualityChangeRequest = lowerQuality
                    onQualityChangeRequested()
                end if
            end if
        end if

        m.bufferStartTime = 0 ' Reset timer
    end if

    ' Start a timer to check for stuck buffering.
    ' 25s gives Twitch CDN enough time for initial segment delivery on busy streams.
    if m.bufferCheckTimer = invalid
        m.bufferCheckTimer = CreateObject("roSGNode", "Timer")
        m.bufferCheckTimer.duration = 25
        m.bufferCheckTimer.repeat = false
        m.bufferCheckTimer.observeField("fire", "onBufferTimeout")
        m.bufferCheckTimer.control = "start"
    end if
end sub

sub onBufferTimeout()
    if m.bufferCheckTimer <> invalid
        m.bufferCheckTimer.control = "stop"
        m.bufferCheckTimer.unobserveField("fire")
    end if
    m.bufferCheckTimer = invalid
    if m.video = invalid then return
    if m.video.state <> "buffering" then return
    ' LIVE streams stall 15-20s waiting for the CDN segment to be produced — normal.
    ' Let Roku self-recover; don't force an error retry.
    if m.top.contentRequested <> invalid and m.top.contentRequested.contentType = "LIVE"
        beginLiveReconnect("buffer_timeout")
        return
    end if
    handleStreamError()
end sub

' ===== LIVE stall watchdog / reconnect =====
sub onWatchdogFire()
    if m.isExiting then return
    if m.video = invalid or m.top.contentRequested = invalid then return
    if m.top.contentRequested.contentType <> "LIVE" then return
    if m.video.state <> "playing" then return

    nowSec = CreateObject("roDateTime").AsSeconds()

    ' Cooldown after a successful reconnect to avoid immediate re-triggers while Twitch stabilizes
    if m.lastReconnectSuccessSec <> 0 and (nowSec - m.lastReconnectSuccessSec) < m.reconnectCooldownSec
        return
    end if

    ' Cooldown after an app-initiated seek to live edge. StitchVideo issues
    ' seek=999999 to anchor at the live edge; the player freezes position
    ' for ~5-15s while re-buffering near the new live position (longer on
    ' slower networks / 1080p60). Without this guard the watchdog mistakes
    ' that freeze for a real stall and triggers a full reconnect, which
    ' actively undoes the live-edge correction. 20s gives Roku enough time
    ' to fully restabilize even on slow networks before re-engaging.
    if m.video.recentSeekTimestamp <> 0 and (nowSec - m.video.recentSeekTimestamp) < 20
        ' Reset position tracking so the moment cooldown ends we start fresh.
        m.lastGoodPosition = invalid
        m.stallSeconds = 0
        return
    end if

    ' If position advanced, reset stall tracking
    if m.lastGoodPosition = invalid
        m.lastGoodPosition = m.video.position
        m.stallSeconds = 0
        return
    end if

    if m.video.position > m.lastGoodPosition
        m.lastGoodPosition = m.video.position
        m.stallSeconds = 0
        return
    end if

    ' Position didn't advance since last tick
    m.stallSeconds = m.stallSeconds + 2

    ' Common post-ad freeze: state remains "playing" but position is stuck.
    ' 16s threshold derived from worst-case legitimate near-live freezes:
    '   - late CDN segment: ~4-5s (one EXT-X-TARGETDURATION + jitter)
    '   - ABR quality switch re-buffer: ~6s
    '   - ad-stitch transition without state change: up to ~10s
    ' This gives ~60% headroom over the worst legitimate case while still
    ' recovering fast enough that the user sees "Reconnecting..." before
    ' they hit Back. Was 8s in v2.5.0 which was too aggressive near the
    ' tighter ~20s live edge introduced by the startup seek.
    '
    ' Tick granularity is 2s (m.watchdogTimer.duration), so `>= 16` fires
    ' on the 8th non-advancing tick (m.stallSeconds = 0,2,...,14,16) —
    ' i.e. exactly 16 wall-clock seconds.
    if m.stallSeconds >= 16
        ? getLogTimestamp(); " [VideoPlayer] LIVE stall detected (pos="; m.video.position; "). Reconnecting..."
        beginLiveReconnect("stall")
    end if
end sub

sub beginLiveReconnect(reason as string)
    if m.isExiting then return

    ' If a reconnect is already scheduled/in-flight, don't stack them
    if m.reconnectTimer <> invalid or m.reconnectTask <> invalid then return

    m.reconnectAttempts = m.reconnectAttempts + 1
    m.recoveryAttempts++
    if m.reconnectAttempts > m.maxReconnectAttempts or m.recoveryAttempts > m.maxRecoveryAttempts
        showErrorDialog(tr("Stream frozen"), tr("Twitch playback stopped and couldn't be recovered automatically."))
        return
    end if

    ' Exponential backoff: 1,2,4,8,16,16...
    delaySec = 1
    for i = 1 to m.reconnectAttempts - 1
        delaySec = delaySec * 2
    end for
    if delaySec > 16 then delaySec = 16

    ? getLogTimestamp(); " [VideoPlayer] beginLiveReconnect reason="; reason; " attempt="; m.reconnectAttempts; "/"; m.maxReconnectAttempts
    showTemporaryMessage(tr("Reconnecting… ({0}/{1})").replace("{0}", m.reconnectAttempts.toStr()).replace("{1}", m.maxReconnectAttempts.toStr()))

    if m.watchdogTimer <> invalid
        m.watchdogTimer.control = "stop"
    end if

    m.reconnectTimer = CreateObject("roSGNode", "Timer")
    m.reconnectTimer.duration = delaySec
    m.reconnectTimer.repeat = false
    m.reconnectTimer.observeField("fire", "doLiveReconnect")
    m.reconnectTimer.control = "start"
end sub

sub cleanupReconnectTask()
    m.reconnectTask = destroyTask(m.reconnectTask, "response")
end sub

sub doLiveReconnect()
    if m.isExiting then return

    if m.reconnectTimer <> invalid
        m.reconnectTimer.control = "stop"
        m.reconnectTimer.unobserveField("fire")
        m.reconnectTimer = invalid
    end if

    ' Clean up any prior reconnect task before creating a new one
    cleanupReconnectTask()

    ' Re-fetch playlist/auth via GetTwitchContent
    m.reconnectTask = CreateObject("roSGNode", "GetTwitchContent")
    m.reconnectTask.observeField("response", "onLiveReconnectResponse")
    m.reconnectTask.contentRequested = m.top.contentRequested.getFields()
    m.reconnectTask.functionName = "main"
    m.reconnectTask.control = "run"
end sub

sub onLiveReconnectResponse()
    if m.isExiting
        cleanupReconnectTask()
        return
    end if

    if m.reconnectTask = invalid or m.reconnectTask.response = invalid
        cleanupReconnectTask()
        beginLiveReconnect("refresh_failed")
        return
    end if

    if m.reconnectTask.response.contentType = "ERROR"
        cleanupReconnectTask()
        beginLiveReconnect("refresh_failed")
        return
    end if

    ' Capture response before cleanup
    refreshedContent = m.reconnectTask.response
    refreshedMetadata = m.reconnectTask.metadata
    cleanupReconnectTask()

    ' Apply fresh content + metadata
    m.top.content = refreshedContent
    m.top.metadata = refreshedMetadata
    if m.video <> invalid
        if m.top.contentRequested.contentType <> "LIVE" then m.resumePosition = m.video.position
        quality = m.video.GetField("selectedQuality")
        if quality <> invalid and refreshedMetadata <> invalid
            for each entry in refreshedMetadata
                if entry.QualityID = quality then refreshedContent.SetFields(entry)
            end for
        end if
    end if
    if refreshedContent.isTransmux
        showTransmuxWarning()
        return
    end if

    ' Reset stall tracking
    m.lastGoodPosition = invalid
    m.stallSeconds = 0

    ' Restart playback in-place without exiting the scene. isRecovery=true
    ' so the new StitchVideo skips its startup live-edge seek — re-anchoring
    ' immediately after a stall would shrink buffer headroom and risk
    ' feeding the next stall. User can re-open the stream from the home or
    ' channel page if they want the low-latency seek again.
    m.allowBreak = false
    exitPlayer()
    m.allowBreak = true
    playContent(true)

    ' Mark successful reconnect (cooldown prevents immediate re-triggers)
    m.lastReconnectSuccessSec = CreateObject("roDateTime").AsSeconds()

    ' The budget belongs to the session, not an individual restart.
    if m.watchdogTimer <> invalid
        m.watchdogTimer.control = "start"
    end if
end sub

sub retryPlayback()
    ? getLogTimestamp(); " [VideoPlayer] retryPlayback() — restarting playback"
    if m.retryTimer <> invalid
        m.retryTimer.control = "stop"
        m.retryTimer.unobserveField("fire")
        m.retryTimer = invalid
    end if
    if m.isExiting then return
    ' isRecovery=true: same reasoning as onLiveReconnectResponse — we just
    ' hit a stream error, conditions are degraded, prioritize stability
    ' over latency. The user can re-open the stream to get the seek again.
    if m.top.contentRequested.contentType <> "LIVE" and m.video <> invalid then m.resumePosition = m.video.position
    doLiveReconnect()
end sub

sub refreshAuthAndRetry()
    ' Refresh the signed playback token. Account OAuth is handled separately.
    retryPlayback()
end sub

function findLowerQuality() as dynamic
    options = m.video.GetField("qualityOptions")
    if options = invalid or options.count() = 0
        return invalid
    end if

    currentQuality = m.video.selectedQuality
    if currentQuality = invalid
        currentQuality = m.video.qualityOptions[0]
    end if

    ' Find current index
    currentIndex = -1
    for i = 0 to m.video.qualityOptions.count() - 1
        if m.video.qualityOptions[i] = currentQuality
            currentIndex = i
            exit for
        end if
    end for

    ' Return next lower quality
    if currentIndex >= 0 and currentIndex < m.video.qualityOptions.count() - 1
        return currentIndex + 1
    end if

    return invalid
end function

' Playback stops behind the dialog. Try again makes one fresh attempt for the
' same video; Back (button or remote) leaves the player as before. Errors
' that a retry cannot fix pass allowRetry=false and offer only Back.
sub showErrorDialog(title as string, message as string, allowRetry = true as boolean)
    if m.disposed or m.errorDialog <> invalid then return
    rememberRetryState()
    stopPlaybackForDialog()
    m.manualRetryPending = false
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = title
    paragraphs = []
    for each paragraph in message.split(Chr(10))
        if paragraph.trim() <> "" then paragraphs.push(paragraph)
    end for
    dialog.message = paragraphs
    if allowRetry and m.top.contentRequested <> invalid
        m.errorDialogActions = ["retry", "back"]
        dialog.buttons = [tr("Try again"), tr("Back")]
    else
        m.errorDialogActions = ["back"]
        dialog.buttons = [tr("Back")]
    end if
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "onErrorDialogButton")
    dialog.observeField("wasClosed", "onErrorDialogClosed")
    ' Use the scene's dialog property, not m.top.dialog
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = dialog
    end if
    m.errorDialog = dialog
end sub

sub onErrorDialogButton()
    dialog = m.errorDialog
    if dialog = invalid then return
    action = "back"
    index = dialog.buttonSelected
    if index >= 0 and index < m.errorDialogActions.count() then action = m.errorDialogActions[index]
    closeErrorDialog()
    if action = "retry"
        retryAfterError()
    else
        exitPlayer()
    end if
end sub

sub onErrorDialogClosed()
    if m.errorDialog = invalid then return
    closeErrorDialog()
    exitPlayer()
end sub

' Idempotent: unobserves first, so a second button event or a close that
' follows a choice cannot act again.
sub closeErrorDialog()
    dialog = m.errorDialog
    if dialog = invalid then return
    m.errorDialog = invalid
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        if scene.dialog.isSameNode(dialog) then scene.dialog = invalid
    end if
end sub

' Keeps the recorded position or the live quality a Try again should reuse.
sub rememberRetryState()
    m.retryPosition = invalid
    m.retryQuality = invalid
    if m.video = invalid or m.top.contentRequested = invalid then return
    if m.top.contentRequested.contentType = "LIVE"
        quality = m.video.selectedQuality
        if quality <> invalid and quality <> "" then m.retryQuality = quality
    else
        position = m.video.position
        if position <> invalid and position > 0 then m.retryPosition = position
        if m.retryPosition = invalid then m.retryPosition = m.resumePosition
    end if
end sub

' One explicit Try again is one fresh content request for the same video, the
' same work as reopening it, so the session recovery budget starts over. The
' pending flag ignores repeated presses until that request answers; the old
' wrapper keeps only its Back/chat observers, so no stale state change can
' start automatic recovery meanwhile. Disposal destroys the request.
sub retryAfterError()
    if m.disposed or m.manualRetryPending then return
    if m.top.contentRequested = invalid
        exitPlayer()
        return
    end if
    m.manualRetryPending = true
    stopPlaybackForDialog()
    if m.video <> invalid
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("duration")
        if m.video.isSubtype("StitchVideo") then m.video.unobserveField("QualityChangeRequestFlag")
        m.video.callFunc("showMessage", "", tr("Trying again…"), 0)
    end if
    m.reconnectAttempts = 0
    m.recoveryAttempts = 0
    m.nativeFallbackTried = false
    if m.errorHandler <> invalid then m.errorHandler.callFunc("resetErrorState")
    m.resumePosition = m.retryPosition
    m.preferredQuality = m.retryQuality
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = m.top.contentRequested.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end sub

' A Try again keeps the live quality that was playing when the error appeared,
' with that entry's URL and proxy flags, as a quality change would.
sub applyPreferredQuality()
    quality = m.preferredQuality
    m.preferredQuality = invalid
    if quality = invalid or m.top.content = invalid or m.top.metadata = invalid then return
    for each entry in m.top.metadata
        if entry.QualityID = quality
            m.top.content.setFields(entry)
            return
        end if
    end for
end sub

sub showTransmuxWarning()
    stopPlaybackForDialog()
    dialog = createObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Audio service needed")
    dialog.message = [tr("This stream combines audio and video in CMAF segments. Roku needs separate tracks."), tr("Configure the optional demux service URL in Settings, or return to Browse and choose a compatible stream."), tr("The service runs directly in Python or in Docker; it does not re-encode your video.")]
    dialog.buttons = [tr("Back")]
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "onTransmuxDialogButton")
    dialog.observeField("wasClosed", "onTransmuxDialogClosed")
    m.transmuxDialog = dialog
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = dialog
    end if
end sub

sub onTransmuxDialogButton()
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid
        scene.dialog.close = true
    end if
end sub

sub onTransmuxDialogClosed()
    if m.transmuxDialog <> invalid
        m.transmuxDialog.unobserveField("buttonSelected")
        m.transmuxDialog.unobserveField("wasClosed")
        m.transmuxDialog = invalid
    end if
    scene = m.top.getScene()
    if scene <> invalid
        scene.dialog = invalid
    end if
    exitPlayer()
end sub

sub onDurationChanged()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onDurationChange for UI.
    ' ? "[VideoPlayer] Global onDurationChanged: "; m.video.duration
end sub

sub onVideoBack()
    ' Called when CustomVideo's back field is true
    m.allowBreak = true
    exitPlayer()
end sub

sub showTemporaryMessage(message as string)
    if m.video <> invalid then m.video.callFunc("showMessage", "", message, 5)
    ? getLogTimestamp(); " [VideoPlayer] Status: "; message
end sub

sub dismissTemporaryMessage()
    if m.video <> invalid then m.video.callFunc("hideMessage")
end sub

function tryNativePlaybackFallback() as boolean
    if m.top.content = invalid or not m.top.content.isProxied or m.nativeFallbackTried then return false
    m.nativeFallbackTried = true
    if m.top.metadata = invalid or m.recoveryAttempts >= m.maxRecoveryAttempts then return false
    for index = 1 to m.top.metadata.Count() - 1
        entry = m.top.metadata[index]
        if not entry.isProxied and not entry.isTransmux
            m.recoveryAttempts++
            showTemporaryMessage(tr("Audio service unavailable. Switching to a compatible quality…"))
            m.video.qualityChangeRequest = index
            onQualityChangeRequested()
            return true
        end if
    end for
    return false
end function

sub stopPlaybackForDialog()
    m.PlayVideo = destroyTask(m.PlayVideo, "response")
    cleanupReconnectTask()
    if m.video <> invalid then m.video.control = "stop"
    if m.watchdogTimer <> invalid then m.watchdogTimer.control = "stop"
    if m.bufferCheckTimer <> invalid
        m.bufferCheckTimer.control = "stop"
        m.bufferCheckTimer.unobserveField("fire")
        m.bufferCheckTimer = invalid
    end if
    if m.retryTimer <> invalid
        m.retryTimer.control = "stop"
        m.retryTimer.unobserveField("fire")
        m.retryTimer = invalid
    end if
    if m.reconnectTimer <> invalid
        m.reconnectTimer.control = "stop"
        m.reconnectTimer.unobserveField("fire")
        m.reconnectTimer = invalid
    end if
end sub

sub showChatUnavailableNotice()
    if m.infoDialog <> invalid then return
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = tr("Chat is unavailable for this video")
    dialog.message = [tr("Stitch currently supports chat during live streams. Chat replay is unavailable for VODs and clips. Your video will continue playing.")]
    dialog.buttons = [tr("Continue watching")]
    applyDialogPalette(dialog)
    dialog.observeField("buttonSelected", "dismissChatNotice")
    dialog.observeField("wasClosed", "dismissChatNotice")
    m.infoDialog = dialog
    scene = m.top.GetScene()
    if scene <> invalid then scene.dialog = dialog
end sub

sub dismissChatNotice()
    if m.infoDialog <> invalid
        m.infoDialog.unobserveField("buttonSelected")
        m.infoDialog.unobserveField("wasClosed")
    end if
    scene = m.top.GetScene()
    if scene <> invalid then scene.dialog = invalid
    m.infoDialog = invalid
    if m.video <> invalid then m.video.SetFocus(true)
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    m.isExiting = true
    m.bookmarksTask = destroyTask(m.bookmarksTask, "response")
    stopPlaybackForDialog()
    if m.watchdogTimer <> invalid then m.watchdogTimer.unobserveField("fire")
    if m.chatWindow <> invalid
        m.chatWindow.unobserveField("visible")
        m.chatWindow.callFunc("stopJobs")
        m.chatWindow.callFunc("onDestroy")
    end if
    if m.video <> invalid
        m.video.callFunc("onDestroy")
        m.video.unobserveField("toggleChat")
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("duration")
        if m.video.IsSubtype("StitchVideo")
            m.video.unobserveField("QualityChangeRequestFlag")
        else
            m.video.unobserveField("back")
        end if
    end if
    closeOwnedPlayerDialogs()
    m.errorHandler = invalid
end sub

sub closeOwnedPlayerDialogs()
    scene = m.top.GetScene()
    for each dialog in [m.errorDialog, m.infoDialog, m.transmuxDialog]
        if dialog <> invalid
            dialog.unobserveField("buttonSelected")
            dialog.unobserveField("wasClosed")
            if scene <> invalid and scene.dialog <> invalid
                if scene.dialog.IsSameNode(dialog) then scene.dialog = invalid
            end if
        end if
    end for
    m.errorDialog = invalid
    m.infoDialog = invalid
    m.transmuxDialog = invalid
end sub
