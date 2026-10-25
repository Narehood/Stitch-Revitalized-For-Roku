' Test boundary enforces OS 16 source immutability while forwarding the actual
' pixel operations to engine bitmaps. It retains IDs, never old bitmap sources.
function fixtureBitmap(properties as dynamic) as object
    return fixtureWrap(createObject("roBitmap", properties))
end function
function fixtureWrap(bitmap as object) as object
    state = getGlobalAA()
    if state.bitmapSerial = invalid then state.bitmapSerial = 0
    if state.frozenIds = invalid then state.frozenIds = ""
    state.bitmapSerial++
    return { bitmap: bitmap, id: state.bitmapSerial.toStr(), getWidth: fixtureWidth, getHeight: fixtureHeight, clear: fixtureClear, drawObject: fixtureCopy, drawScaledObject: fixtureScale, setAlphaEnable: fixtureAlpha, finish: fixtureFinish, getPng: fixtureGetPng }
end function
sub fixtureWritable(id as string)
    if getGlobalAA().frozenIds.instr("|" + id + "|") >= 0 then throw "source bitmap mutated after draw"
end sub
sub fixtureFrozen(id as string)
    state = getGlobalAA()
    state.frozenIds += "|" + id + "|"
end sub
function fixtureWidth() as integer
    return m.bitmap.getWidth()
end function
function fixtureHeight() as integer
    return m.bitmap.getHeight()
end function
sub fixtureClear(color as integer)
    fixtureWritable(m.id)
    m.bitmap.clear(color)
end sub
function fixtureCopy(x as integer, y as integer, source as object) as boolean
    fixtureWritable(m.id)
    result = m.bitmap.drawObject(x, y, source.bitmap)
    fixtureFrozen(source.id)
    return result
end function
function fixtureScale(x as integer, y as integer, scaleX as float, scaleY as float, source as object) as boolean
    fixtureWritable(m.id)
    result = m.bitmap.drawScaledObject(x, y, scaleX, scaleY, source.bitmap)
    fixtureFrozen(source.id)
    return result
end function
sub fixtureAlpha(enabled as boolean)
    m.bitmap.setAlphaEnable(enabled)
end sub
sub fixtureFinish()
    m.bitmap.finish()
end sub
function fixtureGetPng(x as integer, y as integer, width as integer, height as integer) as object
    return m.bitmap.getPng(x, y, width, height)
end function
