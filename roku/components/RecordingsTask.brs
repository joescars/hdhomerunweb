sub init()
    m.top.functionName = "runRequest"
end sub

sub runRequest()
    if m.top.serverUrl = invalid or m.top.serverUrl = ""
        m.top.result = { success: false, error: "No server URL configured" }
        return
    end if

    url = m.top.serverUrl + "/api/recordings"
    if m.top.method = "delete" or m.top.method = "stop"
        url = url + "/" + m.top.recordingId + "/" + m.top.method
        response = Net_HttpPost(url, 15000)
    else
        response = Net_HttpGet(url, 15000)
    end if

    if response.success <> true
        m.top.result = { success: false, error: response.error }
        return
    end if

    if m.top.method = "delete" or m.top.method = "stop"
        m.top.result = { success: true }
        return
    end if

    payload = ParseJson(response.body)
    if payload = invalid or payload.recordings = invalid
        m.top.result = { success: false, error: "Invalid recordings response" }
        return
    end if
    m.top.result = { success: true, recordings: payload.recordings }
end sub
