' Returns row item size and height config for a given content type.
' contentType: string — the contentType field from a TwitchContentNode child
' hasRowLabel: boolean — whether the row has a visible label (affects height)
' tallRows: boolean — reserve space for the expanded stream card text
' Returns: { itemSize: [width, height], rowHeight: integer }
' Returns invalid if contentType is unrecognized.
function getRowConfig(contentType, hasRowLabel as boolean, tallRows = false as boolean) as object
    if contentType = invalid then return invalid

    if contentType = "LIVE" or contentType = "VOD" or contentType = "CLIP"
        itemSize = [320, 180]
        if tallRows
            if hasRowLabel
                rowHeight = 295
            else
                rowHeight = 255
            end if
        else
            if hasRowLabel
                rowHeight = 275
            else
                rowHeight = 235
            end if
        end if
        return { itemSize: itemSize, rowHeight: rowHeight }
    end if

    if contentType = "GAME"
        ' The category subtitle ends at y=308; leave padding and label space.
        if hasRowLabel
            rowHeight = 355
        else
            rowHeight = 315
        end if
        return { itemSize: [188, 250], rowHeight: rowHeight }
    end if

    if contentType = "USER"
        if hasRowLabel
            rowHeight = 260
        else
            rowHeight = 240
        end if
        return { itemSize: [150, 150], rowHeight: rowHeight }
    end if

    return invalid
end function
