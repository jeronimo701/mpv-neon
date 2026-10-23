local neon_context=dofile(require('mp').command_native({'expand-path','~~/script-modules/neon-context.lua'}))
local mp = require 'mp'
local utils = require 'mp.utils'
local anime=dofile(mp.command_native({'expand-path','~~/script-modules/anime4k-profiles.lua'}))
local profiles = {
    {id='native', title='Обычный — без шейдеров', hint='Рекомендуется по умолчанию'},
    {id='sd480', title='480p → экран — мягкий апскейл', hint='FSRCNNX 8 · KrigBilateral · сглаживание градиентов'},
    {id='hd720', title='720p → 1080p / 1440p — чёткий апскейл', hint='FSRCNNX 8 · KrigBilateral'},
    {id='ravu', title='RAVU — лёгкий апскейл', hint='Экономичный профиль'},
    {id='fsrcnnx8', title='FSRCNNX 8 + KrigBilateral', hint='Проверить плавность на вашем видео'},
    {id='fsrcnnx16', title='FSRCNNX 16 + KrigBilateral', hint='Тяжёлый, экспериментальный'},
    {id='anime', title='Anime4K — лёгкий', hint='Для рисованной анимации'},
}
local current = 'native'
local sharpen = false
local sharp_path = mp.command_native({'expand-path', '~~/shaders/SSimSuperRes.glsl'})
local function publish()
    mp.set_property('user-data/quality/profile', current)
    mp.set_property_bool('user-data/quality/sharpen', sharpen)
end
-- Respect an explicit --profile=quality-* command-line selection, if supplied.
local initial = mp.get_property_native('glsl-shaders', {})
for _, path in ipairs(initial) do
    if path:find('FSRCNNX_x2_16', 1, true) then current = 'fsrcnnx16'; break
    elseif path:find('FSRCNNX_x2_8', 1, true) then current = 'fsrcnnx8'; break
    elseif path:find('ravu-', 1, true) then current = 'ravu'; break
    elseif path:find('Anime4K', 1, true) then current = 'anime'; break end
end
local function select_profile(id)
    if mp.get_property_native('user-data/picture/ab')=='before' then mp.commandv('script-message-to','picture_presets','quality-edit','select',id);return end
    if anime[id] then
        local paths={}
        for _,path in ipairs(anime[id].paths)do
            local expanded=mp.command_native({'expand-path',path})
            if not utils.file_info(expanded)then mp.osd_message('Нет шейдера: '..path,5);return end
            paths[#paths+1]=expanded
        end
        mp.set_property_native('glsl-shaders',paths)
        current,sharpen=id,false;publish();mp.osd_message(anime[id].title..' — проверяйте пропуски кадров (Ctrl+I)',4);return
    end
    for _, p in ipairs(profiles) do
        if p.id == id then
            mp.commandv('apply-profile', 'quality-' .. id)
            if id == 'native' then mp.set_property_native('glsl-shaders', {}) end
            current, sharpen = id, false
            publish()
            mp.osd_message(p.title, 3)
            return
        end
    end
    mp.msg.error('Unknown quality profile: ' .. tostring(id))
end
local function toggle_sharpen()
    if mp.get_property_native('user-data/picture/ab')=='before' then mp.commandv('script-message-to','picture_presets','quality-edit','sharpen');return end
    local shaders = mp.get_property_native('glsl-shaders', {})
    local found = false
    for i = #shaders, 1, -1 do
        if shaders[i] == sharp_path or shaders[i] == '~~/shaders/SSimSuperRes.glsl' then
            table.remove(shaders, i)
            found = true
        end
    end
    if not found then shaders[#shaders+1] = sharp_path end
    mp.set_property_native('glsl-shaders', shaders)
    sharpen = not found
    publish()
    mp.osd_message('SSimSuperRes: ' .. (sharpen and 'включён' or 'выключен'), 2)
end
local function quality_menu()
    local items = {}
    for _, p in ipairs(profiles) do
        items[#items+1] = {title=p.title, hint=p.hint, active=p.id == current,
            value={'script-message-to', 'quality', 'select', p.id}}
    end
    local tiers={}
    for _,tier in ipairs({'fast','hq'})do
        local children={}
        for _,mode in ipairs({'a','b','c','aa','bb','ca'})do
            local id='anime-'..tier..'-'..mode
            children[#children+1]={title=anime[id].title,active=current==id,
                hint=(mode=='aa' or mode=='bb' or mode=='ca') and 'Для масштаба 2× и выше' or '',
                value={'script-message-to','quality','select',id}}
        end
        tiers[#tiers+1]={title=tier=='fast' and 'Fast — официальный Low-end' or 'HQ — тяжёлый High-end',items=children}
    end
    items[#items+1]={title='Anime4K — все официальные режимы',items=tiers}
    items[#items+1] = {title='Дополнительная резкость SSimSuperRes', active=sharpen,
        value={'script-message-to', 'quality', 'sharpen'}}
    neon_context.open( utils.format_json({
        type='picture-quality', title='Апскейл и шейдеры — профили', items=items,
        footnote='Ctrl+0: сброс • Ctrl+i: статистика • F2: это меню'}))
end
mp.add_key_binding(nil,'menu',quality_menu)
mp.register_script_message('select', select_profile)
mp.register_script_message('sharpen', toggle_sharpen)
mp.register_script_message('help', function()mp.commandv('script-binding','player_help/menu')end)
publish()
mp.observe_property('glsl-shaders','native',function(_,paths)
    local selected=mp.get_property_native('user-data/quality/profile',current)
    current,sharpen='native',false
    for _,path in ipairs(paths or {}) do
        if path:find('FSRCNNX_x2_16',1,true) then current='fsrcnnx16'
        elseif path:find('FSRCNNX_x2_8',1,true) then current='fsrcnnx8'
        elseif path:find('ravu-',1,true) then current='ravu'
        elseif path:find('Anime4K',1,true) then current='anime' end
        if path:find('SSimSuperRes',1,true) then sharpen=true end
    end
    if current=='fsrcnnx8' and (selected=='sd480' or selected=='hd720') then current=selected end
    if current=='anime' and anime[selected] then
        local expected=anime[selected].paths;local same=#expected==#(paths or {})
        for i,p in ipairs(paths or {})do if p~=mp.command_native({'expand-path',expected[i] or ''}) then same=false end end
        if same then current=selected end
    end
    publish()
end)

neon_context.register({menu=quality_menu})
