' Read-only local history input; actual rail/items process it.
function RW_Load() as object
    return m.global.fixtureHistory
end function

function RW_LoadRail() as object
    return RW_Load()
end function

function RW_Section() as string
    return "fixture-recently-watched"
end function

function RW_IsPinned(login as string) as boolean
    return false
end function

function RW_MaxItems() as integer
    return 12
end function
