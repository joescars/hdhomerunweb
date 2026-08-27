' Shared networking helpers for Task nodes.
'
' CRITICAL: these functions must only ever be called from inside a Task node's
' thread (i.e. from a function invoked via Task control="RUN"), never from the
' render thread. They perform blocking-with-timeout HTTP calls using an
' roUrlTransfer + roMessagePort + wait() pattern so a hung connection can
' never wedge the app.

' Performs a GET request with a timeout.
' Returns an associative array: { success: boolean, code: integer, body: string, error: string }
function Net_HttpGet(url as string, timeoutMs as integer) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.SetRequest("GET")
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)

    ok = xfer.AsyncGetToString()
    if not ok
        return { success: false, code: 0, body: "", error: "Could not start GET request" }
    end if

    msg = wait(timeoutMs, port)
    if msg = invalid
        xfer.AsyncCancel()
        return { success: false, code: 0, body: "", error: "Request timed out" }
    end if

    if type(msg) = "roUrlEvent"
        code = msg.GetResponseCode()
        body = msg.GetString()
        if code >= 200 and code < 300
            return { success: true, code: code, body: body, error: "" }
        else
            return { success: false, code: code, body: body, error: "HTTP " + code.ToStr() }
        end if
    end if

    return { success: false, code: 0, body: "", error: "Unexpected response from server" }
end function

' Performs a POST request (empty body) with a timeout.
' Returns an associative array: { success: boolean, code: integer, error: string }
function Net_HttpPost(url as string, timeoutMs as integer) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)
    xfer.AddHeader("Content-Length", "0")

    ok = xfer.AsyncPostFromString("")
    if not ok
        return { success: false, code: 0, error: "Could not start POST request" }
    end if

    msg = wait(timeoutMs, port)
    if msg = invalid
        xfer.AsyncCancel()
        return { success: false, code: 0, error: "Request timed out" }
    end if

    if type(msg) = "roUrlEvent"
        code = msg.GetResponseCode()
        if code >= 200 and code < 300
            return { success: true, code: code, error: "" }
        else
            return { success: false, code: code, error: "HTTP " + code.ToStr() }
        end if
    end if

    return { success: false, code: 0, error: "Unexpected response from server" }
end function
