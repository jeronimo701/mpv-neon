local mp=require 'mp'
local utils=require 'mp.utils'
local profiles=dofile(mp.command_native({'expand-path','~~/script-modules/anime4k-profiles.lua'}))
local ids={};for _,tier in ipairs({'fast','hq'})do for _,mode in ipairs({'a','b','c','aa','bb','ca'})do ids[#ids+1]='anime-'..tier..'-'..mode end end
local i,fail=0,0
local function next_profile()
    i=i+1
    if i>#ids then mp.msg.info('ANIME_FAILURES='..fail);mp.commandv('quit',fail==0 and 0 or 1);return end
    local id=ids[i]
    mp.commandv('script-message-to','quality','select',id)
    mp.add_timeout(1.4,function()
        local shaders=mp.get_property_native('glsl-shaders',{})
        local ok=mp.get_property_native('user-data/quality/profile')==id and #shaders==#profiles[id].paths
        for n,p in ipairs(shaders)do if p~=mp.command_native({'expand-path',profiles[id].paths[n] or ''}) or not utils.file_info(p) then ok=false end end
        mp.msg.info((ok and 'PASS 'or'FAIL ')..id..' pipeline '..#shaders..' shaders')
        if not ok then fail=fail+1 end
        next_profile()
    end)
end
mp.add_timeout(2,next_profile)
