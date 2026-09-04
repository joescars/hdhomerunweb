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
    m.filterLabel = m.top.findNode("filterLabel")
    m.previewVideo = m.top.findNode("previewVideo")
    m.previewThumbnail = m.top.findNode("previewThumbnail")
    m.previewLabel = m.top.findNode("previewLabel")
    m.previewDebounceTimer = m.top.findNode("previewDebounceTimer")

    m.hasLoadedOnce = false
    m.guideStarted = false
    m.lastFocusedIndex = 0
    m.filterMode = readFilterMode()
    m.allChannels = []
    m.recentChannels = []
    m.lastServerTime = invalid
    m.lastSlotStart = invalid
    m.previewTask = invalid
    m.previewChannelNumber = invalid
    m.livePreviewEnabled = true

    m.guideGrid.observeField("itemSelected", "onChannelSelected")
    m.guideGrid.observeField("itemFocused", "onChannelFocused")

    m.refreshTimer.observeField("fire", "onRefreshTimerFire")
    m.previewDebounceTimer.observeField("fire", "onPreviewDebounceFire")
    updateFilterLabel()
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
    else
        ' Returning from Player/Settings - preview was stopped on the way
        ' out (see tuneToChannelIndex/onKeyEvent), restart it for whatever
        ' row is currently focused.
        restartPreviewDebounce()
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
    m.lastServerTime = serverTime
    m.lastSlotStart = slotStart
    m.firstTimeLabel.text = formatGuideTime(slotStart)
    m.secondTimeLabel.text = formatGuideTime(slotStart + 1800)
    m.thirdTimeLabel.text = formatGuideTime(slotStart + 3600)

    m.allChannels = result.channels
    applyCurrentFilter()

    if m.hasLoadedOnce and m.filterMode = "favorites"
        if getGuideChildCount() = 0
            print "[GuideScreen] favorites filter has no matching channels"
        end if
    end if
end sub

sub applyCurrentFilter()
    if m.lastServerTime = invalid or m.lastSlotStart = invalid then return
    channels = getFilteredChannels()
    applyGuideContent(channels)

    childCount = getGuideChildCount()
    if childCount <= 0
        m.detailTitle.text = "No channels match current filter"
        m.detailSynopsis.text = "Press Left or Right to switch between All and Favorites."
        return
    end if

    focusIndex = m.lastFocusedIndex
    if focusIndex >= childCount then focusIndex = childCount - 1
    if focusIndex < 0 then focusIndex = 0
    updateFocusedDetails(focusIndex)
    updatePreviewThumbnail(focusIndex)
end sub

function getFilteredChannels() as object
    if m.filterMode = "favorites"
        favorites = []
        for each ch in m.allChannels
            if ch.favorite = true
                favorites.Push(ch)
            end if
        end for
        return pinRecentChannels(favorites)
    end if
    return pinRecentChannels(m.allChannels)
end function

' Reorders channels so recently-watched ones (present in this list) appear
' first, in recency order, followed by the remaining channels in their
' original order. Applies within both the All and Favorites filters.
function pinRecentChannels(channels as object) as object
    if m.recentChannels = invalid or m.recentChannels.Count() = 0 then return channels

    byNumber = {}
    for each ch in channels
        byNumber[ch.number.ToStr()] = ch
    end for

    pinned = []
    usedNumbers = {}
    for each chNum in m.recentChannels
        match = byNumber[chNum]
        if match <> invalid
            pinned.Push(match)
            usedNumbers[chNum] = true
        end if
    end for

    if pinned.Count() = 0 then return channels

    rest = []
    for each ch in channels
        if usedNumbers[ch.number.ToStr()] <> true
            rest.Push(ch)
        end if
    end for

    pinned.Append(rest)
    return pinned
end function

function isRecentChannel(channelNumber as dynamic) as boolean
    if m.recentChannels = invalid or channelNumber = invalid then return false
    chStr = channelNumber.ToStr()
    for each chNum in m.recentChannels
        if chNum = chStr then return true
    end for
    return false
end function

sub onRecentChannelsChange(event as object)
    m.recentChannels = event.getData()
    if m.recentChannels = invalid then m.recentChannels = []
    if m.hasLoadedOnce then applyCurrentFilter()
end sub

sub setFilterMode(mode as string)
    if mode <> "all" and mode <> "favorites" then return
    if m.filterMode = mode then return

    m.filterMode = mode
    writeFilterMode(mode)
    m.lastFocusedIndex = 0
    updateFilterLabel()
    applyCurrentFilter()
end sub

sub updateFilterLabel()
    if m.filterLabel = invalid then return
    if m.filterMode = "favorites"
        m.filterLabel.text = "Filter: Favorites  •  *: Options"
    else
        m.filterLabel.text = "Filter: All  •  *: Options"
    end if
end sub

' --- filter persistence ---------------------------------------------------

