-- Share the same menu definitions between hotkeys and the contextual menu.
local mp=require 'mp'
local utils=require 'mp.utils'
local M={}
local generation
local function send(json,update)
    if generation or mp.get_property_native('user-data/uosc/menu/type')=='neon-context' then
        mp.commandv('script-message-to','context_menu','deliver',json,generation or '')
        generation=nil
    else mp.commandv('script-message-to','uosc',update and 'update-menu' or 'open-menu',json) end
end
function M.open(json)send(json,false)end
function M.update(json)send(json,true)end
function M.register(providers)
    mp.register_script_message('context-export',function(key,token)
        local fn=providers[key];if not fn then return end
        generation=token
        local ok,err=pcall(fn)
        generation=nil
        if not ok then mp.msg.error('Context menu: '..tostring(err)) end
    end)
end
return M
