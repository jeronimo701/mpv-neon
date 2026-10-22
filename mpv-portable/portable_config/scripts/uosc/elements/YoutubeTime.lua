local Element=require('elements/Element')
local YoutubeTime=class(Element)
function YoutubeTime:new(id,props)return Class.new(self,id,props)end
function YoutubeTime:init(id,props)Element.init(self,id,props)end
local function clock(n)
    n=math.max(0,math.floor(n or 0));local h=math.floor(n/3600)
    return h>0 and string.format('%d:%02d:%02d',h,math.floor(n/60)%60,n%60) or string.format('%d:%02d',math.floor(n/60),n%60)
end
function YoutubeTime:render()
    local visibility=self:get_visibility();if visibility<=0 then return end
    local ass=assdraw.ass_new()
    ass:txt(self.ax+4*state.scale,(self.ay+self.by)/2,4,clock(state.time)..' / '..clock(state.duration),
        {size=(self.by-self.ay)*0.36,color=bgt,opacity=visibility,border=0.6*state.scale,border_color='000000'})
    return ass
end
return YoutubeTime
