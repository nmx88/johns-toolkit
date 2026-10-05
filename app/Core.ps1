# ======================================================================
#  John's Toolkit by nmx88 - Core (logic without UI)
#  Windows 10/11 - https://github.com/nmx88/johns-toolkit
# ======================================================================
$AppVersion = '2.5.2'
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

# ======================================================================
#  ΦΑΣΗ 2α: ΕΝΗΜΕΡΩΣΕΙΣ (winget), ΑΦΑΙΡΕΣΗ ΕΦΑΡΜΟΓΩΝ, ΑΣΦΑΛΕΙΑ, ΣΧΕΔΙΟ ΕΝΕΡΓΕΙΑΣ
# ======================================================================
$UpdateRiskTable = @(
    @{ P = 'Mullvad|NordVPN|ProtonVPN|ExpressVPN|Surfshark|Windscribe|CyberGhost|IPVanish|TunnelBear'; K = 'upd.r.vpn' }
    @{ P = 'qBittorrent|uTorrent|BitTorrent|Transmission|Deluge'; K = 'upd.r.torrent' }
    @{ P = '^Docker\.'; K = 'upd.r.docker' }
    @{ P = '^Oracle\.VirtualBox'; K = 'upd.r.vbox' }
    @{ P = '^Tailscale\.'; K = 'upd.r.tailscale' }
    @{ P = '^PostgreSQL\.'; K = 'upd.r.postgres' }
    @{ P = '^Microsoft\.VisualStudio'; K = 'upd.r.vs' }
    @{ P = '^Adobe\.'; K = 'upd.r.adobe' }
    @{ P = '^EpicGames\.EpicGamesLauncher|^Valve\.Steam|^Discord\.'; K = 'upd.r.self' }
    @{ P = '^Microsoft\.WindowsInstallationAssistant|^Microsoft\.WindowsPCHealthCheck'; K = 'upd.r.skip' }
)
function Get-UpdateRiskCore($u) {
    foreach ($r in $UpdateRiskTable) { if ("$($u.Id)" -match $r.P -or "$($u.Name)" -match $r.P) { return @{ Level = 2; K = $r.K; A = @() } } }
    $a = 0; $b = 0
    if ("$($u.Version)" -match '^(\d+)') { $a = [int64]$matches[1] }
    if ("$($u.Available)" -match '^(\d+)') { $b = [int64]$matches[1] }
    if ($a -gt 0 -and $b -gt $a) { return @{ Level = 1; K = 'upd.r.major'; A = @("$($u.Version)", "$($u.Available)") } }
    return @{ Level = 0; K = 'upd.r.safe'; A = @() }
}
function Get-UpdateInfo {
    $wg = Get-WingetPath
    if (-not $wg) { return @{ NoWinget = $true; Updates = @(); Pins = @() } }
    Set-TK -1 (T 'upd.scanning') ''
    $r = Invoke-Native $wg 'upgrade --accept-source-agreements' '' ([Text.Encoding]::UTF8)
    $list = @()
    foreach ($c in @(ConvertFrom-WingetTable $r.Output)) {
        if ($c.Count -ge 4 -and $c[1] -and $c[1] -notmatch '\s') {
            $u = [pscustomobject]@{ Name = $c[0]; Id = $c[1]; Version = $c[2]; Available = $c[3]; Level = 0; K = ''; A = @() }
            $k = Get-UpdateRiskCore $u; $u.Level = $k.Level; $u.K = $k.K; $u.A = $k.A
            $list += $u
        }
    }
    $p = Invoke-Native $wg 'pin list --accept-source-agreements' '' ([Text.Encoding]::UTF8)
    $pins = @()
    foreach ($c in @(ConvertFrom-WingetTable $p.Output)) { if ($c.Count -ge 2 -and $c[1]) { $pins += [pscustomobject]@{ Name = $c[0]; Id = $c[1] } } }
    return @{ NoWinget = $false; Updates = @($list | Sort-Object Level, Name); Pins = $pins }
}
function Update-AppsCore($items) {
    $wg = Get-WingetPath
    $items = @($items); $ok = 0; $fail = @()
    New-Item -ItemType Directory -Path $CoreLogs -Force | Out-Null
    $log = Join-Path $CoreLogs ('winget-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    for ($i = 0; $i -lt $items.Count; $i++) {
        $u = $items[$i]
        Set-TK -1 ((T 'upd.installing') -f ($i + 1), $items.Count, $u.Name) "$($u.Version) → $($u.Available)"
        $r = Invoke-Native $wg "upgrade $(Get-WingetIdArg $u.Id) --silent --accept-package-agreements --accept-source-agreements" '' ([Text.Encoding]::UTF8)
        Add-Content -Path $log -Encoding UTF8 -Value @("===== $($u.Name) ($($u.Id)) -> $($r.Code) =====", $r.Output)
        if (Test-ExitOk $r.Code) { $ok++; Add-TKLog ((T 'upd.ok1') -f $u.Name) 'ok' }
        else { $why = Get-CodeText $r.Code; $fail += [pscustomobject]@{ Name = $u.Name; Why = $why }; Add-TKLog ((T 'upd.fail') -f $u.Name, $why) 'warn' }
        Write-AppLog "Update $($u.Name): $($r.Code)"
    }
    Set-TK 100 ((T 'upd.result') -f $ok, $fail.Count) ''
    return @{ Ok = $ok; Fail = $fail; Log = $log }
}
function Set-PinCore([string]$id, [bool]$pin) {
    $wg = Get-WingetPath
    if (-not $wg) { return -1 }
    if ($pin) { $r = Invoke-Native $wg "pin add $(Get-WingetIdArg $id) --accept-source-agreements" '' ([Text.Encoding]::UTF8) }
    else { $r = Invoke-Native $wg "pin remove $(Get-WingetIdArg $id)" '' ([Text.Encoding]::UTF8) }
    Write-AppLog "Pin $id -> $pin ($($r.Code))"
    return $r.Code
}

# Προεγκατεστημένες εφαρμογές (ονόματα προϊόντων, ίδια σε όλες τις γλώσσες)
$BloatApps = [ordered]@{
    'Microsoft.BingNews' = 'Microsoft News'; 'Microsoft.BingWeather' = 'MSN Weather'; 'Microsoft.BingSearch' = 'Bing Search'
    'Microsoft.GetHelp' = 'Get Help'; 'Microsoft.Getstarted' = 'Tips'; 'Microsoft.MicrosoftSolitaireCollection' = 'Solitaire Collection'
    'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365 (Office) hub'; 'Microsoft.People' = 'People'; 'Microsoft.WindowsFeedbackHub' = 'Feedback Hub'
    'Microsoft.WindowsMaps' = 'Maps'; 'Microsoft.ZuneVideo' = 'Movies & TV'; 'Microsoft.SkypeApp' = 'Skype'; 'Microsoft.Todos' = 'Microsoft To Do'
    'Microsoft.PowerAutomateDesktop' = 'Power Automate'; 'Microsoft.549981C3F5F10' = 'Cortana'; 'Clipchamp.Clipchamp' = 'Clipchamp'
    'MicrosoftTeams' = 'Teams (personal)'; 'MSTeams' = 'Teams'; 'Microsoft.OutlookForWindows' = 'Outlook (new)'; 'Microsoft.Copilot' = 'Copilot'
    'Microsoft.YourPhone' = 'Phone Link'; 'Microsoft.GamingApp' = 'Xbox'; 'Microsoft.XboxGamingOverlay' = 'Xbox Game Bar'
}
$BloatNotes = @{ 'Microsoft.GamingApp' = 'bl.n.xbox'; 'Microsoft.XboxGamingOverlay' = 'bl.n.gamebar'; 'Microsoft.YourPhone' = 'bl.n.phone' }
function Get-BloatInstalled {
    Set-TK -1 (T 'bl.loading') ''
    $out = @()
    foreach ($n in $BloatApps.Keys) {
        if (Get-AppxPackage -Name $n -ErrorAction SilentlyContinue) { $out += [pscustomobject]@{ Pkg = $n; Name = $BloatApps[$n]; Note = "$($BloatNotes[$n])" } }
    }
    return $out
}
function Remove-BloatCore($items) {
    $items = @($items); $n = 0
    for ($i = 0; $i -lt $items.Count; $i++) {
        Set-TK (100.0 * $i / $items.Count) ((T 'bl.removing') -f ($i + 1), $items.Count, $items[$i].Name) ''
        Get-AppxPackage -Name $items[$i].Pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
        if (-not (Get-AppxPackage -Name $items[$i].Pkg -ErrorAction SilentlyContinue)) { $n++; Add-TKLog ((T 'bl.removed1') -f $items[$i].Name) 'ok' }
        else { Add-TKLog ((T 'bl.failed1') -f $items[$i].Name) 'warn' }
        Write-AppLog "Remove app: $($items[$i].Pkg)"
    }
    Set-TK 100 ((T 'bl.done') -f $n) ''
    return @{ Removed = $n }
}

