sub init()
    m.list = m.top.findNode("list")
    m.status = m.top.findNode("status")
    m.refreshTimer = m.top.findNode("refreshTimer")
    m.task = invalid
    m.deleteTask = invalid
    m.items = []
    m.list.observeField("itemSelected", "onSelected")
    m.refreshTimer.observeField("fire", "onRefreshTimerFire")
end sub

sub onScreenFocus()
    m.top.setFocus(true)
    m.refreshTimer.control = "start"
    loadRecordings()
end sub

sub onRefreshTimerFire(event as object)
    loadRecordings()
end sub

sub loadRecordings()
    if m.task <> invalid then return
    m.status.text = "Loading recordings..."
    task = CreateObject("roSGNode", "RecordingsTask")
    task.serverUrl = m.top.serverUrl
    task.method = "list"
    task.observeField("result", "onResult")
    m.task = task
    task.control = "RUN"
end sub

sub onResult(event as object)
    result = event.getData()
    m.task = invalid
    if result = invalid or result.success <> true
        m.status.text = "DVR unavailable: " + errorText(result)
        return
    end if

    m.items = []
    content = CreateObject("roSGNode", "ContentNode")
    for each group in result.recordings
        for each episode in group.episodes
            item = content.CreateChild("ContentNode")
            title = group.Title
            if title = invalid or title = "" then title = "Recording"
            subtitle = episode.EpisodeTitle
            if subtitle = invalid or subtitle = "" then subtitle = "Recorded episode"
            isActive = (episode.recording = true)
            if isActive
                subtitle = "RECORDING NOW  -  " + subtitle
            end if
            if episode.ChannelName <> invalid and episode.ChannelName <> ""
                subtitle = subtitle + "  -  " + episode.ChannelName
            end if
            item.AddFields({
                recordingTitle: title
                recordingSubtitle: subtitle
                recordingId: episode.id
            })
            m.items.Push({ id: episode.id, title: title, recording: isActive })
        end for
    end for
    m.list.content = content
    if m.items.Count() = 0
        m.status.text = "No recordings"
    else
        m.status.text = ""
        m.list.setFocus(true)
    end if
end sub

function errorText(result as dynamic) as string
    if result <> invalid and result.error <> invalid and result.error <> "" then return result.error
    return "Recording engine is not configured"
end function

sub onSelected(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.items.Count() then return
    m.top.openRecording = m.items[idx]
end sub

sub deleteSelected()
    idx = m.list.itemFocused
    if idx < 0 or idx >= m.items.Count() then return
    if m.deleteTask <> invalid then return
    method = "delete"
    action = "Deleting recording..."
    if m.items[idx].recording = true
        method = "stop"
        action = "Stopping recording..."
    end if
    m.status.text = action
    task = CreateObject("roSGNode", "RecordingsTask")
    task.serverUrl = m.top.serverUrl
    task.method = method
    task.recordingId = m.items[idx].id
    task.observeField("result", "onDeleteResult")
    m.deleteTask = task
    task.control = "RUN"
end sub

sub onDeleteResult(event as object)
    m.deleteTask = invalid
    result = event.getData()
    if result = invalid or result.success <> true
        m.status.text = "Recording action failed: " + errorText(result)
        return
    end if
    m.items = []
    m.list.content = invalid
    loadRecordings()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options"
        deleteSelected()
        return true
    else if key = "back"
        m.refreshTimer.control = "stop"
        m.top.closed = true
        return true
    end if
    return false
end function
