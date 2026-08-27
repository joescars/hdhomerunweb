' GuideScreen - hosts the channel-by-time EPG, kicks off channel playback,
' and opens Settings. All network I/O is delegated to GuideTask.

sub init()
    m.timeGrid = m.top.findNode("timeGrid")
    m.hintLabel = m.top.findNode("hintLabel")
    m.detailTitle = m.top.findNode("detailTitle")
    m.detailSynopsis = m.top.findNode("detailSynopsis")
    m.statusBg = m.top.findNode("statusBg")
    m.statusLabel = m.top.findNode("statusLabel")
    m.refreshTimer = m.top.findNode("refreshTimer")

    m.hasLoadedOnce = false
    m.guideStarted = false

    m.timeGrid.observeField("channelSelected", "onChannelSelected")
    m.timeGrid.observeField("programSelected", "onProgramSelected")
    m.timeGrid.observeField("programFocusedDetails", "onProgramFocusedDetails")

    m.refreshTimer.observeField("fire", "onRefreshTimerFire")
end sub

' Public - callable from MainScene whenever this screen becomes the visible
' top-of-stack screen (initial show, or returning from Player/Settings).
' Focus must land on the TimeGrid itself, not this screen's outer Group, or
' remote directional/OK keys won't reach the grid.
sub onScreenFocus()
    m.timeGrid.setFocus(true)
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

    gridTime = result.serverTime
    if gridTime = invalid or gridTime <= 0
        now = CreateObject("roDateTime")
        gridTime = now.AsSeconds()
    end if
    m.timeGrid.contentStartTime = gridTime - (gridTime mod 1800)
    m.timeGrid.leftEdgeTargetTime = gridTime
    m.timeGrid.content = buildGuideContent(result.channels)
end sub

function buildGuideContent(channels as object) as object
    root = CreateObject("roSGNode", "ContentNode")

    for each ch in channels
        chNode = root.CreateChild("ContentNode")
        chNode.title = ch.name
        chNode.AddFields({
            ChannelNumber: ch.number
            StreamPath: ch.streamPath
            Favorite: ch.favorite
        })

        for each pr in ch.programs
            prNode = chNode.CreateChild("ContentNode")
            prNode.title = pr.title
            ' PLAYSTART / PLAYDURATION are "time" fields; per Roku docs/samples
            ' these accept plain integer seconds (epoch seconds for PLAYSTART,
            ' seconds for PLAYDURATION) the same way contentStartTime does -
            ' no explicit roDateTime object construction is required.
            prNode.PLAYSTART = pr.start
            prNode.PLAYDURATION = pr.duration
            prNode.AddFields({
                EpisodeTitle: pr.episodeTitle
                Synopsis: pr.synopsis
            })
        end for
    end for

    return root
end function

' --- selection handling ---------------------------------------------------

sub onChannelSelected(event as object)
    idx = event.getData()
    tuneToChannelIndex(idx)
end sub

sub onProgramSelected(event as object)
    ' programSelected only gives the program's child index; the row it
    ' belongs to is whichever channel currently has focus.
    chIdx = m.timeGrid.channelFocused
    tuneToChannelIndex(chIdx)
end sub

sub tuneToChannelIndex(chIdx as integer)
    content = m.timeGrid.content
    if content = invalid then return
    chNode = content.getChild(chIdx)
    if chNode = invalid then return

    m.top.launchPlayer = {
        channelNumber: chNode.ChannelNumber
        channelName: chNode.title
        streamPath: chNode.StreamPath
    }
end sub

sub onProgramFocusedDetails(event as object)
    details = event.getData()
    if details = invalid then return

    content = m.timeGrid.content
    if content = invalid then return

    chNode = content.getChild(details.focusChannelIndex)
    if chNode = invalid then return
    prNode = chNode.getChild(details.focusIndex)
    if prNode = invalid then return

    title = prNode.title
    if prNode.EpisodeTitle <> invalid and prNode.EpisodeTitle <> ""
        title = title + " - " + prNode.EpisodeTitle
    end if
    m.detailTitle.text = title
    m.detailSynopsis.text = prNode.Synopsis
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
