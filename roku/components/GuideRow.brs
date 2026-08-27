sub init()
    m.background = m.top.findNode("background")
    m.channelBackground = m.top.findNode("channelBackground")
    m.channelLogo = m.top.findNode("channelLogo")
    m.channelLabel = m.top.findNode("channelLabel")
    m.firstLabel = m.top.findNode("firstLabel")
    m.secondLabel = m.top.findNode("secondLabel")
    m.thirdLabel = m.top.findNode("thirdLabel")
end sub

sub onSizeChange(event as object)
    m.background.width = m.top.width
    m.background.height = m.top.height
    m.channelBackground.height = m.top.height
end sub

sub onContentChange(event as object)
    content = m.top.itemContent
    if content = invalid then return

    logoUri = content.LogoUri
    if logoUri <> invalid and logoUri <> ""
        m.channelLogo.uri = logoUri
        m.channelLogo.visible = true
    else
        m.channelLogo.uri = ""
        m.channelLogo.visible = false
    end if
    m.channelLabel.text = content.ChannelName
    m.firstLabel.text = content.FirstTitle
    m.secondLabel.text = content.SecondTitle
    m.thirdLabel.text = content.ThirdTitle
end sub

sub onFocusChange(event as object)
    if m.top.focusPercent > 0.5
        m.background.color = "0xE2E8F0FF"
        m.channelBackground.color = "0x38BDF8FF"
        setTextColor("0x0A1428FF")
    else
        m.background.color = "0x101820FF"
        m.channelBackground.color = "0x142238FF"
        setTextColor("0xE2E8F0FF")
    end if
end sub

sub setTextColor(color as string)
    m.channelLabel.color = color
    m.firstLabel.color = color
    m.secondLabel.color = color
    m.thirdLabel.color = color
end sub
