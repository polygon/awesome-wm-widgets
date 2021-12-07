local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local wibox = require("wibox")
local watch = require("awful.widget.watch")
local gears = require("gears")
local spawn = require("awful.spawn")
local json = require("json.json")

local HOME = os.getenv("HOME")
local WIDGET_DIR = HOME .. '/.config/awesome/awesome-wm-widgets/hue-widget'

local XINPUT = 'xinput'

local hue_widget = {}

local pinger = {
	host = nil,
	cb = nil,
  timer = nil,

	do_ping = function(self)
		awful.spawn.easy_async("ping -n -c 1 -W 2 " .. self.host, function(_, _, _, code)
			self.cb(code == 0)
		end)
	end,

	setup = function(self, args)
		self.host = args.host
		self.cb = args.cb
		self.timer = gears.timer {
			timeout = args.interval or 10,
			call_now = true,
			autostart = true,
			callback = function() self:do_ping() end
		}
	end
}

local hue_client = {
  base_call = nil,
  host = nil,
  user = nil,
  queued = {
    group_id = nil,
    is_on = nil,
    brightness = nil
  },
  update_cb = nil,
  update_timer = nil,
	update_interval = 30,
  set_timer = nil,
  updating = false,
	enabled = false,

	set_enabled = function(self, is_enabled)
		if is_enabled == self.enabled then 
			return 
		end

		if is_enabled
		then
			self.update_timer:start()
		else
			self.update_timer:stop()
		end
		self.enabled = is_enabled
	end,

	set_update_interval = function(self, update_interval)
		if self.update_interval == update_interval then 
			return 
		end

		self.update_timer.timeout = update_interval

	end,

  send_queued = function(self)
    if self.queued.group_id == nil then
      return
    end

    local data = {}
    if self.queued.is_on ~= nil then
      data.on = self.queued.is_on
    end

    if self.queued.brightness ~= nil then
      data.on = true
      data.bri = self.queued.brightness
    end

    body = json.encode(data)

    self.update_timer:again()
    awful.spawn.easy_async(self.base_call .. "/groups/" .. tostring(self.queued.group_id) .. "/action -X PUT -d '" .. body .. "'",
      function(out)
      end
    )

    self.queued = { group_id = nil, is_on = nil, brightness = nil }
  end,

  setup = function(self, args)
    self.host = args.host
    self.user = args.user
    self.base_call = "curl --insecure https://" .. self.host .. "/api/" .. self.user
    self.update_timer = gears.timer {
      timeout = args.update_timeout or 5,
      autostart = false,
      call_now = false,
      callback = function() self:do_update() end
    }
    self.set_timer = gears.timer {
      timeout = args.set_timeout or 1.0,
      callback = function() self:send_queued() end
    }
    self.update_cb = args.update_cb
  end,

  set_group = function(self, group_id, is_on, brightness)
    if self.updating then
      return
    end

    self.queued = { group_id = group_id, is_on = is_on, brightness = brightness }

    if not self.set_timer.started
    then
      self:send_queued()
      self.set_timer:start()
    end
  end,

  do_update = function(self)
    self.updating = true
    awful.spawn.easy_async(self.base_call .. "/", function(out)
      data = json.decode(out)
      self.update_cb(data)
      self.updating = false
    end)
  end
}

local function build_controls(is_on, brightness)
  local checkbox = wibox.widget {
    checked = is_on,
    color = '#777777',
    paddings = 6,
    shape = gears.shape.circle,
    forced_height = 36,
    forced_width = 36,
    border_width = 2,
    widget = wibox.widget.checkbox
  }
  local textbox = wibox.widget {
    widget = wibox.widget.textbox,
    forced_width = 64,
    text = is_on and "On" or "Off"
  }
  local slider = wibox.widget {
    bar_shape = gears.shape.rounded_rect,
    bar_height = 3,
    bar_color = '#666666',
    handle_color = '#777777',
    handle_shape = gears.shape.circle,
    forced_width = 300,
    forced_height = 36,
    widget = wibox.widget.slider,
    minimum = 0,
    maximum = 255,
    value = brightness,
  }
  local value = wibox.widget {
    widget = wibox.widget.textbox,
    forced_width = 64,
    text = brightness
  }

  local widget = wibox.widget {
    checkbox,
    textbox,
    slider,
    value,
    spacing = 5,
    fill_space = false,
    layout = wibox.layout.fixed.horizontal,
  }

  function widget:update(is_on, brightness)
    if is_on ~= nil
    then
      checkbox.checked = is_on
      textbox.text = is_on and "On" or "Off"
    end

    if brightness ~= nil
    then
      slider.value = brightness
      value.text = brightness
    end
  end

  checkbox:connect_signal("button::press",
    function()
      local is_on = not checkbox.checked
      checkbox:set_checked(is_on)
      textbox:set_text(is_on and "On" or "Off")
      widget:emit_signal("hue::set_on", is_on)
    end
  )

  slider:connect_signal("property::value",
    function(v)
      value:set_text(v.value)
      widget:emit_signal("hue::set_brightness", v.value)
    end
  )

  return widget
