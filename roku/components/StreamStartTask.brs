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
        m.top.result = { state: "failed", error: "Could not start stream (" + postResp.error + ")" }
        return
    end if

    ' Step 2: poll every 500ms, capped at 30s total elapsed wall-clock time.
    pollIntervalMs = 500
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
                    m.top.result = { state: "failed", error: errMsg }
                    return
                else if json.ready = true
                    m.top.result = { state: "ready", error: "" }
                    return
                end if
                ' else: not ready yet, keep polling
            end if
        end if
        ' On a transient GET failure we keep polling until the overall cap
        ' is hit rather than failing immediately - a single dropped poll
        ' shouldn't abort a tune that's otherwise progressing.
    end while

    m.top.result = { state: "timeout", error: "Timed out waiting for the stream to start" }
end sub
