' ChannelInfo - custom left-column renderer for TimeGrid, set via
' channelInfoComponentName="ChannelInfo". TimeGrid drives width/height/
' itemContent/focusPercent on this node as the user scrolls/focuses rows.

sub init()
    m.bg = m.top.findNode("bg")
    m.logo = m.top.findNode("logo")
    m.numberLabel = m.top.findNode("numberLabel")
end sub

sub onSizeChange(event as object)
    w = m.top.width
    h = m.top.height
    if w = invalid or h = invalid then return

    m.bg.width = w
    m.bg.height = h

    logoSize = h - 16
    if logoSize < 0 then logoSize = 0
    m.logo.width = logoSize
    m.logo.height = logoSize
    m.logo.translation = [8, 8]

    m.numberLabel.translation = [logoSize + 16, 0]
    m.numberLabel.width = w - logoSize - 24
    m.numberLabel.height = h
end sub

sub onContentChange(event as object)
    content = m.top.itemContent
    if content = invalid
        m.numberLabel.text = ""
        m.logo.visible = false
        return
    end if

    number = content.ChannelNumber
    if number = invalid then number = ""
    m.numberLabel.text = number

    logoUrl = content.HDSMALLICONURL
    if logoUrl <> invalid and logoUrl <> ""
        m.logo.uri = logoUrl
        m.logo.visible = true
    else
        m.logo.visible = false
    end if
end sub

sub onFocusChange(event as object)
    pct = m.top.focusPercent
    if pct >= 1.0
        m.bg.color = "0x2A4568FF"
    else
        m.bg.color = "0x142238FF"
    end if
end sub
