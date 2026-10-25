sub main()
    m.checks = 0
    m.failures = 0
    fs = createObject("roFileSystem")
    state = getGlobalAA()
    state.mode = "valid"
    state.checkpoints = 0
    state.decodeIndex = 0
    state.golden = parseJson(readAsciiFile("pkg:/pillow-goldens.json"))
    state.official = true
    m.top = { stopRequested: false }
    bytes = createObject("roByteArray")
    bytes.readFile("pkg:/official.gif")
    info = chatAdmitGif(bytes)
    check(info.images.count() = 15 and info.durationMs = 990 and info.loopCount = 0, "checked metadata retains every frame/delay and infinite loop")
    runMovie(fs, bytes, "official", invalid)
    check(state.decodeIndex = 15, "all fifteen independently pinned wrappers and native stills decoded")
    state.official = false
    for each sample in parseJson(readAsciiFile("pkg:/atlas-cases.json"))
        bytes.readFile("pkg:/" + sample.name + ".gif")
        expectedLoop = -1
        if sample.name = "disposals" then expectedLoop = 0
        if sample.name = "opaque-background" then expectedLoop = 2
        check(chatAdmitGif(bytes).loopCount = expectedLoop, "actual finite/infinite/absent loop metadata: " + sample.name)
        expected = sample.expected
        if sample.engineExpected <> invalid then expected = sample.engineExpected
        runMovie(fs, bytes, sample.name, expected)
    end for
    for each mode in ["32-frames", "33-frames", "conversion-deadline", "request-deadline", "cancel-before", "cancel-during", "cancel-after-png", "wrapper-write", "wrapper-append", "wrapper-stat", "decode-invalid", "decode-size", "draw-failed", "png-write", "png-stat", "png-read", "png-corrupt", "png-admission", "delete-source", "delete-wrapper"]
        state.mode = mode
        state.official = false
        state.checkpoints = 0
        state.decodeIndex = 0
        m.top.stopRequested = mode = "cancel-before"
        source = "disposals"
        if mode = "32-frames" or mode = "33-frames" then source = mode
        bytes.readFile("pkg:/" + source + ".gif")
        path = "tmp:/stitch-emote-failure-" + mode + "/emote.gif"
        fs.createDirectory(chatAnimationDirectory(path))
        bytes.writeFile(path)
        result = invalid
        try
            result = chatConvertGif(fs, bytes, path, { totalMilliseconds: fixtureRequestTime })
        catch e
        end try
        check((result <> invalid) = (mode = "32-frames"), "bounded conversion failure/acceptance: " + mode)
        if result <> invalid then check(result.atlasWidth * result.atlasHeight = 131072 and result.frames = 32, "exact atlas/frame ceiling admitted without truncation")
        check(directoryBytes(fs, chatAnimationDirectory(path)) <= 3145728, "all partial files remain under reserved 3 MiB peak: " + mode)
        if mode = "delete-source" or mode = "delete-wrapper"
            check(fs.exists(path) or fs.exists(chatAnimationDirectory(path) + "/frame.gif"), "failed deletion retains its owned file")
        end if
        state.mode = "valid"
        check(deleteChatAnimationFile(fs, path) and not fs.exists(chatAnimationDirectory(path)), "fixed owned files cleaned after conversion failure: " + mode)
    end for
    m.top.stopRequested = false
    ' Unknown files are never deleted, even in an otherwise-owned directory.
    directory = "tmp:/stitch-emote-unknown"
    fs.createDirectory(directory)
    bytes.fromAsciiString("sentinel")
    bytes.writeFile(directory + "/keep.txt")
    check(not deleteChatAnimationFile(fs, directory + "/emote.gif") and fs.exists(directory + "/keep.txt"), "unknown file blocks cleanup acknowledgment without broad deletion")
    png = createObject("roByteArray")
    png.readFile("pkg:/rgba.png")
    check(chatGifPng(png, 2, 2), "actual RGBA PNG with signed CRC admitted")
    check(not chatGifPng(png, 1, 2), "wrong PNG dimensions rejected")
    png[40] = (png[40] + 1) mod 256
    check(not chatGifPng(png, 2, 2), "PNG CRC mutation rejected")
    if m.failures = 0 then print "__PASS_MARKER__: "; m.checks; " assertions"
end sub

