# ======================================================================
#  John's Toolkit by nmx88 - Core (logic without UI)
#  Windows 10/11 - https://github.com/nmx88/johns-toolkit
# ======================================================================
$AppVersion = '2.1.1'
$AppName    = "John's Toolkit"
$AppAuthor  = 'nmx88'
if (-not $AppRoot) { $AppRoot = Split-Path -Parent $PSScriptRoot }
$CoreData = Join-Path $AppRoot 'data'
$CoreLogs = Join-Path $AppRoot 'logs'
$Languages = [ordered]@{ el = 'Ελληνικά'; en = 'English'; de = 'Deutsch'; it = 'Italiano'; fr = 'Français'; es = 'Español' }

# ---------- Γλώσσες ----------
function Read-LangFile([string]$code) {
    $h = @{}
    $f = Join-Path $AppRoot "lang\$code.json"
    if (-not (Test-Path -LiteralPath $f)) { return $h }
    try {
        $obj = ConvertFrom-Json ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8))
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }
    } catch {}
    return $h
}
function Set-AppLanguage([string]$code) {
    if (-not $Languages.Contains($code)) { $code = 'en' }
    $script:LangCode = $code
    $script:LangFallback = Read-LangFile 'en'
    $script:Lang = Read-LangFile $code
}
function T([string]$k) {
    $s = $null
    if ($script:Lang -and $script:Lang.ContainsKey($k)) { $s = $script:Lang[$k] }
    elseif ($script:LangFallback -and $script:LangFallback.ContainsKey($k)) { $s = $script:LangFallback[$k] }
    else { $s = $k }
    if ($args.Count -gt 0) { try { $s = $s -f $args } catch {} }
    return $s
}
function Get-DefaultLanguage {
    $c = ''
    try { $c = (Get-UICulture).TwoLetterISOLanguageName } catch {}
    if ($Languages.Contains($c)) { return $c }
    return 'en'
}

# ---------- Ρυθμίσεις εφαρμογής ----------
function Get-AppSettings {
    $s = @{ lang = (Get-DefaultLanguage); theme = 'dark'; ageDays = 2; totalFreed = 0.0; lastClean = '' }
    $f = Join-Path $CoreData 'settings.json'
    if (Test-Path -LiteralPath $f) {
        try {
            $o = ConvertFrom-Json ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8))
            foreach ($p in $o.PSObject.Properties) { $s[$p.Name] = $p.Value }
        } catch {}
    }
    return $s
}
function Save-AppSettings($s) {
    New-Item -ItemType Directory -Path $CoreData -Force | Out-Null
    $o = New-Object PSObject
    foreach ($k in $s.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $s[$k] }
    [IO.File]::WriteAllText((Join-Path $CoreData 'settings.json'), (ConvertTo-Json $o), (New-Object System.Text.UTF8Encoding $false))
}
function Write-AppLog([string]$t) {
    try {
        New-Item -ItemType Directory -Path $CoreLogs -Force | Out-Null
        Add-Content -Path (Join-Path $CoreLogs 'history.log') -Value "$(Get-Date -Format 'dd/MM/yyyy HH:mm')  $t" -Encoding UTF8
    } catch {}
}

# ---------- Πρόοδος προς το παράθυρο (μέσω του κοινόχρηστου $TK) ----------
function Set-TK([double]$pct = -1, $label = $null, $detail = $null) {
    if (-not $TK) { return }
    $TK.Pct = $pct
    if ($null -ne $label) { $TK.Label = [string]$label }
    if ($null -ne $detail) { $TK.Detail = [string]$detail }
}
function Add-TKLog([string]$t, [string]$lvl = 'info') { if ($TK) { $TK.Log.Enqueue(@($lvl, $t)) } }

# ---------- Πληροφορίες συστήματος ----------
function Get-OSInfo {
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $p = Get-ItemProperty -Path $cv -ErrorAction SilentlyContinue
    $build = 0; [void][int]::TryParse("$($p.CurrentBuildNumber)", [ref]$build)
    $name = "$($p.ProductName)"
    if ($build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
    [pscustomobject]@{ Name = $name; Version = "$($p.DisplayVersion)"; Build = $build; IsWin11 = ($build -ge 22000); Supported = ($build -ge 10240) }
}
function Get-Dashboard {
    $d = @{}
    $c = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($c) { $tot = [double]$c.Free + [double]$c.Used; if ($tot -gt 0) { $d.DiskPct = [double]$c.Used / $tot * 100; $d.DiskFree = [double]$c.Free; $d.DiskTotal = $tot } }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $t = [double]$os.TotalVisibleMemorySize * 1KB; $f = [double]$os.FreePhysicalMemory * 1KB
        if ($t -gt 0) { $d.RamPct = ($t - $f) / $t * 100; $d.RamUsed = $t - $f; $d.RamTotal = $t }
        $d.Uptime = (Get-Date) - $os.LastBootUpTime
    }
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu) { $d.CpuPct = [double]$cpu.LoadPercentage; $d.CpuName = "$($cpu.Name)".Trim() }
    $d.Vpns = @(Get-VpnStatus)
    $d.Reboot = ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                 (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
    return $d
}

