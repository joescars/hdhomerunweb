' SplashScreen - shows the branded splash for a fixed duration, then fires
' "finished" so MainScene can pop it and reveal the guide loading underneath.

sub init()
    m.timer = m.top.findNode("splashTimer")
    m.timer.observeField("fire", "onTimerFire")
end sub

' Public - callable from MainScene when this screen becomes top-of-stack.
sub onScreenFocus()
    m.top.setFocus(true)
    m.timer.control = "start"
end sub

sub onTimerFire(event as object)
    m.top.finished = true
end sub
