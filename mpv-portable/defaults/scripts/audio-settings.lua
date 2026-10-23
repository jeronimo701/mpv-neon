local mp=require 'mp'
local utils=require 'mp.utils'
local input=require 'mp.input'
local context=dofile(mp.command_native({'expand-path','~~/script-modules/neon-context.lua'}))
local opt={settings_file='~~/audio-settings.json'}
require('mp.options').read_options(opt,'audio-settings')
local file=mp.command_native({'expand-path',opt.settings_file})
local state={normalization='off',boost=100,night=false,renderer='auto',exclusive=false,device='auto'}
local modes={off='Выключена',dynamic='Динамическая — тихое громче',lufs='LUFS — цель −18 LUFS'}
local renderers={auto='Автоматически',wasapi='WASAPI',openal='OpenAL'}
local f=io.open(file,'rb')
if f then local saved=utils.parse_json(f:read('*a'));f:close()
    if type(saved)=='table' then
        if modes[saved.normalization] then state.normalization=saved.normalization end
        if type(saved.boost)=='number' and saved.boost>=100 and saved.boost<=400 then state.boost=saved.boost end
        if type(saved.night)=='boolean' then state.night=saved.night end
        if renderers[saved.renderer] then state.renderer=saved.renderer end
        if type(saved.exclusive)=='boolean' then state.exclusive=saved.exclusive end
        if type(saved.device)=='string' and #saved.device<2048 then state.device=saved.device end
    end
end
local function save()
    local out,err=io.open(file,'wb')
    if out then out:write(utils.format_json(state));out:close() else mp.osd_message('Не удалось сохранить звук: '..tostring(err),4) end
end
local function publish()
    mp.set_property_native('user-data/audio-settings/state',state)
    mp.set_property_bool('user-data/player-tools/night',state.night)
    mp.commandv('script-message-to','uosc','set-button','night',utils.format_json({icon='bedtime',active=state.night,
        tooltip='Ночной звук: диалоги ровнее, эффекты тише',command={'script-message-to','audio_settings','toggle-night'}}))
