' MainScene - top-level scene. Owns a simple screen stack (array of Group
' nodes) since this app doesn't need anything fancier: GuideScreen is always
' at the bottom, PlayerScreen / SettingsScreen get pushed on top of it.

sub init()
    m.top.backgroundColor = "0x0A1428FF"
    m.screenStack = []
    m.serverUrl = readServerUrl()
    m.streamCodec = readStreamCodec()

    showGuide()
end sub

' --- registry -------------------------------------------------------------

function normalizeServerUrl(url as dynamic) as string
    if url = invalid then return ""
    text = url.Trim()
    if text = "" then return ""
    if Right(text, 1) = "/" then return Left(text, Len(text) - 1)
    return text
end function

function readServerUrl() as string
    defaultUrl = GetPackagedServerUrl()
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return defaultUrl
    if sec.Exists("serverUrl")
        stored = sec.Read("serverUrl")
        normalized = normalizeServerUrl(stored)
        if normalized <> "" then return normalized
    end if
    return defaultUrl
end function

function normalizeStreamCodec(codec as dynamic) as string
    if codec = invalid then return "hevc"
    text = LCase(codec.ToStr())
    if text = "h264" then return "h264"
    return "hevc"
end function

function readStreamCodec() as string
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return "hevc"
    if sec.Exists("streamCodec")
        return normalizeStreamCodec(sec.Read("streamCodec"))
    end if
    return "hevc"
end function

sub writeServerUrl(url as string)
    normalized = normalizeServerUrl(url)
    if normalized = "" then return

    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return
    sec.Write("serverUrl", normalized)
    sec.Flush()
end sub

sub writeStreamCodec(codec as string)
    normalized = normalizeStreamCodec(codec)

    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return
    sec.Write("streamCodec", normalized)
    sec.Flush()
end sub

' --- screen stack -----------------------------------------------------------

' NOTE: we deliberately call the screen's own "onScreenFocus" function rather
' than screen.setFocus(true) directly. GuideScreen needs focus to land on its
' inner TimeGrid (not the screen's outer Group) for remote navigation to
' work, so each screen component owns exactly where its focus goes.
sub pushScreen(screen as object)
    if m.screenStack.Count() > 0
        m.screenStack[m.screenStack.Count() - 1].visible = false
    end if
    m.top.appendChild(screen)
    m.screenStack.Push(screen)
    screen.callFunc("onScreenFocus")
end sub

sub popScreen()
    if m.screenStack.Count() = 0 then return
    screen = m.screenStack.Pop()
    m.top.removeChild(screen)
    if m.screenStack.Count() > 0
        top = m.screenStack[m.screenStack.Count() - 1]
        top.visible = true
        top.callFunc("onScreenFocus")
    end if
end sub

function currentScreen() as dynamic
    if m.screenStack.Count() = 0 then return invalid
    return m.screenStack[m.screenStack.Count() - 1]
end function

' --- guide ------------------------------------------------------------------

sub showGuide()
    screen = CreateObject("roSGNode", "GuideScreen")
    screen.serverUrl = m.serverUrl
    screen.observeField("launchPlayer", "onLaunchPlayer")
    screen.observeField("openSettings", "onOpenSettings")
    m.guideScreen = screen
    pushScreen(screen)
end sub

' --- player -------------------------------------------------------------

sub onLaunchPlayer(event as object)
    data = event.getData()
    if data = invalid then return

    if m.serverUrl = invalid or m.serverUrl = "" then m.serverUrl = readServerUrl()

    if m.streamCodec = invalid or m.streamCodec = "" then m.streamCodec = readStreamCodec()
    codec = normalizeStreamCodec(m.streamCodec)

    screen = CreateObject("roSGNode", "PlayerScreen")
    screen.serverUrl = m.serverUrl
    screen.channelNumber = data.channelNumber
    screen.channelName = data.channelName
    screen.codec = codec
    screen.streamPath = "/stream/" + data.channelNumber.ToStr() + "/" + codec + "/stream.m3u8"
    screen.channels = data.channels
    screen.observeField("closed", "onPlayerClosed")
    pushScreen(screen)
end sub

sub onPlayerClosed(event as object)
    popScreen()
end sub

' --- settings -----------------------------------------------------------

sub onOpenSettings(event as object)
    screen = CreateObject("roSGNode", "SettingsScreen")
    screen.serverUrl = m.serverUrl
    screen.streamCodec = m.streamCodec
    screen.observeField("saved", "onSettingsSaved")
    screen.observeField("codecSaved", "onCodecSaved")
    screen.observeField("closed", "onSettingsClosed")
    pushScreen(screen)
end sub

sub onSettingsSaved(event as object)
    newUrl = event.getData()
    if newUrl = invalid or newUrl = "" then return

    validated = normalizeServerUrl(newUrl)
    if validated = "" then return

    m.serverUrl = validated
    writeServerUrl(validated)
    if m.guideScreen <> invalid
        m.guideScreen.serverUrl = validated
        m.guideScreen.callFunc("refreshGuide")
    end if
end sub

sub onSettingsClosed(event as object)
    popScreen()
end sub

sub onCodecSaved(event as object)
    codec = event.getData()
    if codec = invalid or codec = "" then return
    m.streamCodec = normalizeStreamCodec(codec)
    writeStreamCodec(m.streamCodec)
end sub

' --- called from main.brs's message loop --------------------------------

sub onSystemResumeSignal()
    top = currentScreen()
    if top <> invalid and top.subtype() = "GuideScreen"
        top.callFunc("refreshGuide")
    end if
end sub
