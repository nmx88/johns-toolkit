param([switch]$Auto, [switch]$DebugMode)
# John's Toolkit by nmx88 - launcher (Windows 10/11). ASCII only on purpose.
$ErrorActionPreference = 'SilentlyContinue'
$AppRoot = Split-Path -Parent $PSScriptRoot
$ToolDir = Join-Path $AppRoot 'classic'
$StartLog = Join-Path $AppRoot 'logs\startup.log'
function Read-Utf8([string]$p) { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }
function Write-Stage([string]$t) {
    try {
        New-Item -ItemType Directory -Path (Split-Path $StartLog) -Force | Out-Null
        Add-Content -Path $StartLog -Value ("{0}  [pid {1}] {2}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $PID, $t) -Encoding UTF8
    } catch {}
    if ($DebugMode) { Write-Host ">> $t" -ForegroundColor Cyan }
}
function Show-Msg([string]$text) {
    if ($Auto) { return }
    if ($DebugMode) { Write-Host $text -ForegroundColor Red }
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show($text, "John's Toolkit")
}
function Stop-Debug {
    if (-not $DebugMode) { return }
    $shown = @($Error | Select-Object -First 25)
    if ($shown.Count -gt 0) {
        Write-Host "`nErrors ($($Error.Count) total, first 25):" -ForegroundColor Yellow
        foreach ($e in $shown) { Write-Host ("  line {0}: {1}" -f $e.InvocationInfo.ScriptLineNumber, $e.Exception.Message) -ForegroundColor Yellow }
    } else { Write-Host "`nNo errors." -ForegroundColor Green }
    Write-Host "`nLog: $StartLog"
    Read-Host 'Press Enter to close'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$apt = [Threading.Thread]::CurrentThread.ApartmentState
Write-Stage "start: admin=$isAdmin sta=$apt auto=$Auto debug=$DebugMode ps=$($PSVersionTable.PSVersion) path=$PSCommandPath"

# 1) Windows 10/11 only
$build = 0
try { $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).CurrentBuildNumber } catch {}
Write-Stage "windows build: $build"
if ($build -gt 0 -and $build -lt 10240) {
    Show-Msg ("John's Toolkit requires Windows 10 or Windows 11.`n`n" +
              "Windows 7 and 8 no longer receive security updates from Microsoft. " +
              "Upgrading to a supported version of Windows is strongly recommended.")
    exit 1
}

# 2) Administrator rights (asks once with UAC)
if (-not $isAdmin) {
    if ($Auto) { Write-Stage 'auto mode without admin rights: stop'; exit 1 }
    $style = '-WindowStyle Hidden'; $extra = ''
    if ($DebugMode) { $style = '-NoExit'; $extra = ' -DebugMode' }
    Write-Stage 'asking for administrator rights (UAC)...'
    try {
        Start-Process powershell.exe -Verb RunAs -ErrorAction Stop -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA $style -File `"$PSCommandPath`"$extra"
        Write-Stage 'elevated copy started'
    } catch {
        Write-Stage "UAC failed or was cancelled: $($_.Exception.Message)"
        Show-Msg "John's Toolkit needs administrator rights.`n`nThe Windows prompt was cancelled or blocked.`n`nIf you did not see a prompt, look for a flashing shield icon on the taskbar."
    }
    exit
}

# 3) Load the engine (classic functions + core)
try {
    foreach ($f in @((Join-Path $ToolDir 'PCTools.ps1'), (Join-Path $PSScriptRoot 'Core.ps1'), (Join-Path $PSScriptRoot 'Worker.ps1'), (Join-Path $PSScriptRoot 'Gui.ps1'), (Join-Path $PSScriptRoot 'MainWindow.xaml'))) {
        if (-not (Test-Path -LiteralPath $f)) { throw "Missing file: $f" }
    }
    $classicText = Read-Utf8 (Join-Path $ToolDir 'PCTools.ps1')
    $cut = $classicText.IndexOf('if ($Auto) { Invoke-AutoClean; return }')
    if ($cut -gt 0) { $classicText = $classicText.Substring(0, $cut) }
    $Engine = $classicText + "`r`n" + (Read-Utf8 (Join-Path $PSScriptRoot 'Core.ps1'))
    $WorkerEngine = $Engine + "`r`n" + (Read-Utf8 (Join-Path $PSScriptRoot 'Worker.ps1'))
    Write-Stage "engine loaded ($($Engine.Length) chars)"
} catch {
    Write-Stage "ENGINE LOAD FAILED: $($_.Exception.Message)"
    Show-Msg "John's Toolkit could not start.`n`n$($_.Exception.Message)`n`nPlease extract the whole zip again (all folders)."
    Stop-Debug; exit 1
}
$Error.Clear()

if ($Auto) {
    Write-Stage 'auto cleanup: start'
    & ([scriptblock]::Create($Engine + "`r`nInvoke-AutoCleanCore"))
    Write-Stage 'auto cleanup: done'
} else {
    # The window needs a single-threaded apartment
    if ($apt -ne 'STA') {
        Write-Stage 'restarting in STA mode'
        $style = '-WindowStyle Hidden'; $extra = ''
        if ($DebugMode) { $style = '-NoExit'; $extra = ' -DebugMode' }
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA $style -File `"$PSCommandPath`"$extra"
        exit
    }
    # Only one window at a time (a double click used to open two)
    $createdNew = $false
    $script:GuiMutex = [System.Threading.Mutex]::new($true, 'Local\JohnsToolkitGui', [ref]$createdNew)
    if (-not $createdNew) { Write-Stage 'already running: this copy closes'; exit }
    $guiCode = $null
    try { $guiCode = [scriptblock]::Create($Engine + "`r`n" + (Read-Utf8 (Join-Path $PSScriptRoot 'Gui.ps1'))) }
    catch {
        Write-Stage "GUI CODE PARSE FAILED: $($_.Exception.Message)"
        Show-Msg "John's Toolkit could not start (code error).`n`n$($_.Exception.Message)"
        Stop-Debug; exit 1
    }
    Write-Stage 'opening window...'
    # Run WITHOUT try/catch on purpose: a small error is skipped instead of closing the app.
    & $guiCode
    Write-Stage 'window closed'
    try { $script:GuiMutex.ReleaseMutex() } catch {}
}

# 4) Keep a log of hidden errors (helps with bug reports)
try {
    $real = @($Error | Where-Object {
        $_.FullyQualifiedErrorId -notmatch 'NotFound|PathNotFound|ItemNotFound|NoMatchingDrive|ObjectNotFound|AccessDenied|UnauthorizedAccess|IOException|TypeNotFound'
    } | Select-Object -First 40)
    if ($real.Count -gt 0) {
        $logDir = Join-Path $AppRoot 'logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $stamp = Get-Date -Format 'dd/MM/yyyy HH:mm'
        $lines = $real | ForEach-Object { "$stamp  line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" }
        Add-Content -Path (Join-Path $logDir 'errors.log') -Value $lines -Encoding UTF8
    }
} catch {}
Stop-Debug
