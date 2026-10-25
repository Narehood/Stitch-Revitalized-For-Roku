' Local history input only. The production bar, item and CirclePoster execute.
function RW_Load() as object
    return m.global.recentRingHistory
end function

function RW_LoadRail() as object
    return RW_Load()
end function

function RW_Section() as string
    return "fixture-recently-watched"
end function
