' @include source/utils/ircEmotes.brs
sub main()
    emote = {
        data: {
            host: {
                url: "//cdn.7tv.app/emote/id", files: [
                    { name: "1x.webp", static_name: "1x.webp" },
                    { name: "2x.gif", static_name: "2x.png" },
                    { name: "1x.gif", static_name: "1x.png" }
                ]
            }
        }
    }
    if not chatEmoteAssert(irc7tvImage(emote) = "https://cdn.7tv.app/emote/id/1x.png", "7TV advertised static 1x PNG") then return
    if not chatEmoteAssert(irc7tvImage({ data: { host: { url: "//cdn.7tv.app/emote/id", files: [{ name: "1x.webp" }] } } }) = invalid, "unsupported image format") then return
    if not chatEmoteAssert(irc7tvImage(invalid) = invalid, "missing emote") then return
    if not chatEmoteAssert(ircImageUrl("//cdn.frankerfacez.com/emote/1/1") = "https://cdn.frankerfacez.com/emote/1/1", "FFZ relative protocol") then return
    if not chatEmoteAssert(ircImageUrl("javascript:invalid") = invalid, "invalid image URL") then return
    if not chatEmoteAssert(ircBttvImage({ id: "id", imageType: "gif" }) = "https://cdn.betterttv.net/emote/id/1x.gif", "BTTV animated source") then return
    if not chatEmoteAssert(ircBttvImage({ id: "id", imageType: "png" }) = "https://cdn.betterttv.net/emote/id/1x.png", "BTTV static source") then return
    merged = ircMergeEmoteCache({ Kappa: "https://twitch.example/kappa" }, { NewEmote: "https://cdn.example/new", Bad: invalid }, 2)
    if not chatEmoteAssert(merged.count() = 2 and merged.Kappa = "https://twitch.example/kappa" and merged.NewEmote = "https://cdn.example/new", "preserve IRC emotes during fetch") then return
    merged = ircMergeEmoteCache(merged, { Another: "https://cdn.example/another" }, 2)
    if not chatEmoteAssert(merged.count() = 2, "bounded emote cache") then return
    print "STITCH_TEST_PASS: chat emotes"
end sub

function chatEmoteAssert(condition as boolean, description as string) as boolean
    if not condition then print "STITCH_TEST_FAIL: chat emotes " + description
    return condition
end function
