param([Parameter(Mandatory)][string]$PlayerRoot,[string]$InstallerManifest = '')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PlayerRoot).Path
$blockedNames = @('Lossless.dll','memo-history.log','bookmarks.json','picture-presets.json','picture-presets.json.bak','ambient-settings.json','picture-settings.json','motion-settings.json','ui-theme.json','audio-settings.json','playlists.json','playlists.json.bak','playlist-window.json','Player.pdb','sponsorblock-settings.json','installation-mode.txt','portable-defaults.sha256')
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File)
$blocked = @($files | Where-Object { $_.Name -in $blockedNames -or $_.FullName -match '\\(cache|watch_later|screenshots|torrserver-data|config-backups|new-defaults)\\' -or $_.Extension -in @('.log','.bak','.tmp') })
if ($blocked.Count) { throw "Private/runtime files found: $($blocked.Count). Do not publish this payload." }
foreach ($name in @('mpv.exe','mpv-neon.exe','README.md','THIRD-PARTY.md','LICENSE.txt','LICENSE-SCOPE.md','defaults.sha256','build-id.txt','portable_config/mpv.conf','portable_config/scripts/uosc/main.lua','portable_config/scripts/lsfg-native.dll','native/lsfg-native.c','docs/SOURCES.json','docs/licenses/mpv-GPL.txt','docs/licenses/uosc-LGPL.txt')) {
    if (!(Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) { throw "Required file missing: $name" }
}
$manifest = Get-Content -Raw -LiteralPath (Join-Path $root 'docs/SOURCES.json') | ConvertFrom-Json
if (@($manifest.components | Where-Object { $_.redistributable -eq $false }).Count) { throw 'A non-redistributable component remains in the public source manifest.' }
foreach ($line in Get-Content -LiteralPath (Join-Path $root 'defaults.sha256')) {
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2 -or $parts[1] -match '(^[\\/]|:|(^|[\\/])\.\.([\\/]|$))') { throw 'Invalid defaults manifest path.' }
    $file = Join-Path $root ('defaults/' + $parts[1])
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $parts[0]) { throw 'Defaults manifest hash mismatch.' }
}
$server = Get-Content -LiteralPath (Join-Path $root 'portable_config/script-opts/torrserver.conf')
if (!($server -contains 'server=http://127.0.0.1:8090') -or @($server | Where-Object { $_ -match '^(username|password)\s*=\s*\S+' }).Count) { throw 'Public server defaults are not anonymous loopback.' }
if ($InstallerManifest) {
    $list = Get-Content -Raw -LiteralPath $InstallerManifest
    if ($list -match '(?i)Lossless\.dll|memo-history\.log|watch_later|torrserver-data|bookmarks\.json|ui-theme\.json') { throw 'Installer includes a forbidden private file.' }
}
Write-Output "PASS: public payload validated ($($files.Count) files); private DLL and user data absent; licenses and sources present."
