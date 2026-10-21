param(
    [string]$PrimaryServer='http://127.0.0.1:8090',
    [int]$FallbackPort=8099,
    [string]$DataDir='',
    [switch]$SkipDiscovery
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$binary=Join-Path $PSScriptRoot 'TorrServer-windows-amd64.exe'
if (-not $DataDir) { $DataDir=Join-Path $PSScriptRoot '../../portable_config/torrserver-data' }
$DataDir=[IO.Path]::GetFullPath($DataDir)
$primaryUri=[Uri]$PrimaryServer
function Test-TorrServer([string]$Address) {
    $script:lastHttpStatus=0
    try {
        $response=Invoke-WebRequest -UseBasicParsing -Uri ($Address.TrimEnd('/')+'/echo') -TimeoutSec 2
        $version=([string]$response.Content).Trim()
        if ($version -match '^(MatriX\.|TorrServer)') { return $version }
    } catch { if ($_.Exception.Response) { $script:lastHttpStatus=[int]$_.Exception.Response.StatusCode } }
    return $null
}
function Result([string]$Address,[string]$Source,[string]$Version,[int]$ServerPid=0) {
    @{ok=$true;server=$Address;source=$Source;version=$Version;pid=$ServerPid} | ConvertTo-Json -Compress
}
$mutex=$null; $locked=$false
try {
    if ($primaryUri.Scheme -notin @('http','https')) { throw 'Invalid TorrServer protocol' }
    $version=Test-TorrServer $PrimaryServer
    if ($version) { Result $PrimaryServer 'configured' $version; exit 0 }
    if ($script:lastHttpStatus -in @(401,403)) { throw 'Configured server requires authentication or denies access; fallback cancelled.' }
    if ($primaryUri.Host -notin @('127.0.0.1','localhost','::1','[::1]')) {
        throw 'Remote TorrServer unavailable; local fallback is only enabled for loopback addresses.'
    }
    if (-not $SkipDiscovery) {
        $servers=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'TorrServer%'" -ErrorAction SilentlyContinue)
        foreach ($serverProcess in $servers) {
            $ports=@(Get-NetTCPConnection -State Listen -OwningProcess $serverProcess.ProcessId -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty LocalPort -Unique | Select-Object -First 8)
            foreach ($port in $ports) {
                $address='http://127.0.0.1:'+ $port
                $version=Test-TorrServer $address
                if ($version) { Result $address 'discovered' $version $serverProcess.ProcessId; exit 0 }
            }
        }
    }
    if (-not (Test-Path -LiteralPath $binary)) { throw 'Bundled TorrServer executable missing' }
    if ($FallbackPort -lt 1024 -or $FallbackPort -gt 65526) { throw 'Invalid fallback port' }
    $sha=[Security.Cryptography.SHA256]::Create()
    $key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($DataDir.ToLowerInvariant())))).Replace('-','').Substring(0,24)
    $sha.Dispose()
    $mutex=New-Object Threading.Mutex($false,('Local\mpv-torrserver-'+$key))
    try { $locked=$mutex.WaitOne(15000) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if (-not $locked) { throw 'Timed out waiting for another player to start TorrServer' }
    # The other mpv instance may have finished launching while this one waited.
    $chosen=0
    for ($port=$FallbackPort;$port -lt $FallbackPort+10;$port++) {
        $address='http://127.0.0.1:'+ $port
        $version=Test-TorrServer $address
        if ($version) { Result $address 'fallback-existing' $version; exit 0 }
        $listener=$null
        try {
            $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port)
            $listener.Start(); $chosen=$port
        } catch {} finally { if ($listener) { $listener.Stop() } }
        if ($chosen) { break }
    }
    if (-not $chosen) { throw 'No free local fallback port' }
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $logPath=Join-Path $DataDir 'server.log'
    $arguments=@('--ip','127.0.0.1','--port',[string]$chosen,'--path',('"'+$DataDir+'"'),'--logpath',('"'+$logPath+'"'))
    $started=Start-Process -FilePath $binary -ArgumentList $arguments -WorkingDirectory $DataDir -WindowStyle Hidden -PassThru
    $address='http://127.0.0.1:'+ $chosen
    for ($attempt=0;$attempt -lt 30;$attempt++) {
        $version=Test-TorrServer $address
        if ($version) { Result $address 'bundled' $version $started.Id; exit 0 }
        $started.Refresh()
        if ($started.HasExited) { throw ('Bundled TorrServer exited: '+$started.ExitCode) }
        Start-Sleep -Milliseconds 250
    }
    throw 'Bundled TorrServer did not become ready; see portable_config/torrserver-data/server.log'
} catch {
    @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