# Έλεγχος ασφάλειας: κάθε γραμμή = κλειδί κειμένου + κατάσταση (ok/warn/bad/info) + παράμετροι
function Get-SecurityStatus {
    Set-TK -1 (T 'sec.loading') ''
    $L = [System.Collections.ArrayList]::new()
    function Add-Sec([string]$k, [string]$s, $a = @()) { [void]$L.Add([pscustomobject]@{ K = $k; S = $s; A = @($a) }) }

    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object { "$($_.displayName)" } | Where-Object { $_ -and $_ -notmatch 'Defender' } | Select-Object -Unique)
    if ($mp -and $mp.RealTimeProtectionEnabled) {
        Add-Sec 'sec.av.def' 'ok'
        if ([int]$mp.AntivirusSignatureAge -gt 3) { Add-Sec 'sec.av.sig' 'warn' @([int]$mp.AntivirusSignatureAge) }
    } elseif ($av.Count -gt 0) { Add-Sec 'sec.av.other' 'ok' @(($av -join ', ')) }
    else { Add-Sec 'sec.av.none' 'bad' }

    $fw = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    if ($fw.Count -gt 0) {
        $off = @($fw | Where-Object { -not $_.Enabled } | ForEach-Object { "$($_.Name)" })
        if ($off.Count -eq 0) { Add-Sec 'sec.fw.on' 'ok' } else { Add-Sec 'sec.fw.off' 'bad' @(($off -join ', ')) }
    }
    if ("$(Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA')" -eq '0') { Add-Sec 'sec.uac.off' 'bad' } else { Add-Sec 'sec.uac.on' 'ok' }
    if ("$(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections')" -eq '0') { Add-Sec 'sec.rdp.on' 'warn' } else { Add-Sec 'sec.rdp.off' 'ok' }
    $smb = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($smb) { if ($smb.EnableSMB1Protocol) { Add-Sec 'sec.smb1.on' 'warn' } else { Add-Sec 'sec.smb1.off' 'ok' } }
    try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { Add-Sec 'sec.sb.on' 'ok' } else { Add-Sec 'sec.sb.off' 'warn' } } catch {}
    $tpm = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    if ($tpm -and $tpm.SpecVersion) { Add-Sec 'sec.tpm' 'ok' @(("$($tpm.SpecVersion)" -split ',')[0].Trim()) } else { Add-Sec 'sec.tpm.none' 'info' }
    $hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($hf) { $days = [int]((Get-Date) - $hf.InstalledOn).TotalDays; if ($days -le 40) { Add-Sec 'sec.upd.ok' 'ok' @($days) } else { Add-Sec 'sec.upd.old' 'warn' @($days) } }
    if ("$(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled')" -eq '1') { Add-Sec 'sec.hvci.on' 'ok' } else { Add-Sec 'sec.hvci.off' 'info' }
    if ("$(Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt')" -eq '0') { Add-Sec 'sec.ext.shown' 'ok' } else { Add-Sec 'sec.ext.hidden' 'warn' }
    $v = @(Get-VpnStatus | Where-Object { $_.Kind -eq 'vpn' } | ForEach-Object { $_.Name })
    if ($v.Count -gt 0) { Add-Sec 'sec.vpn.on' 'ok' @(($v -join ' + ')) } else { Add-Sec 'sec.vpn.off' 'info' }
    $ra = @()
    foreach ($uk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($sub in @(Get-ChildItem -Path $uk -ErrorAction SilentlyContinue)) {
            $n = "$((Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue).DisplayName)"
            if ($n -match 'TeamViewer|AnyDesk|RustDesk|UltraViewer|Supremo|ScreenConnect|Splashtop|LogMeIn|Ammyy|Radmin|VNC') { $ra += ($n -replace '\s+[\d.]+$', '') }
        }
    }
    if ($ra.Count -gt 0) { Add-Sec 'sec.remote' 'info' @((($ra | Select-Object -Unique) -join ', ')) }
    Set-TK 100 (T 'sec.loaded') ''
    return , $L
}
function Invoke-QuickScanCore {
    $mpExe = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path -LiteralPath $mpExe)) { Add-TKLog (T 'sec.scan.nodef') 'warn'; return @{ Code = -1 } }
    Set-TK -1 (T 'sec.scanning') ''
    $r = Invoke-Native $mpExe '-Scan -ScanType 1' (T 'sec.scanning')
    $tail = @($r.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 3)
    foreach ($l in $tail) { Add-TKLog $l 'info' }
    Write-AppLog "Defender quick scan: $($r.Code)"
    return @{ Code = $r.Code }
}

# Σχέδιο ενέργειας
$PowerGuids = @{ balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'; high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
function Get-PowerPlanName {
    $g = Get-ActivePlanGuid
    if ($g -eq $PowerGuids.balanced) { return 'balanced' }
    if ($g -eq $PowerGuids.high) { return 'high' }
    $u = Get-UltimateGuid; if ($u -and $g -eq $u) { return 'ultimate' }
    return 'other'
}
function Set-PowerPlanCore([string]$which) {
    $g = $null
    if ($which -eq 'ultimate') {
        $g = Get-UltimateGuid
        if (-not $g) {
            $o = "$(powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61)"
            if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $g = $matches[1].ToLower()
                New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
                Set-Content -Path (Join-Path $DataDir 'ultimate-plan.txt') -Value $g
            }
        }
    } else { $g = $PowerGuids[$which] }
    if (-not $g) { return $false }
    powercfg /setactive $g | Out-Null
    $ok = ((Get-ActivePlanGuid) -eq $g)
    Write-AppLog "Power plan: $which ($ok)"
    return $ok
}

# ======================================================================
#  ΦΑΣΗ 2β: ΔΙΚΤΥΟ & VPN, ΥΠΟΛΕΙΜΜΑΤΑ, ΜΕΓΑΛΑ ΑΡΧΕΙΑ, ΥΓΕΙΑ ΔΙΣΚΩΝ
# ======================================================================
$VpnClientProc = '^(mullvad|nordvpn|nordlynx|protonvpn|expressvpn|surfshark|pia|cyberghost|ipvanish|windscribe|warp-svc|openvpn|wireguard|tunnelbear)'

function Get-ThreatSetCore {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    $cache = Join-Path $DataDir 'threat-ips.txt'
    $fresh = (Test-Path $cache) -and (((Get-Date) - (Get-Item $cache).LastWriteTime).TotalHours -lt 24)
    if (-not $fresh) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $all = New-Object System.Collections.Generic.List[string]
        foreach ($feed in $ThreatFeeds) {
            Set-TK -1 (T 'net.lists') $feed.Name
            try {
                $txt = (Invoke-WebRequest -Uri $feed.Url -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop).Content
                if ($txt -is [byte[]]) { $txt = [Text.Encoding]::ASCII.GetString($txt) }
                foreach ($line in ("$txt" -split "`n")) { $l = $line.Trim(); if ($l -match '^\d{1,3}(\.\d{1,3}){3}$') { $all.Add($l) } }
            } catch { Add-TKLog ((T 'net.listfail') -f $feed.Name) 'warn' }
        }
        if ($all.Count -gt 0) { [IO.File]::WriteAllLines($cache, $all) }
    }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    if (Test-Path $cache) { foreach ($l in [IO.File]::ReadAllLines($cache)) { [void]$set.Add($l) } }
    return , $set
}

