local Button = require('elements/Button')

---@alias ManagedButtonProps {name: string; anchor_id?: string; render_order?: number; hide?: boolean}

---@class ManagedButton : Button
local ManagedButton = class(Button)

---@param id string
---@param props ManagedButtonProps
function ManagedButton:new(id, props) return Class.new(self, id, props) --[[@as ManagedButton]] end
---@param id string
---@param props ManagedButtonProps
function ManagedButton:init(id, props)
	self.name = props.name
	---@type string | table | nil
	self.command = nil
	---@type boolean
	self.hide = nil
	---@type fun(hide: boolean) | nil
	self.on_hide = nil
	Button.init(self, id, table_assign({}, props, {on_click = function() execute_command(self.command) end}))
	self:update(buttons:get(props.name))
	self:register_disposer(buttons:subscribe(props.name, function(data) self:update(data) end))
end

function ManagedButton:update(data)
	local hide_before = self.hide
	for _, prop in ipairs({'icon', 'label', 'active', 'badge', 'command', 'tooltip', 'hide'}) do
		self[prop] = data[prop]
	end
	self.is_clickable = self.command ~= nil
	if self.hide ~= hide_before and self.on_hide then
		self.on_hide(self.hide)
	end
end

function ManagedButton:on_coordinates()
	Button.on_coordinates(self)
	if self.name == 'playback_speed' or self.name == 'more_tools' or self.name == 'youtube_settings' then
		mp.set_property_native('user-data/ui-theme/'..self.name..'-box',{ax=self.ax,ay=self.ay,bx=self.bx,by=self.by})
	end
end

return ManagedButton
