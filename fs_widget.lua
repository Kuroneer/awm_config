-- Lain widgets (https://github.com/lcpz/lain)
local lain = safe_require("lain")
if require("lgi").Gio.unix_mounts_get and lain then
   local beautiful = require("beautiful")
   local wibox = require("wibox")
   local bars  = {" ","▁","▂","▃","▄","▅","▆","▇","█"}

   local symbol_widget = wibox.widget{
      align  = 'center',
      valign = 'center',
      widget = wibox.widget.textbox,
   }
   local text_widget = wibox.widget{
      align  = 'center',
      valign = 'center',
      widget = wibox.widget.textbox,
   }
   local fs_widget = wibox.widget{
      symbol_widget,
      text_widget,
      layout = wibox.layout.align.horizontal
   }

   local fs = lain.widget.fs{ -- Not visible
      followtag = true,
      settings  = function()
         local percentage = tonumber(fs_now["/"].percentage or 0)

         symbol_widget:set_markup(string.format(
            '<span color="%s"> ⛁ </span>',
            ((percentage > 90) and beautiful.bg_urgent or beautiful.fg_normal)
         ))
         text_widget:set_markup(string.format(
            '<span color="%s">%s</span> ',
            ((percentage > 90) and beautiful.bg_urgent or beautiful.fg_normal),
            bars[math.floor(percentage*(#bars-1)/100 + 1.5)]
         ))
      end,
      notification_preset = {font = beautiful.font},
   }

   fs_widget:connect_signal('mouse::enter', function() fs.show(0) end)
   fs_widget:connect_signal('mouse::leave', function() fs.hide( ) end)

   return fs_widget
else
   return false
end