sub runMovie(fs as object, bytes as object, name as string, expected as dynamic)
    state = getGlobalAA()
    state.mode = "valid"
    state.checkpoints = 0
    state.decodeIndex = 0
    path = "tmp:/stitch-emote-pixels-" + name + "/emote.gif"
    fs.createDirectory(chatAnimationDirectory(path))
    bytes.writeFile(path)
    info = chatConvertGif(fs, bytes, path, { totalMilliseconds: fixtureRequestTime })
    check(info <> invalid, "complete movie admitted: " + name)
    if info = invalid then return
    check(info.renderer = "gif-atlas" and info.sourceBytes = bytes.count() and info.bytes > 0 and info.bytes <= 525312, "separate source and retained byte admission: " + name)
    check(not fs.exists(path) and not fs.exists(chatAnimationDirectory(path) + "/frame.gif"), "input and wrapper removed before cache publication: " + name)
    ' Fresh drawn GetByteArray is deliberately never used. Export, file reload,
    ' then read decoded PNG pixels, matching the target's required validation path.
    atlas = createObject("roBitmap", info.renderPath)
    for index = 0 to info.frames - 1
        rgba = atlas.getByteArray((index mod info.columns) * info.loadWidth, int(index / info.columns) * info.loadHeight, info.loadWidth, info.loadHeight)
        normalize(rgba)
        if expected = invalid
            check(chatGifSha(rgba) = state.golden.frames[index].rgba64Sha256, "Pillow exact pixel-center tile " + index.toStr())
            previous = 0
            if index > 0 then previous = info.frameEnds[index - 1]
            check(info.frameEnds[index] - previous = state.golden.frames[index].delayMs, "exact official delay " + index.toStr())
        else
            check(lcase(rgba.toHexString()) = expected[index], "hand-authored composition/scale pixels " + name + ":" + index.toStr())
            if lcase(rgba.toHexString()) <> expected[index] then print "PIXELS "; name; index; " actual="; rgba.toHexString().left(128); " expected="; expected[index].left(128)
        end if
    end for
    if info.frames < info.columns * int(info.atlasHeight / info.loadHeight)
        rgba = atlas.getByteArray((info.frames mod info.columns) * info.loadWidth, int(info.frames / info.columns) * info.loadHeight, info.loadWidth, info.loadHeight)
        check(rgba.toHexString() = string(rgba.count() * 2, "0"), "unused atlas tile is transparent black: " + name)
    end if
    atlas = invalid
    check(deleteChatAnimationFile(fs, path) and not fs.exists(chatAnimationDirectory(path)), "atlas deleted through sentinel ownership: " + name)
end sub

function directoryBytes(fs as object, directory as string) as integer
    total = 0
    for each name in ["emote.gif", "frame.gif", "atlas.png"]
        stat = fs.stat(directory + "/" + name)
        if stat <> invalid
            if GetInterface(stat.size, "ifInt") <> invalid then total += stat.size
        end if
    end for
    return total
end function

sub normalize(bytes as object)
    for offset = 0 to bytes.count() - 1 step 4
        if bytes[offset + 3] = 0
            bytes[offset] = 0
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
        end if
    end for
end sub

' Native still GIF and GPU scaling are offline boundaries. The engine's real
' still decoder is checked against independent Pillow full-frame hashes here.
function fixtureDecode(path as string) as dynamic
    state = getGlobalAA()
    if state.mode = "decode-invalid" then return invalid
    if state.mode = "decode-size" then return createObject("roBitmap", { width: 1, height: 1, AlphaEnable: false })
    if state.official
        wrapper = createObject("roByteArray")
        wrapper.readFile(path)
        golden = state.golden.frames[state.decodeIndex]
        check(wrapper.count() = golden.wrapperBytes and chatGifSha(wrapper) = golden.wrapperSha256, "exact independent still wrapper bytes " + state.decodeIndex.toStr())
    end if
    bitmap = createObject("roBitmap", path)
    if state.official and bitmap <> invalid
        rgba = bitmap.getByteArray(0, 0, bitmap.getWidth(), bitmap.getHeight())
        normalize(rgba)
        check(chatGifSha(rgba) = golden.decodedSha256, "Pillow full native-boundary decode " + state.decodeIndex.toStr())
    end if
    state.decodeIndex++
    return fixtureWrap(bitmap)
end function

function fixtureGifClock() as object
    return { totalMilliseconds: fixtureGifTime, mark: fixtureNothing }
end function
function fixtureGifTime() as integer
    if getGlobalAA().mode = "conversion-deadline" and getGlobalAA().decodeIndex >= 2 then return 2000
    return 25
end function
function fixtureRequestTime() as integer
    if getGlobalAA().mode = "request-deadline" and getGlobalAA().decodeIndex >= 1 then return 8000
    return 0
end function
sub fixtureNothing()
end sub
sub fixtureCheckpoint()
    state = getGlobalAA()
    state.checkpoints++
    if state.mode = "cancel-during" and state.decodeIndex = 2 then m.top.stopRequested = true
end sub

function fixtureWrite(bytes as object, path as string) as boolean
    if getGlobalAA().mode = "wrapper-write" then return false
    return bytes.writeFile(path)
end function
function fixtureAppend(bytes as object, path as string, start as integer, size as integer) as boolean
    if getGlobalAA().mode = "wrapper-append" then return false
    return bytes.appendFile(path, start, size)
end function
function fixturePngWrite(bytes as object, path as string) as boolean
    state = getGlobalAA()
    if state.mode = "png-write" then return false
    result = bytes.writeFile(path)
    if state.mode = "cancel-after-png" then m.top.stopRequested = true
    if state.mode = "png-corrupt"
        broken = createObject("roByteArray")
        broken.fromAsciiString(string(bytes.count(), "x"))
        broken.writeFile(path)
    end if
    return result
end function
function fixturePngRead(bytes as object, path as string, start as integer, size as integer) as boolean
    if getGlobalAA().mode = "png-read" then return false
    return bytes.readFile(path, start, size)
end function
function fixtureAtlasStat(fs as object, path as string) as dynamic
    mode = getGlobalAA().mode
    if (mode = "wrapper-stat" and path.right(9) = "frame.gif") or (mode = "png-stat" and path.right(9) = "atlas.png") then return { size: "not numeric" }
    return fs.stat(path)
end function
function fixtureDelete(fs as object, path as string) as boolean
    mode = getGlobalAA().mode
    if mode = "delete-source" and path.right(9) = "emote.gif" then return false
    if mode = "delete-wrapper" and path.right(9) = "frame.gif" then return false
    return fs.delete(path)
end function
sub check(ok as boolean, label as string)
    m.checks++
    if not ok
        m.failures++
        print "STITCH_TEST_FAIL: " + label
    end if
end sub
