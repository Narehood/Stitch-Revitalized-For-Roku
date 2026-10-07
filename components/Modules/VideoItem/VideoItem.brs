sub init()
    m.disposed = false
    m.itemlabel = m.top.findNode("itemLabel")
    m.itemmask = m.top.findNode("itemMask")
    m.timestampRect = m.top.findNode("timestampRect")
    m.timestampLabel = m.top.findNode("timestampLabel")
    m.itemposter = m.top.findNode("itemPoster")
    m.circlePoster = m.top.findNode("circlePoster")
    m.liveicon = m.top.findNode("liveIcon")
    m.itemSubtitle = m.top.findNode("itemSubtitle")
    m.itemViewers = m.top.findNode("itemViewers")
    m.viewsRect = m.top.findNode("viewsRect")
    m.runtimeRect = m.top.findNode("runtimeRect")
    m.runtimeLabel = m.top.findNode("runtimeLabel")
    initLiveBadge()
    initTitleFonts()
end sub

' Category tiles are narrower, so their titles use a smaller size. Both fonts
' are created once per card instance and swapped as RowList recycles it.
sub initTitleFonts()
    m.titleFont = invalid
    m.gameTitleFont = invalid
    if m.itemlabel = invalid or m.itemlabel.font = invalid then return
    m.titleFont = m.itemlabel.font
    m.gameTitleFont = CreateObject("roSGNode", "Font")
    m.gameTitleFont.uri = m.titleFont.uri
    m.gameTitleFont.size = 20
end sub

sub setTitleFont(font as dynamic)
    if font = invalid or m.itemlabel = invalid then return
    current = m.itemlabel.font
    if current <> invalid and current.isSameNode(font) then return
    m.itemlabel.font = font
end sub

' Sizes the red badge to the localized LIVE text once per card instance.
sub initLiveBadge()
    badge = m.top.findNode("liveBadge")
    label = m.top.findNode("liveLabel")
    if badge = invalid or label = invalid then return
    ' Width 0 lets the label size to its text for measuring.
    label.width = 0
    label.text = tr("LIVE")
    width = 52
    try
        textWidth = label.localBoundingRect().width
        if textWidth + 16 > width then width = textWidth + 16
    catch e
    end try
    badge.width = width
    label.width = width
end sub

' Restores the LIVE/VOD/CLIP card geometry. RowList recycles item components
' across rows, so GAME or USER geometry would otherwise carry over.
sub resetLayout()
    m.itemposter.width = 320
    m.itemposter.height = 180
    m.itemposter.loadwidth = 320
    m.itemposter.loadheight = 180
    m.itemlabel.maxwidth = 320
    m.itemlabel.translation = [0, 192]
    m.itemSubtitle.translation = [0, 222]
end sub

' Joins card subtitle parts with a middle dot, skipping empty parts.
function joinSubtitle(first as dynamic, second as dynamic) as string
    parts = []
    for each part in [first, second]
        if part <> invalid and part.toStr() <> "" then parts.push(part.toStr())
    end for
    return parts.join(" · ")
end function

' Reset all toggleable nodes to their default visible state before each
' content type configures its own layout. RowList recycles item components,
' so state from a previous content type would otherwise bleed through.
sub resetVisibility()
    if m.itemposter = invalid then return
    m.itemposter.visible = true
    if m.circlePoster <> invalid then m.circlePoster.visible = false
    if m.liveicon <> invalid then m.liveicon.visible = true
    if m.itemViewers <> invalid then m.itemViewers.visible = true
    if m.viewsRect <> invalid then m.viewsRect.visible = true
    ' No content type populates the runtime badge; an empty 9-patch would
    ' otherwise draw as a stray square under the LIVE badge.
    if m.runtimeRect <> invalid then m.runtimeRect.visible = false
    if m.runtimeLabel <> invalid then m.runtimeLabel.visible = false
    if m.timestampLabel <> invalid then m.timestampLabel.visible = true
    if m.timestampRect <> invalid then m.timestampRect.visible = true
end sub

