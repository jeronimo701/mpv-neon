local mp=require 'mp'
local utils=require 'mp.utils'
local cache={}
local generation=0
local opening=false
local pending_update
local last_json
local providers={
    quality={'quality','menu','picture-quality'},ambient={'ambient','menu','ambient-settings'},
    theme={'ui_theme','menu','ui-theme'},motion={'motion','menu','motion'},
    sleep={'sleep_timer','menu','sleep-timer'},presets={'picture_presets','menu','my-picture-presets'},
    manual={'picture_controls','manual','manual-picture'},bookmarks={'player_tools','bookmarks','bookmarks'},
    help={'player_help','menu','player-help'},
    sponsorblock={'sponsorblock','menu','sponsorblock-settings'},
    ['external-audio']={'external_audio','menu','external-audio'},
    history={'memo','history','memo-history'},
    ['help-playback']={'player_help','playback'},['help-quality']={'player_help','quality'},
    ['help-ambient']={'player_help','ambient'},['help-playlist']={'player_help','playlist'},['help-extras']={'player_help','extras'},
}
local types={}
for key,p in pairs(providers)do if p[3] then types[p[3]]=key end end
types.torrserver='torrserver'
types['quality-menu-video']='stream-video';types['quality-menu-audio']='stream-audio'
types['quality-menu-video_menu']='stream-video';types['quality-menu-audio_menu']='stream-audio'
types['quality-menu-video_fetching']='stream-video';types['quality-menu-audio_fetching']='stream-audio'
types['memo-history']='history'
local function binding(name)return {'script-binding',name}end
local function item(title,command,extra)
    local out=extra or {};out.title=title;out.value=command;if out.keep_open==nil then out.keep_open=true end;return out
end
local function label(title)return {title=title,selectable=false,muted=true}end
local function key_for(value)
    if type(value)~='table' then return end
    if value[1]=='script-binding' then
        return ({['quality/menu']='quality',['ambient/menu']='ambient',['picture_controls/ambient']='ambient',
            ['picture_controls/manual']='manual',['picture_presets/menu']='presets',['ui_theme/menu']='theme',
            ['motion/menu']='motion',['sleep_timer/menu']='sleep',['player_tools/bookmarks']='bookmarks',
            ['player_help/menu']='help',['sponsorblock/menu']='sponsorblock'})[value[2]]
    elseif value[1]=='script-message-to' and value[2]=='player_help' and value[3]=='topic' then return 'help-'..tostring(value[4]) end
