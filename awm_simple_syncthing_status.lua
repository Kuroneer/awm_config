local awful = require("awful")
local naughty = require("naughty")
local timer   = require("gears.timer")
local wibox = require("wibox")

local home_path = os.getenv("HOME")

if type(awful.spawn("syncthing -h")) ~= "number" then
    return false
end

local syncthing = {
    options = {
        endpoint = "http://localhost:8384",
        transfer_color = "#43c8f4",
        notification_defaults = {
            ignore_suspend = true,
        },
    },
    last_event = nil,
    last_status = 100,
    event_subscription = {},
    event_subscription_filter = "",
    devices = {},
    device_keys = {},
    local_folders = {},
    local_folder_keys = {},
    popup_notification = nil,
    text_widget = wibox.widget{
        markup = '? ',
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
                callback(csrf)
            end
        end,
        stderr = function() end,
        output_done = function()
            if not found then
                callback(nil)
            end
        end
    })
end

function syncthing:rest(path, callback)
    if not self.csrf then
        self:get_csrf(function(csrf)
            if csrf then
                self.csrf = csrf
                self:rest(path, callback)
            else
                callback(nil)
            end
        end)
        return
    end

    local XHeader = "X-"..self.csrf:gsub("=", ": ", 1)

    awful.spawn.easy_async('curl '..self.options.endpoint..'/rest/'..path..' -H "'..XHeader..'" -H "Cookie: '..self.csrf..';"',
        function(stdout, stderr, exitreason, exitcode)
            if exitcode and exitcode ~= 0 then
                self.csrf = nil
                callback(nil)
            else
                local t = simplejson.decode(stdout)
                if type(t) ~= 'table' then
                    self.csrf = nil
                end
                callback(t)
            end
        end)
end

function syncthing:get_events(callback)
    self:rest("events?since="..tostring(self.last_event)..(self.event_subscription_filter), callback)
end

function syncthing:get_last_event_id(callback)
    self:rest("events?since=0&limit=1"..(self.event_subscription_filter), callback)
end

function syncthing:get_connections(callback)
    self:rest("system/connections", callback)
end

function syncthing:get_config(callback)
    self:rest("system/config", callback)
end

function syncthing:get_status(callback)
    self:rest("system/status", callback)
end

function syncthing:get_completions(callback, folders_to_check)
    local folder_to_check = table.remove(folders_to_check)
    local folder_device = folder_to_check[1]
    local folder_id = folder_to_check[2]
    self:rest("db/completion?device="..folder_device.."&folder="..folder_id, function(completion)
        callback(folder_device, folder_id, completion, folders_to_check)
    end)
end

function syncthing:update_last_seen(devices)
    self:rest("stats/device", function(t)
        for id, device in pairs(devices) do
            device.lastSeen = t[id] and t[id].lastSeen
        end
    end)
end

function syncthing:init(options)

    syncthing.options = setmetatable(options or {}, { __index = syncthing.options })

    local config_callback = nil
    local events_callback = nil
    local status_callback = nil
    local connections_callback = nil
    local completion_callback = nil
    local last_event_id_callback = nil

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

            -- for k, v in pairs(self.devices) do
            --     if connected_devices[k] ~= v.connected then
            --         naughty.notify(setmetatable({
            --             title = "Syncthing",
            --             text = (v.name or k) .. (v.connected and " connected!" or " disconnected!"),
            --             timeout = 5
            --         },{__index = self.options.notification_defaults}))
            --     end
            -- end

            if updated_notification then
                naughty.notify(setmetatable({
                    title = "Syncthing",
                    text = "Updated!",
                    timeout = 5
                },{__index = self.options.notification_defaults}))
            end

            self.last_event = last_id
            self:get_events(events_callback)
        else
            timer.start_new(60, function() self:get_status(status_callback) end)
        end
    end

    completion_callback = function(folder_device, folder_id, completion, folders_to_check)
        if completion then
            self.devices[folder_device].shared_folders[folder_id].completion = completion.completion

            if #folders_to_check == 0 then
                self:update()
                self:get_events(events_callback)
            else
                self:get_completions(completion_callback, folders_to_check)
            end
        else
            timer.start_new(60, function() self:get_status(status_callback) end)
        end
    end

    connections_callback = function(connections)
        if connections then
            local folders_to_check = {}
            for deviceID, device in pairs(connections.connections) do
                self.devices[deviceID].connected = device.connected
                for id, folder in pairs(self.devices[deviceID].shared_folders) do
                    table.insert(folders_to_check, {deviceID, id, folder.label})
                end
            end

            if #folders_to_check == 0 then
                self:update()
                self:get_events(events_callback)
            else
                self:get_completions(completion_callback, folders_to_check)
            end
        else
            timer.start_new(60, function() self:get_status(status_callback) end)
        end
    end

    config_callback = function(config)
        if config then
            self:process_config(config)
            self:update_last_seen(self.devices)
            self:get_connections(connections_callback)
        else
            timer.start_new(60, function() self:get_status(status_callback) end)
        end
    end

    last_event_id_callback = function(events)
        if events then
            for _, event in ipairs(events) do
                self.last_event = event.id
            end

            self:get_config(config_callback)
        else
            timer.start_new(60, function() self:get_status(status_callback) end)
        end
    end

    status_callback = function(status)
        if status then
            self.myId = status.myID
            self:get_last_event_id(last_event_id_callback)
        else
            timer.start_new(60, function() self:get_status(status_callback) end)
        end
    end
    self:get_status(status_callback)

    return self.widget
