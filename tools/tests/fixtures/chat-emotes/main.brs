' Executes the actual renderer and tokenizer. Only PCRE syntax is adapted by
' the Node harness: brs-engine cannot compile Roku's scalar Unicode escapes.
' These checks establish layout/URI/lifecycle behavior, not native decoding.
sub main()
    fixtureBegin()
    m.global.addFields({ fixtureRegistry: {}, emoteCache: {} })
    m.scene = m.screen.createScene("PhaseTwoHost")
    m.screen.show()
    chat = createObject("roSGNode", "Chat")
    m.scene.appendChild(chat)
    state = chat.callFunc("fixtureState")
    check(not state.compiled, "chat does not compile an emoji pattern in init")
    face = chr(&h1F600)
    heart = chr(&h2764) + chr(&hFE0F)
    family = chr(&h1F468) + chr(&h200D) + chr(&h1F469) + chr(&h200D) + chr(&h1F467) + chr(&h200D) + chr(&h1F466)
    samples = [
        { text: "hello" + face + "world", images: "1f600", plain: "helloworld " },
        { text: heart, images: "2764", plain: " " },
        { text: chr(&h1F44D) + chr(&h1F3FD), images: "1f44d-1f3fd", plain: " " },
        { text: family, images: "1f468-200d-1f469-200d-1f467-200d-1f466", plain: " " },
        { text: chr(&h1F1FA) + chr(&h1F1F8), images: "1f1fa-1f1f8", plain: " " },
        { text: "1" + chr(&hFE0F) + chr(&h20E3), images: "31-20e3", plain: " " },
        { text: face + face, images: "1f600,1f600", plain: " " },
        { text: chr(&h1FAE8) + chr(&h1FA77), images: "1fae8,1fa77", plain: " " },
        { text: "ASCII 123 #*", images: "", plain: "ASCII 123 #* " },
        { text: "caf" + chr(&hE9) + " " + chr(&h4F60) + chr(&h597D), images: "", plain: "caf" + chr(&hE9) + " " + chr(&h4F60) + chr(&h597D) + " " }
    ]
    for each sample in samples
        group = chat.callFunc("fixtureBuild", sample.text)
        check(points(group) = sample.images, "image runs and pinned URIs for " + sample.text)
        check(textOf(group) = sample.plain, "ordinary text preserved around emoji for " + sample.text)
        check(inBounds(group, state), "image/text runs fit chat bounds")
        chat.callFunc("fixturePrune", group)
    end for
    check(chat.callFunc("fixtureState").builds = 1, "all words and messages reuse one compiled full pattern")

    cache = { PETPET: "https://cdn.7tv.app/emote/01FSNK0GP000038GDBZ91HT6SQ/1x_static.webp", catJAM: "https://cdn.betterttv.net/emote/5f1b0186cf6d2144653d2970/static/1x.webp" }
    m.global.emoteCache = cache
    group = chat.callFunc("fixtureBuild", "PETPET catJAM PETPETx " + face + "catJAM")
    nodes = posters(group)
    check(nodes.count() = 3, "whole provider words become images; substrings and emoji-adjacent names stay text")
    if nodes.count() = 3
        check(nodes[0].uri = cache.PETPET and nodes[1].uri = cache.catJAM, "provider cache URLs are used verbatim")
    end if
    check(textOf(group).instr("PETPETx") >= 0 and textOf(group).instr("catJAM") >= 0, "provider lookup never replaces substrings")
    check(m.global.emoteCache.count() = 2, "emoji rendering does not modify the shared provider cache")
    chat.callFunc("fixturePrune", group)

    chat.width = 140
    state = chat.callFunc("fixtureState")
    group = chat.callFunc("fixtureBuild", "ordinary words " + string(70, "x") + face + face + " tail")
    check(inBounds(group, state), "long words, adjacent emoji and following text remain within both bounds")
    check(group.localBoundingRect().height > 60, "long message wraps onto several rows")
    check(points(group) = "1f600,1f600", "wrapping does not split emoji into missing-glyph labels")
    check(textOf(group) = "ordinary words " + string(70, "x") + " tail ", "wrapping preserves ASCII text and spaces")
    chat.callFunc("fixturePrune", group)

    ' A native emote after a non-BMP character must be cached under its entire
    ' token, not a UTF-16 slice beginning at the preceding space.
    chat.width = 275
    chat.channel = "fixture"
    state = chat.callFunc("fixtureState")
    job = state.job
    message = ircParseMessage("@id=unicode;display-name=Viewer;emotes=25:2-6 :viewer!viewer@host PRIVMSG #fixture :" + face + " Kappa")
    message.identity = { id: "unicode", userId: "1", login: "viewer" }
    message.moderationSeq = 0
    job.nextCommentObj = message
    settle(100)
    check(m.global.emoteCache.Kappa = "https://static-cdn.jtvnw.net/emoticons/v2/25/static/light/1.0", "actual renderComment consumes Twitch code-point offsets before emoji parsing")
    panel = chat.callFunc("fixtureState").panel
    nodes = posters(panel)
    check(nodes.count() = 2, "actual comment renders both Unicode and Twitch emote images")
    if nodes.count() = 2
        old = nodes[1]
        chat.callFunc("fixtureImageStatus", old, "failed")
        check(textOf(panel).instr("Kappa") >= 0 and posters(panel).count() = 1, "failed Twitch image is replaced with its readable token")
        check(inBounds(panel.getChild(0).getChild(0).getChild(3), chat.callFunc("fixtureState")), "failed-image fallback reflows within chat bounds")
    end if
    chat.callFunc("fixtureModerateRoom")
    check(panel.getChildCount() = 0, "moderation removes emoji-bearing rows")
    if nodes.count() = 2
        failedBefore = chat.callFunc("fixtureState").failed
        chat.callFunc("fixtureImageStatus", nodes[0], "failed")
        check(chat.callFunc("fixtureState").failed = failedBefore, "a removed row's late image event cannot change the cache")
    end if

    group = chat.callFunc("fixtureBuild", heart)
    nodes = posters(group)
    if nodes.count() = 1
        parent = group.getParent()
        chat.callFunc("fixtureImageStatus", nodes[0], "failed")
        replacement = parent.getChild(parent.getChildCount() - 1)
        check(textOf(replacement) = "<3 " and posters(replacement).count() = 0, "Unicode decode failure uses supported text, not Archivo missing glyphs")
        chat.callFunc("fixturePrune", replacement)
    else
        fail("heart image is unavailable before failure test")
    end if
    group = chat.callFunc("fixtureBuild", "catJAM")
    nodes = posters(group)
    if nodes.count() = 1
        chat.callFunc("fixtureImageStatus", nodes[0], "ready")
        check(posters(group).count() = 1, "ready image stays an image")
        chat.callFunc("fixturePrune", group)
    end if

    group = chat.callFunc("fixtureBuild", face)
    nodes = posters(group)
    if nodes.count() = 1
        parent = group.getParent()
        ' loadStatus is read-only. Supply the native event at the decoder boundary.
        chat.callFunc("fixtureImageStatus", nodes[0], "failed")
        replacement = parent.getChild(parent.getChildCount() - 1)
        check(textOf(replacement) = "[emoji] " and posters(replacement).count() = 0, "failed image notification uses a neutral Unicode fallback")
        chat.callFunc("fixturePrune", replacement)
    end if

    testEmojiLabel(heart, face)
    chat.callFunc("onDestroy")
    check(not chat.callFunc("fixtureState").compiled and chat.callFunc("fixtureState").failed = 0, "chat disposal releases its parser and bounded failure cache")
    m.scene.removeChild(chat)
    fixtureEnd()
