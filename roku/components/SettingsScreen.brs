' SettingsScreen - lets the user view/edit the server base URL, persisted to
' the Roku registry (section "hdhrweb", key "serverUrl").
'
' This screen has no focusable children of its own; it grabs focus itself and
' handles OK (open keyboard) / Back (close) directly via onKeyEvent, which is
' simple and sufficient for a single-field settings screen.

sub init()
    m.urlLabel = m.top.findNode("urlLabel")
    m.statusLabel = m.top.findNode("statusLabel")
    updateUrlLabel()
    setStatus("Ready")
    onScreenFocus()
end sub

' Public - callable from MainScene when this screen becomes top-of-stack.
sub onScreenFocus()
    m.top.setFocus(true)
end sub

sub updateUrlLabel()
    m.urlLabel.text = m.top.serverUrl
end sub

sub setStatus(text as string)
    if m.statusLabel = invalid then return
    m.statusLabel.text = text
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        if key = "OK"
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
            setStatus("Saved")
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

sub saveServerUrl(url as string)
    scene = m.top.getScene()
    if scene <> invalid
        scene.callFunc("writeServerUrl", url)
    end if
end sub
