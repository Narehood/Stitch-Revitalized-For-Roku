' @include source/utils/deviceCapabilities.brs
sub main()
    avcDevice = {
        graphicsHeight: 720,
        CanDecodeVideo: function(format as object) as object
            return { result: format.codec = "mpeg4 avc" and Val(format.level) <= 4.2 }
        end function
    }
    hevcDevice = {
        graphicsHeight: 720,
        CanDecodeVideo: function(format as object) as object
            return { result: (format.codec = "mpeg4 avc" and Val(format.level) <= 4.2) or (format.codec = "hevc" and format.profile = "main" and Val(format.level) <= 5.1) }
        end function
    }
    avc = { RESOLUTION: "1920x1080", "FRAME-RATE": "60", CODECS: "avc1.64002a,mp4a.40.2", BANDWIDTH: "6000000" }
    hevc = { RESOLUTION: "2560x1440", "FRAME-RATE": "60", CODECS: "hvc1.1.6.L153.B0,mp4a.40.2", BANDWIDTH: "8500000" }
    if not playbackCapabilityExpect(isTwitchVariantSupported(avc, avcDevice), "1080p60 on a 720p UI device") then return
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc, avcDevice), "1440p HEVC excluded on AVC decoder") then return
    if not playbackCapabilityExpect(isTwitchVariantSupported(hevc, hevcDevice), "1440p60 HEVC included on capable decoder") then return
    if not playbackCapabilityExpect(getTwitchSupportedCodecs(avcDevice) = "h264", "old-device AVC Usher fallback") then return
    if not playbackCapabilityExpect(getTwitchSupportedCodecs(hevcDevice) = "h264,h265", "verified HEVC negotiation names") then return
    hevcFormat = twitchVariantVideoFormat(hevc)
    if not playbackCapabilityExpect(hevcFormat.codec = "hevc" and hevcFormat.profile = "main" and Val(hevcFormat.level) = 5.1, "documented HEVC decoder query fields") then return
    hevc.CODECS = "hvc1.1.6.L150.B0,mp4a.40.2"
    if not playbackCapabilityExpect(Val(twitchVariantVideoFormat(hevc).level) = 5.0, "1440p60 fits HEVC level 5.0") then return
    hevc.CODECS = "hvc1.2.4.L153.B0,mp4a.40.2"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc, hevcDevice), "unsupported Main10 rejected") then return
    hevc.CODECS = "hvc1.1.6.L153.B0,mp4a.40.2"
    hevc["FRAME-RATE"] = "120"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(hevc, hevcDevice), "unsupported frame rate rejected") then return
    avc.RESOLUTION = "2560x1440"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc, avcDevice), "AVC conservative resolution cap") then return
    avc.RESOLUTION = "bad-resolution"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc, avcDevice), "malformed resolution rejected") then return
    avc.RESOLUTION = "1920x1080"
    avc.CODECS = "av01.0.08M.08,mp4a.40.2"
    if not playbackCapabilityExpect(not isTwitchVariantSupported(avc, hevcDevice), "unnegotiated AV1 rejected") then return
    ? "STITCH_TEST_PASS: playback-capabilities"
end sub

function playbackCapabilityExpect(condition as boolean, detail as string) as boolean
    if not condition then ? "STITCH_TEST_FAIL: " + detail
    return condition
end function
