' StreamStopTask releases an abandoned stream without blocking the UI thread.
sub init()
    m.top.functionName = "doStop"
end sub

sub doStop()
    if m.top.serverUrl = invalid or m.top.serverUrl = "" or m.top.channelNumber = invalid or m.top.channelNumber = "" then return
    codec = m.top.codec
    if codec = invalid or codec = "" then codec = "h264"
    profile = m.top.profile
    if profile = invalid or profile = "" then profile = "medium"
    Net_HttpPost(m.top.serverUrl + "/stream/" + m.top.channelNumber + "/" + codec + "/" + profile + "/stop", 3000)
end sub