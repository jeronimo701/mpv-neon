local neon_context=dofile(require('mp').command_native({'expand-path','~~/script-modules/neon-context.lua'}))
-- Local theme preferences. Uses mp.options' supported live script-opts updates.
local mp=require 'mp'
local utils=require 'mp.utils'
local opts={state_file='~~/ui-theme.json'}
require('mp.options').read_options(opts,'ui-theme')
local file=mp.command_native({'expand-path',opts.state_file})
local themes={
    youtube={name='YouTube — привычный видеоплеер',background='212121',foreground_text='FFFFFF',background_text='FFFFFF',curtain='000000',radius=8,height=38,padding=8,width=320,opacity=98,curtain_opacity=0.42,submenu=0.75},
    glass={name='Glass — полупрозрачное стекло',background='141C2C',foreground_text='081522',
        background_text='F4F7FF',curtain='080D17',radius=20,height=42,padding=12,width=350,opacity=86,curtain_opacity=0.22,submenu=0.7},
    deck={name='Deck — в духе Steam Deck',background='141D2B',foreground_text='06101C',
        background_text='EEF4FC',curtain='080D17',radius=8,height=40,padding=8,width=330,opacity=97,curtain_opacity=0.4,submenu=0.8},
    neon={name='Neon — под иконку №07',background='1C1118',foreground_text='240807',
        background_text='FFF4EF',curtain='10090D',radius=16,height=42,padding=10,width=350,opacity=94,curtain_opacity=0.3,submenu=0.75},
    classic={name='Стандартный — прежний uosc',background='000000',foreground_text='000000',
        background_text='FFFFFF',curtain='111111',radius=6,height=36,padding=4,width=260,opacity=100,curtain_opacity=0.8,submenu=0.4},
}
local accents={youtube='FF0033',cyan='7CE7FF',blue='53ADFF',violet='BDA0FF',mint='79E9BC',red='FF717D',ember='FF6247',white='FFFFFF'}
local state={theme='deck',accent='blue',opacity=97,size='normal',animation='smooth'}
local sizes={compact=0.9,normal=1,large=1.15}
local animations={none=0,quick=90,smooth=180}
local f=io.open(file,'r')
if f then
    local raw=f:read('*a');f:close()
    local data=utils.parse_json(raw)
    if type(data)=='table' then
        if themes[data.theme] then state.theme=data.theme end
        if accents[data.accent] then state.accent=data.accent end
        if type(data.opacity)=='number' and data.opacity==data.opacity then state.opacity=math.max(60,math.min(100,data.opacity)) end
        if sizes[data.size] then state.size=data.size end
        if animations[data.animation] then state.animation=data.animation end
    end
end
local default_controls='play-pause,next,space,button:more_tools,<video,audio>subtitles,command:picture_in_picture_alt:script-binding player_tools/pip?Мини-плеер,command:crop_16_9:script-binding player_tools/theater?Кинотеатр,gap,volume-slider,gap,speed-menu,fullscreen'
local conf=io.open(mp.command_native({'expand-path','~~/script-opts/uosc.conf'}),'r')
if conf then for line in conf:lines() do local value=line:match('^controls%s*=%s*(.+)');if value then default_controls=value:gsub('%s+$','') end end;conf:close() end
local youtube_controls='play-pause,next,volume-slider,youtube-time,space,<video>cycle:subtitles:sub-visibility:no/yes!?Субтитры (C),speed-menu,button:youtube_settings,command:picture_in_picture_alt:script-binding player_tools/pip?Мини-плеер,command:crop_16_9:script-binding player_tools/theater?Кинотеатр,button:more_tools,fullscreen'
local function apply(persist)
    local t=themes[state.theme]
    local youtube=state.theme=='youtube'
    local color=accents[state.accent]
    local values={menu_style=state.theme,border_radius=t.radius,window_border_size=0,
        controls=youtube and youtube_controls or default_controls,controls_margin=youtube and 12 or 8,controls_spacing=youtube and 4 or 2,
        progress=youtube and 'never' or 'windowed',destination_time=youtube and 'total' or 'playtime-remaining',
        timeline_style='line',timeline_size=youtube and 22 or 32,timeline_line_width=3,timeline_persistency='paused',controls_size=youtube and 40 or 36,
        menu_item_height=math.floor(t.height*sizes[state.size]+0.5),
        menu_padding=t.padding,menu_min_width=t.width,font_scale=sizes[state.size],
        font_bold=state.theme=='deck' and 'yes' or 'no',animation_duration=animations[state.animation],
        color='foreground='..color..',foreground_text='..t.foreground_text..',background='..t.background..
            ',background_text='..t.background_text..',window_border='..color..',curtain='..t.curtain..',match='..color..',heatmap='..color,
        opacity=string.format('menu=%.3f,submenu=%.2f,curtain=%.2f,controls=%.2f,timeline=%.2f',
            state.opacity/100,t.submenu,t.curtain_opacity,(state.theme=='classic' or youtube) and 0 or 0.08,state.theme=='classic' and 0.9 or 0.95)}
    local current=mp.get_property_native('options/script-opts',{})
    for k,v in pairs(values) do current['uosc-'..k]=tostring(v) end
    mp.set_property_native('options/script-opts',current)
    mp.set_property_native('user-data/ui-theme/settings',state)
    if persist then
        local out,err=io.open(file,'w')
        if out then out:write(utils.format_json(state));out:close()
        else mp.msg.error('Cannot save theme: '..tostring(err));mp.osd_message('Не удалось сохранить оформление',3) end
    end
