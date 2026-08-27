' HDHomeRun Web client - entry point.
'
' Standard SceneGraph bootstrap: create the roSGScreen, create the MainScene,
' and pump a message loop. We also register for a couple of roDeviceInfo
' events so we can nudge the guide to refresh when something resume-like
' happens (see comment below - the exact semantics of these events were not
' verified on a physical device).

sub main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.Show()

    ' Best-effort "app resumed" detection.
    '
    ' NOTE (uncertain / needs on-device verification): EnableAppFocusEvent and
    ' EnableScreensaverExitedEvent deliver roDeviceInfoEvent messages on the
    ' device info object's message port. We wire that to the same port as the
    ' screen so a single wait() loop sees everything. We do NOT try to
    ' distinguish "focus gained" vs "focus lost" or inspect the event payload
    ' precisely - we treat receipt of ANY such event as a hint to refresh the
    ' guide. Worst case this causes one extra harmless /api/guide fetch.
    ' The 5-minute GuideScreen timer is the reliable primary refresh
    ' mechanism; this is just a best-effort improvement for accuracy.
    deviceInfo = CreateObject("roDeviceInfo")
    deviceInfo.SetMessagePort(port)
    deviceInfo.EnableAppFocusEvent(true)
    deviceInfo.EnableScreensaverExitedEvent(true)

    while true
        msg = wait(0, port)
        msgType = type(msg)

        if msgType = "roSGScreenEvent"
            if msg.IsScreenClosed()
                return
            end if
        else if msgType = "roDeviceInfoEvent"
            if scene <> invalid
                scene.callFunc("onSystemResumeSignal")
            end if
        end if
    end while
end sub
