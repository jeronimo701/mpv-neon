local neon_context=dofile(require('mp').command_native({'expand-path','~~/script-modules/neon-context.lua'}))
-- GPU ambient canvas. The film is sampled separately; history/blur stay on GPU.
local mp=require 'mp'
local utils=require 'mp.utils'
local input=require 'mp.input'
local o={settings_file='~~/ambient-settings.json'}
require('mp.options').read_options(o,'ambient')
local file=mp.command_native({'expand-path',o.settings_file})
local shader=mp.command_native({'expand-path','~~/shaders/Ambient.glsl'})
local s={mode=0,brightness=80,coverage=80,blur=32,edge=50,reaction='smooth'}
local names={'Выключено — чёрные полосы','Сияние — свет от краёв','Кино — размытая сцена','Эхо — волны и след движения','Зеркало — отражённый кадр'}
local reaction={calm=0.85,smooth=0.3,immediate=0}
local ranges={mode={0,4},brightness={0,100},coverage={0,100},blur={0,128},edge={0,100}}
local active,editing=false,false
local original_aspect
local original_resize
local serial=1
local function valid(k,v)
    if k=='reaction' then return reaction[v]~=nil end
    return ranges[k] and type(v)=='number' and v==v and v>=ranges[k][1] and v<=ranges[k][2] and (k~='mode' or v%1==0)
end
local f=io.open(file,'rb')
if f then local data=utils.parse_json(f:read('*a'));f:close()
    if type(data)=='table' then for k,v in pairs(data) do if valid(k,v) then s[k]=v end end end
end
local function save()
    local out,err=io.open(file,'wb')
    if out then out:write(utils.format_json(s));out:close() else mp.msg.error(tostring(err)) end
