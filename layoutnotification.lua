local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")

local layoutNotificationInScreen = {}
local layoutNotifiedInScreen = {}
local notifyLayoutIcon = function(t)
    local screen = t.screen
    if not screen then return end
    local layout = awful.layout.get(screen)
    if layoutNotifiedInScreen[screen.index] == layout or not screen.selected_tag then
        return
    end
    layoutNotificationInScreen[screen.index] = naughty.notify{
        icon = beautiful["layout_"..awful.layout.getname(layout)],
        border_width = 0,
        margin = 0,
        timeout = 1,
        screen = screen,
        ontop = true,
        replaces_id = layoutNotificationInScreen[screen.index],
    }.id
    layoutNotifiedInScreen[screen.index] = layout
end
-- Whenever a tag is selected or unselected, try to notify
tag.connect_signal("property::selected", notifyLayoutIcon)
-- Whenever a tag layour changes, notify
tag.connect_signal("property::layout", notifyLayoutIcon)

for s in screen do
    notifyLayoutIcon(s.selected_tag)
end


local ncolmasterNotificationInScreen = {}
local notifyNcolNmaster = function(t)
    local screen = t.screen
    local text = string.format("N Master: %d\nN Column: %d", t.master_count, t.column_count)
    local notification = naughty.getById(ncolmasterNotificationInScreen[screen.index])
    if notification then
        naughty.replace_text(notification, nil, text)
        naughty.reset_timeout(notification, 0)
    else
        ncolmasterNotificationInScreen[screen.index] = naughty.notify{
            text = text,
            timeout = 3,
            screen = screen,
            replaces_id = ncolmasterNotificationInScreen[screen.index],
        }.id
    end
end

tag.connect_signal("property::master_count", notifyNcolNmaster)
tag.connect_signal("property::column_count", notifyNcolNmaster)

