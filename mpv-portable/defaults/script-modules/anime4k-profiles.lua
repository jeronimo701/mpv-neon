-- Exact pipelines from Anime4K v4 official low-end / high-end Windows templates.
-- https://github.com/bloc97/Anime4K/tree/master/md/Template
local M={}
local function make(tier,mode)
    local main=tier=='fast' and 'M' or 'VL'
    local small=tier=='fast' and 'S' or 'M'
    local restore=(mode=='b' or mode=='bb') and 'Restore_CNN_Soft_' or 'Restore_CNN_'
    local denoise=mode=='c' or mode=='ca'
    local chain={'Clamp_Highlights'}
    if not denoise then chain[#chain+1]=restore..main end
    chain[#chain+1]=(denoise and 'Upscale_Denoise_CNN_x2_' or 'Upscale_CNN_x2_')..main
    if mode=='aa' then chain[#chain+1]='Restore_CNN_'..small end
    chain[#chain+1]='AutoDownscalePre_x2';chain[#chain+1]='AutoDownscalePre_x4'
    if mode=='bb' then chain[#chain+1]='Restore_CNN_Soft_'..small end
    if mode=='ca' then chain[#chain+1]='Restore_CNN_'..small end
    chain[#chain+1]='Upscale_CNN_x2_'..small
    for i,v in ipairs(chain)do chain[i]='~~/shaders/Anime4K/Anime4K_'..v..'.glsl' end
    return chain
end
for _,tier in ipairs({'fast','hq'})do
    for _,mode in ipairs({'a','b','c','aa','bb','ca'})do
        local label=({a='A',b='B',c='C',aa='A+A',bb='B+B',ca='C+A'})[mode]
        M['anime-'..tier..'-'..mode]={title='Anime4K '..label..' · '..(tier=='fast' and 'Fast' or 'HQ'),paths=make(tier,mode)}
    end
end
return M
