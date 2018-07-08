local awful = require("awful")
local wibox = require("wibox")

return function(command, period, numerators, denominators, base_color, threshold, threshold_color, widget_options)
    return wibox.container.mirror(awful.widget.watch(command, period, function(w, stdout)
        local numerator, denominator, current_position = 0, 0, 0

        stdout:gsub("%d+", function(value)
            current_position = current_position + 1
            numerator = numerator + (numerators[current_position] or 0) * value
            denominator = denominator + (denominators[current_position] or 0) * value
        end)

        local change_denominator = denominator + (denominators.previous or 0) * (w.denominator or 0)
        local change_numerator   =   numerator + (  numerators.previous or 0) * (  w.numerator or 0)
        w.denominator, w.numerator = denominator, numerator

        w:set_color(change_numerator / change_denominator > threshold and threshold_color or base_color)
        w:add_value(change_numerator / change_denominator)
    end,
    wibox.widget(setmetatable(widget_options, {__index = {
        widget = wibox.widget.graph
    }}))), {horizontal = true})
end