# ======================================================================
#  ΚΑΘΑΡΙΣΜΟΣ (μόνο αρχεία που δεν χρησιμοποιούνται)
# ======================================================================
function Get-CleanCategories {
    $la = $env:LOCALAPPDATA; $w = $env:WINDIR; $pd = $env:ProgramData
    @(
        @{ Id = 'usertemp';  Def = $true;  Age = $true;  Paths = @($env:TEMP) }
        @{ Id = 'wintemp';   Def = $true;  Age = $true;  Paths = @("$w\Temp") }
        @{ Id = 'wucache';   Def = $true;  Age = $false; Paths = @("$w\SoftwareDistribution\Download"); Services = @('wuauserv', 'bits') }
        @{ Id = 'doptim';    Def = $true;  Age = $false; Paths = @("$w\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"); Special = 'doptim' }
        @{ Id = 'wer';       Def = $true;  Age = $true;  Paths = @("$pd\Microsoft\Windows\WER\ReportArchive", "$pd\Microsoft\Windows\WER\ReportQueue", "$la\Microsoft\Windows\WER\ReportArchive", "$la\Microsoft\Windows\WER\ReportQueue") }
        @{ Id = 'inetcache'; Def = $true;  Age = $true;  Paths = @("$la\Microsoft\Windows\INetCache") }
        @{ Id = 'dumps';     Def = $true;  Age = $false; Paths = @("$w\Minidump", "$la\CrashDumps"); Files = @("$w\MEMORY.DMP") }
        @{ Id = 'logs';      Def = $true;  Age = $true;  MinAge = 14; Paths = @("$w\Logs\CBS", "$w\Logs\DISM"); Ext = @('.log', '.cab') }
        @{ Id = 'browsers';  Def = $false; Age = $false; Special = 'browsers' }
        @{ Id = 'shader';    Def = $false; Age = $false; Paths = @("$la\NVIDIA\DXCache", "$la\NVIDIA\GLCache", "$la\AMD\DxCache", "$la\AMD\GLCache", "$la\D3DSCache") }
        @{ Id = 'recycle';   Def = $false; Special = 'recycle' }
        @{ Id = 'winold';    Def = $false; Special = 'winold'; Paths = @("$env:SystemDrive\Windows.old") }
        @{ Id = 'component'; Def = $false; Special = 'component' }
        @{ Id = 'dns';       Def = $true;  Special = 'dns' }
    )
}

function Get-BrowserCacheDirs {
    $la = $env:LOCALAPPDATA; $out = @()
    $chromium = @(
        @{ P = 'chrome'; N = 'Chrome'; D = "$la\Google\Chrome\User Data" }
        @{ P = 'msedge'; N = 'Edge'; D = "$la\Microsoft\Edge\User Data" }
        @{ P = 'brave'; N = 'Brave'; D = "$la\BraveSoftware\Brave-Browser\User Data" }
        @{ P = 'vivaldi'; N = 'Vivaldi'; D = "$la\Vivaldi\User Data" }
    )
    foreach ($b in $chromium) {
        if (-not (Test-Path -LiteralPath $b.D)) { continue }
        foreach ($prof in @(Get-ChildItem -LiteralPath $b.D -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
            foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) {
                $p = Join-Path $prof.FullName $c
                if (Test-Path -LiteralPath $p) { $out += @{ Proc = $b.P; Name = $b.N; Dir = $p } }
            }
        }
    }
    $ff = "$la\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $ff) {
        foreach ($prof in @(Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue)) {
            $p = Join-Path $prof.FullName 'cache2'
            if (Test-Path -LiteralPath $p) { $out += @{ Proc = 'firefox'; Name = 'Firefox'; Dir = $p } }
        }
    }
    return $out
}

