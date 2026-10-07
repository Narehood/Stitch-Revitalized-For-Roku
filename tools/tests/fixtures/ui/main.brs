sub main()
    m.assertions = 0
    m.failures = 0
    m.fixturePort = createObject("roMessagePort")
    screen = createObject("roSGScreen")
    screen.setMessagePort(m.fixturePort)
    scene = screen.createScene("FixtureScene")
    screen.show()
    fixtureGlobal = screen.getGlobalNode()
    testFollowing(scene, fixtureGlobal)
    testBrowse(scene)
    testDetailPages(scene)
    testRoute(scene)
    testSearch(scene)
    testMenu(scene, fixtureGlobal)
    testRail(scene, fixtureGlobal)
    screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_UI_FAIL:"; m.failures; " failures; "; m.assertions; " assertions"
    end if
end sub

sub testFollowing(scene as object, fixtureGlobal as object)
    page = addPage(scene, "Following")
    s = inspect(page)
    check(s.status.state = "loading" and s.task.request.type = "getFollowingPageQuery", "anonymous Following starts loading")
    check(page.findNode("anonymousHint").visible, "anonymous Following keeps its recommendation hint")
    s.task.response = invalid
    s = inspect(page)
    check(s.status.state = "error" and s.status.actions.count() = 1, "Following invalid response offers Retry")
    old = s.task
    selectAction(s, 0)
    s = inspect(page)
    check(not old.isSameNode(s.task) and old.control = "stop" and s.status.state = "loading", "Following Retry replaces and stops the old task")
    current = s.task
    old.response = { shelves: [] }
    s = inspect(page)
    check(s.status.state = "loading" and current.isSameNode(s.task), "removed Following observer suppresses a stale response")
    s.task.response = { shelves: [] }
    s = inspect(page)
    check(s.status.state = "empty" and s.status.actions.count() = 2, "anonymous Following valid-empty differs from failure")
    s.status.setFocus(true)
    check(s.status.findNode("buttons").isInFocusChain(), "real StatusPanel actions receive child focus")
    menu = addMenu(scene)
    menu.findNode("MenuOptions").setFocus(true)
    check(menu.isInFocusChain() and not s.status.isInFocusChain(), "page actions release focus to the actual MenuBar")
    check(not s.rowlist.drawFocusFeedback, "actionable page keeps row feedback hidden when menu is focused")
    s.status.setFocus(true)
    fixtureGlobal.fixtureHistory = [{ login: "focus-rail", displayName: "Focus Rail", iconUrl: "pkg:/images/default_banner.png" }]
    rail = addPage(scene, "RecentlyWatchedBar")
    rail.itemHasFocus = true
    rail.setFocus(true)
    check(rail.isInFocusChain() and not s.status.isInFocusChain(), "page actions release focus to the actual recent rail")
    disposePage(scene, rail)
    fixtureGlobal.fixtureHistory = []
    s.status.setFocus(true)
    selectAction(s, 0)
    s = inspect(page)
    check(s.status.state = "loading" and not s.status.hasActions and s.rowlist.isInFocusChain(), "Retry hides actions and moves focus to sibling content")
    pending = s.task
    selectAction(s, 0)
    check(pending.isSameNode(inspect(page).task), "hidden loading action cannot create a duplicate task")
    s.task.response = { shelves: [] }
    s = inspect(page)
    selectAction(s, 9)
    check(page.menuRequest = "", "out-of-range action cannot navigate")
    selectAction(s, 1)
    check(page.menuRequest = "Browse", "child Go to Browse maps to the actual navigation field")
    old = s.task
    page.callFunc("fixtureCleanup")
    page.callFunc("fixtureCleanup")
    selectAction(s, 0)
    old.response = invalid
    check(inspect(page).task = invalid and old.control = "stop" and inspect(page).disposed, "Following disposal stops tasks and suppresses child/stale callbacks")
    disposePage(scene, menu)
    disposePage(scene, page)

    fixtureGlobal.fixtureSigned = true
    page = addPage(scene, "Following")
    s = inspect(page)
    check(s.signedIn and not page.findNode("anonymousHint").visible, "signed-in Following omits anonymous guidance")
    s.task.response = { liveFollows: [], offlineFollows: [] }
    s = inspect(page)
    check(s.status.state = "empty" and s.status.actions.count() = 1 and s.status.actions[0] = "Go to Browse", "zero followed channels offers Browse")
    s.task.response = { liveFollows: [], offlineFollows: [cardFields("USER", "offline-one")] }
    s = inspect(page)
    check(s.status.state = "hidden" and s.rowlist.content.getChildCount() = 1, "offline-only follows remain usable content")
    check(instr(0, s.rowlist.content.getChild(0).title, "No one you follow is live") > 0, "offline-only follows have meaningful row copy")
    s.rowlist.setFocus(true)
    check(s.rowlist.isInFocusChain() and s.rowlist.drawFocusFeedback, "loaded Following shows feedback for actual row focus")
    menu = addMenu(scene)
    menu.findNode("MenuOptions").setFocus(true)
    check(menu.isInFocusChain() and not s.rowlist.isInFocusChain() and not s.rowlist.drawFocusFeedback, "loaded Following releases focus and feedback to MenuBar")
    disposePage(scene, menu)
    disposePage(scene, page)
    fixtureGlobal.fixtureSigned = false