function Get-NetReportCore([bool]$geo) {
    function Write-Note([string]$t) { Add-TKLog (T 'net.geofail') 'warn' }
    $st = Get-MullvadStatus
    $vpnNames = @(Get-VpnStatus | Where-Object { $_.Kind -eq 'vpn' } | ForEach-Object { $_.Name })
    $vpnIps = @(Get-VpnIps)
    $threat = Get-ThreatSetCore
    $trusted = @(Get-TrustedList)
    $conns = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { -not (Test-PrivateIp $_.RemoteAddress) })
    $ipInfo = @{}
    if ($geo) { Set-TK -1 (T 'net.geo') ''; $ipInfo = Get-IpInfo @($conns | ForEach-Object { "$($_.RemoteAddress)" }) }
    $groups = @($conns | Group-Object OwningProcess)
    $out = @(); $gi = 0
    foreach ($g in $groups) {
        $gi++; Set-TK (100.0 * $gi / [Math]::Max(1, $groups.Count)) (T 'net.analyzing') "$gi/$($groups.Count)"
        $procId = [int]$g.Name
        $pi = Get-ProcInfo $procId
        $isTorrent = ("$($pi.Name)" -match $TorrentApps)
        $isTrusted = [bool]($pi.Path -and ($trusted -contains "$($pi.Path)".ToLower()))
        $flags = @(); $level = 0
        $bad = @($g.Group | Where-Object { $threat.Contains("$($_.RemoteAddress)") })
        if ($bad.Count -gt 0) {
            $ips = (@($bad | ForEach-Object { "$($_.RemoteAddress)" }) | Select-Object -Unique) -join ', '
            if ($isTorrent) { $flags += @{ K = 'net.f.threat.torrent'; A = @($bad.Count, $ips) }; if ($level -lt 1) { $level = 1 } }
            else { $flags += @{ K = 'net.f.threat'; A = @($ips) }; $level = 2 }
        }
        if ($vpnIps.Count -gt 0 -and "$($pi.Name)" -notmatch $VpnClientProc) {
            $outside = @($g.Group | Where-Object { $vpnIps -notcontains "$($_.LocalAddress)" })
            if ($outside.Count -gt 0) {
                if ($isTorrent) { $flags += @{ K = 'net.f.torrentleak'; A = @($outside.Count) }; $level = 2 }
                elseif (-not $isTrusted) { $flags += @{ K = 'net.f.outside'; A = @($outside.Count) }; if ($level -lt 1) { $level = 1 } }
            }
        }
        if (-not $isTrusted) {
            if ($pi.Unsigned) { $flags += @{ K = 'net.f.unsigned'; A = @() }; if ($level -lt 1) { $level = 1 } }
            if ("$($pi.Path)" -match '\\(Temp|Downloads)\\') { $flags += @{ K = 'net.f.temp'; A = @() }; $level = 2 }
            if ("$($pi.Name)" -match $RemoteAccessApps) { $flags += @{ K = 'net.f.remote'; A = @() }; if ($pi.Unsigned) { $level = 2 } elseif ($level -lt 1) { $level = 1 } }
            foreach ($port in (@($g.Group | ForEach-Object { [int]$_.RemotePort }) | Select-Object -Unique)) {
                if ($SuspiciousPorts.ContainsKey($port)) { $flags += @{ K = 'net.f.port'; A = @($port) }; if ($pi.Unsigned) { $level = 2 } elseif ($level -lt 1) { $level = 1 } }
            }
        }
        $sigKey = 'net.sig.unknown'; if ($pi.Publisher) { $sigKey = 'net.sig.ok' } elseif ($pi.Unsigned) { $sigKey = 'net.sig.none' }
        $dest = ''
        if ($ipInfo.Count -gt 0) {
            $names = foreach ($c in $g.Group) { $i = $ipInfo["$($c.RemoteAddress)"]; if ($i) { "$($i.Org) ($($i.Code))" } }
            $dest = (@($names) | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ×$($_.Count)" }) -join ', '
        }
        $cl = @()
        foreach ($c in ($g.Group | Select-Object -First 30)) {
            $via = ''; if ($vpnIps.Count -gt 0) { if ($vpnIps -contains "$($c.LocalAddress)") { $via = 'vpn' } else { $via = 'out' } }
            $i = $ipInfo["$($c.RemoteAddress)"]; $org = ''; if ($i) { $org = "$($i.Org), $($i.Country)" }
            $cl += [pscustomobject]@{ Ip = "$($c.RemoteAddress)"; Port = [int]$c.RemotePort; Via = $via; Org = $org; Bad = $threat.Contains("$($c.RemoteAddress)") }
        }
        $out += [pscustomobject]@{ Level = $level; Name = "$($pi.Name)"; PID = $procId; Count = $g.Count; SigKey = $sigKey; Publisher = "$($pi.Publisher)"
                                   Path = "$($pi.Path)"; Trusted = $isTrusted; Flags = $flags; Dest = $dest; Conns = $cl }
    }
    $listen = @()
    foreach ($lg in (@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { "$($_.LocalAddress)" -eq '0.0.0.0' -or "$($_.LocalAddress)" -eq '::' }) | Group-Object OwningProcess)) {
        $pn = (Get-Process -Id ([int]$lg.Name) -ErrorAction SilentlyContinue).ProcessName; if (-not $pn) { $pn = "PID $($lg.Name)" }
        $listen += [pscustomobject]@{ Name = $pn; Ports = ((@($lg.Group | ForEach-Object { [int]$_.LocalPort }) | Sort-Object -Unique) -join ', ') }
    }
    Set-TK 100 ((T 'net.done') -f $conns.Count, $out.Count) ''
    $status = $null
    if ($st) { $status = [pscustomobject]@{ Ip = "$($st.ip)"; Country = "$($st.country)"; City = "$($st.city)"; Mullvad = [bool]$st.mullvad_exit_ip; Server = "$($st.mullvad_exit_ip_hostname)"; Org = "$($st.organization)" } }
    return @{ Report = @($out | Sort-Object @{ e = 'Level'; Descending = $true }, @{ e = 'Count'; Descending = $true }); Listen = $listen; Status = $status
              VpnNames = $vpnNames; VpnIps = $vpnIps; ThreatCount = $threat.Count; Threat = $threat; Total = $conns.Count; When = (Get-Date) }
}

