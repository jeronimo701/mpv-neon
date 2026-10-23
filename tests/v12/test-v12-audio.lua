local mp=require 'mp'
local fail=0
local function at(t,fn)mp.add_timeout(t+2,fn)end
local function check(ok,name)mp.msg.info((ok and 'PASS ' or 'FAIL ')..name);if not ok then fail=fail+1 end end
local function set(k,v)mp.commandv('script-message-to','audio_settings','set',k,tostring(v))end
local function filters()
    local all=mp.get_property_native('af',{});local s='';for _,v in ipairs(all)do if v.label=='neon_audio' then s=require('mp.utils').format_json(v) end end;return s
end
at(0.7,function()set('normalization','dynamic')end)
at(1.1,function()check(filters():find('dynaudnorm',1,true)~=nil,'dynamic normalization filter initialized');set('boost',200)end)
at(1.5,function()check(filters():find('volume=2.0000',1,true)~=nil,'200 percent linear boost');check(filters():find('alimiter',1,true)~=nil,'peak limiter');set('night',true)end)
at(1.9,function()check(filters():find('acompressor',1,true)~=nil,'night compressor separate');set('normalization','lufs')end)
at(2.3,function()check(filters():find('loudnorm',1,true)~=nil,'LUFS normalizer initialized');set('renderer','wasapi')end)
at(2.9,function()
    check(mp.get_property_native('user-data/audio-settings/state').renderer=='wasapi','WASAPI setting applied')
    mp.msg.info('ACTUAL_AO='..mp.get_property('current-ao','none'))
    set('normalization','off');set('night',false);set('boost',100)
end)
at(3.4,function()
    check(filters()=='','bypass removes only our processing')
    local found=false;for _,f in ipairs(mp.get_property_native('af',{}))do if f.label=='external' then found=true end end
    check(found,'unrelated external audio filter preserved')
    check(mp.get_property_native('user-data/audio-settings/state').boost==100,'boost reset')
    mp.msg.info('AUDIO_FAILURES='..fail);mp.commandv('quit',fail==0 and 0 or 1)
end)