end sub

sub testBrowse(scene as object)
    page = addPage(scene, "Browse")
    s = inspect(page)
    check(s.status.state = "loading" and s.featured <> invalid and s.categories <> invalid and s.live <> invalid, "Browse launches a finite section set")
    s.featured.response = invalid
    s = inspect(page)
    check(s.status.state = "loading" and s.failed = 1, "Browse waits for pending siblings after one failure")
    s.live.response = { streams: [cardFields("LIVE", "live-one")], hasNextPage: true, cursor: "live-cursor" }
    s = inspect(page)
    row = s.rowlist.content.getChild(0)
    check(s.status.state = "hidden" and s.rowlist.visible and row.getChild(0).streamerLogin = "live-one", "Browse partial success is usable before all siblings settle")
    s.categories.response = invalid
    s = inspect(page)
    check(s.status.state = "hidden" and s.rowlist.content.getChild(0).isSameNode(row), "Browse sibling failures preserve loaded row identity")
    page.callFunc("fixtureMore")
    s = inspect(page)
    pending = s.live
    check(s.liveBuffering and pending.request.cursor = "live-cursor", "Browse pagination sends the current cursor")
    page.callFunc("fixtureMore")
    check(pending.isSameNode(inspect(page).live), "Browse suppresses duplicate pending pagination")
    pending.response = invalid
    s = inspect(page)
    check(not s.liveBuffering and s.status.state = "hidden" and s.rowlist.content.getChild(0).isSameNode(row), "failed pagination preserves existing content and clears pending")
    page.callFunc("fixtureMore")
    s = inspect(page)
    check(not pending.isSameNode(s.live) and pending.control = "stop", "Browse permits a finite explicit pagination retry")
    s.live.response = { streams: [cardFields("LIVE", "live-two")], hasNextPage: false, cursor: "" }
    s = inspect(page)
    check(s.rowlist.content.getChildCount() = 2 and s.rowlist.content.getChild(1).getChild(0).streamerLogin = "live-two", "later Browse success appends real native content")
    check(s.rowlist.rowItemSize.count() = s.rowlist.content.getChildCount() and s.rowlist.rowHeights.count() = s.rowlist.content.getChildCount(), "Browse row metadata stays aligned after append")
    disposePage(scene, page)

    page = addPage(scene, "Browse")
    s = inspect(page)
    s.featured.response = { shelves: [] }
    s.categories.response = { games: [], hasNextPage: false, cursor: "" }
    s.live.response = { streams: [], hasNextPage: false, cursor: "" }
    s = inspect(page)
    check(s.status.state = "empty" and s.failed = 0, "Browse all-success empty differs from error")
    oldFeatured = s.featured
    oldCategories = s.categories
    oldLive = s.live
    selectAction(s, 0)
    s = inspect(page)
    check(s.status.state = "loading" and not oldFeatured.isSameNode(s.featured) and not oldCategories.isSameNode(s.categories) and not oldLive.isSameNode(s.live), "Browse Retry replaces each section once")
    check(oldFeatured.control = "stop" and oldCategories.control = "stop" and oldLive.control = "stop", "Browse Retry stops every previous section")
    oldLive.response = { streams: [cardFields("LIVE", "stale")], hasNextPage: false, cursor: "" }
    check(inspect(page).status.state = "loading" and inspect(page).rowlist.content = invalid, "old Browse response cannot overwrite retry state")
    s.featured.response = invalid
    s.categories.response = invalid
    s.live.response = invalid
    s = inspect(page)
    check(s.status.state = "error" and s.failed = 3 and s.status.actions.count() = 1, "Browse all-invalid offers explicit Retry")
    selectAction(s, 0)
    s = inspect(page)
    pause(150)
    check(s.featured.isSameNode(inspect(page).featured), "Browse does not automatically retry pending loading")
    old = s.live
    page.callFunc("fixtureCleanup")
    old.response = invalid
    check(inspect(page).disposed and inspect(page).live = invalid and old.control = "stop", "Browse disposal removes pending observers and stops tasks")
    disposePage(scene, page)
