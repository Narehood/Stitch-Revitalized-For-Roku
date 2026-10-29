' EventSub raid notifications describe a completed outgoing raid, not an IRC
' USERNOTICE (which describes an incoming raid on the destination channel).
function raidString(value as dynamic, maxLength = 128 as integer) as boolean
    return GetInterface(value, "ifString") <> invalid and value <> "" and value.len() <= maxLength
end function

function raidId(value as dynamic) as boolean
    if not raidString(value, 20) then return false
    return CreateObject("roRegex", "^[0-9]+$", "").IsMatch(value)
end function

function raidSocketUrl(value as dynamic) as boolean
    if not raidString(value, 2048) then return false
    return CreateObject("roRegex", "^wss://eventsub[.]wss[.]twitch[.]tv(:443)?/[^ " + Chr(13) + Chr(10) + "]*$", "").IsMatch(value)
end function

function raidNotification(message as dynamic, sourceId as string, subscriptionId as string, nowSeconds as double) as dynamic
    if GetInterface(message, "ifAssociativeArray") = invalid then return invalid
    meta = message.metadata
    payload = message.payload
    if GetInterface(meta, "ifAssociativeArray") = invalid or GetInterface(payload, "ifAssociativeArray") = invalid then return invalid
    if meta.message_type <> "notification" or meta.subscription_type <> "channel.raid" or meta.subscription_version <> "1" then return invalid
    if not raidString(meta.message_id) or not raidString(meta.message_timestamp) then return invalid
    eventTime = CreateObject("roDateTime")
    eventTime.FromSeconds(0)
    ' Twitch uses UTC nanoseconds; freshness only needs whole seconds in Roku's supported format.
    eventTime.FromISO8601String(meta.message_timestamp.Left(19) + ".000")
    age = nowSeconds - eventTime.AsSeconds()
    if age < -30 or age > 120 then return invalid
    subscription = payload.subscription
    event = payload.event
    if GetInterface(subscription, "ifAssociativeArray") = invalid or GetInterface(event, "ifAssociativeArray") = invalid then return invalid
    if subscription.id <> subscriptionId or subscriptionId = "" or subscription.status <> "enabled" then return invalid
    if subscription.type <> "channel.raid" or subscription.version <> "1" then return invalid
    condition = subscription.condition
    if GetInterface(condition, "ifAssociativeArray") = invalid then return invalid
    if condition.from_broadcaster_user_id <> sourceId or event.from_broadcaster_user_id <> sourceId then return invalid
    if not raidId(event.to_broadcaster_user_id) or event.to_broadcaster_user_id = sourceId then return invalid
    login = event.to_broadcaster_user_login
    if not raidString(login, 25) then return invalid
    if not CreateObject("roRegex", "^[a-zA-Z0-9_]+$", "").IsMatch(login) then return invalid
    name = event.to_broadcaster_user_name
    if not raidString(name, 100) then name = login
    name = name.Replace(Chr(13), " ").Replace(Chr(10), " ")
    return { messageId: meta.message_id, sourceId: sourceId, id: event.to_broadcaster_user_id, login: LCase(login), name: name }
end function
