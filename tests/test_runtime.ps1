# Run with Windows PowerShell 5.1; does not touch the live Codex app or startup tasks.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\skills\codex-background\scripts\Runtime.Core.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$healthy = '{"healthy":true,"expected_theme_id":"test","pages":[{"healthy":true,"theme_id":"test","hidden_controls":0,"low_contrast_text":0}]}'
$result = [pscustomobject]@{ ExitCode = 0; Out = $healthy; Err = '' }
Assert (Test-ThemeHealth $result 'test') 'Healthy report rejected'
$result.Out = '{"healthy":false,"expected_theme_id":"test","pages":[{"healthy":true,"theme_id":"test","hidden_controls":0,"low_contrast_text":0}]}'
Assert (-not (Test-ThemeHealth $result 'test')) 'Nested true must not override top-level false'
$result.Out = $healthy.Replace('"healthy":true', '"healthy":"true"')
Assert (-not (Test-ThemeHealth $result 'test')) 'String booleans must fail'
$result.Out = '{"healthy":true,"expected_theme_id":"test","pages":[]}'
Assert (-not (Test-ThemeHealth $result 'test')) 'Empty pages must fail'
$result.Out = $healthy
Assert (-not (Test-ThemeHealth $result 'wrong')) 'Wrong theme must fail'
$result.ExitCode = 1
Assert (-not (Test-ThemeHealth $result 'test')) 'Nonzero exit code must fail'
Assert ((Get-DeclaredPort 'app --remote-debugging-port=9229 --inspect=9329') -eq 9229) 'Actual CDP port must win'
Assert ((Get-DeclaredPort 'app --remote-debugging-port 9341') -eq 9341) 'Spaced port failed'
Assert ((Get-DeclaredPort 'app --remote-debugging-port=99999') -eq 0) 'Invalid port accepted'
Assert ((Get-DeclaredPort 'app --inspect=9329') -eq 0) 'Inspector port confused with CDP'
$shellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$oldLocalData = $env:LOCALAPPDATA
$result = Invoke-ThemeProcess $shellExe @('-NoProfile','-Command', '[Console]::Write($env:LOCALAPPDATA); exit 7') 'X:\IsolatedData'
Assert ($result.ExitCode -eq 7) 'Child exit code not captured'
Assert ($result.Out -eq 'X:\IsolatedData') 'Child override missing'
Assert ($env:LOCALAPPDATA -eq $oldLocalData) 'Parent environment was modified'
$value = 'a path\with "quotes" and trailing\'
$command = '[Console]::Write(' + "'" + $value.Replace("'", "''") + "')"
$result = Invoke-ThemeProcess $shellExe @('-NoProfile','-Command',$command) ''
Assert ($result.Out -eq $value) 'Native argument quoting failed'
$timedOut = $false
try { $null = Invoke-ThemeProcess $shellExe @('-NoProfile','-Command','Start-Sleep -Seconds 10') '' 1 } catch { $timedOut = $_.Exception.Message -match 'timed out' }
Assert $timedOut 'Subprocess timeout failed'
Write-Output 'PASS: health gate, dynamic ports, child isolation, native quoting, bounded subprocess timeout.'
