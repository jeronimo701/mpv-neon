local neon_context=dofile(require('mp').command_native({'expand-path','~~/script-modules/neon-context.lua'}))
-- TorrServer Matrix client. API requests are asynchronous; arguments bypass a shell.
local mp = require 'mp'
local utils = require 'mp.utils'
local input = require 'mp.input'
local opts = {server='http://127.0.0.1:8090', timeout=20, username='', password='',
    auto_start=true,fallback_port=8099,fallback_data='',skip_discovery=false}
require('mp.options').read_options(opts, 'torrserver')
opts.server = opts.server:gsub('/+$', '')
local primary_server=opts.server
local ready,busy=false,false
local waiting={}
local function ensure_server(callback)
    if ready or not opts.auto_start then callback(true); return end
    waiting[#waiting+1]=callback
    if busy then return end
    busy=true
    mp.set_property_bool('user-data/torrserver/ready',false)
    local helper=mp.command_native({'expand-path','~~/../runtime/torrserver/Ensure-TorrServer.ps1'})
    local args={'powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',helper,'-PrimaryServer',primary_server,'-FallbackPort',tostring(opts.fallback_port)}
    if opts.fallback_data~='' then args[#args+1]='-DataDir'; args[#args+1]=mp.command_native({'expand-path',opts.fallback_data}) end
    if opts.skip_discovery then args[#args+1]='-SkipDiscovery' end
    mp.command_native_async({name='subprocess',args=args,playback_only=false,capture_stdout=true,capture_stderr=true},function(success,result)
        local data=result and utils.parse_json(result.stdout or '')
        ready=success and result.status==0 and type(data)=='table' and data.ok==true
        if ready then
            opts.server=data.server
            if opts.server~=primary_server then opts.username=''; opts.password='' end
            mp.set_property('user-data/torrserver/server',opts.server)
            mp.set_property('user-data/torrserver/source',data.source)
            mp.set_property('user-data/torrserver/version',data.version)
            mp.msg.info('TorrServer: '..opts.server..' ('..data.source..', '..data.version..')')
        else
            mp.msg.warn('TorrServer startup: '..tostring(data and data.error or 'helper failed'))
        end
        mp.set_property_bool('user-data/torrserver/ready',ready)
        busy=false
        local callbacks=waiting; waiting={}
        for _,fn in ipairs(callbacks) do fn(ready) end
    end)
end
local serial = 0
local function menu(title, items, footnote)
    neon_context.open( utils.format_json({
        type='torrserver', title=title, items=items, footnote=footnote}))
end
local function info(text)
    mp.osd_message(text, 5)
end
local function request(body, callback)
    ensure_server(function(available)
    if not available then info('Не удалось подключить или запустить TorrServer. Проверьте настройки и журнал.'); return end
    local args = {'curl.exe', '--silent', '--show-error', '--fail', '--connect-timeout', '5',
        '--max-time', tostring(opts.timeout), '--header', 'Content-Type: application/json',
        '--data-raw', utils.format_json(body)}
    if opts.username ~= '' then
        args[#args+1] = '--user'
        args[#args+1] = opts.username .. ':' .. opts.password
    end
    args[#args+1] = opts.server .. '/torrents'
    mp.command_native_async({name='subprocess', args=args,
        playback_only=false, capture_stdout=true, capture_stderr=true}, function(success, result)
        if not success or not result or result.status ~= 0 then
            ready=false
            mp.msg.warn('TorrServer request failed: ' .. tostring(result and result.status))
            info('TorrServer недоступен. Нажмите F3 для повторного поиска и запуска.')
            return
        end
        local data = utils.parse_json(result.stdout)
        if not data then info('TorrServer вернул некорректный ответ'); return end
        callback(data)
    end)
    end)
end
local function encode(value)
    return tostring(value):gsub('([^%w%-_%.~])', function(c) return string.format('%%%02X', c:byte()) end)
end
local function stream_url(hash, file)
    local base = opts.server
    if opts.username ~= '' then
        base = base:gsub('^(https?://)', function(scheme)
            return scheme .. encode(opts.username) .. ':' .. encode(opts.password) .. '@'
        end)
    end
    return base .. '/stream/' .. encode((file.path or 'video'):match('[^/\\]+$') or 'video')
        .. '?link=' .. encode(hash) .. '&index=' .. tostring(file.id) .. '&play'
end
local function play(hash, index)
    request({action='get', hash=hash}, function(torrent)
        for _, file in ipairs(torrent.file_stats or {}) do
            if tostring(file.id) == tostring(index) then
                local url = stream_url(hash, file)
                local title = (file.path or torrent.title or 'TorrServer'):match('[^/\\]+$')
                mp.command_native({'loadfile', url, 'replace', -1, {['force-media-title']=title}})
                return
            end
        end
        info('Файл пока недоступен: обновите список после загрузки метаданных.')
    end)
end
local function show_files(hash)
    serial = serial + 1
    local token = serial
    info('TorrServer: получаю список файлов…')
    request({action='get', hash=hash}, function(torrent)
        if token ~= serial then return end
        local items = {{title='← Все торренты', value={'script-binding', 'torrserver/menu'}}}
        local files = {}
        for _, file in ipairs(torrent.file_stats or {}) do
            local ext = (file.path or ''):match('%.([^%.]+)$')
            if ext and ({mkv=true,mp4=true,avi=true,mov=true,webm=true,m4v=true,ts=true,m2ts=true,mpg=true,mpeg=true,wmv=true,flv=true,ogv=true})[ext:lower()] then
                files[#files+1] = file
            end
        end
        table.sort(files, function(a,b) return (a.path or '') < (b.path or '') end)
        for _, file in ipairs(files) do
            items[#items+1] = {title=file.path, hint=string.format('%.2f ГБ', (file.length or 0)/1073741824),
                value={'script-message-to', 'torrserver', 'play', hash, tostring(file.id)}}
        end
        if #files == 0 then
            items[#items+1] = {title='Обновить — ожидание метаданных', value={'script-message-to', 'torrserver', 'files', hash}}
        end
        mp.set_property_number('user-data/torrserver/file-count', #files)
        menu(torrent.title or torrent.name or 'Файлы торрента', items, 'Выберите файл для воспроизведения')
    end)
end
local function show_torrents()
    serial = serial + 1
    local token = serial
    info('TorrServer: подключаюсь…')
    request({action='list'}, function(torrents)
        if token ~= serial then return end
        local items = {
            {title='Добавить magnet / torrent URL', icon='add', value={'script-binding', 'torrserver/add'}},
            {title='Веб-интерфейс TorrServer', icon='open_in_browser', value={'script-binding', 'torrserver/browser'}},
            {title='Обновить список', icon='refresh', value={'script-binding', 'torrserver/menu'}},
        }
        for _, torrent in ipairs(torrents) do
            if torrent.hash then
                items[#items+1] = {title=torrent.title or torrent.name or torrent.hash,
                    hint=torrent.stat_string or '',
                    value={'script-message-to', 'torrserver', 'files', torrent.hash}}
            end
        end
        mp.set_property_number('user-data/torrserver/torrent-count', #torrents)
        mp.osd_message('', 0)
        menu('TorrServer', items, opts.server .. ' • ' .. #torrents .. ' торрентов')
    end)
end
mp.add_key_binding(nil, 'menu', show_torrents)
mp.add_key_binding(nil, 'browser', function()
    ensure_server(function(ok)
        if ok then mp.command_native_async({name='subprocess', args={'explorer.exe', opts.server}, playback_only=false}, function() end)
        else info('TorrServer пока недоступен.') end
    end)
end)
local function add_link(text)
    text = text:match('^%s*(.-)%s*$')
    local is_hash = #text == 40 and text:match('^%x+$')
    if not (text:match('^magnet:%?') or text:match('^https?://') or text:match('^torrs://') or is_hash) then
        info('Нужна magnet-ссылка, HTTP(S) URL .torrent или infohash.'); return
    end
    request({action='add', link=text, save_to_db=true}, function(torrent)
        if torrent.hash then show_files(torrent.hash) else show_torrents() end
    end)
end
mp.add_key_binding(nil, 'add', function()
    input.get({prompt='TorrServer: magnet или URL .torrent', submit=add_link})
end)
mp.register_script_message('add-link', add_link)
mp.register_script_message('files', show_files)
mp.register_script_message('play', play)
mp.add_timeout(0.3,function() ensure_server(function() end) end)