sub showcontent()
    if m.disposed then return
    resetVisibility()
    if m.itemposter <> invalid and m.itemlabel <> invalid and m.itemSubtitle <> invalid then resetLayout()
    GlobalSettings()
    titleFont = m.titleFont
    if m.top.itemContent.contentType = "GAME" then titleFont = m.gameTitleFont
    setTitleFont(titleFont)
    if m.top.itemContent.contentType = "GAME"
        GameSettings()
    else if m.top.itemContent.contentType = "LIVE"
        LiveSettings()
    else if m.top.itemContent.contentType = "VOD"
        VodSettings()
    else if m.top.itemContent.contentType = "CLIP"
        ClipSettings()
    else if m.top.itemContent.contentType = "USER"
        UserSettings()
    end if
end sub

sub GlobalSettings()
    if m.global = invalid or m.global.constants = invalid then return
    if m.itemSubtitle = invalid then return
    m.itemSubtitle.color = m.global.constants.ui.color.textSecondary
end sub

sub GameSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.itemSubtitle = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.width = 188
    m.itemposter.height = 250
    m.itemposter.loadwidth = 188
    m.itemposter.loadheight = 250
    m.itemlabel.maxwidth = 188
    m.itemlabel.translation = [0, 258]
    m.itemSubtitle.translation = [0, 284]
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.viewersDisplay
    m.itemposter.uri = m.top.itemContent.gameBoxArtUrl
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub LiveSettings()
    if m.itemposter = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.itemViewers.text = m.top.itemContent.viewersDisplay
    try
        m.viewsRect.height = m.itemViewers.boundingRect().height
        m.viewsRect.width = m.itemViewers.boundingRect().width + 6
    catch e
    end try
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = joinSubtitle(m.top.itemContent.streamerDisplayName, m.top.itemContent.gameDisplayName)
    m.itemlabel.text = m.top.itemContent.contentTitle
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
end sub

sub VodSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.liveicon.visible = false
    m.itemViewers.text = m.top.itemContent.viewersDisplay
    try
        m.viewsRect.height = m.itemViewers.boundingRect().height
        m.viewsRect.width = m.itemViewers.boundingRect().width + 6
        m.timestampLabel.text = m.top.itemContent.relativePublishDate
        m.timestampRect.height = m.timestampLabel.boundingRect().height
        m.timestampRect.width = m.timestampLabel.boundingRect().width + 6
    catch e
    end try
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = joinSubtitle(m.top.itemContent.streamerDisplayName, m.top.itemContent.gameDisplayName)
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub ClipSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.liveicon.visible = false
    m.itemViewers.text = m.top.itemContent.viewersDisplay
    try
        m.viewsRect.height = m.itemViewers.boundingRect().height
        m.viewsRect.width = m.itemViewers.boundingRect().width + 6
        m.timestampLabel.text = m.top.itemContent.relativePublishDate
        m.timestampRect.height = m.timestampLabel.boundingRect().height
        m.timestampRect.width = m.timestampLabel.boundingRect().width + 6
    catch e
    end try
    m.itemposter.uri = m.top.itemContent.previewImageURL
    m.itemSubtitle.text = joinSubtitle(m.top.itemContent.streamerDisplayName, m.top.itemContent.gameDisplayName)
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub UserSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.circlePoster = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.visible = false
    m.circlePoster.uri = m.top.itemContent.streamerProfileImageUrl
    m.circlePoster.visible = true
    m.itemlabel.maxwidth = 150
    m.itemlabel.translation = [0, 160]
    m.itemSubtitle.translation = [0, 188]
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.followerDisplay
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub onGetFocus()
    if m.disposed then return
    if m.top.itemHasFocus
        if m.itemLabel.localBoundingRect().width > m.itemLabel.maxWidth
            m.itemLabel.repeatCount = -1
        end if
    else
        m.itemLabel.repeatCount = 0
    end if
end sub

sub showrowfocus()
    if m.disposed then return
    m.itemmask.opacity = 0.75 - (m.top.rowFocusPercent * 0.75)
end sub

sub onDestroy()
    if m.disposed then return
    m.disposed = true
    if m.itemlabel <> invalid then m.itemlabel.callFunc("onDestroy")
end sub
