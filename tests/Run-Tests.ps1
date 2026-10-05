# John's Toolkit by nmx88 - automated tests
#
# On Windows (and in GitHub Actions): real WPF, real read-only system calls, and a screenshot of every page.
# On any other system: the window code runs against a small stand-in for WPF (tests\FakeWpf.cs).
# Nothing on the PC is changed: every action that would change something is replaced by a safe stand-in.
#
#   powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
#
# Exit code 0 = every check passed. Results: tests\out\results.md, screenshots: tests\out\screens\
param([string]$OutDir = '')
$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $Root 'tests\out' }
$OnWindows = ($env:OS -eq 'Windows_NT')

# WPF needs a single-threaded apartment
if ($OnWindows -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath -OutDir $OutDir
    exit $LASTEXITCODE
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# ---------------------------------------------------------------- results
$script:Results = [System.Collections.ArrayList]::new()
function Add-Result([string]$group, [string]$name, [string]$state, [string]$detail = '') {
    $detail = ($detail -replace '\s+', ' ').Trim(); if ($detail.Length -gt 400) { $detail = $detail.Substring(0, 400) + '...' }
    [void]$script:Results.Add([pscustomobject]@{ Group = $group; Name = $name; State = $state; Detail = $detail })
    $color = @{ pass = 'Green'; fail = 'Red'; skip = 'DarkGray' }[$state]
    $d = ''; if ($detail) { $d = '  -  ' + $detail }
    Write-Host ("  [{0}] {1}{2}" -f $state.ToUpper(), $name, $d) -ForegroundColor $color
}
# Errors that only mean "this PC does not have that thing" (no battery, no TPM, a missing folder...)
$IgnoredErrors = 'CommandNotFound|PathNotFound|DriveNotFound|ItemNotFound|ObjectNotFound|NoMatchingDrive|UnauthorizedAccess|AccessDenied|IOException|NotSupported|PlatformNotSupported|HRESULT 0x8007|CimJob|Cim|WinEvent|NoMatchingEventsFound'
function Invoke-Check([string]$group, [string]$name, [scriptblock]$sb, [switch]$OnlyExceptions) {
    $Error.Clear()
    $r = $null
    try { $r = @(& $sb) | Select-Object -Last 1 } catch { Add-Result $group $name 'fail' "$($_.Exception.Message)"; return }
    if ($r -is [string] -and $r.StartsWith('FAIL:')) { Add-Result $group $name 'fail' $r.Substring(5); return }
    if ($r -is [string] -and $r.StartsWith('SKIP:')) { Add-Result $group $name 'skip' $r.Substring(5); return }
    if (-not $OnlyExceptions) {
        $errs = @($Error | Where-Object { "$($_.FullyQualifiedErrorId) $($_.Exception.GetType().Name)" -notmatch $IgnoredErrors })
        if ($errs.Count -gt 0) {
            Add-Result $group $name 'fail' ((@($errs | Select-Object -First 3) | ForEach-Object { "line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" }) -join ' | ')
            return
        }
    }
    Add-Result $group $name 'pass' "$r"
}
function Read-Utf8([string]$p) { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }

Write-Host "John's Toolkit - tests ($(if ($OnWindows) { 'Windows, real WPF' } else { 'stand-in WPF' }), PowerShell $($PSVersionTable.PSVersion))" -ForegroundColor Cyan

# ================================================================ 1. STATIC CHECKS (every system)
Write-Host "`n1) Static checks" -ForegroundColor Cyan
$psFiles = @(Get-ChildItem $Root -Recurse -Include *.ps1 | Where-Object { $_.FullName -notmatch '[\\/](dist|tests[\\/]out)[\\/]' })
$guiFiles = @(Get-ChildItem (Join-Path $Root 'app/gui') -Filter *.ps1 | Sort-Object Name)
$classic = Read-Utf8 (Join-Path $Root 'classic/PCTools.ps1')
$classicEngine = $classic.Substring(0, $classic.IndexOf('if ($Auto) { Invoke-AutoClean; return }'))
$coreText = Read-Utf8 (Join-Path $Root 'app/Core.ps1')
$guiText = ($guiFiles | ForEach-Object { Read-Utf8 $_.FullName }) -join "`r`n"
$xamlText = Read-Utf8 (Join-Path $Root 'app/MainWindow.xaml')
$en = @{}; foreach ($p in (Read-Utf8 (Join-Path $Root 'lang/en.json') | ConvertFrom-Json).PSObject.Properties) { $en[$p.Name] = "$($p.Value)" }

Invoke-Check 'static' "Every .ps1 file parses ($($psFiles.Count) files)" {
    $bad = foreach ($f in $psFiles) { $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e) | Out-Null; if ($e.Count) { "$($f.Name): $($e[0].Message) (line $($e[0].Extent.StartLineNumber))" } }
    if ($bad) { "FAIL:" + ($bad -join '; ') }
}
Invoke-Check 'static' 'The combined window program parses (as the Launcher builds it)' {
    $all = $classicEngine + "`r`n" + $coreText + "`r`n" + $guiText + "`r`nStart-JohnsToolkitWindow"
    $e = $null; [System.Management.Automation.Language.Parser]::ParseInput($all, [ref]$null, [ref]$e) | Out-Null
    if ($e.Count) { "FAIL:$($e[0].Message) (line $($e[0].Extent.StartLineNumber))" }
}
Invoke-Check 'static' 'Language files: same keys and same {0} placeholders as English' {
    $bad = @()
    foreach ($f in Get-ChildItem (Join-Path $Root 'lang') -Filter *.json) {
        $d = @{}; foreach ($p in (Read-Utf8 $f.FullName | ConvertFrom-Json).PSObject.Properties) { $d[$p.Name] = "$($p.Value)" }
        $miss = @($en.Keys | Where-Object { -not $d.ContainsKey($_) }); $extra = @($d.Keys | Where-Object { -not $en.ContainsKey($_) })
        if ($miss.Count) { $bad += "$($f.Name) missing $($miss.Count): $(($miss | Select-Object -First 3) -join ', ')" }
        if ($extra.Count) { $bad += "$($f.Name) extra: $(($extra | Select-Object -First 3) -join ', ')" }
        foreach ($k in $en.Keys) {
            if (-not $d.ContainsKey($k)) { continue }
            $a = (@([regex]::Matches($en[$k], '\{\d\}') | ForEach-Object { $_.Value }) | Sort-Object -Unique) -join ''
            $b = (@([regex]::Matches($d[$k], '\{\d\}') | ForEach-Object { $_.Value }) | Sort-Object -Unique) -join ''
            if ($a -ne $b) { $bad += "$($f.Name) $k placeholders '$b' vs '$a'" }
        }
    }
    if ($bad) { "FAIL:" + (($bad | Select-Object -First 6) -join '; ') } else { "$($en.Count) keys x 6 languages" }
}
Invoke-Check 'static' 'Every text key used in the code exists' {
    $code = $coreText + $guiText
    $keys = @([regex]::Matches($code, "T '([a-z0-9_.]+)'") | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($code, "Start-Task '([a-z0-9_.]+)'") | ForEach-Object { $_.Groups[1].Value })
    $miss = @($keys | Sort-Object -Unique | Where-Object { -not $en.ContainsKey($_) })
    if ($miss) { "FAIL:" + ($miss -join ', ') } else { "$(@($keys | Sort-Object -Unique).Count) keys" }
}
Invoke-Check 'static' 'Window layout: XAML is valid, every element and colour the code uses exists' {
    [xml]$x = $xamlText
    $names = @([regex]::Matches($xamlText, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $keys = @([regex]::Matches($xamlText, 'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $used = @([regex]::Matches($guiText, '\$UI\.([A-Z][A-Za-z0-9]+)') | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
    $missN = @($used | Where-Object { $names -notcontains $_ })
    $res = @([regex]::Matches($guiText, "FindResource\('([^']+)'\)") | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($guiText, "'(\w+Brush)'") | ForEach-Object { $_.Groups[1].Value })
    $missR = @($res | Sort-Object -Unique | Where-Object { $keys -notcontains $_ })
    if ($missN -or $missR) { "FAIL:elements: $($missN -join ', ') resources: $($missR -join ', ')" } else { "$($names.Count) elements" }
}
Invoke-Check 'static' 'No known-dangerous code patterns' {
    $bad = @()
    if ($guiText -match 'New-Object (System\.)?Windows\.') { $bad += 'New-Object for WPF types (gives PSObject-wrapped values WPF cannot read)' }
    if ($guiText -match '\$Win\.Resources\[[^\]]+\]\s*=') { $bad += 'indexer assignment into window resources (use Set-WinResource)' }
    if ($guiText -match '@\(\$TK\.Result\)') { $bad += '@($TK.Result) (use ConvertTo-CleanList: @($null) has one item)' }
    if (($guiText + $coreText) -match '\[System\.Windows\.MessageBox\]::Show' -and ([regex]::Matches(($guiText + $coreText), '\[System\.Windows\.MessageBox\]::Show').Count -gt 3)) { $bad += 'MessageBox outside Confirm-Box/Show-Info' }
    if ($bad) { "FAIL:" + ($bad -join '; ') }
}
Invoke-Check 'static' 'No function name hides a built-in alias (like "H" = Get-History)' {
    $aliases = @((Get-Alias).Name) + @('h', 'r', 'ls', 'cat', 'cp', 'mv', 'rm', 'ps', 'kill', 'sort', 'curl', 'wget', 'diff', 'sleep', 'tee', 'write', 'man', 'md', 'rd', 'cd', 'dir', 'echo', 'type', 'del', 'copy', 'move', 'ren', 'set', 'clear', 'cls', 'history', 'sc', 'gc', 'select', 'where', 'foreach', 'group', 'measure', 'compare')
    $fns = foreach ($f in $psFiles) { $a = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null); $a.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } }
    $hits = @($fns | Sort-Object -Unique | Where-Object { $aliases -contains $_.ToLower() -or $aliases -contains $_ })
    if ($hits) { "FAIL:" + ($hits -join ', ') } else { "$(@($fns | Sort-Object -Unique).Count) functions" }
}
Invoke-Check 'static' 'Version is the same everywhere (config, Core, exe, CHANGELOG)' {
    $cfg = (Read-Utf8 (Join-Path $Root 'app/config.json') | ConvertFrom-Json).version
    $core = [regex]::Match($coreText, "\`$AppVersion = '([^']+)'").Groups[1].Value
    $cs = [regex]::Match((Read-Utf8 (Join-Path $Root 'build/JohnsToolkit.cs')), 'AssemblyVersion\("([\d.]+)"\)').Groups[1].Value
    $log = (Read-Utf8 (Join-Path $Root 'CHANGELOG.md')) -match "(?m)^## v$([regex]::Escape($cfg))\s*$"
    if ($cfg -ne $core -or -not $cs.StartsWith($cfg) -or -not $log) { "FAIL:config=$cfg core=$core exe=$cs changelog-entry=$log" } else { "v$cfg" }
}

Invoke-Check 'static' 'PSScriptAnalyzer: no findings (rules in PSScriptAnalyzerSettings.psd1)' {
    if (-not (Get-Module PSScriptAnalyzer)) {
        try { Import-Module PSScriptAnalyzer -ErrorAction Stop } catch { if ($env:JT_PSSA) { Import-Module $env:JT_PSSA -ErrorAction SilentlyContinue } }
    }
    if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) { return 'SKIP:PSScriptAnalyzer is not installed' }
    $settings = Join-Path $Root 'PSScriptAnalyzerSettings.psd1'
    $r = @(foreach ($p in 'app', 'classic', 'tests', 'build') { Invoke-ScriptAnalyzer -Path (Join-Path $Root $p) -Recurse -Settings $settings })
    if ($r.Count) { 'FAIL:' + ((@($r | Select-Object -First 5) | ForEach-Object { "$($_.ScriptName):$($_.Line) $($_.RuleName)" }) -join '; ') + " ($($r.Count) total)" } else { '0 findings' }
} -OnlyExceptions

# ================================================================ 2. LOAD THE PROGRAM
Write-Host "`n2) Loading the program" -ForegroundColor Cyan
$RealWpf = $false
if ($OnWindows) { try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction Stop; $RealWpf = $true } catch {} }
if (-not $RealWpf) { Add-Type -TypeDefinition (Read-Utf8 (Join-Path $PSScriptRoot 'FakeWpf.cs')) }
$AppRoot = $Root; $ToolDir = Join-Path $Root 'classic'
$guiNoStart = $guiText
. ([scriptblock]::Create($classicEngine + "`r`n" + $coreText + "`r`n" + $guiNoStart))
Add-Result 'load' "Engine + window code loaded ($($guiFiles.Count) window files)" 'pass'

