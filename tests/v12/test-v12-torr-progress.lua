local mp=require 'mp'
local fail=0
local function check(ok,label)mp.msg.info((ok and 'PASS 'or'FAIL ')..label);if not ok then fail=fail+1 end end
mp.add_timeout(2,function()mp.commandv('script-message-to','torrserver','play','0123456789abcdef0123456789abcdef01234567','1')end)
mp.add_timeout(5,function()
    local progress=mp.get_property_native('user-data/torrserver/progress',{})
    check(type(progress.percent)=='number' and progress.percent>10 and progress.percent<90,'server startup-buffer percent during blocked stream open')
    check(progress.download_speed==4*1048576 and progress.peers==7,'real speed and peer counters')
    mp.msg.info('BUFFER_PERCENT='..tostring(progress.percent))
    mp.commandv('screenshot-to-file','outputs/player-previews/v12-torrserver-buffer.png','window')
end)
mp.add_timeout(9,function()
    check(mp.get_property_native('user-data/torrserver/progress',{}).phase==nil,'overlay clears after file-loaded')
    check(mp.get_property_number('duration',0)>0,'video actually opened')
    mp.msg.info('TORR_FAILURES='..fail);mp.commandv('quit',fail==0 and 0 or 1)
end)