function Get-EligibleFiles($cat, [int]$days) {
    $minAge = 0; if ($cat.MinAge) { $minAge = [int]$cat.MinAge }
    $useAge = [bool]$cat.Age
    $cut = (Get-Date).AddDays(-[Math]::Max($days, $minAge))
    $ext = @($cat.Ext | Where-Object { $_ })
    foreach ($p in @($cat.Paths)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
            ((-not $useAge) -or ($_.LastWriteTime -lt $cut -and $_.CreationTime -lt $cut)) -and
            (($ext.Count -eq 0) -or ($ext -contains $_.Extension.ToLower()))
        }
    }
    foreach ($f in @($cat.Files)) { if ($f -and (Test-Path -LiteralPath $f)) { Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
}

function Get-RecycleBytes {
    $s = 0.0
    try { $sh = New-Object -ComObject Shell.Application; foreach ($i in @($sh.Namespace(10).Items())) { $s += [double]$i.Size } } catch {}
    return $s
}
function Get-FolderBytes([string]$p) {
    $s = 0.0
    if ($p -and (Test-Path -LiteralPath $p)) { foreach ($f in @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)) { $s += $f.Length } }
    return $s
}

# Μέγεθος κάθε κατηγορίας (χωρίς να σβήσει τίποτα)
function Measure-CleanCategories([string[]]$ids, [int]$days) {
    $res = @{}
    $cats = @(Get-CleanCategories | Where-Object { $ids -contains $_.Id })
    $i = 0
    foreach ($c in $cats) {
        Set-TK (100.0 * $i / [Math]::Max(1, $cats.Count)) (T 'clean.scanning') (T "cat.$($c.Id).t")
        $bytes = 0.0; $count = 0
        switch ($c.Special) {
            'dns' { }
            'component' { }
            'recycle' { $bytes = Get-RecycleBytes }
            'doptim' { $bytes = Get-FolderBytes $c.Paths[0] }
            'winold' { $bytes = Get-FolderBytes $c.Paths[0] }
            'browsers' {
                foreach ($b in @(Get-BrowserCacheDirs)) { foreach ($f in @(Get-ChildItem -LiteralPath $b.Dir -Recurse -File -Force -ErrorAction SilentlyContinue)) { $bytes += $f.Length; $count++ } }
            }
            default { foreach ($f in @(Get-EligibleFiles $c $days)) { $bytes += $f.Length; $count++ } }
        }
        $res[$c.Id] = @{ Bytes = $bytes; Files = $count }
        $i++
    }
    Set-TK 100 (T 'clean.scanned') ''
    return $res
}

function Remove-FileList($files, [double]$base, [double]$span) {
    $files = @($files); $total = $files.Count; $done = 0; $freed = 0.0
    for ($i = 0; $i -lt $total; $i++) {
        $f = $files[$i]; $len = 0
        try { $len = $f.Length; [IO.File]::Delete($f.FullName); $done++; $freed += $len }
        catch { try { $f.Attributes = 'Normal'; [IO.File]::Delete($f.FullName); $done++; $freed += $len } catch {} }
        if ($i % 25 -eq 0) { Set-TK ($base + $span * ($i + 1) / [Math]::Max(1, $total)) $null ((T 'clean.progress') -f ($i + 1), $total, (Format-Size $freed)) }
    }
    return @{ Freed = $freed; Deleted = $done; Skipped = ($total - $done) }
}
function Remove-EmptyDirs($paths) {
    foreach ($p in @($paths)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $p -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
            try { [IO.Directory]::Delete($d.FullName, $false) } catch {}
        }
    }
}