end
local function command(action,key,value)
    return {'script-message-to','ui_theme',action,key,value}
end
local function menu()
    local items={}
    for _,id in ipairs({'glass','deck','youtube','neon','classic'}) do
        items[#items+1]={title=themes[id].name,icon=id=='glass' and 'blur_on' or id=='deck' and 'sports_esports' or 'contrast',
            active=state.theme==id,keep_open=true,value=command('select',id)}
    end
    local colors={}
    for _,entry in ipairs({{'youtube','Красный YouTube'},{'cyan','Ледяной неон'},{'blue','Синий Deck'},{'violet','Лиловый'},{'mint','Мятный'},{'red','Коралловый'},{'ember','Огненный №07'},{'white','Белый'}}) do
        colors[#colors+1]={title=entry[2],active=state.accent==entry[1],keep_open=true,value=command('set','accent',entry[1])}
    end
    items[#items+1]={id='colors',title='Цвет акцента',items=colors,separator=true}
    local opacity={}
    for _,n in ipairs({60,70,80,86,90,95,97,100}) do
        opacity[#opacity+1]={title=n..'% — '..(n==100 and 'непрозрачно' or 'плотность'),active=state.opacity==n,
            keep_open=true,value=command('set','opacity',tostring(n))}
    end
    items[#items+1]={id='opacity',title='Плотность панелей: '..state.opacity..'%',items=opacity}
    local scale={}
    for _,entry in ipairs({{'compact','Компактно'},{'normal','Обычно'},{'large','Крупнее'}}) do
        scale[#scale+1]={title=entry[2],active=state.size==entry[1],keep_open=true,value=command('set','size',entry[1])}
    end
    items[#items+1]={id='size',title='Размер меню и текста',items=scale}
    local animation={}
    for _,entry in ipairs({{'none','Без анимации'},{'quick','Быстро'},{'smooth','Плавно'}}) do
        animation[#animation+1]={title=entry[2],active=state.animation==entry[1],keep_open=true,value=command('set','animation',entry[1])}
    end
    items[#items+1]={id='animation',title='Анимация',items=animation}
    neon_context.open(utils.format_json({type='ui-theme',title='Оформление',items=items,
        footnote='YouTube: панель, прогресс и быстрые настройки · F12'}))
end
mp.register_script_message('select',function(id)
    if not themes[id] then return end
    state.theme=id;state.opacity=themes[id].opacity
    state.accent=id=='youtube' and 'youtube' or id=='deck' and 'blue' or id=='classic' and 'white' or id=='neon' and 'ember' or 'cyan'
    apply(true)
    mp.add_timeout(0.05,menu)
end)
mp.register_script_message('set',function(key,value)
    if key=='accent' and accents[value] or key=='size' and sizes[value] or key=='animation' and animations[value] then state[key]=value
    elseif key=='opacity' then
        local n=tonumber(value)
        if not n or n~=n or n<60 or n>100 then return end
        state.opacity=math.floor(n+0.5)
    else return end
    apply(true)
    mp.add_timeout(0.05,menu)
end)
mp.add_key_binding(nil,'menu',menu)
mp.register_script_message('menu',menu)
mp.add_timeout(0.15,function() apply(false) end)

neon_context.register({menu=menu})
