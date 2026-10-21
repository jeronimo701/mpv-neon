param(
    [string]$Compiler = '',
    [string]$PlayerRoot = (Join-Path $PSScriptRoot '..\mpv-portable'),
    [string]$BuildRoot = (Join-Path $PSScriptRoot '..\..\work\installer-build'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..'),
    [switch]$TestBuild
)
$ErrorActionPreference = 'Stop'
if (-not $Compiler) { $Compiler = Join-Path $PSScriptRoot '..\..\work\toolchain\inno7\ISCC.exe' }
$PlayerRoot = (Resolve-Path -LiteralPath $PlayerRoot).Path
if (Get-ChildItem -LiteralPath $PlayerRoot -Recurse -File -Filter 'Lossless.dll') { throw 'Public build refused: Lossless.dll must not be present. Use prepare-public.ps1 first.' }
New-Item -ItemType Directory -Force -Path $BuildRoot, $OutputRoot | Out-Null
$BuildRoot = (Resolve-Path -LiteralPath $BuildRoot).Path
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$files = Get-ChildItem -LiteralPath $PlayerRoot -Recurse -File | Where-Object {
    $_.Name -notin @('Lossless.dll','SHA256.csv','memo-history.log','bookmarks.json','picture-presets.json','picture-presets.json.bak','ambient-settings.json','picture-settings.json','motion-settings.json','ui-theme.json','Player.pdb','mpv-register.bat','mpv-unregister.bat','updater.bat') -and
    $_.FullName -notmatch '\\portable_config\\(cache|watch_later|torrserver-data)\\' -and
    $_.FullName -notmatch '\\installer\\'
} | Sort-Object FullName
$registeredExe=if($TestBuild){'mpv-neon-installer-test.exe'}else{'mpv-neon.exe'}
$hashes=@(foreach($file in $files) {
    [pscustomobject]@{Path=$file.FullName.Substring($PlayerRoot.Length+1).Replace('\','/');Bytes=$file.Length;SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$launcher=Get-Item -LiteralPath (Join-Path $PlayerRoot 'Player.exe')
$hashes += [pscustomobject]@{Path=$registeredExe;Bytes=$launcher.Length;SHA256=(Get-FileHash -LiteralPath $launcher.FullName).Hash.ToLowerInvariant()}
$manifestFile=Join-Path $BuildRoot 'SHA256.csv'
$hashes | Export-Csv -LiteralPath $manifestFile -NoTypeInformation -Encoding utf8
$lines = foreach ($file in $files) {
    $relative = $file.FullName.Substring($PlayerRoot.Length + 1)
    $parent = Split-Path $relative -Parent
    $flags = 'ignoreversion'
    if ($relative -match '^portable_config\\(mpv\.conf|input\.conf|script-opts\\.*)$') {
        $flags = 'onlyifdoesntexist uninsneveruninstall'
    }
    'Source: "{0}"; DestDir: "{{app}}\{1}"; Flags: {2}' -f $file.FullName, $parent, $flags
}
$lines += 'Source: "{0}"; DestDir: "{{app}}\docs"; DestName: "SHA256.csv"; Flags: ignoreversion' -f $manifestFile
$fileList = Join-Path $BuildRoot 'files.iss'
$lines | Set-Content -LiteralPath $fileList -Encoding utf8
$argsList = @('/Qp', ('/DSourceRoot='+$PlayerRoot), ('/DFileList='+$fileList), ('/DOutputRoot='+$OutputRoot))
if ($TestBuild) {
    $argsList += '/DAppKey=mpvNeonInstallerTest','/DProductName=mpv Neon Installer Test','/DRegisteredExe=mpv-neon-installer-test.exe','/DOutputName=mpv-Neon-Test-Setup'
}
& $Compiler @argsList (Join-Path $PSScriptRoot 'mpv-neon.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }
Write-Host "Packaged $($files.Count) source files plus the uniquely named launcher."
