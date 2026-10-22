local mp=require 'mp'
local neon_context=dofile(mp.command_native({'expand-path','~~/script-modules/neon-context.lua'}))
-- sponsorblock.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock

local ON_WINDOWS = package.config:sub(1,1) ~= "/"

local options = {
    server_address = "https://sponsor.ajay.app",

    python_path = ON_WINDOWS and mp.command_native({'expand-path', '~~/../runtime/python/python.exe'}) or "python3",

    -- Categories to fetch
    categories = "sponsor,intro,outro,interaction,selfpromo,filler",

    -- Categories to skip automatically
    skip_categories = "sponsor",

    -- If true, sponsored segments will only be skipped once
    skip_once = true,

    -- Note that sponsored segments may ocasionally be inaccurate if this is turned off
    -- see https://blog.ajay.app/voting-and-pseudo-randomness-or-sponsorblock-or-youtube-sponsorship-segment-blocker
    local_database = false,

    -- Update database on first run, does nothing if local_database is false
    auto_update = true,

    -- How long to wait between local database updates
    -- Format: "X[d,h,m]", leave blank to update on every mpv run
    auto_update_interval = "6h",

    -- User ID used to submit sponsored segments, leave blank for random
    user_id = "",

    -- Name to display on the stats page https://sponsor.ajay.app/stats/ leave blank to keep current name
    display_name = "",

    -- Tell the server when a skip happens
    report_views = true,

    -- Auto upvote skipped sponsors
    auto_upvote = false,

    -- Use sponsor times from server if they're more up to date than our local database
    server_fallback = true,

    -- Create chapters at sponsor boundaries for OSC display and manual skipping
    make_chapters = true,

    -- Minimum duration for sponsors (in seconds), segments under that threshold will be ignored
    min_duration = 1,

    -- Fade audio for smoother transitions
    audio_fade = false,

    -- Audio fade step, applied once every 100ms until cap is reached
    audio_fade_step = 10,

    -- Audio fade cap
    audio_fade_cap = 0,

    -- Fast forward through sponsors instead of skipping
    fast_forward = false,

    -- Playback speed modifier when fast forwarding, applied once every second until cap is reached
    fast_forward_increase = .2,

    -- Playback speed cap
    fast_forward_cap = 2,

    -- Length of the sha256 prefix (3-32) when querying server, 0 to disable
    sha256_length = 4,

    -- Pattern for video id in local files, ignored if blank
    -- Recommended value for base youtube-dl is "-([%w-_]+)%.[mw][kpe][v4b]m?$"
    local_pattern = "",

    -- Legacy option, use skip_categories instead
    skip = true
}

mp.options = require "mp.options"
mp.options.read_options(options, "sponsorblock")

local legacy = mp.command_native_async == nil
--[[
if legacy then
    options.local_database = false
end
--]]
options.local_database = false

local utils = require "mp.utils"
scripts_dir = mp.find_config_file("scripts")

