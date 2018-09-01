-- TODO - Improve connection check and report

local awful = require("awful")
local naughty = require("naughty")
local timer   = require("gears.timer")
local wibox = require("wibox")

if type(awful.spawn("syncthing -v")) ~= "number" then
    return false
end

local syncthing = {
    options = {
        endpoint = "http://localhost:8384",
        transfer_color = "#43c8f4",
    },
    last_event = 0,
    last_status = 100,
    event_subscription = {},
    devices = {},
    device_keys = {},
    local_folders = {},
    local_folder_keys = {},
    popup_notification = nil,
    text_widget = wibox.widget{
        markup = '',
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox,
    },
    symbol_widget = wibox.widget{
        base_markup = ' <span size="larger">♺</span> ',
        markup = ' <span size="larger">♺</span> ',
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox,
    }
}
syncthing.widget = wibox.widget{
    syncthing.symbol_widget,
    syncthing.text_widget,
    layout  = wibox.layout.align.horizontal
}

syncthing.widget:connect_signal("mouse::enter", function() syncthing:update_popup_notification(true) end)
syncthing.widget:connect_signal("mouse::leave", function() syncthing:update_popup_notification(false) end)
syncthing.widget:connect_signal("button::press", function() awful.spawn({"xdg-open", syncthing.options.endpoint}) end)

