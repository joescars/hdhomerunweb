' PlayerScreen - runs the required start/poll handshake via StreamStartTask,
' then plays the resulting HLS stream in a full-screen Video node.

sub init()
    m.video = m.top.findNode("video")
    m.overlayBg = m.top.findNode("overlayBg")
    m.spinner = m.top.findNode("spinner")
    m.statusLabel = m.top.findNode("statusLabel")
    m.hintLabel = m.top.findNode("hintLabel")

    m.video.observeField("state", "onVideoStateChange")

    onScreenFocus()

    startTuning()
end sub

' Public - callable from MainScene when this screen becomes top-of-stack.
sub onScreenFocus()
    m.top.setFocus(true)
end sub

sub startTuning()
    showOverlay("Tuning " + m.top.channelName + "...", true)

    task = CreateObject("roSGNode", "StreamStartTask")
    task.serverUrl = m.top.serverUrl
    task.channelNumber = m.top.channelNumber
    task.observeField("result", "onStreamStartResult")
    task.control = "RUN"
    m.streamTask = task
end sub

sub onStreamStartResult(event as object)
    result = event.getData()
    m.streamTask = invalid
    if result = invalid then return

    if result.state = "ready"
        playStream()
    else
        ' The server's /ready error field carries an ffmpeg stderr tail that can
        ' run to thousands of characters. Full text goes to the debug console
        ' (telnet <roku-ip> 8085); the screen gets a short readable version.
        if result.error <> invalid and result.error <> ""
            print "[PlayerScreen] stream start failed: "; result.error
        end if
        showOverlay(friendlyError("Could not tune channel", result.error), false)
    end if
end sub

' Builds a one-line, screen-safe message: a human headline plus a trimmed hint
' from the underlying error, if there is one worth showing.
function friendlyError(headline as string, detail as dynamic) as string
    if detail = invalid or detail = "" then return headline

    text = detail.Trim()

    ' Prefer the last non-empty line - for ffmpeg output that's the part
    ' closest to the actual failure.
    lines = text.Split(Chr(10))
    for i = lines.Count() - 1 to 0 step -1
        candidate = lines[i].Trim()
        if candidate <> ""
            text = candidate
            exit for
        end if
    end for

    maxLen = 120
    if Len(text) > maxLen
        text = Left(text, maxLen - 1) + Chr(8230) ' ellipsis
    end if

    return headline + " - " + text
end function

sub playStream()
    hideOverlay()

    url = m.top.serverUrl + m.top.streamPath
    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    content.streamFormat = "hls"
    content.live = true

    m.video.content = content
    m.video.visible = true
    m.video.control = "play"
end sub

sub onVideoStateChange(event as object)
    state = event.getData()

    if state = "error"
        if m.video.errorMsg <> invalid and m.video.errorMsg <> ""
            print "[PlayerScreen] playback error: "; m.video.errorMsg
        end if
        showOverlay(friendlyError("Playback error", m.video.errorMsg), false)
    else if state = "finished"
        showOverlay("Stream ended", false)
    end if
end sub

' --- overlay helpers ---------------------------------------------------

sub showOverlay(text as string, showSpinner as boolean)
    m.video.visible = false
    m.overlayBg.visible = true
    m.spinner.visible = showSpinner
    m.statusLabel.visible = true
    m.statusLabel.text = text
    m.hintLabel.visible = true
    m.hintLabel.text = "Press Back to return to Guide"
end sub

sub hideOverlay()
    m.overlayBg.visible = false
    m.spinner.visible = false
    m.statusLabel.visible = false
    m.hintLabel.visible = false
end sub

' --- key handling / teardown --------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back"
        closePlayer()
        return true
    end if
    return false
end function

sub closePlayer()
    if m.streamTask <> invalid
        m.streamTask.control = "STOP"
        m.streamTask = invalid
    end if
    ' Explicitly halt playback on the way out even though the server also
    ' auto-releases the tuner ~20s after requests stop.
    m.video.control = "stop"
    m.top.closed = true
end sub
