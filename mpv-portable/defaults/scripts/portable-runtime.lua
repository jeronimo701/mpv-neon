local mp = require 'mp'
local options = mp.get_property_native('ytdl-raw-options', {})
options['js-runtimes'] = 'deno:' .. mp.command_native({'expand-path', '~~/../runtime/deno.exe'})
mp.set_property_native('ytdl-raw-options', options)
