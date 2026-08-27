' PlayerScreen - runs the required start/poll handshake via StreamStartTask,
' then plays the resulting HLS stream in a full-screen Video node.

sub init()
    m.video = m.top.findNode("video")
    m.statsTimer = m.top.findNode("statsTimer")
    m.overlayBg = m.top.findNode("overlayBg")
    m.spinner = m.top.findNode("spinner")
    m.statusLabel = m.top.findNode("statusLabel")
    m.hintLabel = m.top.findNode("hintLabel")
    m.statsPanel = m.top.findNode("statsPanel")
    m.statsTitle = m.top.findNode("statsTitle")
    m.statsBody = m.top.findNode("statsBody")
    m.tuningStarted = false
    m.statsVisible = false
    m.statsTask = invalid
    m.statsCodec = "hevc"
    m.statsProfile = "medium"

    m.video.observeField("state", "onVideoStateChange")
    m.statsTimer.observeField("fire", "onStatsTimerFire")
end sub

' Public - callable from MainScene when this screen becomes top-of-stack.
sub onScreenFocus()
    m.top.setFocus(true)
    if m.tuningStarted = false
        m.tuningStarted = true
        startTuning()
    end if
end sub

sub startTuning()
    if m.top.serverUrl = invalid or m.top.serverUrl = "" or m.top.channelNumber = invalid or m.top.channelNumber = ""
        showOverlay("Missing server URL or channel number", false)
        return
    end if

    refreshStatsContext()
    showOverlay("Tuning " + m.top.channelName + "...", true)

    task = CreateObject("roSGNode", "StreamStartTask")
    task.serverUrl = m.top.serverUrl
    task.channelNumber = m.top.channelNumber
    task.observeField("result", "onStreamStartResult")
    task.control = "RUN"
    m.streamTask = task
end sub

sub refreshStatsContext()
    m.statsCodec = "hevc"
    m.statsProfile = "medium"

    if m.top.streamPath = invalid or m.top.streamPath = "" then return
    parts = m.top.streamPath.Split("/")
    if parts = invalid or parts.Count() < 5 then return

    m.statsCodec = parts[3]
    if parts.Count() >= 6 and parts[4] <> "stream.m3u8"
        m.statsProfile = parts[4]
    end if
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
    hideStatsPanel()
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

' --- diagnostics panel ---------------------------------------------------

sub onStatsTimerFire(event as object)
    if m.statsVisible = true
        requestStats()
    end if
end sub

sub requestStats()
    if m.statsTask <> invalid then return

    task = CreateObject("roSGNode", "StreamStatsTask")
    task.serverUrl = m.top.serverUrl
    task.channelNumber = m.top.channelNumber
    task.codec = m.statsCodec
    task.profile = m.statsProfile
    task.observeField("result", "onStatsResult")
    task.control = "RUN"
    m.statsTask = task
end sub

sub onStatsResult(event as object)
    result = event.getData()
    m.statsTask = invalid
    if m.statsVisible <> true then return

    if result = invalid or result.success <> true
        errText = "Could not load stream diagnostics"
        if result <> invalid and result.error <> invalid and result.error <> ""
            errText = errText + Chr(10) + result.error
        end if
        m.statsBody.text = errText
        return
    end if

    payload = result.payload
    if payload = invalid
        m.statsBody.text = "No diagnostics payload received"
        return
    end if

    session = payload.session
    tuner = payload.tuner
    signalError = payload.signalError

    lines = []
    lines.Push("Channel " + payload.channel + "  •  Codec " + UCase(payload.codec) + "  •  Profile " + payload.profile)

    if session <> invalid
        ffmpeg = session.ffmpeg
        progress = session.progress
        lines.Push("Video target: " + ffmpeg.targetVideoBitrate + " (" + ffmpeg.videoEncoder + ")")
        lines.Push("Audio target: " + ffmpeg.targetAudioBitrate + " (" + ffmpeg.audioEncoder + ")")

        fpsText = "n/a"
        if progress.fps <> invalid then fpsText = progress.fps.ToStr()

        speedText = "n/a"
        if progress.speed <> invalid and progress.speed <> "" then speedText = progress.speed

        bitrateText = "n/a"
        if progress.bitrate <> invalid and progress.bitrate <> "" then bitrateText = progress.bitrate

        lines.Push("FFmpeg: fps " + fpsText + "  •  speed " + speedText + "  •  bitrate " + bitrateText)

        ageSec = Int(session.ageMs / 1000)
        idleSec = Int(session.idleMs / 1000)
        lines.Push("Session age: " + ageSec.ToStr() + "s  •  Last access: " + idleSec.ToStr() + "s ago")
    else
        lines.Push("No active transcoder session found")
    end if

    if tuner <> invalid
        signalText = "Signal: " + percentText(tuner.signalStrengthPercent) + "  •  Quality: " + percentText(tuner.signalQualityPercent) + "  •  Symbol: " + percentText(tuner.symbolQualityPercent)
        lines.Push(signalText)
        if tuner.networkRateMbps <> invalid
            lines.Push("Network rate: " + tuner.networkRateMbps.ToStr() + " Mbps")
        end if
        if tuner.resource <> invalid and tuner.resource <> ""
            lines.Push("Tuner: " + tuner.resource)
        end if
    else if signalError <> invalid and signalError <> ""
        lines.Push("Tuner telemetry unavailable: " + signalError)
    else
        lines.Push("No matching tuner telemetry for this channel yet")
    end if

    m.statsBody.text = Join(lines, Chr(10))
end sub

function percentText(value as dynamic) as string
    if value = invalid then return "n/a"
    return value.ToStr() + "%"
end function

sub showStatsPanel()
    if m.statsVisible = true then return
    m.statsVisible = true
    m.statsPanel.visible = true
    m.statsBody.text = "Loading diagnostics..."
    requestStats()
    m.statsTimer.control = "start"
end sub

sub hideStatsPanel()
    m.statsVisible = false
    m.statsPanel.visible = false
    m.statsTimer.control = "stop"
end sub

sub toggleStatsPanel()
    if m.statsVisible = true
        hideStatsPanel()
    else
        showStatsPanel()
    end if
end sub

' --- key handling / teardown --------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "up"
        toggleStatsPanel()
        return true
    end if
    if press and key = "back"
        closePlayer()
        return true
    end if
    return false
end function

sub closePlayer()
    hideStatsPanel()
    if m.statsTask <> invalid
        m.statsTask.control = "STOP"
        m.statsTask = invalid
    end if
    if m.streamTask <> invalid
        m.streamTask.control = "STOP"
        m.streamTask = invalid
    end if
    ' Explicitly halt playback on the way out even though the server also
    ' auto-releases the tuner ~20s after requests stop.
    m.video.control = "stop"
    m.top.closed = true
end sub
