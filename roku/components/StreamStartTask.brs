' StreamStartTask - implements the required tuner start/poll handshake:
'   1. POST <base>/stream/<channel>/start   (202, no body)
'   2. GET  <base>/stream/<channel>/ready   every 500ms until ready or failed
'      capped at 30s total, then a timeout error
'
' Do NOT simplify this: the HLS playlist does not exist until ffmpeg has
' spun up server-side, so the player must not touch the .m3u8 until "ready".
'
' All network I/O happens here, never on the render thread.

sub init()
    m.top.functionName = "doStart"
end sub

sub doStart()
    base = m.top.serverUrl
    chan = m.top.channelNumber

    if base = invalid or base = "" or chan = invalid or chan = ""
        m.top.result = { state: "failed", error: "Missing server URL or channel number" }
        return
    end if

    ' Roku always requests the hevc encode - its Video node decodes HEVC
    ' natively, unlike the browser player's hls.js pipeline (h264 only).
    startUrl = base + "/stream/" + chan + "/hevc/start"
    readyUrl = base + "/stream/" + chan + "/hevc/ready"

    ' Step 1: kick off the tuner/transcode. 202 Accepted with no body expected,
    ' but we treat any 2xx as success.
    postResp = Net_HttpPost(startUrl, 10000)
    if postResp.success <> true
        m.top.result = {
            state: "failed"
            reason: "network"
            error: "Could not start stream (" + postResp.error + ")"
        }
        return
    end if

    ' Step 2: poll with bounded backoff, capped at 30s total elapsed wall-clock time.
    pollIntervalMs = 500
    maxPollIntervalMs = 2000
    backoffStepMs = 250
    consecutivePollFailures = 0
    maxConsecutivePollFailures = 6
    maxWaitMs = 30000

    stopwatch = CreateObject("roTimespan")
    stopwatch.Mark()

    while stopwatch.TotalMilliseconds() < maxWaitMs
        ' Bail out early if someone stopped the task (e.g. user backed out).
        if m.top.control = "STOP" then return

        Sleep(pollIntervalMs)

        if m.top.control = "STOP" then return

        readyResp = Net_HttpGet(readyUrl, 5000)
        if readyResp.success = true
            json = ParseJson(readyResp.body)
            if json <> invalid
                if json.failed = true
                    errMsg = "Tuner failed to start"
                    if json.error <> invalid and json.error <> ""
                        errMsg = json.error
                    end if
                    m.top.result = {
                        state: "failed"
                        reason: classifyFailureReason(errMsg)
                        error: errMsg
                    }
                    return
                else if json.ready = true
                    m.top.result = {
                        state: "ready"
                        reason: "ok"
                        error: ""
                    }
                    return
                end if
                ' else: not ready yet, keep polling
            end if
            consecutivePollFailures = 0
            pollIntervalMs = 500
        else
            consecutivePollFailures = consecutivePollFailures + 1
            pollIntervalMs = pollIntervalMs + backoffStepMs
            if pollIntervalMs > maxPollIntervalMs
                pollIntervalMs = maxPollIntervalMs
            end if

            if consecutivePollFailures >= maxConsecutivePollFailures
                m.top.result = {
                    state: "failed"
                    reason: "network"
                    error: "Could not confirm stream readiness due to repeated network errors"
                }
                return
            end if
        end if
    end while

    m.top.result = {
        state: "timeout"
        reason: "timeout"
        error: "Timed out waiting for the stream to start"
    }
end sub

function classifyFailureReason(errorText as string) as string
    if errorText = invalid then return "unknown"
    lower = LCase(errorText)

    if Instr(1, lower, "busy") > 0 or Instr(1, lower, "in use") > 0 or Instr(1, lower, "resource") > 0
        return "tuner_busy"
    end if

    if Instr(1, lower, "unauthorized") > 0 or Instr(1, lower, "forbidden") > 0
        return "access_denied"
    end if

    if Instr(1, lower, "timeout") > 0 or Instr(1, lower, "timed out") > 0
        return "timeout"
    end if

    if Instr(1, lower, "signal") > 0 or Instr(1, lower, "channel") > 0
        return "signal"
    end if

    return "unknown"
end function
