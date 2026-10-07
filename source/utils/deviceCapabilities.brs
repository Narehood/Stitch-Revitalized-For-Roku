' Video decoding is independent of the resolution of the SceneGraph UI plane.
' CanDecodeVideo accepts codec/profile/level; dimensions and frame rate are
' constrained here rather than passed as undocumented query parameters.
' https://developer.roku.com/dev/docs/ifdeviceinfo
function getTwitchSupportedCodecs(device = invalid as dynamic) as string
    if device = invalid then device = CreateObject("roDeviceInfo")
    codecs = "h264"
    try
        result = device.CanDecodeVideo({ codec: "hevc", profile: "main", level: "5.0" })
        if result <> invalid and result.result = true then codecs += ",h265"
    catch e
        ' Older devices continue with AVC.
    end try
    return codecs
end function

function twitchVariantVideoFormat(variant as object) as dynamic
    resolution = variant["RESOLUTION"]
    if resolution = invalid then return invalid
    dimensions = resolution.Split("x")
    if dimensions.Count() <> 2 then return invalid
    width = Val(dimensions[0])
    height = Val(dimensions[1])
    fps = 30.0
    if variant["FRAME-RATE"] <> invalid then fps = Val(variant["FRAME-RATE"])
    if width <= 0 or height <= 0 or fps <= 0 or fps > 60.01 then return invalid

    codecText = ""
    if variant["CODECS"] <> invalid then codecText = LCase(variant["CODECS"])
    format = { codec: "mpeg4 avc", profile: "high", level: "3.1" }
    minimumLevel = 3.1
    if width > 1280 or height > 720 then minimumLevel = 4.0
    if fps > 30 and (width > 1280 or height > 720) then minimumLevel = 4.2
    if fps > 30 and minimumLevel < 3.2 then minimumLevel = 3.2

    if codecText.InStr("hvc1") >= 0 or codecText.InStr("hev1") >= 0
        if width > 3840 or height > 2160 then return invalid
        if variant["BANDWIDTH"] <> invalid and Val(variant["BANDWIDTH"]) > 40000000 then return invalid
        format = { codec: "hevc", profile: "main", level: "4.0" }
        ' HEVC level limits are based on picture size AND luma sample rate.
        ' 1440p60 fits level 5.0; it must not be treated as 2160p60 (5.1).
        ' https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/h265_profile_level.c
        minimumLevel = 4.0
        pictureSize = width * height
        sampleRate = pictureSize * fps
        if sampleRate > 66846720 then minimumLevel = 4.1
        if pictureSize > 2228224 or sampleRate > 133693440 then minimumLevel = 5.0
        if sampleRate > 267386880 then minimumLevel = 5.1
        for each codec in codecText.Split(",")
            codec = codec.Trim()
            if codec.Left(5) = "hvc1." or codec.Left(5) = "hev1."
                parts = codec.Split(".")
                if parts.Count() < 4 then return invalid
                if parts[1] = "2"
                    format.profile = "main 10"
                else if parts[1] <> "1"
                    return invalid
                end if
                for each part in parts
                    if part.Left(1) = "l" or part.Left(1) = "h"
                        advertisedLevel = Val(part.Mid(1)) / 30
                        if advertisedLevel > minimumLevel then minimumLevel = advertisedLevel
                    end if
                end for
            end if
        end for
    else
        if codecText <> "" and codecText.InStr("avc1") < 0 and codecText.InStr("avc3") < 0 then return invalid
        if width > 1920 or height > 1080 then return invalid
        for each codec in codecText.Split(",")
            codec = codec.Trim()
            if codec.Left(5) = "avc1." or codec.Left(5) = "avc3."
                profileLevel = codec.Mid(5)
                if profileLevel.Len() <> 6 then return invalid
                profile = playbackHexValue(profileLevel.Left(2))
                if profile = 66
                    format.profile = "baseline"
                else if profile = 77
                    format.profile = "main"
                else if profile <> 100
                    return invalid
                end if
                advertisedLevel = playbackHexValue(profileLevel.Right(2)) / 10
                if advertisedLevel > minimumLevel then minimumLevel = advertisedLevel
            end if
        end for
    end if
    levelTenths = Int(minimumLevel * 10 + 0.5)
    format.level = Int(levelTenths / 10).ToStr() + "." + (levelTenths mod 10).ToStr()
    return format
end function

function playbackHexValue(value as string) as integer
    total = 0
    digits = "0123456789abcdef"
    for index = 0 to value.Len() - 1
        digit = digits.InStr(LCase(value.Mid(index, 1)))
        if digit < 0 then return -1
        total = total * 16 + digit
    end for
    return total
end function

function isTwitchVariantSupported(variant as object, device = invalid as dynamic) as boolean
    format = twitchVariantVideoFormat(variant)
    if format = invalid then return false
    if device = invalid then device = CreateObject("roDeviceInfo")
    try
        result = device.CanDecodeVideo(format)
        return result <> invalid and result.result = true
    catch e
        return false
    end try
end function
