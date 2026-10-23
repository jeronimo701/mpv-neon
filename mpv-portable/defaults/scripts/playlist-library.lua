local mp=require 'mp'
local utils=require 'mp.utils'
local input=require 'mp.input'
local context=dofile(mp.command_native({'expand-path','~~/script-modules/neon-context.lua'}))
local opt={library_file='~~/playlists.json',restore=true}
require('mp.options').read_options(opt,'playlist-library')
local path=mp.command_native({'expand-path',opt.library_file})
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end
local disk=read(path)
local bank
if disk then bank=utils.parse_json(disk) else bank={version=1,active='default',lists={{id='default',name='Основной',items={},position=0,time=0}}} end
local valid=type(bank)=='table' and bank.version==1 and type(bank.lists)=='table' and #bank.lists>0
if valid then
    local ids={}
    for _,list in ipairs(bank.lists) do
        if type(list)~='table' or type(list.id)~='string' or ids[list.id] or type(list.name)~='string' or type(list.items)~='table' then valid=false;break end
        ids[list.id]=true
        for _,item in ipairs(list.items) do if type(item)~='table' or type(item.filename)~='string' then valid=false;break end end
    end
end
local writable=valid
if not valid then
    mp.msg.error('Playlist library is invalid; original is left untouched.')
    bank={version=1,active='recovery',lists={{id='recovery',name='Временный — файл библиотеки повреждён',items={},position=0,time=0}}}
end
local switching,initialized=false,false
local linked=false
local pending_seek
local counter=0
local function active()
    for _,list in ipairs(bank.lists) do if list.id==bank.active then return list end end
    bank.active=bank.lists[1].id;return bank.lists[1]
