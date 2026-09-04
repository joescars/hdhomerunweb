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
    ' App-focus events cannot be safely distinguished as gain vs. loss across
    ' supported firmware versions. Subscribe only to screensaver exit, which
    ' is unambiguously a resume event and never fires while backgrounding.
    ' The 5-minute GuideScreen timer is the reliable primary refresh
    ' mechanism; this is just a best-effort improvement for accuracy.
    deviceInfo = CreateObject("roDeviceInfo")
    deviceInfo.SetMessagePort(port)
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
