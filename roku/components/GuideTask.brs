' GuideTask - fetches GET /api/guide on a background Task thread.
'
' All network I/O happens here, never on the render thread, per SceneGraph
' rules. Set serverUrl then control="RUN" to execute.

sub init()
    m.top.functionName = "doFetch"
end sub

sub doFetch()
    base = m.top.serverUrl
    if base = invalid or base = ""
        m.top.guideResult = { success: false, errorMessage: "No server URL configured" }
        return
    end if

    url = base + "/api/guide?slim=1"
    resp = Net_HttpGet(url, 30000)
    if resp.success <> true
        resp = Net_HttpGet(url, 30000)
    end if

    if resp.success <> true
        m.top.guideResult = { success: false, errorMessage: resp.error }
        return
    end if

    json = ParseJson(resp.body)
    if json = invalid
        m.top.guideResult = { success: false, errorMessage: "Could not parse guide response" }
        return
    end if

    if json.channels = invalid
        m.top.guideResult = { success: false, errorMessage: "Guide response missing channels" }
        return
    end if

    channels = []
    for each ch in json.channels
        slots = ch.slots
        if slots = invalid or slots.Count() < 3
            m.top.guideResult = { success: false, errorMessage: "Slim guide response missing slots" }
            return
        end if
        first = slots[0]
        channels.Push({
            number: ch.number
            name: ch.name
            logo: ch.logo
            favorite: ch.favorite
            firstTitle: first.title
            secondTitle: slots[1].title
            thirdTitle: slots[2].title
            detailsTitle: formatDetailsTitle(first)
            synopsis: first.synopsis
            nextTitle: ch.nextTitle
            currentImage: first.image
        })
    end for

    m.top.guideResult = {
        success: true
        errorMessage: ""
        serverTime: json.serverTime
        channels: channels
    }
end sub

function formatDetailsTitle(program as object) as string
    if program = invalid then return ""
    title = program.title
    if title = invalid then title = ""
    episodeTitle = program.episodeTitle
    if episodeTitle <> invalid and episodeTitle <> ""
        if title <> "" then return title + " — " + episodeTitle
        return episodeTitle
    end if
    return title
end function
