local mp=require 'mp'
local utils=require 'mp.utils'
local context=dofile(mp.command_native({'expand-path','~~/script-modules/neon-context.lua'}))
local extensions={aac=true,ac3=true,eac3=true,dts=true,flac=true,m4a=true,m4b=true,mka=true,mp2=true,mp3=true,ogg=true,opus=true,wav=true,wma=true,weba=true,aiff=true,aif=true,ape=true,alac=true,tta=true}
local candidates={}
local uppercase='АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
local lowercase='абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
local chars={};for c in lowercase:gmatch('[%z\1-\127\194-\244][\128-\191]*')do chars[#chars+1]=c end
local case={};local i=0;for c in uppercase:gmatch('[%z\1-\127\194-\244][\128-\191]*')do i=i+1;case[c]=chars[i]end
local function lower(s)return (s:gsub('[%z\1-\127\194-\244][\128-\191]*',case)):lower()end
local function absolute(p)
    if not p:match('^%a:[/\\]') and not p:match('^[/\\]') then p=utils.join_path(mp.get_property('working-directory'),p)end
    return p
end
local function normal(p)return lower(absolute(p):gsub('\\','/'))end
local function stem(s)return lower(s:gsub('%.[^.]+$',''))end
local function clean(s)
    return stem(s):gsub('%b[]',' '):gsub('%b()',' '):gsub('%d%d%d+[pi]',' '):gsub('[%s%p]','')
end
local function episode(name)
    local s=stem(name)
    local season,number=s:match('s(%d+)[%s._-]*e(%d+)')
    if number then return tonumber(number),tonumber(season)end
    number=s:match('ep[%s._-]*(%d+)') or s:match('(%d+)%s*серия') or s:match('серия%s*(%d+)')
    for n in s:gmatch('%s%-%s*(%d+)')do number=n end
    number=number or s:match('%[(%d%d?)%]')
    s=s:gsub('%b[]',' '):gsub('%b()',' '):gsub('%d%d%d+[pi]',' '):gsub('%s+$','')
    number=number or s:match('^%s*(%d+)%s*$') or s:match('[%s._-](%d+)$')
    if number and tonumber(number)<500 then return tonumber(number)end
end
local function match_audio(video,audio,folder)
    local ve,vs=episode(video);local ae,as=episode(audio)
    if ve and ae and (ve~=ae or (vs and as and vs~=as))then return false end
    local a,v=clean(audio),clean(video)
    if #a>3 and #v>3 and (a:find(v,1,true) or v:find(a,1,true))then return true end
    -- Audio packs often use just episode numbers inside the voice group's folder.
    if ve and ae and ve==ae then
        if folder~='' then return true end
        return a:match('^%d+$')~=nil
    end
    return a==v and a~=''
end
local function loaded()
    local map={}
    for _,track in ipairs(mp.get_property_native('track-list',{}))do
        if track.type=='audio' and track['external-filename'] then map[normal(track['external-filename'])]=track end
    end
    return map
end
local function publish()mp.set_property_native('user-data/external-audio/candidates',candidates)end
local function scan()
    candidates={}
    local path=mp.get_property('path','')
    if path=='' or path:match('^%a[%w+.-]*://')then publish();return end
    path=absolute(path)
    local dir,video=utils.split_path(path)
    local function directory(location,label)
        for _,file in ipairs(utils.readdir(location,'files') or {})do
            local ext=file:match('%.([^.]+)$')
            if ext and extensions[ext:lower()] then
                candidates[#candidates+1]={path=utils.join_path(location,file),filename=file,folder=label,
                    matching=match_audio(video,file,label),extension=ext:upper()}
            end
        end
    end
    directory(dir,'')
    local folders=utils.readdir(dir,'dirs') or {};table.sort(folders)
    for _,name in ipairs(folders)do
        if name~='.' and name~='..' and name:sub(1,1)~='.' then directory(utils.join_path(dir,name),name)end
    end
    table.sort(candidates,function(a,b)
        if a.matching~=b.matching then return a.matching end
        return lower(a.folder..'/'..a.filename)<lower(b.folder..'/'..b.filename)
    end)
    publish()
end
local menu
local function row(c,index)
    local label=c.folder~='' and c.filename:gsub('^%b[]%s*','') or c.filename
    return {title=(c.folder~='' and c.folder..' · ' or '')..label,hint=c.extension,
        value={'script-message-to','external_audio','add',tostring(index)},keep_open=false}
end
menu=function()
    local items={{title='Выключить звук',active=mp.get_property('aid')=='no',value={'set','aid','no'},keep_open=false}}
    for _,t in ipairs(mp.get_property_native('track-list',{}))do if t.type=='audio'then
        local label=t.title or ('Дорожка '..t.id)
        if t.external and t['external-filename'] then
            local _,name=utils.split_path(t['external-filename']);local ext=name:match('%.([^.]+)$')
            if not t.title or (ext and lower(t.title)==lower(ext)) then label=name end
        end
        local hint={};if t.lang then hint[#hint+1]=t.lang end;if t.codec then hint[#hint+1]=t.codec end
        if t.external then hint[#hint+1]='Внешняя' end
        items[#items+1]={title=label,hint=table.concat(hint,' · '),active=t.selected,
            value={'set','aid',tostring(t.id)},keep_open=false}
    end end
    local existing=loaded();local matching,others={},{}
    for index,c in ipairs(candidates)do if not existing[normal(c.path)]then
        local list=c.matching and matching or others;list[#list+1]=row(c,index)
    end end
    if #matching>0 then
        items[#items+1]={title='Внешние дорожки для этого видео',selectable=false,muted=true,separator=true}
        for _,entry in ipairs(matching)do items[#items+1]=entry end
    end
    if #others>0 then items[#items+1]={title='Другие аудиофайлы рядом',hint=tostring(#others),items=others}end
    if #candidates==0 then items[#items+1]={title='Отдельных аудиофайлов рядом не найдено',selectable=false,muted=true}end
    items[#items+1]={title='Выбрать аудиофайл вручную…',value={'script-binding','uosc/load-audio'},keep_open=false,separator=true}
    items[#items+1]={title='Обновить поиск рядом с видео',value={'script-binding','external_audio/rescan'},keep_open=true}
    local data={type='external-audio',title='Аудиодорожка',items=items,footnote='Поиск: папка видео и её подпапки · дорожка подключается при выборе'}
    mp.set_property_native('user-data/external-audio/menu',data)
    context.open(utils.format_json(data))
end
mp.register_script_message('add',function(id)
    local candidate=candidates[tonumber(id)];if not candidate then return end
    local track=loaded()[normal(candidate.path)]
    if track then mp.set_property_number('aid',track.id);return end
    local title=(candidate.folder~='' and candidate.folder..' · ' or '')..candidate.filename
    local ok,err=mp.commandv('audio-add',candidate.path,'select',title)
    if not ok then mp.msg.error(tostring(err));mp.osd_message('Не удалось открыть аудиодорожку',3)end
end)
mp.add_key_binding(nil,'menu',function()
    if mp.get_property_native('user-data/uosc/menu/type')=='external-audio' then mp.commandv('script-message-to','uosc','close-menu','external-audio')
    else menu()end
end)
mp.add_key_binding(nil,'rescan',function()scan();menu()end)
mp.register_event('file-loaded',scan)
mp.register_event('end-file',function()candidates={};publish()end)
context.register({menu=menu})
