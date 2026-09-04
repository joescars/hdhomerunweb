' FavoriteTask keeps the HDHomeRun mutation off the render thread.
sub init()
    m.top.functionName = "setFavorite"
end sub

sub setFavorite()
    desired = "0"
    if m.top.favorite = true then desired = "1"
    url = m.top.serverUrl + "/api/channels/" + m.top.channelNumber + "/favorite?favorite=" + desired
    response = Net_HttpPost(url, 15000)
    if response.success <> true
        m.top.result = { success: false, error: response.error }
        return
    end if
    payload = ParseJson(response.body)
    if payload = invalid or payload.favorite = invalid
        m.top.result = { success: false, error: "Server did not confirm favorite update" }
        return
    end if
    m.top.result = { success: true, favorite: payload.favorite }
end sub