function readFilterMode() as string
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return "all"
    if sec.Exists("guideFilter") and sec.Read("guideFilter") = "favorites"
        return "favorites"
    end if
    return "all"
end function

sub writeFilterMode(mode as string)
    if mode <> "all" and mode <> "favorites" then return
    sec = CreateObject("roRegistrySection", "hdhrweb")
    if sec = invalid then return
    sec.Write("guideFilter", mode)
    sec.Flush()
end sub

sub applyGuideContent(channels as object)
    existing = m.guideGrid.content
    if existing = invalid
        m.guideGrid.content = buildGuideContent(channels)
        return
    end if

    existingCount = existing.GetChildCount()
    incomingCount = channels.Count()

    if existingCount <> incomingCount
        m.guideGrid.content = buildGuideContent(channels)
        return
    end if

    for i = 0 to incomingCount - 1
        ch = channels[i]
        row = buildGuideRow(ch)
        node = existing.GetChild(i)

        if node = invalid or node.ChannelNumber <> row.ChannelNumber
            m.guideGrid.content = buildGuideContent(channels)
            return
        end if

        if node.RowSignature <> row.RowSignature
            patchGuideRowNode(node, row)
        end if
    end for
end sub

function buildGuideContent(channels as object) as object
    root = CreateObject("roSGNode", "ContentNode")

    for each ch in channels
        chNode = root.CreateChild("ContentNode")
        chNode.AddFields(buildGuideRow(ch))
    end for

    return root
end function

function buildGuideRow(ch as object) as object
    isRecent = isRecentChannel(ch.number)

    rowSignature = ch.number.ToStr() + "|" + ch.firstTitle + "|" + ch.secondTitle + "|" + ch.thirdTitle + "|" + ch.detailsTitle + "|" + ch.synopsis + "|" + ch.nextTitle + "|" + isRecent.ToStr() + "|" + ch.currentImage

    return {
        ChannelNumber: ch.number
        ChannelName: ch.name
        LogoUri: ch.logo
        StreamPath: "/stream/" + ch.number.ToStr() + "/h264/medium/stream.m3u8"
        Favorite: ch.favorite
        IsRecent: isRecent
        FirstTitle: ch.firstTitle
        SecondTitle: ch.secondTitle
        ThirdTitle: ch.thirdTitle
        DetailsTitle: ch.detailsTitle
        Synopsis: ch.synopsis
        NextTitle: ch.nextTitle
        CurrentImage: ch.currentImage
        RowSignature: rowSignature
    }
end function

sub patchGuideRowNode(node as object, row as object)
    node.ChannelName = row.ChannelName
    node.LogoUri = row.LogoUri
    node.StreamPath = row.StreamPath
    node.Favorite = row.Favorite
    node.IsRecent = row.IsRecent
    node.FirstTitle = row.FirstTitle
    node.SecondTitle = row.SecondTitle
    node.ThirdTitle = row.ThirdTitle
    node.DetailsTitle = row.DetailsTitle
    node.Synopsis = row.Synopsis
    node.NextTitle = row.NextTitle
    node.CurrentImage = row.CurrentImage
    node.RowSignature = row.RowSignature
end sub

function getGuideChildCount() as integer
    content = m.guideGrid.content
    if content = invalid then return 0
    return content.GetChildCount()
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
    updatePreviewThumbnail(idx)
    restartPreviewDebounce()
end sub

