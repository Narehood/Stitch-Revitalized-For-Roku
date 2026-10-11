' Serves Twitch live playlists trimmed to their newest segments on a loopback
' port (see lowLatencyPlaylist.brs). The Video still fetches segments directly.
sub init()
    m.top.functionName = "runRelay"
end sub

sub runRelay()
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("stopRequested", m.port)
    m.state = { anchor: -1& }
    m.variants = invalid
    m.masterText = ""
    m.mediaUrl = ""
    m.lastGood = {}
    m.failures = 0
    m.listener = invalid
    try
        ' An unsupported source is refused before advertising; it plays directly.
        if relayPrepare()
            listenPort = relayListen()
            if listenPort = 0
                m.top.status = { failure: "listen_failed" }
            else
                m.top.status = { url: "http://127.0.0.1:" + listenPort.ToStr() + "/live.m3u8" }
                while not m.top.stopRequested
                    wait(1000, m.port)
                    while not m.top.stopRequested and m.listener.IsReadable()
                        connection = m.listener.Accept()
                        if connection = invalid then exit while
                        relayServe(connection)
                    end while
                end while
            end if
        end if
    catch error
        m.top.status = { failure: "relay_exception" }
    end try
    if m.listener <> invalid
        m.listener.NotifyReadable(false)
        m.listener.Close()
        m.listener = invalid
    end if
end sub

function relayPrepare() as boolean
    source = m.top.sourceUrl
    text = relayFetch(source)
    if text = invalid
        m.top.status = { failure: "source_unavailable" }
        return false
    end if
    if text.InStr("#EXT-X-STREAM-INF:") >= 0
        master = lowLatencyMaster(text, source)
        if master <> invalid
            m.variants = master.variants
            m.masterText = master.text
            return true
        end if
    else if lowLatencyMedia(text, { anchor: -1& }, m.top.startCount, m.top.maxCount) <> invalid
        m.mediaUrl = source
        return true
    end if
    m.top.status = { failure: "unsupported_playlist" }
    return false
end function

' A closed relay's port can linger briefly, so a few neighbours are tried.
function relayListen() as integer
    for listenPort = 49380 to 49389
        address = CreateObject("roSocketAddress")
        listener = CreateObject("roStreamSocket")
        if address.SetAddress("127.0.0.1:" + listenPort.ToStr()) and listener <> invalid
            listener.SetMessagePort(m.port)
            listener.SetReuseAddr(true)
            if listener.SetAddress(address)
                listener.NotifyReadable(true)
                if listener.Listen(4)
                    m.listener = listener
                    return listenPort
                end if
            end if
            listener.Close()
        end if
    end for
    return 0
end function

sub relayServe(connection as object)
    port = CreateObject("roMessagePort")
    connection.SetMessagePort(port)
    connection.NotifyReadable(true)
    request = relayReadRequest(connection, port)
    if request <> invalid
        status = "404 Not Found"
        body = invalid
        if request.path = "/live.m3u8" and m.masterText <> ""
            body = m.masterText
        else
            url = ""
            if request.path = "/live.m3u8"
                url = m.mediaUrl
            else if m.variants <> invalid and request.path.Left(3) = "/v/" and request.path.Right(5) = ".m3u8"
                index = lowLatencyNatural(request.path.Mid(3, request.path.Len() - 8))
                if index >= 0 and index < m.variants.Count() then url = m.variants[CInt(index)]
            end if
            if url <> ""
                status = "502 Bad Gateway"
                body = lowLatencyMedia(relayFetch(url), m.state, m.top.startCount, m.top.maxCount)
                ' A failed refresh can end Roku's live playback, so a brief
                ' upstream failure re-serves the last good playlist.
                if body <> invalid
                    m.lastGood[request.path] = body
                    m.failures = 0
                else if m.lastGood.DoesExist(request.path) and m.failures < 5
                    m.failures += 1
                    body = m.lastGood[request.path]
                end if
            end if
        end if
        if body = invalid
            body = ""
        else
            status = "200 OK"
        end if
        relaySend(connection, port, status, body, request.method = "HEAD")
    end if
    connection.NotifyReadable(false)
    connection.NotifyWritable(false)
    connection.Close()
end sub

function relayReadRequest(connection as object, port as object) as dynamic
    crlf = Chr(13) + Chr(10)
    text = ""
    clock = CreateObject("roTimespan")
    while not m.top.stopRequested and clock.TotalMilliseconds() < 3000
        if connection.IsReadable() or connection.GetCountRcvBuf() > 0
            chunk = connection.ReceiveStr(2048)
            if chunk = invalid or chunk = "" then return invalid
            text += chunk
            if text.InStr(crlf + crlf) >= 0
                parts = text.Left(text.InStr(crlf)).Split(" ")
                if parts.Count() <> 3 then return invalid
                if parts[0] <> "GET" and parts[0] <> "HEAD" then return invalid
                path = parts[1]
                if path.InStr("?") >= 0 then path = path.Left(path.InStr("?"))
                return { method: parts[0], path: path }
            end if
            if text.Len() > 8192 then return invalid
        else
            wait(20, port)
        end if
    end while
    return invalid
end function

sub relaySend(connection as object, port as object, status as string, body as string, headOnly as boolean)
    crlf = Chr(13) + Chr(10)
    payload = CreateObject("roByteArray")
    payload.FromAsciiString(body)
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString("HTTP/1.1 " + status + crlf + "Content-Type: application/vnd.apple.mpegurl" + crlf + "Content-Length: " + payload.Count().ToStr() + crlf + "Cache-Control: no-store" + crlf + "Connection: close" + crlf + crlf)
    if not headOnly then bytes.Append(payload)
    offset = 0
    clock = CreateObject("roTimespan")
    while offset < bytes.Count() and not m.top.stopRequested and clock.TotalMilliseconds() < 3000
        sent = 0
        if connection.IsWritable() then sent = connection.Send(bytes, offset, bytes.Count() - offset)
        if sent > 0
            offset += sent
        else
            if not connection.eOK() then return
            wait(10, port)
        end if
    end while
end sub

function relayFetch(url as string) as dynamic
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.SetHeaders({ Accept: "*/*", Origin: "https://android.tv.twitch.tv", Referer: "https://android.tv.twitch.tv/", "User-Agent": "Stitch Roku", "Client-ID": "kimne78kx3ncx6brgo4mv6wki5h1ko" })
    transfer.SetUrl(url)
    if not transfer.AsyncGetToString() then return invalid
    clock = CreateObject("roTimespan")
    while not m.top.stopRequested and clock.TotalMilliseconds() < 4000
        event = wait(100, port)
        if type(event) = "roUrlEvent"
            if event.GetInt() = 1 and event.GetResponseCode() = 200 then return event.GetString()
            return invalid
        end if
    end while
    transfer.AsyncCancel()
    return invalid
end function