end

local function build_hue_group(group_id, state)
  local data = state.groups[tostring(group_id)]
  local controls = build_controls(data.action.on, data.action.bri)
  local outline = wibox.widget {
    {
      {
         widget = wibox.widget.textbox,
        text = data.name,
        align = "center"
      },
      controls,
      layout = wibox.layout.fixed.vertical,
      spacing = 5,
      fill_space = false
    },
    widget = wibox.container.background,
    bg = '#333333',
    shape = gears.shape.rounded_rect
  }
  local widget = wibox.widget {
    outline,
    widget = wibox.container.margin,
    margins = 5
  }

  function widget:update(state)
    local data = state.groups[tostring(group_id)]
    controls:update(data.action.on, data.action.bri)
  end

  outline:connect_signal("mouse::enter", function() outline:set_bg('#444444') end)
  outline:connect_signal("mouse::leave", function() outline:set_bg('#333333') end)

  controls:connect_signal("hue::set_on", function(_, is_on) hue_client:set_group(group_id, is_on, nil) end)
  controls:connect_signal("hue::set_brightness", function(_, brightness) hue_client:set_group(group_id, nil, brightness) end)

  return widget
end

local function build_popup(groups, state)
  local w = {
    spacing = 5,
    fill_space = false,
    layout = wibox.layout.fixed.vertical
  }
	local group_widgets = {}
  for _, k in ipairs(groups) do
    local g = build_hue_group(k, state)
    table.insert(group_widgets, g)
    table.insert(w, g)
  end

  local popup = awful.popup {
    widget = w,
    shape = gears.shape.rounded_rect,
    border_width = 2,
    border_color = beautiful.border_normal,
    visible = false,
		ontop = true
  }

	return popup, group_widgets
end
	
local function worker(user_args)
	local args = user_args or {}
	local size = args.size or 18

	local on_color = args.on_color or '#88ff88'
	local off_color = args.off_color or '#ff8888'

	local host = args.host
	local user = args.user
	local groups = args.groups

	local available = false
	local built = false
	local group_widgets = {}

	local popup = nil
	
	local hue_widget = wibox.widget {
		image = gears.color.recolor_image(WIDGET_DIR .. '/lamp.svg', off_color),
		widget = wibox.widget.imagebox,
		forced_height = size,
		available = false,
		popup = nil,

		is_available = function(self, avail)
		  self.image = gears.color.recolor_image(WIDGET_DIR .. '/lamp.svg', avail and on_color or off_color)
			self.available = available
		end
	}

	hue_client:setup({
		host = host,
		user = user,
    update_interval = 30,
		update_cb = function(state)
			if not built then
				popup, group_widgets = build_popup(groups, state)
				built = true
				hue_client:set_update_interval(5)
				hue_widget.popup = popup
			else
				for _, g in ipairs(group_widgets) do
					g:update(data)
				end
			end	
		end	
  })

	pinger:setup({
		host = host,
		interval = 10,
		cb = function(is_available)
			if available == is_available then
				return
			end

			available = is_available
			hue_widget:is_available(available)

			if available then
				hue_client:do_update()	-- Update immediately once available
				local interval = built and 60 or 5
				hue_client:set_update_interval(interval)
				hue_client:set_enabled(true)
			else
				hue_client:set_enabled(false)
				popup.visible = false
			end
		end
	})

	hue_widget:connect_signal("button::press", function(_,_,_,button) 
		if button == 1 then 
			if available and built then
				if popup.visible then
					hue_client:set_update_interval(60)
					popup.visible = false
				else
					hue_client:do_update()
					hue_client:set_update_interval(5)
					popup:move_next_to(mouse.current_widget_geometry)
					popup.visible = true
				end
			end
		end 
	end)
	
	return hue_widget
end

return setmetatable(hue_widget, { __call = function(_, ...)
	return worker(...)
end })
