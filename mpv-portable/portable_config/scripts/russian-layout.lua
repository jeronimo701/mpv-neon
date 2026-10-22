-- Physical QWERTY shortcuts also work with the Russian ЙЦУКЕН layout.
-- Forward the key instead of copying its command: custom input.conf bindings
-- and the currently active input section remain authoritative.
local mp = require 'mp'
local pairs_by_key = {
    {'й','q','Й','Q'}, {'ц','w','Ц','W'}, {'у','e','У','E'},
    {'к','r','К','R'}, {'е','t','Е','T'}, {'н','y','Н','Y'},
    {'г','u','Г','U'}, {'ш','i','Ш','I'}, {'щ','o','Щ','O'},
    {'з','p','З','P'}, {'х','[','Х','{'}, {'ъ',']','Ъ','}'},
    {'ф','a','Ф','A'}, {'ы','s','Ы','S'}, {'в','d','В','D'},
    {'а','f','А','F'}, {'п','g','П','G'}, {'р','h','Р','H'},
    {'о','j','О','J'}, {'л','k','Л','K'}, {'д','l','Д','L'},
    {'ж',';','Ж',':'}, {'э',"'",'Э','"'},
    {'я','z','Я','Z'}, {'ч','x','Ч','X'}, {'с','c','С','C'},
    {'м','v','М','V'}, {'и','b','И','B'}, {'т','n','Т','N'},
    {'ь','m','Ь','M'}, {'б',',','Б','<'}, {'ю','.','Ю','>'},
    {'ё','`','Ё','~'},
}
local prefixes = {'', 'Ctrl+', 'Alt+', 'Ctrl+Alt+', 'Meta+'}
local serial = 0
for _, keys in ipairs(pairs_by_key) do
    for _, prefix in ipairs(prefixes) do
        for index = 1, 3, 2 do
            local target = prefix .. keys[index + 1]
            serial = serial + 1
            -- Ordinary bindings allow forced text-entry/search sections to win,
            -- and never override explicit Russian bindings from input.conf.
            mp.add_key_binding(prefix .. keys[index], 'ru-layout-' .. serial,
                function() mp.commandv('keypress', target) end, {repeatable=true})
        end
    end
end
