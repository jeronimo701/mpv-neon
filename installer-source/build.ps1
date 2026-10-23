param(
    [string]$Compiler = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    [Parameter(Mandatory)][Alias('Payload')][string]$PlayerRoot,
    [Parameter(Mandatory)][Alias('Output')][string]$OutputRoot,
    [switch]$TestBuild
)
$ErrorActionPreference = 'Stop'
$PlayerRoot = (Resolve-Path -LiteralPath $PlayerRoot).Path
& (Join-Path $PSScriptRoot '../tests/validate-public.ps1') -PlayerRoot $PlayerRoot
# Build the launcher from the committed C# source, preserving the payload icon.
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /codepage:65001 /target:winexe /optimize+ /reference:System.Windows.Forms.dll ('/win32icon:' + (Join-Path $PlayerRoot 'assets/player-neon-07.ico')) ('/out:' + (Join-Path $PlayerRoot 'mpv-neon.exe')) (Join-Path $PSScriptRoot 'Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed' }
& $csc /nologo /codepage:65001 /target:winexe /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll ('/out:' + (Join-Path $PlayerRoot 'native/PlaylistWindow.exe')) (Join-Path $PlayerRoot 'native/PlaylistWindow.cs')
if ($LASTEXITCODE -ne 0) { throw 'Playlist window compilation failed' }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$compileArgs = @('/Qp', ('/DPayload=' + $PlayerRoot), ('/DSetupOut=' + $OutputRoot))
if ($TestBuild) { $compileArgs += '/DTestBuild','/DBuildName=mpv-Neon-Setup-v12-public-test' }
& $Compiler @compileArgs (Join-Path $PSScriptRoot 'Setup.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