end
local function publish()
    local lists={}
    for _,list in ipairs(bank.lists) do lists[#lists+1]={id=list.id,name=list.name,count=#list.items} end
    mp.set_property_native('user-data/playlist-library/state',{active=bank.active,lists=lists,writable=writable})
end
local function snapshot()
    linked=true
    local list=active();list.items={}
    for _,item in ipairs(mp.get_property_native('playlist',{})) do
        local filename=item.filename
        if not filename:match('^%a[%w+.-]*://') and not filename:match('^%a:[/\\]') and filename:sub(1,2)~='\\\\' then filename=utils.join_path(mp.get_property('working-directory'),filename) end
        list.items[#list.items+1]={filename=filename,title=item.title}
    end
    list.position=math.max(0,mp.get_property_number('playlist-pos',0))
    list.time=mp.get_property_number('time-pos',list.time or 0)
    publish()
end
local function save()
    if not writable then return false end
    if read(path)~=disk then
        writable=false;publish();mp.osd_message('Библиотека плейлистов изменилась в другом окне.\nСохранение остановлено, чтобы не затереть списки.',8);return false
    end
    local raw=utils.format_json(bank)
    local tmp=path..'.'..utils.getpid()..'.tmp'
    local f,err=io.open(tmp,'wb')
    if not f then mp.msg.error(tostring(err));return false end
    f:write(raw);f:close()
    if disk then
        os.remove(path..'.bak')
        if not os.rename(path,path..'.bak') then os.remove(tmp);return false end
    end
    if not os.rename(tmp,path) then if disk then os.rename(path..'.bak',path) end;return false end
    disk=raw;return true
end
local debounce
local function changed()
    if not initialized or switching then return end
    if not linked and mp.get_property_number('playlist-count',0)==0 then return end
    if debounce then debounce:kill() end
    debounce=mp.add_timeout(0.3,function()if not switching then snapshot();save()end end)
end
local function restore(list)
    if debounce then debounce:kill() end
    linked=true
    switching=true
    if #list.items>0 then
        mp.set_property_bool('pause',true)
        for i,item in ipairs(list.items) do
            local flag=i==1 and 'replace' or 'append'
            if item.title then mp.command_native({'loadfile',item.filename,flag,-1,{['force-media-title']=item.title}})
            else mp.commandv('loadfile',item.filename,flag) end
        end
        local pos=math.max(0,math.min(#list.items-1,tonumber(list.position) or 0))
        pending_seek={filename=list.items[pos+1].filename,position=pos,time=tonumber(list.time) or 0}
        mp.set_property_number('playlist-pos',pos)
    else mp.commandv('stop');mp.commandv('playlist-clear') end
    mp.add_timeout(0.5,function()switching=false;publish()end)
end
local function select(id)
    for _,list in ipairs(bank.lists) do if list.id==id then
        if linked then snapshot() end;bank.active=id;restore(list);save();publish();return
    end end
end
local menu
local function create(name)
    name=tostring(name or ''):match('^%s*(.-)%s*$')
    if name=='' or #name>240 or #bank.lists>=100 then return end
    if linked then snapshot() end;counter=counter+1
    local id=os.time()..'-'..utils.getpid()..'-'..counter
    bank.lists[#bank.lists+1]={id=id,name=name,items={},position=0,time=0}
    bank.active=id;restore(active());save();publish()
end
menu=function()
    local items={{title='Создать плейлист…',icon='add',value={'script-message-to','playlist_library','new'}},
        {title='Переименовать текущий…',value={'script-message-to','playlist_library','rename'}},
        {title='Удалить текущий список…',value={'script-message-to','playlist_library','delete'}},
        {title='Отдельное окно / вкладки',value={'script-binding','playlist_window/toggle'}}}
    for _,list in ipairs(bank.lists) do items[#items+1]={id=list.id,title=list.name,hint=#list.items..' файлов',active=list.id==bank.active,
        value={'script-message-to','playlist_library','select',list.id}} end
    context.open(utils.format_json({type='playlist-library',title='Мои плейлисты',items=items,
        footnote='Списки сохраняются автоматически · при переключении и запуске воспроизведение на паузе · файлы не удаляются'}))
end
mp.register_script_message('new',function(name)
    if name and name~='' then create(name) else input.get({prompt='Название нового плейлиста',submit=create}) end
end)
mp.register_script_message('rename',function(name)
    local function submit(value)if value and value:match('%S') and #value<=240 then active().name=value;save();publish();menu()end end
    if name and name~='' then submit(name)else input.get({prompt='Название плейлиста',default_text=active().name,submit=submit}) end
end)
mp.register_script_message('delete',function()
    if #bank.lists<=1 then mp.osd_message('Последний список нельзя удалить. Можно убрать его элементы.',4);return end
    local list=active()
    context.open(utils.format_json({type='playlist-delete',title='Удалить список «'..list.name..'»?',items={
        {title='Отмена',value={'script-binding','playlist_library/menu'}},
        {title='Удалить только список, не файлы',value={'script-message-to','playlist_library','delete-confirm',list.id}}}}))
end)
mp.register_script_message('delete-confirm',function(id)
    if #bank.lists<=1 then return end
    for i,list in ipairs(bank.lists) do if list.id==id then
        local was_active=bank.active==id;table.remove(bank.lists,i)
        if was_active then bank.active=bank.lists[1].id;restore(active()) end
        save();publish();return
    end end
end)
mp.register_script_message('select',select)
mp.register_script_message('save',function()snapshot();save()end)
mp.add_key_binding(nil,'menu',menu)
mp.observe_property('playlist','native',changed)
mp.observe_property('playlist-pos','number',changed)
mp.register_event('file-loaded',function()
    if pending_seek and mp.get_property('path')==pending_seek.filename and mp.get_property_number('playlist-pos')==pending_seek.position then
        if pending_seek.time>0 then mp.commandv('seek',pending_seek.time,'absolute','exact') end
        pending_seek=nil
    end
end)
mp.register_event('shutdown',function()if initialized and linked and not switching then snapshot();save()end end)
mp.add_periodic_timer(4,function()if initialized and linked and not switching then snapshot();save()end end)
mp.add_timeout(0.7,function()
    if mp.get_property_number('playlist-count',0)==0 then if opt.restore then restore(active()) end else
        local incoming=mp.get_property_native('playlist',{})
        local saved=active();local different=#incoming~=#saved.items
        if not different then for i,item in ipairs(incoming)do
            local name=item.filename
            if not name:match('^%a[%w+.-]*://') and not name:match('^%a:[/\\]') and name:sub(1,2)~='\\\\' then name=utils.join_path(mp.get_property('working-directory'),name) end
            if name~=saved.items[i].filename then different=true;break end
        end end
        if #incoming>0 and #saved.items>0 and different then
            counter=counter+1
            local id=os.time()..'-'..utils.getpid()..'-'..counter
            bank.lists[#bank.lists+1]={id=id,name='Открыто: '..mp.get_property('media-title','Новый файл'),items={},position=0,time=0}
            bank.active=id
        end
        snapshot()
    end
    initialized=true;publish()
end)
context.register({menu=menu})