function Invoke-CleanCategory($c, [int]$days, [double]$base, [double]$span) {
    $r = @{ Freed = 0.0; Deleted = 0; Skipped = 0; Status = 'ok'; Note = '' }
    $label = T "cat.$($c.Id).t"
    Set-TK $base $label ''
    if ($c.Special -eq 'dns') { ipconfig /flushdns | Out-Null; return $r }
    if ($c.Special -eq 'recycle') { $r.Freed = Get-RecycleBytes; Clear-RecycleBin -Force -ErrorAction SilentlyContinue; return $r }
    if ($c.Special -eq 'doptim') {
        $b = Get-FolderBytes $c.Paths[0]
        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue }
        $r.Freed = [Math]::Max(0, $b - (Get-FolderBytes $c.Paths[0])); return $r
    }
    if ($c.Special -eq 'component') {
        $before = [double](Get-PSDrive C).Free
        $x = Invoke-Native "$env:WINDIR\System32\Dism.exe" '/Online /Cleanup-Image /StartComponentCleanup' $label
        $r.Freed = [Math]::Max(0, [double](Get-PSDrive C).Free - $before)
        if (-not (Test-ExitOk $x.Code)) { $r.Status = 'warn'; $r.Note = Get-CodeText $x.Code }
        return $r
    }
    if ($c.Special -eq 'winold') {
        $p = $c.Paths[0]
        if (-not (Test-Path -LiteralPath $p)) { return $r }
        $b = Get-FolderBytes $p
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Previous Installations'
        if (Test-Path $k) {
            New-ItemProperty -Path $k -Name 'StateFlags0099' -PropertyType DWord -Value 2 -Force | Out-Null
            $null = Invoke-Native "$env:WINDIR\System32\cleanmgr.exe" '/sagerun:99' $label
            Remove-ItemProperty -Path $k -Name 'StateFlags0099' -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $p) { $r.Status = 'warn'; $r.Note = T 'clean.note.winold' }
        $r.Freed = [Math]::Max(0, $b - (Get-FolderBytes $p))
        return $r
    }
    if ($c.Special -eq 'browsers') {
        $skipped = @(); $files = @()
        foreach ($b in @(Get-BrowserCacheDirs)) {
            if (Get-Process -Name $b.Proc -ErrorAction SilentlyContinue) { if ($skipped -notcontains $b.Name) { $skipped += $b.Name }; continue }
            $files += @(Get-ChildItem -LiteralPath $b.Dir -Recurse -File -Force -ErrorAction SilentlyContinue)
        }
        $x = Remove-FileList $files $base $span
        $r.Freed = $x.Freed; $r.Deleted = $x.Deleted; $r.Skipped = $x.Skipped
        if ($skipped.Count -gt 0) { $r.Status = 'warn'; $r.Note = (T 'clean.note.browseropen') -f ($skipped -join ', ') }
        return $r
    }
    foreach ($s in @($c.Services)) { if ($s) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } }
    $files = @(Get-EligibleFiles $c $days)
    $x = Remove-FileList $files $base $span
    if (-not $c.Ext) { Remove-EmptyDirs $c.Paths }
    foreach ($s in @($c.Services)) { if ($s) { Start-Service -Name $s -ErrorAction SilentlyContinue } }
    $r.Freed = $x.Freed; $r.Deleted = $x.Deleted; $r.Skipped = $x.Skipped
    if ($x.Skipped -gt 0) { $r.Note = (T 'clean.note.inuse') -f $x.Skipped }
    return $r
}

function Invoke-Clean([string[]]$ids, [int]$days) {
    $cats = @(Get-CleanCategories | Where-Object { $ids -contains $_.Id })
    $results = [ordered]@{}; $t0 = Get-Date
    for ($i = 0; $i -lt $cats.Count; $i++) {
        $c = $cats[$i]
        $span = 100.0 / [Math]::Max(1, $cats.Count)
        $ts = Get-Date
        $r = Invoke-CleanCategory $c $days ($i * $span) $span
        $r.Seconds = ((Get-Date) - $ts).TotalSeconds
        $results[$c.Id] = $r
        $line = '{0}: {1}' -f (T "cat.$($c.Id).t"), (Format-Size $r.Freed)
        if ($r.Note) { $line += ' · ' + $r.Note }
        $lvl = 'ok'; if ($r.Status -ne 'ok') { $lvl = 'warn' }
        Add-TKLog $line $lvl
    }
    $total = 0.0; foreach ($k in $results.Keys) { $total += $results[$k].Freed }
    Set-TK 100 (T 'clean.done') (Format-Size $total)
    Write-AppLog ("Clean: " + (Format-Size $total))
    return @{ Results = $results; Total = $total; Seconds = ((Get-Date) - $t0).TotalSeconds }
}

# ======================================================================
#  ΕΠΙΔΙΟΡΘΩΣΕΙΣ
# ======================================================================
function Get-CodeText([int]$code) {
    $hex = '0x' + $code.ToString('X8')
    $k = "code.$hex"
    $txt = T $k
    if ($txt -eq $k) { return ((T 'code.generic') -f $hex) }
    return "$txt ($hex)"
}

