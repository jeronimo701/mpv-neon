local mp = require 'mp'
local utils = require 'mp.utils'
local profiles = {
    {id='native', title='Обычный — без шейдеров', hint='Рекомендуется по умолчанию'},
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
mp.add_key_binding(nil, 'menu', function()
    local items = {}
    for _, p in ipairs(profiles) do
        items[#items+1] = {title=p.title, hint=p.hint, active=p.id == current,
            value={'script-message-to', 'quality', 'select', p.id}}
    end
    items[#items+1] = {title='Дополнительная резкость SSimSuperRes', active=sharpen,
        value={'script-message-to', 'quality', 'sharpen'}}
    items[#items+1] = {title='Ручные настройки изображения',value={'script-binding','picture_controls/manual'}}
    items[#items+1] = {title='Подсветка чёрных полос',value={'script-binding','picture_controls/ambient'}}
    items[#items+1] = {title='До / после',value={'script-binding','picture_presets/compare'}}
    items[#items+1] = {title='Мои пресеты',value={'script-binding','picture_presets/menu'}}
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json({
        type='picture-quality', title='Апскейл и шейдеры — профили', items=items,
        footnote='Ctrl+0: сброс • Ctrl+i: статистика • F2: это меню'}))
end)
mp.register_script_message('select', select_profile)
mp.register_script_message('sharpen', toggle_sharpen)
mp.register_script_message('help', function()
    mp.osd_message('Клик / Space / K — пауза\nДвойной клик / F — полный экран\nJ / L — ±10 с; ← / → — ±5 с\n↑ / ↓ — громкость; M — без звука\n0…9 — позиция; C — субтитры; T — кинотеатр\n< / > — скорость; , / . — по кадрам\nF2 — картинка; F3 — TorrServer; F5 — настройки\nF6 — LSFG; N — ночной звук\nB — добавить закладку; Shift+B — закладки\nCtrl+R — восстановить поток\nCtrl+I — статистика; Ctrl+0 — убрать шейдеры', 15)
end)
publish()
mp.observe_property('glsl-shaders','native',function(_,paths)
    current,sharpen='native',false
    for _,path in ipairs(paths or {}) do
        if path:find('FSRCNNX_x2_16',1,true) then current='fsrcnnx16'
        elseif path:find('FSRCNNX_x2_8',1,true) then current='fsrcnnx8'
        elseif path:find('ravu-',1,true) then current='ravu'
        elseif path:find('Anime4K',1,true) then current='anime' end
        if path:find('SSimSuperRes',1,true) then sharpen=true end
    end
    publish()
end)