end
local function owned(path) return path:lower():gsub('\\','/'):match('/ambient%.glsl$')~=nil end
local function chain()
    if editing then return end
    local old=mp.get_property_native('glsl-shaders',{});local next={};local count=0
    for _,p in ipairs(old) do if owned(p) then count=count+1 else next[#next+1]=p end end
    if active then next[#next+1]=shader end
    local same=#old==#next
    if same then for i,p in ipairs(old) do if p~=next[i] then same=false;break end end end
    if not same then editing=true;mp.set_property_native('glsl-shaders',next);editing=false end
end
local function publish()
    mp.set_property_native('user-data/ambient/settings',s)
    mp.set_property_bool('user-data/ambient/active',active)
end
local function params()
    local values=mp.get_property_native('glsl-shader-opts',{})
    for k in pairs(values) do if k:match('^ambient_') then values[k]=nil end end
    if active then
        local dims=mp.get_property_native('osd-dimensions',{})
        local src=mp.get_property_native('video-dec-params') or mp.get_property_native('video-params',{})
        local aspect=tonumber(src.aspect) or ((src.dw or src.w or 16)/(src.dh or src.h or 9))
        if type(original_aspect)=='number' and original_aspect>0 then aspect=original_aspect end
        local target=(dims.w or 16)/(dims.h or 9)
        -- Shader coordinates precede the renderer's rotation.
        local rotate=tonumber(src.rotate) or 0
        if rotate%180~=0 then target=1/target end
        local p={ambient_mode=s.mode,ambient_aspect=target,ambient_source=aspect,
            ambient_brightness=s.brightness/100,ambient_coverage=s.coverage/100,
            ambient_blur=s.blur,ambient_edge=s.edge/100,ambient_reaction=reaction[s.reaction],
            ambient_clock=mp.get_property_number('time-pos',0),ambient_serial=serial}
        for k,v in pairs(p) do values[k]=tostring(v) end
        if math.abs(mp.get_property_number('video-aspect-override',-2)-target)>0.000001 then mp.set_property_number('video-aspect-override',target) end
    end
    mp.set_property_native('glsl-shader-opts',values)
end
local function apply()
    local dims=mp.get_property_native('osd-dimensions',{})
    local src=mp.get_property_native('video-params')
    local want=s.mode>0 and not mp.get_property_bool('idle-active',true) and type(src)=='table' and (dims.w or 0)>0 and (dims.h or 0)>0
    if want then
        local dec=mp.get_property_native('video-dec-params') or src
        local source=tonumber(dec.aspect) or ((dec.dw or dec.w or 16)/(dec.dh or dec.h or 9))
        local override=active and original_aspect or mp.get_property_native('video-aspect-override',-2)
        if type(override)=='number' and override>0 then source=override end
        local target=dims.w/dims.h
        if (tonumber(dec.rotate) or 0)%180~=0 then target=1/target end
        want=math.abs(source-target)>0.0001
    end
    if want and not active then
        original_aspect=mp.get_property_native('video-aspect-override',-2)
        original_resize=mp.get_property_native('auto-window-resize',true)
        mp.set_property_bool('auto-window-resize',false)
    end
    if not want and active then
        mp.set_property_native('video-aspect-override',original_aspect or -2)
        mp.set_property_native('auto-window-resize',original_resize)
        original_aspect,original_resize=nil,nil
    end
    active=want
    mp.set_property('border-background','color')
    params();chain();publish()
end
local function set(k,v)
    if mp.get_property_native('user-data/picture/ab')=='before' then
        mp.commandv('script-message-to','picture_presets','ambient-edit',k,tostring(v));return
    end
    if ranges[k] then v=tonumber(v) end
    if not valid(k,v) then mp.osd_message('Подсветка: недопустимое значение',3);return end
    if s[k]==v then return end
    s[k]=v;save();apply()
end
local function choices(title,k,values)
    local items={}
    for _,p in ipairs(values) do
        items[#items+1]={title=p[2] or tostring(p[1]),active=s[k]==p[1],value={'script-message-to','ambient','set',k,tostring(p[1])}}
    end
    if k~='reaction' and k~='mode' then items[#items+1]={title='Ввести число…',value={'script-message-to','ambient','input',k,title}} end
    local label=tostring(s[k])
    if k=='mode' then label=names[s.mode+1]:match('^(.-)%s*—') or names[s.mode+1] end
    if k=='reaction' then label=({calm='Спокойно',smooth='Плавно',immediate='Сразу'})[s.reaction] end
    return {title=title..': '..label,items=items}
end
local function menu()
    local modes={};for i=0,4 do modes[#modes+1]={i,names[i+1]} end
    local items={choices('Режим','mode',modes),choices('Яркость фона, %','brightness',{{0},{25},{50},{80},{100}}),
        choices('Охват полос, %','coverage',{{0},{25},{50},{80},{100}}),choices('Размытие','blur',{{0},{8},{16},{32},{64},{96},{128}}),
        {title='Сглаживание границы: '..s.edge..'% — ползунок',value={'script-binding','ambient/edge-slider'}},
        choices('Успевает за кадром','reaction',{{'calm','Спокойно'},{'smooth','Плавно'},{'immediate','Сразу'}}),
        {title='Справка по подсветке',value={'script-message-to','player_help','topic','ambient'}}}
    neon_context.open(utils.format_json({type='ambient-settings',title='Подсветка — '..names[s.mode+1],items=items,
        footnote='GPU-эффект • Не убирает полосы внутри видео • F8'}))
end
-- Modal OSD slider, in window pixels. Background blur and seam width are independent.
local slider,slider_timer,dragging,window_dragging
local function slider_close()
    if slider_timer then slider_timer:kill();slider_timer=nil end
    if slider then slider:remove();slider=nil end
    dragging=false
    if window_dragging~=nil then mp.set_property_bool('window-dragging',window_dragging);window_dragging=nil end
    for _,key in ipairs({'edge-mouse','edge-double','edge-esc','edge-enter','edge-left','edge-right','edge-wheel-up','edge-wheel-down'}) do mp.remove_key_binding(key) end
    mp.enable_key_bindings('input_forced_ambient','allow-hide-cursor+allow-vo-dragging')
end
local function slider_geometry()
    local w,h=mp.get_osd_size()
    local width=math.min(560,w*0.85)
    return w,h,(w-width)/2,(h-170)/2,width
end
local function slider_draw()
    if not slider then return end
    local w,h,x,y,width=slider_geometry()
    local a=require('mp.assdraw').ass_new()
    a:new_event();a:pos(0,0);a:append('{\\bord0\\shad0\\1c&H2C1C14&\\1a&H10&}')
    a:draw_start();a:rect_cw(x,y,x+width,y+170);a:draw_stop()
    local left,right=x+28,x+width-28
    local pos=left+(right-left)*s.edge/100
    a:new_event();a:pos(0,0);a:append('{\\bord0\\shad0\\1c&H655344&}')
    a:draw_start();a:rect_cw(left,y+83,right,y+89);a:draw_stop()
    a:new_event();a:pos(0,0);a:append('{\\bord0\\shad0\\1c&HFFE77C&}')
    a:draw_start();a:rect_cw(left,y+83,pos,y+89);a:rect_cw(pos-5,y+75,pos+5,y+97);a:draw_stop()
    a:new_event();a:pos(x+width/2,y+20);a:an(8)
    a:append('{\\fs22\\bord0\\shad0\\1c&HFFFFFF&}Сглаживание границы: '..s.edge..'%')
    a:new_event();a:pos(x+width/2,y+118);a:an(8)
    a:append('{\\fs16\\bord0\\shad0\\1c&HD8D8D8&}Мышь / ← →: изменить · Enter / Esc: закрыть\\N0% — резкий край · 100% — широкий мягкий переход')
    slider.res_x=w;slider.res_y=h;slider.data=a.text;slider:update()
end
local function slider_mouse()
    local _,_,x,_,width=slider_geometry()
    local mx=mp.get_mouse_pos()
    set('edge',math.floor(math.max(0,math.min(100,(mx-x-28)/(width-56)*100))+0.5))
    slider_draw()
end
mp.add_key_binding(nil,'edge-slider',function()
    if slider then slider_close();return end
    mp.commandv('script-message-to','uosc','close-menu')
    window_dragging=mp.get_property_bool('window-dragging',true)
    mp.set_property_bool('window-dragging',false)
    slider=mp.create_osd_overlay('ass-events')
    mp.add_forced_key_binding('MBTN_LEFT','edge-mouse',function(e)
        if e.event=='down' or e.event=='press' then
            local _,_,x,y,width=slider_geometry();local mx,my=mp.get_mouse_pos()
            if mx<x or mx>x+width or my<y or my>y+170 then slider_close();return end
            dragging=true;slider_mouse()
        elseif e.event=='up' then if dragging then slider_mouse() end;dragging=false end
    end,{complex=true})
    mp.add_forced_key_binding('MBTN_LEFT_DBL','edge-double',function()end)
    mp.add_forced_key_binding('ESC','edge-esc',slider_close)
    mp.add_forced_key_binding('ENTER','edge-enter',slider_close)
    local function adjust(delta)return function()set('edge',math.max(0,math.min(100,s.edge+delta)));slider_draw()end end
    mp.add_forced_key_binding('LEFT','edge-left',adjust(-1),{repeatable=true})
    mp.add_forced_key_binding('RIGHT','edge-right',adjust(1),{repeatable=true})
    mp.add_forced_key_binding('WHEEL_UP','edge-wheel-up',adjust(5))
    mp.add_forced_key_binding('WHEEL_DOWN','edge-wheel-down',adjust(-5))
    -- The default script section permits moving the borderless native window.
    -- Capture the drag while the modal slider is open instead.
    mp.enable_key_bindings('input_forced_ambient','')
    slider_timer=mp.add_periodic_timer(0.04,function()if dragging then slider_mouse() else slider_draw() end end)
    slider_draw()
end)
mp.register_event('start-file',slider_close)
mp.add_key_binding(nil,'menu',menu)
mp.register_script_message('set',set)
mp.register_script_message('input',function(k,title)
    if not ranges[k] then return end
    input.get({prompt=title..' ('..ranges[k][1]..'…'..ranges[k][2]..')',default_text=tostring(s[k]),submit=function(v)set(k,v)end})
end)
local function apply_json(json,persist)
    local data=utils.parse_json(json)
    if type(data)~='table' then return end
    for k,v in pairs(data) do if not valid(k,v) then mp.msg.error('Invalid ambient preset');return end end
    for k,v in pairs(data) do s[k]=v end
    if persist then save() end;apply()
end
mp.register_script_message('apply',function(json)apply_json(json,true)end)
mp.register_script_message('preview',function(json)apply_json(json,false)end)
mp.observe_property('glsl-shaders','native',chain)
mp.observe_property('time-pos','number',function() if active then params() end end)
local last_size=''
mp.observe_property('osd-dimensions','native',function(_,d)
    if not d then return end
    local key=tostring(d.w)..':'..tostring(d.h)
    if key~=last_size then last_size=key;apply() end
end)
mp.observe_property('idle-active','bool',apply)
mp.register_event('file-loaded',function()serial=serial+1;apply()end)
mp.register_event('shutdown',function()if active then mp.set_property_native('video-aspect-override',original_aspect or -2);mp.set_property_native('auto-window-resize',original_resize) end end)
mp.add_timeout(0.5,apply)

neon_context.register({menu=menu})
