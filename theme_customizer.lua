local dpi = require("beautiful.xresources").apply_dpi
local theme = require("beautiful").get() or {}

theme.useless_gap   = 0

local xrdb_urxvt_font = awesome.xrdb_get_value("", "URxvt.font")
xrdb_urxvt_font = xrdb_urxvt_font and string.match( xrdb_urxvt_font, "xft:([^:]*):.*")
if xrdb_urxvt_font then
    local xrdb_urxvt_font_without_prefix = string.match(xrdb_urxvt_font, "xos4 (.*)")
    theme.font      = xrdb_urxvt_font_without_prefix or xrdb_urxvt_font
end
local xrdb_awesomewm_font = awesome.xrdb_get_value("", "awesomewm.font")
if xrdb_awesomewm_font then
    theme.font      = xrdb_awesomewm_font
end

theme.bg_normal     = "#000000" -- Black
theme.fg_normal     = "#aaaaaa" -- Clear grey

theme.bg_focus      = theme.bg_normal
theme.fg_focus      = "#E3E3E3" -- Dirty white
theme.bg_systray    = theme.bg_normal

-- Active tags switch colors
theme.taglist_bg_focus = theme.fg_normal
theme.taglist_fg_focus = theme.bg_normal

-- Border shows focus only
theme.border_width  = dpi(1)
theme.border_normal = theme.bg_normal
theme.border_focus  = theme.fg_normal
theme.border_marked = theme.border_normal
theme.border_gradient_blue = "#43c8f4"

-- Urgent is orange
theme.bg_urgent     = "#ff6600" -- Orange
theme.fg_urgent     = "#FFFFFF" -- White

-- Minimized is darker grey
theme.bg_minimize   = theme.bg_normal -- Black
theme.fg_minimize   = "#535d6c" -- Dark grey

-- Hotkeys help
theme.hotkeys_modifiers_fg = theme.fg_minimize

-- Wibar height
theme.wibar_height = dpi(18)

-- Tasklist
-- Do not show 'ontop' marker on tasklist
theme.tasklist_ontop = ''

-- Battery widget colors
theme.battery_fg_normal = theme.fg_normal
theme.battery_fg_full = theme.fg_normal
theme.battery_fg_charging = "#99ff66" -- Clear green
theme.battery_fg_critical = theme.bg_urgent

-- Display the taglist squares
local cairo = require("lgi").cairo
local gears_color = require("gears.color")

local function image_top_bottom_lines(size_w, size_h, line_width, top_color, bottom_color, corner_width, top_corners, bottom_corners)
    local img = cairo.ImageSurface(cairo.Format.ARGB32, size_w, size_h)
    local cr = cairo.Context(img)
    cr:set_line_width(line_width)
    cr:set_source(gears_color(top_color))
    cr:new_path()
    cr:move_to(0, 0)
    cr:rel_line_to(size_w, 0)
    cr:stroke()
    cr:set_source(gears_color(bottom_color))
    cr:move_to(0, size_h)
    cr:rel_line_to(size_w, 0)
    cr:stroke()

    corner_width = corner_width or line_width
    if top_corners then
        cr:set_line_width(corner_width)
        cr:set_source(gears_color(top_color))
        cr:move_to(-dpi(1), corner_width)
        cr:line_to(corner_width, -dpi(1))
        cr:move_to(size_w-corner_width, -dpi(1))
        cr:line_to(size_w+dpi(1), corner_width)
        cr:stroke()
    end
    if bottom_corners then
        cr:set_line_width(corner_width)
        cr:set_source(gears_color(bottom_color))
        cr:move_to(-dpi(1), size_h-corner_width)
        cr:line_to(corner_width, size_h+dpi(1))
        cr:move_to(size_w-corner_width, size_h+dpi(1))
        cr:line_to(size_w+dpi(1), size_h-corner_width)
        cr:stroke()
    end

    return img
end

theme.tag_width = dpi(17)
theme.stroke_width = dpi(4)
theme.taglist_squares_sel =         image_top_bottom_lines(theme.tag_width, theme.wibar_height, theme.stroke_width, theme.fg_normal, theme.fg_normal)
theme.taglist_squares_unsel =       image_top_bottom_lines(theme.tag_width, theme.wibar_height, theme.stroke_width, theme.fg_normal, theme.bg_normal)
theme.taglist_squares_sel_empty =   image_top_bottom_lines(theme.tag_width, theme.wibar_height, theme.stroke_width, theme.bg_normal, theme.bg_normal)
theme.taglist_squares_unsel_empty = image_top_bottom_lines(theme.tag_width, theme.wibar_height, theme.stroke_width, theme.bg_normal, theme.bg_normal)

