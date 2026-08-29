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
    m.channels = invalid
    m.currentIndex = invalid
    m.failed = false

    m.video.observeField("state", "onVideoStateChange")
    m.statsTimer.observeField("fire", "onStatsTimerFire")
end sub

' Public - callable from MainScene when this screen becomes top-of-stack.
sub onScreenFocus()
    m.top.setFocus(true)
    m.channels = m.top.channels
    m.top.codec = normalizeCodec(m.top.codec)
    if m.top.streamPath = invalid or m.top.streamPath = ""
        m.top.streamPath = buildStreamPath(m.top.channelNumber)
    end if
    resolveCurrentIndex()
    if m.tuningStarted = false
        m.tuningStarted = true
        startTuning()
    end if
end sub

function normalizeCodec(codec as dynamic) as string
    if codec = invalid then return "h264"
    value = LCase(codec.ToStr())
    if value = "hevc" then return "hevc"
    return "h264"
end function

function buildStreamPath(channelNumber as dynamic) as string
    codec = normalizeCodec(m.top.codec)
    return "/stream/" + channelNumber.ToStr() + "/" + codec + "/stream.m3u8"
end function

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
    task.codec = normalizeCodec(m.top.codec)
    task.observeField("result", "onStreamStartResult")
    task.control = "RUN"
    m.streamTask = task
end sub

sub refreshStatsContext()
    m.statsCodec = normalizeCodec(m.top.codec)
    m.statsProfile = "medium"

    if m.top.streamPath = invalid or m.top.streamPath = "" then return
    parts = m.top.streamPath.Split("/")
    if parts = invalid or parts.Count() < 5 then return

    m.statsCodec = parts[3]
    if parts.Count() >= 6 and parts[4] <> "stream.m3u8"
        m.statsProfile = parts[4]
    end if
end sub

' Finds the index of the current channel within the passed channel list so
' rewind/forward can step through the same order shown in the guide.
sub resolveCurrentIndex()
    m.currentIndex = invalid
    if m.channels = invalid or m.top.channelNumber = invalid then return
    for i = 0 to m.channels.Count() - 1
        if m.channels[i].channelNumber = m.top.channelNumber
            m.currentIndex = i
            exit for
        end if
    end for
end sub

' Steps to the previous (-1) or next (+1) channel in the guide order and
' re-runs the tuning handshake. Wraps around at both ends.
sub changeChannelBy(delta as integer)
    if m.channels = invalid or m.channels.Count() = 0 then return
    if m.currentIndex = invalid then return

    n = m.channels.Count()
    newIdx = m.currentIndex + delta
    if newIdx < 0 then newIdx = n - 1
    if newIdx >= n then newIdx = 0

    ch = m.channels[newIdx]
    if ch = invalid then return

    m.currentIndex = newIdx
    m.top.channelNumber = ch.channelNumber
    m.top.channelName = ch.channelName
    m.top.streamPath = buildStreamPath(ch.channelNumber)

    if m.streamTask <> invalid
        m.streamTask.control = "STOP"
        m.streamTask = invalid
    end if
    if m.video <> invalid
        m.video.control = "stop"
    end if
    hideStatsPanel()
    m.failed = false
    startTuning()
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
    m.failed = false

    url = m.top.serverUrl + m.top.streamPath
    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    content.streamFormat = "hls"
    content.live = true

    ' Unlike a TV or browser, Roku's Video node does not auto-detect
    ' embedded EIA-608 captions from H.264 SEI data - it only looks for a
    ' caption track if SubtitleTracks explicitly names one. h264_qsv is the
    ' only codec path that embeds caption data at all (see
    ' docs/closed-captioning-options.md); hevc has nothing to point at.
    if normalizeCodec(m.top.codec) = "h264"
        content.SubtitleTracks = [{
            TrackName: "eia608/1"
            Language: "eng"
            Description: "English"
        }]
    end if

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
    if showSpinner
        m.hintLabel.text = "Press Back to return to Guide"
        m.failed = false
    else
        m.hintLabel.text = "Press OK to retry · Back to return to Guide"
        m.failed = true
    end if
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
        captions = session.captions
        sourceCaptions = session.sourceCaptions
        webvtt = session.webvtt
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

        captionModeText = "n/a"
        captionStrategyText = "n/a"
        if ffmpeg <> invalid
            if ffmpeg.captionMode <> invalid and ffmpeg.captionMode <> "" then captionModeText = ffmpeg.captionMode.ToStr()
            if ffmpeg.captionStrategy <> invalid and ffmpeg.captionStrategy <> "" then captionStrategyText = ffmpeg.captionStrategy.ToStr()
        end if

        captionDetectedText = "unknown"
        captionDetailText = ""
        if captions <> invalid
            if captions.detected = true
                captionDetectedText = "detected"
            else if captions.detected = false
                captionDetectedText = "not detected"
            end if

            if captions.closedCaptions = true
                captionDetailText = "embedded CC"
            else if captions.subtitleTrackCount <> invalid and captions.subtitleTrackCount > 0
                captionDetailText = captions.subtitleTrackCount.ToStr() + " subtitle track(s)"
            end if
        end if

        captionLine = "Captions: " + captionDetectedText + "  •  Mode " + captionModeText + "  •  Strategy " + captionStrategyText
        if captionDetailText <> "" then captionLine = captionLine + " (" + captionDetailText + ")"
        lines.Push(captionLine)

        if captions <> invalid and captions.lastProbeError <> invalid and captions.lastProbeError <> ""
            lines.Push("Caption probe error: " + captions.lastProbeError)
        end if

        sourceDetectedText = "unknown"
        sourceDetailText = ""
        if sourceCaptions <> invalid
            if sourceCaptions.source = "disabled"
                sourceDetectedText = "probe disabled"
            end if

            if sourceCaptions.detected = true
                sourceDetectedText = "detected"
            else if sourceCaptions.detected = false
                sourceDetectedText = "not detected"
            end if

            if sourceCaptions.closedCaptions = true
                sourceDetailText = "embedded CC"
            else if sourceCaptions.subtitleTrackCount <> invalid and sourceCaptions.subtitleTrackCount > 0
                sourceDetailText = sourceCaptions.subtitleTrackCount.ToStr() + " subtitle track(s)"
            end if
        end if

        sourceLine = "Input captions: " + sourceDetectedText
        if sourceDetailText <> "" then sourceLine = sourceLine + " (" + sourceDetailText + ")"
        lines.Push(sourceLine)

        if sourceCaptions <> invalid and sourceCaptions.source <> "disabled" and sourceCaptions.lastProbeError <> invalid and sourceCaptions.lastProbeError <> ""
            lines.Push("Input probe error: " + sourceCaptions.lastProbeError)
        end if

        if webvtt <> invalid
            webvttState = "unknown"
            if webvtt.state <> invalid and webvtt.state <> "" then webvttState = webvtt.state.ToStr()
            webvttReason = ""
            if webvtt.reason <> invalid and webvtt.reason <> "" then webvttReason = " (" + webvtt.reason.ToStr() + ")"
            lines.Push("WebVTT sidecar: " + webvttState + webvttReason)
            if webvtt.lastError <> invalid and webvtt.lastError <> ""
                lines.Push("WebVTT error: " + webvtt.lastError)
            end if
        end if

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
    if press and key = "rewind"
        changeChannelBy(-1)
        return true
    end if
    if press and key = "forward"
        changeChannelBy(1)
        return true
    end if
    if press and key = "OK" and m.failed = true
        startTuning()
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
