param([switch]$Auto)
# Loader: reads PCTools.ps1 as UTF-8 so Greek text always works. Do not edit.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Please start PC Tools with Start-PCTools.bat (Administrator rights needed).' -ForegroundColor Red
    if (-not $Auto) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
$ToolDir = $PSScriptRoot
$AppRoot = Split-Path -Parent $PSScriptRoot
$main = Join-Path $ToolDir 'PCTools.ps1'
if (-not (Test-Path $main)) {
    Write-Host 'PCTools.ps1 was not found next to this file.' -ForegroundColor Red
    if (-not $Auto) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
$sb = $null
try {
    $code = [IO.File]::ReadAllText($main, [Text.Encoding]::UTF8)
    $sb = [scriptblock]::Create($code)
} catch {
    Write-Host "Could not load PCTools.ps1: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $Auto) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}

# Run WITHOUT try/catch on purpose: a small error in one screen is skipped
# instead of closing the whole tool. Hidden errors are written to logs\errors.log.
$Error.Clear()
& $sb -Auto:$Auto

try {
    $real = @($Error | Where-Object {
        $_.FullyQualifiedErrorId -notmatch 'NotFound|PathNotFound|ItemNotFound|NoMatchingDrive|ObjectNotFound|AccessDenied|UnauthorizedAccess|IOException|TypeNotFound'
    } | Select-Object -First 40)
    if ($real.Count -gt 0) {
        $logDir = Join-Path $ToolDir 'logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $stamp = Get-Date -Format 'dd/MM/yyyy HH:mm'
        $lines = $real | ForEach-Object { "$stamp  line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" }
        Add-Content -Path (Join-Path $logDir 'errors.log') -Value $lines -Encoding UTF8
    }
} catch {}