Invoke-Check 'logic' 'Change history: add, newest first, undo (in a temporary folder)' {
    $keep = $CoreData; $script:CoreData = Join-Path ([IO.Path]::GetTempPath()) ('jt-test-' + [guid]::NewGuid().ToString('N'))
    try {
        function Set-Tweak($t, $on) { $script:UndoCalls += "$($t.Id)=$on" }   # stand-in, only inside this check
        $script:UndoCalls = @()
        $a = Add-History 'cleanup' 'hist.cleanup' @('1 GB')
        $b = Add-History 'tweak' 'hist.tweak.on' @('X') @{ Type = 'tweaks'; Items = @(@{ Id = $Tweaks[0].Id; Was = $false }) }
        $list = @(Get-ChangeHistory)
        if ($list.Count -ne 2 -or $list[0].Id -ne $b.Id) { return "FAIL:expected 2 entries, newest first (got $($list.Count))" }
        $r = Invoke-HistoryUndoCore $b.Id
        if (-not $r.Ok -or $script:UndoCalls -notcontains "$($Tweaks[0].Id)=False") { return "FAIL:undo did not restore the setting ($($script:UndoCalls -join ','))" }
        $after = @(Get-ChangeHistory)
        if (-not ($after | Where-Object { $_.Id -eq $b.Id }).Undone -or $after[0].Kind -ne 'undo') { return 'FAIL:entry not marked undone / no undo entry' }
        if ((Invoke-HistoryUndoCore $a.Id).Ok) { return 'FAIL:an entry without undo data was "undone"' }
        "$($after.Count) entries, undo works"
    } finally { Remove-Item -LiteralPath $CoreData -Recurse -Force -ErrorAction SilentlyContinue; $script:CoreData = $keep }
} -OnlyExceptions
Invoke-Check 'logic' 'Update: picks the right download and refuses to update a git checkout' {
    $assets = @([pscustomobject]@{ Name = 'JohnsToolkit-v9.9.9.zip' }, [pscustomobject]@{ Name = 'JohnsToolkit-v9.9.9-with-exe.zip' }, [pscustomobject]@{ Name = 'SHA256SUMS.txt' })
    $a = Select-UpdateAsset $assets
    $exeHere = Test-Path -LiteralPath (Join-Path $AppRoot 'JohnsToolkit.exe')
    if ($exeHere -and $a.Name -notlike '*-with-exe.zip') { return "FAIL:with JohnsToolkit.exe present it chose $($a.Name)" }
    if (-not $exeHere -and $a.Name -like '*-with-exe.zip') { return "FAIL:without JohnsToolkit.exe it chose $($a.Name)" }
    if (Test-GitCheckout) { $r = Install-AppUpdate ([pscustomobject]@{ Latest = '9.9.9'; Assets = $assets }); if ($r.Ok -or $r.Why -ne 'git') { return 'FAIL:a git checkout would have been overwritten' }; return "chose $($a.Name); git checkout protected" }
    "chose $($a.Name)"
} -OnlyExceptions

