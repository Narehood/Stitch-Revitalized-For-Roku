sub handleContent()
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = m.top.contentRequested.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end sub

function handleItemSelected()
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    ' m.top.playContent = true
    ' m.top.contentSelected = selectedItem
    m.PlayVideo = CreateObject("roSGNode", "GetTwitchContent")
    m.PlayVideo.observeField("response", "OnResponse")
    m.PlayVideo.contentRequested = selectedItem.getFields()
    m.PlayVideo.functionName = "main"
    m.PlayVideo.control = "run"
end function

sub onResponse()
    response = m.PlayVideo.response
    if response = invalid or response.url = invalid or response.url = ""
        ? "[VideoPlayer] Playback content missing or has no URL — aborting start"
        m.allowBreak = true
        m.top.state = "done"
        m.top.backpressed = true
        return
    end if
    m.top.content = response
    m.top.metadata = m.PlayVideo.metadata
    playContent()
end sub

sub taskStateChanged(event as object)
    ' print "Player: taskStateChanged(), id = "; event.getNode(); ", "; event.getField(); " = "; event.getData()
    state = event.GetData()
    if state = "done" or state = "stop"
        exitPlayer()
    end if
end sub

sub controlChanged()
    'handle orders by the parent/owner
    control = m.top.control
    if control = "play" then
        playContent()
    else if control = "stop" then
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
    idx = m.video.qualityChangeRequest
    if m.top.metadata = invalid or idx = invalid or idx < 0 or idx >= m.top.metadata.Count()
        return
    end if
    selected = m.top.metadata[idx]
    new_content = CreateObject("roSGNode", "TwitchContentNode")
    new_content.setFields(m.top.contentRequested.getFields())
    ' Apply only ContentNode-safe playback fields from the chosen rung
    if selected.QualityID <> invalid then new_content.QualityID = selected.QualityID
    if selected.StreamUrls <> invalid and selected.StreamUrls.Count() > 0
        new_content.url = selected.StreamUrls[0]
        new_content.StreamUrls = selected.StreamUrls
    end if
    if selected.StreamQualities <> invalid then new_content.StreamQualities = selected.StreamQualities
    if selected.StreamContentIds <> invalid
        new_content.StreamContentIds = selected.StreamContentIds
    else if selected.StreamContentIDs <> invalid
        new_content.StreamContentIds = selected.StreamContentIDs
    end if
    if selected.StreamBitrates <> invalid then new_content.StreamBitrates = selected.StreamBitrates
    if selected.StreamStickyHttpRedirects <> invalid then new_content.StreamStickyHttpRedirects = selected.StreamStickyHttpRedirects
    if selected.isLowLatency <> invalid then new_content.isLowLatency = selected.isLowLatency
    if selected.lowLatencyStreamsAvailable <> invalid then new_content.lowLatencyStreamsAvailable = selected.lowLatencyStreamsAvailable
    m.top.content = new_content
    m.allowBreak = false
    exitPlayer()
    playContent()
    m.allowBreak = true
end sub

sub configureVideoForLatency(video as object, isLive as boolean)
    latencyPreference = get_user_setting("preferred.latency", "normal")
    isLowLatency = (latencyPreference = "low")

    ' StitchVideo owns its live player UX/config. Do not poke experimental
    ' LL-HLS / buffering fields on it from here — that path wedged playback.
    if video.isSubtype("StitchVideo")
        if isLive
            actualLL = false
            if m.top.content <> invalid and m.top.content.isLowLatency = true
                actualLL = true
            end if
            video.isActualLowLatency = actualLL
        end if
        return
    end if

    if isLive and isLowLatency
        video.bufferingConfig = {
            initialBufferingMs: 1000,
            minBufferMs: 2000,
            maxBufferMs: 6000,
            bufferForPlaybackMs: 1000,
            bufferForPlaybackAfterRebufferMs: 2000,
            rebufferMs: 1000
        }
    else if isLive
        video.bufferingConfig = {
            initialBufferingMs: 2000,
            minBufferMs: 5000,
            maxBufferMs: 15000,
            bufferForPlaybackMs: 2000,
            bufferForPlaybackAfterRebufferMs: 5000,
            rebufferMs: 2000
        }
    else
        video.bufferingConfig = {
            initialBufferingMs: 3000,
            minBufferMs: 10000,
            maxBufferMs: 30000,
            bufferForPlaybackMs: 3000,
            bufferForPlaybackAfterRebufferMs: 8000,
            rebufferMs: 3000
        }
    end if
end sub

