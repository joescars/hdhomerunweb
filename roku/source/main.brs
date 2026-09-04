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
    ' Refresh only for focus-gain or screensaver-exit events; backgrounding
    ' must not trigger a guide fetch and render.
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
            param = ""
            if msg.GetMessageParam() <> invalid then param = LCase(msg.GetMessageParam().ToStr())
            if scene <> invalid and (param = "active" or param = "screensaver_exited")
                scene.callFunc("onSystemResumeSignal")
            end if
        end if
    end while
end sub