end sub

sub testDetailPages(scene as object)
    for each name in ["GamePage", "ChannelPage"]
        page = addPage(scene, name)
        content = createObject("roSGNode", "TwitchContentNode")
        content.contentType = "LIVE"
        content.streamerLogin = "fixture-channel"
        content.streamerDisplayName = "Fixture Channel"
        content.gameName = "Fixture Game"
        page.contentRequested = content
        s = inspect(page)
        check(s.task <> invalid and s.status.state = "loading", name + " loads requested content")
        s.task.response = invalid
        s = inspect(page)
        check(s.status.state = "error" and s.status.actions.count() = 2, name + " failure offers Retry and Back")
        old = s.task
        selectAction(s, 0)
        s = inspect(page)
        check(not old.isSameNode(s.task) and old.control = "stop" and s.status.state = "loading", name + " Retry replaces a stopped task")
        if name = "GamePage"
            s.task.response = { edges: [] }
        else
            s.task.response = { isLive: false, videoShelves: [], description: "fixture", followerCount: 2 }
        end if
        s = inspect(page)
        check(s.status.state = "empty" and s.status.actions.count() = 1 and s.status.actions[0] = "Back", name + " valid-empty offers Back without claiming failure")
        selectAction(s, 0)
        check(page.backPressed, name + " child Back emits navigation")
        if name = "GamePage"
            edges = []
            for i = 0 to 6
                edges.push({ node: { id: i.toStr(), viewersCount: i, broadcaster: { login: "game-" + i.toStr(), displayName: "Game " + i.toStr(), id: i.toStr(), broadcastSettings: { title: "Stream" } } } })
            end for
            edges.unshift(invalid)
            edges.push({ node: { broadcaster: { login: "" } } })
            s.task.response = { edges: edges }
            s = inspect(page)
            check(s.status.state = "hidden" and s.rowlist.content.getChildCount() = 3, "Game handler retains valid streams and skips malformed entries")
            check(s.rowlist.content.getChild(0).getChildCount() = 3 and s.rowlist.content.getChild(1).getChildCount() = 3 and s.rowlist.content.getChild(2).getChildCount() = 1, "Game trailing partial row preserves all seven streams as 3/3/1")
        else
            s.task.response = { isLive: true, videoShelves: [], description: "fixture", followerCount: 2 }
            s = inspect(page)
            check(s.status.state = "hidden" and s.rowlist.content.getChild(0).getChild(0).isSameNode(content), "Channel success exposes the requested live card identity")
        end if
        old = s.task
        shell = s.shell
        page.callFunc("fixtureCleanup")
        page.callFunc("fixtureCleanup")
        s = inspect(page)
        check(s.task = invalid and old.control = "stop" and s.disposed, name + " cleanup is idempotent and stops task")
        if name = "ChannelPage" then check(s.shell = invalid and shell.control = "stop", "Channel cleanup stops its independent profile task")
        old.response = invalid
        check(s.status.state = "hidden", name + " disposed response cannot restore error status")
        disposePage(scene, page)
    end for
end sub

sub testRoute(scene as object)
    route = scene.callFunc("fixtureRoute")
    check(route.after.id = "Browse" and route.active = "Browse" and route.focus = "Browse", "Following child Browse action executes actual hero navigation and menu state")
    check(route.before.callFunc("fixtureRead").disposed and route.task.control = "stop", "hero routing disposes the departing page")
    check(route.afterStale.isSameNode(route.after), "disposed Following menuRequest cannot reroute the active page")
end sub