local sponsorblock = utils.join_path(scripts_dir, "sponsorblock_shared/sponsorblock.py")
local uid_path = utils.join_path(scripts_dir, "sponsorblock_shared/sponsorblock.txt")
local database_file = options.local_database and utils.join_path(scripts_dir, "sponsorblock_shared/sponsorblock.db") or ""
local youtube_id = nil
local ranges = {}
local init = false
local segment = {a = 0, b = 0, progress = 0, first = true}
local retrying = false
local last_skip = {uuid = "", dir = nil}
local speed_timer = nil
local fade_timer = nil
local fade_dir = nil
local volume_before = mp.get_property_number("volume")
local categories = {}
local all_categories = {"sponsor", "intro", "outro", "interaction", "selfpromo", "preview", "music_offtopic", "filler"}
local chapter_cache = {}
local sb_labels={sponsor='Рекламные интеграции',intro='Заставка / вступление',outro='Концовка / титры',interaction='Просьбы подписаться и поставить лайк',selfpromo='Самореклама автора',preview='Анонсы / повтор фрагментов',music_offtopic='Немузыкальные вставки в клипах',filler='Паузы и отступления'}
local sb_enabled=options.skip~=false
local sb_mode=options.fast_forward and 'fast' or 'skip'
local sb_payload
local sb_generation=0
local sb_fetch_state=""
local sb_chapter_titles={}
local sb_speed_before=1
local sb_state_path=mp.command_native({'expand-path','~~/sponsorblock-settings.json'})
local sb_defaults={enabled=sb_enabled,mode=sb_mode,skip_once=options.skip_once,make_chapters=options.make_chapters,min_duration=options.min_duration,skip_categories=options.skip_categories}
do
    local f=io.open(sb_state_path,'r')
    if f then
        local data=utils.parse_json(f:read('*a'));f:close()
        if type(data)=='table' then
            if type(data.enabled)=='boolean' then sb_enabled=data.enabled end
            if data.mode=='skip' or data.mode=='fast' or data.mode=='chapters' then sb_mode=data.mode end
            for _,key in ipairs({'skip_once','make_chapters'})do if type(data[key])=='boolean' then options[key]=data[key] end end
            if type(data.min_duration)=='number' and data.min_duration==data.min_duration and data.min_duration>=0 and data.min_duration<=60 then options.min_duration=data.min_duration end
            if type(data.skip_categories)=='string' then
                local ids={};for id in data.skip_categories:gmatch('[^,]+')do if sb_labels[id] then ids[#ids+1]=id end end
                options.skip_categories=table.concat(ids,',')
            end
        end
    end
end
options.categories=table.concat(all_categories,',')
options.fast_forward=sb_mode=='fast'
options.skip=true


for category in string.gmatch(options.skip_categories, "([^,]+)") do
    categories[category] = true
end

function file_exists(name)
    local f = io.open(name,"r")
    if f ~= nil then io.close(f) return true else return false end
end

function t_count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function time_sort(a, b)
    if a.time == b.time then
        return string.match(a.title, "segment end")
    end
    return a.time < b.time
end

function parse_update_interval()
    local s = options.auto_update_interval
    if s == "" then return 0 end -- Interval Disabled

    local num, mod = s:match "^(%d+)([hdm])$"

    if num == nil or mod == nil then
        mp.osd_message("[sponsorblock] auto_update_interval " .. s .. " is invalid", 5)
        return nil
    end

    local time_table = {
        m = 60,
        h = 60 * 60,
        d = 60 * 60 * 24,
    }

    return num * time_table[mod]
end

function clean_chapters()
    local chapters = mp.get_property_native("chapter-list")
    local new_chapters = {}
    for _, chapter in pairs(chapters) do
        if chapter.title ~= "Preview segment start" and chapter.title ~= "Preview segment end" then
            table.insert(new_chapters, chapter)
        end
    end
    mp.set_property_native("chapter-list", new_chapters)
end

function create_chapter(chapter_title, chapter_time)
    local chapters = mp.get_property_native("chapter-list")
    local duration = mp.get_property_native("duration")
    table.insert(chapters, {title=chapter_title, time=(duration == nil or duration > chapter_time) and chapter_time or duration - .001})
    table.sort(chapters, time_sort)
    mp.set_property_native("chapter-list", chapters)
end

function process(uuid, t, new_ranges)
    start_time = tonumber(string.match(t, "[^,]+"))
    end_time = tonumber(string.sub(string.match(t, ",[^,]+"), 2))
    for o_uuid, o_t in pairs(ranges) do
        if (start_time >= o_t.start_time and start_time <= o_t.end_time) or (o_t.start_time >= start_time and o_t.start_time <= end_time) then
            new_ranges[o_uuid] = o_t
            return
        end
    end
    category = string.match(t, "[^,]+$")
    if categories[category] and end_time - start_time >= options.min_duration then
        new_ranges[uuid] = {
            start_time = start_time,
            end_time = end_time,
            category = category,
            skipped = false
        }
    end
    if options.make_chapters and not chapter_cache[uuid] then
        chapter_cache[uuid] = true
        local category_title = (category:gsub("^%l", string.upper):gsub("_", " "))
        local first=category_title .. " segment start (" .. string.sub(uuid, 1, 6) .. ")"
        local last=category_title .. " segment end (" .. string.sub(uuid, 1, 6) .. ")"
        sb_chapter_titles[first]=true;sb_chapter_titles[last]=true
        create_chapter(first, start_time)
        create_chapter(last, end_time)
    end
end

function getranges(_, exists, db, more)
    if type(exists) == "table" and exists["status"] == "1" then
        if options.server_fallback then
            mp.add_timeout(0, function() getranges(true, true, "") end)
        else
            return mp.osd_message("[sponsorblock] database update failed, gave up")
        end
    end
    if db ~= "" and db ~= database_file then db = database_file end
    if exists ~= true and not file_exists(db) then
        if not retrying then
            mp.osd_message("[sponsorblock] database update failed, retrying...")
            retrying = true
        end
        return update()
    end
    if retrying then
        mp.osd_message("[sponsorblock] database update succeeded")
        retrying = false
    end
    local args = {
        options.python_path,
        sponsorblock,
        "ranges",
        db,
        options.server_address,
        youtube_id,
        options.categories,
        tostring(options.sha256_length)
    }
    local generation=sb_generation
    sb_fetch_state='loading'
    local function receive(success,sponsors)
        if generation~=sb_generation or not sb_enabled then return end
        if not success or not sponsors or sponsors.status~=0 then
            sb_fetch_state='error';if sb_menu_publish then sb_menu_publish() end;return
        end
        sb_fetch_state='ready'
        sponsors.stdout=sponsors.stdout or ''
    mp.msg.debug("Got: " .. string.gsub(sponsors.stdout, "[\n\r]", ""))
    if not string.match(sponsors.stdout, "^%s*(.*%S)") then sb_payload="";if sb_menu_publish then sb_menu_publish() end;return end
    if string.match(sponsors.stdout, "error") then sb_fetch_state="error";mp.msg.warn("SponsorBlock: segments unavailable");if sb_menu_publish then sb_menu_publish() end;return end
    sb_payload=sponsors.stdout
    local new_ranges = {}
    local r_count = 0
    if more then r_count = -1 end
    for t in string.gmatch(sponsors.stdout, "[^:%s]+") do
        uuid = string.match(t, "([^,]+),[^,]+$")
        if ranges[uuid] then
            new_ranges[uuid] = ranges[uuid]
        else
            process(uuid, t, new_ranges)
        end
        r_count = r_count + 1
    end
    local c_count = t_count(ranges)
    if c_count == 0 or r_count >= c_count then
        ranges = new_ranges
    end
    if sb_menu_publish then sb_menu_publish() end
    end
    if not legacy then
        mp.command_native_async({name='subprocess',capture_stdout=true,capture_stderr=true,playback_only=false,args=args},receive)
    else receive(true,utils.subprocess({args=args})) end
end

function fast_forward()
    if options.fast_forward and options.fast_forward == true then
        speed_timer = nil
        mp.set_property("speed", sb_speed_before)
    end
    local last_speed = mp.get_property_number("speed")
    local new_speed = math.min(last_speed + options.fast_forward_increase, options.fast_forward_cap)
    if new_speed <= last_speed then return end
    mp.set_property("speed", new_speed)
end

function fade_audio(step)
    local last_volume = mp.get_property_number("volume")
    local new_volume = math.max(options.audio_fade_cap, math.min(last_volume + step, volume_before))
    if new_volume == last_volume then
        if step >= 0 then fade_dir = nil end
        if fade_timer ~= nil then fade_timer:kill() end
        fade_timer = nil
        return
    end
    mp.set_property("volume", new_volume)
end

function skip_ads(name, pos)
    if pos == nil or not sb_enabled or sb_mode=='chapters' then return end
    local sponsor_ahead = false
    for uuid, t in pairs(ranges) do
        if (options.fast_forward == uuid or not options.skip_once or not t.skipped) and t.start_time <= pos and t.end_time > pos then
            if options.fast_forward == uuid then return end
            if options.fast_forward == false then
                mp.osd_message("[sponsorblock] " .. t.category .. " skipped")
                mp.set_property("time-pos", t.end_time)
            else
                mp.osd_message("[sponsorblock] skipping " .. t.category)
            end
            t.skipped = true
            last_skip = {uuid = uuid, dir = nil}
            if options.report_views or options.auto_upvote then
                local args = {
                    options.python_path,
                    sponsorblock,
                    "stats",
                    database_file,
                    options.server_address,
                    youtube_id,
                    uuid,
                    options.report_views and "1" or "",
                    uid_path,
                    options.user_id,
                    options.auto_upvote and "1" or ""
                }
                if not legacy then
                    mp.command_native_async({name = "subprocess", playback_only = false, args = args}, function () end)
                else
                    utils.subprocess_detached({args = args})
                end
            end
            if options.fast_forward ~= false then
                sb_speed_before=mp.get_property_number("speed",1)
                options.fast_forward = uuid
                if speed_timer ~= nil then speed_timer:kill() end
                speed_timer = mp.add_periodic_timer(1, fast_forward)
            end
            return
        elseif (not options.skip_once or not t.skipped) and t.start_time <= pos + 1 and t.end_time > pos + 1 then
            sponsor_ahead = true
        end
    end
    if options.audio_fade then
        if sponsor_ahead then
            if fade_dir ~= false then
                if fade_dir == nil then volume_before = mp.get_property_number("volume") end
                if fade_timer ~= nil then fade_timer:kill() end
                fade_dir = false
                fade_timer = mp.add_periodic_timer(.1, function() fade_audio(-options.audio_fade_step) end)
            end
        elseif fade_dir == false then
            fade_dir = true
            if fade_timer ~= nil then fade_timer:kill() end
            fade_timer = mp.add_periodic_timer(.1, function() fade_audio(options.audio_fade_step) end)
        end
    end
    if options.fast_forward and options.fast_forward ~= true then
        options.fast_forward = true
        speed_timer:kill()
        speed_timer = nil
        mp.set_property("speed", sb_speed_before)
    end
end

function vote(dir)
    if last_skip.uuid == "" then return mp.osd_message("[sponsorblock] no sponsors skipped, can't submit vote") end
    local updown = dir == "1" and "up" or "down"
    if last_skip.dir == dir then return mp.osd_message("[sponsorblock] " .. updown .. "vote already submitted") end
    last_skip.dir = dir
    local args = {
        options.python_path,
        sponsorblock,
        "stats",
        database_file,
        options.server_address,
        youtube_id,
        last_skip.uuid,
        "",
        uid_path,
        options.user_id,
        dir
    }
    if not legacy then
        mp.command_native_async({name = "subprocess", playback_only = false, args = args}, function () end)
    else
        utils.subprocess({args = args})
    end
    mp.osd_message("[sponsorblock] " .. updown .. "vote submitted")
end

function update()
    mp.command_native_async({name = "subprocess", playback_only = false, args = {
        options.python_path,
        sponsorblock,
        "update",
        database_file,
        options.server_address
    }}, getranges)
end

function file_loaded()
    if sb_menu_stop_effects then sb_menu_stop_effects() end
    sb_payload=nil;sb_chapter_titles={};sb_generation=sb_generation+1;sb_fetch_state=""
    local initialized = init
    ranges = {}
    segment = {a = 0, b = 0, progress = 0, first = true}
    last_skip = {uuid = "", dir = nil}
    chapter_cache = {}
    local video_path = mp.get_property("path", "")
    mp.msg.debug("Path: " .. video_path)
    local video_referer = string.match(mp.get_property("http-header-fields", ""), "Referer:([^,]+)") or ""
    mp.msg.debug("Referer: " .. video_referer)

    local urls = {
        "ytdl://([%w-_]+).*",
        "https?://youtu%.be/([%w-_]+).*",
        "https?://w?w?w?%.?youtube%.com/v/([%w-_]+).*",
        "/watch.*[?&]v=([%w-_]+).*",
        "/embed/([%w-_]+).*"
    }
    youtube_id = nil
    for i, url in ipairs(urls) do 
        youtube_id = youtube_id or string.match(video_path, url) or string.match(video_referer, url)
        if youtube_id then break end
    end
    youtube_id = youtube_id or string.match(video_path, options.local_pattern)
    
    if not youtube_id or string.len(youtube_id) < 11 or (local_pattern and string.len(youtube_id) ~= 11) then youtube_id=nil;if sb_menu_publish then sb_menu_publish() end;return end
    youtube_id = string.sub(youtube_id, 1, 11)
    mp.msg.debug("Found YouTube ID: " .. youtube_id)
    if not sb_enabled then if sb_menu_publish then sb_menu_publish() end;return end
    init = true
    if not options.local_database then
        getranges(true, true)
    else
        local exists = file_exists(database_file)
        if exists and options.server_fallback then
            getranges(true, true)
            mp.add_timeout(0, function() getranges(true, true, "", true) end)
        elseif exists then
            getranges(true, true)
        elseif options.server_fallback then
            mp.add_timeout(0, function() getranges(true, true, "") end)
        end
    end
    if initialized then return end
    if options.skip then
        mp.observe_property("time-pos", "native", skip_ads)
    end
    if options.display_name ~= "" then
        local args = {
            options.python_path,
            sponsorblock,
            "username",
            database_file,
            options.server_address,
            youtube_id,
            "",
            "",
            uid_path,
            options.user_id,
            options.display_name
        }
        if not legacy then
            mp.command_native_async({name = "subprocess", playback_only = false, args = args}, function () end)
        else
            utils.subprocess_detached({args = args})
        end
    end
    if not options.local_database or (not options.auto_update and file_exists(database_file)) then return end

    if file_exists(database_file) then
        local db_info = utils.file_info(database_file)
        local cur_time = os.time(os.date("*t"))
        local upd_interval = parse_update_interval()
        if upd_interval == nil or os.difftime(cur_time, db_info.mtime) < upd_interval then return end
    end

    update()
end

function set_segment()
    if not youtube_id then return end
    local pos = mp.get_property_number("time-pos")
    if pos == nil then return end
    if segment.progress > 1 then
        segment.progress = segment.progress - 2
    end
    if segment.progress == 1 then
        segment.progress = 0
        segment.b = pos
        mp.osd_message("[sponsorblock] segment boundary B set, press again for boundary A", 3)
    else
        segment.progress = 1
        segment.a = pos
        mp.osd_message("[sponsorblock] segment boundary A set, press again for boundary B", 3)
    end
    if options.make_chapters and not segment.first then
        local start_time = math.min(segment.a, segment.b)
        local end_time = math.max(segment.a, segment.b)
        if end_time - start_time ~= 0 and end_time ~= 0 then
            clean_chapters()
            create_chapter("Preview segment start", start_time)
            create_chapter("Preview segment end", end_time)
        end
    end
    segment.first = false
end

function select_category(selected)
    for category in string.gmatch(options.categories, "([^,]+)") do
        mp.remove_key_binding("select_category_"..category)
        mp.remove_key_binding("kp_select_category_"..category)
    end
    submit_segment(selected)
end

function submit_segment(category)
    if not youtube_id then return end
    local start_time = math.min(segment.a, segment.b)
    local end_time = math.max(segment.a, segment.b)
    if end_time - start_time == 0 or end_time == 0 then
        mp.osd_message("[sponsorblock] empty segment, not submitting")
    elseif segment.progress <= 1 then
        segment.progress = segment.progress + 2
        local category_list = ""
        for category_id, category in pairs(all_categories) do
            local category_title = (category:gsub("^%l", string.upper):gsub("_", " "))
            category_list = category_list .. category_id .. ": " .. category_title .. "\n"
            mp.add_forced_key_binding(tostring(category_id), "select_category_"..category, function() select_category(category) end)
            mp.add_forced_key_binding("KP"..tostring(category_id), "kp_select_category_"..category, function() select_category(category) end)
        end
        mp.osd_message(string.format("[sponsorblock] press a number to select category for segment: %.2d:%.2d:%.2d to %.2d:%.2d:%.2d\n\n" .. category_list .. "\nyou can press Shift+G again for default (Sponsor) or hide this message with g", math.floor(start_time/(60*60)), math.floor(start_time/60%60), math.floor(start_time%60), math.floor(end_time/(60*60)), math.floor(end_time/60%60), math.floor(end_time%60)), 30)
    else
        mp.osd_message("[sponsorblock] submitting segment...", 30)
        local submit
        local args = {
            options.python_path,
            sponsorblock,
            "submit",
            database_file,
            options.server_address,
            youtube_id,
            tostring(start_time),
            tostring(end_time),
            uid_path,
            options.user_id,
            category or "sponsor"
        }
        if not legacy then
            submit = mp.command_native({name = "subprocess", capture_stdout = true, playback_only = false, args = args})
        else
            submit = utils.subprocess({args = args})
        end
        if string.match(submit.stdout, "success") then
            segment = {a = 0, b = 0, progress = 0, first = true}
            mp.osd_message("[sponsorblock] segment submitted")
            if options.make_chapters then
                clean_chapters()
                create_chapter("Submitted segment start", start_time)
                create_chapter("Submitted segment end", end_time)
            end
        elseif string.match(submit.stdout, "error") then
            mp.osd_message("[sponsorblock] segment submission failed, server may be down. try again", 5)
        elseif string.match(submit.stdout, "502") then
            mp.osd_message("[sponsorblock] segment submission failed, server is down. try again", 5)
        elseif string.match(submit.stdout, "400") then
            mp.osd_message("[sponsorblock] segment submission failed, impossible inputs", 5)
            segment = {a = 0, b = 0, progress = 0, first = true}
        elseif string.match(submit.stdout, "429") then
            mp.osd_message("[sponsorblock] segment submission failed, rate limited. try again", 5)
        elseif string.match(submit.stdout, "409") then
            mp.osd_message("[sponsorblock] segment already submitted", 3)
            segment = {a = 0, b = 0, progress = 0, first = true}
        else
            mp.osd_message("[sponsorblock] segment submission failed", 5)
        end
    end
end

mp.register_event("file-loaded", file_loaded)
mp.add_key_binding("g", "set_segment", set_segment)
mp.add_key_binding("G", "submit_segment", submit_segment)
mp.add_key_binding("h", "upvote_segment", function() return vote("1") end)
mp.add_key_binding("H", "downvote_segment", function() return vote("0") end)
-- Bindings below are for backwards compatibility and could be removed at any time
mp.add_key_binding(nil, "sponsorblock_set_segment", set_segment)
mp.add_key_binding(nil, "sponsorblock_submit_segment", submit_segment)
mp.add_key_binding(nil, "sponsorblock_upvote", function() return vote("1") end)
mp.add_key_binding(nil, "sponsorblock_downvote", function() return vote("0") end)

-- Local player settings. Opening/exporting this menu never contacts the server.
local function sb_settings()
    return {enabled=sb_enabled,mode=sb_mode,skip_categories=options.skip_categories,
        skip_once=options.skip_once,make_chapters=options.make_chapters,min_duration=options.min_duration}
end
local function sb_publish()
    local list={}
    for uuid,r in pairs(ranges) do list[#list+1]={uuid=uuid,start_time=r.start_time,end_time=r.end_time,category=r.category,skipped=r.skipped} end
    table.sort(list,function(a,b)return a.start_time<b.start_time end)
    mp.set_property_native('user-data/sponsorblock',{settings=sb_settings(),video_id=youtube_id or '',segments=list,fetch_state=sb_fetch_state})
end
local function sb_stop_effects()
    if speed_timer then speed_timer:kill();speed_timer=nil;mp.set_property_number('speed',sb_speed_before) end
    if fade_timer then fade_timer:kill();fade_timer=nil end
    if fade_dir~=nil then mp.set_property_number('volume',volume_before);fade_dir=nil end
    options.fast_forward=sb_mode=='fast'
end
local function sb_clear_chapters()
    local list={}
    for _,chapter in ipairs(mp.get_property_native('chapter-list',{})) do
        if not sb_chapter_titles[chapter.title or ''] then list[#list+1]=chapter end
    end
    mp.set_property_native('chapter-list',list)
    sb_chapter_titles={};chapter_cache={}
end
local function sb_rebuild()
    sb_clear_chapters()
    local previous=ranges
    ranges={}
    if sb_payload and sb_enabled then
        local result={}
        for token in sb_payload:gmatch('[^:%s]+') do
            local uuid=token:match('([^,]+),[^,]+$')
            if uuid then process(uuid,token,result) end
        end
        for uuid,r in pairs(result) do if previous[uuid] then r.skipped=previous[uuid].skipped end end
        ranges=result
    end
    sb_publish()
end
local function sb_save()
    local f,err=io.open(sb_state_path,'w')
    if f then f:write(utils.format_json(sb_settings()));f:close()
    else mp.msg.error(tostring(err));mp.osd_message('Не удалось сохранить настройки SponsorBlock',3) end
end
local sb_menu
local function sb_command(key,value)return {'script-message-to','sponsorblock','settings-set',key,tostring(value or '')}end
local function sb_row(title,key,value,active)
    return {title=title,value=sb_command(key,value),active=active,keep_open=true}
end
sb_menu=function()
    local cats={}
    for _,id in ipairs(all_categories) do cats[#cats+1]=sb_row(sb_labels[id],'category',id,categories[id] or false) end
    local durations={}
    for _,n in ipairs({0,0.5,1,2,3,5,10}) do durations[#durations+1]=sb_row(n==0 and 'Любая длительность' or string.format('%g с',n),'min_duration',n,options.min_duration==n) end
    local modes={sb_row('Автоматически пропускать','mode','skip',sb_mode=='skip'),
        sb_row('Ускорять до 2×','mode','fast',sb_mode=='fast'),
        sb_row('Только отмечать главы','mode','chapters',sb_mode=='chapters')}
    local count=0;for _ in pairs(ranges)do count=count+1 end
    local status=not sb_enabled and 'Выключен' or (youtube_id and (sb_fetch_state=='loading' and 'Получение сегментов…' or sb_fetch_state=='error' and 'Сегменты временно недоступны' or ('YouTube · сегментов для пропуска: '..count)) or 'Работает с видео YouTube')
    neon_context.open(utils.format_json({type='sponsorblock-settings',title='SponsorBlock',items={
        {title=status,selectable=false,muted=true},
        sb_row('Включить SponsorBlock','enabled','toggle',sb_enabled),
        {title='Действие с сегментами',hint=sb_mode=='fast' and 'Ускорение' or sb_mode=='chapters' and 'Метки' or 'Пропуск',items=modes},
        {title='Пропускать категории',items=cats},
        sb_row('Пропускать каждый сегмент только один раз','skip_once','toggle',options.skip_once),
        sb_row('Показывать границы сегментов в главах','make_chapters','toggle',options.make_chapters),
        {title='Минимальная длительность пропуска',hint=string.format('%g с',options.min_duration),items=durations},
        {title='Сбросить настройки SponsorBlock',value=sb_command('reset'),keep_open=true}},
        footnote='Категории задают автоматический пропуск · настройки сохраняются'}))
end
mp.register_script_message('settings-set',function(key,value)
    local was_enabled=sb_enabled
    sb_stop_effects()
    if key=='enabled' then sb_enabled=not sb_enabled
    elseif key=='mode' and (value=='skip' or value=='fast' or value=='chapters') then
        sb_mode=value
        if value=='chapters' then options.make_chapters=true end
    elseif key=='category' and sb_labels[value] then
        categories[value]=not categories[value]
        local selected={};for _,id in ipairs(all_categories)do if categories[id] then selected[#selected+1]=id end end
        options.skip_categories=table.concat(selected,',')
    elseif key=='skip_once' or key=='make_chapters' then options[key]=not options[key]
    elseif key=='min_duration' then
        local n=tonumber(value);if not n or n~=n or n<0 or n>60 then return end
        options.min_duration=n
    elseif key=='reset' then
        sb_enabled=sb_defaults.enabled;sb_mode=sb_defaults.mode
        options.skip_once=sb_defaults.skip_once;options.make_chapters=sb_defaults.make_chapters
        options.min_duration=sb_defaults.min_duration;options.skip_categories=sb_defaults.skip_categories
        categories={};for id in options.skip_categories:gmatch('[^,]+')do if sb_labels[id] then categories[id]=true end end
    else return end
    options.skip=true;options.fast_forward=sb_mode=='fast'
    sb_save();sb_rebuild()
    if sb_enabled and not was_enabled and youtube_id and not sb_payload then file_loaded() end
    sb_menu()
end)
mp.add_key_binding(nil,'menu',sb_menu)
neon_context.register({menu=sb_menu})
mp.add_timeout(0.1,sb_publish)
-- Accessible to the existing file-loaded/getranges callbacks, without new key conflicts.
sb_menu_publish=sb_publish
sb_menu_stop_effects=sb_stop_effects
