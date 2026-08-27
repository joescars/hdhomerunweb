' GuideTask - fetches GET /api/guide on a background Task thread.
'
' All network I/O happens here, never on the render thread, per SceneGraph
' rules. Set serverUrl then control="RUN" to execute.

sub init()
    m.top.functionName = "doFetch"
end sub

sub doFetch()
    base = m.top.serverUrl
    if base = invalid or base = ""
        m.top.guideResult = { success: false, errorMessage: "No server URL configured" }
        return
    end if

    url = base + "/api/guide"
    resp = Net_HttpGet(url, 15000)

    if resp.success <> true
        m.top.guideResult = { success: false, errorMessage: resp.error }
        return
    end if

    json = ParseJson(resp.body)
    if json = invalid
        m.top.guideResult = { success: false, errorMessage: "Could not parse guide response" }
        return
    end if

    if json.channels = invalid
        m.top.guideResult = { success: false, errorMessage: "Guide response missing channels" }
        return
    end if

    m.top.guideResult = {
        success: true
        errorMessage: ""
        serverTime: json.serverTime
        channels: json.channels
    }
end sub
