local mp=require 'mp'
local utils=require 'mp.utils'
local opt={phase='explicit'};require('mp.options').read_options(opt,'library-safety')
local failures=0
local function check(ok,name)mp.msg.info((ok and 'PASS 'or'FAIL ')..name);if not ok then failures=failures+1 end end
mp.add_timeout(2.4,function()
    local state=mp.get_property_native('user-data/playlist-library/state',{})
    if opt.phase=='explicit' then
        check(#state.lists==3,'explicitly opened file gets separate playlist')
        local preserved=false
        for _,list in ipairs(state.lists)do if list.id=='default' and list.count==2 then preserved=true end end
        check(preserved,'previous named queue not overwritten')
    else check(state.writable==false,'malformed library left read-only') end
    mp.msg.info('LIBRARY_SAFETY_FAILURES='..failures);mp.commandv('quit',failures==0 and 0 or 1)
end)
