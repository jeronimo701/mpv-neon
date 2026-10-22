$ErrorActionPreference = 'Stop'
$playlistCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $playlistCompiler)) {
    $playlistCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
& $playlistCompiler /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/out:$PSScriptRoot\PlaylistWindow.exe" "$PSScriptRoot\PlaylistWindow.cs"
if ($LASTEXITCODE -ne 0) { throw 'PlaylistWindow build failed' }
