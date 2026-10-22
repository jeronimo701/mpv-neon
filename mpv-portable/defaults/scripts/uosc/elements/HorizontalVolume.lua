-- Local horizontal YouTube-like volume control; integrated with uosc hit testing.
local Element = require('elements/Element')
local HorizontalVolume = class(Element)
function HorizontalVolume:new(id, props) return Class.new(self, id, props) end
function HorizontalVolume:init(id, props)
    Element.init(self, id, props)
    self.dragging = false
end
function HorizontalVolume:on_coordinates()
    local h = self.by - self.ay
    self.track_ax, self.track_bx = self.ax + h * 1.05, self.bx - h * 1.3
    mp.set_property_native('user-data/ui-theme/volume-box', {ax=self.ax,ay=self.ay,bx=self.bx,by=self.by,
        track_ax=self.track_ax,track_bx=self.track_bx})
end
function HorizontalVolume:set_from_cursor()
    local fraction = clamp(0, (cursor.x-self.track_ax)/math.max(1,self.track_bx-self.track_ax), 1)
    mp.set_property_native('volume', round(fraction * 100))
    if fraction > 0 then mp.set_property_native('mute', false) end
end
function HorizontalVolume:on_global_mouse_move() if self.dragging then self:set_from_cursor() end end
function HorizontalVolume:on_global_mouse_leave()
    self.dragging = false
    state.horizontal_volume_dragging = false
end
function HorizontalVolume:destroy()
    state.horizontal_volume_dragging = false
    Element.destroy(self)
end
function HorizontalVolume:render()
    local visibility = self:get_visibility()
    if visibility <= 0 then return end
    local h, cy = self.by-self.ay, (self.ay+self.by)/2
    local speaker = {ax=self.ax, ay=self.ay, bx=self.track_ax-3, by=self.by}
    local track = {ax=self.track_ax-3, ay=self.ay, bx=self.track_bx+3, by=self.by}
    cursor:zone('primary_down',speaker,function() mp.commandv('cycle','mute') end)
    cursor:zone('primary_down',track,function()
        self.dragging = true
        state.horizontal_volume_dragging = true
        self:set_from_cursor()
        cursor:once('primary_up',function()
            self.dragging = false
            state.horizontal_volume_dragging = false
            request_render()
        end)
    end)
    local function step(amount)
        mp.set_property_native('volume',clamp(0,state.volume+amount,100))
        if amount > 0 then mp.set_property_native('mute',false) end
    end
    cursor:zone('wheel_up',self,function() step(options.volume_step) end)
    cursor:zone('wheel_down',self,function() step(-options.volume_step) end)
    local ass=assdraw.ass_new()
    local muted=state.mute or state.volume<=0
    ass:icon(self.ax+h*0.45,cy,h*0.72,muted and 'volume_off' or 'volume_up',
        {color=bgt,opacity=visibility,border=options.text_border*state.scale})
    local volume_color=options.menu_style=='youtube' and bgt or fg
    local size=math.max(3,4*state.scale)
    local x=self.track_ax+(self.track_bx-self.track_ax)*clamp(0,state.volume/100,1)
    ass:rect(self.track_ax,cy-size/2,self.track_bx,cy+size/2,{color=bgt,opacity=visibility*0.28,radius=size/2})
    ass:rect(self.track_ax,cy-size/2,x,cy+size/2,{color=volume_color,opacity=visibility*(muted and 0.35 or 1),radius=size/2})
    ass:circle(x,cy,4.5*state.scale,{color=volume_color,opacity=visibility})
    ass:txt(self.bx-h*0.05,cy,6,string.format('%d%%',round(state.volume)),
        {size=h*0.42,opacity=visibility,color=bgt,border=options.text_border*state.scale})
    return ass
end
return HorizontalVolume
