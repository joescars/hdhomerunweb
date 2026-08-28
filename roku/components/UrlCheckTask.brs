' UrlCheckTask - lightweight connectivity probe, run on a background Task
' thread (never the render thread, per SceneGraph rules).
'
' A successful probe only proves the server is reachable: it issues a single
' GET to the server root and reports any HTTP response (2xx/3xx/4xx/5xx) as
' "connected". A code of 0 means the connection itself failed (DNS, refused,
' or timed out).

sub init()
    m.top.functionName = "doCheck"
end sub

sub doCheck()
    base = m.top.serverUrl
    if base = invalid or base = ""
        m.top.result = { success: false, code: 0, error: "No server URL" }
        return
    end if

    resp = Net_HttpGet(base + "/", 8000)
    connected = (resp.code <> 0)
    m.top.result = { success: connected, code: resp.code, error: resp.error }
end sub
