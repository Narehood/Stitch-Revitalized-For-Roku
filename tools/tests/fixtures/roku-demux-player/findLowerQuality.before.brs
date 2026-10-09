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