function Repair-WindowsUpdate {
    $svcs = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $sd = "$env:WINDIR\SoftwareDistribution"; $cr = "$env:WINDIR\System32\catroot2"
    Set-TK 5 (T 'wu.stop') ''
    foreach ($s in $svcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Set-TK 30 (T 'wu.old') ''
    $olds = @(Get-ChildItem -Path $env:WINDIR -Directory -Filter 'SoftwareDistribution.bak-*' -ErrorAction SilentlyContinue) +
            @(Get-ChildItem -Path "$env:WINDIR\System32" -Directory -Filter 'catroot2.bak-*' -ErrorAction SilentlyContinue)
    foreach ($old in $olds) { if ($old -and $old.CreationTime -lt (Get-Date).AddDays(-14)) { Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue } }
    Set-TK 50 (T 'wu.rename') ''
    $ok = $true
    foreach ($p in @($sd, $cr)) {
        if (Test-Path -LiteralPath $p) {
            try { Rename-Item -LiteralPath $p -NewName ((Split-Path $p -Leaf) + ".bak-$stamp") -ErrorAction Stop; Add-TKLog ((T 'wu.renamed') -f $p) 'ok' }
            catch { $ok = $false; Add-TKLog ((T 'wu.renamefail') -f $p) 'warn' }
        }
    }
    Set-TK 80 (T 'wu.start') ''
    foreach ($s in $svcs) { Start-Service -Name $s -ErrorAction SilentlyContinue }
    Set-TK 100 (T 'wu.done') ''
    Write-AppLog "Windows Update repair (ok=$ok)"
    return @{ Ok = $ok }
}

function Invoke-SystemRepair {
    Set-TK -1 (T 'rep.dism') ''
    $a = Invoke-Native "$env:WINDIR\System32\Dism.exe" '/Online /Cleanup-Image /RestoreHealth' (T 'rep.dism')
    if (Test-ExitOk $a.Code) { Add-TKLog (T 'rep.dism.ok') 'ok' } else { Add-TKLog ((T 'rep.dism') + ': ' + (Get-CodeText $a.Code)) 'warn' }
    Set-TK -1 (T 'rep.sfc') ''
    $b = Invoke-Native "$env:WINDIR\System32\sfc.exe" '/scannow' (T 'rep.sfc')
    $tail = @($b.Output -split "`r?`n" | ForEach-Object { ($_ -split "`r")[-1].Trim() } | Where-Object { $_ -and $_ -notmatch '%' } | Select-Object -Last 2)
    foreach ($l in $tail) { Add-TKLog $l 'info' }
    Write-AppLog "System repair: dism=$($a.Code) sfc=$($b.Code)"
    return @{ Dism = $a.Code; Sfc = $b.Code }
}

function New-RestorePointCore {
    Set-TK -1 (T 'rp.creating') ''
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    Checkpoint-Computer -Description "John's Toolkit $(Get-Date -Format 'dd-MM-yyyy HH.mm')" -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    $ok = ($after -gt $before)
    if ($ok) { Add-TKLog (T 'rp.ok') 'ok' } else { Add-TKLog (T 'rp.exists') 'warn' }
    Write-AppLog "Restore point: $ok"
    return @{ Ok = $ok }
}

# ======================================================================
#  ΑΥΤΟΜΑΤΙΣΜΟΙ & ΕΡΓΑΛΕΙΑ
# ======================================================================
$AutoTaskName = 'PCTools-WeeklyCleanup'
$AutoCategories = @('usertemp', 'wintemp', 'wucache', 'wer', 'inetcache', 'dns')

function Test-AutoClean { return [bool](Get-ScheduledTask -TaskName $AutoTaskName -ErrorAction SilentlyContinue) }
function Set-AutoCleanTask([bool]$on) {
    if (-not $on) { Unregister-ScheduledTask -TaskName $AutoTaskName -Confirm:$false -ErrorAction SilentlyContinue; return $true }
    $launcher = Join-Path $AppRoot 'app\Launcher.ps1'
    try {
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Auto"
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '20:00'
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $AutoTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}
function Invoke-AutoCleanCore {
    $s = Get-AppSettings
    Set-AppLanguage $s.lang
    $r = Invoke-Clean $AutoCategories ([int]$s.ageDays)
    $s.totalFreed = [double]$s.totalFreed + $r.Total; $s.lastClean = (Get-Date).ToString('s')
    Save-AppSettings $s
    New-Item -ItemType Directory -Path $CoreLogs -Force | Out-Null
    Add-Content -Path (Join-Path $CoreLogs 'auto-cleanup.log') -Encoding UTF8 -Value "$(Get-Date -Format 'dd/MM/yyyy HH:mm')  $(Format-Size $r.Total)"
    if ($r.Total -gt 50MB) { Send-Toast $AppName ((T 'auto.toast') -f (Format-Size $r.Total)) }
}

function New-AppShortcut {
    $desk = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desk "John's Toolkit.lnk"
    $exe = Join-Path $AppRoot 'JohnsToolkit.exe'
    $bat = Join-Path $AppRoot 'Start-JohnsToolkit.bat'
    try {
        $ws = New-Object -ComObject WScript.Shell
        $s = $ws.CreateShortcut($lnk)
        if (Test-Path -LiteralPath $exe) { $s.TargetPath = $exe } else { $s.TargetPath = $bat }
        $s.WorkingDirectory = $AppRoot
        $ico = Join-Path $AppRoot 'assets\icon.ico'
        if (Test-Path -LiteralPath $ico) { $s.IconLocation = $ico }
        $s.Description = "John's Toolkit by nmx88"
        $s.Save()
        return $true
    } catch { return $false }
}

function Get-RepoSlug {
    $f = Join-Path $AppRoot 'app\config.json'
    try { return (ConvertFrom-Json ([IO.File]::ReadAllText($f))).repo } catch { return 'nmx88/johns-toolkit' }
}
function Test-NewVersion {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$(Get-RepoSlug)/releases/latest" -Headers @{ 'User-Agent' = 'JohnsToolkit' } -TimeoutSec 15 -ErrorAction Stop
        $latest = "$($r.tag_name)".TrimStart('v', 'V')
        $newer = $false
        try { $newer = ([version]$latest -gt [version]$AppVersion) } catch {}
        return @{ Ok = $true; Latest = $latest; Newer = $newer; Url = "$($r.html_url)" }
    } catch { return @{ Ok = $false } }
}

# ======================================================================
#  ΑΡΙΘΜΟΙ ΣΤΗ ΓΛΩΣΣΑ ΤΗΣ ΕΦΑΡΜΟΓΗΣ (141.63 GB στα αγγλικά, 141,63 GB στα ελληνικά)
# ======================================================================
$LangCultures = @{ el = 'el-GR'; en = 'en-US'; de = 'de-DE'; it = 'it-IT'; fr = 'fr-FR'; es = 'es-ES' }
function Get-LangCulture {
    try { return [Globalization.CultureInfo]::GetCultureInfo($LangCultures["$script:LangCode"]) } catch { return [Globalization.CultureInfo]::InvariantCulture }
}
function Format-Size([double]$b) {
    $ci = Get-LangCulture
    if ($b -ge 1TB) { return ($b / 1TB).ToString('N2', $ci) + ' TB' }
    if ($b -ge 1GB) { return ($b / 1GB).ToString('N2', $ci) + ' GB' }
    if ($b -ge 1MB) { return ($b / 1MB).ToString('N1', $ci) + ' MB' }
    return ($b / 1KB).ToString('N0', $ci) + ' KB'
}

# ======================================================================
#  ΑΝΙΧΝΕΥΣΗ VPN (όχι μόνο Mullvad)
# ======================================================================
$VpnPatterns = @(
    @{ N = 'Mullvad';                 P = 'Mullvad';                                  Kind = 'vpn' }
    @{ N = 'NordVPN';                 P = 'NordLynx|NordVPN';                         Kind = 'vpn' }
    @{ N = 'Proton VPN';              P = 'ProtonVPN|Proton VPN';                     Kind = 'vpn' }
    @{ N = 'ExpressVPN';              P = 'ExpressVPN|Lightway';                      Kind = 'vpn' }
    @{ N = 'Surfshark';               P = 'Surfshark';                                Kind = 'vpn' }
    @{ N = 'Private Internet Access'; P = 'Private Internet Access';                  Kind = 'vpn' }
    @{ N = 'CyberGhost';              P = 'CyberGhost';                               Kind = 'vpn' }
    @{ N = 'IPVanish';                P = 'IPVanish';                                 Kind = 'vpn' }
    @{ N = 'Windscribe';              P = 'Windscribe';                               Kind = 'vpn' }
    @{ N = 'TunnelBear';              P = 'TunnelBear';                               Kind = 'vpn' }
    @{ N = 'Cloudflare WARP';         P = 'Cloudflare';                               Kind = 'vpn' }
    @{ N = 'Cisco Secure Client';     P = 'Cisco AnyConnect|Cisco Secure Client';     Kind = 'vpn' }
    @{ N = 'FortiClient';             P = 'Fortinet|FortiClient';                     Kind = 'vpn' }
    @{ N = 'GlobalProtect';           P = 'PANGP|GlobalProtect';                      Kind = 'vpn' }
    @{ N = 'OpenVPN';                 P = 'OpenVPN|TAP-Windows|ovpn-dco';             Kind = 'vpn' }
    @{ N = 'WireGuard';               P = 'WireGuard';                                Kind = 'vpn' }
    @{ N = 'Tailscale';               P = 'Tailscale';                                Kind = 'mesh' }
    @{ N = 'ZeroTier';                P = 'ZeroTier';                                 Kind = 'mesh' }
    @{ N = 'Hamachi';                 P = 'Hamachi';                                  Kind = 'mesh' }
    @{ N = 'VPN (Wintun)';            P = 'Wintun';                                   Kind = 'vpn' }
)
function Get-VpnStatus {
    $found = [ordered]@{}
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Up' })) {
        $txt = "$($a.Name) $($a.InterfaceDescription)"
        foreach ($p in $VpnPatterns) {
            if ($txt -match $p.P) { if (-not $found.Contains($p.N)) { $found[$p.N] = @{ Name = $p.N; Kind = $p.Kind } }; break }
        }
    }
    # VPN που έχουν οριστεί στις Ρυθμίσεις των Windows (IKEv2, L2TP, SSTP...)
    foreach ($c in @(@(Get-VpnConnection -ErrorAction SilentlyContinue) + @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue))) {
        if ($c -and "$($c.ConnectionStatus)" -eq 'Connected' -and -not $found.Contains("$($c.Name)")) { $found["$($c.Name)"] = @{ Name = "$($c.Name)"; Kind = 'vpn' } }
    }
    return @($found.Values)
}
# Οι IP των ενεργών VPN (για το διαγνωστικό δικτύου)
function Get-VpnIps {
    $vpnRegex = (($VpnPatterns | Where-Object { $_.Kind -eq 'vpn' } | ForEach-Object { $_.P }) -join '|')
    $ad = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Up' -and "$($_.Name) $($_.InterfaceDescription)" -match $vpnRegex })
    if ($ad.Count -eq 0) { return @() }
    return @(Get-NetIPAddress -InterfaceIndex $ad.ifIndex -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress)
}

