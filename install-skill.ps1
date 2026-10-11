#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$Destination)
$ErrorActionPreference = 'Stop'
if (-not $Destination) {
    $base = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $Destination = Join-Path $base 'skills\codex-background'
}
$source = Join-Path $PSScriptRoot 'skills\codex-background'
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) { throw 'Extract the complete repository before installing.' }
$target = [IO.Path]::GetFullPath($Destination)
if ([IO.Path]::GetFullPath($source) -eq $target) { throw 'Source and destination must differ.' }
if (-not $PSCmdlet.ShouldProcess($target, 'Install codex-background skill (does not change the current background)')) { return }
if (Test-Path -LiteralPath $target) {
    $parent = [IO.Path]::GetDirectoryName($target)
    $backup = Join-Path $parent ('codex-background-backup-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-ffff'))
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($backup)) -ne $parent) { throw 'Invalid backup path.' }
    Move-Item -LiteralPath $target -Destination $backup
    Write-Output "Previous skill saved to $backup"
}
[void][IO.Directory]::CreateDirectory($target)
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $target -Recurse
Write-Output "Skill installed: $target"
Write-Output 'Open a new Codex task; if it is not discovered, restart Codex and invoke $codex-background.'
