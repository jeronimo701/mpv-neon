local mp = require 'mp'
local utils = require 'mp.utils'
local defaults = {model=1,flow=50,mode=1,multiplier=2,capture=1,fps=1}
local s = {}
local opts={settings_file='~~/motion-settings.json'}
require('mp.options').read_options(opts,'motion')
local file = mp.command_native({'expand-path',opts.settings_file})
local bounds = {model={0,1},flow={25,100},mode={0,1},multiplier={2,4},capture={0,1},fps={0,1}}
local function valid(k,v)
    return bounds[k] and type(v)=='number' and v>=bounds[k][1] and v<=bounds[k][2]
        and (k=='multiplier' or v%1==0)
end
for k,v in pairs(defaults) do s[k]=v end
local f=io.open(file,'rb')
if f then
    local data=utils.parse_json(f:read('*a')); f:close()
    if type(data)=='table' then for k,v in pairs(data) do if valid(k,v) then s[k]=v end end end
end
local function send()
    mp.commandv('script-message','lsfg-native-config',tostring(s.model),tostring(s.flow),
        tostring(s.mode),tostring(s.multiplier),tostring(s.capture),tostring(s.fps))
end
local function save()
    local out,err=io.open(file,'wb')
    if out then out:write(utils.format_json(s)); out:close()
    else mp.msg.error('Не удалось сохранить LSFG: '..tostring(err)) end
end
local function select_mode(mode)
    mode=tonumber(mode)
    if mode~=0 and mode~=60 and mode~=120 then return end
    if mode>0 then mp.set_property_bool('interpolation',false); mp.set_property('video-sync','audio') end
    mp.commandv('script-message','lsfg-native-set',tostring(mode))
end
local function choices(title,key,values)
    local items={}
    for _,v in ipairs(values) do
        items[#items+1]={title=v[2] or tostring(v[1]),active=s[key]==v[1],
            value={'script-message-to','motion','setting',key,tostring(v[1])}}
    end
    return {title=title,items=items}
end
local function menu()
    local target=mp.get_property_number('user-data/lsfg/target',0)
    local items={}
    for _,p in ipairs({{0,'Выключено — оригинальная частота'},{60,'Цель 60 кадров/с'},{120,'Цель 120 кадров/с'}}) do
        items[#items+1]={title=p[2],active=target==p[1],value={'script-message-to','motion','select',tostring(p[1])}}
    end
    items[#items+1]=choices('Модель: '..(s.model==1 and 'Производительность' or 'Качество'),'model',{{0,'Качество (Balanced)'},{1,'Производительность (Performance)'}})
    items[#items+1]=choices('Flow Scale: '..s.flow..'%','flow',{{25,'25% — быстрее'},{50,'50% — баланс'},{75,'75%'},{100,'100% — тяжелее'}})
    items[#items+1]=choices('Режим: '..(s.mode==1 and 'Adaptive' or 'Fixed'),'mode',{{0,'Fixed — множитель исходного FPS'},{1,'Adaptive — цель 60/120 FPS'}})
    items[#items+1]=choices('Множитель Fixed: '..s.multiplier..'×','multiplier',{{2,'2×'},{2.5,'2.5×'},{3,'3×'},{4,'4×'}})
    items[#items+1]=choices('Захват: '..(s.capture==1 and 'WGC' or 'DXGI'),'capture',{{1,'WGC'},{0,'DXGI'}})
    items[#items+1]=choices('Счётчик FPS: '..(s.fps==1 and 'вкл.' or 'выкл.'),'fps',{{1,'Включить'},{0,'Выключить'}})
    items[#items+1]={title='Сбросить настройки LSFG',value={'script-message-to','motion','reset'}}
    items[#items+1]={title='Проверить DLL и частоту экрана',value={'script-message','lsfg-native-probe'}}
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json({type='motion',title='Плавность — Lossless Scaling DLL',items=items,
        footnote='Состояние: '..mp.get_property_native('user-data/lsfg/status','неизвестно')..' • Fixed: цель не ограничивает FPS • F6'}))
end
mp.add_key_binding(nil,'menu',menu)
mp.register_script_message('select',select_mode)
mp.register_script_message('setting',function(k,v)
    v=tonumber(v); if not valid(k,v) then return end
    s[k]=v; save(); send(); menu()
end)
mp.register_script_message('reset',function() for k,v in pairs(defaults) do s[k]=v end; save(); send(); menu() end)
mp.observe_property('user-data/lsfg/backend','native',function(_,v) if v=='native-plugin-ready' then send() end end)
mp.add_timeout(0.5,send)
mp.observe_property('user-data/lsfg/status','native',function(_,v)
    if v=='active' then mp.osd_message('LSFG: захват активен • '..(s.mode==1 and 'Adaptive' or ('Fixed '..s.multiplier..'×')),3) end
end)
mp.observe_property('user-data/lsfg/error','native',function(_,v) if v and v~='' then mp.msg.warn(v) end end)
