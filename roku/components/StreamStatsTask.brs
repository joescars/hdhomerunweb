' StreamStatsTask - fetches one snapshot of active stream diagnostics from the
' server for the player's troubleshooting overlay.

sub init()
    m.top.functionName = "doFetch"
end sub

sub doFetch()
    base = m.top.serverUrl
    chan = m.top.channelNumber
    codec = m.top.codec
    profile = m.top.profile

    if base = invalid or base = "" or chan = invalid or chan = "" or codec = invalid or codec = ""
        m.top.result = { success: false, error: "Missing stream context" }
        return
    end if

    if profile = invalid or profile = ""
        url = base + "/stream/" + chan + "/" + codec + "/stats"
    else
        url = base + "/stream/" + chan + "/" + codec + "/" + profile + "/stats"
    end if

    resp = Net_HttpGet(url, 4000)
    if resp.success <> true
        m.top.result = { success: false, error: "Could not read stream stats (" + resp.error + ")" }
        return
    end if

    parsed = ParseJson(resp.body)
    if parsed = invalid
        m.top.result = { success: false, error: "Invalid stream stats payload" }
        return
    end if

    m.top.result = { success: true, payload: parsed }
end sub
