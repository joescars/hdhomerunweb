sub init()
    m.top.functionName = "recordCurrent"
end sub

sub recordCurrent()
    url = m.top.serverUrl + "/watch/" + m.top.channelNumber + "/record"
    response = Net_HttpPost(url, 15000)
    if response.success <> true
        m.top.result = { success: false, error: response.error }
        return
    end if
    payload = ParseJson(response.body)
    if payload = invalid or payload.recording <> true
        m.top.result = { success: false, error: "Server did not confirm recording" }
        return
    end if
    m.top.result = { success: true, title: payload.title }
end sub