# ======================================================================
#  ΤΕΧΝΙΚΑ ΧΑΡΑΚΤΗΡΙΣΤΙΚΑ PC
# ======================================================================
function Get-GpuVram([string]$name) {
    $base = 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in @(Get-ChildItem -Path $base -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if ($p -and "$($p.DriverDesc)" -eq $name) {
            $q = $p.'HardwareInformation.qwMemorySize'
            if ($q) { return [double]$q }
            $m = $p.'HardwareInformation.MemorySize'
            if ($m -is [byte[]]) { return [double][BitConverter]::ToUInt32($m, 0) }
            if ($m) { return [double]$m }
        }
    }
    return 0
}
function Get-DisplayModes {
    # Ανάλυση και Hz από κάθε οθόνη (όχι από την κάρτα γραφικών, που μπορεί να είναι λάθος με 2 κάρτες)
    $out = @()
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if (-not ('JTDisplay' -as [type])) {
            Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class JTDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields;
    public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
    public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency;
    public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
  public static int[] Mode(string dev) {
    DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (EnumDisplaySettings(dev, -1, ref d)) return new int[] { d.dmPelsWidth, d.dmPelsHeight, d.dmDisplayFrequency };
    return null;
  }
}
'@
        }
        foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
            $m = [JTDisplay]::Mode($s.DeviceName)
            if ($m -and $m[0] -gt 0) {
                $t = '{0} × {1} @ {2} Hz' -f $m[0], $m[1], $m[2]
                if ($s.Primary -and @([System.Windows.Forms.Screen]::AllScreens).Count -gt 1) { $t += ' (' + (T 'spec.primary') + ')' }
                $out += $t
            }
        }
    } catch {}
    return $out
}