# ---------------------------------------------------------------- safe stand-ins
$script:Calls = [System.Collections.ArrayList]::new(); $script:Tasks = [System.Collections.ArrayList]::new()
function Rec([string]$w) { [void]$script:Calls.Add($w) }
function Start-Task([string]$titleKey, [string]$workText, [hashtable]$taskArgs = @{}, [scriptblock]$onDone = $null, [switch]$Silent) { [void]$script:Tasks.Add(@{ Key = $titleKey; Work = $workText; Args = $taskArgs; OnDone = $onDone }) }
function Confirm-Box([string]$m) { Rec "confirm"; return $true }
function Show-Info([string]$m) { Rec "info: $m" }
function Start-Process { Rec "Start-Process $args" }
function Stop-Process { Rec "Stop-Process $args" }
function Restart-Computer { Rec 'Restart-Computer' }
function Set-Tweak($t, $on) { Rec "Set-Tweak $($t.Id)" }
function Restore-AllTweaks { 0 }
function Set-StartupEnabled($e, $on) { Rec 'startup' }
function Set-PowerPlanCore($w) { $true }
function Save-TrustedList($l) { }
function Save-AppSettings($s) { }
function Set-AutoClean($on) { }
function New-AppShortcut { '' }
function Test-NewVersion { $null }
function Send-Toast { }
function Select-Folder { $null }
function New-BatteryReport { $null }
function Export-NetReportCore($d) { '' }
function Start-Classic { }
function Set-CleanPath($s, $i) { '' }
function Restore-PathBackup($f) { 'User' }
function Set-DnsPreset($p) { 1 }
function Set-WuHidden($i, $h) { $true }
function Write-AppLog { }
function Add-History { }
function Save-ChangeHistory { }
$script:FixHistory = @()
function Get-ChangeHistory { $script:FixHistory }
function Start-AppUpdater { }
function Write-GuiStage { }

