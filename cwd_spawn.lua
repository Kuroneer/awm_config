--[[
    Snippet (and module) for AwesomeWM 4 that spawns the terminal
    in the path of the current focused client (from the title)

    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2018.08.14
    Version: 1.0.1
    This micro code snippet is public-domain
]]

local awful = require("awful")
local gfs = require("gears.filesystem")
local home = os.getenv("HOME")

return function(max_count)
    max_count = max_count or 15
    if client.focus and client.focus.name then
        local count, path = 0, client.focus.name:match("^([~/].*)") or client.focus.name:match("[^%w]([~/].*)")
        path = path and path:gsub("^~", home)
        while count < max_count and path and path:len() > 0 do
            if gfs.dir_readable(path) then
                awful.spawn(terminal.." -cd '"..path.."'")
                return
            end
            path = path:match("(.*)[^%w][%w]*")
            count = count +1
        end
    end
    awful.spawn(terminal)
end

