local beautiful = require("beautiful")
-- Lain widgets (https://github.com/lcpz/lain)
local lain = safe_require("lain")
local bars  = {"▁","▂","▃","▄","▅","▆","▇","█"}
if require("lgi").Gio.unix_mounts_get and lain then
   return lain.widget.fs{
      followtag = true,
      settings  = function()
         local percentage = tonumber(fs_now["/"].percentage or 0)
         local span_begin = '<span size="larger" weight="bold" color="'..((percentage > 90) and beautiful.bg_urgent or beautiful.fg_normal)..'">'
         local span_end = '</span>'
         widget:set_markup_silently(string.format("%s ⛁ %s %s", span_begin, bars[math.floor(percentage*#bars/100)], span_end))
      end,
      notification_preset = {font = beautiful.font},
   }
else
   return false
end