sub tuneToChannelIndex(chIdx as integer)
    content = m.guideGrid.content
    if content = invalid then return
    chNode = content.getChild(chIdx)
    if chNode = invalid then return

    ' Release the preview's tuner before handing off to the real player -
    ' don't hold two sessions on a potentially scarce tuner pool at once.
    stopPreview()

    channels = []
    for i = 0 to content.GetChildCount() - 1
        c = content.GetChild(i)
        if c <> invalid
            channels.Push({
                channelNumber: c.ChannelNumber
                channelName: c.ChannelName
                streamPath: c.StreamPath
                currentTitle: c.DetailsTitle
                nextTitle: c.NextTitle
            })
        end if
    end for

    m.top.launchPlayer = {
        channelNumber: chNode.ChannelNumber
        channelName: chNode.ChannelName
        streamPath: chNode.StreamPath
        currentTitle: chNode.DetailsTitle
        nextTitle: chNode.NextTitle
        channels: channels
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

' Instant (no debounce) - the program image is already fetched as part of
' the guide data, so this is just a field read, not a network request. Runs
' regardless of whether live preview is enabled, so browsing always shows
' *something* identifiable instead of a blank/black box, and is the only
' thing shown at all when live preview is off.
sub updatePreviewThumbnail(index as integer)
    if m.previewThumbnail = invalid then return
    content = m.guideGrid.content
    if content = invalid then return
    chNode = content.getChild(index)
    if chNode = invalid then return

    ' The currently-airing program's own artwork only (same data already
    ' used for the web guide - src/routes/api.js's per-program `image`) -
    ' not the channel logo. Left blank (no fallback) if a program has no
    ' artwork of its own.
    if chNode.CurrentImage <> invalid and chNode.CurrentImage <> ""
        m.previewThumbnail.uri = chNode.CurrentImage
    else
        m.previewThumbnail.uri = ""
    end if
    m.previewLabel.text = chNode.ChannelName
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

' --- live channel preview --------------------------------------------------
'
' Plays the currently-focused channel in a small preview box in the detail
' panel, so browsing shows what's actually on instead of just program text.
' Debounced (previewDebounceTimer, ~0.9s) so scrolling through rows doesn't
' spawn a transcode/tuner session per row - only the row the user actually
' pauses on gets previewed. Entirely best-effort: any failure (tuner busy,
' network, timeout) just leaves the channel logo showing (see
' updatePreviewThumbnail) rather than showing an error, since a background
' preview should never interrupt browsing.

sub restartPreviewDebounce()
    if m.livePreviewEnabled = false then return
    m.previewDebounceTimer.control = "stop"
    m.previewDebounceTimer.control = "start"
end sub

sub onLivePreviewEnabledChange(event as object)
    m.livePreviewEnabled = event.getData()
    if m.livePreviewEnabled = false
        stopPreview()
    else
        restartPreviewDebounce()
    end if
end sub

sub onPreviewDebounceFire(event as object)
    startPreviewForFocusedChannel()
end sub

sub startPreviewForFocusedChannel()
    content = m.guideGrid.content
    if content = invalid then return
    chNode = content.getChild(m.lastFocusedIndex)
    if chNode = invalid then return

    channelNumber = chNode.ChannelNumber.ToStr()
    if channelNumber = m.previewChannelNumber then return

    stopPreview()
    m.previewChannelNumber = channelNumber

    if m.previewTask = invalid
        m.previewTask = CreateObject("roSGNode", "StreamStartTask")
        m.previewTask.observeField("result", "onPreviewStreamResult")
    end if
    m.previewTask.serverUrl = m.top.serverUrl
    m.previewTask.channelNumber = channelNumber
    ' Always h264 for the preview regardless of the user's main playback
    ' codec preference - lowest-risk/most broadly compatible path (same
    ' reasoning as the caption work: h264_qsv is the one codec proven to
    ' just work), and a background preview is not the place to test Direct
    ' mode or HEVC.
    m.previewTask.codec = "h264"
    m.previewTask.profile = "low"
    m.previewTask.maxWaitMs = 10000
    m.previewTask.control = "RUN"
end sub

sub onPreviewStreamResult(event as object)
    result = event.getData()
    taskNode = event.getRoSGNode()
    if result = invalid or result.state <> "ready" then return

    ' The focused row may have moved on again while this was in flight -
    ' only apply the result if it's still for the channel we currently want.
    if taskNode = invalid or taskNode.channelNumber <> m.previewChannelNumber then return

    url = m.top.serverUrl + "/stream/" + m.previewChannelNumber + "/h264/low/stream.m3u8"
    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    content.streamFormat = "hls"
    content.live = true

    m.previewVideo.content = content
    m.previewVideo.control = "play"
    ' Video node paints solid black even with no/not-yet-started content -
    ' stays hidden (revealing previewThumbnail underneath) until there's
    ' actually something to show.
    m.previewVideo.visible = true
end sub

sub stopPreview()
    m.previewDebounceTimer.control = "stop"
    if m.previewTask <> invalid
        m.previewTask.control = "STOP"
    end if
    if m.previewChannelNumber <> invalid and m.previewChannelNumber <> ""
        requestStreamStop(m.previewChannelNumber, "h264", "low")
    end if
    m.previewVideo.visible = false
    m.previewVideo.control = "stop"
    m.previewVideo.content = invalid
    ' previewThumbnail/previewLabel are intentionally left alone - they're
    ' driven by focus (updatePreviewThumbnail), not by preview lifecycle, so
    ' the logo+name stay visible as the fallback/placeholder.
    m.previewChannelNumber = invalid
end sub

sub requestStreamStop(channelNumber as string, codec as string, profile as string)
    task = CreateObject("roSGNode", "StreamStopTask")
    task.serverUrl = m.top.serverUrl
    task.channelNumber = channelNumber
    task.codec = codec
    task.profile = profile
    task.control = "RUN"
end sub

' --- key handling ---------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "options"
        stopPreview()
        m.top.openSettings = true
        return true
    end if
    if press and key = "left"
        setFilterMode("all")
        return true
    end if
    if press and key = "right"
        setFilterMode("favorites")
        return true
    end if
    ' "back" is intentionally left unhandled here so the OS can exit the
    ' channel when the user backs out of the root guide screen.
    return false
end function
