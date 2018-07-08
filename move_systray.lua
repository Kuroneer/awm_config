--[[
    Snippet (and module) for AwesomeWM 4 that sets the systray in
    the preferred primary screen (higher resolution or bigger)

    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2018.06.05
    Version: 1.0.0
    This micro code snippet is public-domain
]]

local wibox = require("wibox")
local callback = nil

local function set_systray_screen(best_screen)
    if not best_screen then
        local max_resolution = 0;
        local max_size = 0;
        for s in screen do
            local resolution = s.geometry.width * s.geometry.height
            local _name, values = next(s.outputs)
            local size = values.mm_width * values.mm_height
            if resolution > max_resolution or (resolution == max_resolution and size > max_size) then
                max_resolution = resolution
                max_size = size
                best_screen = s
            end
        end
    end
    local systray = wibox.widget.systray()
    systray:set_screen(best_screen)
    systray:emit_signal("widget::redraw_needed")
    if callback then
        callback(best_screen)
    end
end
screen.connect_signal("list", set_systray_screen)
set_systray_screen()

return function(c)
    if type(c) == "function" then
        callback = c
        set_systray_screen()
    end
end

