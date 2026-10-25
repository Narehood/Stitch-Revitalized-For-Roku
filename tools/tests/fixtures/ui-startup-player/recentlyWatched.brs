' Read-only local history input; the actual rail and items process it.
function RW_Load() as object
    return m.global.fixtureHistory
end function

function RW_LoadRail() as object
    return RW_Load()
end function

function RW_Section() as string
    return "fixture-recently-watched"
end function
