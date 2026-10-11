#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$Destination = (Join-Path $env:LOCALAPPDATA 'Programs\CodexBackgroundSkill\CodeFace-1.6.1'))
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\assets\runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Destination = [IO.Path]::GetFullPath($Destination)
$exe = Join-Path $Destination 'CodeFace.exe'
if (Test-Path -LiteralPath $exe) {
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ieq $manifest.exeSha256) { Write-Output $exe; return }
    throw 'An unrelated binary already exists at this destination. Choose another directory.'
}
if (-not $PSCmdlet.ShouldProcess($Destination, 'Download archived CodeFace, verify hashes and extract four known files (no execution)')) { return }
if ((Test-Path -LiteralPath $Destination) -and @(Get-ChildItem -LiteralPath $Destination -Force).Count) { throw 'Destination must be new or empty.' }
[void][IO.Directory]::CreateDirectory($Destination)
$archivePath = Join-Path $Destination 'download.zip'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $manifest.url -OutFile $archivePath -UseBasicParsing
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ine $manifest.archiveSha256) {
    throw 'Archive checksum mismatch. Nothing has been executed or extracted.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($name in @('CodeFace.exe','CodeFace.ico','LICENSE.txt','PROVENANCE.md')) {
        $entry = $archive.GetEntry($name)
        if (-not $entry -or $entry.Length -gt 100MB) { throw "Invalid archive entry: $name" }
        $inputStream = $entry.Open()
        $memory = New-Object IO.MemoryStream
        try { $inputStream.CopyTo($memory); [IO.File]::WriteAllBytes((Join-Path $Destination $name),$memory.ToArray()) }
        finally { $memory.Dispose(); $inputStream.Dispose() }
    }
} finally { $archive.Dispose() }
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ine $manifest.exeSha256) { throw 'Executable checksum mismatch.' }
[IO.File]::Delete($archivePath)
Write-Output $exe