end
local function clean(items,prefix,owner)
    local result={}
    for i,original in ipairs(items or {})do
        local entry={};for k,v in pairs(original)do entry[k]=v end
        local link=key_for(entry.value)
        -- Cross-links stay useful in standalone menus; the contextual menu has these as siblings.
        local crosslink=(owner=='manual' and (link=='ambient' or link=='presets'))
            or (owner:match('^help%-') and link~=nil)
        if not crosslink then
            if owner=='quality' then
                entry.hint=nil
                entry.title=entry.title:gsub('480p → экран — мягкий апскейл','480p — мягкий апскейл')
                    :gsub('720p → 1080p / 1440p — чёткий апскейл','720p — чёткий апскейл')
                    :gsub('Дополнительная резкость SSimSuperRes','SSimSuperRes — резкость')
            end
            entry.id=prefix..'/'..i
            if entry.items then entry.items=clean(entry.items,entry.id,owner)
            elseif link and cache[link] and owner=='help' then
                entry.value=nil;entry.items=clean(cache[link].items,entry.id,link)
            end
            if entry.items then entry.keep_open=false
            elseif entry.keep_open==nil then entry.keep_open=true end
            local value=entry.value
            if type(value)=='table' and ((value[1]=='script-binding' and
                (value[2]=='sleep_timer/custom' or value[2]=='picture_presets/save' or value[2]=='player_tools/bookmark-add' or value[2]=='ambient/edge-slider'))
                or (value[1]=='script-message-to' and value[3]=='input')) then entry.keep_open=false end
            result[#result+1]=entry
        end
    end
    return result
end
local function submenu(key,title,hint,fallback)
    local data=cache[key]
    return {id='ctx/'..key,title=title,hint=hint,keep_open=false,
        items=clean(data and data.items or fallback or {label('Загрузка…')},'ctx/'..key,key)}
end
local function tracks(kind)
    local prop=kind=='audio' and 'aid' or 'sid'
    local current=mp.get_property(prop,'no')
    local entries={item('Выключить',{'set',prop,'no'},{active=current=='no'})}
    for _,t in ipairs(mp.get_property_native('track-list',{}))do if t.type==kind then
        local title=t.title or (kind=='audio' and 'Аудиодорожка ' or 'Субтитры ')..t.id
        local details={};if t.lang then details[#details+1]=t.lang end;if t.codec then details[#details+1]=t.codec end
        entries[#entries+1]=item(title,{'set',prop,tostring(t.id)},{active=tostring(t.id)==current,hint=table.concat(details,' · ')})
    end end
    if #entries==1 then entries[#entries+1]=label(kind=='audio' and 'Аудиодорожек нет' or 'Субтитров нет')end
    return entries
end
local function playlist()
    local enabled=mp.get_property_native('user-data/playlist-window/enabled',false)
    local entries={item('Отдельное окно: '..(enabled and 'вкл.' or 'выкл.'),binding('playlist_window/toggle'),{active=enabled,hint='Ctrl+P',separator=true})}
    local position=mp.get_property_number('playlist-pos',-1)
    for i,p in ipairs(mp.get_property_native('playlist',{}))do
        local title=p.title or p.filename:gsub('\\','/'):match('[^/]+$') or p.filename
        entries[#entries+1]=item(title,{'script-message-to','context_menu','play',tostring(p.id)},{active=i-1==position})
    end
    if #entries==1 then entries[#entries+1]=label('Плейлист пуст — откройте файл')end
    return clean(entries,'ctx/playlist','playlist')
end
local function chapters()
    local entries={};local current=mp.get_property_number('chapter',-1)
    for i,c in ipairs(mp.get_property_native('chapter-list',{}))do
        entries[#entries+1]=item(c.title or 'Глава '..i,{'set','chapter',tostring(i-1)},{active=i-1==current})
    end
    if #entries==0 then entries={label('В этом файле нет глав')}end
    return entries
end
local function build()
    local speeds={};for _,s in ipairs({0.25,0.5,0.75,1,1.25,1.5,1.75,2})do
        speeds[#speeds+1]=item(tostring(s)..'×',{'set','speed',tostring(s)},{active=mp.get_property_number('speed',1)==s})
    end
    local enabled=mp.get_property_native('user-data/playlist-window/enabled',false)
    local root={type='neon-context',title='mpv Neon',mouse_nav=true,keep_open=false,search_submenus=true,
        on_close={'script-message-to','context_menu','closed'},
        footnote='Нажмите раздел → выбор поверх меню · «Назад» / ←: предыдущий уровень · Esc: закрыть',items={
        {id='ctx/open',title='Открыть',items={item('Файл…',binding('uosc/open-file'),{hint='Ctrl+O',keep_open=false}),
            item('Ссылку из буфера',binding('uosc/paste'),{hint='Ctrl+V',keep_open=false})}},
        {id='ctx/playlist',title='Плейлист',hint='P',items=playlist()},
        {id='ctx/picture',title='Изображение',items={
            submenu('quality','Апскейл и шейдеры','F2'),submenu('ambient','Подсветка полос','F8'),
            submenu('manual','Настроить изображение','F7'),submenu('presets','Мои пресеты','F11'),
            item('До / после',binding('picture_presets/compare'),{hint='F9',active=mp.get_property_native('user-data/picture/ab')=='before'}),
            submenu('stream-video','Качество сетевого видео','F4',{
                item('Получить доступные варианты',binding('quality_menu/video_formats_toggle')),
                label('Доступно для поддерживаемых сетевых источников')})}},
        {id='ctx/sound',title='Звук и субтитры',items={
            submenu('external-audio','Аудиодорожка','A',tracks('audio')),
            {id='ctx/subs',title='Субтитры',hint='S',items=tracks('sub')},
            item('Показывать субтитры',{'cycle','sub-visibility'},{active=mp.get_property_bool('sub-visibility',true)}),
            item('Ночной звук',binding('player_tools/night'),{hint='N',active=mp.get_property_native('user-data/player-tools/night',false)}),
            submenu('stream-audio','Качество сетевого аудио','Ctrl+F4',{
                item('Получить доступные варианты',binding('quality_menu/audio_formats_toggle'))})}},
        submenu('motion','Плавность / LSFG','F6'),submenu('sleep','Таймер сна','F10'),
        submenu('theme','Оформление','F12'),submenu('bookmarks','Закладки','Shift+B'),
        submenu('torrserver','TorrServer',nil,{
            item('Торренты на сервере',binding('torrserver/menu')),
            item('Добавить magnet или ссылку…',binding('torrserver/add'),{keep_open=false,hint='Ctrl+T'}),
            item('Открыть веб-интерфейс',binding('torrserver/browser'),{keep_open=false})}),
        submenu('sponsorblock','SponsorBlock'),
        {id='ctx/settings',title='Настройки и навигация',hint='F5',items={
            item('Отдельное окно плейлиста',binding('playlist_window/toggle'),{active=enabled,hint='Ctrl+P'}),
            {id='ctx/speed',title='Скорость воспроизведения',items=speeds},
            {id='ctx/chapters',title='Главы',hint='Ctrl+G',items=chapters()},
            submenu('history','История просмотра','H'),
            item('Мини-плеер',binding('player_tools/pip'),{hint='I',keep_open=false}),
            item('Развернуть окно',binding('player_tools/theater'),{hint='T',keep_open=false}),
            item('Переподключить поток',binding('player_tools/reload'),{hint='Ctrl+R',keep_open=false}),
            item('Статистика',binding('stats/display-stats'),{hint='Ctrl+I',keep_open=false}),
            item('Папка настроек',binding('uosc/open-config-directory'),{keep_open=false})}},
        submenu('help','Справка','F1'),
        item('Выход',{'quit-watch-later'},{hint='Ctrl+Q',keep_open=false}),
    }}
    return root
end
local function refresh()
    pending_update=nil
    local active=mp.get_property_native('user-data/uosc/menu/type')=='neon-context'
    if not opening and not active then return end
    local data=build();local json=utils.format_json(data)
    mp.set_property_native('user-data/neon-context/tree',data)
    if opening then
        opening=false;last_json=json;mp.commandv('script-message-to','uosc','open-menu',json)
    elseif json~=last_json then last_json=json;mp.commandv('script-message-to','uosc','update-menu',json)end
end
local function schedule()
    if not pending_update then pending_update=mp.add_timeout(0.04,refresh)end
end
local function request()
    for key,p in pairs(providers)do mp.commandv('script-message-to',p[1],'context-export',p[2],generation..'/'..key)end
end
mp.register_script_message('deliver',function(json,token)
    local data=utils.parse_json(json);if type(data)~='table' or type(data.items)~='table' then return end
    local key
    if token and token~='' then
        local g,k=token:match('^(%d+)/(.*)$');if tonumber(g)~=generation then return end;key=k
    else
        key=types[data.type]
        if data.type=='player-help' then
            for k,c in pairs(cache)do if k:match('^help%-') and c.title==data.title then key=k;break end end
        end
    end
    if key then cache[key]=data;schedule()
    elseif not token or token=='' then mp.commandv('script-message-to','uosc','open-menu',json) end
end)
mp.register_script_message('closed',function()
    opening=false;last_json=nil
    for _,key in ipairs({'stream-video','stream-audio'})do
        local data=cache[key]
        if data and type(data.on_close)=='table' then mp.commandv(unpack(data.on_close));cache[key]=nil end
    end
end)
mp.register_script_message('play',function(id)
    for i,p in ipairs(mp.get_property_native('playlist',{}))do if tostring(p.id)==id then
        mp.set_property_number('playlist-pos',i-1);mp.set_property_bool('pause',false);return
    end end
end)
mp.add_key_binding(nil,'menu',function()
    if mp.get_property_native('user-data/uosc/menu/type')=='neon-context' then mp.commandv('script-message-to','uosc','close-menu','neon-context');return end
    generation=generation+1;opening=true;last_json=nil
    request();schedule()
end)
mp.add_periodic_timer(0.75,function()
    if mp.get_property_native('user-data/uosc/menu/type')=='neon-context' then request();schedule()end
end)
