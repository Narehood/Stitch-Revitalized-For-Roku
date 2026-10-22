' Actual Chat moderation handling: retained identity, displayed deletion, user
' purge, room clear, in-flight ordering, the bounded window and teardown. The
' ChatJob boundary has the production interface without a socket; comments and
' moderation events come from the production IRC parser.
sub main()
    m.assertions = 0
    m.failures = 0
    m.port = createObject("roMessagePort")
    m.screen = createObject("roSGScreen")
    m.screen.setMessagePort(m.port)
    m.global = m.screen.getGlobalNode()
    setConstants()
    m.global.addFields({ emoteCache: {} })
    scene = m.screen.createScene("ModerationHost")
    m.screen.show()
    m.log = []

    chat = createObject("roSGNode", "Chat")
    scene.appendChild(chat)
    chat.channel = "canned"
    waitUntil(chat, "job", true, "chat job starts")
    job = chat.callFunc("fixtureJob")
    if job = invalid
        fail("chat job is unavailable")
        finish()
        return
    end if

    ' Every comment is rendered with the identity later moderation needs.
    deliver(job, privmsg("a1", "101", "alice", "first"), 0)
    deliver(job, privmsg("b2", "202", "bob", "spam"), 0)
    deliver(job, privmsg("c3", "303", "carol", "keep"), 0)
    deliver(job, privmsg("d4", "202", "bob", "again"), 0)
    deliver(job, "@display-name=erin;id=e5 :erin!erin@erin.tmi.twitch.tv PRIVMSG #canned :tagless" + chr(13) + chr(10), 0)
    before = rows(chat)
    check(ids(before) = "a1,b2,c3,d4,e5", "every delivered comment is displayed")
    if before.count() = 5
        check(before[1].userId = "202" and before[1].login = "bob" and before[4].userId = "" and before[4].login = "erin", "displayed messages retain sender ID and login")
        check(before[0].advance > 0 and before[4].y > before[0].y, "displayed messages are stacked oldest first")
    end if

    ' A displayed deletion removes only its message; older ones close the gap.
    moderate(chat, job, "@login=bob;target-msg-id=b2 :tmi.twitch.tv CLEARMSG #canned :spam")
    after = rows(chat)
    check(ids(after) = "a1,c3,d4,e5", "a deleted displayed message is removed")
    if before.count() = 5 and after.count() = 4
        check(near(after[0].y, before[0].y + before[1].advance), "an older message moves down into the removed space")
        check(near(after[1].y, before[2].y) and near(after[3].y, before[4].y), "newer messages keep their place")
    end if

    moderate(chat, job, "@login=x;target-msg-id=ffff-unknown :tmi.twitch.tv CLEARMSG #canned :gone")
    unchanged = rows(chat)
    check(ids(unchanged) = "a1,c3,d4,e5", "an unknown message ID removes nothing")
    if unchanged.count() = 4 and after.count() = 4 then check(near(unchanged[0].y, after[0].y), "an unknown message ID moves nothing")

    ' A purge removes the user's earlier messages by ID, or by login without one.
    moderate(chat, job, "@ban-duration=60;target-user-id=202 :tmi.twitch.tv CLEARCHAT #canned :bob")
    check(ids(rows(chat)) = "a1,c3,e5", "a user purge removes every displayed message by that user")
    moderate(chat, job, ":tmi.twitch.tv CLEARCHAT #canned :erin")
    check(ids(rows(chat)) = "a1,c3", "a purge falls back to login for messages without a user ID")
    deliver(job, privmsg("f6", "202", "bob", "after timeout"), 4)
    check(ids(rows(chat)) = "a1,c3,f6", "a message after the purge is displayed")

    ' Moderation can reach the renderer before an in-flight comment it covers.
    publish(job, "@target-msg-id=g7 :tmi.twitch.tv CLEARMSG #canned :x")
    deliver(job, privmsg("g7", "404", "dave", "deleted in flight"), 4)
    check(ids(rows(chat)) = "a1,c3,f6", "an in-flight comment deleted after delivery is never displayed")
    deliver(job, privmsg("h8", "404", "dave", "other"), 4)
    check(ids(rows(chat)) = "a1,c3,f6,h8", "an in-flight deletion withholds only its own message")
    publish(job, "@target-user-id=303 :tmi.twitch.tv CLEARCHAT #canned :carol")
    deliver(job, privmsg("i9", "303", "carol", "purged in flight"), 5)
    deliver(job, privmsg("j10", "303", "carol", "after purge"), 6)
    check(ids(rows(chat)) = "a1,f6,h8,j10", "an in-flight purge withholds earlier messages and keeps later ones")
    check(chat.callFunc("fixtureRead").seq = 6, "every published event is applied once")

    ' Events lost before the bounded window fail closed.
    job.moderation = { seq: 41, events: [event(40, "message", "zz1"), event(41, "message", "zz2")] }
    waitUntil(chat, "seq", 41, "gap window applied")
    check(rows(chat).count() = 0, "a gap before the published window clears displayed messages")
    deliver(job, privmsg("k11", "505", "frank", "too old to verify"), 30)
    check(rows(chat).count() = 0, "an in-flight comment older than the window is withheld")
    deliver(job, privmsg("l12", "505", "frank", "verified"), 41)
    check(ids(rows(chat)) = "l12", "a comment covered by the window is displayed")

    ' A room clear removes everything and resets the layout.
    m.log = [event(41, "message", "zz2")]
    moderate(chat, job, "@room-id=1 :tmi.twitch.tv CLEARCHAT #canned")
    state = chat.callFunc("fixtureRead")
    check(state.rows.count() = 0 and near(state.translation, state.start), "a room clear removes every message and resets the layout")
    deliver(job, privmsg("m13", "606", "gina", "after clear"), 42)
    check(ids(rows(chat)) = "m13", "a message after a room clear is displayed")

    ' Stopping the job releases its moderation observer.
    chat.visible = false
    waitUntil(chat, "job", false, "chat job stops")
    job.moderation = { seq: 43, events: [event(43, "room", "")] }
    job.nextCommentObj = withIdentity(privmsg("n14", "606", "gina", "stale"), 43)
    settle(300)
    check(ids(rows(chat)) = "m13" and chat.callFunc("fixtureRead").seq = 42, "a stopped job can no longer remove or add messages")

    ' A restarted job numbers its events from one again.
    chat.visible = true
    waitUntil(chat, "job", true, "chat job restarts")
    nextJob = chat.callFunc("fixtureJob")
    m.log = []
    moderate(chat, nextJob, "@target-msg-id=m13 :tmi.twitch.tv CLEARMSG #canned :x")
    check(rows(chat).count() = 0, "a restarted job's first event is applied")
    deliver(nextJob, privmsg("o15", "707", "hana", "last"), 1)
    chat.callFunc("onDestroy")
    nextJob.moderation = { seq: 2, events: [event(1, "message", "m13"), event(2, "room", "")] }
    settle(300)
    check(ids(rows(chat)) = "o15" and not chat.callFunc("fixtureRead").job, "disposal releases the moderation observer")
    scene.removeChild(chat)
    finish()
