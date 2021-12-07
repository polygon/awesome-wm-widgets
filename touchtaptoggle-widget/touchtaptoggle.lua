local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local wibox = require("wibox")
local watch = require("awful.widget.watch")
local gears = require("gears")
local spawn = require("awful.spawn")

local HOME = os.getenv("HOME")
local WIDGET_DIR = HOME .. '/.config/awesome/awesome-wm-widgets/touchtaptoggle-widget'

local touchtap_widget = {}

local XINPUT = 'xinput'

local function worker(user_args)
	local args = user_args or {}
	local size = args.size or 18

	local on_color = args.on_color or '#88ff88'
	local off_color = args.off_color or '#ff8888'

	local device_id = 0
	local property_id = 0
	local enabled = false
	
	local touchtap_widget = wibox.widget {
		image = gears.color.recolor_image(WIDGET_DIR .. '/touchtap.svg', off_color),
		widget = wibox.widget.imagebox,
		forced_height = size,
		enable = function(self)
			self.image = gears.color.recolor_image(WIDGET_DIR .. '/touchtap.svg', on_color)
		end,
		disable = function(self)
			self.image = gears.color.recolor_image(WIDGET_DIR .. '/touchtap.svg', off_color)
		end
	}

	local function toggle()
		enabled = not enabled
		if enabled
		then
			spawn.easy_async_with_shell(XINPUT .. ' set-prop ' .. device_id .. ' 345 1', function()
				touchtap_widget:enable()
			end)
		else
			spawn.easy_async_with_shell(XINPUT .. ' set-prop ' .. device_id .. ' 345 0', function()
				touchtap_widget:disable()
			end)
		end
	end

	local function initialize_property(stdout)
		property_id = string.match(stdout, "Tapping Enabled %((%d+)%)")
		toggle()
	end
	
	local function initialize_device(stdout)
		device_id = string.match(stdout, "SYNA.*Touchpad%s+id=(%d+)")
	  spawn.easy_async(XINPUT .. ' list-props ' .. device_id, function(stdout) initialize_property(stdout) end)
	end

	touchtap_widget:connect_signal("button::press", function(_,_,_,button) if button == 1 then toggle() end end)
	
	spawn.easy_async(XINPUT, function(stdout) initialize_device(stdout) end)

	return touchtap_widget
end

return setmetatable(touchtap_widget, { __call = function(_, ...)
	return worker(...)
end })