end

function syncthing:process_config(config)
    -- If some config related to a device changes, the device reconnects
    self.device_keys = {}
    local old_devices = self.devices
    local old_devices_shared_folders = {}
    self.devices = {}
    for _, device in pairs(config.devices) do
        local t = old_devices[device.deviceID] or {shared_folders = {}}

        old_devices_shared_folders[device.deviceID] = t.shared_folders
        t.shared_folders = {}

        self.devices[device.deviceID] = t
        t.name = device.name
        if device.deviceID ~= self.myId then
            table.insert(self.device_keys, device.deviceID)
        end
    end
    table.sort(self.device_keys)

    self.local_folder_keys = {}
    local old_local_folders = self.local_folders
    self.local_folders = {}
    for _, folder in pairs(config.folders) do
        local f = old_local_folders[folder.id] or {completion = 100}
        self.local_folders[folder.id] = f

        f.label = folder.label
        f.path = folder.path
        if home_path then
            local start, finish = string.find(f.path, home_path, 1, true)
            if finish then
                f.path = "~"..string.sub(f.path, finish+1)
            end
        end

        table.insert(self.local_folder_keys, folder.id)

        for _, device in pairs(folder.devices) do
            local shared_folder = old_devices_shared_folders[device.deviceID][folder.id] or {completion = 100}
            self.devices[device.deviceID].shared_folders[folder.id] = shared_folder
            shared_folder.label = folder.label
        end
    end
    table.sort(self.local_folder_keys)
end

syncthing.event_subscription = {
    ConfigSaved = function(self, event)
        self:process_config(event.data)
    end,

    DeviceConnected = function(self, event)
        local t = self.devices[event.data.id]
        t.shared_folders = {}
        t.name = event.data.deviceName
        t.connected = true
    end,

    DeviceDisconnected = function(self, event)
        self.devices[event.data.id].connected = false
        self:update_last_seen(self.devices)
    end,

    FolderCompletion = function(self, event)
        -- This event is fired after a device is connected too
        local t = self.devices[event.data.device]
        if not t then return end

        t.connected = true
        t.last_event_time = event.time
        local f = t.shared_folders[event.data.folder]
        if not f then
            f = {label = self.local_folders[event.data.folder].label}
            t.shared_folders[event.data.folder] = f
        end

        local current_timestamp = os.time()
        local time_elapsed = current_timestamp - (f.timestamp or current_timestamp)
        local bytes_transferred = (f.need_bytes or 0) - event.data.needBytes

        f.completion = tonumber(event.data.completion)
        f.timestamp = current_timestamp;
        f.need_bytes = event.data.needBytes

        if f.completion >= 100 or f.need_bytes == 0 then
            f.speed = nil
            f.estimation = nil
        elseif bytes_transferred >= 0 and time_elapsed > 0 then
            f.speed = bytes_transferred / time_elapsed
            if f.speed > 0 then
                f.estimation = f.need_bytes / f.speed
            end
        end
    end,

    FolderSummary = function(self, event)
        -- Generated when folder contents have changed locally.
        local current_timestamp = os.time()
        local f = self.local_folders[event.data.folder]
        if not f then return end

        local time_elapsed = current_timestamp - (f.timestamp or current_timestamp)
        local bytes_transferred = (f.need_bytes or 0) - event.data.summary.needBytes

        f.completion = event.data.summary.globalBytes > 0 and (event.data.summary.inSyncBytes * 100 / event.data.summary.globalBytes) or 100
        f.timestamp = current_timestamp
        f.need_bytes = event.data.summary.needBytes

        if f.completion >= 100 or f.need_bytes == 0 then
            f.speed = nil
            f.estimation = nil
        elseif bytes_transferred >= 0 and time_elapsed > 0 then
            f.speed = bytes_transferred / time_elapsed
            if f.speed > 0 then
                f.estimation = f.need_bytes / f.speed
            end
        end
    end,
}
do
    local event_types = {}
    for event_type in pairs(syncthing.event_subscription) do
        table.insert(event_types, event_type)
    end
    syncthing.event_subscription_filter = "&events="..table.concat(event_types, ',')