end sub

function privmsg(id as string, userId as string, login as string, text as string) as string
    return "@display-name=" + login + ";id=" + id + ";user-id=" + userId + " :" + login + "!" + login + "@" + login + ".tmi.twitch.tv PRIVMSG #canned :" + text + chr(13) + chr(10)
end function

' The comment exactly as the transport delivers it.
function withIdentity(line as string, seq as integer) as object
    comment = ircParseMessage(line)
    comment.identity = ircMessageIdentity(comment)
    comment.moderationSeq = seq
    return comment
end function

' Waits for Chat.onNewCommentObj to finish its ready handshake.
sub deliver(job as object, line as string, seq as integer)
    job.readyForNextComment = false
    job.nextCommentObj = withIdentity(line, seq)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if job.readyForNextComment then return
        pump(20)
    end while
    fail("timed out rendering a comment")
end sub

function event(seq as integer, kind as string, id as string) as object
    return { seq: seq, kind: kind, id: id, userId: "", login: "" }
end function

' Publishes the transport's bounded window shape for one parsed notice.
sub publish(job as object, line as string)
    parsed = ircModerationEvent(ircParseMessage(line))
    if parsed = invalid
        fail("fixture notice did not parse")
        return
    end if
    seq = 1
    if m.log.count() > 0 then seq = m.log[m.log.count() - 1].seq + 1
    parsed.seq = seq
    m.log.push(parsed)
    if m.log.count() > 32 then m.log.shift()
    job.moderation = { seq: seq, events: m.log }
end sub

sub moderate(chat as object, job as object, line as string)
    publish(job, line)
    waitUntil(chat, "seq", m.log[m.log.count() - 1].seq, "moderation applied")
end sub

function rows(chat as object) as object
    return chat.callFunc("fixtureRead").rows
end function

function ids(list as object) as string
    result = []
    for each row in list
        result.push(row.id)
    end for
    return result.join(",")
end function

function near(a as float, b as float) as boolean
    return abs(a - b) < 0.01
end function

sub waitUntil(chat as object, key as string, value as dynamic, what as string)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < 4000
        if chat.callFunc("fixtureRead")[key] = value then return
        pump(20)
    end while
    fail("timed out waiting for " + what)
end sub

sub settle(duration as integer)
    elapsed = createObject("roTimespan")
    while elapsed.totalMilliseconds() < duration
        pump(20)
    end while
end sub

sub pump(duration as integer)
    wait(duration, m.port)
end sub

sub finish()
    m.screen.close()
    if m.failures = 0
        print "__PASS_MARKER__: "; m.assertions; " assertions"
    else
        print "STITCH_CHAT_MODERATION_FAIL:"; m.failures; " failures"
    end if
end sub

sub fail(message as string)
    m.failures += 1
    print "STITCH_CHAT_MODERATION_FAIL: " + message
end sub

sub check(condition as boolean, message as string)
    if condition
        m.assertions += 1
    else
        fail(message)
    end if
end sub
