-- Separate Windows playlist. A private per-process mailbox keeps it portable.
local mp=require 'mp'
local utils=require 'mp.utils'
local pref=mp.command_native({'expand-path','~~/playlist-window.json'})
local exe=mp.command_native({'expand-path','~~/../native/PlaylistWindow.exe'})
local base=os.tmpname();os.remove(base)
local state_file=base..'.state.json'
local command_file=base..'.command.json'
local closed_file=base..'.closed'
local enabled=false
local running=false
local stopping=false
local f=io.open(pref,'rb')
if f then local data=utils.parse_json(f:read('*a'));f:close();enabled=type(data)=='table' and data.enabled==true end
local function write(path,data)
    local out=io.open(path,'wb');if not out then return false end
    out:write(data);out:close();return true
end
local function publish()
    mp.set_property_bool('user-data/playlist-window/enabled',enabled)
    write(state_file,utils.format_json({enabled=enabled and not stopping,pause=mp.get_property_bool('pause',false),
        playlist=mp.get_property_native('playlist',{}),position=mp.get_property_number('playlist-pos',-1)}))
end
local function save()write(pref,utils.format_json({enabled=enabled}))end
local start
local function set_enabled(value)
    enabled=value;save();publish()
    if enabled and not running then start() end
end
start=function()
    if running or stopping or not enabled then return end
    os.remove(closed_file);publish();running=true
    mp.command_native_async({name='subprocess',args={exe,state_file,command_file,closed_file},
        playback_only=false,capture_stderr=true},function(success,result,error)
        running=false
        local closed=io.open(closed_file,'rb')
        if closed then closed:close();os.remove(closed_file);enabled=false;save();publish()
        elseif not stopping and enabled then
            if not success or not result or result.status~=0 then
                enabled=false;save();publish()
                mp.msg.error('Playlist window: '..tostring(error or (result and result.stderr)))
                mp.osd_message('Не удалось открыть окно плейлиста',4)
            else mp.add_timeout(0.2,start) end
        end
    end)
end
local function index_of(id)
    for i,item in ipairs(mp.get_property_native('playlist',{})) do if item.id==tonumber(id) then return i-1 end end
end
local function consume()
    local f=io.open(command_file,'rb');if not f then return end
    local data=utils.parse_json(f:read('*a'));f:close();os.remove(command_file)
    if type(data)~='table' then return end
    local index=index_of(data.id)
    if data.action=='play' and index then mp.set_property_number('playlist-pos',index);mp.set_property_bool('pause',false)
    elseif data.action=='remove' and index then mp.commandv('playlist-remove',index)
    elseif data.action=='move' and index and (data.delta==1 or data.delta==-1) then
        local count=mp.get_property_number('playlist-count',0)
        local target=index+data.delta
        if target>=0 and target<count then mp.commandv('playlist-move',index,target) end
    elseif data.action=='add' and type(data.paths)=='table' then
        for _,path in ipairs(data.paths) do if type(path)=='string' then mp.commandv('loadfile',path,'append-play') end end
    elseif data.action=='pause' then mp.commandv('cycle','pause')
    elseif data.action=='next' then mp.commandv('playlist-next','weak')
    elseif data.action=='prev' then mp.commandv('playlist-prev','weak') end
end
mp.add_periodic_timer(0.25,function()
    if running then consume() end
    local closed=io.open(closed_file,'rb')
    if closed then closed:close();os.remove(closed_file);if enabled then set_enabled(false) end end
    if enabled or running then publish() end
end)
mp.add_key_binding(nil,'toggle',function()set_enabled(not enabled)end)
mp.register_script_message('set',function(v)set_enabled(v=='yes' or v=='true' or v=='1')end)
mp.register_event('shutdown',function()
    stopping=true;publish();os.remove(command_file);os.remove(closed_file)
    -- The helper removes its state file on exit; no command channel survives.
    if not running then os.remove(state_file) end
end)
mp.add_timeout(0.2,function()mp.set_property_bool('user-data/playlist-window/enabled',enabled);if enabled then start() end end)
