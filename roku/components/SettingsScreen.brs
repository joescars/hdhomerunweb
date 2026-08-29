' SettingsScreen - lets the user view/edit the server base URL, persisted to
' the Roku registry (section "hdhrweb", key "serverUrl").
'
' This screen has no focusable children of its own; it grabs focus itself and
' handles OK (open keyboard) / Back (close) directly via onKeyEvent, which is
' simple and sufficient for a single-field settings screen.

sub init()
    m.urlLabel = m.top.findNode("urlLabel")
    m.codecLabel = m.top.findNode("codecLabel")
    m.statusLabel = m.top.findNode("statusLabel")
    m.checkTask = invalid
    setStatus("Ready")
end sub

' Public - callable from MainScene when this screen becomes top-of-stack.
'
' NOTE: label refresh lives here, not in init(). init() runs the instant
' CreateObject("roSGNode", "SettingsScreen") is called in MainScene, which is
' BEFORE MainScene's onOpenSettings assigns screen.serverUrl/streamCodec on
' the following lines - reading those fields in init() would show stale
' (unset) values the first time the screen opens. onScreenFocus() is called
' afterward, once those fields are actually populated.
sub onScreenFocus()
    m.top.setFocus(true)
    m.top.streamCodec = normalizeCodec(m.top.streamCodec)
    updateUrlLabel()
    updateCodecLabel()
end sub

sub updateUrlLabel()
    m.urlLabel.text = m.top.serverUrl
end sub

function normalizeCodec(codec as dynamic) as string
    if codec = invalid then return "h264"
    value = LCase(codec.ToStr())
    if value = "hevc" then return "hevc"
    if value = "direct" then return "direct"
    return "h264"
end function

sub updateCodecLabel()
    if m.codecLabel = invalid then return
    codec = normalizeCodec(m.top.streamCodec)
    if codec = "h264"
        m.codecLabel.text = "H.264 (better compatibility, closed captions supported)"
    else if codec = "hevc"
        m.codecLabel.text = "HEVC / H.265 (better efficiency, closed captions unavailable)"
    else
        m.codecLabel.text = "Direct / no transcoding (experimental - may not play at all)"
    end if
end sub

sub saveStreamCodec(codec as string)
    scene = m.top.getScene()
    if scene <> invalid
        scene.callFunc("writeStreamCodec", codec)
    end if
end sub

sub toggleCodec()
    current = normalizeCodec(m.top.streamCodec)
    nextCodec = "h264"
    if current = "h264" then nextCodec = "hevc"
    if current = "hevc" then nextCodec = "direct"
    ' current = "direct" falls through to the "h264" default above, completing the cycle.

    m.top.streamCodec = nextCodec
    updateCodecLabel()
    saveStreamCodec(nextCodec)
    m.top.codecSaved = nextCodec

    if nextCodec = "h264"
        setStatus("Codec saved: H.264")
    else if nextCodec = "hevc"
        setStatus("Codec saved: HEVC")
    else
        setStatus("Codec saved: Direct (no transcoding, experimental)")
    end if
end sub

sub setStatus(text as string)
    if m.statusLabel = invalid then return
    m.statusLabel.text = text
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        if key = "left" or key = "right"
            toggleCodec()
            return true
        else if key = "OK"
            setStatus("Editing URL…")
            showKeyboard()
            return true
        else if key = "back"
            m.top.closed = true
            return true
        end if
    end if
    return false
end function

sub showKeyboard()
    ' NOTE: using the classic KeyboardDialog node here for broad firmware
    ' compatibility. StandardKeyboardDialog is the newer, visually-updated
    ' equivalent and could be swapped in if targeting only recent firmware.
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = "Server URL"
    dialog.message = "Enter the base URL of your HDHomeRun Web server, e.g. http://192.168.1.50:8080"
    dialog.buttons = ["OK", "Cancel"]
    dialog.text = m.top.serverUrl

    dialog.observeField("buttonSelected", "onKeyboardButtonSelected")

    m.keyboardDialog = dialog
    scene = m.top.getScene()
    scene.dialog = dialog
end sub

sub onKeyboardButtonSelected(event as object)
    idx = event.getData()
    dialog = m.keyboardDialog

    if idx = 0 ' "OK"
        newUrl = dialog.text
        if newUrl <> invalid and newUrl <> ""
            newUrl = trimTrailingSlash(newUrl)
            saveServerUrl(newUrl)
            m.top.serverUrl = newUrl
            updateUrlLabel()
            m.top.saved = newUrl
            runConnectivityCheck(newUrl)
        else
            setStatus("URL cannot be empty")
        end if
    else
        setStatus("Edit canceled")
    end if

    dialog.close = true
    m.keyboardDialog = invalid
end sub

function trimTrailingSlash(url as string) as string
    if Right(url, 1) = "/"
        return Left(url, Len(url) - 1)
    end if
    return url
end function

' Fires a background connectivity probe after the URL is saved and updates the
' status line with the result. Network I/O happens in UrlCheckTask, not here.
sub runConnectivityCheck(url as string)
    if m.checkTask <> invalid
        m.checkTask.control = "STOP"
        m.checkTask = invalid
    end if

    setStatus("Checking connection…")
    task = CreateObject("roSGNode", "UrlCheckTask")
    task.serverUrl = url
    task.observeField("result", "onCheckResult")
    m.checkTask = task
    task.control = "RUN"
end sub

sub onCheckResult(event as object)
    m.checkTask = invalid
    res = event.getData()
    if res = invalid or res.success <> true
        detail = ""
        if res <> invalid and res.error <> invalid and res.error <> ""
            detail = " (" + res.error + ")"
        end if
        setStatus("Saved — can't reach server" + detail)
    else
        setStatus("Saved — connected")
    end if
end sub

sub saveServerUrl(url as string)
    scene = m.top.getScene()
    if scene <> invalid
        scene.callFunc("writeServerUrl", url)
    end if
end sub
