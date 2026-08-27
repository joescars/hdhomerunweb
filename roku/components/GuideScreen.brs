' GuideScreen - hosts the compact channel guide, kicks off channel playback,
' and opens Settings. All network I/O is delegated to GuideTask.

sub init()
    m.guideGrid = m.top.findNode("guideGrid")
    m.hintLabel = m.top.findNode("hintLabel")
    m.detailTitle = m.top.findNode("detailTitle")
    m.detailSynopsis = m.top.findNode("detailSynopsis")
    m.statusBg = m.top.findNode("statusBg")
    m.statusLabel = m.top.findNode("statusLabel")
    m.refreshTimer = m.top.findNode("refreshTimer")
    m.firstTimeLabel = m.top.findNode("firstTimeLabel")
    m.secondTimeLabel = m.top.findNode("secondTimeLabel")
    m.thirdTimeLabel = m.top.findNode("thirdTimeLabel")

    m.hasLoadedOnce = false
    m.guideStarted = false

    m.guideGrid.observeField("itemSelected", "onChannelSelected")
    m.guideGrid.observeField("itemFocused", "onChannelFocused")

    m.refreshTimer.observeField("fire", "onRefreshTimerFire")
end sub

' Public - callable from MainScene whenever this screen becomes the visible
' top-of-stack screen (initial show, or returning from Player/Settings).
' Focus must land on the guide itself, not this screen's outer Group, or
' remote directional/OK keys won't reach the grid.
sub onScreenFocus()
    m.guideGrid.setFocus(true)
    if m.guideStarted = false
        m.guideStarted = true
        m.refreshTimer.control = "start"
        refreshGuide()
    end if
end sub

' Public - callable from MainScene (initial load, resume signal, settings save).
sub refreshGuide()
    if m.guideTask <> invalid
        ' A load is already in flight; let it finish rather than stacking
        ' requests.
        return
    end if

    if not m.hasLoadedOnce
        showStatus("Loading guide...")
    end if

    task = CreateObject("roSGNode", "GuideTask")
    task.serverUrl = m.top.serverUrl
    task.observeField("guideResult", "onGuideResult")
    task.control = "RUN"
    m.guideTask = task
end sub

sub onRefreshTimerFire(event as object)
    refreshGuide()
end sub

sub onGuideResult(event as object)
    result = event.getData()
    m.guideTask = invalid

    if result = invalid or result.success <> true
        errMsg = "Failed to load guide"
        if result <> invalid and result.errorMessage <> invalid and result.errorMessage <> ""
            errMsg = errMsg + ": " + result.errorMessage
        end if

        if m.hasLoadedOnce
            ' Don't blow away a working grid over a transient refresh
            ' failure - just show a quiet corner message briefly.
            m.hintLabel.text = errMsg
        else
            showStatus(errMsg)
        end if
        return
    end if

    hideStatus()
    m.hasLoadedOnce = true
    m.hintLabel.text = "Options ( * ) : Settings"

    serverTime = result.serverTime
    if serverTime = invalid
        now = CreateObject("roDateTime")
        serverTime = now.AsSeconds()
    end if
    slotStart = serverTime - (serverTime mod 1800)
    m.firstTimeLabel.text = formatGuideTime(slotStart)
    m.secondTimeLabel.text = formatGuideTime(slotStart + 1800)
    m.thirdTimeLabel.text = formatGuideTime(slotStart + 3600)

    m.guideGrid.content = buildGuideContent(result.channels, serverTime, slotStart)
    updateFocusedDetails(0)
end sub

function buildGuideContent(channels as object, serverTime as integer, slotStart as integer) as object
    root = CreateObject("roSGNode", "ContentNode")

    for each ch in channels
        chNode = root.CreateChild("ContentNode")
        current = findProgramAt(ch.programs, serverTime)
        firstSlot = findProgramAt(ch.programs, slotStart)
        secondSlot = findProgramAt(ch.programs, slotStart + 1800)
        thirdSlot = findProgramAt(ch.programs, slotStart + 3600)

        detailsTitle = current.title
        if current.episodeTitle <> ""
            detailsTitle = detailsTitle + " - " + current.episodeTitle
        end if

        chNode.AddFields({
            ChannelNumber: ch.number
            ChannelName: ch.name
            LogoUri: ch.logo
            StreamPath: ch.streamPath
            Favorite: ch.favorite
            FirstTitle: firstSlot.title
            SecondTitle: secondSlot.title
            ThirdTitle: thirdSlot.title
            DetailsTitle: detailsTitle
            Synopsis: current.synopsis
        })
    end for

    return root
end function

function findProgramAt(programs as object, timestamp as integer) as object
    for each program in programs
        if program.start <= timestamp and program.start + program.duration > timestamp
            return {
                title: program.title
                episodeTitle: program.episodeTitle
                synopsis: program.synopsis
            }
        end if
    end for
    return { title: "", episodeTitle: "", synopsis: "" }
end function

function formatGuideTime(epochSeconds as integer) as string
    time = CreateObject("roDateTime")
    time.FromSeconds(epochSeconds)
    time.ToLocalTime()

    hour = time.GetHours()
    minute = time.GetMinutes()
    suffix = "AM"
    if hour >= 12 then suffix = "PM"

    displayHour = hour mod 12
    if displayHour = 0 then displayHour = 12

    minuteText = minute.ToStr()
    if minute < 10 then minuteText = "0" + minuteText
    return displayHour.ToStr() + ":" + minuteText + " " + suffix
end function

' --- selection handling ---------------------------------------------------

sub onChannelSelected(event as object)
    idx = event.getData()
    tuneToChannelIndex(idx)
end sub

sub onChannelFocused(event as object)
    updateFocusedDetails(event.getData())
end sub

sub tuneToChannelIndex(chIdx as integer)
    content = m.guideGrid.content
    if content = invalid then return
    chNode = content.getChild(chIdx)
    if chNode = invalid then return

    m.top.launchPlayer = {
        channelNumber: chNode.ChannelNumber
        channelName: chNode.ChannelName
        streamPath: chNode.StreamPath
    }
end sub

sub updateFocusedDetails(index as integer)
    content = m.guideGrid.content
    if content = invalid then return
    chNode = content.getChild(index)
    if chNode = invalid then return
    m.detailTitle.text = chNode.DetailsTitle
    m.detailSynopsis.text = chNode.Synopsis
end sub

' --- status overlay ---------------------------------------------------------

sub showStatus(text as string)
    m.statusBg.visible = true
    m.statusLabel.visible = true
    m.statusLabel.text = text
end sub

sub hideStatus()
    m.statusBg.visible = false
    m.statusLabel.visible = false
end sub

' --- key handling ---------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "options"
        m.top.openSettings = true
        return true
    end if
    ' "back" is intentionally left unhandled here so the OS can exit the
    ' channel when the user backs out of the root guide screen.
    return false
end function
