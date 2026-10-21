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
$skipNames = @('Lossless.dll','Player.pdb','memo-history.log','bookmarks.json','picture-presets.json','picture-presets.json.bak','ambient-settings.json','picture-settings.json','motion-settings.json','ui-theme.json','SHA256.csv')
$skipDocs = @('README.md','docs/TESTED.md','docs/LOCAL-CHANGES.md','docs/ICON-PROMPT.md')
New-Item -ItemType Directory -Path $outputRoot | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $inputRoot -Recurse -File) {
    if ($file.LinkType) { throw 'Linked files require manual review before public packaging.' }
    $relative = $file.FullName.Substring($inputRoot.Length + 1).Replace('\','/')
    if ($file.Name -in $skipNames -or $relative -in $skipDocs -or $relative -match '(^|/)(__pycache__|cache|watch_later|screenshots|torrserver-data|installer)(/|$)' -or $relative -match '\.(log|bak|tmp)$') { continue }
    $target = [IO.Path]::GetFullPath((Join-Path $outputRoot $relative))
    if (!$target.StartsWith($outputRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe output path.' }
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public/README.md') -Destination (Join-Path $outputRoot 'README.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD-PARTY.md') -Destination (Join-Path $outputRoot 'THIRD-PARTY.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public/INSTALLER.md') -Destination (Join-Path $outputRoot 'docs/INSTALLER.md')
$sourceFile = Join-Path $outputRoot 'docs/SOURCES.json'
$manifest = Get-Content -Raw -LiteralPath $sourceFile | ConvertFrom-Json
$manifest.purpose = 'Public mpv Neon v6; excludes Lossless.dll and personal runtime data'
$manifest.components = @($manifest.components | Where-Object { $_.component -ne 'Lossless Scaling private native core' })
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sourceFile -Encoding utf8
$serverOptions = Join-Path $outputRoot 'portable_config/script-opts/torrserver.conf'
# Public defaults only: never carry credentials or a home-server address from the input.
@('server=http://127.0.0.1:8090','timeout=20','auto_start=yes','fallback_port=8099','username=','password=') | Set-Content -LiteralPath $serverOptions -Encoding utf8
if (Get-ChildItem -LiteralPath $outputRoot -Recurse -File -Filter Lossless.dll) { throw 'Private DLL found in public output.' }
Write-Output "Prepared public portable directory: $outputRoot"
