local neon_context=dofile(require('mp').command_native({'expand-path','~~/script-modules/neon-context.lua'}))
local mp=require 'mp'
local utils=require 'mp.utils'
local input=require 'mp.input'
local o={presets_file='~~/picture-presets.json'}
require('mp.options').read_options(o,'picture-presets')
local file=mp.command_native({'expand-path',o.presets_file})
local defaults={brightness=0,contrast=0,gamma=0,saturation=0,sharpen=0,['scale-antiring']=0,['cscale-antiring']=0,
    ['deband-iterations']=1,['deband-threshold']=48,['deband-range']=16,['deband-grain']=32,
    scale='ewa_lanczossharp',cscale='spline36',dscale='mitchell',deband='no'}
local limits={brightness={-100,100},contrast={-100,100},gamma={-100,100},saturation={-100,100},sharpen={0,1},
    ['scale-antiring']={0,1},['cscale-antiring']={0,1},['deband-iterations']={1,4},['deband-threshold']={0,128},['deband-range']={1,64},['deband-grain']={0,128}}
local enums={scale={ewa_lanczossharp=true,ewa_lanczos=true,spline36=true,bilinear=true},
    cscale={spline36=true,ewa_lanczos=true,bilinear=true},dscale={mitchell=true,spline36=true,bilinear=true},deband={yes=true,no=true}}
