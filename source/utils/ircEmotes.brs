function ircImageUrl(uri as dynamic) as dynamic
    if type(uri) <> "String" and type(uri) <> "roString" then return invalid
    if uri.left(2) = "//" then return "https:" + uri
    if uri.left(8) = "https://" then return uri
    return invalid
end function

' Select a format actually advertised by 7TV; static PNG works on older Roku devices.
function irc7tvImage(emote as dynamic) as dynamic
    host = emote?.data?.host
    if host?.files = invalid then return invalid
    base = ircImageUrl(host.url)
    if base = invalid then return invalid
    fallback = invalid
    for each file in host.files
        name = file?.static_name
        if name = invalid then name = file?.name
        if name <> invalid and name.right(4) = ".png"
            if name = "1x.png" then return base + "/" + name
            if fallback = invalid then fallback = base + "/" + name
        end if
    end for
    return fallback
end function

function ircBttvImage(emote as object) as dynamic
    if emote?.id = invalid then return invalid
    imageType = emote?.imageType
    if imageType <> "gif" then imageType = "png"
    return "https://cdn.betterttv.net/emote/" + emote.id + "/1x." + imageType
end function

function ircMergeEmoteCache(current as object, fetched as object, maxEntries = 10000 as integer) as object
    for each item in fetched.items()
        uri = ircImageUrl(item.value)
        if uri <> invalid and item.key <> ""
            if current.doesExist(item.key) or current.count() < maxEntries
                current[item.key] = uri
            end if
        end if
    end for
    return current
end function