end sub

sub testEmojiLabel(heart as string, face as string)
    label = createObject("roSGNode", "EmojiLabel")
    label.height = 28
    m.scene.appendChild(label)
    label.text = "love " + heart
    parts = label.callFunc("fixtureParts")
    check(parts.count() = 2 and parts[1].subtype() = "Poster", "EmojiLabel uses the shared production tokenizer")
    if parts.count() = 2
        poster = parts[1]
        check(poster.uri = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/72x72/2764.png", "EmojiLabel shares corrected VS16 URI normalization")
        label.callFunc("fixtureImageStatus", poster, "failed")
        check(textOf(label) = "love <3", "EmojiLabel image decode failure gets a supported text fallback")
    end if
    label.text = face + face
    parts = label.callFunc("fixtureParts")
    check(parts.count() = 2 and parts[0].subtype() = "Poster" and parts[1].subtype() = "Poster", "repeated text updates create separate emoji images")
    check(label.callFunc("fixtureBuilds") = 1, "EmojiLabel reuses its compiled parser")
    label.callFunc("onDestroy")
    check(label.callFunc("fixtureParts").count() = 0, "EmojiLabel disposal removes image observers and nodes")
    m.scene.removeChild(label)
end sub

function posters(node as object) as object
    result = []
    if node.subtype() = "Poster" then result.push(node)
    for each child in node.getChildren(-1, 0)
        result.append(posters(child))
    end for
    return result
end function

function points(node as object) as string
    result = []
    base = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/72x72/"
    for each poster in posters(node)
        if poster.uri.left(base.len()) <> base then return "unexpected image URI"
        result.push(poster.uri.mid(base.len()).replace(".png", ""))
    end for
    return result.join(",")
end function

function textOf(node as object) as string
    if node.subtype() = "Label" or node.subtype() = "SimpleLabel" then return node.text
    result = ""
    for each child in node.getChildren(-1, 0)
        result += textOf(child)
    end for
    return result
end function

function inBounds(group as object, state as object) as boolean
    for each node in group.getChildren(-1, 0)
        if node.translation[0] < state.left - 0.1 or node.translation[0] + node.localBoundingRect().width > state.right + 0.1 then return false
    end for
    return true
end function