local simplejson = {
    decode = function(string)
        -- FIXME: If this function is not enough, consider using regex that are
        -- able to match repetition of subpatters and apply them and some
        -- library
        local luastring = string:gsub("%[", "{"):gsub("%]", "}") -- [] inside strings -> use same approach as regex below
        luastring = luastring:gsub('("[^"]*"):', "[%1]=") -- " inside strings -> ("([^"\\]*(\\.)*)*"):
        luastring = luastring:gsub('([^\\])\\u', '%1\\\\u') -- escape unicode
        local json_fun, error = load("return "..luastring, "json string", "t", {})
        local status, ret = pcall(json_fun)
        return status and ret
    end,
}

function syncthing:get_csrf(callback)
    local found = false
    awful.spawn.with_line_callback('curl -D - -o /dev/null '..self.options.endpoint, {
        stdout = function(line)
            local csrf = line:match("Set%-Cookie: ([^\r\n]+)")
            if csrf and not found then
                found = true
                self.csrf = csrf
                if callback then
                    callback(csrf)
                end
            end
        end,
        stderr = function() end,
        output_done = function()
            if not found then
                self.csrf = nil
                if callback then
                    callback(false)
                end
            end
        end
    })
end

function syncthing:rest(path, callback, csrf_found)
    if not self.csrf and csrf_found ~= false then
        self:get_csrf(function(csrf) self:rest(path, callback, csrf) end)
        return
    end

    local XHeader = "X-"..self.csrf:gsub("=", ": ", 1)

    awful.spawn.easy_async('curl '..self.options.endpoint..'/rest/'..path..' -H "'..XHeader..'" -H "Cookie: '..self.csrf..';"',
        function(stdout, stderr, exitreason, exitcode)
            if exitcode and exitcode ~= 0 then
                self.csrf = nil
            else
                local t = simplejson.decode(stdout)
                if not t then
                    self.csrf = nil
                end
                if callback then
                    callback(t)
                end
            end
        end)
end

function syncthing:get_events(callback)
    self:rest("events?since="..tostring(self.last_event or 0), callback)
end

function syncthing:init(options)
    syncthing.options = setmetatable(options or {}, { __index = syncthing.options })

    local events_callback = nil
    events_callback = function(events)
        if events then
            local connected_devices = {}
            for k, v in pairs(self.devices) do
                connected_devices[k] = v.connected
            end

            local updated_notification = false
            local last_id = self.last_event
            for _, event in ipairs(events) do
                local handler = self.event_subscription[event.type]
                if handler then
                    handler(self, event)
                    local current_updated_notification = self:update()
                    updated_notification = updated_notification or current_updated_notification
                end
                last_id = event.id
            end

            if updated_notification then
                naughty.notify(setmetatable({
                    title = "Syncthing",
                    text = "Updated!",
                    timeout = 5
                },{__index = self.options.notification_defaults}))
            end

            for k, v in pairs(self.devices) do
                if connected_devices[k] ~= v.connected then
                    naughty.notify(setmetatable({
                        title = "Syncthing",
                        text = (v.name or k) .. (v.connected and " connected!" or " disconnected!"),
                        timeout = 5
                    },{__index = self.options.notification_defaults}))
                end
            end

            self.last_event = last_id
            self:get_events(events_callback)
        else
            timer.start_new(60, function() self:get_events(events_callback) end)
        end
    end
    syncthing:get_events(events_callback)

    return self.widget
end

syncthing.event_subscription = {
    DeviceConnected = function(self, event)
        local t = self.devices[event.data.id]
        if not t then
            t = {shared_folders = {}}
            self.devices[event.data.id] = t
        end

        t.name = event.data.deviceName
        t.connected = true

        self.device_keys = {}
        for k in pairs(self.devices) do
            table.insert(self.device_keys, k)
        end
        table.sort(self.device_keys)
    end,

    DeviceDisconnected = function(self, event)
        local t = self.devices[event.data.id]
        if not t then
            t = {shared_folders = {}}
            self.devices[event.data.id] = t
        end

        self.devices[event.data.id].connected = false
    end,

    FolderCompletion = function(self, event)
        -- Generated when the local or remote contents for a folder changes.
        local t = self.devices[event.data.device]
        if not t then
            t = {shared_folders = {}}
            self.devices[event.data.device] = t
        end

        t.shared_folders[event.data.folder] = {
            completion = tonumber(event.data.completion),
            timestamp = os.time(),
        }

        t.connected = true
    end,

    FolderSummary = function(self, event)
        -- Generated when folder contents have changed locally.
        self.local_folders[event.data.folder] = {
            completion = event.data.summary.globalBytes > 0 and (event.data.summary.inSyncBytes * 100 / event.data.summary.globalBytes) or 100,
            timestamp = os.time(),
        }
        self.local_folder_keys = {}
        for k in pairs(self.local_folders) do
            table.insert(self.local_folder_keys, k)
        end
        table.sort(self.local_folder_keys)
    end,
}

function syncthing:update()
    local min_completion_percent = 100
    local connected_devices = 0

    for id, device in pairs(self.devices) do
        if device.connected then
            connected_devices = connected_devices + 1
            for _, folder in pairs(device.shared_folders) do
                local shared_folder_completion = folder.completion
                min_completion_percent = math.min(min_completion_percent, shared_folder_completion)
            end
        end
    end

    for _, folder in pairs(self.local_folders) do
        local local_folder_completion = folder.completion
        min_completion_percent = math.min(min_completion_percent, local_folder_completion)
    end

    self.text_widget:set_markup(string.format("%s%i%s ",
        min_completion_percent < 100 and ('<span color="'..self.options.transfer_color..'">') or '',
        connected_devices,
        min_completion_percent < 100 and string.format(': %.0f%%</span>', min_completion_percent) or '')
    )
    self.symbol_widget:set_markup(string.format("%s%s%s",
        min_completion_percent < 100 and ('<span color="'..self.options.transfer_color..'">') or '',
        self.symbol_widget.base_markup,
        min_completion_percent < 100 and '</span>' or '')
    )

    self:update_popup_notification()

    local updated_notification = min_completion_percent == 100 and self.last_status ~= 100
    self.last_status = min_completion_percent
    return updated_notification
end

function syncthing:update_popup_notification(display)
    local text = "<span weight=\"bold\">Local</span>:"
    for _, id in pairs(self.local_folder_keys) do
        local local_folder_completion = self.local_folders[id].completion
        text = text..string.format("\n  %s%s: %2.0f%%%s",
        local_folder_completion < 100 and ('<span color="'..self.options.transfer_color..'">') or '',
        id, local_folder_completion,
        local_folder_completion < 100 and '</span>' or '')
    end
    for _, key in ipairs(self.device_keys) do
        local device = self.devices[key]
        text = text.."\n<span weight=\"bold\">"..(device.name or key).."</span>:"
        if device.connected then
            for id, folder in pairs(device.shared_folders) do
                local shared_folder_completion = folder.completion
                text = text..string.format("\n  %s%s: %2.0f%%%s",
                shared_folder_completion < 100 and ('<span color="'..self.options.transfer_color..'">') or '',
                id, shared_folder_completion,
                shared_folder_completion < 100 and '</span>' or '')
            end
        else
            text = text.." <span weight=\"bold\">X</span>"
        end
    end

    local notification = naughty.getById(self.popup_notification)
    if notification then
        if display == false then
            naughty.destroy(notification)
        else
            naughty.replace_text(notification, nil, text)
        end
    elseif display then
        self.popup_notification = naughty.notify(setmetatable({
            text = text,
            timeout = 0,
            replaces_id = self.popup_notification,
        }, { __index = self.options.notification_defaults})).id
    end
end

return function(...) return syncthing:init(...) end