end
local function apply_filters()
    local chain={}
    if state.normalization=='dynamic' then chain[#chain+1]='dynaudnorm=f=250:g=9:p=0.95:m=4:r=0.16'
    elseif state.normalization=='lufs' then chain[#chain+1]='loudnorm=I=-18:TP=-1:LRA=11' end
    if state.night then chain[#chain+1]='acompressor=threshold=0.125:ratio=4:attack=20:release=250:makeup=2' end
    if state.boost~=100 then chain[#chain+1]=string.format('volume=%.4f',state.boost/100) end
    if #chain>0 then chain[#chain+1]='alimiter=limit=0.95:level=false:latency=true' end
    local existing=mp.get_property_native('af',{})
    for i=#existing,1,-1 do if existing[i].label=='neon_audio' or existing[i].label=='night' then table.remove(existing,i) end end
    mp.set_property_native('af',existing)
    if #chain>0 then
        local ok,err=mp.commandv('af','add','@neon_audio:lavfi=['..table.concat(chain,',')..']')
        if not ok then mp.osd_message('Аудиофильтр не применён: '..tostring(err),4);return false end
    end
    publish();return true
end
local function apply_output()
    if state.device~='auto' then
        local found=false
        for _,d in ipairs(mp.get_property_native('audio-device-list',{}))do if d.name==state.device then found=true end end
        if not found then state.device='auto';mp.osd_message('Сохранённое аудиоустройство недоступно — выбран вывод по умолчанию.',4) end
    end
    local old={ao=mp.get_property_native('options/ao'),exclusive=mp.get_property_native('audio-exclusive'),device=mp.get_property_native('audio-device')}
    local _,ao_error=mp.set_property('ao',state.renderer=='auto' and '' or state.renderer)
    local _,exclusive_error=mp.set_property_bool('audio-exclusive',state.exclusive and state.renderer=='wasapi')
    local _,device_error=mp.set_property('audio-device',state.device)
    if ao_error or exclusive_error or device_error then
        if old.ao then mp.set_property_native('options/ao',old.ao) end
        if old.exclusive~=nil then mp.set_property_native('audio-exclusive',old.exclusive) end
        if old.device then mp.set_property('audio-device',old.device) end
        mp.osd_message('Не удалось сменить аудиовывод; проверьте журнал.',4);return false
    end
    mp.commandv('ao-reload')
    return true
end
local menu
local function action(k,v)return {'script-message-to','audio_settings','set',k,tostring(v)}end
menu=function()
    local normal={}
    for _,id in ipairs({'off','dynamic','lufs'}) do normal[#normal+1]={title=modes[id],active=state.normalization==id,value=action('normalization',id)} end
    local gain={}
    for _,n in ipairs({100,125,150,175,200,250,300,400}) do gain[#gain+1]={title=n..'% '..(n==100 and '— без усиления' or '(+'..(n-100)..'%)'),active=state.boost==n,value=action('boost',n)} end
    gain[#gain+1]={title='Свои проценты… (100–400)',value={'script-message-to','audio_settings','boost-input'}}
    local outputs={}
    for _,id in ipairs({'auto','wasapi','openal'}) do outputs[#outputs+1]={title=renderers[id],active=state.renderer==id,value=action('renderer',id)} end
    local devices={}
    for _,d in ipairs(mp.get_property_native('audio-device-list',{})) do
        devices[#devices+1]={title=d.description or d.name,active=state.device==d.name,value=action('device',d.name)}
    end
    if #devices==0 then devices={{title='По умолчанию',value=action('device','auto')}} end
    context.open(utils.format_json({type='audio-settings',title='Звук — громкость и вывод',items={
        {title='Нормализация: '..modes[state.normalization],items=normal},
        {title='Усиление: '..state.boost..'%',items=gain},
        {title='Ночной звук — сжать динамику',active=state.night,value=action('night',not state.night)},
        {title='Что делает ночной звук?',value={'script-message-to','audio_settings','night-help'}},
        {title='Аудиорендер: '..renderers[state.renderer],items=outputs,separator=true},
        {title='WASAPI: эксклюзивный режим',active=state.exclusive,value=action('exclusive',not state.exclusive)},
        {title='Устройство вывода',items=devices},
        {title='Фактически: '..mp.get_property('current-ao','не открыт')..' · '..mp.get_property('audio-device','auto'),selectable=false},
        {title='Аудиодорожки / внешний звук',value={'script-binding','external_audio/menu'}},
    },footnote='100% усиления = оригинал · лимитер защищает от цифрового клиппинга · WASAPI Exclusive может занять устройство'}))
end
mp.register_script_message('set',function(key,value)
    local previous=utils.parse_json(utils.format_json(state))
    if key=='normalization' and modes[value] then state[key]=value
    elseif key=='boost' and tonumber(value) and tonumber(value)>=100 and tonumber(value)<=400 then state.boost=tonumber(value)
    elseif (key=='night' or key=='exclusive') and (value=='true' or value=='false') then
        state[key]=value=='true'
        if key=='exclusive' and state.exclusive then state.renderer='wasapi';state.device='auto' end
    elseif key=='renderer' and renderers[value] then state[key]=value;state.device='auto';if value~='wasapi' then state.exclusive=false end
    elseif key=='device' then
        local valid=value=='auto'
        for _,d in ipairs(mp.get_property_native('audio-device-list',{})) do if d.name==value then valid=true end end
        if not valid then return end
        state.device=value
        local backend=value:match('^([^/]+)')
        if backend=='wasapi' or backend=='openal' then state.renderer=backend;if backend~='wasapi' then state.exclusive=false end end
    else return end
    local ok
    if key=='renderer' or key=='device' or key=='exclusive' then ok=apply_output() else ok=apply_filters() end
    if ok then save() else
        state=previous
        if key~='renderer' and key~='device' and key~='exclusive' then apply_filters() end
        publish()
    end
    menu()
end)
mp.register_script_message('toggle-night',function()
    state.night=not state.night
    if apply_filters() then save() else state.night=not state.night;apply_filters() end
end)
mp.register_script_message('boost-input',function()
    input.get({prompt='Усиление в % (100–400; 100 — оригинал)',default_text=tostring(state.boost),submit=function(value)
        local n=tonumber(value)
        if n and n>=100 and n<=400 then mp.commandv('script-message-to','audio_settings','set','boost',tostring(n))
        else mp.osd_message('Введите число от 100 до 400.',3) end
    end})
end)
mp.register_script_message('night-help',function()
    mp.osd_message('Ночной звук сжимает динамику: диалоги слышнее, взрывы тише.\nНе заменяет нормализацию разных записей.\nУсиление задаётся отдельно; 100% — без усиления.',9)
end)
mp.add_key_binding(nil,'menu',menu)
mp.register_script_message('publish',publish)
mp.observe_property('current-ao','string',function()
    if mp.get_property_native('user-data/uosc/menu/type')=='audio-settings' then mp.add_timeout(0.15,menu) end
end)
context.register({menu=menu})
mp.add_timeout(0.4,function() apply_filters();if state.renderer~='auto' or state.device~='auto' or state.exclusive then apply_output() end end)