sub testSearch(scene as object)
    page = addPage(scene, "Search")
    s = inspect(page)
    s.kb.text = "alpha"
    pause(350)
    s.kb.text = "beta"
    pause(300)
    check(inspect(page).task = invalid, "Search restarts its actual half-second debounce after an edit")
    s = waitForSearch(page)
    check(s.task <> invalid and s.task.request.query = "beta", "Search requests only final text after the Timer fires")
    old = s.task
    s.kb.text = "gamma"
    old.response = { channels: [], games: [], videos: [] }
    s = inspect(page)
    check(s.task = invalid and old.control = "stop" and instr(0, s.status.text, "gamma") > 0, "superseded Search response cannot replace current text status")
    s = waitForSearch(page)
    s.task.response = { channels: [], games: [], videos: [] }
    s = inspect(page)
    check(instr(0, s.status.text, "No results") > 0 and not s.rowlist.visible, "Search valid-empty shows no-results guidance")
    s.kb.text = "delta"
    s = waitForSearch(page)
    s.task.response = invalid
    s = inspect(page)
    check(instr(0, s.status.text, "isn't working") > 0 and not s.rowlist.visible, "Search invalid response shows connection failure")
    s.kb.text = ""
    s = inspect(page)
    check(not s.status.visible and s.timer.control = "stop" and s.task = invalid, "cleared Search cancels Timer/task and hides status")
    s.kb.setFocus(true)
    check(page.callFunc("fixtureKey", "back", true) and page.backPressed, "Search keyboard Back emits navigation")
    s.kb.text = "cleanup"
    s = waitForSearch(page)
    old = s.task
    page.callFunc("fixtureCleanup")
    s = inspect(page)
    check(s.disposed and s.task = invalid and old.control = "stop" and s.timer.control = "stop", "Search cleanup stops request and debounce")
    s.kb.text = "should-not-request"
    old.response = { channels: [], games: [], videos: [] }
    pause(600)
    check(inspect(page).task = invalid, "disposed Search text/response observers cannot launch another request")
    disposePage(scene, page)
end sub

sub testMenu(scene as object, fixtureGlobal as object)
    menu = addMenu(scene)
    s = inspect(menu)
    menu.activeItem = "Browse"
    colorProbe = createObject("roSGNode", "Label")
    colorProbe.color = fixtureGlobal.constants.ui.color.text
    check(s.tabs.getChild(1).textColor = colorProbe.color, "active MenuBar tab uses actual primary color token")
    colorProbe.color = fixtureGlobal.constants.ui.color.textSecondary
    check(s.tabs.getChild(0).textColor = colorProbe.color, "inactive MenuBar tab uses actual secondary color token")
    menu.focusItem = "Browse"
    check(s.tabs.focusButton = 1 and menu.buttonSelected = -1, "MenuBar focusItem moves focus marker without selection")
    s.tabs.buttonSelected = 2
    check(menu.buttonSelected = 2, "actual tab selection bridges the flat index")
    s.icons.buttonSelected = 1
    check(menu.buttonSelected = 5, "actual icon selection bridges after text tabs")
    s.icons.setFocus(true)
    s.icons.buttonFocused = 0
    check(s.caption.visible and s.label.text = "Search", "focused Search icon shows its caption")
    s.icons.buttonFocused = 1
    check(s.label.text = "Settings", "focused Settings icon updates its caption")
    s.icons.buttonFocused = 2
    check(s.label.text = "Sign in", "anonymous account icon says Sign in")
    fixtureGlobal.fixtureSigned = true
    s.icons.buttonFocused = 1
    s.icons.buttonFocused = 2
    check(s.label.text = "Fixture Viewer", "signed-in account caption uses the supplied display name")
    s.tabs.setFocus(true)
    check(not s.caption.visible, "leaving icon focus hides the menu caption")
    oldColor = s.tabs.getChild(0).textColor
    menu.callFunc("fixtureCleanup")
    menu.activeItem = "Following"
    s.icons.buttonSelected = 0
    check(inspect(menu).disposed and s.tabs.getChild(0).textColor = oldColor and menu.buttonSelected = 5, "MenuBar disposal removes color and child selection observers")
    disposePage(scene, menu)
    fixtureGlobal.fixtureSigned = false
end sub

