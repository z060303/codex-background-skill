Set-StrictMode -Version 2.0

function ConvertTo-NativeArgument([string]$Value) {
    # CommandLineToArgvW quoting: escape backslashes before quotes and at the end.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-ThemeProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$LocalDataBase, [int]$TimeoutSeconds = 35)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.WorkingDirectory = Split-Path -Parent $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    if ($LocalDataBase) { $info.EnvironmentVariables['LOCALAPPDATA'] = $LocalDataBase }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $handle = $process.Handle
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            throw "CodeFace timed out after $TimeoutSeconds seconds."
        }
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Out = $stdout.Result; Err = $stderr.Result }
    } finally { $process.Dispose() }
}

function Test-ThemeHealth {
    param($Result, [string]$ThemeId)
    if ($Result.ExitCode -ne 0) { return $false }
    try {
        $report = $Result.Out | ConvertFrom-Json
        if ($report.healthy -isnot [bool] -or -not $report.healthy) { return $false }
        if ($report.expected_theme_id -cne $ThemeId -or @($report.pages).Count -eq 0) { return $false }
        foreach ($page in $report.pages) {
            if ($page.healthy -isnot [bool] -or -not $page.healthy -or $page.theme_id -cne $ThemeId) { return $false }
            if ($page.hidden_controls -gt 0 -or $page.low_contrast_text -gt 0) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-DeclaredPort([string]$CommandLine) {
    if ($CommandLine -match '--remote-debugging-port(?:=|\s+)(\d+)') {
        $value = [int]$Matches[1]
        if ($value -gt 0 -and $value -le 65535) { return $value }
    }
    return 0
}

function Get-CodexMain([string]$ExplicitExecutable) {
    $session = (Get-Process -Id $PID).SessionId
    $found = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe' OR Name='Codex.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.SessionId -eq $session -and $_.CommandLine -and $_.CommandLine -notmatch '--type=' -and
            (($_.ExecutablePath -match 'WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\') -or
             ($ExplicitExecutable -and $_.ExecutablePath -eq $ExplicitExecutable))
        })
    if ($found.Count -gt 1) { throw 'Multiple Codex main processes found. Close the extra instance before applying.' }
    if ($found.Count -eq 1) { return $found[0] }
    return $null
}

function Test-OwnedEndpoint($Main, [int]$Port) {
    if (-not $Main -or $Port -lt 1) { return $false }
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if (-not ($listeners | Where-Object { $_.OwningProcess -eq $Main.ProcessId -and $_.LocalAddress -in @('127.0.0.1', '::1') })) { return $false }
    if ($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') }) { throw 'CDP is not restricted to loopback.' }
    try {
        $endpoint = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 3
        $uri = [uri]$endpoint.webSocketDebuggerUrl
        return $uri.Scheme -eq 'ws' -and $uri.Host -in @('127.0.0.1', 'localhost', '[::1]', '::1')
    } catch { return $false }
}

function Copy-ThemeFiles([string]$Source, [string]$Destination) {
    $manifest = Get-Content -LiteralPath (Join-Path $Source 'theme.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $manifest.image -cne 'background.png') {
        throw 'Use a generated theme with a kebab-case ID and a local background.png.'
    }
    [void][System.IO.Directory]::CreateDirectory($Destination)
    foreach ($name in @('theme.json', 'codeface.css', 'background.png')) {
        $file = Get-Item -LiteralPath (Join-Path $Source $name)
        $max = if ($name -eq 'background.png') { 16MB } else { 256KB }
        if ($file.Length -gt $max -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unsupported theme file: $name" }
        $target = Join-Path $Destination $name
        # Write bytes, not Copy-Item: do not transfer an EFS encryption attribute.
        [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($file.FullName))
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::Encrypted) {
            throw 'Destination inherits EFS encryption. Choose an ordinary -InstallRoot; do not decrypt AppData.'
        }
    }
    return $manifest
}