local bank={version=1,presets={}}
local storage_ok=true
local disk_snapshot
local before
local function copy(t)return utils.parse_json(utils.format_json(t))end
local function ambient_path(p)return p:lower():gsub('\\','/'):match('/ambient%.glsl$')~=nil end
local shader_root=mp.command_native({'expand-path','~~/shaders/'}):gsub('\\','/'):gsub('/+$','')
local function portable(p)
    local path=p:gsub('\\','/')
    if path:sub(1,#shader_root):lower()==shader_root:lower() and path:sub(#shader_root+1,#shader_root+1)=='/' then return '~~/shaders'..path:sub(#shader_root+1) end
    return path
end
local function snapshot()
    local state={properties={},shaders={},shader_opts={},ambient=mp.get_property_native('user-data/ambient/settings',{mode=0}),
        label=mp.get_property_native('user-data/quality/profile','custom')}
    for k in pairs(defaults) do
        local v=mp.get_property_native(k)
        if type(v)=='boolean' then v=v and 'yes' or 'no' end
        state.properties[k]=v
    end
    for _,p in ipairs(mp.get_property_native('glsl-shaders',{})) do if not ambient_path(p) then state.shaders[#state.shaders+1]=portable(p) end end
    for k,v in pairs(mp.get_property_native('glsl-shader-opts',{})) do if not k:match('^ambient_') then state.shader_opts[k]=v end end
    return copy(state)
end
local function valid(state)
    if type(state)~='table' or type(state.properties)~='table' or type(state.shaders)~='table' or type(state.ambient)~='table' then return false end
    for k,v in pairs(state.properties) do
        if limits[k] then if type(v)~='number' or v~=v or v<limits[k][1] or v>limits[k][2] or (k=='deband-iterations' and v%1~=0) then return false end
        elseif not enums[k] or not enums[k][v] then return false end
    end
    for k in pairs(defaults) do if state.properties[k]==nil then return false end end
    if #state.shaders>32 then return false end
    for _,p in ipairs(state.shaders) do
        if type(p)~='string' or ambient_path(p) or not (p:match('%.glsl$') or p:match('%.hook$')) or not utils.file_info(mp.command_native({'expand-path',p})) then return false end
    end
    if type(state.shader_opts)~='table' then return false end
    for k,v in pairs(state.shader_opts) do if type(k)~='string' or k:match('^ambient_') or type(v)~='string' or #k>128 or #v>256 then return false end end
    local ar={mode={0,4},brightness={0,100},coverage={0,100},blur={0,128},edge={0,100}}
    for k,v in pairs(state.ambient) do
        if k=='reaction' then if v~='calm' and v~='smooth' and v~='immediate' then return false end
        elseif not ar[k] or type(v)~='number' or v~=v or v<ar[k][1] or v>ar[k][2] or (k=='mode' and v%1~=0) then return false end
    end
    return true
end
local function apply(state,persist)
    if not valid(state) then mp.osd_message('Пресет повреждён или отсутствует файл шейдера',4);return false end
    for k,v in pairs(state.properties) do mp.set_property_native(k,v) end
    mp.set_property_native('glsl-shader-opts',state.shader_opts)
    mp.set_property_native('glsl-shaders',state.shaders)
    mp.set_property('user-data/quality/profile',state.label or 'custom')
    local sharp=false;for _,p in ipairs(state.shaders) do if p:find('SSimSuperRes',1,true) then sharp=true end end
    mp.set_property_bool('user-data/quality/sharpen',sharp)
    mp.commandv('script-message-to','ambient',persist and 'apply' or 'preview',utils.format_json(state.ambient))
    if persist then mp.commandv('script-message-to','picture_controls','restore-json',utils.format_json(state.properties)) end
    return true
end
local function after()
    if before then local saved=before;before=nil;mp.set_property('user-data/picture/ab','after');apply(saved,false) end
end
local function compare()
    if before then after();mp.osd_message('ПОСЛЕ — ваши настройки',2);return end
    if mp.get_property_bool('idle-active',true) then mp.osd_message('Сначала откройте видео',2);return end
    before=snapshot()
    local base={properties=copy(defaults),shaders={},shader_opts={},ambient={mode=0},label='native'}
    apply(base,false);mp.set_property('user-data/picture/ab','before')
    mp.osd_message('ДО — без улучшений картинки\nF9 — вернуть ваши настройки',3)
end
local f=io.open(file,'rb')
if f then
    disk_snapshot=f:read('*a');local data=utils.parse_json(disk_snapshot);f:close()
    if type(data)=='table' and data.version==1 and type(data.presets)=='table' then
        local ids={}
        for _,p in ipairs(data.presets) do
            if type(p)~='table' or type(p.id)~='string' or type(p.name)~='string' or type(p.state)~='table' then storage_ok=false end
            if type(p)=='table' and type(p.id)=='string' then if ids[p.id] then storage_ok=false end;ids[p.id]=true end
        end
        if storage_ok then bank=data else mp.msg.error('Invalid preset structure; writes disabled') end
    else storage_ok=false;mp.msg.error('Файл пресетов повреждён; запись заблокирована') end
end
local function save_bank()
    if not storage_ok then mp.osd_message('Файл пресетов повреждён — сохранение отменено',4);return false end
    local old=io.open(file,'rb')
    local previous
    if old then
        previous=old:read('*a');old:close()
    end
    if previous~=disk_snapshot then mp.osd_message('Файл пресетов изменён в другом окне. Перезапустите этот плеер перед сохранением.',5);return false end
    if previous then
        local backup=io.open(file..'.bak','wb')
        if not backup then mp.osd_message('Не удалось сохранить резервную копию',3);return false end
        backup:write(previous);backup:close()
    end
    local out,err=io.open(file,'wb')
    if not out then mp.osd_message(tostring(err),3);return false end
    local text=utils.format_json(bank);local ok,write_err=out:write(text);out:close()
    if not ok then mp.osd_message('Ошибка записи; предыдущая версия в .bak: '..tostring(write_err),5);return false end
    disk_snapshot=text;return true
end
local function save_name(name)
    name=tostring(name or ''):match('^%s*(.-)%s*$')
    if name=='' or #name>160 then mp.osd_message('Название: от 1 до 160 байт',3);return end
    local state=before and copy(before) or snapshot()
    if not valid(state) then mp.osd_message('Эти настройки пока нельзя сохранить',3);return end
    local item={id=tostring(os.time())..'-'..tostring(math.random(100000,999999)),name=name,state=state}
    bank.presets[#bank.presets+1]=item
    if save_bank() then mp.osd_message('Пресет «'..name..'» сохранён',3)
    else table.remove(bank.presets) end
end
local function save_prompt()input.get({prompt='Название пресета изображения',submit=save_name})end
local function menu()
    local items={{title='Сохранить текущие настройки…',icon='save',value={'script-binding','picture_presets/save'}},
        {title='До / после — '..(before and 'показано ДО' or 'показано ПОСЛЕ'),value={'script-binding','picture_presets/compare'}}}
    for _,p in ipairs(bank.presets) do if type(p)=='table' and type(p.id)=='string' and type(p.name)=='string' then
        items[#items+1]={id='preset-'..p.id,title=p.name,items={
            {title='Применить',value={'script-message-to','picture_presets','load',p.id}},
            {title='Удалить…',items={{title='Подтвердить удаление «'..p.name..'»',value={'script-message-to','picture_presets','delete',p.id}}}}}}
    end end
    neon_context.open(utils.format_json({type='my-picture-presets',title='Мои пресеты изображения',items=items,
        footnote='Шейдеры, цвет, масштабирование, подсветка • Без громкости, LSFG и позиции видео • F11'}))
end
mp.register_script_message('load',function(id)
    for _,p in ipairs(bank.presets) do if p.id==id then
        if not valid(p.state) then mp.osd_message('Пресет повреждён или отсутствует файл шейдера',4);return end
        after();if apply(p.state,true) then mp.osd_message('Пресет: '..p.name,3) end;return
    end end
end)
mp.register_script_message('delete',function(id)
    for i,p in ipairs(bank.presets) do if p.id==id then table.remove(bank.presets,i);if not save_bank() then table.insert(bank.presets,i,p) end;menu();return end end
end)
mp.register_script_message('save-name',save_name)
mp.register_script_message('after',after)
mp.register_script_message('quality-edit',function(action,id)after();mp.commandv('script-message-to','quality',action,id or '')end)
mp.register_script_message('picture-edit',function(k,v)after();mp.commandv('script-message-to','picture_controls','set',k,v)end)
mp.register_script_message('picture-action',function(action)after();mp.commandv('script-message-to','picture_controls',action)end)
mp.register_script_message('ambient-edit',function(k,v)after();mp.commandv('script-message-to','ambient','set',k,v)end)
mp.add_key_binding(nil,'compare',compare)
mp.add_key_binding(nil,'menu',menu)
mp.add_key_binding(nil,'save',save_prompt)
mp.register_event('start-file',after)
mp.set_property('user-data/picture/ab','after')

neon_context.register({menu=menu})
