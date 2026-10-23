local mp=require 'mp'
local utils=require 'mp.utils'
local opt={phase='save'};require('mp.options').read_options(opt,'test-playlists')
local failures=0
local function check(ok,name)mp.msg.info((ok and 'PASS 'or 'FAIL ')..name);if not ok then failures=failures+1 end end
local function at(t,f)mp.add_timeout(t,f)end
local function send(action,...)mp.commandv('script-message-to','playlist_library',action,...)end
local function info()return mp.get_property_native('user-data/playlist-library/state',{})end
local wd=mp.get_property('working-directory')
local first=utils.join_path(wd,'work/sample.mp4')
local second=utils.join_path(wd,'work/cinema-wide.mp4')
if opt.phase=='save' then
    at(2,function()mp.commandv('loadfile',first,'replace');mp.set_property_bool('pause',true);mp.commandv('loadfile',second,'append')end)
    at(3,function()check(mp.get_property_number('playlist-count')==2,'two entries in default list');send('save')end)
    at(3.4,function()send('new','Аниме и сериалы')end)
    at(4.2,function()
        check(#info().lists==2,'second named playlist created');check(mp.get_property_number('playlist-count')==0,'new playlist is empty')
        mp.commandv('loadfile',second,'replace');mp.set_property_bool('pause',true)
    end)
    at(5.2,function()send('save');check(mp.get_property_number('playlist-count')==1,'second list independent');send('select','default')end)
    at(6.1,function()
        check(mp.get_property_number('playlist-count')==2,'switch back restores first list')
        check(info().active=='default','correct active playlist')
        mp.set_property_number('playlist-pos',1);mp.set_property_bool('pause',true)
    end)
    at(6.7,function()mp.commandv('seek','0.5','absolute','exact')end)
    at(7.3,function()send('save')end)
else
    at(2.5,function()
        check(#info().lists==2,'named library restored after restart')
        check(mp.get_property_number('playlist-count')==2,'queue restored after restart')
        check(mp.get_property_number('playlist-pos')==1,'selected file restored')
        check(mp.get_property_bool('pause'),'restart does not autoplay')
        check(mp.get_property_number('time-pos',0)>=0.4,'position restored')
    end)
end
at(opt.phase=='save' and 7.8 or 3.2,function()mp.msg.info('PLAYLIST_FAILURES='..failures);mp.commandv('quit',failures==0 and 0 or 1)end)
