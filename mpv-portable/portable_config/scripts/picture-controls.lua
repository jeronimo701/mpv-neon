-- GPU-only controls: preserve hardware decoding and video aspect ratio.
local mp=require 'mp'
local utils=require 'mp.utils'
local input=require 'mp.input'
local opts={settings_file='~~/picture-settings.json'}
require('mp.options').read_options(opts,'picture-controls')
local file=mp.command_native({'expand-path',opts.settings_file})
local numeric={['background-blur-radius']={0,128,32},brightness={-100,100,0},contrast={-100,100,0},
    saturation={-100,100,0},gamma={-100,100,0},sharpen={0,1,0},['scale-antiring']={0,1,0},['cscale-antiring']={0,1,0},
    ['deband-iterations']={1,4,1},['deband-threshold']={0,128,48},['deband-range']={1,64,16},['deband-grain']={0,128,32}}
local enums={scale={'ewa_lanczossharp','ewa_lanczos','spline36','bilinear'},cscale={'spline36','ewa_lanczos','bilinear'},
    dscale={'mitchell','spline36','bilinear'},deband={'no','yes'},['border-background']={'color','blur'}}
local enum_defaults={scale='ewa_lanczossharp',cscale='spline36',dscale='mitchell',deband='no',['border-background']='color'}
local saved={}
local function valid(k,v)
    if numeric[k] then return type(v)=='number' and v==v and v>=numeric[k][1] and v<=numeric[k][2]
        and (k~='deband-iterations' or v%1==0) end
    for _,x in ipairs(enums[k] or {}) do if v==x then return true end end
    return false
end
local function save()
    local f,err=io.open(file,'wb')
    if f then f:write(utils.format_json(saved)); f:close() else mp.msg.error(tostring(err)) end
end
local function set(k,v)
    if mp.get_property_native('user-data/picture/ab')=='before' then mp.commandv('script-message-to','picture_presets','picture-edit',k,tostring(v));return end
    if numeric[k] then v=tonumber(v) end
    if not valid(k,v) then mp.osd_message('Значение вне допустимого диапазона',3); return end
    local ok=mp.set_property_native(k,v)
    if ok then saved[k]=v; save() else mp.osd_message('Рендерер не поддерживает '..k,3) end
end
local f=io.open(file,'rb')
if f then
    local data=utils.parse_json(f:read('*a')); f:close()
    if type(data)=='table' then for k,v in pairs(data) do if valid(k,v) then saved[k]=v; mp.set_property_native(k,v) end end end
end
local function item(title,key,values)
    local items={}; local current=mp.get_property_native(key)
    if type(current)=='boolean' then current=current and 'yes' or 'no' end
    for _,v in ipairs(values) do items[#items+1]={title=tostring(v),active=tostring(current)==tostring(v),
        value={'script-message-to','picture_controls','set',key,tostring(v)}} end
    if numeric[key] then items[#items+1]={title='Ввести число…',value={'script-message-to','picture_controls','input',key,title}} end
    return {title=title..': '..tostring(current),items=items}
end
local function open(kind,title,items,footnote)
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json({type=kind,title=title,items=items,footnote=footnote}))
end
local function ambient()
    mp.commandv('script-binding','ambient/menu')
end
local function manual()
    local shaders={}
    for _,p in ipairs({{'native','Без апскейлера'},{'ravu','RAVU'},{'fsrcnnx8','FSRCNNX 8'},{'fsrcnnx16','FSRCNNX 16'},{'anime','Anime4K'}}) do
        shaders[#shaders+1]={title=p[2],value={'script-message-to','quality','select',p[1]}}
    end
    shaders[#shaders+1]={title='KrigBilateral — переключить цветность',value={'script-message-to','picture_controls','krig'}}
    shaders[#shaders+1]={title='SSimSuperRes — переключить',value={'script-message-to','quality','sharpen'}}
    open('manual-picture','Ручные настройки изображения',{
        {title='Шейдеры: апскейлер / цветность / SSim',items=shaders},
        item('Масштабирование яркости','scale',enums.scale),item('Масштабирование цветности','cscale',enums.cscale),
        item('Уменьшение изображения','dscale',enums.dscale),item('Антизвон яркости','scale-antiring',{0,0.25,0.5,0.75,1}),
        item('Антизвон цветности','cscale-antiring',{0,0.25,0.5,0.75,1}),item('Дополнительная резкость GPU','sharpen',{0,0.1,0.25,0.5,1}),
        {title='Устранение цветовых полос (deband)',items={item('Deband','deband',enums.deband),item('Проходы','deband-iterations',{1,2,3,4}),
            item('Порог','deband-threshold',{16,32,48,64,96}),item('Радиус','deband-range',{8,16,32,64}),item('Зерно','deband-grain',{0,16,32,64})}},
        {title='Цвет и яркость',items={item('Яркость','brightness',{-10,-5,0,5,10}),item('Контраст','contrast',{-10,-5,0,5,10}),
            item('Насыщенность','saturation',{-10,-5,0,5,10}),item('Гамма','gamma',{-10,-5,0,5,10})}},
        {title='Подсветка полос',value={'script-binding','picture_controls/ambient'}},
        {title='До / после — переключить',value={'script-binding','picture_presets/compare'}},
        {title='Мои пресеты изображения',value={'script-binding','picture_presets/menu'}},
        {title='Сбросить изображение и шейдеры',value={'script-message-to','picture_controls','reset'}}},
        'Настройки GPU сохраняются • Пресет заменяет цепочку шейдеров • F7')
end
mp.register_script_message('set',function(k,v) set(k,v) end)
mp.register_script_message('input',function(k,title)
    if not numeric[k] then return end
    input.get({prompt=title..' ('..numeric[k][1]..'…'..numeric[k][2]..')',default_text=mp.get_property(k),submit=function(v) set(k,v) end})
end)
mp.register_script_message('krig',function()
    if mp.get_property_native('user-data/picture/ab')=='before' then mp.commandv('script-message-to','picture_presets','picture-action','krig');return end
    local chain=mp.get_property_native('glsl-shaders',{}); local found=false
    for i=#chain,1,-1 do if chain[i]:find('KrigBilateral',1,true) then table.remove(chain,i); found=true end end
    if not found then chain[#chain+1]=mp.command_native({'expand-path','~~/shaders/KrigBilateral.glsl'}) end
    mp.set_property_native('glsl-shaders',chain); mp.osd_message('KrigBilateral: '..(found and 'выкл.' or 'вкл.'),2)
end)
mp.register_script_message('reset',function()
    if mp.get_property_native('user-data/picture/ab')=='before' then mp.commandv('script-message-to','picture_presets','picture-action','reset');return end
    for k,v in pairs(numeric) do set(k,v[3]) end
    for k,v in pairs(enum_defaults) do set(k,v) end
    mp.commandv('script-message-to','ambient','apply',utils.format_json({mode=0,brightness=80,coverage=80,blur=32,reaction='smooth'}))
    mp.commandv('script-message-to','quality','select','native'); mp.osd_message('Изображение сброшено',2)
end)
mp.register_script_message('restore-json',function(json)
    local data=utils.parse_json(json);if type(data)~='table' then return end
    for k,v in pairs(data) do if not valid(k,v) then return end end
    for k,v in pairs(data) do mp.set_property_native(k,v);saved[k]=v end
    save()
end)
mp.add_key_binding(nil,'manual',manual)
mp.add_key_binding(nil,'ambient',ambient)
