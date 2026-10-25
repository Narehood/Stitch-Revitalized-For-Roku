function getNextLowerQuality(video as object) as object
    if video.qualityOptions = invalid or video.qualityOptions.count() = 0
        return invalid
    end if

    currentQuality = video.selectedQuality
    if currentQuality = invalid
        return invalid
    end if

    ' Find current quality index
    currentIndex = -1
    for i = 0 to video.qualityOptions.count() - 1
        if video.qualityOptions[i] = currentQuality
            currentIndex = i
            exit for
        end if
    end for

    ' Get next lower quality (higher index typically means lower quality)
    if currentIndex >= 0 and currentIndex < video.qualityOptions.count() - 1
        return {
            qualityID: video.qualityOptions[currentIndex + 1],
            index: currentIndex + 1,
            isLowerQuality: true
        }
    end if

    return invalid
end function
