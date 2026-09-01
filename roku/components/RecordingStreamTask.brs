sub init()
    m.top.functionName = "startRecordingStream"
end sub

sub startRecordingStream()
    base = m.top.serverUrl + "/recordings/" + m.top.recordingId + "/medium"
    response = Net_HttpPost(base + "/start", 15000)
    if response.success <> true
        m.top.result = { success: false, error: response.error }
        return
    end if

    for i = 1 to 30
        sleep(500)
        ready = Net_HttpGet(base + "/ready", 5000)
        if ready.success = true
            state = ParseJson(ready.body)
            if state <> invalid and state.ready = true
                m.top.result = { success: true }
                return
            end if
            if state <> invalid and state.error <> invalid and state.error <> ""
                m.top.result = { success: false, error: state.error }
                return
            end if
        end if
    end for
    m.top.result = { success: false, error: "Recording playback timed out" }
end sub