function Get-PcSpecs {
    $L = [System.Collections.ArrayList]::new()
    $ci = Get-LangCulture
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cpus = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $osi = Get-OSInfo
    $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR

    $pcName = "$env:COMPUTERNAME"; if (-not $pcName) { $pcName = [Environment]::MachineName }
    [void]$L.Add(@{ K = 'spec.pc'; V = $pcName })
    if ($cs) { [void]$L.Add(@{ K = 'spec.model'; V = ("$($cs.Manufacturer) $($cs.Model)").Trim() }) }
    $osv = "$($osi.Name) $($osi.Version)".Trim()
    if ($osi.Build) { $osv += " (build $($osi.Build)"; if ($ubr) { $osv += ".$ubr" }; $osv += ')' }
    if ($os.OSArchitecture) { $osv += " · $($os.OSArchitecture)" }
    [void]$L.Add(@{ K = 'spec.os'; V = $osv })
    if ($os.InstallDate) { [void]$L.Add(@{ K = 'spec.installed'; V = ([datetime]$os.InstallDate).ToString('d', $ci) }) }

    foreach ($c in $cpus) {
        $v = "$($c.Name)".Trim()
        if ($c.NumberOfCores) { $v += ' · ' + ((T 'spec.cores') -f $c.NumberOfCores, $c.NumberOfLogicalProcessors) }
        if ($c.MaxClockSpeed) { $v += ' · ' + ([double]$c.MaxClockSpeed / 1000).ToString('N2', $ci) + ' GHz' }
        [void]$L.Add(@{ K = 'spec.cpu'; V = $v })
    }

    $total = 0.0; foreach ($m in $mem) { $total += [double]$m.Capacity }
    if ($total -le 0 -and $cs) { $total = [double]$cs.TotalPhysicalMemory }
    if ($total -gt 0) {
        $v = "$([math]::Round($total / 1GB)) GB"
        $types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
        $t = $null; foreach ($m in $mem) { $x = [int]$m.SMBIOSMemoryType; if ($types.ContainsKey($x)) { $t = $types[$x] } }
        if ($t) { $v += " · $t" }
        if ($mem.Count -gt 0) {
            $sizes = @($mem | ForEach-Object { [math]::Round([double]$_.Capacity / 1GB) } | Select-Object -Unique)
            if ($sizes.Count -eq 1) { $v += " · $($mem.Count) × $($sizes[0]) GB" } else { $v += ' · ' + ((T 'spec.modules') -f $mem.Count) }
            $speed = ($mem | ForEach-Object { [int]$(if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed }) } | Measure-Object -Maximum).Maximum
            if ($speed) { $v += " · $speed MT/s" }
        }
        [void]$L.Add(@{ K = 'spec.ram'; V = $v })
    }

    $disp = @(Get-DisplayModes)
    $fromScreens = ($disp.Count -gt 0)
    foreach ($g in $gpus) {
        if (-not $g.Name) { continue }
        $v = "$($g.Name)".Trim()
        $integrated = ("$($g.Name)" -match 'UHD Graphics|Iris|Intel\(R\) HD Graphics|Intel\(R\) Graphics|Radeon\(TM\) Graphics|Radeon Graphics$|Vega \d+ Graphics|Arc\(TM\) Graphics')
        if ($integrated) { $v += ' · ' + (T 'spec.igpu') }
        else {
            $vram = Get-GpuVram "$($g.Name)"
            # Το AdapterRAM σταματά στα 4 GB: αν φτάνει στο όριο, δεν το εμπιστευόμαστε
            if ($vram -le 0 -and $g.AdapterRAM -and [double]$g.AdapterRAM -lt 4290000000) { $vram = [double]$g.AdapterRAM }
            if ($vram -ge 256MB) { $v += ' · ' + [math]::Round($vram / 1GB, 1).ToString($ci) + ' GB' }
        }
        if ($g.DriverVersion) { $v += ' · ' + ((T 'spec.driver') -f $g.DriverVersion) }
        [void]$L.Add(@{ K = 'spec.gpu'; V = $v })
        if (-not $fromScreens -and $g.CurrentHorizontalResolution) { $disp += ('{0} × {1} @ {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate) }
    }
    if ($disp.Count -gt 0) { [void]$L.Add(@{ K = 'spec.display'; V = ($disp -join "`n") }) }

    $dl = @()
    foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)) {
        $x = "$($d.FriendlyName)".Trim()
        $extra = @("$($d.MediaType)", "$($d.BusType)") | Where-Object { $_ -and $_ -ne 'Unspecified' }
        if ($extra) { $x += ' · ' + ($extra -join ' · ') }
        if ($d.Size) { $x += ' · ' + (Format-Size $d.Size) }
        $dl += $x
    }
    if ($dl.Count -gt 0) { [void]$L.Add(@{ K = 'spec.disks'; V = ($dl -join "`n") }) }

    if ($bb) { [void]$L.Add(@{ K = 'spec.board'; V = ("$($bb.Manufacturer) $($bb.Product)").Trim() }) }
    if ($bios) {
        $v = ("$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)").Trim()
        if ($bios.ReleaseDate) { $v += ' (' + ([datetime]$bios.ReleaseDate).ToString('d', $ci) + ')' }
        [void]$L.Add(@{ K = 'spec.bios'; V = $v })
    }

    $nl = @()
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Up' })) { $nl += "$($a.InterfaceDescription) · $($a.LinkSpeed)" }
    if ($nl.Count -gt 0) { [void]$L.Add(@{ K = 'spec.net'; V = ($nl -join "`n") }) }

    $sec = @()
    try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { $sec += 'Secure Boot: ' + (T 'spec.on') } else { $sec += 'Secure Boot: ' + (T 'spec.off') } } catch {}
    $tpm = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    if ($tpm -and $tpm.SpecVersion) { $sec += 'TPM ' + ("$($tpm.SpecVersion)" -split ',')[0].Trim() }
    if ($sec.Count -gt 0) { [void]$L.Add(@{ K = 'spec.security'; V = ($sec -join ' · ') }) }
    return , $L
}