sub measureStreamDelay()
    if m.video <> invalid and m.video.content <> invalid
        currentTime = CreateObject("roDateTime").AsSeconds()
        videoPosition = m.video.position

        ' Initialize tracking on first call
        if m.delayTrackingStartTime = invalid
            m.delayTrackingStartTime = currentTime
            m.delayTrackingStartPosition = videoPosition
            m.lastRealTime = currentTime
            m.lastVideoPosition = videoPosition
            ' ? "[VideoPlayer] ===== INITIAL DELAY MEASUREMENT ====="
            ' ? "[VideoPlayer] Starting delay tracking..."
            ' ? "[VideoPlayer] Initial position: "; videoPosition; " seconds"
            ' ? "[VideoPlayer] ==========================================="
            return
        end if

        ' Calculate time since we started tracking
        realTimeElapsed = currentTime - m.lastRealTime
        videoTimeElapsed = videoPosition - m.lastVideoPosition

        ' For live streams, video should progress at same rate as real time
        ' Any difference indicates buffering/delay from live edge
        if realTimeElapsed > 0
            progressionRate = videoTimeElapsed / realTimeElapsed

            ' Estimate delay based on how video progression compares to real time
            if m.estimatedLiveDelay = invalid then m.estimatedLiveDelay = 25 ' Start with reasonable estimate

            ' If video is progressing slower than real time, we're falling behind
            if progressionRate < 0.99 ' Allow small variance
                ' We're falling behind the live stream
                delayIncrease = realTimeElapsed * (1 - progressionRate)
                m.estimatedLiveDelay = m.estimatedLiveDelay + delayIncrease
            else if progressionRate > 1.01
                ' We're catching up (unlikely but possible during buffering recovery)
                delayCatchup = realTimeElapsed * (progressionRate - 1)
                m.estimatedLiveDelay = m.estimatedLiveDelay - delayCatchup
            end if

            ' Keep delay within reasonable bounds for live streams
            if m.estimatedLiveDelay < 5 then m.estimatedLiveDelay = 5
            if m.estimatedLiveDelay > 120 then m.estimatedLiveDelay = 120

            ' ? "[VideoPlayer] ===== STREAM DELAY MEASUREMENT ====="
            ' ? "[VideoPlayer] Real time elapsed: "; realTimeElapsed; " seconds"
            ' ? "[VideoPlayer] Video time elapsed: "; videoTimeElapsed; " seconds"
            ' ? "[VideoPlayer] Progression rate: "; Int(progressionRate * 100); "%"
            ' ? "[VideoPlayer] ESTIMATED LIVE DELAY: "; Int(m.estimatedLiveDelay); " seconds"

            ' Convert to minutes:seconds for readability
            delayMinutes = Int(m.estimatedLiveDelay / 60)
            delaySeconds = Int(m.estimatedLiveDelay mod 60)
            ' ? "[VideoPlayer] Delay: "; delayMinutes; ":"; FormatSeconds(delaySeconds)

            ' Additional context
            ' if progressionRate < 0.95
            '     ? "[VideoPlayer] ⚠️  Falling behind live stream"
            ' else if progressionRate > 1.05
            '     ? "[VideoPlayer] ✓ Catching up to live stream"
            ' else
            '     ? "[VideoPlayer] ✓ Keeping pace with live stream"
            ' end if

            ' if m.video.bufferingStatus <> invalid
            '     ? "[VideoPlayer] Buffering status: "; m.video.bufferingStatus
            ' end if

            ' ? "[VideoPlayer] ==========================================="
        end if

        ' Update tracking values
        m.lastRealTime = currentTime
        m.lastVideoPosition = videoPosition
    end if
end sub

function FormatSeconds(seconds as integer) as string
    if seconds < 10
        return "0" + seconds.toStr()
    else
        return seconds.toStr()
    end if
end function

