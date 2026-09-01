sub init()
    m.titleLabel = m.top.findNode("titleLabel")
    m.subtitleLabel = m.top.findNode("subtitleLabel")
    m.bg = m.top.findNode("bg")
end sub

sub onContentChange(event as object)
    content = m.top.itemContent
    if content = invalid then return
    m.titleLabel.text = content.recordingTitle
    m.subtitleLabel.text = content.recordingSubtitle
end sub

sub onFocusChange(event as object)
    if m.top.focusPercent > 0.5
        m.bg.color = "0x38BDF8FF"
        m.titleLabel.color = "0x0A1428FF"
        m.subtitleLabel.color = "0x0A1428FF"
    else
        m.bg.color = "0x142238FF"
        m.titleLabel.color = "0xFFFFFFFF"
        m.subtitleLabel.color = "0x9CB0C4FF"
    end if
end sub