end

function syncthing:update()
    local min_completion_percent = 100
    local connected_devices = 0

    for id, device in pairs(self.devices) do
        if device.connected then
            connected_devices = connected_devices + 1
            for folder_id, folder in pairs(device.shared_folders) do
                if self.local_folders[folder_id] then
                    local shared_folder_completion = folder.completion
                    min_completion_percent = math.min(min_completion_percent, shared_folder_completion)
                end
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


local info_units = {"Bytes", "Kb", "Mb", "Gb"}
local function stringify_info(speed)
    local unit_index = 1;
    while speed/1024 >= 1 and unit_index < #info_units do
        speed = speed/1024
        unit_index = unit_index +1
    end
    return string.format("%.1f %s", speed, info_units[unit_index])
end
local function stringify_estimation(estimation)
    if estimation < 60 then
        return string.format("%.0fs", estimation)
    end
    local seconds = estimation % 60
    estimation = estimation / 60

    if estimation < 60 then
        return string.format("%.0f:%02.0f", estimation, seconds)
    end

    local minutes = estimation % 60
    estimation = estimation / 60

    return string.format("%.0f:%02.0f:%02.0f", math.floor(estimation), minutes, seconds)
end
local function stringify_event_time(time_estimation_string)
    if not time_estimation_string then return "" end
    local Y, m, D, H, M, S, OH, OM = string.match(time_estimation_string, "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.?%d*%+(%d+):(%d+)")

    return string.format(" (%02d/%02d/%04d %02d:%02d)", D, m, Y, H, M)
end

function syncthing:update_popup_notification(display)
    local text = "<span weight=\"bold\">Local</span>:"
    for _, id in pairs(self.local_folder_keys) do
        local folder = self.local_folders[id]
        local local_folder_completion = folder.completion
        text = text..string.format("\n  %s%s (%s): %2.2f%%%s%s",
            local_folder_completion < 100 and ('<span color="'..self.options.transfer_color..'">') or '',
            folder.label,
            folder.path,
            local_folder_completion,
            (folder.speed and folder.estimation and string.format(
                " - %s (%s @ %s/s)",
                stringify_estimation(folder.estimation),
                stringify_info(folder.need_bytes),
                stringify_info(folder.speed)
            )) or
            (folder.need_bytes and folder.need_bytes > 0 and string.format(
                " - (%s)",
                stringify_info(folder.need_bytes)
            )) or '',
            local_folder_completion < 100 and '</span>' or ''
        )
    end
    for _, key in ipairs(self.device_keys) do
        local device = self.devices[key]
        text = text.."\n<span weight=\"bold\">"..(device.name or key).."</span>"..stringify_event_time(device.connected and device.last_event_time or device.lastSeen)..":"
        if device.connected then
            for id, folder in pairs(device.shared_folders) do
                local shared_folder_completion = folder.completion
                text = text..string.format("\n  %s%s: %2.2f%%%s%s",
                    shared_folder_completion < 100 and ('<span color="'..self.options.transfer_color..'">') or '',
                    folder.label or id, shared_folder_completion,
                    (folder.speed and folder.estimation and string.format(
                        " - %s (%s @ %s/s)",
                        stringify_estimation(folder.estimation),
                        stringify_info(folder.need_bytes),
                        stringify_info(folder.speed)
                    )) or
                    (folder.need_bytes and folder.need_bytes > 0 and string.format(
                        " - (%s)",
                        stringify_info(folder.need_bytes)
                    )) or '',
                    shared_folder_completion < 100 and '</span>' or ''
                )
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