sub playContent()
    ' Clean up existing video node and its observers
    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        m.video.unobserveField("QualityChangeRequestFlag") ' StitchVideo specific
        m.video.unobserveField("qualityChangeRequest") ' StitchVideo specific
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("errorCode")
        m.video.unobserveField("duration")
        m.video.unobserveField("back") ' CustomVideo specific

        m.top.removeChild(m.video)
        m.video = invalid
    end if

    isLiveContent = (m.top.contentRequested.contentType = "LIVE")
    isClipContent = (m.top.contentRequested.contentType = "CLIP")

    ' ? "[VideoPlayer] ===== PLAYBACK INITIALIZATION ====="
    ' ? "[VideoPlayer] Content type: "; m.top.contentRequested.contentType
    ' ? "[VideoPlayer] Is live: "; isLiveContent
    ' ? "[VideoPlayer] Is clip: "; isClipContent

    if isLiveContent
        quality_options = []
        if m.top.metadata <> invalid
            for each quality_option in m.top.metadata
                quality_options.push(quality_option.qualityID)
            end for
        end if
        m.video = m.top.CreateChild("StitchVideo")
        m.video.qualityOptions = quality_options
        ' ? "[VideoPlayer] Created StitchVideo component for live stream"
        ' StitchVideo will observe its own selectedQuality field
    else
        m.video = m.top.CreateChild("CustomVideo")
        ' ? "[VideoPlayer] Created CustomVideo component for VOD/clip"
    end if

    httpAgent = CreateObject("roHttpAgent")
    httpAgent.setCertificatesFile("common:/certs/ca-bundle.crt")
    httpAgent.InitClientCertificates()
    httpAgent.enableCookies()

    if isClipContent
        headers = TwitchClipPlaybackHeaders()
    else
        ' Keep playback headers minimal/stable — LL-specific agent headers are optional.
        headers = TwitchWebPlaybackHeaders(false)
    end if
    for each key in headers
        httpAgent.addheader(key, headers[key])
    end for
    m.video.setHttpAgent(httpAgent)

    ' Configure video player properties (buffering, ABR config, decode caps)
    configureVideoForLatency(m.video, isLiveContent)

    m.video.notificationInterval = 1

    ' Add observers to the new video node
    m.video.observeField("toggleChat", "onToggleChat")
    if isLiveContent
        m.video.observeField("QualityChangeRequestFlag", "onQualityChangeRequested") ' StitchVideo specific
    else
        m.video.observeField("back", "onVideoBack") ' CustomVideo specific
    end if
    m.video.observeField("position", "onPositionChanged")
    m.video.observeField("state", "onVideoStateChange")
    m.video.observeField("errorCode", "onVideoError")
    m.video.observeField("duration", "onDurationChanged")

    videoBookmarks = get_user_setting("VideoBookmarks", "")
    m.video.video_type = m.top.contentRequested.contentType
    m.video.video_id = m.top.contentRequested.contentId

    if videoBookmarks <> ""
        m.video.videoBookmarks = ParseJSON(videoBookmarks)
    else
        m.video.videoBookmarks = {}
    end if

    contentNodeToPlay = m.top.content ' This is the TwitchContentNode
    if contentNodeToPlay <> invalid then
        ' ? "[VideoPlayer] Preparing to play content. QualityID: "; contentNodeToPlay.QualityID
        ' ? "[VideoPlayer] Latency Preference: "; get_user_setting("preferred.latency", "low")

        if isLiveContent
            contentNodeToPlay.ignoreStreamErrors = false
            contentNodeToPlay.streamFormat = "hls"
            contentNodeToPlay.live = true

            currentQualityID = ""
            if contentNodeToPlay.QualityID <> invalid
                currentQualityID = contentNodeToPlay.QualityID
            end if
            isAutomaticQuality = (currentQualityID <> "" and currentQualityID.Instr("Automatic") > -1)

            if isAutomaticQuality
                contentNodeToPlay.switchingStrategy = "full-adaptation"
            else
                contentNodeToPlay.switchingStrategy = "no-adaptation"
            end if
        else if isClipContent
            contentNodeToPlay.ignoreStreamErrors = true
            contentNodeToPlay.switchingStrategy = "no-adaptation"
            contentNodeToPlay.streamFormat = "mp4"
            contentNodeToPlay.enableTrickPlay = false
        else ' VOD
            contentNodeToPlay.ignoreStreamErrors = true
            contentNodeToPlay.streamFormat = "hls"
            contentNodeToPlay.switchingStrategy = "full-adaptation"
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

        m.video.visible = false ' Make visible after PlayerTask starts if needed

        if m.video.video_id <> invalid and m.top.contentRequested.contentType <> "LIVE"
            ' ? "[VideoPlayer] VOD/Clip ID is valid: "; m.video.video_id
            if m.video.videoBookmarks.DoesExist(m.video.video_id)
                ' ? "[VideoPlayer] Jump To Position From Bookmarks > "; m.video.videoBookmarks[m.video.video_id]
                m.video.seek = Val(m.video.videoBookmarks[m.video.video_id])
            end if
        end if

        m.PlayerTask = CreateObject("roSGNode", "PlayerTask")
        m.PlayerTask.observeField("state", "taskStateChanged")
        m.PlayerTask.video = m.video
        m.PlayerTask.control = "RUN"

        if isLiveContent
            initChat()
            ' Start measuring delay after a short delay to let the stream start
            m.delayMeasureTimer = createObject("roSGNode", "Timer")
            m.delayMeasureTimer.observeField("fire", "measureStreamDelay")
            m.delayMeasureTimer.repeat = false
            m.delayMeasureTimer.duration = 10 ' Wait 10 seconds before first measurement
            m.delayMeasureTimer.control = "start"
        end if

        ' ? "[VideoPlayer] ==========================================="
    else
        ' ? "[VideoPlayer] Error: contentNodeToPlay is invalid. Cannot start playback."
    end if