if (-not $OnWindows) {
    foreach ($c in 'powercfg', 'Get-CimInstance', 'Get-NetAdapter', 'Get-NetTCPConnection', 'Get-NetUDPEndpoint', 'Get-NetIPAddress', 'Get-DnsClientServerAddress', 'Get-VpnConnection', 'Get-MpComputerStatus', 'Get-PhysicalDisk', 'Get-StorageReliabilityCounter', 'Get-NetFirewallProfile', 'Get-SmbServerConfiguration', 'Confirm-SecureBootUEFI', 'Get-HotFix', 'Get-WinEvent', 'Get-AppxPackage', 'Get-ScheduledTask', 'Get-Tpm') {
        Set-Item -Path "Function:\$c" -Value { }
    }
}

# ---------------------------------------------------------------- UI helpers (real WPF or stand-in)
function Get-Kids($e) {
    if ($RealWpf) { if ($e -is [System.Windows.DependencyObject]) { return @([System.Windows.LogicalTreeHelper]::GetChildren($e) | Where-Object { $_ -is [System.Windows.DependencyObject] }) }; return @() }
    $k = @(); if ($e -is [Windows.Controls.FE]) { $k += @($e.Children) + @($e.Items); if ($e.Child) { $k += $e.Child }; if ($e.Content -is [Windows.Controls.FE]) { $k += $e.Content } }
    return @($k | Where-Object { $_ })
}
function Get-All($root) {
    $out = [System.Collections.ArrayList]::new(); $st = [System.Collections.Stack]::new(); $st.Push($root)
    while ($st.Count) { $e = $st.Pop(); [void]$out.Add($e); foreach ($c in Get-Kids $e) { $st.Push($c) } }
    return $out
}
function Get-Texts($root) {
    foreach ($e in Get-All $root) {
        if ("$($e.GetType().Name)" -match 'TextBlock' -and $e.Text) { "$($e.Text)" }
        elseif ($e.Content -is [string]) { "$($e.Content)" }
        if ($e.ToolTip -is [string]) { "$($e.ToolTip)" }
    }
}
function Invoke-Ui($e) {
    if ($RealWpf) {
        if ($e -is [System.Windows.Controls.RadioButton]) { $e.IsChecked = $false; $e.IsChecked = $true; return 1 }
        if ($e -is [System.Windows.Controls.Primitives.ButtonBase]) {
            if ($e -is [System.Windows.Controls.CheckBox]) { $e.IsChecked = -not [bool]$e.IsChecked }
            $e.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)); return 1
        }
        if ($e -is [System.Windows.Controls.Border] -and $e.Cursor -eq [System.Windows.Input.Cursors]::Hand) {
            $a = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $a.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent; $e.RaiseEvent($a); return 1
        }
        return 0
    }
    $n = 0
    foreach ($ev in 'Click', 'Checked', 'MouseLeftButtonUp') { if ($e.HasHandler($ev)) { if ($e -is [Windows.Controls.CheckBox]) { $e.IsChecked = -not [bool]$e.IsChecked }; $e.Raise($ev); $n++ } }
    return $n
}
function Save-Screenshot([string]$path) {
    if (-not $RealWpf) { return }
    $w = 1280; $h = 860; $root = $Win.Content
    $root.Measure([System.Windows.Size]::new($w, $h)); $root.Arrange([System.Windows.Rect]::new(0, 0, $w, $h)); $root.UpdateLayout()
    $bmp = [System.Windows.Media.Imaging.RenderTargetBitmap]::new($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bg = [System.Windows.Media.DrawingVisual]::new(); $dc = $bg.RenderOpen(); $dc.DrawRectangle($Win.Resources['BgBrush'], $null, [System.Windows.Rect]::new(0, 0, $w, $h)); $dc.Close()
    $bmp.Render($bg); $bmp.Render($root)
    $enc = [System.Windows.Media.Imaging.PngBitmapEncoder]::new(); $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    $fs = [IO.File]::Create($path); try { $enc.Save($fs) } finally { $fs.Close() }
}

# ================================================================ 3. READ-ONLY SYSTEM CALLS (Windows only)
Write-Host "`n3) Read-only system information (real calls)" -ForegroundColor Cyan
$probes = [ordered]@{
    'Windows version' = { $o = Get-OSInfo; if (-not $o.Name) { 'FAIL:no name' } else { "$($o.Name) $($o.Version) build $($o.Build)" } }
    'Dashboard' = { $d = Get-Dashboard; if ($d.DiskPct -lt 0 -or $d.DiskPct -gt 100) { "FAIL:disk $($d.DiskPct)" } else { "disk $([int]$d.DiskPct)% ram $([int]$d.RamPct)%" } }
    'PC specs' = { $s = Get-PcSpecs; if ($s.Count -lt 3) { "FAIL:only $($s.Count) rows" } else { "$($s.Count) rows" } }
    'Fixed drives' = { $d = @(Get-FixedDrives); if ($d.Count -lt 1) { 'FAIL:none' } else { ($d | ForEach-Object { $_.Letter }) -join ' ' } }
    'VPN detection' = { "$(@(Get-VpnStatus).Count) found" }
    'PATH report' = { $r = Get-PathReport; if (@($r.Machine).Count -lt 1) { 'FAIL:empty system PATH' } else { "$(@($r.Machine).Count) system + $(@($r.User).Count) user entries" } }
    'DNS status' = { "$(@(Get-DnsStatus).Count) adapters" }
    'Port finder (135, always used by Windows)' = { $p = @(Find-PortUsers 135); if ($p.Count -lt 1) { 'FAIL:nothing on port 135' } else { ($p | ForEach-Object { $_.Name }) -join ', ' } }
    'Installed programs' = { "$(@(Get-InstalledPrograms).Count) programs" }
    'Startup entries' = { "$(@(Get-StartupEntries).Count) entries" }
    'Crash history (7 days)' = { $c = Get-CrashHistory 7; if ($null -eq $c.Days) { 'FAIL:no result' } else { "$(@($c.Bsod).Count) bsod, $(@($c.Apps).Count) apps" } }
    'Devices & drivers' = { $d = Get-DeviceReport; if ($null -eq $d) { 'FAIL:no result' } else { "$(@($d.Problems).Count) problems, $(@($d.Gpu).Count) gpu" } }
    'Security status' = { $s = Get-SecurityStatus; if ($s.Count -lt 3) { "FAIL:only $($s.Count)" } else { "$($s.Count) checks" } }
    'Health status' = { $h = Get-HealthStatus; if ($h.Count -lt 1) { 'FAIL:no rows' } else { "$($h.Count) rows" } }
    'Boot times' = { "$(@(Get-BootTimes).Count) records" }
    'Windows settings state' = { $n = 0; foreach ($t in $Tweaks) { $null = Get-TweakState $t; $n++ }; "$n settings read" }
    'WSL/Docker disks' = { "$(@(Get-WslDisks).Count) found" }
    'Leftover scan (read-only)' = { "$(@(Find-Leftovers).Count) found" }
}
foreach ($k in $probes.Keys) {
    if (-not $OnWindows) { Add-Result 'system' $k 'skip' 'needs Windows'; continue }
    Invoke-Check 'system' $k $probes[$k] -OnlyExceptions
}

# ================================================================ 4. THE WINDOW
Write-Host "`n4) The window: start-up, every page, every language, every button" -ForegroundColor Cyan
$App.Settings.flicker = $true
if ($RealWpf) {
    Invoke-Check 'ui' 'Window is created and every page is built' { if (-not (New-MainWindow $xamlText)) { 'FAIL:New-MainWindow returned false' } else { "$($UI.Count) named elements" } }
} else {
    $script:Win = [pscustomobject]@{ Title = ''; Resources = [hashtable]@{} }; $Win | Add-Member ScriptMethod FindResource { param($k) "style:$k" }
    $script:UI = @{}; foreach ($m in [regex]::Matches($xamlText, 'x:Name="([^"]+)"')) { $UI[$m.Groups[1].Value] = [Windows.Controls.StackPanel]::new() }
    $App.Pal = $Themes['dark']
    Invoke-Check 'ui' 'Every page is built (stand-in window)' { Set-AllTexts }
}
Invoke-Check 'ui' 'No background task starts before the window is shown' {
    $t = @($script:Tasks | ForEach-Object { $_.Key }); if ($t.Count) { "FAIL:started at start-up: $($t -join ', ')" }
}

# Sample data so every page has content to show and click
function Set-Fixtures {
    $App.Specs = @(@{ K = 'spec.cpu'; V = 'Test CPU' }, @{ K = 'spec.ram'; V = '32 GB' })
    $App.Leftovers = [System.Collections.ArrayList]@([pscustomobject]@{ Cat = 'startup'; Label = 'Old updater'; Missing = 'C:\Gone\upd.exe' }); $App.LeftSel = @{ 0 = $true }
    $App.Big = @{ Root = 'C:\'; Files = @([pscustomobject]@{ Path = 'C:\nonexistent\a.iso'; Name = 'a.iso'; Dir = 'C:\nonexistent'; Size = 2GB; Date = (Get-Date) }, [pscustomobject]@{ Path = 'C:\nonexistent\Docker\wsl\disk\docker_data.vhdx'; Name = 'docker_data.vhdx'; Dir = 'x'; Size = 40GB; Date = (Get-Date) }) }
    $App.Dupes = @{ Total = 1; Wasted = 3MB; Root = 'C:\'; Groups = @([pscustomobject]@{ Size = 3MB; Count = 2; Wasted = 3MB; Files = @([pscustomobject]@{ Path = 'C:\nonexistent\a.jpg'; Date = (Get-Date) }, [pscustomobject]@{ Path = 'C:\nonexistent\b.jpg'; Date = (Get-Date) }) }) }; $App.DupSel = @{ 'C:\nonexistent\b.jpg' = $true }
    $App.Updates = @([pscustomobject]@{ Name = 'Mullvad VPN'; Id = 'MullvadVPN.MullvadVPN'; Version = '1'; Available = '2'; Level = 2; K = 'upd.r.vpn'; A = @() }, [pscustomobject]@{ Name = 'Tool'; Id = 'T.T'; Version = '1'; Available = '3'; Level = 1; K = 'upd.r.major'; A = @('1', '3') }); $App.Pins = @([pscustomobject]@{ Name = 'Pinned'; Id = 'P.P' }); $App.UpdSel = @{ 'T.T' = $true }
    $App.Bloat = @([pscustomobject]@{ Pkg = 'Microsoft.BingNews'; Name = 'Microsoft News'; Note = '' }); $App.BloatSel = @{}
    $App.Programs = @([pscustomobject]@{ Name = 'Test App'; Publisher = 'Test'; Version = '1.0'; Date = (Get-Date); Size = 10MB; Uninstall = 'x'; Location = ''; Key = 'k' })
    $App.UnLeft = @{ Name = 'Test App'; Items = @([pscustomobject]@{ Type = 'dir'; Path = 'C:\nonexistent\TestApp'; Size = 1MB; Sure = $true }) }; $App.UnLeftSel = @{}
    $App.Net = @{ Status = [pscustomobject]@{ Ip = '1.2.3.4'; Country = 'Sweden' }; VpnNames = @('Mullvad'); Total = 2; ThreatCount = 5; Listen = @([pscustomobject]@{ Name = 'svchost'; Ports = '135' }); Report = @([pscustomobject]@{ Level = 2; Name = 'testapp'; PID = 999999; Count = 2; SigKey = 'net.sig.none'; Publisher = ''; Path = 'C:\nonexistent\t.exe'; Trusted = $false; Flags = @(@{ K = 'net.f.port'; A = @(4444) }); Dest = ''; Conns = @([pscustomobject]@{ Ip = '6.6.6.6'; Port = 4444; Via = 'out'; Org = ''; Bad = $true }) }) }; $App.NetOpen = 999999
    $App.Security = @('sec.fw.on', 'sec.ext.hidden', 'sec.upd.old', 'sec.rdp.on', 'hl.battery', 'hl.uptime.long' | ForEach-Object { [pscustomobject]@{ K = $_; S = 'warn'; A = @(1, 2, 3); G = $(if ($_ -like 'hl.*') { 'health' } else { 'sec' }) } })
    $App.Crash = @{ Days = 30; Bsod = @([pscustomobject]@{ When = (Get-Date); Code = '0x00000133'; Kind = 'dpc' }); Power = @((Get-Date)); Apps = @([pscustomobject]@{ Name = 'Discord.exe'; Crashes = 3; Hangs = 1; Last = (Get-Date); Module = 'amdxx64.dll'; Hint = 'gpu' }); Dumps = 1 }
    $App.Devices = @{ Problems = @([pscustomobject]@{ Name = 'USB device'; Code = 43 }); Gpu = @([pscustomobject]@{ Name = 'AMD Radeon RX 7700 XT'; Version = '32.0'; Date = (Get-Date).AddDays(-400); Vendor = 'AMD' }); Old = @(); Unsigned = @() }
    $App.Wu = @{ Pending = @([pscustomobject]@{ Title = 'Feature update'; KB = 'KB1'; Id = 'a'; Size = 3GB; Cat = 'Upgrades'; Downloaded = $false }); Hidden = @(); History = @([pscustomobject]@{ Title = 'Windows 11 26H2'; Date = (Get-Date); Result = 4; HResult = '0x80070490' }) }
    $App.PortNum = 135; $App.PortRes = @([pscustomobject]@{ PID = 999999; Name = 'svchost'; Path = ''; Services = @('RpcSs'); States = 'TCP Listen'; Lines = @() })
    $App.DnsTimes = [ordered]@{ cloudflare = 11; quad9 = -1 }; $App.DnsPick = 'quad9'; $App.Speed = $null
    $script:FixHistory = @([pscustomobject]@{ Id = 'a1'; When = (Get-Date).ToString('s'); Kind = 'tweak'; Key = 'hist.tweak.on'; A = @('Show file extensions'); Undo = [pscustomobject]@{ Type = 'tweaks'; Items = @() }; Undone = $false },
        [pscustomobject]@{ Id = 'a2'; When = (Get-Date).AddDays(-1).ToString('s'); Kind = 'recycle'; Key = 'hist.dupes'; A = @('3'); Undo = [pscustomobject]@{ Type = 'recyclebin' }; Undone = $false },
        [pscustomobject]@{ Id = 'a3'; When = (Get-Date).AddDays(-2).ToString('s'); Kind = 'cleanup'; Key = 'hist.cleanup'; A = @('2 GB'); Undo = $null; Undone = $false })
}
# Every page and sub-tab, with the function that builds it
$Views = [ordered]@{
    'Home' = { Show-Page 'Home' }; 'Cleanup-temp' = { $App.CleanTab = 'temp'; Show-Page 'Clean'; Build-CleanTabs }; 'Cleanup-leftovers' = { $App.CleanTab = 'left'; Show-Page 'Clean'; Build-CleanTabs }
    'Cleanup-large' = { $App.CleanTab = 'big'; Show-Page 'Clean'; Build-CleanTabs }; 'Cleanup-duplicates' = { $App.CleanTab = 'dupes'; Show-Page 'Clean'; Build-CleanTabs }
    'WindowsSettings' = { Show-Page 'Tweaks' }; 'Apps-startup' = { $App.AppsTab = 'startup'; Show-Page 'Apps'; Build-AppsPage }; 'Apps-updates' = { $App.AppsTab = 'updates'; Show-Page 'Apps'; Build-AppsPage }
    'Apps-uninstall' = { $App.AppsTab = 'uninstall'; Show-Page 'Apps'; Build-AppsPage }; 'Apps-remove' = { $App.AppsTab = 'bloat'; Show-Page 'Apps'; Build-AppsPage }
    'Network' = { Show-Page 'Net'; Build-NetPage }; 'Security' = { Show-Page 'Security'; Build-SecurityPage }
    'Diagnostics-crashes' = { $App.DiagTab = 'crash'; Show-Page 'Diag'; Build-DiagPage }; 'Diagnostics-devices' = { $App.DiagTab = 'devices'; Show-Page 'Diag'; Build-DiagPage }; 'Diagnostics-update' = { $App.DiagTab = 'wu'; Show-Page 'Diag'; Build-DiagPage }
    'Developer-path' = { $App.DevTab = 'path'; Show-Page 'Dev'; Build-DevPage }; 'Developer-ports' = { $App.DevTab = 'ports'; Show-Page 'Dev'; Build-DevPage }; 'Developer-dns' = { $App.DevTab = 'dns'; Show-Page 'Dev'; Build-DevPage }
    'Repair' = { Show-Page 'Repair' }; 'History' = { Show-Page 'History' }; 'Settings' = { Show-Page 'Settings' }
}
$PageRoot = @{ 'Home' = 'PageHome'; 'Cleanup' = 'PageClean'; 'WindowsSettings' = 'PageTweaks'; 'Apps' = 'PageApps'; 'Network' = 'PageNet'; 'Security' = 'PageSecurity'; 'Diagnostics' = 'PageDiag'; 'Developer' = 'PageDev'; 'Repair' = 'PageRepair'; 'History' = 'PageHistory'; 'Settings' = 'PageSettings' }
function Get-ViewRoot([string]$v) {
    if ($RealWpf) { return $UI[$PageRoot[($v -split '-')[0]]] }
    $r = [Windows.Controls.StackPanel]::new(); $r.Items.Loose = $true; foreach ($x in $UI.Values) { [void]$r.Items.Add($x) }; return $r   # stand-in: elements are not nested
}

# 4a) every page in every language: builds, and no untranslated key is shown
foreach ($jtTestLang in 'en', 'el', 'de', 'it', 'fr', 'es') {
    Set-AppLanguage $jtTestLang; Set-Fixtures; Set-AllTexts
    Invoke-Check 'ui' "Every page in '$jtTestLang' builds and shows no raw text keys" {
        $raw = @()
        foreach ($v in $Views.Keys) {
            Set-Fixtures; & $Views[$v]
            $raw += @(Get-Texts (Get-ViewRoot $v) | Where-Object { $_ -cmatch '^[a-z]{2,}(\.[a-z0-9_]+){1,3}$' } | ForEach-Object { "$v`: $_" })
        }
        if ($raw) { "FAIL:" + (($raw | Select-Object -Unique -First 6) -join '; ') } else { "$($Views.Count) views" }
    }
}
Set-AppLanguage 'en'; Set-AllTexts

# 4a+) Search (Ctrl+K)
Invoke-Check 'search' 'Search: every entry, accents ignored, English works in Greek, numbers find ports' {
    Set-AppLanguage 'el'; Set-AllTexts
    $all = @(Get-PaletteEntries ''); if ($all.Count -lt 60) { return "FAIL:only $($all.Count) entries" }
    $find = { param($q) $UI.PaletteBox.Text = $q; $App.PalSel = 0; Update-PaletteResults; @($App.PalItems) }
    $r1 = & $find 'θυρες'; if (-not ($r1 | Where-Object { $_.Label -like '*Θύρες*' })) { return "FAIL:'θυρες' (no accent) did not find the Ports tab" }
    $r2 = & $find 'ports'; if (-not ($r2 | Where-Object { $_.Label -like '*Θύρες*' })) { return "FAIL:'ports' (English) did not find the Ports tab in Greek" }
    $r3 = & $find '5432'; if ($r3.Count -lt 1 -or $r3[0].Label -notlike '*5432*') { return "FAIL:'5432' did not offer the port lookup first" }
    $r4 = & $find 'synthwave'; if (-not ($r4 | Where-Object { $_.Label -like '*Synthwave*' })) { return "FAIL:'synthwave' did not find the theme" }
    $r5 = & $find 'zzzqqq'; if ($r5.Count -ne 0) { return 'FAIL:nonsense found something' }
    Set-AppLanguage 'en'; Set-AllTexts
    "$($all.Count) entries"
} -OnlyExceptions
Invoke-Check 'search' 'Search: every result runs without errors' {
    $UI.PaletteBox.Text = ''; $all = @(Get-PaletteEntries '5432'); $bad = @()
    foreach ($e in $all) {
        Set-Fixtures; $Error.Clear(); $script:Tasks.Clear()
        try { & $e.Run } catch { $bad += "$($e.Label): $($_.Exception.Message)" }
        foreach ($x in @($Error | Where-Object { "$($_.FullyQualifiedErrorId) $($_.Exception.GetType().Name)" -notmatch $IgnoredErrors })) { $bad += "$($e.Label): line $($x.InvocationInfo.ScriptLineNumber) $($x.Exception.Message)" }
    }
    Set-AppLanguage 'en'; $App.Settings.lang = 'en'; Set-AllTexts; Set-Fixtures
    if ($bad) { 'FAIL:' + (($bad | Select-Object -First 4) -join ' | ') } else { "$($all.Count) results run" }
} -OnlyExceptions

# 4b) every button, switch and tab on every page (with the safe stand-ins)
foreach ($v in $Views.Keys) {
    Invoke-Check 'click' "Click everything: $v" {
        Set-Fixtures; & $Views[$v]
        $els = @(Get-All (Get-ViewRoot $v)); $n = 0; $problems = @()
        foreach ($e in $els) {
            $Error.Clear(); $script:Tasks.Clear()
            try { $n += Invoke-Ui $e } catch { $problems += "$($e.GetType().Name) '$($e.Tag)': $($_.Exception.InnerException.Message)$($_.Exception.Message)" }
            foreach ($x in @($Error | Where-Object { "$($_.FullyQualifiedErrorId) $($_.Exception.GetType().Name)" -notmatch $IgnoredErrors -and "$($_.Exception.Message)" -notmatch 'nonexistent|Could not find' })) { $problems += "line $($x.InvocationInfo.ScriptLineNumber): $($x.Exception.Message)" }
            foreach ($t in @($script:Tasks)) {
                if ($t.OnDone) { $Error.Clear(); try { & $t.OnDone @{ Result = $null; Args = $t.Args; Error = $null } } catch { $problems += "after '$($t.Key)' with no result: $($_.Exception.Message)" } }
            }
        }
        $Error.Clear()
        if ($problems) { "FAIL:" + (($problems | Select-Object -Unique -First 4) -join ' | ') } else { "$n controls" }
    } -OnlyExceptions
}

# 4c) screenshots (real WPF only): every view in the dark theme, Home in every theme
if ($RealWpf) {
    Write-Host "`n5) Screenshots" -ForegroundColor Cyan
    $shots = Join-Path $OutDir 'screens'
    # the click test pressed the language and theme buttons too: start from English and the default theme
    Set-AppLanguage 'en'; $App.Settings.lang = 'en'; Set-AllTexts
    $App.NeedsRestart = $false; $UI.RestartBanner.Visibility = 'Collapsed'   # set by the click test, not by the app
    Set-Theme 'dark'
    foreach ($v in $Views.Keys) {
        Invoke-Check 'screens' "Screenshot: dark / $v" { Set-Fixtures; & $Views[$v]; Set-SignStatic; Save-Screenshot (Join-Path $shots "dark\$v.png") } -OnlyExceptions
    }
    Invoke-Check 'screens' 'Neon sign is not clipped (every letter fits its cell, the sign fits its space)' {
        Show-Page 'Home'; Set-SignStatic
        $root = $Win.Content; $root.Measure([System.Windows.Size]::new(1280, 860)); $root.Arrange([System.Windows.Rect]::new(0, 0, 1280, 860)); $root.UpdateLayout()
        $bad = @()
        foreach ($cell in @($App.SignLetters)) {
            if ($cell -is [System.Windows.Controls.Grid]) {
                foreach ($pth in @($cell.Children)) { $b = $pth.Data.Bounds; if ($b.Bottom -gt $cell.Height -or $b.Right -gt $cell.Width) { $bad += ('letter {0:0}x{1:0} in cell {2:0}x{3:0}' -f $b.Right, $b.Bottom, $cell.Width, $cell.Height) } }
            }
        }
        $s = $UI.NeonSign
        if ($s.ActualHeight + 0.5 -lt $s.DesiredSize.Height -or $s.ActualWidth + 0.5 -lt $s.DesiredSize.Width) { $bad += ('sign {0:0}x{1:0} needs {2:0}x{3:0}' -f $s.ActualWidth, $s.ActualHeight, $s.DesiredSize.Width, $s.DesiredSize.Height) }
        if ($bad) { 'FAIL:' + (($bad | Select-Object -First 4) -join '; ') } else { ('sign {0:0}x{1:0}, {2} letters' -f $s.ActualWidth, $s.ActualHeight, @($App.SignLetters).Count) }
    } -OnlyExceptions
    foreach ($th in @($Themes.Keys)) {
        Invoke-Check 'screens' "Screenshot: $th / Home + Network" {
            Set-Theme $th; Set-Fixtures
            Show-Page 'Home'; Set-SignStatic; Save-Screenshot (Join-Path $shots "themes\$th-Home.png")
            Show-Page 'Net'; Build-NetPage; Save-Screenshot (Join-Path $shots "themes\$th-Network.png")
        } -OnlyExceptions
    }
    Set-Theme 'dark'
} else { Add-Result 'screens' 'Screenshots' 'skip' 'need real WPF (Windows)' }

# ================================================================ SUMMARY
$pass = @($Results | Where-Object State -eq 'pass').Count; $fail = @($Results | Where-Object State -eq 'fail').Count; $skip = @($Results | Where-Object State -eq 'skip').Count
$md = @("# John's Toolkit - test results", '', "**$pass passed, $fail failed, $skip skipped** - $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $(if ($RealWpf) { 'Windows, real WPF' } else { 'stand-in WPF' })", '', '| Result | Group | Check | Detail |', '|---|---|---|---|')
foreach ($r in $Results) { $md += "| $(@{ pass = '✅'; fail = '❌'; skip = '⏭' }[$r.State]) | $($r.Group) | $($r.Name) | $(("$($r.Detail)" -replace '\|', '/' -replace '\r?\n', ' '))  |" }
[IO.File]::WriteAllLines((Join-Path $OutDir 'results.md'), $md, (New-Object System.Text.UTF8Encoding $false))
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md -Encoding utf8 }
Write-Host ("`n{0} passed, {1} failed, {2} skipped" -f $pass, $fail, $skip) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
