local neon_context=dofile(require('mp').command_native({'expand-path','~~/script-modules/neon-context.lua'}))
-- Player-only timer: never shuts down or suspends Windows.
local mp=require 'mp'
local utils=require 'mp.utils'
local input=require 'mp.input'
local deadline
local action='pause'
local function publish()
    local remaining=deadline and math.max(0,math.ceil(deadline-mp.get_time())) or 0
    mp.set_property_number('user-data/sleep/remaining',remaining)
    mp.set_property('user-data/sleep/action',action)
    mp.set_property_bool('user-data/sleep/active',deadline~=nil)
end
local function cancel()
    deadline=nil;publish();mp.osd_message('Таймер сна отменён',2)
end
local function finish()
    deadline=nil;publish()
    mp.commandv('script-message-to','motion','select','0')
    if action=='quit' then mp.commandv('quit')
    else mp.set_property_bool('pause',true);mp.osd_message('Таймер сна: воспроизведение остановлено',5) end
end
local function start(minutes)
    minutes=tonumber(minutes)
    if not minutes or minutes~=minutes or minutes<1 or minutes>720 then mp.osd_message('Укажите от 1 до 720 минут',3);return end
    deadline=mp.get_time()+minutes*60;publish()
    mp.osd_message('Таймер сна: '..minutes..' мин • '..(action=='quit' and 'закрыть плеер' or 'пауза'),3)
end
local function custom()
    input.get({prompt='Таймер сна — минут (1…720)',submit=start})
end
local function menu()
    local remaining=deadline and math.max(0,math.ceil(deadline-mp.get_time())) or 0
    local status=deadline and string.format('Осталось %02d:%02d',math.floor(remaining/60),remaining%60) or 'Таймер выключен'
    local items={{title=status,selectable=false},{title='Действие: '..(action=='quit' and 'закрыть плеер' or 'пауза'),items={
        {title='Пауза и выключение LSFG',active=action=='pause',value={'script-message-to','sleep_timer','action','pause'}},
        {title='Закрыть только плеер',active=action=='quit',value={'script-message-to','sleep_timer','action','quit'}}}}}
    for _,minutes in ipairs({15,30,45,60,90,120}) do items[#items+1]={title='Через '..minutes..' минут',value={'script-message-to','sleep_timer','start',tostring(minutes)}} end
    items[#items+1]={title='Указать время…',value={'script-binding','sleep_timer/custom'}}
    items[#items+1]={title='Отменить таймер',value={'script-binding','sleep_timer/cancel'}}
    neon_context.open(utils.format_json({type='sleep-timer',title='Таймер сна',items=items,
        footnote='Отсчёт идёт и на паузе • Не выключает компьютер • После перезапуска сбрасывается • F10'}))
end
mp.register_script_message('start',start)
mp.register_script_message('action',function(v)if v=='pause' or v=='quit' then action=v;publish();menu() end end)
mp.register_script_message('cancel',cancel)
mp.add_key_binding(nil,'menu',menu)
mp.add_key_binding(nil,'custom',custom)
mp.add_key_binding(nil,'cancel',cancel)
mp.add_periodic_timer(1,function()
    if deadline and mp.get_time()>=deadline then finish() else publish() end
    if mp.get_property_native('user-data/uosc/menu/type')=='sleep-timer' then menu() end
end)
publish()

neon_context.register({menu=menu})