function Export-NetReportCore($data) {
    $dir = Join-Path $AppRoot 'reports'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir ('network-{0}.html' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    function ConvertTo-HtmlText([string]$t) { [System.Net.WebUtility]::HtmlEncode($t) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<!DOCTYPE html><html lang=""$script:LangCode""><head><meta charset=""utf-8""><meta name=""viewport"" content=""width=device-width, initial-scale=1""><title>$(ConvertTo-HtmlText (T 'net.rep.title'))</title><style>")
    [void]$sb.Append('body{font-family:"Segoe UI",Arial,sans-serif;margin:24px;background:#0A0E1A;color:#E8F1FF}h1{margin:0 0 4px;color:#00E5FF}p.meta{color:#8C9DBA}.vpn{padding:10px 14px;border-radius:10px;margin:14px 0;font-weight:600}.ok{background:#0f2e22;color:#3DFF9A}.bad{background:#3a1220;color:#FF4D6D}')
    [void]$sb.Append('table{border-collapse:collapse;width:100%;background:#141C30;border-radius:10px;overflow:hidden}th,td{padding:8px 10px;text-align:left;vertical-align:top;font-size:14px;border-bottom:1px solid #22304D}th{background:#0F1526;color:#8C9DBA}.l1 td:first-child{border-left:5px solid #FFC53D}.l2 td:first-child{border-left:5px solid #FF4D6D}.l0 td:first-child{border-left:5px solid #3DFF9A}small{color:#8C9DBA}ul{margin:0;padding-left:18px}</style></head><body>')
    [void]$sb.Append("<h1>John's Toolkit · $(ConvertTo-HtmlText (T 'net.rep.title'))</h1><p class=""meta"">$((Get-Date).ToString('f', (Get-LangCulture))) · $(ConvertTo-HtmlText $env:COMPUTERNAME) · $(ConvertTo-HtmlText ((T 'net.threatcount') -f $data.ThreatCount))</p>")
    if ($data.Status) {
        if (@($data.VpnNames).Count -gt 0) { [void]$sb.Append("<div class=""vpn ok"">$(ConvertTo-HtmlText ((T 'net.vpn.on') -f (@($data.VpnNames) -join ' + '), $data.Status.Ip, $data.Status.Country))</div>") }
        else { [void]$sb.Append("<div class=""vpn bad"">$(ConvertTo-HtmlText ((T 'net.vpn.off') -f $data.Status.Ip, $data.Status.Country))</div>") }
    }
    [void]$sb.Append("<table><tr><th>$(ConvertTo-HtmlText (T 'net.col.state'))</th><th>$(ConvertTo-HtmlText (T 'net.col.prog'))</th><th>$(ConvertTo-HtmlText (T 'net.col.conns'))</th><th>$(ConvertTo-HtmlText (T 'net.col.sig'))</th><th>$(ConvertTo-HtmlText (T 'net.col.dest'))</th><th>$(ConvertTo-HtmlText (T 'net.col.flags'))</th></tr>")
    foreach ($r in $data.Report) {
        $fl = ''
        if (@($r.Flags).Count -gt 0) { $fl = '<ul>' + ((@($r.Flags) | ForEach-Object { $t = T $_.K; if (@($_.A).Count) { $t = $t -f @($_.A) }; "<li>$(ConvertTo-HtmlText $t)</li>" }) -join '') + '</ul>' }
        $sig = T $r.SigKey; if ($r.Publisher) { $sig += ": $($r.Publisher)" }
        [void]$sb.Append("<tr class=""l$($r.Level)""><td>$(ConvertTo-HtmlText (T ('net.lv.' + $r.Level)))</td><td><b>$(ConvertTo-HtmlText $r.Name)</b><br><small>$(ConvertTo-HtmlText $r.Path)</small></td><td>$($r.Count)</td><td>$(ConvertTo-HtmlText $sig)</td><td>$(ConvertTo-HtmlText $r.Dest)</td><td>$fl</td></tr>")
    }
    [void]$sb.Append("</table><p class=""meta"">$(ConvertTo-HtmlText (T 'net.rep.note'))</p></body></html>")
    [IO.File]::WriteAllText($file, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    return $file
}

function Invoke-FileScanCore([string]$path) {
    $mpExe = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path -LiteralPath $mpExe)) { return -1 }
    Set-TK -1 (T 'net.scanning') (Split-Path $path -Leaf)
    $r = Invoke-Native $mpExe "-Scan -ScanType 3 -File `"$path`"" ''
    Write-AppLog "Defender file scan $path -> $($r.Code)"
    return $r.Code
}

# ---------- Υπολείμματα (χρησιμοποιεί τον κλασικό μηχανισμό με αντίγραφα, με μηνύματα στη γλώσσα της εφαρμογής) ----------
function Find-LeftoversCore {
    function Start-Progress([string]$l) { Set-TK -1 (T 'lo.scanning') '' }
    function Update-Progress([double]$pct = -1, [string]$detail = '', [switch]$Force) { if ($TK) { $TK.Pct = $pct } }
    function Stop-Progress { }
    $r = @(Find-Leftovers)
    Set-TK 100 ((T 'lo.found') -f $r.Count) ''
    return , $r
}
function Remove-LeftoversCore($items) {
    function Start-Progress([string]$l) { Set-TK -1 (T 'lo.removing') '' }
    function Update-Progress([double]$pct = -1, [string]$detail = '', [switch]$Force) { if ($TK) { $TK.Pct = $pct; if ($detail) { $TK.Detail = $detail } } }
    function Stop-Progress { }
    $r = Remove-Leftovers @($items)
    Set-TK 100 ((T 'lo.removed') -f $r.Ok) ''
    return $r
}
function Get-LeftoverBackups {
    $root = Join-Path $DataDir 'backup'
    $out = @()
    foreach ($s in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $mf = Join-Path $s.FullName 'manifest.json'
        if (-not (Test-Path $mf)) { continue }
        $m = @(); foreach ($e in (ConvertFrom-Json ([IO.File]::ReadAllText($mf, [Text.Encoding]::UTF8)))) { if ($e.Type) { $m += $e } }
        $out += [pscustomobject]@{ Dir = $s.FullName; When = $s.CreationTime; Count = $m.Count; Labels = @($m | ForEach-Object { "$($_.Label)" }) }
    }
    return $out
}
function Restore-LeftoverBackupCore([string]$dir) {
    $mf = Join-Path $dir 'manifest.json'
    $ok = 0; $fail = 0
    foreach ($e in (ConvertFrom-Json ([IO.File]::ReadAllText($mf, [Text.Encoding]::UTF8)))) {
        if (-not $e.Type) { continue }
        try {
            if ($e.Type -eq 'reg') { & reg.exe import $e.File 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'reg' } }
            elseif ($e.Type -eq 'file') { New-Item -ItemType Directory -Path (Split-Path $e.Extra -Parent) -Force | Out-Null; Move-Item -LiteralPath $e.File -Destination $e.Extra -Force -ErrorAction Stop }
            elseif ($e.Type -eq 'task') { $tp, $tn = "$($e.Extra)" -split '\|', 2; Register-ScheduledTask -Xml ([IO.File]::ReadAllText($e.File)) -TaskName $tn -TaskPath $tp -Force -ErrorAction Stop | Out-Null }
            $ok++
        } catch { $fail++ }
    }
    if ($fail -eq 0) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    Write-AppLog "Leftover restore: ok=$ok fail=$fail"
    return @{ Ok = $ok; Fail = $fail }
}

# ---------- Μεγάλα αρχεία ----------
function Find-BigFilesCore([string]$root) {
    Set-TK -1 (T 'bf.scanning') $root
    $skipDirs = @("$env:WINDIR", "$env:SystemDrive\System Volume Information", "$env:SystemDrive\`$Recycle.Bin") | Where-Object { $_ }
    $skipFiles = @('pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'DumpStack.log.tmp')
    $big = New-Object System.Collections.Generic.List[object]
    $n = 0; $bytes = 0.0
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $n++; $bytes += $_.Length
        if ($_.Length -ge 5MB -and $skipFiles -notcontains $_.Name) {
            $f = $_.FullName; $skip = $false
            foreach ($d in $skipDirs) { if ($f.StartsWith($d + '\', [StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break } }
            if (-not $skip) { $big.Add([pscustomobject]@{ Path = $f; Name = $_.Name; Dir = $_.DirectoryName; Size = [double]$_.Length; Date = $_.LastWriteTime }) }
        }
        if ($n % 500 -eq 0) { Set-TK -1 $null ((T 'bf.progress') -f $n, (Format-Size $bytes)) }
    }
    $top = @($big | Sort-Object Size -Descending | Select-Object -First 40)
    Set-TK 100 ((T 'bf.done') -f $n, (Format-Size $bytes)) ''
    return @{ Files = $top; Count = $n; Bytes = $bytes; Root = $root }
}

# ---------- Υγεία δίσκων (προστίθεται στη σελίδα Ασφάλειας) ----------
function Get-HealthStatus {
    $L = [System.Collections.ArrayList]::new()
    foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)) {
        $rel = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $s = 'info'; $k = 'hl.disk.unknown'
        switch ("$($d.HealthStatus)") { 'Healthy' { $s = 'ok'; $k = 'hl.disk.ok' } 'Warning' { $s = 'warn'; $k = 'hl.disk.warn' } 'Unhealthy' { $s = 'bad'; $k = 'hl.disk.bad' } }
        $extra = @()
        if ($rel.Temperature) { $extra += ((T 'hl.temp') -f $rel.Temperature); if ([int]$rel.Temperature -ge 60 -and $s -eq 'ok') { $s = 'warn' } }
        if ("$($d.MediaType)" -eq 'SSD' -and $null -ne $rel.Wear) { $extra += ((T 'hl.wear') -f $rel.Wear); if ([int]$rel.Wear -ge 80 -and $s -eq 'ok') { $s = 'warn' } }
        $name = "$($d.FriendlyName) ($($d.MediaType), $(Format-Size $d.Size))"
        $txt = $name; if ($extra.Count -gt 0) { $txt += ' · ' + ($extra -join ' · ') }
        [void]$L.Add([pscustomobject]@{ K = $k; S = $s; A = @($txt); G = 'health' })
    }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { $up = (Get-Date) - $os.LastBootUpTime; if ($up.Days -ge 7) { [void]$L.Add([pscustomobject]@{ K = 'hl.uptime.long'; S = 'warn'; A = @($up.Days); G = 'health' }) } else { [void]$L.Add([pscustomobject]@{ K = 'hl.uptime'; S = 'ok'; A = @($up.Days, $up.Hours); G = 'health' }) } }
    $bt = @(Get-BootTimes)
    if ($bt.Count -gt 0) {
        $avg = [math]::Round(($bt | Measure-Object Seconds -Average).Average, 1)
        $st = 'ok'; if ($bt[0].Seconds -gt 90) { $st = 'warn' }
        [void]$L.Add([pscustomobject]@{ K = 'hl.boot'; S = $st; A = @($bt[0].Seconds, $bt.Count, $avg); G = 'health' })
    }
    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { [void]$L.Add([pscustomobject]@{ K = 'hl.battery'; S = 'info'; A = @(); G = 'health' }) }
    return , $L
}
function Get-SecurityAndHealth {
    # Οι δύο συναρτήσεις επιστρέφουν λίστα ως ένα αντικείμενο: τη διατρέχουμε απευθείας (χωρίς @()),
    # αλλιώς η λίστα θα έμπαινε ολόκληρη σαν ένα στοιχείο.
    $all = [System.Collections.ArrayList]::new()
    $sec = Get-SecurityStatus
    foreach ($x in $sec) { $x | Add-Member -NotePropertyName G -NotePropertyValue 'sec' -Force; [void]$all.Add($x) }
    $hl = Get-HealthStatus
    foreach ($x in $hl) { [void]$all.Add($x) }
    return , $all
}
function New-BatteryReport {
    $rep = Join-Path $AppRoot 'reports\battery-report.html'
    New-Item -ItemType Directory -Path (Split-Path $rep) -Force | Out-Null
    powercfg /batteryreport /output "$rep" | Out-Null
    return $rep
}

# ======================================================================
#  v2.4: SPEEDTEST, ΕΠΙΔΙΟΡΘΩΣΗ ΔΙΚΤΥΟΥ, ΔΙΣΚΟΙ WSL/DOCKER, ΧΡΟΝΟΣ ΕΚΚΙΝΗΣΗΣ, ΔΙΣΚΟΙ
# ======================================================================
function Get-FixedDrives {
    $out = @()
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try { if ($d.DriveType -eq 'Fixed' -and $d.IsReady) { $out += [pscustomobject]@{ Root = $d.RootDirectory.FullName; Letter = $d.Name.TrimEnd('\'); Label = "$($d.VolumeLabel)"; Free = [double]$d.AvailableFreeSpace; Size = [double]$d.TotalSize } } } catch {}
    }
    return $out
}
# Αρχεία που ΔΕΝ πρέπει να σβηστούν (δίσκοι εικονικών μηχανών, Docker/WSL, βάσεις δεδομένων, Outlook)
function Test-CriticalFile([string]$path) {
    if ($path -match '\.(vhdx|vhd|avhdx|vdi|vmdk|qcow2|nvram|vmsn|pst|ost|mdf|ldf|ndf|ibd)$') { return $true }
    if ($path -match '\\(Docker|wsl|VirtualBox VMs|Virtual Machines|Hyper-V|PostgreSQL\\[^\\]+\\data|MySQL|MongoDB)\\') { return $true }
    return $false
}

# ---------- Speedtest (διακομιστές της Cloudflare) ----------
function Invoke-SpeedTest {
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $h = [System.Net.Http.HttpClient]::new(); $h.Timeout = [TimeSpan]::FromSeconds(60)
    try { $h.DefaultRequestHeaders.UserAgent.ParseAdd("JohnsToolkit/$AppVersion") } catch {}
    $base = 'https://speed.cloudflare.com'
    $where = ''
    try { $trace = $h.GetStringAsync("$base/cdn-cgi/trace").GetAwaiter().GetResult(); if ($trace -match 'colo=(\w+)') { $where = $matches[1] } } catch {}
    Set-TK 3 (T 'sp.ping') $where
    $lat = @()
    for ($i = 0; $i -lt 10; $i++) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { [void]$h.GetStringAsync("$base/__down?bytes=0").GetAwaiter().GetResult(); $sw.Stop(); $lat += $sw.Elapsed.TotalMilliseconds } catch {}
    }
    if ($lat.Count -lt 3) { $h.Dispose(); return @{ Ok = $false } }
    $best = @($lat | Sort-Object | Select-Object -First ($lat.Count - 2))
    $ping = ($best | Measure-Object -Average).Average
    $jit = 0.0; for ($i = 1; $i -lt $lat.Count; $i++) { $jit += [math]::Abs($lat[$i] - $lat[$i - 1]) }; $jit = $jit / ($lat.Count - 1)

    $down = Measure-SpeedRounds $h 'down' 10 45
    $up = Measure-SpeedRounds $h 'up' 55 45
    $h.Dispose()
    $r = [pscustomobject]@{ Ok = $true; Ping = [math]::Round($ping); Jitter = [math]::Round($jit, 1); Down = [math]::Round($down, 1); Up = [math]::Round($up, 1); Where = $where; When = (Get-Date).ToString('s') }
    Set-TK 100 ((T 'sp.done') -f $r.Down, $r.Up, $r.Ping) ''
    # ιστορικό (τελευταίες 20 μετρήσεις)
    try {
        $f = Join-Path $CoreData 'speedtests.json'; $hist = @()
        if (Test-Path $f) { foreach ($x in (ConvertFrom-Json ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)))) { if ($x.When) { $hist += $x } } }
        $hist = @($r) + $hist | Select-Object -First 20
        New-Item -ItemType Directory -Path $CoreData -Force | Out-Null
        [IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject @($hist) -Depth 3), (New-Object System.Text.UTF8Encoding $false))
    } catch {}
    Write-AppLog ("Speedtest: down {0} / up {1} Mbps, ping {2} ms" -f $r.Down, $r.Up, $r.Ping)
    return $r
}
function Measure-SpeedRounds($h, [string]$dir, [double]$p0, [double]$span) {
    $base = 'https://speed.cloudflare.com'
    $size = 4MB; if ($dir -eq 'up') { $size = 2MB }
    $rounds = @(); $sw = [Diagnostics.Stopwatch]::StartNew(); $limit = 8.0
    $label = T 'sp.down'; if ($dir -eq 'up') { $label = T 'sp.up' }
    while ($sw.Elapsed.TotalSeconds -lt $limit -and $rounds.Count -lt 30) {
        $t0 = $sw.Elapsed.TotalSeconds
        $tasks = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task]'
        if ($dir -eq 'down') { for ($i = 0; $i -lt 4; $i++) { $tasks.Add($h.GetByteArrayAsync("$base/__down?bytes=$size")) } }
        else {
            $data = New-Object byte[] $size; ([Random]::new()).NextBytes($data)
            for ($i = 0; $i -lt 4; $i++) { $tasks.Add($h.PostAsync("$base/__up", [System.Net.Http.ByteArrayContent]::new($data))) }
        }
        $arr = $tasks.ToArray()
        while (-not [System.Threading.Tasks.Task]::WaitAll($arr, 250)) {
            Set-TK ($p0 + $span * [math]::Min(1, $sw.Elapsed.TotalSeconds / $limit)) $label ''
            if ($sw.Elapsed.TotalSeconds -gt 30) { break }
        }
        $okCount = @($arr | Where-Object { "$($_.Status)" -eq 'RanToCompletion' }).Count
        if ($okCount -eq 0) { break }
        $dt = $sw.Elapsed.TotalSeconds - $t0
        $mbps = ($okCount * [double]$size * 8) / [math]::Max(0.05, $dt) / 1e6
        $rounds += $mbps
        Set-TK ($p0 + $span * [math]::Min(1, $sw.Elapsed.TotalSeconds / $limit)) $label ('{0:N1} Mbps' -f $mbps)
        if ($dt -lt 1.5 -and $size -lt 64MB) { $size *= 2 }
    }
    if ($rounds.Count -eq 0) { return 0 }
    if ($rounds.Count -gt 2) { $rounds = @($rounds | Select-Object -Skip 1) }
    # μέσος όρος των καλύτερων μισών γύρων (όπως τα περισσότερα speedtest)
    $top = @($rounds | Sort-Object -Descending | Select-Object -First ([math]::Max(1, [math]::Ceiling($rounds.Count / 2))))
    return ($top | Measure-Object -Average).Average
}
function Get-SpeedHistory {
    $f = Join-Path $CoreData 'speedtests.json'; $out = @()
    if (Test-Path $f) { try { foreach ($x in (ConvertFrom-Json ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)))) { if ($x.When) { $out += $x } } } catch {} }
    return $out
}

# ---------- Επιδιόρθωση δικτύου ----------
function Test-Online {
    $ip = $false; $dns = $false
    try { $ip = [bool](Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction Stop) } catch {}
    try { $dns = [bool](Resolve-DnsName -Name 'www.microsoft.com' -DnsOnly -QuickTimeout -ErrorAction Stop) } catch {}
    return @{ Ip = $ip; Dns = $dns }
}
function Invoke-NetworkQuickFix {
    $steps = @(
        @{ K = 'nr.s.dns'; R = { ipconfig /flushdns | Out-Null; $LASTEXITCODE } }
        @{ K = 'nr.s.arp'; R = { netsh interface ip delete arpcache | Out-Null; $LASTEXITCODE } }
        @{ K = 'nr.s.renew'; R = { ipconfig /renew | Out-Null; 0 } }
        @{ K = 'nr.s.adapters'; R = { $a = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Up' }); foreach ($x in $a) { Restart-NetAdapter -Name $x.Name -Confirm:$false -ErrorAction SilentlyContinue }; Start-Sleep -Seconds 6; 0 } }
    )
    for ($i = 0; $i -lt $steps.Count; $i++) {
        Set-TK (100.0 * $i / ($steps.Count + 1)) (T $steps[$i].K) ''
        $code = & $steps[$i].R
        if ("$code" -eq '0' -or -not $code) { Add-TKLog ('✓ ' + (T $steps[$i].K)) 'ok' } else { Add-TKLog ((T $steps[$i].K) + ': ' + (Get-CodeText ([int]$code))) 'warn' }
    }
    Set-TK 90 (T 'nr.s.test') ''
    $t = Test-Online
    Write-AppLog "Network quick fix: ip=$($t.Ip) dns=$($t.Dns)"
    return $t
}
function Invoke-NetworkReset {
    $cmds = @(
        @{ K = 'nr.s.winsock'; A = 'winsock reset' }
        @{ K = 'nr.s.ip4'; A = 'int ip reset' }
        @{ K = 'nr.s.ip6'; A = 'int ipv6 reset' }
        @{ K = 'nr.s.proxy'; A = 'winhttp reset proxy' }
    )
    $fail = 0
    for ($i = 0; $i -lt $cmds.Count; $i++) {
        Set-TK (100.0 * $i / ($cmds.Count + 1)) (T $cmds[$i].K) ''
        $r = Invoke-Native "$env:WINDIR\System32\netsh.exe" $cmds[$i].A ''
        if ((Test-ExitOk $r.Code) -or $r.Code -eq 1) { Add-TKLog ('✓ ' + (T $cmds[$i].K)) 'ok' } else { $fail++; Add-TKLog ((T $cmds[$i].K) + ': ' + (Get-CodeText $r.Code)) 'warn' }
    }
    ipconfig /flushdns | Out-Null
    Set-TK 100 (T 'nr.reset.done') ''
    Write-AppLog "Network reset (fail=$fail)"
    return @{ Fail = $fail }
}

# ---------- Συμπίεση δίσκων WSL / Docker ----------
function Get-WslDisks {
    $la = $env:LOCALAPPDATA; $out = @()
    $cands = @("$la\Docker\wsl\disk\docker_data.vhdx", "$la\Docker\wsl\data\ext4.vhdx", "$la\Docker\wsl\main\ext4.vhdx")
    foreach ($p in @(Get-ChildItem -Path "$la\Packages" -Directory -ErrorAction SilentlyContinue)) {
        $v = Join-Path $p.FullName 'LocalState\ext4.vhdx'; if (Test-Path -LiteralPath $v) { $cands += $v }
    }
    foreach ($c in $cands | Select-Object -Unique) {
        if (Test-Path -LiteralPath $c) { $out += [pscustomobject]@{ Path = $c; Size = [double](Get-Item -LiteralPath $c -Force).Length } }
    }
    return $out
}
function Test-DockerRunning { return [bool](Get-Process -Name 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue) }
function Invoke-CompactWslDisks($paths) {
    $paths = @($paths); $saved = 0.0; $ok = 0
    Set-TK 3 (T 'wsl.stopping') ''
    $wsl = "$env:WINDIR\System32\wsl.exe"
    if (Test-Path $wsl) { $null = Invoke-Native $wsl '--shutdown' ''; Start-Sleep -Seconds 4 }
    for ($i = 0; $i -lt $paths.Count; $i++) {
        $p = $paths[$i]
        Set-TK (10 + 85.0 * $i / $paths.Count) ((T 'wsl.compacting') -f (Split-Path $p -Leaf)) ''
        $before = [double](Get-Item -LiteralPath $p -Force).Length
        $script = Join-Path ([IO.Path]::GetTempPath()) ('jt_diskpart_' + [guid]::NewGuid().ToString('N') + '.txt')
        [IO.File]::WriteAllLines($script, @("select vdisk file=`"$p`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk'))
        $r = Invoke-Native "$env:WINDIR\System32\diskpart.exe" "/s `"$script`"" ''
        Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
        $after = [double](Get-Item -LiteralPath $p -Force).Length
        $gain = [math]::Max(0, $before - $after); $saved += $gain
        if ($r.Code -eq 0) { $ok++; Add-TKLog ((T 'wsl.done1') -f (Split-Path $p -Leaf), (Format-Size $before), (Format-Size $after)) 'ok' }
        else { Add-TKLog ((T 'wsl.fail1') -f (Split-Path $p -Leaf)) 'warn' }
    }
    Set-TK 100 ((T 'wsl.done') -f (Format-Size $saved)) ''
    Write-AppLog "WSL compact: saved $(Format-Size $saved)"
    return @{ Saved = $saved; Ok = $ok }
}

# ---------- Χρόνος εκκίνησης των Windows ----------
function Get-BootTimes {
    $out = @()
    try {
        foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 10 -ErrorAction Stop)) {
            $x = [xml]$e.ToXml()
            $ms = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
            if ($ms) { $out += [pscustomobject]@{ When = $e.TimeCreated; Seconds = [math]::Round([double]$ms / 1000, 1) } }
        }
    } catch {}
    return $out
}

# ======================================================================
#  v2.5: PATH, ΘΥΡΕΣ, DNS, ΑΠΕΓΚΑΤΑΣΤΑΣΗ, ΚΡΑΣΑΡΙΣΜΑΤΑ, ΣΥΣΚΕΥΕΣ, WINDOWS UPDATE, ΔΙΠΛΑ ΑΡΧΕΙΑ
# ======================================================================

# ---------- PATH ----------
$PathKeys = @{ Machine = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; User = 'HKCU:\Environment' }
function Get-RawPath([string]$scope) {
    try { return [string](Get-Item -LiteralPath $PathKeys[$scope] -ErrorAction Stop).GetValue('Path', '', 'DoNotExpandEnvironmentNames') } catch { return '' }
}
function Get-PathReport {
    $seen = @{}; $out = @{}
    foreach ($scope in 'Machine', 'User') {
        $list = @(); $i = 0
        foreach ($raw in ((Get-RawPath $scope) -split ';')) {
            $exp = [Environment]::ExpandEnvironmentVariables($raw).Trim().TrimEnd('\')
            $key = $exp.ToLowerInvariant()
            $state = 'ok'
            if (-not $raw.Trim()) { $state = 'empty' }
            elseif ($seen.ContainsKey($key)) { $state = 'dup' }
            elseif (-not (Test-Path -LiteralPath $exp)) { $state = 'missing' }
            if ($raw.Trim() -and -not $seen.ContainsKey($key)) { $seen[$key] = "$scope" }
            $py = ''
            if ($state -eq 'ok' -and (Test-Path -LiteralPath (Join-Path $exp 'python.exe'))) {
                $py = 'python'
                if ($exp -match 'WindowsApps') { $py = 'store-alias' }
                elseif ($exp -match 'Python(\d)(\d+)') { $py = "Python $($matches[1]).$($matches[2])" }
            }
            $list += [pscustomobject]@{ Scope = $scope; Index = $i; Raw = $raw; Expanded = $exp; State = $state; Python = $py }
            $i++
        }
        $out[$scope] = $list
    }
    # ποιο python τρέχει πρώτο (τα Windows ψάχνουν πρώτα στο Machine και μετά στο User PATH)
    $first = @($out.Machine + $out.User | Where-Object { $_.Python }) | Select-Object -First 1
    $out.FirstPython = $first
    return $out
}
function Update-EnvBroadcast {
    try {
        if (-not ('JTEnv' -as [type])) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class JTEnv { [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult); }'
        }
        $r = [UIntPtr]::Zero
        [void][JTEnv]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 3000, [ref]$r)
    } catch {}
}
function Set-CleanPath([string]$scope, [int[]]$removeIdx) {
    $raw = Get-RawPath $scope
    New-Item -ItemType Directory -Path $CoreData -Force | Out-Null
    $bk = Join-Path $CoreData ('path-backup-{0}-{1}.txt' -f $scope.ToLower(), (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    [IO.File]::WriteAllText($bk, $raw, (New-Object System.Text.UTF8Encoding $false))
    $parts = $raw -split ';'
    $keep = for ($i = 0; $i -lt $parts.Count; $i++) { if ($removeIdx -notcontains $i -and $parts[$i].Trim()) { $parts[$i] } }
    $new = ($keep -join ';')
    $hive = if ($scope -eq 'Machine') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $sub = if ($scope -eq 'Machine') { 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } else { 'Environment' }
    $rk = $hive.OpenSubKey($sub, $true)
    $rk.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString); $rk.Close()
    Update-EnvBroadcast
    Write-AppLog "PATH ($scope) cleaned: removed $($removeIdx.Count) entries, backup $bk"
    return $bk
}
function Get-PathBackups { return @(Get-ChildItem -Path (Join-Path $CoreData 'path-backup-*.txt') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 6) }
function Restore-PathBackup([string]$file) {
    $scope = 'User'; if ((Split-Path $file -Leaf) -like 'path-backup-machine-*') { $scope = 'Machine' }
    $val = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
    $hive = if ($scope -eq 'Machine') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $sub = if ($scope -eq 'Machine') { 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } else { 'Environment' }
    $rk = $hive.OpenSubKey($sub, $true); $rk.SetValue('Path', $val, [Microsoft.Win32.RegistryValueKind]::ExpandString); $rk.Close()
    Update-EnvBroadcast
    Write-AppLog "PATH ($scope) restored from $file"
    return $scope
}

# ---------- Ποιος πιάνει τη θύρα ----------
function Find-PortUsers([int]$port) {
    $rows = @()
    foreach ($c in @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)) { $rows += [pscustomobject]@{ Proto = 'TCP'; State = "$($c.State)"; Local = "$($c.LocalAddress):$($c.LocalPort)"; Remote = "$($c.RemoteAddress):$($c.RemotePort)"; PID = [int]$c.OwningProcess } }
    foreach ($u in @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue)) { $rows += [pscustomobject]@{ Proto = 'UDP'; State = ''; Local = "$($u.LocalAddress):$($u.LocalPort)"; Remote = ''; PID = [int]$u.OwningProcess } }
    $out = @()
    foreach ($g in ($rows | Group-Object PID)) {
        $procId = [int]$g.Name
        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $svc = @(Get-CimInstance Win32_Service -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)" })
        $path = ''; try { $path = "$($p.Path)" } catch {}
        $out += [pscustomobject]@{ PID = $procId; Name = $(if ($p) { $p.ProcessName } elseif ($procId -eq 4) { 'System' } else { "PID $procId" }); Path = $path; Services = $svc
                                   States = ((@($g.Group | ForEach-Object { "$($_.Proto) $($_.State)".Trim() }) | Select-Object -Unique) -join ', '); Lines = @($g.Group | Select-Object -First 6) }
    }
    return $out
}

# ---------- DNS ----------
$DnsPresets = [ordered]@{
    auto = @(); cloudflare = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'); quad9 = @('9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9')
    google = @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844'); adguard = @('94.140.14.14', '94.140.15.15', '2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'); mullvad = @('194.242.2.2', '2a07:e340::2')
}
function Get-DnsAdapters { return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { "$($_.Status)" -eq 'Up' }) }
function Get-DnsStatus {
    $out = @()
    foreach ($a in Get-DnsAdapters) {
        $srv = @(Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        $preset = 'custom'
        foreach ($k in $DnsPresets.Keys) { if ($k -ne 'auto' -and $srv.Count -gt 0 -and $DnsPresets[$k] -contains $srv[0]) { $preset = $k } }
        $dhcp = $false; try { $dhcp = [bool]((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" -ErrorAction Stop).NameServer -eq '') } catch {}
        if ($dhcp -and $preset -eq 'custom') { $preset = 'auto' }
        $out += [pscustomobject]@{ Name = "$($a.Name)"; Desc = "$($a.InterfaceDescription)"; Servers = ($srv -join ', '); Preset = $preset }
    }
    return $out
}
function Set-DnsPreset([string]$preset) {
    $n = 0
    foreach ($a in Get-DnsAdapters) {
        if ($preset -eq 'auto') { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue }
        else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $DnsPresets[$preset] -ErrorAction SilentlyContinue }
        $n++
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-AppLog "DNS -> $preset ($n adapters)"
    return $n
}
function Measure-DnsPresets {
    $res = [ordered]@{}; $names = @('www.google.com', 'www.wikipedia.org', 'github.com', 'www.microsoft.com')
    $keys = @($DnsPresets.Keys | Where-Object { $_ -ne 'auto' }); $i = 0
    foreach ($k in $keys) {
        $i++; Set-TK (100.0 * $i / $keys.Count) (T 'dns.measuring') $k
        $times = @()
        foreach ($n in $names) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try { $null = Resolve-DnsName -Name $n -Server $DnsPresets[$k][0] -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop; $sw.Stop(); $times += $sw.Elapsed.TotalMilliseconds } catch {}
        }
        if ($times.Count -gt 0) { $res[$k] = [math]::Round((@($times | Sort-Object) | Select-Object -First ([math]::Max(1, $times.Count - 1)) | Measure-Object -Average).Average) } else { $res[$k] = -1 }
    }
    return $res
}

# ---------- Απεγκατάσταση προγραμμάτων ----------
function Get-InstalledPrograms {
    $out = @{}
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($k in $keys) {
        foreach ($s in @(Get-ChildItem -Path $k -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $s.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.DisplayName -or -not $p.UninstallString) { continue }
            if ("$($p.SystemComponent)" -eq '1' -or $p.ParentKeyName -or "$($p.ReleaseType)" -match 'Update|Hotfix') { continue }
            $id = "$($p.DisplayName)|$($p.DisplayVersion)"
            if ($out.ContainsKey($id)) { continue }
            $date = $null; if ("$($p.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$') { try { $date = [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3]) } catch {} }
            $size = 0.0; if ($p.EstimatedSize) { $size = [double]$p.EstimatedSize * 1KB }
            $out[$id] = [pscustomobject]@{ Name = "$($p.DisplayName)"; Publisher = "$($p.Publisher)"; Version = "$($p.DisplayVersion)"; Date = $date; Size = $size
                                          Uninstall = "$($p.UninstallString)"; Quiet = "$($p.QuietUninstallString)"; Location = "$($p.InstallLocation)".Trim('"').TrimEnd('\'); Key = "$($s.PSPath)" }
        }
    }
    return @($out.Values | Sort-Object Name)
}
function Split-CommandLine([string]$cmd) {
    $cmd = $cmd.Trim()
    if ($cmd.StartsWith('"')) { $e = $cmd.IndexOf('"', 1); if ($e -gt 0) { return @($cmd.Substring(1, $e - 1), $cmd.Substring($e + 1).Trim()) } }
    $m = [regex]::Match($cmd, '^(.+?\.exe)\b(.*)$', 'IgnoreCase')
    if ($m.Success) { return @($m.Groups[1].Value.Trim(), $m.Groups[2].Value.Trim()) }
    return @($cmd, '')
}
function Invoke-UninstallCore($app) {
    Set-TK -1 ((T 'un.running1') -f $app.Name) ''
    $cmd = $app.Uninstall
    if ($cmd -match 'msiexec' -and $cmd -match '(\{[0-9A-Fa-f\-]{36}\})') { $exe = "$env:WINDIR\System32\msiexec.exe"; $arg = "/x $($matches[1])" }
    else { $parts = Split-CommandLine $cmd; $exe = $parts[0]; $arg = $parts[1] }
    $code = -1
    try {
        if ($arg) { $pr = Start-Process -FilePath $exe -ArgumentList $arg -PassThru -ErrorAction Stop } else { $pr = Start-Process -FilePath $exe -PassThru -ErrorAction Stop }
        $pr.WaitForExit(); $code = $pr.ExitCode
        # πολλά uninstallers ξεκινούν ένα αντίγραφο του εαυτού τους και κλείνουν αμέσως: περιμένουμε λίγο ακόμα
        Start-Sleep -Seconds 3
        $t = 0; while ($t -lt 120 -and (Get-Process -Name 'Au_', 'Un_A', 'unins*', 'uninstall*' -ErrorAction SilentlyContinue)) { Start-Sleep -Seconds 2; $t += 2 }
    } catch { Add-TKLog ((T 'un.fail') -f $app.Name) 'warn'; return @{ Code = -1; Gone = $false; Leftovers = @() } }
    $gone = -not (Test-Path -LiteralPath ($app.Key -replace '^Microsoft\.PowerShell\.Core\\Registry::', 'Registry::'))
    Write-AppLog "Uninstall $($app.Name): code=$code gone=$gone"
    $left = @(Find-AppLeftovers $app)
    Set-TK 100 ((T 'un.done1') -f $app.Name) ''
    return @{ Code = $code; Gone = $gone; Leftovers = $left }
}
function Get-FolderSize([string]$p) { $s = 0.0; foreach ($f in @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)) { $s += $f.Length }; return $s }
function Find-AppLeftovers($app) {
    $out = @()
    # "Notepad++ (64-bit x64)" -> "Notepad++", "Python 3.12.7 (64-bit)" -> "Python": αφαιρούμε παρενθέσεις, αρχιτεκτονική και έκδοση
    $base = "$($app.Name)"
    for ($k = 0; $k -lt 3; $k++) { $base = ($base -replace '\s*\([^)]*\)\s*$', '' -replace '\s+(x64|x86|64-bit|32-bit|amd64)$', '' -replace '\s+v?\d+(\.\d+)*$', '').Trim() }
    $names = @($base, "$($app.Name)".Trim()) | Where-Object { $_ -and $_.Length -ge 3 } | Select-Object -Unique
    $pub = ("$($app.Publisher)" -replace ',?\s*(Inc|LLC|Ltd|GmbH|Corp(oration)?|Co\.?)\.?$', '').Trim()
    # 1) ο φάκελος εγκατάστασης: σίγουρα του προγράμματος
    if ($app.Location -and (Test-Path -LiteralPath $app.Location) -and $app.Location -notmatch '^[A-Z]:\\?$|\\Windows$|\\Program Files( \(x86\))?$') {
        $out += [pscustomobject]@{ Type = 'dir'; Path = $app.Location; Size = (Get-FolderSize $app.Location); Sure = $true }
    }
    # 2) φάκελοι δεδομένων με ΑΚΡΙΒΩΣ το όνομα του προγράμματος (ή Εκδότης\Πρόγραμμα)
    $roots = @($env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($r in $roots) {
        foreach ($n in $names) {
            foreach ($cand in @((Join-Path $r $n), $(if ($pub) { Join-Path (Join-Path $r $pub) $n }))) {
                if ($cand -and (Test-Path -LiteralPath $cand) -and @($out | Where-Object { $_.Path -eq $cand }).Count -eq 0) {
                    $out += [pscustomobject]@{ Type = 'dir'; Path = $cand; Size = (Get-FolderSize $cand); Sure = $false }
                }
            }
        }
    }
    # 3) κλειδιά μητρώου Software\Εκδότης\Πρόγραμμα ή Software\Πρόγραμμα
    foreach ($h in 'HKCU:\Software', 'HKLM:\SOFTWARE') {
        foreach ($n in $names) {
            foreach ($cand in @((Join-Path $h $n), $(if ($pub) { Join-Path (Join-Path $h $pub) $n }))) {
                if ($cand -and (Test-Path -LiteralPath $cand)) { $out += [pscustomobject]@{ Type = 'reg'; Path = $cand; Size = 0; Sure = $false } }
            }
        }
    }
    return $out
}
function Remove-AppLeftovers($items) {
    $items = @($items); $ok = 0; $fail = 0
    $bdir = Join-Path $CoreData ('backup\uninstall-{0}' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    Add-Type -AssemblyName Microsoft.VisualBasic
    foreach ($x in $items) {
        try {
            if ($x.Type -eq 'dir') { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($x.Path, 'OnlyErrorDialogs', 'SendToRecycleBin') }
            else {
                New-Item -ItemType Directory -Path $bdir -Force | Out-Null
                $native = $x.Path -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
                & reg.exe export $native (Join-Path $bdir ('{0}.reg' -f ([guid]::NewGuid().ToString('N')))) /y 2>&1 | Out-Null
                Remove-Item -LiteralPath $x.Path -Recurse -Force -ErrorAction Stop
            }
            $ok++; Add-TKLog ((T 'un.left.ok') -f $x.Path) 'ok'
        } catch { $fail++; Add-TKLog ((T 'un.left.fail') -f $x.Path) 'warn' }
    }
    Write-AppLog "Uninstall leftovers removed: $ok (fail $fail)"
    return @{ Ok = $ok; Fail = $fail }
}

# ---------- Ιστορικό κρασαρισμάτων ----------
$BugChecks = @{ '0000007E' = 'driver'; '1000007E' = 'driver'; '000000D1' = 'driver'; '0000009F' = 'power'; '00000133' = 'dpc'; '00000124' = 'whea'; '0000001A' = 'memory'; '00000050' = 'memory'; '000000EF' = 'process'; '00000116' = 'gpu'; '00000117' = 'gpu'; '00000139' = 'driver'; '0000003B' = 'driver'; '000000A0' = 'power'; '00000154' = 'storage'; '0000007A' = 'storage' }
function Get-CrashHistory([int]$days = 30) {
    Set-TK -1 (T 'cr.loading') ''
    $since = (Get-Date).AddDays(-$days)
    $bsod = @()
    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since } -ErrorAction SilentlyContinue)) {
        $txt = "$($e.Message) $(@($e.Properties | ForEach-Object { $_.Value }) -join ' ')"
        $code = ''; if ($txt -match '0x([0-9a-fA-F]{8})') { $code = $matches[1].ToUpper() }
        $kind = 'other'; if ($BugChecks.ContainsKey($code)) { $kind = $BugChecks[$code] }
        $bsod += [pscustomobject]@{ When = $e.TimeCreated; Code = "0x$code"; Kind = $kind }
    }
    $power = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue | ForEach-Object { $_.TimeCreated })
    $apps = @{}
    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error', 'Application Hang'; StartTime = $since } -ErrorAction SilentlyContinue)) {
        $p = @($e.Properties | ForEach-Object { "$($_.Value)" })
        $name = "$($p[0])"; if (-not $name) { continue }
        $mod = ''; if ($e.Id -eq 1000 -and $p.Count -gt 3) { $mod = "$($p[3])" }
        if (-not $apps.ContainsKey($name)) { $apps[$name] = [pscustomobject]@{ Name = $name; Crashes = 0; Hangs = 0; Last = $e.TimeCreated; Modules = @{} } }
        $a = $apps[$name]
        if ($e.Id -eq 1002) { $a.Hangs++ } else { $a.Crashes++ }
        if ($e.TimeCreated -gt $a.Last) { $a.Last = $e.TimeCreated }
        if ($mod) { $a.Modules[$mod] = 1 + [int]$a.Modules[$mod] }
    }
    $appList = foreach ($a in $apps.Values) {
        $top = ($a.Modules.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        $hint = ''; if ("$top" -match '^(nvlddmkm|nvwgf2um|nvoglv|amdkmdag|atikmdag|atidxx|amdxx|igdkmd|igd10|igdumd)') { $hint = 'gpu' } elseif ("$top" -match '^(ntdll|KERNELBASE)\.dll$') { $hint = 'generic' }
        [pscustomobject]@{ Name = $a.Name; Crashes = $a.Crashes; Hangs = $a.Hangs; Last = $a.Last; Module = "$top"; Hint = $hint }
    }
    $dumps = @(Get-ChildItem -Path "$env:WINDIR\Minidump" -Filter '*.dmp' -ErrorAction SilentlyContinue).Count
    Set-TK 100 (T 'cr.loaded') ''
    return @{ Days = $days; Bsod = @($bsod | Sort-Object When -Descending); Power = @($power); Apps = @($appList | Sort-Object @{ e = { $_.Crashes + $_.Hangs }; Descending = $true } | Select-Object -First 15); Dumps = $dumps }
}

# ---------- Συσκευές & οδηγοί ----------
function Get-DeviceReport {
    Set-TK -1 (T 'dv.loading') ''
    $prob = @()
    foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -notin 0, 45 })) {
        $prob += [pscustomobject]@{ Name = "$($d.Name)"; Code = [int]$d.ConfigManagerErrorCode; Class = "$($d.PNPClass)"; Id = "$($d.DeviceID)" }
    }
    $drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceName -and $_.DriverDate })
    $gpu = @($drivers | Where-Object { "$($_.DeviceClass)" -eq 'DISPLAY' } | ForEach-Object { [pscustomobject]@{ Name = "$($_.DeviceName)"; Version = "$($_.DriverVersion)"; Date = [datetime]$_.DriverDate; Vendor = "$($_.Manufacturer)" } })
    $limit = (Get-Date).AddYears(-5)
    $old = @($drivers | Where-Object { "$($_.DeviceClass)" -in 'DISPLAY', 'NET', 'MEDIA', 'BLUETOOTH', 'SCSIADAPTER', 'HDC', 'USB' -and [datetime]$_.DriverDate -lt $limit -and "$($_.DriverProviderName)" -notmatch '^Microsoft' } |
        Sort-Object DriverDate | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ Name = "$($_.DeviceName)"; Date = [datetime]$_.DriverDate; Provider = "$($_.DriverProviderName)"; Version = "$($_.DriverVersion)" } })
    $unsigned = @($drivers | Where-Object { $_.IsSigned -eq $false } | ForEach-Object { "$($_.DeviceName)" } | Select-Object -Unique -First 10)
    Set-TK 100 (T 'dv.loaded') ''
    return @{ Problems = $prob; Gpu = $gpu; Old = $old; Unsigned = $unsigned }
}

# ---------- Windows Update (μόνο ανάγνωση και απόκρυψη) ----------
function Get-WuInfo {
    Set-TK -1 (T 'wu.loading') ''
    $s = New-Object -ComObject Microsoft.Update.Session
    $se = $s.CreateUpdateSearcher()
    $hist = @()
    try {
        $n = [math]::Min(50, $se.GetTotalHistoryCount())
        if ($n -gt 0) {
            foreach ($h in @($se.QueryHistory(0, $n))) {
                if (-not $h.Title) { continue }
                $hr = ''; if ($h.HResult -ne 0) { $hr = '0x{0:X8}' -f [int]$h.HResult }
                $hist += [pscustomobject]@{ Title = "$($h.Title)"; Date = [datetime]$h.Date; Result = [int]$h.ResultCode; HResult = $hr }
            }
        }
    } catch {}
    Set-TK -1 (T 'wu.searching') ''
    $pending = @(); $hidden = @()
    try {
        foreach ($u in @($se.Search('IsInstalled=0').Updates)) {
            $kb = (@($u.KBArticleIDs) | ForEach-Object { "KB$_" }) -join ', '
            $cat = (@($u.Categories) | ForEach-Object { "$($_.Name)" } | Select-Object -First 2) -join ', '
            $o = [pscustomobject]@{ Title = "$($u.Title)"; KB = $kb; Id = "$($u.Identity.UpdateID)"; Size = [double]$u.MaxDownloadSize; Cat = $cat; Downloaded = [bool]$u.IsDownloaded }
            if ($u.IsHidden) { $hidden += $o } else { $pending += $o }
        }
    } catch { Add-TKLog ((T 'wu.searchfail') -f $_.Exception.Message) 'warn' }
    Set-TK 100 (T 'wu.loaded') ''
    return @{ History = $hist; Pending = $pending; Hidden = $hidden }
}
function Set-WuHidden([string]$id, [bool]$hide) {
    $s = New-Object -ComObject Microsoft.Update.Session
    $r = $s.CreateUpdateSearcher().Search("UpdateID='$id'")
    foreach ($u in @($r.Updates)) { $u.IsHidden = $hide }
    Write-AppLog "WU hide=$hide $id"
    return $true
}

# ---------- Διπλά αρχεία ----------
$DupSkip = '\\(Windows|Program Files|Program Files \(x86\)|ProgramData|AppData|\$Recycle\.Bin|System Volume Information|node_modules|\.git|\.venv|venv|site-packages|__pycache__|\.gradle|\.m2|\.nuget|\.cache|bin\\Debug|bin\\Release|obj)(\\|$)'
function Get-PartialHash([string]$p) {
    try {
        $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite')
        try { $buf = New-Object byte[] 65536; $n = $fs.Read($buf, 0, $buf.Length); $md5 = [Security.Cryptography.MD5]::Create(); return [BitConverter]::ToString($md5.ComputeHash($buf, 0, $n)) } finally { $fs.Dispose() }
    } catch { return $null }
}
function Find-DuplicatesCore([string]$root, [double]$minSize) {
    Set-TK -1 (T 'du.scanning') $root
    $bySize = @{}; $n = 0
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $n++
        if ($_.Length -ge $minSize -and $_.FullName -notmatch $DupSkip -and -not (Test-CriticalFile $_.FullName)) {
            $k = [string]$_.Length; if (-not $bySize.ContainsKey($k)) { $bySize[$k] = New-Object System.Collections.Generic.List[object] }
            $bySize[$k].Add($_)
        }
        if ($n % 1000 -eq 0) { Set-TK -1 $null ((T 'du.progress') -f $n) }
    }
    $cands = @($bySize.Values | Where-Object { $_.Count -gt 1 })
    $groups = @(); $ci = 0
    foreach ($c in $cands) {
        $ci++; if ($ci % 20 -eq 0) { Set-TK (100.0 * $ci / $cands.Count) (T 'du.hashing') "$ci/$($cands.Count)" }
        $byPart = @{}
        foreach ($f in $c) { $h = Get-PartialHash $f.FullName; if ($h) { if (-not $byPart.ContainsKey($h)) { $byPart[$h] = @() }; $byPart[$h] += $f } }
        foreach ($pg in @($byPart.Values | Where-Object { $_.Count -gt 1 })) {
            $byFull = @{}
            foreach ($f in $pg) { try { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash; if (-not $byFull.ContainsKey($h)) { $byFull[$h] = @() }; $byFull[$h] += $f } catch {} }
            foreach ($fg in @($byFull.Values | Where-Object { $_.Count -gt 1 })) {
                $files = @($fg | Sort-Object LastWriteTime | ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Date = $_.LastWriteTime } })
                $size = [double]$fg[0].Length
                $groups += [pscustomobject]@{ Size = $size; Count = $files.Count; Wasted = $size * ($files.Count - 1); Files = $files }
            }
        }
    }
    $top = @($groups | Sort-Object Wasted -Descending | Select-Object -First 60)
    $wasted = 0.0; foreach ($g in $groups) { $wasted += $g.Wasted }
    Set-TK 100 ((T 'du.done') -f $groups.Count, (Format-Size $wasted)) ''
    return @{ Groups = $top; Total = $groups.Count; Wasted = $wasted; Root = $root; Scanned = $n }
}
