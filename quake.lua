-- Started from http://awesome.naquadah.org/wiki/Drop-down_terminal , completely modified

-- local quake = require("quake")
-- local quakeconsole = {}
-- for s in screen do
--    quakeconsole[s] = quake({ terminal = config.terminal, height = 0.3, screen = s })
--    s:connect_signal("removed", function() quakeconsoles[s] = nil end)
-- end
-- config.keys.global = awful.util.table.join(config.keys.global,
--    awful.key({ modkey }, "?", function () quakeconsole[mouse.screen]:toggle() end)
-- )

local awful     = require("awful")
local beautiful = require("beautiful")
local timer     = require("gears.timer")

local QuakeConsole = {
    height   = 0.25,
    width    = 1,
    vert     = "top",
    horiz    = "center",
    screen   = nil,
    terminal = "urxvt",
}

local factors = setmetatable({
    left = 0,
    right = 1,
    top = 0,
    bottom = 1,
}, { __index = function() return 0.5 end})

function QuakeConsole:resize()
    local client = self.client
    if not client then return end

    client.floating = true
    client.size_hints_honor = false
    client.border_width = beautiful.border_width

    local geom = client.screen.workarea
    local width, height = self.width, self.height
    width = width <= 1 and geom.width * width or width
    height = height <= 1 and geom.height * height or height
    client:geometry{
        x = geom.x + factors[self.horiz] * (geom.width - width),
        y = geom.y + factors[self.vert] * (geom.height - height),
        width = width - 2 * client.border_width,
        height = height - 2 * client.border_width,
    }
end

-- Display
function QuakeConsole:toggle(show_it)
    if self.snid and not self.client then return end

    if not self.client then
        self.snid = awful.spawn(self.terminal, {
            screen = self.screen,
            titlebars_enabled = false,
        }, function(c) self.client = c end) -- Triggers before "manage" event
        return
    end

    -- Toggle display or move to focused screen if requested
    local expected_hidden = not show_it
    if show_it == nil then
        expected_hidden = not self.client.hidden
    end
    if not self.screen then
        local focused_screen = awful.screen.focused()
        if self.client.screen ~= focused_screen and show_it ~= false then
            self.client.screen = focused_screen
            expected_hidden = false
        end
    end
    self.client.hidden = expected_hidden

    if not self.client.hidden then
        self:resize()
        self.client:raise()
        client.focus = self.client
    end
end

-- Create a console
function QuakeConsole:new(config)
    local console = setmetatable(config, { __index = self })
    client.connect_signal("manage", function(c)
        if c and c == console.client then
            c:connect_signal("unmanage", function()
                console.client = nil
                console.snid = nil
            end)

            c:connect_signal("request::activate", function()
                console:toggle(true)
            end)

            c.ontop = true
            c.above = true
            c.skip_taskbar = true
            c.sticky = true
            c.urgent = false
            c:buttons{}
            c:keys{}
            awful.titlebar.hide(c)

            console:toggle(true)

            -- This client is untagged
            c:connect_signal("tagged", function() -- In case client is moved
                if c == console.client then -- To tag correctly in awesome reload
                    c:tags{}
                end
            end)
            -- setting c:tags{} here does not work
            timer.delayed_call(function() c:tags{} end)
        end
    end)

    awesome.connect_signal("exit", function() -- Make the client a normal one on reload
        local c = console.client
        if c then
            console.client = nil
            console.snid = nil
            c.floating = false
            c.ontop = false
            c.above = false
            c.skip_taskbar = false
            c.sticky = false
            c.urgent = false
            c:tags{c.screen.selected_tag or next(c.screen.tags)}
        end
    end)

    tag.connect_signal("property::selected", function(t)
        if console.client then console.client.border_width = beautiful.border_width end
    end)
    tag.connect_signal("property::layout", function(t)
        if console.client then console.client.border_width = beautiful.border_width end
    end)

    if config.screen then
        config.screen:connect_signal("property::workarea", function() console:resize() end)
    else
        screen.connect_signal("property::workarea", function() console:resize() end)
    end

    return console
end

function QuakeConsole:is_quake_console(c) return c and c == self.client end

return setmetatable({}, { __call = function(_, ...) return QuakeConsole:new(...) end })

