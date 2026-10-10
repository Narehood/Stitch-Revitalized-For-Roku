' Task-owned gate: actual downloaded initialization bytes are checked BEFORE publication.
sub validateLiveInitOutput(payload as object)
    if m.top.stopRequested then return
    actual = nativeLiveInspectInitMetadata(payload)
    frameRate = m.config["metadata"]["frameRate"]
    bandwidth = m.config.metadata.bandwidth
    variant = nativeLiveInitMetadataVariant(actual, frameRate, bandwidth)
    nlCheck(variant <> invalid, "actual init metadata invalid")
    allowed = nativeLiveInitMetadataSupported(actual, frameRate, bandwidth)
    nlCheck(allowed, "actual init decoder rejected")
    if m.top.stopRequested then return
    m.config["metadata"] = { "videoCodec": actual.videoCodec, "audioCodec": actual.audioCodec, "width": actual.width, "height": actual.height, "frameRate": frameRate, "bandwidth": bandwidth, "isHD": actual.height >= 720 }
    m.result["decoderApproved"] = allowed
    m.result["actualInitValidated"] = true
    m.result["requestedDecoderFormat"] = twitchVariantVideoFormat(variant)
end sub
