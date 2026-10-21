local mp = require 'mp'
local utils = require 'mp.utils'
local input = require 'mp.input'
local opts = {bookmarks_file='~~/bookmarks.json'}
require('mp.options').read_options(opts, 'player-tools')
local bookmark_file = mp.command_native({'expand-path', opts.bookmarks_file})
local night = false
local pending_reload
local pip
local click_timer
local function open_menu(kind, title, items)
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json({type=kind,title=title,items=items}))
end
local function load_bookmarks()
    local file = io.open(bookmark_file, 'rb')
    if not file then return {} end
    local data = utils.parse_json(file:read('*a'))
    file:close()
    if type(data) ~= 'table' then mp.osd_message('Файл закладок повреждён; сохранение отменено.', 4); return nil end
    return data
end
local function save_bookmarks(data)
    local file, err = io.open(bookmark_file, 'wb')
    if not file then mp.osd_message('Не удалось сохранить закладки: ' .. tostring(err), 4); return false end
    file:write(utils.format_json(data)); file:close()
    return true
end
local function source_path()
    local path = mp.get_property('path')
    if path and not path:match('^%a[%w+.-]*://') and not path:match('^%a:[/\\]') then
        path = utils.join_path(mp.get_property('working-directory'), path)
    end
    return path
end
local function add_bookmark()
    local path, time = source_path(), mp.get_property_number('time-pos')
    if not path or not time then mp.osd_message('Сначала откройте видео.', 2); return end
    local title = mp.get_property('media-title', 'Видео')
    local title_override = mp.get_property('force-media-title', '')
    input.get({prompt='Название закладки', default_text=title, submit=function(name)
        local data = load_bookmarks()
        if not data then return end
        data[#data+1] = {path=path,time=time,title=name ~= '' and name or title, media_title=title_override,created=os.time()}
        if save_bookmarks(data) then mp.osd_message('Закладка сохранена', 2) end
    end})
end
local function bookmark_menu()
    local data = load_bookmarks()
    if not data then return end
    local items = {{title='Добавить закладку текущего момента',icon='bookmark_add',value={'script-binding','player_tools/bookmark-add'}}}
    for i=#data,1,-1 do
        local b=data[i]
        local seconds=math.floor(b.time or 0)
        items[#items+1]={title=b.title or 'Закладка', hint=string.format('%02d:%02d:%02d',seconds/3600,seconds/60%60,seconds%60),
            items={{title='Открыть',value={'script-message-to','player_tools','bookmark-open',tostring(i)}},
                {title='Удалить…',value={'script-message-to','player_tools','bookmark-delete',tostring(i)}}}}
    end
    open_menu('bookmarks','Закладки сцен',items)
end
local function open_bookmark(index)
    local data=load_bookmarks(); local b=data and data[tonumber(index)]
    if not b then return end
    mp.command_native({'loadfile',b.path,'replace',-1,{start=tostring(b.time),['force-media-title']=b.media_title or ''}})
end
mp.register_script_message('bookmark-open',open_bookmark)
mp.register_script_message('bookmark-delete',function(index)
    local data=load_bookmarks(); local b=data and data[tonumber(index)]
    if not b then return end
    open_menu('bookmark-confirm','Удалить «' .. b.title .. '»?',{
        {title='Отмена',value={'script-binding','player_tools/bookmarks'}},
        {title='Удалить закладку',value={'script-message-to','player_tools','bookmark-delete-confirm',index,tostring(b.created)}}})
end)
mp.register_script_message('bookmark-delete-confirm',function(index,created)
    local data=load_bookmarks(); index=tonumber(index)
    if data and data[index] and tostring(data[index].created)==created then
        table.remove(data,index); save_bookmarks(data)
    end
    bookmark_menu()
end)
local function night_toggle()
    local active=false
    for _, filter in ipairs(mp.get_property_native('af', {})) do if filter.label=='night' then active=true end end
    if active then mp.commandv('af','remove','@night') else
        mp.commandv('af','add','@night:lavfi=[acompressor=threshold=0.125:ratio=4:attack=20:release=250:makeup=2,alimiter=limit=0.95:level=false]')
    end
    night=not active
    mp.set_property_bool('user-data/player-tools/night',night)
    mp.commandv('script-message-to','uosc','set-button','night',utils.format_json({icon='bedtime',active=night,
        tooltip='Ночной звук',command={'script-binding','player_tools/night'}}))
    mp.osd_message('Ночной звук: ' .. (night and 'включён' or 'выключен'),2)
end
local function reload()
    local path=source_path()
    if not path then mp.osd_message('Нет открытого видео',2); return end
    local options={['force-media-title']=mp.get_property('force-media-title','')}
    local position=mp.get_property_number('time-pos')
    if position then options.start=tostring(position) end
    pending_reload={pause=mp.get_property_bool('pause',false),aid=mp.get_property('aid','auto'),
        playlist=mp.get_property_native('playlist',{}),index=mp.get_property_number('playlist-pos',0),
        sid=mp.get_property('sid','auto'),sub_delay=mp.get_property_number('sub-delay',0),audio_delay=mp.get_property_number('audio-delay',0)}
    mp.command_native({'loadfile',path,'replace',-1,options})
    mp.osd_message('Переподключаю поток…',3)
end
mp.register_event('file-loaded',function()
    if not pending_reload then return end
    local restore=pending_reload; pending_reload=nil
    if #restore.playlist>1 then
        for index,entry in ipairs(restore.playlist) do
            if index-1~=restore.index then
                mp.command_native({'loadfile',entry.filename,'append',-1,{['force-media-title']=entry.title or ''}})
            end
        end
        if restore.index>0 then mp.commandv('playlist-move',0,restore.index) end
    end
    mp.set_property_bool('pause',restore.pause)
    mp.set_property('aid',restore.aid); mp.set_property('sid',restore.sid)
    mp.set_property_number('sub-delay',restore.sub_delay); mp.set_property_number('audio-delay',restore.audio_delay)
end)
mp.add_key_binding(nil,'night',night_toggle)
mp.add_key_binding(nil,'click',function()
    if click_timer then click_timer:kill() end
    click_timer=mp.add_timeout(0.3,function() click_timer=nil; mp.commandv('cycle','pause') end)
end)
mp.add_key_binding(nil,'double-click',function()
    if click_timer then click_timer:kill(); click_timer=nil end
    mp.commandv('cycle','fullscreen')
end)
mp.add_key_binding(nil,'bookmarks',bookmark_menu)
mp.add_key_binding(nil,'bookmark-add',add_bookmark)
mp.add_key_binding(nil,'reload',reload)
mp.add_key_binding(nil,'settings',function()
    open_menu('player-settings','Настройки',{
        {title='Оформление — Glass / Deck / Neon / Стандартный',icon='palette',value={'script-binding','ui_theme/menu'}},
        {title='Апскейл и шейдеры — профили · F2',icon='tune',value={'script-binding','quality/menu'}},
        {title='Ручные настройки изображения',value={'script-binding','picture_controls/manual'}},
        {title='Подсветка чёрных полос',value={'script-binding','picture_controls/ambient'}},
        {title='До / после — переключить',value={'script-binding','picture_presets/compare'}},
        {title='Мои пресеты изображения',value={'script-binding','picture_presets/menu'}},
        {title='Таймер сна',value={'script-binding','sleep_timer/menu'}},
        {title='Плавность / LSFG',icon='auto_awesome',value={'script-binding','motion/menu'}},
        {title='Скорость воспроизведения',icon='speed',items=(function()
            local items={}; for _, speed in ipairs({0.25,0.5,0.75,1,1.25,1.5,1.75,2}) do
                items[#items+1]={title=tostring(speed)..'×',active=mp.get_property_number('speed')==speed,value={'set','speed',tostring(speed)}}
            end; return items end)()},
        {title='Аудиодорожка',value={'script-binding','uosc/audio'}},
        {title='Субтитры',value={'script-binding','uosc/subtitles'}},
        {title='Ночной звук',active=night,value={'script-binding','player_tools/night'}},
        {title='Качество сетевого потока',value={'script-binding','quality_menu/video_formats_toggle'}},
        {title='Закладки сцен',value={'script-binding','player_tools/bookmarks'}},
        {title='Переподключить поток',value={'script-binding','player_tools/reload'}},
        {title='Горячие клавиши',value={'script-message-to','quality','help'}}})
end)
mp.add_key_binding(nil,'theater',function()
    mp.set_property_bool('window-maximized',not mp.get_property_bool('window-maximized',false))
end)
mp.add_key_binding(nil,'pip',function()
    if pip then
        mp.set_property_bool('ontop',pip.ontop)
        mp.set_property('geometry',pip.width..'x'..pip.height)
        mp.set_property_bool('window-maximized',pip.maximized)
        mp.set_property_bool('fullscreen',pip.fullscreen)
        pip=nil
    else
        pip={width=mp.get_property_number('osd-width',1280),height=mp.get_property_number('osd-height',720),
            maximized=mp.get_property_bool('window-maximized',false),fullscreen=mp.get_property_bool('fullscreen',false),ontop=mp.get_property_bool('ontop',false)}
        mp.set_property_bool('fullscreen',false); mp.set_property_bool('window-maximized',false)
        mp.set_property('geometry','480x270-24-24'); mp.set_property_bool('ontop',true)
    end
end)
mp.add_key_binding(nil,'percent-seek',function(_,key)
    local digit=tonumber(key)
    if digit then mp.commandv('seek',tostring(digit*10),'absolute-percent') end
end)
mp.add_timeout(0.3,function()
    mp.commandv('script-message-to','uosc','set-button','night',utils.format_json({icon='bedtime',active=false,
        tooltip='Ночной звук',command={'script-binding','player_tools/night'}}))
end)
local function volume_button()
    local muted=mp.get_property_bool('mute',false) or mp.get_property_number('volume',0)==0
    mp.commandv('script-message-to','uosc','set-button','volume',utils.format_json({
        icon=muted and 'volume_off' or 'volume_up',tooltip=muted and 'Включить звук' or 'Выключить звук',command={'cycle','mute'}}))
end
mp.observe_property('mute','bool',volume_button)
mp.observe_property('volume','number',volume_button)
mp.add_timeout(0.3,volume_button)
