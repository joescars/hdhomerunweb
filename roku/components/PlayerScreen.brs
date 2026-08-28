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
        showOverlay(streamStartFailureMessage(result), false)
    end if
end sub

' Builds a concise user-facing status for common startup failures while still
' including useful detail from the backend when available.
function streamStartFailureMessage(result as object) as string
    reason = ""
    detail = ""
    if result <> invalid
        if result.reason <> invalid and result.reason <> "" then reason = LCase(result.reason)
        if result.error <> invalid then detail = result.error
    end if

    if reason = "tuner_busy"
        return friendlyError("All tuners are busy", detail)
    else if reason = "network"
        return friendlyError("Network issue while starting stream", detail)
    else if reason = "timeout"
        return friendlyError("Stream startup timed out", detail)
    else if reason = "access_denied"
        return friendlyError("Channel access denied", detail)
    else if reason = "signal"
        return friendlyError("Channel unavailable or weak signal", detail)
    end if

    return friendlyError("Could not tune channel", detail)
end function

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

    channelText = "n/a"
    codecText = "n/a"
    profileText = "n/a"
    if payload.channel <> invalid and payload.channel <> "" then channelText = payload.channel.ToStr()
    if payload.codec <> invalid and payload.codec <> "" then codecText = UCase(payload.codec.ToStr())
    if payload.profile <> invalid and payload.profile <> "" then profileText = payload.profile.ToStr()

    lines = []
    lines.Push("Channel " + channelText + "  •  Codec " + codecText + "  •  Profile " + profileText)

    if session <> invalid
        ffmpeg = session.ffmpeg
        progress = session.progress

        videoTarget = "n/a"
        videoEncoder = "n/a"
        audioTarget = "n/a"
        audioEncoder = "n/a"
        if ffmpeg <> invalid
            if ffmpeg.targetVideoBitrate <> invalid and ffmpeg.targetVideoBitrate <> "" then videoTarget = ffmpeg.targetVideoBitrate.ToStr()
            if ffmpeg.videoEncoder <> invalid and ffmpeg.videoEncoder <> "" then videoEncoder = ffmpeg.videoEncoder.ToStr()
            if ffmpeg.targetAudioBitrate <> invalid and ffmpeg.targetAudioBitrate <> "" then audioTarget = ffmpeg.targetAudioBitrate.ToStr()
            if ffmpeg.audioEncoder <> invalid and ffmpeg.audioEncoder <> "" then audioEncoder = ffmpeg.audioEncoder.ToStr()
        end if
        lines.Push("Video target: " + videoTarget + " (" + videoEncoder + ")")
        lines.Push("Audio target: " + audioTarget + " (" + audioEncoder + ")")

        fpsText = "n/a"
        if progress <> invalid and progress.fps <> invalid then fpsText = progress.fps.ToStr()

        speedText = "n/a"
        if progress <> invalid and progress.speed <> invalid and progress.speed <> "" then speedText = progress.speed.ToStr()

        bitrateText = "n/a"
        if progress <> invalid and progress.bitrate <> invalid and progress.bitrate <> "" then bitrateText = progress.bitrate.ToStr()

        lines.Push("FFmpeg: fps " + fpsText + "  •  speed " + speedText + "  •  bitrate " + bitrateText)

        ageSecText = "n/a"
        if session.ageMs <> invalid then ageSecText = Int(session.ageMs / 1000).ToStr()
        idleSecText = "n/a"
        if session.idleMs <> invalid then idleSecText = Int(session.idleMs / 1000).ToStr()
        lines.Push("Session age: " + ageSecText + "s  •  Last access: " + idleSecText + "s ago")
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

    m.statsBody.text = lines.Join(Chr(10))
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
