' Engine boundary: brs-engine cannot compile the production Unicode emoji
' pattern, so card titles use an ASCII pattern here. EmojiLabel.brs and
' EmojiLabelUtil.brs run unchanged.
function regex() as string
    return ":\)"
end function
