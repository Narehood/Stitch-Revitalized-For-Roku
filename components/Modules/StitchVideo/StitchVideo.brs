function init()
    ' Initialize UI elements
    m.top.enableUI = false
    m.top.enableTrickPlay = false

    ' Control overlay elements
    m.controlOverlay = m.top.findNode("controlOverlay")
    m.controlOverlay.visible = false

    ' Progress bar elements
    m.progressBarBase = m.top.findNode("progressBarBase")
    m.progressBarProgress = m.top.findNode("progressBarProgress")

    ' Control buttons
    m.backGroup = m.top.findNode("backGroup")
    m.chatGroup = m.top.findNode("chatGroup")
    m.playPauseGroup = m.top.findNode("playPauseGroup")
    m.qualityGroup = m.top.findNode("qualityGroup")
    m.controlButton = m.top.findNode("controlButton")
    m.messagesButton = m.top.findNode("messagesButton")
    m.qualitySelectButton = m.top.findNode("qualitySelectButton")

    ' Focus backgrounds
    m.backFocus = m.top.findNode("backFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.qualityFocus = m.top.findNode("qualityFocus")

    ' Other elements
    m.liveIndicator = m.top.findNode("liveIndicator")
    m.lowLatencyIndicator = m.top.findNode("lowLatencyIndicator")
    if m.lowLatencyIndicator <> invalid
        m.lowLatencyIndicatorLabel = m.lowLatencyIndicator.findNode("lowLatencyIndicatorLabel")
    end if
    m.normalLatencyIndicator = m.top.findNode("normalLatencyIndicator")
    if m.normalLatencyIndicator <> invalid
        m.normalLatencyIndicatorLabel = m.normalLatencyIndicator.findNode("normalLatencyIndicatorLabel") ' Though not changed in this iteration, good practice to have the reference
    end if

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")

    ' Quality dialog
    m.qualityDialog = m.top.findNode("QualityDialog")
    ' Set up quality dialog observer once during initialization
    m.qualityDialog.observeFieldScoped("buttonSelected", "onQualityButtonSelect")

    ' State variables
    m.currentFocusedButton = 2 ' 0=back, 1=chat, 2=play/pause, 3=quality
    m.isOverlayVisible = false
    m.currentPositionSeconds = 0
    m.isLiveStream = true ' StitchVideo is always for live streams

    ' Timers
    m.fadeAwayTimer = createObject("roSGNode", "Timer")
    m.fadeAwayTimer.observeField("fire", "onFadeAway")
    m.fadeAwayTimer.repeat = false
    m.fadeAwayTimer.duration = 5
    m.fadeAwayTimer.control = "stop"

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("qualityOptions", "onQualityOptionsChange")
    m.top.observeField("selectedQuality", "onSelectedQualityChange")

    ' Initialize UI
    updateProgressBar()
    setupLiveUI()
    updateLatencyIndicator()

    ' CRITICAL FIX: Configure low latency at initialization
    configureForLowLatency()

    ' ? "[StitchVideo] Initialized for live stream"
end function

sub configureForLowLatency()
    latencyPreference = get_user_setting("preferred.latency", "low")
    isLowLatency = (latencyPreference = "low")

    ? "[StitchVideo] ===== LOW LATENCY CONFIGURATION ====="
    ? "[StitchVideo] Latency preference: "; latencyPreference
    ? "[StitchVideo] Applying low latency config: "; isLowLatency

    if isLowLatency
        ' Check device compatibility first
        if isLowLatencySupported()
            ' Enable LL-HLS properties
            m.top.enableLowLatencyHLS = true
            m.top.hlsOptimization = "lowLatency"
            m.top.enablePartialSegments = true
            m.top.enablePreloadHints = true
            m.top.enableBlockingPlaylistReload = true

            ' Configure aggressive buffering for low latency
            m.top.bufferingConfig = {
                initialBufferingMs: 100,
                minBufferMs: 200,
                maxBufferMs: 800,
                bufferForPlaybackMs: 100,
                bufferForPlaybackAfterRebufferMs: 200,
                rebufferMs: 100
            }

            ' Configure adaptive bitrate for low latency
            m.top.adaptiveBitrateConfig = {
                initialBandwidthBps: 5000000,
                maxInitialBitrate: 8000000,
                minDurationForQualityIncreaseMs: 30000,
                minDurationForQualityDecreaseMs: 1000,
                minDurationToRetainAfterDiscardMs: 500,
                bandwidthMeterSlidingWindowMs: 2000
            }

            ' Disable decoder compatibility for better performance
            m.top.enableDecoderCompatibility = false
            m.top.maxVideoDecodeResolution = "1440p"

            ' Set actual low latency status
            m.top.isActualLowLatency = true

            ? "[StitchVideo] ✓ Low latency configuration applied successfully"
        else
            ' Device doesn't support LL-HLS properly
            m.top.isActualLowLatency = false
            ? "[StitchVideo] ⚠️ Device doesn't support LL-HLS, using normal latency"
        end if
    else
        ' User prefers normal latency
        m.top.isActualLowLatency = false
        ? "[StitchVideo] Normal latency mode selected"
    end if
    ? "[StitchVideo] ========================================"
end sub

function isLowLatencySupported() as boolean
    di = CreateObject("roDeviceInfo")
    model = di.GetModel()
    version = di.GetVersion()

    ' Check for minimum Roku OS version that supports LL-HLS
    ' Roku OS 10.0+ generally has better LL-HLS support
    versionParts = version.Split(".")
    if versionParts.Count() > 0
        majorVersion = Val(versionParts[0])
        if majorVersion >= 10
            return true
        end if
    end if

    ' Some older high-end models may support it
    supportedModels = ["4800", "4802", "4640", "3941", "3940"]
    for each supportedModel in supportedModels
        if model.InStr(supportedModel) > -1
            return true
        end if
    end for

    ' ? "[StitchVideo] Device model "; model; " with OS "; version; " may have limited LL-HLS support"
    return false
end function

sub setupLiveUI()
    ' Set up UI specifically for live streams
    m.progressBarProgress.width = m.progressBarBase.width ' Full bar for live

    ' Live indicator is only visible when overlay is shown
    m.liveIndicator.visible = m.isOverlayVisible
end sub

sub updateLatencyIndicator()
    latencySetting = get_user_setting("preferred.latency", "low")
    userPrefersLowLatency = (latencySetting = "low")
    isActuallyLowLatency = m.top.isActualLowLatency ' This field is set from VideoPlayer.brs

    ' Hide both indicators initially
    if m.lowLatencyIndicator <> invalid then m.lowLatencyIndicator.visible = false
    if m.normalLatencyIndicator <> invalid then m.normalLatencyIndicator.visible = false

    if m.isOverlayVisible
        if userPrefersLowLatency
            if m.lowLatencyIndicator <> invalid and m.lowLatencyIndicatorLabel <> invalid
                if isActuallyLowLatency
                    m.lowLatencyIndicatorLabel.text = "Stream Mode: Low Latency"
                else
                    m.lowLatencyIndicatorLabel.text = "Stream Mode: Low Latency (Unavailable)"
                end if
                m.lowLatencyIndicator.visible = true
            end if
        else ' User prefers normal latency
            if m.normalLatencyIndicator <> invalid and m.normalLatencyIndicatorLabel <> invalid
                m.normalLatencyIndicatorLabel.text = "Stream Mode: Normal" ' Ensure text is set
                m.normalLatencyIndicator.visible = true
            end if
        end if
    end if
end sub

sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    ' Live streams don't need position-based updates
end sub

sub onVideoStateChange()
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
    else if m.top.state = "buffering"
        ' Could add loading spinner here
        ' ? "[StitchVideo] Buffering..."
    else if m.top.state = "error"
        ' ? "[StitchVideo] Video error occurred"
    end if
end sub

sub onChatVisibilityChange()
    ' Adjust layout based on chat visibility
    if m.top.chatIsVisible
        m.progressBarBase.width = 900
        ' Adjust latency indicator position when chat is visible (move further left)
        m.lowLatencyIndicator.translation = [750, 0]
        m.normalLatencyIndicator.translation = [750, 0]
    else
        m.progressBarBase.width = 1160
        ' Reset latency indicator position (bottom right of overlay)
        m.lowLatencyIndicator.translation = [0, 0]
        m.normalLatencyIndicator.translation = [0, 0]
    end if
    updateProgressBar()
end sub

sub onDurationChange()
    updateProgressBar()
end sub

sub onBufferingStatusChange()
    ' Live streams handle buffering differently
    ' ? "[StitchVideo] Buffering status changed"
end sub

sub onQualityOptionsChange()
    setupQualityDialog()
end sub

sub onSelectedQualityChange()
    setupLiveUI()
    updateLatencyIndicator()
    ' ? "[StitchVideo] Quality changed to: "; m.top.selectedQuality
end sub

sub setupQualityDialog()
    if m.top.qualityOptions <> invalid and m.top.qualityOptions.count() > 0
        m.qualityDialog.title = "Please Choose Your Video Quality"
        m.qualityDialog.message = "Choose video quality:"

        buttons = []
        for each quality in m.top.qualityOptions
            buttons.push(quality)
        end for
        buttons.push("Cancel")

        m.qualityDialog.buttons = buttons
    end if
end sub

sub onQualityButtonSelect()
    ' ? "[StitchVideo] Quality dialog button selected: "; m.qualityDialog.buttonSelected

    selectedIndex = m.qualityDialog.buttonSelected
    totalButtons = m.qualityDialog.buttons.count()

    ' Hide dialog first
    m.qualityDialog.visible = false
    m.qualityDialog.setFocus(false)

    ' Check if Cancel was selected (last button)
    if selectedIndex = totalButtons - 1
        ' ? "[StitchVideo] Cancel selected, no quality change"
    else if selectedIndex >= 0 and selectedIndex < m.top.qualityOptions.count()
        ' Valid quality option selected
        selectedQuality = m.top.qualityOptions[selectedIndex]
        ' ? "[StitchVideo] Quality selected: "; selectedQuality

        m.top.selectedQuality = selectedQuality
        m.top.QualityChangeRequest = selectedIndex
        m.top.QualityChangeRequestFlag = true

        ' Update latency indicator
        updateLatencyIndicator()
    else
        ' ? "[StitchVideo] Invalid selection index: "; selectedIndex
    end if

    ' Restore focus to video component
    m.top.setFocus(true)

    ' If overlay is visible, restart fade timer
    if m.isOverlayVisible
        focusButton(m.currentFocusedButton)
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.control = "start"
    end if
end sub

sub updateProgressBar()
    ' For live streams, always show full progress bar in Twitch purple
    m.progressBarProgress.width = m.progressBarBase.width
end sub

sub showOverlay()
    m.isOverlayVisible = true
    m.controlOverlay.visible = true
    m.liveIndicator.visible = true ' Show LIVE indicator with overlay
    updateLatencyIndicator() ' Update latency indicator visibility
    focusButton(m.currentFocusedButton)

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.liveIndicator.visible = false ' Hide LIVE indicator with overlay
    updateLatencyIndicator() ' Hide latency indicators
    clearAllButtonFocus()
end sub

sub onFadeAway()
    ' Only hide overlay if quality dialog is not visible
    if not m.qualityDialog.visible
        hideOverlay()
    end if
end sub

sub focusButton(buttonIndex)
    clearAllButtonFocus()
    m.currentFocusedButton = buttonIndex

    if buttonIndex = 0 ' Back
        m.backFocus.visible = true
    else if buttonIndex = 1 ' Chat
        m.chatFocus.visible = true
    else if buttonIndex = 2 ' Play/Pause
        m.playPauseFocus.visible = true
    else if buttonIndex = 3 ' Quality
        m.qualityFocus.visible = true
    end if
end sub

sub clearAllButtonFocus()
    m.backFocus.visible = false
    m.chatFocus.visible = false
    m.playPauseFocus.visible = false
    m.qualityFocus.visible = false
end sub

sub executeButtonAction()
    if m.currentFocusedButton = 0 ' Back
        ' ? "[StitchVideo] Back button pressed - attempting to exit"
        m.top.backPressed = true
        if m.top.getParent() <> invalid
            m.top.getParent().backPressed = true
        end if
        hideOverlay()
        m.top.control = "stop"
    else if m.currentFocusedButton = 1 ' Chat
        m.top.toggleChat = true
        m.top.streamLayoutMode = (m.top.streamLayoutMode + 1) mod 3
    else if m.currentFocusedButton = 2 ' Play/Pause
        togglePlayPause()
    else if m.currentFocusedButton = 3 ' Quality
        showQualityDialog()
    end if
end sub

sub togglePlayPause()
    if m.top.state = "paused"
        m.top.control = "resume"
    else
        m.top.control = "pause"
    end if
end sub

sub showQualityDialog()
    if m.top.qualityOptions <> invalid and m.top.qualityOptions.count() > 0
        ' Stop the fade timer when showing dialog
        m.fadeAwayTimer.control = "stop"

        ' Show dialog and give it focus
        ' (Observer is already set up in init() function)
        m.qualityDialog.visible = true
        m.qualityDialog.setFocus(true)
    else
        ' ? "[StitchVideo] No quality options available"
    end if
end sub

function convertToReadableTimeFormat(time) as string
    time = Int(time)
    if time < 3600
        minutes = Int(time / 60)
        seconds = Int(time mod 60)
        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if
        return minutes.toStr() + ":" + secondStr
    else
        hours = Int(time / 3600)
        minutes = Int((time mod 3600) / 60)
        seconds = Int(time mod 60)

        if minutes < 10
            minuteStr = "0" + minutes.toStr()
        else
            minuteStr = minutes.toStr()
        end if

        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if

        return hours.toStr() + ":" + minuteStr + ":" + secondStr
    end if
end function

function onKeyEvent(key, press) as boolean
    ' ? "[StitchVideo] KeyEvent: "; key; " "; press

    if press
        ' If quality dialog is visible, only handle back to close it
        if m.qualityDialog.visible
            if key = "back" or key = "down"
                m.qualityDialog.visible = false
                m.qualityDialog.setFocus(false)
                m.top.setFocus(true)

                ' Restart fade timer if overlay is visible
                if m.isOverlayVisible
                    focusButton(m.currentFocusedButton)
                    m.fadeAwayTimer.control = "stop"
                    m.fadeAwayTimer.control = "start"
                end if
                return true
            end if
            ' Let dialog handle all other keys
            return false
        end if

        ' Normal key handling when dialog is not visible
        ' Reset fade timer on any key press (except back when overlay is hidden)
        if key <> "back" or m.isOverlayVisible
            if m.isOverlayVisible
                m.fadeAwayTimer.control = "stop"
                m.fadeAwayTimer.control = "start"
            end if
        end if

        return handleMainKeys(key)
    end if

    return false
end function

function handleMainKeys(key) as boolean
    if key = "up" or key = "OK" or key = "play"
        if not m.isOverlayVisible
            showOverlay()
            return true
        end if
    end if

    if not m.isOverlayVisible
        return false
    end if

    if key = "left"
        ' Live stream navigation: back(0) -> chat(1) -> play/pause(2) -> quality(3)
        if m.currentFocusedButton > 0
            focusButton(m.currentFocusedButton - 1)
        else
            focusButton(3) ' Wrap to quality
        end if
        return true
    else if key = "right"
        ' Live stream navigation: back(0) -> chat(1) -> play/pause(2) -> quality(3)
        if m.currentFocusedButton < 3
            focusButton(m.currentFocusedButton + 1)
        else
            focusButton(0) ' Wrap to back
        end if
        return true
    else if key = "down" or key = "back"
        hideOverlay()
        return true
    else if key = "OK"
        executeButtonAction()
        return true
    else if key = "play"
        togglePlayPause()
        return true
    end if

    return false
end function