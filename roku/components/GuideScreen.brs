' GuideScreen - hosts the compact channel guide, kicks off channel playback,
' and opens Settings. All network I/O is delegated to GuideTask.

sub init()
    m.guideGrid = m.top.findNode("guideGrid")
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
    m.lastFocusedIndex = 0

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
            print "[GuideScreen] guide refresh failed: "; errMsg
        else
            showStatus(errMsg)
        end if
        return
    end if

    hideStatus()
    m.hasLoadedOnce = true

    serverTime = result.serverTime
    if serverTime = invalid
        now = CreateObject("roDateTime")
        serverTime = now.AsSeconds()
    end if
    slotStart = serverTime - (serverTime mod 1800)
    m.firstTimeLabel.text = formatGuideTime(slotStart)
    m.secondTimeLabel.text = formatGuideTime(slotStart + 1800)
    m.thirdTimeLabel.text = formatGuideTime(slotStart + 3600)

    applyGuideContent(result.channels, serverTime, slotStart)

    childCount = getGuideChildCount()
    if childCount <= 0 then return

    focusIndex = m.lastFocusedIndex
    if focusIndex >= childCount then focusIndex = childCount - 1
    if focusIndex < 0 then focusIndex = 0
    updateFocusedDetails(focusIndex)
end sub

sub applyGuideContent(channels as object, serverTime as integer, slotStart as integer)
    existing = m.guideGrid.content
    if existing = invalid
        m.guideGrid.content = buildGuideContent(channels, serverTime, slotStart)
        return
    end if

    existingCount = existing.GetChildCount()
    incomingCount = channels.Count()

    if existingCount <> incomingCount
        m.guideGrid.content = buildGuideContent(channels, serverTime, slotStart)
        return
    end if

    for i = 0 to incomingCount - 1
        ch = channels[i]
        row = buildGuideRow(ch, serverTime, slotStart)
        node = existing.GetChild(i)

        if node = invalid or node.ChannelNumber <> row.ChannelNumber
            m.guideGrid.content = buildGuideContent(channels, serverTime, slotStart)
            return
        end if

        if node.RowSignature <> row.RowSignature
            patchGuideRowNode(node, row)
        end if
    end for
end sub

function buildGuideContent(channels as object, serverTime as integer, slotStart as integer) as object
    root = CreateObject("roSGNode", "ContentNode")

    for each ch in channels
        chNode = root.CreateChild("ContentNode")
        chNode.AddFields(buildGuideRow(ch, serverTime, slotStart))
    end for

    return root
end function

function buildGuideRow(ch as object, serverTime as integer, slotStart as integer) as object
    current = findProgramAt(ch.programs, serverTime)
    firstSlot = findProgramAt(ch.programs, slotStart)
    secondSlot = findProgramAt(ch.programs, slotStart + 1800)
    thirdSlot = findProgramAt(ch.programs, slotStart + 3600)

    detailsTitle = current.title
    if current.episodeTitle <> ""
        detailsTitle = detailsTitle + " - " + current.episodeTitle
    end if

    rowSignature = ch.number.ToStr() + "|" + firstSlot.title + "|" + secondSlot.title + "|" + thirdSlot.title + "|" + detailsTitle + "|" + current.synopsis

    return {
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
        RowSignature: rowSignature
    }
end function

sub patchGuideRowNode(node as object, row as object)
    node.ChannelName = row.ChannelName
    node.LogoUri = row.LogoUri
    node.StreamPath = row.StreamPath
    node.Favorite = row.Favorite
    node.FirstTitle = row.FirstTitle
    node.SecondTitle = row.SecondTitle
    node.ThirdTitle = row.ThirdTitle
    node.DetailsTitle = row.DetailsTitle
    node.Synopsis = row.Synopsis
    node.RowSignature = row.RowSignature
end sub

function getGuideChildCount() as integer
    content = m.guideGrid.content
    if content = invalid then return 0
    return content.GetChildCount()
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
    idx = event.getData()
    m.lastFocusedIndex = idx
    updateFocusedDetails(idx)
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
