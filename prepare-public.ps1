param(
    [Parameter(Mandatory)][string]$InputPlayerRoot,
    [Parameter(Mandatory)][string]$OutputPlayerRoot
)
$ErrorActionPreference = 'Stop'
$inputRoot = (Resolve-Path -LiteralPath $InputPlayerRoot).Path.TrimEnd('\')
$outputRoot = [IO.Path]::GetFullPath($OutputPlayerRoot).TrimEnd('\')
if (Test-Path -LiteralPath $outputRoot) { throw 'Output already exists. Choose a new empty destination; nothing will be deleted.' }
if ($outputRoot.StartsWith($inputRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $outputRoot -eq $inputRoot) { throw 'Output cannot be inside the input directory.' }
if (!(Test-Path -LiteralPath (Join-Path $inputRoot 'mpv.exe'))) { throw 'Input must be a complete player directory with mpv.exe.' }
if (Get-ChildItem -LiteralPath $inputRoot -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Linked input paths require manual review.' }
$skipNames = @('Lossless.dll','Player.pdb','memo-history.log','bookmarks.json','picture-presets.json','picture-presets.json.bak','ambient-settings.json','picture-settings.json','motion-settings.json','ui-theme.json','SHA256.csv','sponsorblock-settings.json','installation-mode.txt','portable-defaults.sha256','mpv-register.bat','mpv-unregister.bat','updater.bat')
$skipDocs = @('README.md','docs/TESTED.md','docs/LOCAL-CHANGES.md','docs/ICON-PROMPT.md')
New-Item -ItemType Directory -Path $outputRoot | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $inputRoot -Recurse -File) {
    if ($file.LinkType) { throw 'Linked files require manual review before public packaging.' }
    $relative = $file.FullName.Substring($inputRoot.Length + 1).Replace('\','/')
    if ($file.Name -in $skipNames -or $relative -in $skipDocs -or $relative -match '(^|/)(__pycache__|cache|watch_later|screenshots|torrserver-data|installer|config-backups|new-defaults)(/|$)' -or $relative -match '\.(log|bak|tmp)$') { continue }
    $target = [IO.Path]::GetFullPath((Join-Path $outputRoot $relative))
    if (!$target.StartsWith($outputRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe output path.' }
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public/README.md') -Destination (Join-Path $outputRoot 'README.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD-PARTY.md') -Destination (Join-Path $outputRoot 'THIRD-PARTY.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public/INSTALLER.md') -Destination (Join-Path $outputRoot 'docs/INSTALLER.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public/CHANGES.txt') -Destination (Join-Path $outputRoot 'ИЗМЕНЕНИЯ.txt')
$sourceFile = Join-Path $outputRoot 'docs/SOURCES.json'
$manifest = Get-Content -Raw -LiteralPath $sourceFile | ConvertFrom-Json
$manifest.version = '11.4'
$manifest.built = '2026-10-22'
$manifest.purpose = 'Public mpv Neon v11.4; excludes Lossless.dll and personal runtime data'
$manifest.components = @($manifest.components | Where-Object { $_.component -ne 'Lossless Scaling private native core' })
$ui = $manifest.components | Where-Object { $_.component -eq 'Glass/Deck themes and horizontal volume' }
$ui.version = '11.4'
$ui.local_uosc_changes = @('main.lua','elements/Button.lua','elements/Controls.lua','elements/ManagedButton.lua','elements/Menu.lua','elements/HorizontalVolume.lua','elements/Timeline.lua','elements/YoutubeTime.lua','intl/ru.json','lib/menus.lua','lib/utils.lua','assets/player-neon-07.bgra')
$manifest | Add-Member -NotePropertyName local_changes -NotePropertyValue @('SponsorBlock settings/menu and skip modes: portable_config/scripts/sponsorblock.lua','External audio: portable_config/scripts/external-audio.lua','Russian layout: portable_config/scripts/russian-layout.lua','Profile-aware launcher and installer: installer-source/ in source repository') -Force
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sourceFile -Encoding utf8
$serverOptions = Join-Path $outputRoot 'portable_config/script-opts/torrserver.conf'
# Public defaults only: never carry credentials or a home-server address from the input.
@('server=http://127.0.0.1:8090','timeout=20','auto_start=yes','fallback_port=8099','username=','password=') | Set-Content -LiteralPath $serverOptions -Encoding utf8
foreach ($notice in @('LICENSE.txt','LICENSE-SCOPE.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $notice) -Destination (Join-Path $outputRoot $notice) }
# Restore public license notices from the published source tree.
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'mpv-portable/docs/licenses') -Destination (Join-Path $outputRoot 'docs') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'mpv-portable/native/BUILD.md') -Destination (Join-Path $outputRoot 'native/BUILD.md') -Force
foreach ($tree in @('defaults')) {
    $options = Join-Path $outputRoot ($tree + '/script-opts/torrserver.conf')
    Copy-Item -LiteralPath $serverOptions -Destination $options -Force
}
# Hashes must describe the sanitized defaults rather than the private input.
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public/INSTALLER.md') -Destination (Join-Path $outputRoot 'УСТАНОВКА.txt') -Force
$defaultRoot = Join-Path $outputRoot 'defaults'
$defaultHashes = @(Get-ChildItem -LiteralPath $defaultRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash + "`t" + $_.FullName.Substring($defaultRoot.Length + 1)
})
$defaultHashes | Set-Content -LiteralPath (Join-Path $outputRoot 'defaults.sha256') -Encoding utf8
Set-Content -LiteralPath (Join-Path $outputRoot 'build-id.txt') -Value 'mpv-neon-v11.4-public' -Encoding ascii
if (Get-ChildItem -LiteralPath $outputRoot -Recurse -File -Filter Lossless.dll) { throw 'Private DLL found in public output.' }
Write-Output "Prepared public portable directory: $outputRoot"