-- AWESOME icon
theme.awesome_icon = require("beautiful.theme_assets").awesome_icon(
    theme.wibar_height or dpi(100), theme.bg_focus, "white" -- dpi(X) would get scaled, white because it gets darker
)

-- Master width factor
theme.master_width_factor = 0.65

-- Variables set for theming the menu:
theme.menu_bg_focus = theme.fg_normal
theme.menu_fg_focus = theme.bg_normal
theme.menu_height = dpi(15)
theme.menu_width  = dpi(160)
theme.menu_submenu_icon = nil

local gfs = require("gears.filesystem")
theme.wallpaper = gfs.get_configuration_dir() .. "/background.png"

-- Define the icon theme for application icons. If not set then the icons
-- from /usr/share/icons and /usr/share/icons/hicolor will be used.
theme.icon_theme = nil

-- Notifications: Color
local naughty = require("naughty")
naughty.config.defaults.border_color = theme.fg_minimize -- Dark grey to notice it

-- Notificatons: Max icon size and timeout with actions
local surface = require("gears.surface")
local util = require("awful.util")
theme.notification_icon_size = dpi(100)
if awesome.version == "v4.2" then
    naughty.config.notify_callback = function(args)
        if args.actions then
            args.timeout = 10
            args.hover_timeout = 30
        end

        local icon = args.icon
        if icon then
            -- Copied from naughty/core.lua
            if type(icon) == "string" and string.sub(icon, 1, 7) == "file://" then
                icon = string.sub(icon, 8)
                -- urldecode URI path
                icon = string.gsub(icon, "%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end )
            end
            if type(icon) == "string" and not gfs.file_readable(icon) then
                icon = util.geticonpath(icon, naughty.config.icon_formats, naughty.config.icon_dirs, icon_size) or icon
            end
            icon = surface.load_uncached(icon)
            -- Max size applied
            if icon and math.max(icon:get_width(), icon:get_height()) > theme.notification_icon_size then
                args.icon_size = theme.notification_icon_size
            end
            args.icon = icon
        end
        return args
    end
else
    naughty.config.notify_callback = function(args)
        if args.actions then
            args.timeout = 10
            args.hover_timeout = 30
        end
        return args
    end
end

-- Change ☛ in notifications actions for >
local textbox = require("wibox.widget.textbox")
local previous_set_markup = textbox.set_markup
function textbox:set_markup(text)
    previous_set_markup(self, text:gsub("^☛", ">"))
end

-- Separator
local function image_separator(size_w, size_h, line_width, fg_color, right, serif)
    local img = cairo.ImageSurface(cairo.Format.ARGB32, size_w, size_h)
    local cr = cairo.Context(img)
    cr:set_source(gears_color(fg_color))

    local middle
    local end_line

    cr:new_path()
    if right then
        middle = size_w*2/3
        end_line = size_w

        cr:move_to(0, 0)
        cr:line_to(middle, size_h/2)
        cr:line_to(0, size_h)
    else
        middle = size_w/3
        end_line = 0

        cr:move_to(size_w, 0)
        cr:line_to(middle, size_h/2)
        cr:line_to(size_w, size_h)
    end

    if serif then
        cr:move_to(end_line, size_h/2)
        cr:line_to(middle, size_h/2)
    end
    cr:stroke()

    return img
end

local widget = require("wibox.widget")
theme.create_separator_widget = function(right, serif)
    return widget{
        image = image_separator(theme.separator_width or theme.tag_width*3/5, theme.wibar_height, theme.stroke_width, theme.fg_normal, right, serif),
        resize = true,
        widget = widget.imagebox,
    }
end

theme.separator_widget_left         = theme.create_separator_widget(false, false)
theme.separator_widget_right        = theme.create_separator_widget(true, false)
theme.separator_widget_left_serif   = theme.create_separator_widget(false, true)
theme.separator_widget_right_serif  = theme.create_separator_widget(true, true)

return theme

