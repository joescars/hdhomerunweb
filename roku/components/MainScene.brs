' MainScene - top-level scene. Owns a simple screen stack (array of Group
' nodes) since this app doesn't need anything fancier: GuideScreen is always
' at the bottom, PlayerScreen / SettingsScreen get pushed on top of it.

sub init()
    m.top.backgroundColor = "0x0A1428FF"
    m.screenStack = []
    m.serverUrl = readServerUrl()
    m.streamCodec = readStreamCodec()
    m.livePreviewEnabled = readLivePreviewEnabled()

    ' GuideScreen is pushed first so its guide-data fetch starts immediately
    ' in the background, then SplashScreen is pushed on top of it (pushScreen
    ' hides whatever's beneath) - the fixed ~2s splash duration overlaps with
    ' guide loading instead of adding to it.
    showGuide()
    showSplash()
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

' h264_qsv is the only hardware-encoded codec path with closed-caption
' support today (hevc_qsv has no -a53cc equivalent - see
' docs/closed-captioning-options.md). Default to h264 so captions work out
' of the box; users who don't need captions and want HEVC's bitrate/quality
' edge can switch in Settings.
'
' "direct" is a third value alongside h264/hevc, not a separate setting: it
' means "skip transcoding entirely, remux the tuner's raw MPEG2/AC3 into
' HLS unchanged" (see DIRECT_CODEC in src/stream.js). Experimental - CLAUDE.md
' already notes raw MPEG-TS isn't a generally supported Roku stream format,
' so this exists for the user to try and revert, not as a guaranteed-working
' path.
function normalizeStreamCodec(codec as dynamic) as string
    if codec = invalid then return "h264"
    text = LCase(codec.ToStr())
    if text = "hevc" then return "hevc"
    if text = "direct" then return "direct"
    return "h264"
end function

function readStreamCodec() as string
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return "h264"
    if sec.Exists("streamCodec")
        return normalizeStreamCodec(sec.Read("streamCodec"))
    end if
    return "h264"
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

' Defaults to on - most users benefit from it, and it's already debounced
' and best-effort-silent (see GuideScreen.brs). Users with few tuners can
' turn it off in Settings (Up/Down) since each preview holds a tuner while
' it plays.
function readLivePreviewEnabled() as boolean
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return true
    if sec.Exists("livePreviewEnabled") and sec.Read("livePreviewEnabled") = "off"
        return false
    end if
    return true
end function

sub writeLivePreviewEnabled(enabled as boolean)
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return
    if enabled
        sec.Write("livePreviewEnabled", "on")
    else
        sec.Write("livePreviewEnabled", "off")
    end if
    sec.Flush()
end sub

' --- recently watched -------------------------------------------------------
' Local-only (not synced with the web app's server-side favorites) - a
' most-recent-first list of channel numbers, capped at RecentChannelsMax()
' so the guide's pinned row stays a quick-glance list rather than a second
' full channel list.

function RecentChannelsMax() as integer
    return 6
end function

function readRecentChannels() as object
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return []
    if not sec.Exists("recentChannels") then return []

    raw = sec.Read("recentChannels")
    if raw = invalid or raw = "" then return []
    return raw.Split(",")
end function

sub recordRecentChannel(channelNumber as dynamic)
    if channelNumber = invalid then return
    chStr = channelNumber.ToStr()
    if chStr = "" then return

    existing = readRecentChannels()
    updated = [chStr]
    for each ch in existing
        if ch <> chStr and updated.Count() < RecentChannelsMax()
            updated.Push(ch)
        end if
    end for

    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return
    sec.Write("recentChannels", updated.Join(","))
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
    screen.recentChannels = readRecentChannels()
    screen.livePreviewEnabled = m.livePreviewEnabled
    screen.observeField("launchPlayer", "onLaunchPlayer")
    screen.observeField("openSettings", "onOpenSettings")
    screen.observeField("openRecordings", "onOpenRecordings")
    m.guideScreen = screen
    pushScreen(screen)
end sub

sub onOpenRecordings(event as object)
    screen = CreateObject("roSGNode", "RecordingsScreen")
    screen.serverUrl = m.serverUrl
    screen.observeField("openRecording", "onOpenRecording")
    screen.observeField("closed", "onRecordingsClosed")
    pushScreen(screen)
end sub

sub onOpenRecording(event as object)
    data = event.getData()
    if data = invalid then return
    screen = CreateObject("roSGNode", "RecordingPlayerScreen")
    screen.serverUrl = m.serverUrl
    screen.recordingId = data.id
    screen.title = data.title
    screen.observeField("closed", "onRecordingPlayerClosed")
    pushScreen(screen)
end sub

sub onRecordingPlayerClosed(event as object)
    popScreen()
end sub

sub onRecordingsClosed(event as object)
    popScreen()
end sub

' --- splash ---------------------------------------------------------------

sub showSplash()
    screen = CreateObject("roSGNode", "SplashScreen")
    screen.observeField("finished", "onSplashFinished")
    pushScreen(screen)
end sub

sub onSplashFinished(event as object)
    popScreen()
end sub

' --- player -------------------------------------------------------------

sub onLaunchPlayer(event as object)
    data = event.getData()
    if data = invalid then return

    if m.serverUrl = invalid or m.serverUrl = "" then m.serverUrl = readServerUrl()

    if m.streamCodec = invalid or m.streamCodec = "" then m.streamCodec = readStreamCodec()
    codec = normalizeStreamCodec(m.streamCodec)

    recordRecentChannel(data.channelNumber)

    screen = CreateObject("roSGNode", "PlayerScreen")
    screen.serverUrl = m.serverUrl
    screen.channelNumber = data.channelNumber
    screen.channelName = data.channelName
    screen.codec = codec
    screen.streamPath = "/stream/" + data.channelNumber.ToStr() + "/" + codec + "/stream.m3u8"
    screen.channels = data.channels
    screen.currentTitle = data.currentTitle
    screen.nextTitle = data.nextTitle
    screen.observeField("closed", "onPlayerClosed")
    pushScreen(screen)
end sub

sub onPlayerClosed(event as object)
    popScreen()
    ' GuideScreen is created once and reused (not recreated on every visit),
    ' so its recentChannels snapshot needs an explicit refresh here to
    ' reflect whatever was just watched. Setting the field (rather than
    ' forcing a full refreshGuide() network re-fetch) triggers GuideScreen's
    ' own onChange handler to just re-render from its already-cached data.
    if m.guideScreen <> invalid
        m.guideScreen.recentChannels = readRecentChannels()
    end if
end sub

' --- settings -----------------------------------------------------------

sub onOpenSettings(event as object)
    screen = CreateObject("roSGNode", "SettingsScreen")
    screen.serverUrl = m.serverUrl
    screen.streamCodec = m.streamCodec
    screen.livePreviewEnabled = m.livePreviewEnabled
    screen.observeField("saved", "onSettingsSaved")
    screen.observeField("codecSaved", "onCodecSaved")
    screen.observeField("livePreviewSaved", "onLivePreviewSaved")
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

sub onLivePreviewSaved(event as object)
    enabled = event.getData()
    if enabled = invalid then return
    m.livePreviewEnabled = enabled
    writeLivePreviewEnabled(enabled)
    if m.guideScreen <> invalid
        m.guideScreen.livePreviewEnabled = enabled
    end if
end sub

' --- called from main.brs's message loop --------------------------------

sub onSystemResumeSignal()
    top = currentScreen()
    if top <> invalid and top.subtype() = "GuideScreen"
        top.callFunc("refreshGuide")
    end if
end sub
