#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install','Apply','Diagnose','Launch','Watch','EnableStartup','DisableStartup','Restore')]
    [string]$Action = 'Diagnose',
    [string]$ThemePath,
    [string]$CodeFaceExe,
    [string]$CodexExe,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\CodexBackgroundSkill'),
    [ValidateRange(1024,65535)][int]$Port = 9341,
    [switch]$LaunchAtLogin
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Runtime.Core.ps1')
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$configPath = Join-Path $InstallRoot 'config.json'
$pausePath = Join-Path $InstallRoot 'paused'
$lockPath = Join-Path $InstallRoot 'watch.lock'
$logPath = Join-Path $InstallRoot 'watcher.log'
$taskName = 'CodexBackgroundSkill'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Write-Log([string]$Message) {
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 512KB) {
        [IO.File]::WriteAllLines($logPath, @(Get-Content -LiteralPath $logPath -Tail 150))
    }
    [IO.File]::AppendAllText($logPath, ('{0:o} {1}{2}' -f [DateTime]::Now, $Message, [Environment]::NewLine))
}
function Save-Config($Value) {
    [IO.File]::WriteAllText($configPath, ($Value | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
}
function Invoke-CF([string[]]$Arguments) {
    return Invoke-ThemeProcess -Executable $config.CodeFaceExe -Arguments $Arguments -LocalDataBase $config.RuntimeBase
}
function Require-Result($Result) {
    if ($Result.ExitCode -ne 0) { throw "CodeFace failed ($($Result.ExitCode)): $($Result.Err) $($Result.Out)" }
}
function Get-Endpoint {
    $main = Get-CodexMain $config.CodexExe
    $actualPort = if ($main) { Get-DeclaredPort $main.CommandLine } else { 0 }
    if (-not (Test-OwnedEndpoint $main $actualPort)) {
        throw 'Codex has no ready loopback endpoint. Close it when convenient, then use Codex with background.lnk.'
    }
    return [pscustomobject]@{ Main = $main; Port = $actualPort }
}
function Pause-Watcher {
    [IO.File]::WriteAllText($pausePath, 'Paused explicitly')
    # Wait for in-flight injection to finish before restore; never kill Codex.
    $deadline = [DateTime]::UtcNow.AddSeconds(80)
    do {
        try { $stream = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None'); $stream.Dispose(); return } catch {}
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Watcher is still busy. Startup is paused; wait and retry restoration.'
}
function Clear-Pause { if ([IO.File]::Exists($pausePath)) { [IO.File]::Delete($pausePath) } }
function Apply-Verified($Endpoint) {
    $active = Get-Content -LiteralPath (Join-Path $config.DataRoot 'theme\theme.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($active.id -cne $config.ThemeId) { throw 'Active theme changed in CodeFace. Reinstall the intended theme before monitoring it.' }
    $result = Invoke-CF @('--inject-active', [string]$Endpoint.Port)
    Require-Result $result
    $health = Invoke-CF @('--health-check', $config.ThemeId, [string]$Endpoint.Port)
    if (-not (Test-ThemeHealth $health $config.ThemeId)) {
        if ($config.PreviousTheme -and (Test-Path -LiteralPath $config.PreviousTheme)) {
            $previous = Copy-ThemeFiles $config.PreviousTheme (Join-Path $config.DataRoot 'theme')
            $rollback = Invoke-CF @('--inject-active', [string]$Endpoint.Port)
            $check = Invoke-CF @('--health-check', $previous.id, [string]$Endpoint.Port)
            Write-Log "Rollback healthy=$(Test-ThemeHealth $check $previous.id)"
        }
        throw "Theme health gate failed; automatic retry is paused. $($health.Out)"
    }
    $config.LastPort = $Endpoint.Port
    $statePath = Join-Path $config.DataRoot 'state.json'
    $config.StateStamp = if (Test-Path -LiteralPath $statePath) { [string](Get-Item -LiteralPath $statePath).LastWriteTimeUtc.Ticks } else { '' }
    Save-Config $config
    Write-Log "Verified theme $($config.ThemeId) on PID $($Endpoint.Main.ProcessId), port $($Endpoint.Port)."
    return $health.Out
}
function Resolve-CodexExecutable {
    if ($config.CodexExe -and (Test-Path -LiteralPath $config.CodexExe)) { return $config.CodexExe }
    $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
    if ($package) {
        foreach ($name in @('ChatGPT.exe','Codex.exe')) {
            $candidate = Join-Path $package.InstallLocation "app\$name"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    throw 'Codex desktop executable not found. Supply -CodexExe when installing for a non-Store installation.'
}
function Launch-Codex {
    if (Get-CodexMain $config.CodexExe) { return }
    if (Get-NetTCPConnection -LocalPort $config.LaunchPort -State Listen -ErrorAction SilentlyContinue) { throw 'Launch port is already occupied.' }
    $exe = Resolve-CodexExecutable
    # Inherit normal environment. Only Invoke-CF overrides LOCALAPPDATA.
    Start-Process -FilePath $exe -ArgumentList '--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$($config.LaunchPort)" | Out-Null
}
function Get-OurTask {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task -and -not (($task.Actions | Select-Object -ExpandProperty Arguments) -match [regex]::Escape((Join-Path $InstallRoot 'ThemeRuntime.ps1')))) {
        throw 'A task with the same name belongs to a different installation. Diagnose it before migrating.'
    }
    return $task
}

if ($Action -eq 'Install') {
    if (-not $ThemePath -or -not $CodeFaceExe) { throw 'Install needs -ThemePath and -CodeFaceExe.' }
    $ThemePath = (Resolve-Path -LiteralPath $ThemePath).Path
    $CodeFaceExe = (Resolve-Path -LiteralPath $CodeFaceExe).Path
    if (-not $PSCmdlet.ShouldProcess($InstallRoot, 'Install theme helper and stage theme; leave live Codex unchanged')) { return }
    [void][IO.Directory]::CreateDirectory($InstallRoot)
    Pause-Watcher
    $runtimeBase = Join-Path $InstallRoot 'runtime'
    [void][IO.Directory]::CreateDirectory($runtimeBase)
    $rootResult = Invoke-ThemeProcess $CodeFaceExe @('--print-data-root') $runtimeBase
    Require-Result $rootResult
    $dataRoot = $rootResult.Out.Trim()
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $runtimeBase 'CodeFace'))
    if ([IO.Path]::GetFullPath($dataRoot) -ne $expectedRoot) { throw 'Unexpected CodeFace data root. Check binary compatibility.' }
    $staged = Join-Path $InstallRoot 'staged-theme'
    $manifest = Copy-ThemeFiles $ThemePath $staged
    $previousTheme = ''
    $active = Join-Path $dataRoot 'theme'
    if (Test-Path -LiteralPath (Join-Path $active 'theme.json')) {
        $previousTheme = Join-Path $InstallRoot ('backups\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-ffff'))
        $null = Copy-ThemeFiles $active $previousTheme
    }
    $import = Invoke-ThemeProcess $CodeFaceExe @('--import-theme', $staged) $runtimeBase
    Require-Result $import
    $null = Copy-ThemeFiles (Join-Path $dataRoot ('themes\' + $manifest.id)) $active
    foreach ($name in @('ThemeRuntime.ps1','Runtime.Core.ps1')) {
        $source = Join-Path $PSScriptRoot $name
        $destination = Join-Path $InstallRoot $name
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($destination)) {
            [IO.File]::WriteAllBytes($destination, [IO.File]::ReadAllBytes($source))
        }
    }
    $config = [pscustomobject]@{ Schema = 1; CodeFaceExe = $CodeFaceExe; CodexExe = $CodexExe; RuntimeBase = $runtimeBase; DataRoot = $dataRoot; ThemeId = $manifest.id; PreviousTheme = $previousTheme; LaunchPort = $Port; LastPort = 0; LaunchAtLogin = $false; StateStamp = '' }
    Save-Config $config
    $shell = New-Object -ComObject WScript.Shell
    foreach ($entry in @(@('Codex with background','Launch'), @('Restore native appearance','Restore'))) {
        $shortcut = $shell.CreateShortcut((Join-Path $InstallRoot ($entry[0] + '.lnk')))
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument (Join-Path $InstallRoot 'ThemeRuntime.ps1')) + ' -InstallRoot ' + (ConvertTo-NativeArgument $InstallRoot) + ' -Action ' + $entry[1]
        $shortcut.WorkingDirectory = $InstallRoot
        $shortcut.WindowStyle = 7
        $shortcut.Save()
    }
    Write-Output "Installed $($manifest.id) at $InstallRoot. Live app unchanged; startup disabled until EnableStartup."
    return
}

if (-not (Test-Path -LiteralPath $configPath)) {
    if ($Action -eq 'Diagnose') { Write-Output 'No helper installed. Use Install after previewing a theme.'; return }
    throw "Configuration not found: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Action -eq 'Diagnose') {
    $main = Get-CodexMain $config.CodexExe
    $actualPort = if ($main) { Get-DeclaredPort $main.CommandLine } else { 0 }
    [pscustomobject]@{ Theme = $config.ThemeId; DataRoot = $config.DataRoot; Paused = [IO.File]::Exists($pausePath); Port = $actualPort; EndpointReady = (Test-OwnedEndpoint $main $actualPort); Task = (Get-OurTask | Select-Object TaskName, State); Log = $logPath } | ConvertTo-Json -Depth 4
    if (Test-OwnedEndpoint $main $actualPort) {
        $health = Invoke-CF @('--health-check', $config.ThemeId, [string]$actualPort)
        Write-Output $health.Out
    }
    return
}
if (-not $PSCmdlet.ShouldProcess($InstallRoot, $Action)) { return }

switch ($Action) {
    'DisableStartup' {
        Pause-Watcher
        if (Get-OurTask) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
        Write-Output 'Startup disabled and watcher paused. The current picture is unchanged.'
    }
    'EnableStartup' {
        Pause-Watcher
        $null = Get-OurTask
        $config.LaunchAtLogin = [bool]$LaunchAtLogin
        Save-Config $config
        $argsText = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument (Join-Path $InstallRoot 'ThemeRuntime.ps1')) + ' -Action Watch -InstallRoot ' + (ConvertTo-NativeArgument $InstallRoot)
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $taskAction = New-ScheduledTaskAction -Execute $powershell -Argument $argsText -WorkingDirectory $InstallRoot
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Clear-Pause
        Start-ScheduledTask -TaskName $taskName
        Write-Output 'Login task configured and started. Check Diagnose and watcher.log; a reboot has not been tested.'
    }
    'Apply' {
        Pause-Watcher
        $endpoint = Get-Endpoint
        Apply-Verified $endpoint
        Clear-Pause
        if (Get-OurTask) { Start-ScheduledTask -TaskName $taskName }
    }
    'Launch' {
        Pause-Watcher
        Launch-Codex
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        $endpoint = $null
        do { try { $endpoint = Get-Endpoint; break } catch { Start-Sleep -Seconds 2 } } while ([DateTime]::UtcNow -lt $deadline)
        if (-not $endpoint) { throw 'No ready endpoint after 45 seconds. An already-open app is never forcibly restarted.' }
        Apply-Verified $endpoint
        Clear-Pause
        if (Get-OurTask) { Start-ScheduledTask -TaskName $taskName }
    }
    'Restore' {
        Pause-Watcher
        if (Get-OurTask) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
        $main = Get-CodexMain $config.CodexExe
        if (-not $main) { Write-Output 'Startup disabled. The next normal Codex launch uses its native appearance.'; return }
        $endpoint = Get-Endpoint
        $result = Invoke-CF @('--restore')
        Require-Result $result
        $verify = Invoke-CF @('--verify', [string]$endpoint.Port)
        if ($verify.ExitCode -eq 0) {
            # v1.6.1 --restore defaults to 9341 when no saved state exists.
            # Let CodeFace record the actual port and remove its own layer.
            $bridge = Invoke-CF @('--start-control', [string]$endpoint.Port)
            Require-Result $bridge
            $result = Invoke-CF @('--restore')
            Require-Result $result
            $verify = Invoke-CF @('--verify', [string]$endpoint.Port)
        }
        if (-not (Test-OwnedEndpoint $endpoint.Main $endpoint.Port)) { throw 'Endpoint disappeared; native appearance not verified.' }
        if ($verify.ExitCode -eq 0) { throw 'CodeFace markers remain. Startup is disabled; inspect other background managers.' }
        if (($verify.Err + $verify.Out) -notmatch 'CodeFace marker not detected on the live page') { throw 'Restore verification failed for an unrelated reason; inspect the window and log.' }
        Write-Output 'Startup disabled; CodeFace restored. Inspect the window to confirm native appearance.'
    }
    'Watch' {
        if ([IO.File]::Exists($pausePath)) { return }
        try { $watchLock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { return }
        try {
            Write-Log 'Watcher started.'
            $failures = 0
            $first = $true
            $lastMain = 0
            $lastHealth = [DateTime]::MinValue
            while (-not [IO.File]::Exists($pausePath)) {
                try {
                    if ($first -and $config.LaunchAtLogin) { Launch-Codex }
                    $first = $false
                    $statePath = Join-Path $config.DataRoot 'state.json'
                    if (Test-Path -LiteralPath $statePath) {
                        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $stateStamp = [string](Get-Item -LiteralPath $statePath).LastWriteTimeUtc.Ticks
                        if ($state.PSObject.Properties['injection_enabled'] -and $state.injection_enabled -eq $false -and $stateStamp -ne $config.StateStamp) {
                            Write-Log 'Native appearance selected in CodeFace. Watcher paused.'
                            [IO.File]::WriteAllText($pausePath, 'Native appearance selected')
                            break
                        }
                    }
                    $main = Get-CodexMain $config.CodexExe
                    if ($main) {
                        $actualPort = Get-DeclaredPort $main.CommandLine
                        if (Test-OwnedEndpoint $main $actualPort) {
                            if ($lastMain -ne $main.ProcessId -or ([DateTime]::UtcNow - $lastHealth).TotalSeconds -ge 60) {
                                $health = Invoke-CF @('--health-check', $config.ThemeId, [string]$actualPort)
                                if (-not (Test-ThemeHealth $health $config.ThemeId)) {
                                    $null = Apply-Verified ([pscustomobject]@{ Main = $main; Port = $actualPort })
                                }
                                $lastMain = $main.ProcessId
                                $lastHealth = [DateTime]::UtcNow
                                $failures = 0
                            }
                        } elseif ($lastMain -ne $main.ProcessId) {
                            Write-Log 'Waiting for a Codex endpoint. If launched normally, close and use the background launcher.'
                            $lastMain = $main.ProcessId
                        }
                    } else { $lastMain = 0 }
                } catch {
                    $failures++
                    Write-Log $_.Exception.Message
                    if ($failures -ge 3) {
                        [IO.File]::WriteAllText($pausePath, 'Paused after three failures; inspect watcher.log')
                        break
                    }
                }
                for ($i = 0; $i -lt 5 -and -not [IO.File]::Exists($pausePath); $i++) { Start-Sleep -Seconds 1 }
            }
            Write-Log 'Watcher stopped.'
        } finally { $watchLock.Dispose() }
    }
}
