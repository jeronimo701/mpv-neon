param([Parameter(Mandatory=$true)][string]$AppDir)
$ErrorActionPreference='Stop'
try {
    $target=[IO.Path]::GetFullPath((Join-Path $AppDir 'runtime/torrserver/TorrServer-windows-amd64.exe'))
    $servers=@(Get-CimInstance Win32_Process -Filter "Name='TorrServer-windows-amd64.exe'")
    foreach ($server in $servers) {
        if (-not $server.ExecutablePath) { continue }
        $actual=[IO.Path]::GetFullPath($server.ExecutablePath)
        if (-not [String]::Equals($actual,$target,[StringComparison]::OrdinalIgnoreCase)) { continue }
        $owned=Get-Process -Id $server.ProcessId -ErrorAction SilentlyContinue
        if (-not $owned) { continue }
        # Check the live process again to avoid acting on a reused PID.
        if (-not [String]::Equals($owned.Path,$target,[StringComparison]::OrdinalIgnoreCase)) { continue }
        Stop-Process -InputObject $owned -Force
        if (-not $owned.WaitForExit(10000)) { throw 'Bundled TorrServer did not stop within 10 seconds.' }
    }
    exit 0
} catch {
    Write-Error -ErrorAction Continue ('Cannot stop bundled TorrServer: '+$_.Exception.Message)
    exit 1
}