end sub

sub exitPlayer()
    ' print "[VideoPlayer] exitPlayer()"

    if m.delayMeasureTimer <> invalid
        m.delayMeasureTimer.control = "stop"
        m.delayMeasureTimer = invalid
    end if

    if m.video <> invalid
        m.video.unobserveField("toggleChat")
        if m.video.isSubtype("StitchVideo")
            m.video.unobserveField("QualityChangeRequestFlag")
        else if m.video.isSubtype("CustomVideo")
            m.video.unobserveField("back")
        end if
        m.video.unobserveField("position")
        m.video.unobserveField("state")
        m.video.unobserveField("errorCode")
        m.video.unobserveField("duration")

        m.video.control = "stop"
        m.video.visible = false
    end if

    if m.PlayerTask <> invalid
        m.PlayerTask.unobserveField("state")
        m.PlayerTask.control = "stop" ' Ensure task is stopped
        m.PlayerTask = invalid
    end if

    ' ? "[VideoPlayer] Allow Break?: "; m.allowBreak
    if m.allowBreak
        m.top.state = "done"
        m.top.backpressed = true ' Ensure this signals back correctly
    end if
end sub

function onKeyEvent(key, press) as boolean
    if press
        ' ? "[VideoPlayer] Key Event: "; key
        if key = "back" then
            if m.chatWindow <> invalid and m.chatWindow.visible = true
                m.chatWindow.callFunc("stopJobs") ' Stop chat jobs if chat is open
            end if
            m.allowBreak = true ' Ensure exitPlayer signals upwards
            exitPlayer()
            ' m.top.backpressed = true ' This is set in exitPlayer if allowBreak is true
            return true
        end if
    end if
    return false ' Let child video component (StitchVideo/CustomVideo) handle other keys
end function

sub init()
    m.chatWindow = m.top.findNode("chat")
    if m.chatWindow <> invalid
        m.chatWindow.fontSize = get_user_setting("ChatFontSize")
        m.chatWindow.observeField("visible", "onChatVisibilityChange")
    end if
    m.allowBreak = true ' Default to allowing break unless in quality change

    ' Initialize delay tracking variables
    m.lastDelayMeasurement = invalid
    m.estimatedDelay = 0
    m.streamStartSystemTime = invalid
    ' New variables for proper live delay tracking
    m.delayTrackingStartTime = invalid
    m.delayTrackingStartPosition = invalid
    m.lastRealTime = invalid
    m.lastVideoPosition = invalid
    m.estimatedLiveDelay = invalid
end sub

sub onToggleChat()
    ' ? "[VideoPlayer] onToggleChat received from video component"
    if m.video.toggleChat = true ' Check the field on the video component
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
        ' ? "[VideoPlayer] Chat visibility changed. Chat visible: "; m.chatWindow.visible; ", Video width: "; m.video.width
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

    ' Measure delay every 30 seconds for debugging
    if m.video <> invalid and Int(m.video.position) mod 30 = 0
        measureStreamDelay()
    end if
end sub

sub onVideoStateChange()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onVideoStateChange for UI.
    ' ? "[VideoPlayer] Global onVideoStateChange: "; m.video.state
    if m.video.state = "finished" and m.allowBreak
        ' ? "[VideoPlayer] Video finished, exiting player."
        exitPlayer()
    else if m.video.state = "error"
        ' ? "[VideoPlayer] Video error state. Code: "; m.video.errorCode; ", Message: "; m.video.errorMessage
        ' Potentially show a global error message or attempt recovery if not handled by child
    end if
end sub

sub onVideoError()
    ' ? "[VideoPlayer] Global onVideoError. Code: "; m.video.errorCode; ", Message: "; m.video.errorMessage
    ' This can be used for more detailed global error logging or recovery.
end sub

sub onDurationChanged()
    ' This is observed on m.video.
    ' StitchVideo/CustomVideo have their own onDurationChange for UI.
    ' ? "[VideoPlayer] Global onDurationChanged: "; m.video.duration
end sub

sub onVideoBack()
    ' Called when CustomVideo's back field is true
    ' ? "[VideoPlayer] Back key propagated from CustomVideo"
    if m.chatWindow <> invalid and m.chatWindow.visible = true
        m.chatWindow.callFunc("stopJobs")
    end if
    m.allowBreak = true
    exitPlayer()
end sub