sub testRail(scene as object, fixtureGlobal as object)
    history = []
    for i = 0 to 9
        history.push({ login: "rail-" + i.toStr(), displayName: "Rail " + i.toStr(), iconUrl: "pkg:/images/default_banner.png" })
    end for
    fixtureGlobal.fixtureHistory = history
    rail = addPage(scene, "RecentlyWatchedBar")
    s = inspect(rail)
    check(rail.hasItems and s.items.count() = 10 and not s.caption.visible, "actual rail builds supplied history without invisible initial focus")
    rail.itemHasFocus = true
    check(s.caption.visible and s.label.text = "Rail 0" and s.items[0].focused, "entering actual rail reveals focused channel name")
    s.task.response = { "rail-0": true }
    check(s.items[0].isLive and s.label.text = "Rail 0 · LIVE", "rail status response adds LIVE to focused caption")
    oldItems = s.items
    rail.callFunc("fixtureRefresh")
    check(oldItems[0].isSameNode(inspect(rail).items[0]), "rail refresh preserves focused item identity")
    check(rail.callFunc("fixtureKey", "down", true), "rail Down consumes navigation")
    s = inspect(rail)
    check(s.index = 1 and s.label.text = "Rail 1" and s.items[1].focused and not s.items[0].focused, "rail Down updates focus and caption together")
    for i = 0 to 7
        rail.callFunc("fixtureKey", "down", true)
    end for
    s = inspect(rail)
    check(s.index = 9 and s.items[9].visible and not s.items[0].visible and s.label.text = "Rail 9", "scrolling rail keeps its focused final item visible")
    check(rail.callFunc("fixtureKey", "down", true) and inspect(rail).index = 9, "rail Down remains bounded at final item")
    for i = 0 to 8
        rail.callFunc("fixtureKey", "up", true)
    end for
    check(not rail.callFunc("fixtureKey", "up", true) and inspect(rail).index = 0, "top rail Up bubbles for host navigation")
    s = inspect(rail)
    s.task.response = invalid
    check(not s.items[0].isLive and s.label.text = "Rail 0", "failed live status clears stale LIVE caption")
    check(rail.callFunc("fixtureKey", "OK", true) and rail.contentSelected.streamerLogin = "rail-0", "rail OK emits the actual selected channel")
    check(not rail.itemHasFocus and not s.caption.visible and not s.items[0].focused, "rail selection releases caption and focus marker")
    old = s.task
    timer = s.timer
    rail.callFunc("fixtureCleanup")
    rail.callFunc("fixtureCleanup")
    s = inspect(rail)
    old.response = { "rail-0": true }
    check(s.disposed and s.task = invalid and old.control = "stop" and timer.control = "stop" and s.items.count() = 0, "rail disposal stops Timer/task and releases all items")
    disposePage(scene, rail)
    fixtureGlobal.fixtureHistory = []
    rail = addPage(scene, "RecentlyWatchedBar")
    rail.itemHasFocus = true
    s = inspect(rail)
    check(not rail.hasItems and not s.caption.visible and s.task = invalid, "empty rail has no invisible caption or request")
    check(not rail.callFunc("fixtureKey", "up", true), "empty rail Up bubbles without a hidden item")
    disposePage(scene, rail)
end sub

function addPage(scene as object, name as string) as object
    node = createObject("roSGNode", name)
    scene.appendChild(node)
    return node
end function

function addMenu(scene as object) as object
    menu = addPage(scene, "MenuBar")
    menu.menuOptionsText = ["Following", "Browse", "Live Channels", "Categories"]
    return menu
end function

function inspect(node as object) as object
    return node.callFunc("fixtureRead")
end function

sub selectAction(state as object, index as integer)
    state.status.findNode("buttons").buttonSelected = index
end sub

sub disposePage(scene as object, node as object)
    disposeNodeTree(node)
    scene.removeChild(node)
end sub

function cardFields(kind as string, login as string) as object
    return { contentType: kind, contentTitle: login, streamerLogin: login, streamerDisplayName: login, viewersCount: 4, followerCount: 2, previewImageURL: "pkg:/images/default_banner.png" }
end function

' Port events must not shorten a requested delay; the actual Timer drives Search.
sub pause(duration as integer)
    elapsed = createObject("roTimespan")
    elapsed.mark()
    while elapsed.totalMilliseconds() < duration
        wait(25, m.fixturePort)
    end while
end sub

function waitForSearch(page as object) as object
    elapsed = createObject("roTimespan")
    elapsed.mark()
    while inspect(page).task = invalid and elapsed.totalMilliseconds() < 1500
        wait(25, m.fixturePort)
    end while
    return inspect(page)
end function

sub check(condition as boolean, message as string)
    if condition
        m.assertions += 1
    else
        m.failures += 1
        print "STITCH_UI_FAIL:"; message
    end if
end sub
