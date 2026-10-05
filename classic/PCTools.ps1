param([switch]$Auto)
# John's Toolkit by nmx88 - classic console mode (Windows 10/11)
# ΜΗΝ το ανοίγεις απευθείας. Ξεκίνα πάντα από το Start-PCTools.bat

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
# Κάποιες εντολές των Windows (π.χ. Get-ScheduledTask) διαβάζουν μόνο τη γενική ρύθμιση
$global:ErrorActionPreference = 'SilentlyContinue'
$global:ProgressPreference = 'SilentlyContinue'
if (-not $ToolDir) { $ToolDir = $PSScriptRoot }
$TaskName = 'PCTools-WeeklyCleanup'
$DataDir  = Join-Path $ToolDir 'data'
$LogDir   = Join-Path $ToolDir 'logs'
if ($AppRoot) { $DataDir = Join-Path $AppRoot 'data'; $LogDir = Join-Path $AppRoot 'logs' }
$State    = @{ NeedsRestart = $false; ScreenInit = $false; LastLines = 0; Step = @{ Status = 'ok'; Note = ''; Freed = 0.0 } }

# ======================================================================
#  ΘΕΜΑ & ΒΟΗΘΗΤΙΚΑ ΕΜΦΑΝΙΣΗΣ
# ======================================================================
$Theme = @{ Accent = 'Cyan'; Title = 'White'; Dim = 'DarkGray'; Text = 'Gray'; Ok = 'Green'; Warn = 'Yellow'; Bad = 'Red'; SelBg = 'DarkCyan'; SelFg = 'White'; Logo = 'Cyan' }
$GrCulture = [Globalization.CultureInfo]::GetCultureInfo('el-GR')

function Get-FreeGB { [math]::Round((Get-PSDrive C).Free / 1GB, 2) }
function Get-FreeBytes { [double](Get-PSDrive C).Free }
function Write-Step([string]$t) { Write-Host "`n  ► $t" -ForegroundColor $Theme.Accent }
function Write-Ok([string]$t = 'Ολοκληρώθηκε') { Write-Host "     $t" -ForegroundColor $Theme.Ok }
function Write-Note([string]$t) { Write-Host "     $t" -ForegroundColor $Theme.Warn }
function Write-Bad([string]$t) { Write-Host "     $t" -ForegroundColor $Theme.Bad }
function Format-Size([double]$b) {
    if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) }
    elseif ($b -ge 1MB) { '{0:N1} MB' -f ($b / 1MB) }
    else { '{0:N0} KB' -f ($b / 1KB) }
}
function Format-Time([double]$sec) {
    $ts = [TimeSpan]::FromSeconds([Math]::Max(0, $sec))
    if ($ts.TotalHours -ge 1) { return ('{0}:{1:00}:{2:00}' -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds) }
    return ('{0}:{1:00}' -f $ts.Minutes, $ts.Seconds)
}
function Get-Width { $w = 100; try { $w = [Console]::WindowWidth } catch {}; if ($w -lt 50) { $w = 80 }; return ($w - 1) }

function Initialize-Console {
    try { $host.UI.RawUI.WindowTitle = 'John''s Toolkit (classic)' } catch {}
    try { $host.UI.RawUI.BackgroundColor = 'Black'; $host.UI.RawUI.ForegroundColor = 'Gray' } catch {}
    if (-not $env:WT_SESSION) {
        try {
            $raw = $host.UI.RawUI; $max = $raw.MaxPhysicalWindowSize
            $wW = [Math]::Min(112, $max.Width); $wH = [Math]::Min(38, $max.Height)
            $buf = $raw.BufferSize
            if ($buf.Width -lt $wW) { $raw.BufferSize = New-Object Management.Automation.Host.Size($wW, [Math]::Max($buf.Height, 3000)) }
            $raw.WindowSize = New-Object Management.Automation.Host.Size($wW, $wH)
        } catch {}
    }
    Clear-Host
}

function Wrap-Text([string]$Text, [int]$Width, [string]$Indent = '') {
    $max = [Math]::Max(10, $Width - $Indent.Length)
    $out = New-Object System.Collections.Generic.List[string]
    $line = ''
    foreach ($word in ($Text -split ' ')) {
        if ($word -eq '') { continue }
        while ($word.Length -gt $max) {
            if ($line) { $out.Add($Indent + $line); $line = '' }
            $out.Add($Indent + $word.Substring(0, $max)); $word = $word.Substring($max)
        }
        if (-not $line) { $line = $word }
        elseif (($line.Length + 1 + $word.Length) -le $max) { $line += ' ' + $word }
        else { $out.Add($Indent + $line); $line = $word }
    }
    if ($line -or $out.Count -eq 0) { $out.Add($Indent + $line) }
    return $out.ToArray()
}

# Μια γραμμή οθόνης: είτε T/T2 (δύο κομμάτια) είτε S = λίστα @(κείμενο, χρώμα)
function L([string]$T = '', [string]$F = 'Gray', $B = $null, [string]$T2 = '', $F2 = $null) {
    [pscustomobject]@{ T = $T; F = $F; B = $B; T2 = $T2; F2 = $F2; S = $null }
}
function Seg($segments, $B = $null) {
    [pscustomobject]@{ T = ''; F = 'Gray'; B = $B; T2 = ''; F2 = $null; S = @($segments) }
}
function Get-Bar([double]$pct, [int]$width = 20) {
    $p = [Math]::Min(100, [Math]::Max(0, $pct))
    $fill = [int][Math]::Round($width * $p / 100)
    return @(('█' * $fill), ('░' * ($width - $fill)))
}
function Get-GaugeLine([string]$label, [double]$pct, [string]$text, [int]$warnAt = 80, [int]$badAt = 90) {
    $col = $Theme.Ok; if ($pct -ge $badAt) { $col = $Theme.Bad } elseif ($pct -ge $warnAt) { $col = $Theme.Warn }
    $bar = Get-Bar $pct 20
    return (Seg @(@(('  {0,-10} ' -f $label), $Theme.Dim), @($bar[0], $col), @($bar[1], 'DarkGray'), @((' {0,3:0}%  ' -f $pct), $col), @($text, $Theme.Text)))
}

function Write-Screen($lines) {
    $w = Get-Width
    if (-not $State.ScreenInit) { Clear-Host; $State.ScreenInit = $true; $State.LastLines = 0 }
    try { [Console]::SetCursorPosition(0, 0) } catch {}
    foreach ($l in $lines) {
        if ($l.S) { $segs = @($l.S) }
        else { $f2 = $l.F; if ($l.F2) { $f2 = $l.F2 }; $segs = @(@("$($l.T)", $l.F), @("$($l.T2)", $f2)) }
        $used = 0
        foreach ($sg in $segs) {
            $t = "$($sg[0])"
            if ($used -ge $w) { break }
            if ($used + $t.Length -gt $w) { $t = $t.Substring(0, [Math]::Max(0, $w - $used - 1)) + '…' }
            if ($t.Length -eq 0) { continue }
            $bg = $l.B; if ($sg.Count -gt 2 -and $sg[2]) { $bg = $sg[2] }
            $fc = $sg[1]; if (-not $fc) { $fc = 'Gray' }
            if ($bg) { Write-Host $t -ForegroundColor $fc -BackgroundColor $bg -NoNewline } else { Write-Host $t -ForegroundColor $fc -NoNewline }
            $used += $t.Length
        }
        $pad = ''.PadRight([Math]::Max(0, $w - $used))
        if ($l.B) { Write-Host $pad -BackgroundColor $l.B } else { Write-Host $pad }
    }
    $blank = ''.PadRight($w)
    for ($i = $lines.Count; $i -lt $State.LastLines; $i++) { Write-Host $blank }
    $State.LastLines = $lines.Count
}

function Write-Box([string]$title, $rows, [int]$width = 64) {
    $inner = $width - 4
    Write-Host ''
    Write-Host ('  ┌' + ('─' * ($width - 2)) + '┐') -ForegroundColor $Theme.Dim
    if ($title) {
        Write-Host '  │ ' -ForegroundColor $Theme.Dim -NoNewline
        Write-Host ($title.PadRight($inner)) -ForegroundColor $Theme.Title -NoNewline
        Write-Host ' │' -ForegroundColor $Theme.Dim
        Write-Host ('  ├' + ('─' * ($width - 2)) + '┤') -ForegroundColor $Theme.Dim
    }
    foreach ($r in $rows) {
        if ($r -eq '-') { Write-Host ('  ├' + ('─' * ($width - 2)) + '┤') -ForegroundColor $Theme.Dim; continue }
        $t = "$($r[0])"; if ($t.Length -gt $inner) { $t = $t.Substring(0, $inner - 1) + '…' }
        $c = 'Gray'; if ($r -is [array] -and $r.Count -gt 1 -and $r[1]) { $c = $r[1] }
        Write-Host '  │ ' -ForegroundColor $Theme.Dim -NoNewline
        Write-Host ($t.PadRight($inner)) -ForegroundColor $c -NoNewline
        Write-Host ' │' -ForegroundColor $Theme.Dim
    }
    Write-Host ('  └' + ('─' * ($width - 2)) + '┘') -ForegroundColor $Theme.Dim
}

function Write-Header([string]$title) {
    Clear-Host
    $w = [Math]::Min(76, (Get-Width) - 2)
    $clock = (Get-Date).ToString('ddd dd/MM · HH:mm', $GrCulture)
    Write-Host ''
    Write-Host '  JOHN''S TOOLKIT  ›  ' -ForegroundColor $Theme.Dim -NoNewline
    Write-Host $title -ForegroundColor $Theme.Title -NoNewline
    $gap = $w - 20 - $title.Length - $clock.Length
    if ($gap -gt 1) { Write-Host (''.PadRight($gap)) -NoNewline; Write-Host $clock -ForegroundColor $Theme.Dim } else { Write-Host '' }
    Write-Host ('  ' + ('═' * ($w - 2))) -ForegroundColor $Theme.Accent
}

# ----- Μπάρα προόδου με χρόνο και εκτίμηση -----
$Prog = @{ Start = (Get-Date); Label = ''; LastDraw = [datetime]::MinValue; Spin = 0; Pct = -1 }
function Set-TaskbarProgress([double]$pct) {
    if (-not $env:WT_SESSION) { return }
    $e = [char]27; $bel = [char]7
    if ($pct -lt 0) { [Console]::Write("$e]9;4;3;0$bel") }
    elseif ($pct -gt 100) { [Console]::Write("$e]9;4;0;0$bel") }
    else { [Console]::Write("$e]9;4;1;$([int]$pct)$bel") }
}
function Start-Progress([string]$label) {
    $Prog.Start = Get-Date; $Prog.Label = $label; $Prog.LastDraw = [datetime]::MinValue; $Prog.Spin = 0; $Prog.Pct = -1
    try { [Console]::CursorVisible = $false } catch {}
    Write-Host "     $label" -ForegroundColor $Theme.Text
}
function Update-Progress([double]$pct = -1, [string]$detail = '', [switch]$Force) {
    $now = Get-Date
    if (-not $Force -and ($now - $Prog.LastDraw).TotalMilliseconds -lt 150) { return }
    $Prog.LastDraw = $now
    $el = ($now - $Prog.Start).TotalSeconds
    $w = Get-Width
    $segs = @()
    if ($pct -ge 0) {
        $p = [Math]::Min(100, $pct); $Prog.Pct = $p
        $bar = Get-Bar $p 28
        $segs += , @($bar[0], $Theme.Ok); $segs += , @($bar[1], 'DarkGray')
        $txt = (' {0,3:0}%  {1}' -f $p, (Format-Time $el))
        if ($p -ge 2 -and $p -lt 100 -and $el -ge 3) { $txt += ' · ~' + (Format-Time ($el * (100 - $p) / $p)) + ' ακόμα' }
        $segs += , @($txt, $Theme.Title)
        Set-TaskbarProgress $p
    } else {
        $frames = @('●○○○', '○●○○', '○○●○', '○○○●', '○○●○', '○●○○')
        $Prog.Spin = ($Prog.Spin + 1) % $frames.Count
        $segs += , @($frames[$Prog.Spin], $Theme.Accent)
        $segs += , @(("  " + (Format-Time $el)), $Theme.Title)
        Set-TaskbarProgress -1
    }
    if ($detail) { $segs += , @("  ·  $detail", $Theme.Dim) }
    Write-Host "`r     " -NoNewline
    $used = 5
    foreach ($sg in $segs) {
        $t = $sg[0]; if ($used + $t.Length -gt $w) { $t = $t.Substring(0, [Math]::Max(0, $w - $used - 1)) }
        $fc = $sg[1]; if (-not $fc) { $fc = 'Gray' }
        Write-Host $t -ForegroundColor $fc -NoNewline; $used += $t.Length
    }
    Write-Host (''.PadRight([Math]::Max(0, $w - $used))) -NoNewline
}
function Stop-Progress([string]$msg = '', [string]$color = 'Green') {
    if ($Prog.Pct -ge 0) { Update-Progress 100 '' -Force } else { Update-Progress -1 '' -Force }
    $el = ((Get-Date) - $Prog.Start).TotalSeconds
    Write-Host ''
    $t = "Ολοκληρώθηκε σε $(Format-Time $el)"; if ($msg) { $t += " · $msg" }
    foreach ($l in @(Wrap-Text $t ((Get-Width) - 2) '     ')) { Write-Host $l -ForegroundColor $color }
    Set-TaskbarProgress 101
    try { [Console]::CursorVisible = $true } catch {}
}

function Send-Toast([string]$title, [string]$text) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $t = [System.Security.SecurityElement]::Escape($title); $b = [System.Security.SecurityElement]::Escape($text)
        $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$t</text><text>$b</text></binding></visual></toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch {}
}

# ----- Διαγραφή αρχείων με μπάρα προόδου -----
function Remove-WithProgress([string[]]$paths, [string]$label) {
    Start-Progress $label
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($p in $paths) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File -Force)) {
            $files.Add($f)
            if ($files.Count % 300 -eq 0) { Update-Progress -1 "μέτρηση: $($files.Count) αρχεία" }
        }
    }
    $total = $files.Count; $done = 0; $freed = 0.0
    for ($i = 0; $i -lt $total; $i++) {
        $f = $files[$i]
        try { $len = $f.Length; [IO.File]::Delete($f.FullName); $done++; $freed += $len }
        catch { try { $f.Attributes = 'Normal'; [IO.File]::Delete($f.FullName); $done++; $freed += $len } catch {} }
        if ($i % 25 -eq 0) { Update-Progress (100.0 * ($i + 1) / $total) ('{0}/{1} αρχεία · {2}' -f ($i + 1), $total, (Format-Size $freed)) }
    }
    foreach ($p in $paths) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $p -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending)) {
            try { [IO.Directory]::Delete($d.FullName, $false) } catch {}
        }
    }
    if ($total -eq 0) { Update-Progress 100 '' -Force; Stop-Progress 'δεν υπήρχαν αρχεία για καθαρισμό'; return }
    $skip = $total - $done
    $State.Step.Freed += $freed
    $m = "σβήστηκαν $done αρχεία ($(Format-Size $freed))"
    if ($skip -gt 0) { $m += ", $skip ήταν σε χρήση και παραλείφθηκαν" }
    Stop-Progress $m
}

# ----- Εκτέλεση εργαλείου των Windows (DISM, SFC, defrag) με μπάρα προόδου -----
function Read-SharedText([string]$path, $Encoding = $null) {
    try {
        $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $fs.Close()
        $bytes = $ms.ToArray()
    } catch { return '' }
    if ($bytes.Length -eq 0) { return '' }
    if ($Encoding) { return $Encoding.GetString($bytes) }
    $zeros = 0; foreach ($b in $bytes) { if ($b -eq 0) { $zeros++ } }
    if ($zeros -gt ($bytes.Length / 4)) { return ([Text.Encoding]::Unicode.GetString($bytes) -replace "`0", '') }
    $enc = [Text.Encoding]::Default; try { $enc = [Console]::OutputEncoding } catch {}
    return $enc.GetString($bytes)
}
function Get-ExitCodeText([int]$code) {
    $hex = '0x' + $code.ToString('X8')
    $map = @{
        '0xFFFFFFFF' = 'Δεν ήταν δυνατή η εκκίνηση του εργαλείου των Windows (ίσως το μπλοκάρει antivirus ή λείπει).'
        '0x800F0806' = 'Τα Windows περιμένουν επανεκκίνηση για να ολοκληρώσουν μια ενημέρωση. Κάνε επανεκκίνηση και ξανατρέξε το.'
        '0x800F081F' = 'Δεν βρέθηκαν τα αρχεία επιδιόρθωσης. Συνήθως λύνεται με Windows Update και επανάληψη.'
        '0x800F0906' = 'Δεν ήταν δυνατή η λήψη αρχείων επιδιόρθωσης. Έλεγξε τη σύνδεση στο ίντερνετ.'
        '0x80070070' = 'Δεν υπάρχει αρκετός ελεύθερος χώρος στον δίσκο.'
        '0x800705B4' = 'Η εργασία άργησε πολύ και σταμάτησε. Δοκίμασε ξανά.'
        '0x80070005' = 'Δεν επιτράπηκε η πρόσβαση (ίσως το μπλοκάρει άλλο πρόγραμμα, π.χ. antivirus).'
        '0x80073D02' = 'Το πρόγραμμα ήταν ανοιχτό. Κλείσε το και ξαναδοκίμασε.'
        '0x00000BC2' = 'Ολοκληρώθηκε, αλλά χρειάζεται επανεκκίνηση.'
        '0x00000652' = 'Τρέχει ήδη άλλη εγκατάσταση. Περίμενε να τελειώσει και ξαναδοκίμασε.'
        '0x00000642' = 'Η εγκατάσταση ακυρώθηκε.'
        '0x00000643' = 'Το πρόγραμμα εγκατάστασης απέτυχε (γενικό σφάλμα του ίδιου του προγράμματος).'
        '0x8A15002B' = 'Δεν βρέθηκε κατάλληλη ενημέρωση για αυτό το PC. Συνήθως ενημερώνεται μέσα από το ίδιο το πρόγραμμα.'
        '0x8A150014' = 'Το πακέτο δεν βρέθηκε στο winget.'
        '0x8A150101' = 'Το πρόγραμμα ήταν ανοιχτό. Κλείσε το και ξαναδοκίμασε.'
        '0x8A150109' = 'Ενημερώθηκε, αλλά χρειάζεται επανεκκίνηση για να ολοκληρωθεί.'
    }
    if ($map.ContainsKey($hex)) { return "$($map[$hex]) ($hex)" }
    return "Τερμάτισε με κωδικό $hex."
}
function Test-ExitOk([int]$code) { return ($code -eq 0 -or $code -eq 3010 -or ('0x' + $code.ToString('X8')) -eq '0x8A150109') }

# Τρέχει ένα εργαλείο κρυφά, δείχνει μπάρα/ένδειξη και επιστρέφει κωδικό + έξοδο
function Invoke-Native([string]$exe, [string]$arguments, [string]$detail = '', $Encoding = $null) {
    $out = Join-Path ([IO.Path]::GetTempPath()) ('pctools_' + [guid]::NewGuid().ToString('N') + '.txt')
    $err = "$out.err"
    $sp = @{ FilePath = $exe; NoNewWindow = $true; PassThru = $true; RedirectStandardOutput = $out; RedirectStandardError = $err }
    if ($arguments) { $sp.ArgumentList = $arguments }
    $t0 = Get-Date
    $p = $null
    try { $p = Start-Process @sp -ErrorAction Stop } catch { $p = $null }
    if (-not $p) { return [pscustomobject]@{ Code = -1; Output = "Δεν ήταν δυνατή η εκτέλεση του $exe"; Seconds = 0 } }
    $null = $p.Handle
    $pct = -1
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 250
        $txt = Read-SharedText $out $Encoding
        $m = [regex]::Matches($txt, '(\d{1,3})(?:[.,]\d+)?\s?%')
        if ($m.Count -gt 0) { $v = [double]$m[$m.Count - 1].Groups[1].Value; if ($v -le 100) { $pct = $v } }
        Update-Progress $pct $detail
    }
    $p.WaitForExit()
    $code = 0; if ($null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
    $txt = (Read-SharedText $out $Encoding) + "`n" + (Read-SharedText $err $Encoding)
    Remove-Item $out, $err -Force
    return [pscustomobject]@{ Code = $code; Output = $txt; Seconds = ((Get-Date) - $t0).TotalSeconds }
}

function Invoke-NativeProgress([string]$exe, [string]$arguments, [string]$label) {
    Start-Progress $label
    $r = Invoke-Native $exe $arguments
    $lines = @($r.Output -split "`r?`n" | ForEach-Object { ($_ -split "`r")[-1].Trim() } | Where-Object { $_ -and $_ -notmatch '%' -and $_ -notmatch '^\[' })
    if (Test-ExitOk $r.Code) {
        Stop-Progress 'επιτυχώς'
        if ($r.Code -ne 0) { $State.Step.Status = 'warn'; $State.Step.Note = Get-ExitCodeText $r.Code; $State.NeedsRestart = $true }
    } else {
        $txt = Get-ExitCodeText $r.Code
        Stop-Progress $txt 'Yellow'
        $State.Step.Status = 'warn'; $State.Step.Note = $txt
    }
    foreach ($l in @($lines | Select-Object -Last 3)) { foreach ($x in @(Wrap-Text $l ((Get-Width) - 2) '       ')) { Write-Host $x -ForegroundColor $Theme.Dim } }
    return $r.Code
}

# Μενού με βελάκια. Επιστρέφει τη θέση της επιλογής ή -1 (πίσω).
# Με -Multi επιστρέφει πίνακα με τις τσεκαρισμένες θέσεις.
function Show-Choice {
    param(
        [string]$Title, $Items, [scriptblock]$Header = $null, $HeaderLines = @(),
        [int]$Start = 0, [string]$Message = '', [string]$MessageColor = 'Green',
        [hashtable]$ExtraKeys = @{}, [string]$Footer = '', [string]$EscText = 'πίσω', [switch]$Multi, [switch]$Banner, [int[]]$PreChecked = @()
    )
    $Items = @($Items)
    if ($Items.Count -eq 0) { return -1 }
    $sel = [Math]::Max(0, [Math]::Min($Start, $Items.Count - 1))
    $head = @($HeaderLines)
    if ($Header) { $head += @(& $Header) }
    $status = @{}
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Status) { $s = & $Items[$i].Status $Items[$i]; if ($s) { $status[$i] = $s } }
    }
    $checked = New-Object 'bool[]' $Items.Count
    foreach ($pc in $PreChecked) { if ($pc -ge 0 -and $pc -lt $Items.Count) { $checked[$pc] = $true } }
    $logo = @(
        '   ┌──────────────────────────────┐',
        '   │   J O H N '' S   T O O L K I T │',
        '   └──────────────────────────────┘',
        '      by nmx88 · classic mode · Windows 10/11'
    )
    $State.ScreenInit = $false
    try { [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            $w = Get-Width
            $h = 30; try { $h = [Console]::WindowHeight } catch {}
            $rw = [Math]::Min(76, $w - 2)
            $rule = '  ' + ('─' * ($rw - 2))
            $clock = (Get-Date).ToString('ddd dd/MM · HH:mm', $GrCulture)

            $top = New-Object System.Collections.Generic.List[object]
            if ($Banner) {
                for ($j = 0; $j -lt $logo.Count; $j++) {
                    if ($j -eq $logo.Count - 1) { $top.Add((Seg @(@($logo[$j], $Theme.Logo), @(''.PadRight([Math]::Max(1, $rw - $logo[$j].Length - $clock.Length)), 'Gray'), @($clock, $Theme.Dim)))) }
                    elseif ($j -eq 1) { $top.Add((Seg @(@($logo[$j], $Theme.Logo), @('   καθαρισμός · επιδόσεις · δίκτυο', $Theme.Dim)))) }
                    else { $top.Add((L $logo[$j] $Theme.Logo)) }
                }
                $top.Add((L ('  ' + ('═' * ($rw - 2))) $Theme.Accent))
            } else {
                $gap = [Math]::Max(1, $rw - 20 - $Title.Length - $clock.Length)
                $top.Add((Seg @(@('  JOHN''S TOOLKIT  ›  ', $Theme.Dim), @($Title, $Theme.Title), @(''.PadRight($gap), 'Gray'), @($clock, $Theme.Dim))))
                $top.Add((L ('  ' + ('═' * ($rw - 2))) $Theme.Accent))
            }
            foreach ($x in $head) { if ($x) { $top.Add($x) } }
            if ($Message) { $top.Add((L '')); $top.Add((Seg @(@('  » ', $MessageColor), @($Message, $MessageColor)))) }
            $top.Add((L ''))

            $body = New-Object System.Collections.Generic.List[object]
            $selLine = 0; $grp = $null
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $it = $Items[$i]
                if ($it.Group -and $it.Group -ne $grp) {
                    $grp = $it.Group
                    if ($body.Count -gt 0) { $body.Add((L '')) }
                    $fill = '─' * [Math]::Max(3, $rw - $grp.Length - 8)
                    $body.Add((Seg @(@('  ── ', 'DarkCyan'), @($grp, $Theme.Accent), @(" $fill", 'DarkCyan'))))
                }
                $k = '  '; if ($it.Key) { $k = "$($it.Key)." }
                $label = $it.Label
                if ($Multi) { if ($checked[$i]) { $label = "[x] $label" } else { $label = "[ ] $label" } }
                $st = ''; $stc = $Theme.Dim
                if ($status.ContainsKey($i)) { $st = "   $($status[$i].Text)"; $stc = $status[$i].Color }
                if ($i -eq $sel) {
                    $selLine = $body.Count
                    $body.Add((Seg @(@(" ► $k $label", $Theme.SelFg), @($st, $Theme.SelFg)) $Theme.SelBg))
                } else {
                    $c = $Theme.Text; if ($it.Color) { $c = $it.Color }
                    if ($Multi -and $checked[$i]) { $c = $Theme.Ok }
                    $body.Add((Seg @(@('   ', 'Gray'), @($k, $Theme.Dim), @(" $label", $c), @($st, $stc))))
                }
            }

            $cur = $Items[$sel]
            $src = @()
            if ($cur.Lines) { $src = @($cur.Lines) }
            else {
                if ($cur.What) { $src += (L "Τι κάνει:  $($cur.What)" $Theme.Text) }
                if ($cur.Affects) { $src += (L "Επηρεάζει: $($cur.Affects)" $Theme.Warn) }
            }
            $desc = New-Object System.Collections.Generic.List[object]
            foreach ($dl in $src) { foreach ($wl in @(Wrap-Text $dl.T ($w - 2) '  ')) { $desc.Add((L $wl $dl.F)) } }
            if ($desc.Count -gt 9) {
                $tmp = New-Object System.Collections.Generic.List[object]
                for ($j = 0; $j -lt 8; $j++) { $tmp.Add($desc[$j]) }
                $tmp.Add((L '  …' $Theme.Dim)); $desc = $tmp
            }

            if ($Multi) { $keys = @(@('↑↓', 'μετακίνηση'), @('Space', 'τικ'), @('A', 'όλα'), @('Enter', 'συνέχεια'), @('Esc', 'ακύρωση')) }
            else { $keys = @(@('↑↓', 'μετακίνηση'), @('Enter', 'επιλογή'), @('Esc', $EscText)) }
            if ($Footer) { foreach ($pair in ($Footer -split '\|')) { $kv = $pair.Trim() -split ' ', 2; if ($kv.Count -eq 2) { $keys += , @($kv[0], $kv[1]) } } }
            $fs = @(, @('  ', 'Gray'))
            foreach ($kp in $keys) { $fs += , @(" $($kp[0]) ", 'Black', 'Gray'); $fs += , @(" $($kp[1])   ", $Theme.Dim) }
            $footLine = [pscustomobject]@{ T = ''; F = 'Gray'; B = $null; T2 = ''; F2 = $null; S = $fs; Keys = $true }

            $avail = $h - $top.Count - $desc.Count - 5
            if ($avail -lt 5) { $avail = 5 }
            $lines = New-Object System.Collections.Generic.List[object]
            foreach ($x in $top) { $lines.Add($x) }
            if ($body.Count -le $avail) { foreach ($x in $body) { $lines.Add($x) } }
            else {
                $avail -= 2
                $s0 = [Math]::Max(0, $selLine - [int][Math]::Floor($avail / 2))
                $s0 = [Math]::Min($s0, $body.Count - $avail)
                if ($s0 -gt 0) { $lines.Add((L '        ▲ περισσότερα' $Theme.Dim)) } else { $lines.Add((L '')) }
                for ($j = $s0; $j -lt $s0 + $avail; $j++) { $lines.Add($body[$j]) }
                if ($s0 + $avail -lt $body.Count) { $lines.Add((L '        ▼ περισσότερα' $Theme.Dim)) } else { $lines.Add((L '')) }
            }
            $lines.Add((L ''))
            $lines.Add((L $rule $Theme.Dim))
            foreach ($x in $desc) { $lines.Add($x) }
            $lines.Add((L ''))
            $lines.Add($footLine)
            Write-Screen $lines

            $key = [Console]::ReadKey($true)
            $kn = "$($key.Key)"
            if ($kn -eq 'UpArrow') { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            elseif ($kn -eq 'DownArrow') { $sel = ($sel + 1) % $Items.Count }
            elseif ($kn -eq 'Home') { $sel = 0 }
            elseif ($kn -eq 'End') { $sel = $Items.Count - 1 }
            elseif ($kn -eq 'PageUp') { $sel = [Math]::Max(0, $sel - 5) }
            elseif ($kn -eq 'PageDown') { $sel = [Math]::Min($Items.Count - 1, $sel + 5) }
            elseif ($Multi -and $kn -eq 'Spacebar') { $checked[$sel] = -not $checked[$sel] }
            elseif ($Multi -and $kn -eq 'A') {
                $all = $true; foreach ($c in $checked) { if (-not $c) { $all = $false } }
                for ($j = 0; $j -lt $checked.Count; $j++) { $checked[$j] = -not $all }
            }
            elseif ($kn -eq 'Enter') {
                if ($Multi) {
                    $res = @(); for ($j = 0; $j -lt $checked.Count; $j++) { if ($checked[$j]) { $res += $j } }
                    return ,$res
                }
                return $sel
            }
            elseif ($kn -eq 'Escape' -or $kn -eq 'Backspace' -or $kn -eq 'Q') { return -1 }
            elseif ($ExtraKeys.ContainsKey($kn)) { return $ExtraKeys[$kn] }
            elseif (-not $Multi) {
                $hot = $kn
                if ($kn -match '^(D|NumPad)(\d)$') { $hot = $matches[2] }
                for ($j = 0; $j -lt $Items.Count; $j++) { if ($Items[$j].Key -and "$($Items[$j].Key)" -eq $hot) { return $j } }
            }
        }
    } finally { try { [Console]::CursorVisible = $true } catch {} }
}

function Write-Segs($line) {
    foreach ($sg in @($line.S)) {
        $fc = $sg[1]; if (-not $fc) { $fc = 'Gray' }
        if ($sg.Count -gt 2 -and $sg[2]) { Write-Host $sg[0] -ForegroundColor $fc -BackgroundColor $sg[2] -NoNewline }
        else { Write-Host $sg[0] -ForegroundColor $fc -NoNewline }
    }
    Write-Host ''
}

# Ερώτηση ναι/όχι με ένα πλήκτρο (δουλεύει και με ελληνικό πληκτρολόγιο)
function Ask-Yes([string]$q) {
    Write-Host ''
    Write-Host '     ? ' -ForegroundColor $Theme.Accent -NoNewline
    Write-Host "$q  " -ForegroundColor $Theme.Title -NoNewline
    Write-Host ' Y ' -ForegroundColor Black -BackgroundColor Gray -NoNewline
    Write-Host ' ναι   ' -ForegroundColor $Theme.Dim -NoNewline
    Write-Host ' N ' -ForegroundColor Black -BackgroundColor Gray -NoNewline
    Write-Host ' όχι' -ForegroundColor $Theme.Dim
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ("$($k.Key)" -eq 'Y') { Write-Host '     → Ναι' -ForegroundColor Green; return $true }
        if ("$($k.Key)" -eq 'N' -or "$($k.Key)" -eq 'Escape') { Write-Host '     → Όχι' -ForegroundColor DarkGray; return $false }
    }
}

function Pause-Key([string]$msg = 'Πάτα οποιοδήποτε πλήκτρο για επιστροφή...') {
    Write-Host ''
    Write-Host '  ' -NoNewline
    Write-Host ' οποιοδήποτε πλήκτρο ' -ForegroundColor Black -BackgroundColor Gray -NoNewline
    Write-Host "  $($msg -replace 'Πάτα οποιοδήποτε πλήκτρο ', '')" -ForegroundColor $Theme.Dim
    [void][Console]::ReadKey($true)
}

function Write-Log([string]$t) {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Add-Content -Path (Join-Path $LogDir 'history.log') -Value "$(Get-Date -Format 'dd/MM/yyyy HH:mm')  $t" -Encoding UTF8
    } catch {}
}

function Select-Folder {
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Διάλεξε φάκελο'
    $res = $d.ShowDialog($owner); $owner.Dispose()
    if ("$res" -eq 'OK') { return $d.SelectedPath }
    return $null
}

function Select-Exe {
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Προγράμματα (*.exe)|*.exe'
    $d.Title = 'Διάλεξε το παιχνίδι ή το πρόγραμμα'
    $res = $d.ShowDialog($owner); $owner.Dispose()
    if ("$res" -eq 'OK') { return $d.FileName }
    return $null
}

# ======================================================================
#  ΜΗΤΡΩΟ (registry) & ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΡΥΘΜΙΣΕΩΝ
# ======================================================================
function Get-RegValue($path, $name) {
    # A setting that was never changed has no value yet: return $null without writing an error
    # (Get-ItemProperty would add one to $Error every time, filling logs\errors.log with noise)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Item -LiteralPath $path -ErrorAction Stop).GetValue($name, $null) } catch { return $null }
}
function Set-RegValue($path, $name, $type, $value) {
    if ($null -eq $value) { Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue; return }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $value -Force | Out-Null
}
function Test-RegEqual($cur, $want) {
    if ($null -eq $want) { return ($null -eq $cur) }
    if ($null -eq $cur) { return $false }
    if ($want -is [byte[]]) { return ((@($cur) -join ',') -eq (@($want) -join ',')) }
    return ("$cur" -eq "$want")
}
function Load-Backup {
    $h = @{}
    $f = Join-Path $DataDir 'settings-backup.json'
    if (Test-Path $f) {
        $raw = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
        if ($raw.Trim()) { foreach ($e in (ConvertFrom-Json $raw)) { if ($e.Key) { $h[$e.Key] = $e } } }
    }
    return $h
}
function Save-Backup($h) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    $json = ConvertTo-Json -InputObject @($h.Values) -Depth 4
    [IO.File]::WriteAllText((Join-Path $DataDir 'settings-backup.json'), $json, (New-Object System.Text.UTF8Encoding $false))
}
# Κρατά την αρχική τιμή μιας ρύθμισης (μόνο την πρώτη φορά που την αλλάζουμε)
function Backup-RegValue($path, $name, $type) {
    $bk = Load-Backup
    $key = "$path|$name"
    if ($bk.ContainsKey($key)) { return }
    $cur = Get-RegValue $path $name
    $val = $cur; if ($cur -is [byte[]]) { $val = @($cur | ForEach-Object { [int]$_ }) }
    $bk[$key] = [pscustomobject]@{ Key = $key; Path = $path; Name = $name; Type = $type; Exists = ($null -ne $cur); Value = $val }
    Save-Backup $bk
}
function ConvertFrom-BackupValue($e) {
    if ($e.Type -eq 'Binary') { return [byte[]]@($e.Value | ForEach-Object { [byte]$_ }) }
    if ($e.Type -eq 'DWord') { return [int]$e.Value }
    return "$($e.Value)"
}

# ======================================================================
#  ΚΑΘΑΡΙΣΜΟΣ
# ======================================================================
function Clear-TempFiles {
    Write-Step 'Προσωρινά αρχεία'
    Remove-WithProgress @($env:TEMP, "$env:WINDIR\Temp", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache", "$env:LOCALAPPDATA\CrashDumps") 'Καθαρισμός προσωρινών αρχείων των Windows και των προγραμμάτων...'
}

function Clear-UpdateCache {
    Write-Step 'Cache του Windows Update'
    Stop-Service -ErrorAction SilentlyContinue wuauserv, bits -Force
    Remove-WithProgress @("$env:WINDIR\SoftwareDistribution\Download") 'Καθαρισμός αρχείων ενημερώσεων που έχουν ήδη εγκατασταθεί...'
    Start-Service -ErrorAction SilentlyContinue wuauserv, bits
}

function Clear-Bin {
    Write-Step 'Άδειασμα Κάδου Ανακύκλωσης...'
    Clear-RecycleBin -ErrorAction SilentlyContinue -Force
    Write-Ok
}

function Invoke-ComponentCleanup {
    Write-Step 'Παλιές ενημερώσεις συστήματος (DISM)'
    $null = Invoke-NativeProgress 'Dism.exe' '/Online /Cleanup-Image /StartComponentCleanup' 'Αφαίρεση παλιών εκδόσεων αρχείων συστήματος. Μην κλείσεις το παράθυρο...'
}

function Clear-Dns {
    Write-Step 'Καθαρισμός DNS cache...'
    ipconfig /flushdns | Out-Null
    Write-Ok
}

function Find-BigFiles {
    $locs = @(
        @{ Key = '1'; Label = 'Ο φάκελος του χρήστη μου'; P = $env:USERPROFILE; What = 'Έγγραφα, Λήψεις, Εικόνες, Βίντεο, Επιφάνεια εργασίας κ.λπ.' }
        @{ Key = '2'; Label = 'Λήψεις (Downloads)'; P = (Join-Path $env:USERPROFILE 'Downloads'); What = 'Συνήθως εκεί μαζεύονται τα περισσότερα ξεχασμένα αρχεία.' }
        @{ Key = '3'; Label = 'Όλος ο δίσκος C:'; P = 'C:\'; What = 'Ψάχνει σε όλο τον δίσκο.'; Affects = 'Αργεί αρκετά λεπτά.' }
        @{ Key = '4'; Label = 'Άλλος φάκελος...'; P = ''; What = 'Ανοίγει παράθυρο για να διαλέξεις φάκελο (π.χ. τον φάκελο λήψεων του torrent).' }
    )
    $r = Show-Choice -Title 'Μεγάλα αρχεία › Πού να ψάξω;' -Items $locs
    if ($r -lt 0) { return }
    $root = $locs[$r].P
    if (-not $root) { $root = Select-Folder; if (-not $root) { return } }
    Write-Header 'Μεγάλα αρχεία'
    Write-Step "Αναζήτηση στο $($root)"
    Start-Progress 'Σάρωση αρχείων...'
    $big = New-Object System.Collections.Generic.List[object]
    $n = 0; $bytes = 0.0
    Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
        $n++; $bytes += $_.Length
        if ($_.Length -ge 5MB) { $big.Add($_) }
        if ($n % 200 -eq 0) { Update-Progress -1 ('{0:N0} αρχεία · {1}' -f $n, (Format-Size $bytes)) }
    }
    Stop-Progress ('σαρώθηκαν {0:N0} αρχεία ({1})' -f $n, (Format-Size $bytes))
    $files = @($big | Sort-Object Length -Descending | Select-Object -First 40)
    if ($files.Count -eq 0) { Write-Note 'Δεν βρέθηκαν αρχεία μεγαλύτερα από 5 MB.'; Pause-Key; return }
    $total = ($files | Measure-Object Length -Sum).Sum
    $items = @()
    foreach ($f in $files) {
        $items += @{ Label = ('{0,10}   {1}' -f (Format-Size $f.Length), $f.Name); F = $f.FullName
                     Lines = @((L "Φάκελος: $($f.DirectoryName)" 'Gray'),
                               (L "Τελευταία αλλαγή: $($f.LastWriteTime.ToString('dd/MM/yyyy'))" 'Gray'),
                               (L 'Enter = ανοίγει τον φάκελο στην Εξερεύνηση, για να αποφασίσεις εσύ. Τίποτα δεν σβήνεται αυτόματα.' 'Yellow')) }
    }
    $sel = 0
    while ($true) {
        $r = Show-Choice -Title 'Μεγάλα αρχεία' -Items $items -Start $sel -HeaderLines @((L "  Τα $($files.Count) μεγαλύτερα αρχεία ($(Format-Size $total) συνολικά) στο $($root)" 'Gray'))
        if ($r -lt 0) { return }
        $sel = $r
        Start-Process explorer.exe -ArgumentList "/select,`"$($items[$r].F)`""
    }
}

# ======================================================================
#  ΕΠΙΔΟΣΕΙΣ
# ======================================================================
function Optimize-Drives {
    Write-Step 'Βελτιστοποίηση δίσκων (TRIM για SSD, ανασυγκρότηση για HDD)'
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' })) {
        $dl = "$($v.DriveLetter)" + ':'
        $null = Invoke-NativeProgress "$env:WINDIR\System32\defrag.exe" "$dl /O /U" "Δίσκος $dl"
    }
}

function Get-ActivePlanGuid {
    $o = "$(powercfg /getactivescheme)"
    if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $matches[1].ToLower() }
    return ''
}
function Get-UltimateGuid {
    $f = Join-Path $DataDir 'ultimate-plan.txt'
    if (Test-Path $f) {
        $g = "$(Get-Content $f -Raw)".Trim()
        if ($g -and ("$(powercfg /list)" -match [regex]::Escape($g))) { return $g }
    }
    return ''
}
function Set-PowerPlan {
    $plans = @(
        @{ Key = '1'; Label = 'Ισορροπημένο (προεπιλογή)'; G = '381b4222-f694-41f0-9685-ff5bb260df2e'
           What = 'Το σχέδιο των Windows: ανεβάζει την ταχύτητα όταν χρειάζεται και εξοικονομεί όταν όχι.'; Affects = 'Συνιστάται για laptop και καθημερινή χρήση.' }
        @{ Key = '2'; Label = 'Υψηλές επιδόσεις'; G = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
           What = 'Ο επεξεργαστής μένει πιο "ξύπνιος", με λιγότερη καθυστέρηση όταν αλλάζει ο φόρτος.'; Affects = 'Λίγο περισσότερη κατανάλωση και ζέστη.' }
        @{ Key = '3'; Label = 'Απόλυτες επιδόσεις (Ultimate Performance)'; G = 'ultimate'
           What = 'Το πιο "επιθετικό" σχέδιο της Microsoft: καμία εξοικονόμηση, ελάχιστη καθυστέρηση. Για δυνατά desktop και gaming.'
           Affects = 'Περισσότερη κατανάλωση ρεύματος και ζέστη. ΔΕΝ συνιστάται για laptop σε μπαταρία.' }
    )
    $sel = 0; $msg = ''; $mcol = 'Green'
    while ($true) {
        $active = Get-ActivePlanGuid; $ult = Get-UltimateGuid
        foreach ($p in $plans) { $p.Active = (($p.G -eq $active) -or ($p.G -eq 'ultimate' -and $ult -and $ult -eq $active)); $p.Status = { param($it) if ($it.Active) { @{ Text = '« ενεργό τώρα'; Color = 'Green' } } } }
        $r = Show-Choice -Title 'Σχέδιο ενέργειας' -Items $plans -Start $sel -Message $msg -MessageColor $mcol `
              -HeaderLines @((L '  Στα Windows 11 δες και: Ρυθμίσεις > Σύστημα > Παροχή ενέργειας > Λειτουργία = "Βέλτιστη απόδοση".' 'DarkGray'))
        if ($r -lt 0) { return }
        $sel = $r; $g = $plans[$r].G
        if ($g -eq 'ultimate' -and -not $ult) {
            $o = "$(powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61)"
            if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $ult = $matches[1].ToLower()
                New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
                Set-Content -Path (Join-Path $DataDir 'ultimate-plan.txt') -Value $ult
            }
        }
        if ($g -eq 'ultimate') { $g = $ult }
        if (-not $g) { $msg = 'Αυτό το σχέδιο δεν υποστηρίζεται σε αυτό το PC (συχνό σε laptop).'; $mcol = 'Yellow'; continue }
        powercfg /setactive $g | Out-Null
        if ((Get-ActivePlanGuid) -eq $g) { $msg = "Ενεργό σχέδιο: $($plans[$r].Label)"; $mcol = 'Green'; Write-Log "Σχέδιο ενέργειας: $($plans[$r].Label)" }
        else { $msg = 'Δεν ήταν δυνατή η αλλαγή. Δοκίμασε: Ρυθμίσεις > Σύστημα > Παροχή ενέργειας.'; $mcol = 'Yellow' }
    }
}

function Test-StartupEnabled($appr, $name) {
    $v = Get-RegValue $appr $name
    if ($null -eq $v) { return $true }
    return ((([byte[]]$v)[0] % 2) -eq 0)
}
function Set-StartupEnabled($e, [bool]$on) {
    $bytes = New-Object byte[] 12
    if ($on) { $bytes[0] = 2 } else { $bytes[0] = 3 }
    Set-RegValue $e.Appr $e.Name 'Binary' $bytes
}
function Get-StartupEntries {
    $base = 'Software\Microsoft\Windows\CurrentVersion'
    $list = @()
    $srcs = @(
        @{ Run = "HKCU:\$base\Run"; Appr = "HKCU:\$base\Explorer\StartupApproved\Run"; Scope = 'μόνο για εμένα' }
        @{ Run = "HKLM:\$base\Run"; Appr = "HKLM:\$base\Explorer\StartupApproved\Run"; Scope = 'όλους τους χρήστες' }
        @{ Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Appr = "HKLM:\$base\Explorer\StartupApproved\Run32"; Scope = 'όλους τους χρήστες' }
    )
    $skip = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    foreach ($s in $srcs) {
        $props = Get-ItemProperty -Path $s.Run
        if (-not $props) { continue }
        foreach ($pp in $props.PSObject.Properties) {
            if ($skip -contains $pp.Name) { continue }
            $list += [pscustomobject]@{ Name = $pp.Name; Command = "$($pp.Value)"; Appr = $s.Appr; Scope = $s.Scope; Enabled = (Test-StartupEnabled $s.Appr $pp.Name); Kind = 'Run'; Key = $s.Run }
        }
    }
    $folders = @(
        @{ D = [Environment]::GetFolderPath('Startup'); Appr = "HKCU:\$base\Explorer\StartupApproved\StartupFolder"; Scope = 'μόνο για εμένα' }
        @{ D = [Environment]::GetFolderPath('CommonStartup'); Appr = "HKLM:\$base\Explorer\StartupApproved\StartupFolder"; Scope = 'όλους τους χρήστες' }
    )
    foreach ($f in $folders) {
        if (-not $f.D) { continue }
        foreach ($file in @(Get-ChildItem -Path $f.D -File | Where-Object { $_.Name -ne 'desktop.ini' })) {
            $list += [pscustomobject]@{ Name = $file.Name; Command = $file.FullName; Appr = $f.Appr; Scope = $f.Scope; Enabled = (Test-StartupEnabled $f.Appr $file.Name); Kind = 'Folder'; Key = $null }
        }
    }
    return $list
}
function Show-StartupManager {
    $sel = 0; $msg = ''
    while ($true) {
        $entries = @(Get-StartupEntries)
        $items = @()
        foreach ($e in $entries) {
            $hint = 'Αν το απενεργοποιήσεις, απλώς δεν θα ανοίγει μόνο του με τα Windows. Το ανοίγεις κανονικά όποτε θέλεις.'
            if ($e.Name -match 'mullvad') { $hint = 'ΣΥΝΙΣΤΑΤΑΙ να μείνει ενεργό, ώστε το VPN να ξεκινά πριν από οτιδήποτε άλλο.' }
            elseif ($e.Name -match 'SecurityHealth|Defender') { $hint = 'Είναι το εικονίδιο της Ασφάλειας των Windows. Άφησέ το ενεργό.' }
            elseif ("$($e.Name) $($e.Command)" -match $TorrentApps) { $hint = 'Αν ξεκινά μόνο του, βεβαιώσου ότι το Mullvad έχει Lockdown mode, για να μη συνδεθεί ποτέ χωρίς VPN.' }
            $items += @{ Label = $e.Name; Group = 'ΠΡΟΓΡΑΜΜΑΤΑ ΠΟΥ ΑΝΟΙΓΟΥΝ ΜΑΖΙ ΜΕ ΤΑ WINDOWS'; E = $e
                         Lines = @((L "Εντολή: $($e.Command)" 'DarkGray'), (L "Ισχύει για: $($e.Scope)" 'DarkGray'), (L $hint 'Yellow'))
                         Status = { param($it) if ($it.E.Enabled) { @{ Text = '● Ενεργό'; Color = 'Green' } } else { @{ Text = '○ Ανενεργό'; Color = 'DarkGray' } } } }
        }
        $items += @{ Label = 'Άνοιγμα Διαχείρισης Εργασιών'; Group = 'ΑΛΛΑ'; Action = 'tm'
                     What = 'Για εφαρμογές που δεν φαίνονται εδώ (π.χ. του Microsoft Store): καρτέλα "Εφαρμογές εκκίνησης".' }
        $r = Show-Choice -Title 'Προγράμματα εκκίνησης' -Items $items -Start $sel -Message $msg `
              -HeaderLines @((L '  Enter = ενεργό/ανενεργό. Λιγότερα προγράμματα εκκίνησης = πιο γρήγορο άνοιγμα των Windows.' 'DarkGray'))
        if ($r -lt 0) { return }
        $sel = $r; $it = $items[$r]
        if ($it.Action -eq 'tm') { Start-Process taskmgr.exe -ArgumentList '/0 /startup'; $msg = 'Άνοιξε η Διαχείριση Εργασιών.'; continue }
        $on = -not $it.E.Enabled
        Set-StartupEnabled $it.E $on
        if ($on) { $msg = "Ενεργοποιήθηκε: $($it.Label)" } else { $msg = "Απενεργοποιήθηκε: $($it.Label) (δεν θα ανοίγει πια μόνο του)" }
        Write-Log "Εκκίνηση: $msg"
    }
}

$BloatList = [ordered]@{
    'Microsoft.BingNews'                     = 'Ειδήσεις (Microsoft News)'
    'Microsoft.BingWeather'                  = 'Καιρός'
    'Microsoft.GetHelp'                      = 'Λήψη βοήθειας'
    'Microsoft.Getstarted'                   = 'Συμβουλές / Ξεκινήστε'
    'Microsoft.MicrosoftSolitaireCollection' = 'Παιχνίδια Solitaire'
    'Microsoft.MicrosoftOfficeHub'           = 'Διαφήμιση Office / Microsoft 365'
    'Microsoft.People'                       = 'Επαφές'
    'Microsoft.WindowsFeedbackHub'           = 'Κέντρο σχολίων'
    'Microsoft.WindowsMaps'                  = 'Χάρτες'
    'Microsoft.ZuneVideo'                    = 'Ταινίες & TV'
    'Microsoft.SkypeApp'                     = 'Skype'
    'Microsoft.Todos'                        = 'Microsoft To Do (λίστες εργασιών)'
    'Microsoft.PowerAutomateDesktop'         = 'Power Automate'
    'Microsoft.549981C3F5F10'                = 'Cortana'
    'Clipchamp.Clipchamp'                    = 'Clipchamp (επεξεργασία βίντεο)'
    'MicrosoftTeams'                         = 'Teams (προσωπικό)'
    'MSTeams'                                = 'Teams (νέο)'
    'Microsoft.YourPhone'                    = 'Σύνδεση με το τηλέφωνο (Phone Link)'
    'Microsoft.GamingApp'                    = 'Εφαρμογή Xbox (χρειάζεται για Game Pass)'
    'Microsoft.XboxGamingOverlay'            = 'Xbox Game Bar (χρειάζεται για εγγραφή οθόνης σε παιχνίδια)'
}

function Remove-Bloat {
    Write-Header 'Αφαίρεση περιττών εφαρμογών'
    Write-Step 'Αναζήτηση προεγκατεστημένων εφαρμογών...'
    $found = @()
    foreach ($name in $BloatList.Keys) {
        if (Get-AppxPackage -ErrorAction SilentlyContinue -Name $name) {
            $found += @{ Label = $BloatList[$name]; Name = $name; What = "Εφαρμογή των Windows ($name)."; Affects = 'Αν τη χρειαστείς ξανά, την κατεβάζεις δωρεάν από το Microsoft Store.' }
        }
    }
    if ($found.Count -eq 0) { Write-Ok 'Δεν βρέθηκε καμία από τις γνωστές περιττές εφαρμογές. Όλα καθαρά!'; Pause-Key; return }
    $res = Show-Choice -Title 'Αφαίρεση περιττών εφαρμογών' -Items $found -Multi `
            -HeaderLines @((L '  Μετακινήσου με τα βελάκια, πάτα Space σε όσες θέλεις να φύγουν και μετά Enter.' 'Gray'))
    if ($res -is [int]) { return }
    $picked = @($res)
    Write-Header 'Αφαίρεση περιττών εφαρμογών'
    if ($picked.Count -eq 0) { Write-Note 'Δεν επέλεξες καμία εφαρμογή.'; Pause-Key; return }
    Write-Step 'Θα αφαιρεθούν:'
    foreach ($i in $picked) { Write-Host "       - $($found[$i].Label)" }
    if (-not (Ask-Yes "Να αφαιρεθούν αυτές οι $($picked.Count) εφαρμογές;")) { return }
    Start-Progress 'Αφαίρεση εφαρμογών...'
    $j = 0
    foreach ($i in $picked) {
        Update-Progress (100.0 * $j / $picked.Count) $found[$i].Label -Force
        Get-AppxPackage -ErrorAction SilentlyContinue -Name $found[$i].Name | Remove-AppxPackage -ErrorAction SilentlyContinue
        Write-Log "Αφαίρεση εφαρμογής: $($found[$i].Label)"
        $j++
    }
    Stop-Progress "αφαιρέθηκαν $($picked.Count) εφαρμογές. Όποια χρειαστείς ξανά, την κατεβάζεις από το Microsoft Store."
    Pause-Key
}

# ----- Ενημερώσεις προγραμμάτων (winget) με επιλογή -----
function Get-WingetPath { return (Get-Command winget.exe -ErrorAction SilentlyContinue).Source }
# Αν το winget έκοψε το Id με "…", ψάχνουμε με το αρχικό κομμάτι (χωρίς ακριβές ταίριασμα)
function Get-WingetIdArg([string]$id) {
    if ($id -match '…$') { return "--id `"$($id.TrimEnd([char]0x2026))`"" }
    return "--id `"$id`" --exact"
}

function ConvertFrom-WingetTable([string]$text) {
    $lines = @($text -split "`r?`n" | ForEach-Object { ($_ -split "`r")[-1] })
    $dash = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*-{10,}\s*$') { $dash = $i; break } }
    if ($dash -lt 1) { return @() }
    $starts = @([regex]::Matches($lines[$dash - 1], '\S+') | ForEach-Object { $_.Index })
    if ($starts.Count -lt 3) { return @() }
    $rows = @()
    for ($i = $dash + 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if (-not $l.Trim()) { break }
        if ($l.Length -le $starts[2]) { break }
        $cells = @()
        for ($c = 0; $c -lt $starts.Count; $c++) {
            $s = $starts[$c]; $e = $l.Length; if ($c -lt $starts.Count - 1) { $e = [Math]::Min($starts[$c + 1], $l.Length) }
            if ($s -ge $l.Length) { $cells += '' } else { $cells += $l.Substring($s, $e - $s).Trim() }
        }
        $rows += , $cells
    }
    return $rows
}

function Get-WingetUpgrades {
    $wg = Get-WingetPath
    if (-not $wg) { return $null }
    Start-Progress 'Έλεγχος για διαθέσιμες ενημερώσεις...'
    $r = Invoke-Native $wg 'upgrade --accept-source-agreements' 'winget' ([Text.Encoding]::UTF8)
    $list = @()
    foreach ($c in @(ConvertFrom-WingetTable $r.Output)) {
        if ($c.Count -ge 4 -and $c[1] -and $c[1] -notmatch '\s') { $list += [pscustomobject]@{ Name = $c[0]; Id = $c[1]; Version = $c[2]; Available = $c[3] } }
    }
    Stop-Progress "$($list.Count) διαθέσιμες ενημερώσεις"
    return $list
}

$UpdateRisks = @(
    @{ P = '^MullvadVPN|Mullvad'; R = 'Το VPN θα πέσει για λίγο κατά την ενημέρωση. Κάνε πρώτα παύση στο torrent.' }
    @{ P = 'qBittorrent|uTorrent|BitTorrent|Transmission|Deluge'; R = 'Το torrent θα κλείσει για να ενημερωθεί.' }
    @{ P = '^Docker\.'; R = 'Σταματά όλα τα containers και μπορεί να ζητήσει ενημέρωση του WSL.' }
    @{ P = '^Oracle\.VirtualBox'; R = 'Κλείσε πρώτα τις εικονικές μηχανές. Ξαναστήνει τους οδηγούς δικτύου (κόβει για λίγο το ίντερνετ).' }
    @{ P = '^Tailscale\.'; R = 'Πέφτει για λίγο η σύνδεση Tailscale.' }
    @{ P = '^PostgreSQL\.'; R = 'Επανεκκινεί τη βάση δεδομένων. Κλείσε πρώτα ό,τι τη χρησιμοποιεί.' }
    @{ P = '^Microsoft\.VisualStudio'; R = 'Τεράστιο, και μέσω winget συχνά κολλάει. Ενημέρωσέ το από το Visual Studio Installer.' }
    @{ P = '^Adobe\.'; R = 'Ενημερώνεται καλύτερα μέσα από το ίδιο το πρόγραμμα. Μέσω winget αποτυγχάνει συχνά.' }
    @{ P = '^EpicGames\.EpicGamesLauncher|^Valve\.Steam|^Discord\.'; R = 'Ενημερώνεται μόνο του όταν το ανοίγεις.' }
    @{ P = '^Microsoft\.WindowsInstallationAssistant|^Microsoft\.WindowsPCHealthCheck'; R = 'Δεν χρειάζεται για καθημερινή χρήση. Μπορείς να το αγνοήσεις ή να το "παγώσεις".' }
)
function Get-UpdateRisk($u) {
    foreach ($r in $UpdateRisks) { if ($u.Id -match $r.P -or $u.Name -match $r.P) { return @{ Level = 2; Reason = $r.R } } }
    $a = 0; $b = 0
    if ("$($u.Version)" -match '^(\d+)') { $a = [int64]$matches[1] }
    if ("$($u.Available)" -match '^(\d+)') { $b = [int64]$matches[1] }
    if ($a -gt 0 -and $b -gt $a) { return @{ Level = 1; Reason = "Μεγάλη αλλαγή έκδοσης ($($u.Version) → $($u.Available)). Συνήθως είναι εντάξει, αλλά μπορεί να αλλάξει η εμφάνιση ή να ζητήσει μεταφορά ρυθμίσεων." } }
    return @{ Level = 0; Reason = 'Μικρή ενημέρωση (διορθώσεις και ασφάλεια). Ασφαλής.' }
}

function Update-Apps {
    Write-Header 'Ενημέρωση προγραμμάτων'
    $wg = Get-WingetPath
    if (-not $wg) { Write-Bad 'Δεν βρέθηκε το winget. Εγκατέστησε ή ενημέρωσε το "App Installer" από το Microsoft Store.'; Pause-Key; return }
    $ups = @(Get-WingetUpgrades)
    if ($ups.Count -eq 0) { Write-Ok 'Όλα τα προγράμματα είναι ενημερωμένα!'; Pause-Key; return }

    $rated = foreach ($u in $ups) { $k = Get-UpdateRisk $u; [pscustomobject]@{ U = $u; L = $k.Level; R = $k.Reason } }
    $rated = @($rated | Sort-Object L, @{ e = { $_.U.Name } })
    $items = @(); $pre = @()
    for ($i = 0; $i -lt $rated.Count; $i++) {
        $x = $rated[$i]
        $g = 'ΑΣΦΑΛΕΙΣ (ήδη τσεκαρισμένες)'; $col = $Theme.Text; $rc = $Theme.Ok
        if ($x.L -eq 1) { $g = 'ΜΕΓΑΛΕΣ ΑΛΛΑΓΕΣ ΕΚΔΟΣΗΣ (τσεκαρισμένες, ρίξε μια ματιά)'; $col = $Theme.Text; $rc = $Theme.Warn }
        if ($x.L -eq 2) { $g = 'ΜΕ ΠΡΟΣΟΧΗ (δεν είναι τσεκαρισμένες)'; $col = $Theme.Warn; $rc = $Theme.Warn }
        if ($x.L -lt 2) { $pre += $i }
        $items += @{ Label = ('{0}   {1} → {2}' -f $x.U.Name, $x.U.Version, $x.U.Available); Group = $g; Color = $col
                     Lines = @((L "Id: $($x.U.Id)" $Theme.Dim), (L $x.R $rc)) }
    }
    $res = Show-Choice -Title 'Ενημέρωση προγραμμάτων' -Items $items -Multi -PreChecked $pre `
            -HeaderLines @((L "  Βρέθηκαν $($ups.Count) ενημερώσεις. Τα ασφαλή είναι ήδη τσεκαρισμένα: άλλαξε ό,τι θέλεις με Space και πάτα Enter." $Theme.Text))
    if ($res -is [int]) { return }
    $picked = @($res | ForEach-Object { $rated[$_].U })
    Write-Header 'Ενημέρωση προγραμμάτων'
    if ($picked.Count -eq 0) { Write-Note 'Δεν επέλεξες κάποιο πρόγραμμα.'; Pause-Key; return }
    if (@($picked | Where-Object { $_.Id -match 'Mullvad' }).Count -gt 0) {
        Write-Note 'Στη λίστα είναι και το Mullvad: το VPN θα πέσει για λίγο. Κάνε τώρα παύση στο torrent.'
        if (-not (Ask-Yes 'Συνέχεια;')) { return }
    }
    Write-Note 'Κλείσε τα προγράμματα που θα ενημερωθούν, αν είναι ανοιχτά (αλλιώς μπορεί να αποτύχουν).'
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $log = Join-Path $LogDir ('winget-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    $ok = @(); $bad = @(); $t0 = Get-Date
    for ($i = 0; $i -lt $picked.Count; $i++) {
        $u = $picked[$i]
        $bar = Get-Bar (100.0 * $i / $picked.Count) 20
        Write-Host ''
        Write-Segs (Seg @(@(('  [{0}/{1}] ' -f ($i + 1), $picked.Count), $Theme.Accent), @($bar[0], $Theme.Ok), @($bar[1], 'DarkGray'), @("  $($u.Name)", $Theme.Title), @("   $($u.Version) → $($u.Available)", $Theme.Dim)))
        Start-Progress 'Λήψη και εγκατάσταση...'
        $r = Invoke-Native $wg "upgrade $(Get-WingetIdArg $u.Id) --silent --accept-package-agreements --accept-source-agreements" '' ([Text.Encoding]::UTF8)
        Add-Content -Path $log -Encoding UTF8 -Value @("===== $($u.Name) ($($u.Id)) -> κωδικός $($r.Code) =====", $r.Output)
        if (Test-ExitOk $r.Code) {
            $m = 'ενημερώθηκε'; if ($r.Code -ne 0) { $m += ' · ' + (Get-ExitCodeText $r.Code); $State.NeedsRestart = $true }
            Stop-Progress $m; $ok += $u
        } else {
            $why = Get-ExitCodeText $r.Code
            Stop-Progress "απέτυχε: $why" 'Yellow'
            $bad += [pscustomobject]@{ U = $u; Why = $why }
        }
        Write-Log "Ενημέρωση $($u.Name): κωδικός $($r.Code)"
    }
    $rows = @(, @("● Ενημερώθηκαν: $($ok.Count)", 'Green'))
    if ($bad.Count -gt 0) {
        $rows += , @("● Απέτυχαν: $($bad.Count)", 'Yellow')
        $rows += '-'
        foreach ($b in $bad) { $rows += , @($b.U.Name, 'White'); foreach ($l in @(Wrap-Text $b.Why 66 '   ')) { $rows += , @($l, 'Yellow') } }
    }
    $rows += '-'
    $rows += , @("Χρόνος: $(Format-Time ((Get-Date) - $t0).TotalSeconds)")
    $rows += , @("Λεπτομέρειες: logs\$(Split-Path $log -Leaf)", $Theme.Dim)
    Write-Box 'ΑΠΟΤΕΛΕΣΜΑ ΕΝΗΜΕΡΩΣΕΩΝ' $rows 74
    Send-Toast 'John''s Toolkit: ενημερώσεις' "Ενημερώθηκαν $($ok.Count), απέτυχαν $($bad.Count)."
    Pause-Key
}

function Show-WingetPins {
    $wg = Get-WingetPath
    if (-not $wg) { Write-Header 'Παγωμένα προγράμματα'; Write-Bad 'Δεν βρέθηκε το winget.'; Pause-Key; return }
    $sel = 0; $msg = ''; $mcol = 'Green'
    while ($true) {
        Write-Header 'Παγωμένα προγράμματα'
        Start-Progress 'Ανάγνωση λίστας...'
        $r = Invoke-Native $wg 'pin list --accept-source-agreements' '' ([Text.Encoding]::UTF8)
        Stop-Progress
        $pins = @()
        foreach ($c in @(ConvertFrom-WingetTable $r.Output)) { if ($c.Count -ge 2 -and $c[1]) { $pins += [pscustomobject]@{ Name = $c[0]; Id = $c[1] } } }
        $items = @(@{ Label = 'Πάγωμα προγράμματος...'; Group = 'ΕΝΕΡΓΕΙΕΣ'; Action = 'add'
                      What = 'Διαλέγεις ένα πρόγραμμα από τις διαθέσιμες ενημερώσεις και το "παγώνεις": δεν θα εμφανίζεται πια στις ενημερώσεις.'; Affects = 'Μόνο τις ενημερώσεις μέσω winget. Το ίδιο το πρόγραμμα μπορεί ακόμα να ενημερωθεί μόνο του.' })
        foreach ($p in $pins) {
            $items += @{ Label = $p.Name; Group = 'ΠΑΓΩΜΕΝΑ (Enter = ξεπάγωμα)'; P = $p
                         Lines = @((L "Id: $($p.Id)" $Theme.Dim), (L 'Enter = να εμφανίζεται ξανά στις ενημερώσεις.' $Theme.Warn)) }
        }
        if ($r.Code -ne 0 -and $pins.Count -eq 0 -and $r.Output -notmatch '-{10,}') { $msg = 'Το winget σου δεν υποστηρίζει πάγωμα ή δεν υπάρχουν παγωμένα. Αν χρειάζεται, ενημέρωσε το "App Installer" από το Store.'; $mcol = 'Yellow' }
        $x = Show-Choice -Title 'Παγωμένα προγράμματα' -Items $items -Start $sel -Message $msg -MessageColor $mcol
        $msg = ''; $mcol = 'Green'
        if ($x -lt 0) { return }
        $sel = $x
        if ($items[$x].Action -eq 'add') {
            Write-Header 'Παγωμένα προγράμματα'
            $ups = @(Get-WingetUpgrades)
            if ($ups.Count -eq 0) { $msg = 'Δεν υπάρχουν διαθέσιμες ενημερώσεις για πάγωμα.'; continue }
            $ui = @(); foreach ($u in $ups) { $ui += @{ Label = ('{0}   {1} → {2}' -f $u.Name, $u.Version, $u.Available); U = $u; What = "Id: $($u.Id)" } }
            $y = Show-Choice -Title 'Ποιο να παγώσει;' -Items $ui
            if ($y -lt 0) { continue }
            $u = $ui[$y].U
            $rr = Invoke-Native $wg "pin add $(Get-WingetIdArg $u.Id) --accept-source-agreements" '' ([Text.Encoding]::UTF8)
            if ($rr.Code -eq 0) { $msg = "Πάγωσε: $($u.Name)"; Write-Log "Πάγωμα: $($u.Name)" } else { $msg = "Δεν έγινε το πάγωμα: $(Get-ExitCodeText $rr.Code)"; $mcol = 'Yellow' }
        } else {
            $p = $items[$x].P
            $rr = Invoke-Native $wg "pin remove $(Get-WingetIdArg $p.Id)" '' ([Text.Encoding]::UTF8)
            if ($rr.Code -eq 0) { $msg = "Ξεπάγωσε: $($p.Name)"; Write-Log "Ξεπάγωμα: $($p.Name)" } else { $msg = "Δεν έγινε: $(Get-ExitCodeText $rr.Code)"; $mcol = 'Yellow' }
        }
    }
}

# ======================================================================
#  ΡΥΘΜΙΣΕΙΣ WINDOWS 11 (γραφικά, gaming, σύστημα)
# ======================================================================
function Update-MouseNow([int[]]$vals) {
    try {
        if (-not ('PCTools.Native' -as [type])) {
            Add-Type -Namespace PCTools -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(int uiAction, int uiParam, int[] pvParam, int fWinIni);'
        }
        [void][PCTools.Native]::SystemParametersInfo(4, 0, $vals, 3)
    } catch {}
}

$DxPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$Tweaks = @(
    @{ Id = 'visualfx'; Group = 'ΓΡΑΦΙΚΑ & ΕΦΕ'; Label = 'Λιγότερα οπτικά εφέ (κινήσεις, σκιές)'; Short = 'λιγότερα εφέ'; Recommended = $false; Restart = 'signout'
       What = 'Κλείνει τις κινήσεις στα παράθυρα και τη γραμμή εργασιών, τις σκιές και την "κρυφή ματιά" στην επιφάνεια εργασίας. Κρατά τις μικρογραφίες εικόνων και τα ομαλά γράμματα. Το PC "νιώθει" πιο γρήγορο, ειδικά αν είναι παλιό ή αδύναμο.'
       Affects = 'Μόνο την εμφάνιση. Ισχύει πλήρως μετά από αποσύνδεση ή επανεκκίνηση.'
       Reg = @(
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; N = 'VisualFXSetting'; T = 'DWord'; On = 3; Off = 0 }
           @{ P = 'HKCU:\Control Panel\Desktop'; N = 'UserPreferencesMask'; T = 'Binary'; On = [byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0); Off = [byte[]](0x9E, 0x1E, 0x07, 0x80, 0x12, 0, 0, 0) }
           @{ P = 'HKCU:\Control Panel\Desktop\WindowMetrics'; N = 'MinAnimate'; T = 'String'; On = '0'; Off = '1' }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'TaskbarAnimations'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\DWM'; N = 'EnableAeroPeek'; T = 'DWord'; On = 0; Off = 1 }
       ) }
    @{ Id = 'transparency'; Group = 'ΓΡΑΦΙΚΑ & ΕΦΕ'; Label = 'Χωρίς διαφάνεια σε μενού και γραμμή εργασιών'; Short = 'χωρίς διαφάνεια'; Recommended = $false
       What = 'Κλείνει το εφέ "θολού γυαλιού" στο μενού Έναρξη, τη γραμμή εργασιών και τα παράθυρα. Ελαφρύνει την κάρτα γραφικών, κυρίως σε laptop με ενσωματωμένη κάρτα.'
       Affects = 'Μόνο την εμφάνιση (τα μενού γίνονται συμπαγή). Ισχύει αμέσως.'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'EnableTransparency'; T = 'DWord'; On = 0; Off = 1 }) }

    @{ Id = 'fileext'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = 'Εμφάνιση επεκτάσεων αρχείων (.pdf, .exe...)'; Short = 'επεκτάσεις αρχείων'; Recommended = $true
       What = 'Δείχνει την κατάληξη κάθε αρχείου. Έτσι ξεχωρίζεις αμέσως ένα ψεύτικο "ταινία.mp4.exe" από ένα πραγματικό βίντεο. Πολύ χρήσιμο για την ασφάλεια, ειδικά με αρχεία από torrent.'
       Affects = 'Μόνο την εμφάνιση των ονομάτων στην Εξερεύνηση. Ισχύει αμέσως (ή με F5 στον φάκελο).'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'HideFileExt'; T = 'DWord'; On = 0; Off = 1 }) }
    @{ Id = 'menudelay'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = 'Γρηγορότερα μενού'; Short = 'γρήγορα μενού'; Recommended = $true; Restart = 'signout'
       What = 'Τα μενού και τα υπομενού ανοίγουν σχεδόν αμέσως (100 ms αντί για 400 ms). Είναι η καλή ρύθμιση από το αρχείο AskVG, σε πιο ήπια τιμή.'
       Affects = 'Μόνο την ταχύτητα εμφάνισης των μενού. Ισχύει μετά από αποσύνδεση ή επανεκκίνηση.'
       Reg = @(@{ P = 'HKCU:\Control Panel\Desktop'; N = 'MenuShowDelay'; T = 'String'; On = '100'; Off = '400' }) }
    @{ Id = 'nostoreopen'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = 'Χωρίς Microsoft Store για άγνωστα αρχεία'; Short = 'χωρίς Store σε άγνωστα αρχεία'; Recommended = $true
       What = 'Όταν ανοίγεις αρχείο που δεν αναγνωρίζεται, δεν σε στέλνει στο Store: βλέπεις κατευθείαν τη λίστα με τα δικά σου προγράμματα. Από το αρχείο AskVG.'
       Affects = 'Τίποτα αρνητικό.'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; N = 'NoInternetOpenWith'; T = 'DWord'; On = 1; Off = $null }) }
    @{ Id = 'copymove'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = '"Αντιγραφή σε..." και "Μετακίνηση σε..." στο δεξί κλικ'; Short = 'Αντιγραφή/Μετακίνηση σε'; Recommended = $false
       What = 'Προσθέτει δύο επιλογές στο δεξί κλικ, για να στέλνεις αρχεία σε άλλον φάκελο χωρίς αντιγραφή-επικόλληση. Από το αρχείο AskVG.'
       Affects = 'Στα Windows 11 εμφανίζονται στο "Εμφάνιση περισσότερων επιλογών" (ή κατευθείαν, αν ενεργοποιήσεις και το κλασικό δεξί κλικ).'
       Reg = @(
           @{ P = 'HKCU:\Software\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Copy To'; N = '(default)'; T = 'String'; On = '{C2FBB630-2971-11D1-A18C-00C04FD75D13}'; Off = $null }
           @{ P = 'HKCU:\Software\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Move To'; N = '(default)'; T = 'String'; On = '{C2FBB631-2971-11D1-A18C-00C04FD75D13}'; Off = $null }
       )
       After = { param($on) if (-not $on) { Remove-Item -Path 'HKCU:\Software\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Copy To', 'HKCU:\Software\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\Move To' -Force -ErrorAction SilentlyContinue } } }
    @{ Id = 'classicmenu'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = 'Κλασικό δεξί κλικ (όπως στα Windows 10)'; Short = 'κλασικό δεξί κλικ'; Recommended = $false; Restart = 'explorer'; CustomBackup = $true
       What = 'Το δεξί κλικ δείχνει κατευθείαν όλες τις επιλογές (7-Zip, Notepad++, VS Code...), χωρίς το ενδιάμεσο "Εμφάνιση περισσότερων επιλογών".'
       Affects = 'Μόνο την εμφάνιση του δεξιού κλικ. Θέλει επανεκκίνηση της Εξερεύνησης (επιλογή στην κορυφή αυτής της λίστας).'
       Get = { Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
       Set = { param($on)
           $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
           if ($on) { New-Item -Path "$k\InprocServer32" -Force | Out-Null; Set-ItemProperty -Path "$k\InprocServer32" -Name '(default)' -Value '' }
           else { Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue } } }
    @{ Id = 'thispc'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = 'Η Εξερεύνηση ανοίγει στο "Αυτός ο υπολογιστής"'; Short = 'Αυτός ο υπολογιστής'; Recommended = $false
       What = 'Αντί για την "Αρχική" (πρόσφατα αρχεία, OneDrive), η Εξερεύνηση ανοίγει κατευθείαν στους δίσκους σου.'
       Affects = 'Μόνο το σημείο όπου ανοίγει η Εξερεύνηση. Ισχύει από το επόμενο παράθυρο.'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'LaunchTo'; T = 'DWord'; On = 1; Off = $null }) }
    @{ Id = 'endtask'; Group = 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ'; Label = '"Τερματισμός εργασίας" στη γραμμή εργασιών'; Short = 'Τερματισμός εργασίας'; Recommended = $true
       What = 'Με δεξί κλικ σε πρόγραμμα στη γραμμή εργασιών εμφανίζεται το "Τερματισμός εργασίας". Κλείνεις ένα κολλημένο πρόγραμμα χωρίς Διαχείριση Εργασιών.'
       Affects = 'Χρειάζεται Windows 11 23H2 ή νεότερα. Ισχύει αμέσως ή μετά από επανεκκίνηση της Εξερεύνησης.'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; N = 'TaskbarEndTask'; T = 'DWord'; On = 1; Off = $null }) }

    @{ Id = 'hags'; Group = 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING'; Label = 'Επιτάχυνση GPU από το υλικό (HAGS)'; Short = 'HAGS'; Recommended = $false; Restart = 'restart'
       What = 'Η κάρτα γραφικών διαχειρίζεται μόνη της τη μνήμη της αντί για τον επεξεργαστή. Μειώνει την καθυστέρηση σε παιχνίδια και χρειάζεται για το DLSS Frame Generation της NVIDIA.'
       Affects = 'Χρειάζεται επανεκκίνηση. Δουλεύει μόνο σε σχετικά νέες κάρτες (NVIDIA GTX 1000+, AMD RX 5000+, Intel Arc) με ενημερωμένους drivers. Αν μετά δεις κολλήματα, ξανακλείσε το.'
       Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; N = 'HwSchMode'; T = 'DWord'; On = 2; Off = 1 }) }
    @{ Id = 'windowed'; Group = 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING'; Label = 'Βελτιστοποίηση για παιχνίδια σε παράθυρο'; Short = 'παιχνίδια σε παράθυρο'; Recommended = $true
       What = 'Ρύθμιση των Windows 11 που μειώνει την καθυστέρηση (input lag) και βελτιώνει τη ροή εικόνας σε παιχνίδια που τρέχουν σε παράθυρο ή "χωρίς περίγραμμα".'
       Affects = 'Μόνο παιχνίδια DirectX 10/11. Ισχύει από το επόμενο άνοιγμα του παιχνιδιού.'
       Get = { "$(Get-RegValue $DxPath 'DirectXUserGlobalSettings')" -match 'SwapEffectUpgradeEnable=1' }
       Set = { param($on)
           Backup-RegValue $DxPath 'DirectXUserGlobalSettings' 'String'
           $v = "$(Get-RegValue $DxPath 'DirectXUserGlobalSettings')"
           $parts = @($v -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' })
           $parts += "SwapEffectUpgradeEnable=$([int]$on)"
           Set-RegValue $DxPath 'DirectXUserGlobalSettings' 'String' (($parts -join ';') + ';') } }
    @{ Id = 'gamemode'; Group = 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING'; Label = 'Λειτουργία παιχνιδιού (Game Mode)'; Short = 'Game Mode'; Recommended = $true
       What = 'Όταν παίζεις, τα Windows δίνουν προτεραιότητα στο παιχνίδι και καθυστερούν ενημερώσεις και ειδοποιήσεις. Συνήθως είναι ήδη ενεργό: εδώ βεβαιώνεσαι ότι δεν έχει κλείσει.'
       Affects = 'Τίποτα αρνητικό για την καθημερινή χρήση.'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; T = 'DWord'; On = 1; Off = 0 }) }
    @{ Id = 'gamedvr'; Group = 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING'; Label = 'Χωρίς εγγραφή παρασκηνίου του Xbox (Game DVR)'; Short = 'χωρίς Game DVR'; Recommended = $true
       What = 'Σταματά τις εγγραφές του Xbox Game Bar (κλιπ και "κατέγραψε ό,τι μόλις έγινε"), που τρέχουν κρυφά όταν παίζεις και μπορεί να ρίχνουν τα FPS.'
       Affects = 'Δεν θα γράφεις κλιπ με το Win+Alt+G. Αν δεν το χρησιμοποιείς, δεν χάνεις τίποτα.'
       Reg = @(
           @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_Enabled'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled'; T = 'DWord'; On = 0; Off = 1 }
       ) }
    @{ Id = 'mouse'; Group = 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING'; Label = 'Ακριβές ποντίκι (χωρίς επιτάχυνση)'; Short = 'ποντίκι χωρίς επιτάχυνση'; Recommended = $false
       What = 'Κλείνει τη "Βελτίωση ακρίβειας δείκτη". Ο δείκτης κινείται πάντα την ίδια απόσταση για την ίδια κίνηση του χεριού, κάτι που βοηθά πολύ στη στόχευση σε παιχνίδια.'
       Affects = 'Το ποντίκι θα "νιώθει" λίγο διαφορετικά στην αρχή. Ισχύει αμέσως.'
       Reg = @(
           @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseSpeed'; T = 'String'; On = '0'; Off = '1' }
           @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseThreshold1'; T = 'String'; On = '0'; Off = '6' }
           @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseThreshold2'; T = 'String'; On = '0'; Off = '10' }
       )
       After = { param($on) if ($on) { Update-MouseNow @(0, 0, 0) } else { Update-MouseNow @(6, 10, 1) } } }

    @{ Id = 'startupdelay'; Group = 'ΣΥΣΤΗΜΑ'; Label = 'Γρηγορότερο άνοιγμα προγραμμάτων εκκίνησης'; Short = 'γρήγορη εκκίνηση'; Recommended = $true
       What = 'Τα Windows περιμένουν μερικά δευτερόλεπτα πριν ανοίξουν τα προγράμματα εκκίνησης. Αυτό καταργεί την αναμονή, ώστε η επιφάνεια εργασίας να είναι έτοιμη νωρίτερα.'
       Affects = 'Σε σκληρό δίσκο (HDD) τα πρώτα δευτερόλεπτα μπορεί να βαρύνουν λίγο. Σε SSD μόνο κέρδος.'
       Reg = @(@{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; N = 'StartupDelayInMSec'; T = 'DWord'; On = 0; Off = $null }) }
    @{ Id = 'bgapps'; Group = 'ΣΥΣΤΗΜΑ'; Label = 'Χωρίς εφαρμογές Store στο παρασκήνιο'; Short = 'χωρίς παρασκήνιο'; Recommended = $false
       What = 'Οι εφαρμογές του Microsoft Store (Καιρός, Phone Link κ.λπ.) δεν θα τρέχουν όταν είναι κλειστές. Εξοικονομεί μνήμη και μπαταρία.'
       Affects = 'Εφαρμογές του Store δεν θα στέλνουν ειδοποιήσεις όταν είναι κλειστές. Κανονικά προγράμματα (Chrome, Discord, torrent, Mullvad) ΔΕΝ επηρεάζονται.'
       Reg = @(
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; N = 'GlobalUserDisabled'; T = 'DWord'; On = 1; Off = 0 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'BackgroundAppGlobalToggle'; T = 'DWord'; On = 0; Off = 1 }
       ) }
    @{ Id = 'widgets'; Group = 'ΣΥΣΤΗΜΑ'; Label = 'Κλείσιμο Widgets (ειδήσεις/καιρός)'; Short = 'χωρίς Widgets'; Recommended = $false; Restart = 'restart'
       What = 'Απενεργοποιεί τον πίνακα Widgets, που τρέχει συνέχεια στο παρασκήνιο και τρώει αρκετή μνήμη RAM.'
       Affects = 'Χάνεις τον πίνακα με ειδήσεις και καιρό (Win+W). Ισχύει μετά από επανεκκίνηση.'
       Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N = 'AllowNewsAndInterests'; T = 'DWord'; On = 0; Off = $null }) }
    @{ Id = 'ads'; Group = 'ΣΥΣΤΗΜΑ'; Label = 'Λιγότερες διαφημίσεις και "προτάσεις" της Microsoft'; Short = 'λιγότερες διαφημίσεις'; Recommended = $true
       What = 'Σταματά τις προτεινόμενες εφαρμογές στο μενού Έναρξη, τις "συμβουλές", την αυτόματη εγκατάσταση προωθούμενων εφαρμογών και το διαφημιστικό αναγνωριστικό.'
       Affects = 'Τίποτα σημαντικό. Απλώς λιγότερες ενοχλήσεις.'
       Reg = @(
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SilentInstalledAppsEnabled'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SystemPaneSuggestionsEnabled'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SoftLandingEnabled'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-338388Enabled'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-338389Enabled'; T = 'DWord'; On = 0; Off = 1 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; N = 'Enabled'; T = 'DWord'; On = 0; Off = 1 }
       ) }

    @{ Id = 'hibernate'; Group = 'ΣΥΣΤΗΜΑ'; Label = 'Απενεργοποίηση αδρανοποίησης (ελευθερώνει GB)'; Short = 'χωρίς αδρανοποίηση'; Recommended = $false; CustomBackup = $true
       What = 'Σβήνει το αρχείο hiberfil.sys, που πιάνει περίπου το 40% της RAM σου (π.χ. 13 GB με 32 GB RAM).'
       Affects = 'Χάνεις την «Αδρανοποίηση» και τη «Γρήγορη εκκίνηση». Σε laptop που το κλείνεις συχνά, καλύτερα άφησέ το.'
       Get = { "$(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled')" -eq '0' }
       Set = { param($on) if ($on) { powercfg /hibernate off | Out-Null } else { powercfg /hibernate on | Out-Null } } }
    @{ Id = 'storagesense'; Group = 'ΣΥΣΤΗΜΑ'; Label = 'Αισθητήρας αποθήκευσης (Storage Sense)'; Short = 'Storage Sense'; Recommended = $false
       What = 'Αφήνει τα ίδια τα Windows να σβήνουν κάθε εβδομάδα τα προσωρινά αρχεία που δεν χρειάζονται.'
       Affects = 'Δεν αγγίζει τον Κάδο Ανακύκλωσης ούτε τις Λήψεις.'
       Reg = @(
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; N = '01'; T = 'DWord'; On = 1; Off = 0 }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; N = '04'; T = 'DWord'; On = 1; Off = $null }
           @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; N = '2048'; T = 'DWord'; On = 7; Off = $null }
       ) }

    @{ Id = 'delivopt'; Group = 'ΔΙΚΤΥΟ'; Label = 'Χωρίς μοίρασμα ενημερώσεων με άλλους υπολογιστές'; Short = 'χωρίς μοίρασμα ενημερώσεων'; Recommended = $true
       What = 'Από προεπιλογή, τα Windows ανεβάζουν κομμάτια ενημερώσεων σε άλλους υπολογιστές (σαν torrent). Αυτό το κλείνει, ώστε όλο το upload να μένει για εσένα.'
       Affects = 'Οι ενημερώσεις κατεβαίνουν κανονικά από τη Microsoft. Χρήσιμο όταν κατεβάζεις torrent.'
       Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; N = 'DODownloadMode'; T = 'DWord'; On = 0; Off = $null }) }
)

function Get-TweakState($t) {
    if ($t.Get) { return [bool](& $t.Get) }
    foreach ($r in $t.Reg) { if (-not (Test-RegEqual (Get-RegValue $r.P $r.N) $r.On)) { return $false } }
    return $true
}
function Backup-CustomTweak($t) {
    $bk = Load-Backup
    $key = "custom|$($t.Id)"
    if ($bk.ContainsKey($key)) { return }
    $bk[$key] = [pscustomobject]@{ Key = $key; Path = ''; Name = $t.Id; Type = 'Custom'; Exists = [bool](Get-TweakState $t); Value = $null }
    Save-Backup $bk
}
function Set-Tweak($t, [bool]$on) {
    if ($t.CustomBackup) { Backup-CustomTweak $t }
    if ($t.Set) { & $t.Set $on }
    else {
        foreach ($r in $t.Reg) {
            Backup-RegValue $r.P $r.N $r.T
            if ($on) { Set-RegValue $r.P $r.N $r.T $r.On } else { Set-RegValue $r.P $r.N $r.T $r.Off }
        }
    }
    if ($t.After) { & $t.After $on }
    if ($t.Restart -and $t.Restart -ne 'explorer') { $State.NeedsRestart = $true }
    $txt = 'ΟΧΙ'; if ($on) { $txt = 'ΝΑΙ' }
    Write-Log "Ρύθμιση: $($t.Label) -> $txt"
}
function Restore-AllTweaks {
    $bk = Load-Backup
    if ($bk.Count -eq 0) { return 0 }
    foreach ($e in @($bk.Values)) {
        if ($e.Type -eq 'Custom') { $t = $Tweaks | Where-Object { $_.Id -eq $e.Name } | Select-Object -First 1; if ($t) { & $t.Set ([bool]$e.Exists) }; continue }
        if ($e.Exists) { Set-RegValue $e.Path $e.Name $e.Type (ConvertFrom-BackupValue $e) }
        else { Set-RegValue $e.Path $e.Name $e.Type $null }
    }
    Remove-Item (Join-Path $DataDir 'settings-backup.json') -Force
    $t1 = [int]"0$(Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1')"
    $t2 = [int]"0$(Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2')"
    $sp = [int]"0$(Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed')"
    Update-MouseNow @($t1, $t2, $sp)
    $State.NeedsRestart = $true
    Write-Log 'Επαναφορά όλων των ρυθμίσεων Windows στις αρχικές'
    return $bk.Count
}

function Set-AppGpu {
    Write-Header 'Κάρτα γραφικών ανά πρόγραμμα'
    Write-Step 'Διάλεξε το παιχνίδι ή το πρόγραμμα (αρχείο .exe) στο παράθυρο που άνοιξε...'
    $exe = Select-Exe
    if (-not $exe) { return 'Ακυρώθηκε.' }
    $cur = "$(Get-RegValue $DxPath $exe)"
    $opts = @(
        @{ Key = '1'; Label = 'Υψηλή απόδοση (η δυνατή κάρτα γραφικών)'; V = 'GpuPreference=2;'; Cur = $cur
           What = 'Το πρόγραμμα θα τρέχει πάντα στην ισχυρή κάρτα γραφικών (NVIDIA/AMD). Ιδανικό για παιχνίδια σε laptop με δύο κάρτες.'; Affects = 'Περισσότερη κατανάλωση μπαταρίας όσο τρέχει.' }
        @{ Key = '2'; Label = 'Εξοικονόμηση ενέργειας (η ενσωματωμένη κάρτα)'; V = 'GpuPreference=1;'; Cur = $cur
           What = 'Το πρόγραμμα θα τρέχει στην ενσωματωμένη κάρτα, που καταναλώνει λιγότερο.'; Affects = 'Χαμηλότερες επιδόσεις γραφικών.' }
        @{ Key = '3'; Label = 'Να αποφασίζουν τα Windows (προεπιλογή)'; V = ''; Cur = $cur
           What = 'Αφαιρεί κάθε δική σου επιλογή για αυτό το πρόγραμμα.'; Affects = 'Τίποτα.' }
    )
    foreach ($o in $opts) { $o.Status = { param($it) if ("$($it.Cur)" -eq "$($it.V)") { @{ Text = '« τώρα'; Color = 'Green' } } } }
    $r = Show-Choice -Title "Κάρτα γραφικών για: $(Split-Path $exe -Leaf)" -Items $opts `
          -HeaderLines @((L '  Έχει νόημα κυρίως σε laptop με δύο κάρτες γραφικών. Σε desktop με μία κάρτα δεν αλλάζει κάτι.' 'DarkGray'))
    if ($r -lt 0) { return 'Ακυρώθηκε.' }
    $v = $opts[$r].V; if (-not $v) { $v = $null }
    Set-RegValue $DxPath $exe 'String' $v
    Write-Log "Κάρτα γραφικών: $(Split-Path $exe -Leaf) -> $($opts[$r].Label)"
    return "$(Split-Path $exe -Leaf): $($opts[$r].Label). Ισχύει από το επόμενο άνοιγμα."
}

function Show-MemoryIntegrity {
    Write-Header 'Ακεραιότητα μνήμης'
    $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    Write-Step 'Ακεραιότητα μνήμης (Απομόνωση πυρήνα / Memory integrity)'
    if ("$v" -eq '1') { Write-Host '     Κατάσταση τώρα: ΕΝΕΡΓΗ' -ForegroundColor Green } else { Write-Host '     Κατάσταση τώρα: ανενεργή' -ForegroundColor Yellow }
    $txt = @(
        'Τι είναι: προστατεύει τον "πυρήνα" των Windows από κακόβουλα προγράμματα που προσπαθούν να μπουν βαθιά στο σύστημα.',
        'Επιδόσεις: σε ορισμένα παιχνίδια ρίχνει λίγο τα FPS (συνήθως 0-5%). Η Microsoft αναφέρει ότι οι gamers μπορούν να την κλείνουν όταν παίζουν και να την ξανανοίγουν μετά.',
        'Επειδή είναι ρύθμιση ασφαλείας, αυτό το εργαλείο δεν την αλλάζει μόνο του: την αλλάζεις εσύ από την Ασφάλεια των Windows.',
        'Η σύστασή μου: άφησέ την ανοιχτή, εκτός αν ένα συγκεκριμένο παιχνίδι έχει πρόβλημα.'
    )
    foreach ($t in $txt) { Write-Host ''; foreach ($l in @(Wrap-Text $t ((Get-Width) - 2) '     ')) { Write-Host $l } }
    if (Ask-Yes 'Να ανοίξω τη σελίδα "Απομόνωση πυρήνα" της Ασφάλειας των Windows;') { Start-Process 'windowsdefender://coreisolation' }
}

function Show-TweakMenu {
    $sel = 0; $msg = ''; $mcol = 'Green'
    while ($true) {
        $rec = (@($Tweaks | Where-Object { $_.Recommended } | ForEach-Object { $_.Short }) -join ', ')
        $items = @(
            @{ Label = 'Εφαρμογή όλων των προτεινόμενων'; Group = 'ΓΡΗΓΟΡΑ'; Action = 'rec'
               What = "Ενεργοποιεί με μία κίνηση: $rec."; Affects = 'Όλα αναιρούνται ένα-ένα ή με την "Επαναφορά όλων".' }
            @{ Label = 'Επανεκκίνηση της Εξερεύνησης'; Group = 'ΓΡΗΓΟΡΑ'; Action = 'explorer'
               What = 'Ξαναξεκινά την Εξερεύνηση και τη γραμμή εργασιών, για να ισχύσουν αμέσως αλλαγές όπως το κλασικό δεξί κλικ.'; Affects = 'Η γραμμή εργασιών εξαφανίζεται για 1-2 δευτερόλεπτα. Τα ανοιχτά παράθυρα της Εξερεύνησης κλείνουν.' }
            @{ Label = 'Επαναφορά όλων στις αρχικές ρυθμίσεις'; Group = 'ΓΡΗΓΟΡΑ'; Action = 'restore'
               What = 'Επαναφέρει κάθε ρύθμιση αυτής της λίστας ακριβώς όπως ήταν πριν την αλλάξεις από εδώ.'; Affects = 'Ισχύει πλήρως μετά από επανεκκίνηση.' }
        )
        foreach ($t in $Tweaks) {
            $items += @{ Label = $t.Label; Group = $t.Group; What = $t.What; Affects = $t.Affects; Tweak = $t
                         Status = { param($it)
                             if (Get-TweakState $it.Tweak) { @{ Text = '● Ενεργό'; Color = 'Green' } }
                             elseif ($it.Tweak.Recommended) { @{ Text = '○ Όχι · προτείνεται'; Color = 'Yellow' } }
                             else { @{ Text = '○ Όχι'; Color = 'DarkGray' } } } }
            if ($t.Id -eq 'mouse') {
                $items += @{ Label = 'Κάρτα γραφικών ανά παιχνίδι/πρόγραμμα...'; Group = $t.Group; Action = 'gpu'
                             What = 'Διαλέγεις ένα παιχνίδι ή πρόγραμμα και ορίζεις ποια κάρτα γραφικών θα χρησιμοποιεί (ισχυρή ή οικονομική).'; Affects = 'Μόνο το πρόγραμμα που διαλέγεις. Χρήσιμο κυρίως σε laptop.'
                             Status = { param($it) $n = 0; $k = Get-Item $DxPath; if ($k) { $n = @($k.Property | Where-Object { $_ -and $_ -ne 'DirectXUserGlobalSettings' }).Count }; @{ Text = "$n ρυθμισμένα"; Color = 'DarkGray' } } }
                $items += @{ Label = 'Ακεραιότητα μνήμης (πληροφορίες)...'; Group = $t.Group; Action = 'hvci'
                             What = 'Εξηγεί τι είναι η "Ακεραιότητα μνήμης", πώς επηρεάζει τα παιχνίδια και πού την αλλάζεις.'; Affects = 'Τίποτα, μόνο πληροφορίες.'
                             Status = { param($it) if ("$(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled')" -eq '1') { @{ Text = 'ενεργή'; Color = 'DarkGray' } } else { @{ Text = 'ανενεργή'; Color = 'DarkGray' } } } }
            }
        }
        $hdr = @((L '  Enter = ενεργοποίηση/απενεργοποίηση. Τίποτα δεν είναι μόνιμο: όλα αναιρούνται.' 'DarkGray'))
        if ($State.NeedsRestart) { $hdr += (L '  ! Κάποιες αλλαγές θέλουν επανεκκίνηση (κεντρικό μενού > Επανεκκίνηση).' 'Yellow') }
        $r = Show-Choice -Title 'Ρυθμίσεις Windows 11' -Items $items -Start $sel -Message $msg -MessageColor $mcol -HeaderLines $hdr
        if ($r -lt 0) { return }
        $sel = $r; $it = $items[$r]; $mcol = 'Green'
        if ($it.Action -eq 'rec') {
            $n = 0
            foreach ($t in ($Tweaks | Where-Object { $_.Recommended })) { if (-not (Get-TweakState $t)) { Set-Tweak $t $true; $n++ } }
            if ($n -gt 0) { $msg = "Εφαρμόστηκαν $n προτεινόμενες ρυθμίσεις." } else { $msg = 'Όλες οι προτεινόμενες ήταν ήδη ενεργές.' }
        }
        elseif ($it.Action -eq 'restore') {
            $n = Restore-AllTweaks
            if ($n -gt 0) { $msg = 'Όλες οι ρυθμίσεις επανήλθαν όπως ήταν. Κάνε επανεκκίνηση για να ισχύσουν πλήρως.' } else { $msg = 'Δεν έχεις αλλάξει κάποια ρύθμιση από εδώ, άρα δεν υπάρχει κάτι για επαναφορά.' }
        }
        elseif ($it.Action -eq 'explorer') {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
            $msg = 'Η Εξερεύνηση ξεκίνησε ξανά.'
        }
        elseif ($it.Action -eq 'gpu') { $msg = Set-AppGpu }
        elseif ($it.Action -eq 'hvci') { Show-MemoryIntegrity; $msg = '' }
        else {
            $t = $it.Tweak; $on = -not (Get-TweakState $t)
            Set-Tweak $t $on
            if ($on) { $msg = "Ενεργοποιήθηκε: $($t.Label)" } else { $msg = "Απενεργοποιήθηκε: $($t.Label)" }
            if ($t.Restart -eq 'restart') { $msg += ' (θέλει επανεκκίνηση)'; $mcol = 'Yellow' }
            elseif ($t.Restart -eq 'signout') { $msg += ' (θέλει αποσύνδεση ή επανεκκίνηση)'; $mcol = 'Yellow' }
            elseif ($t.Restart -eq 'explorer') { $msg += ' (πάτα "Επανεκκίνηση της Εξερεύνησης" στην κορυφή)'; $mcol = 'Yellow' }
        }
    }
}

# ======================================================================
#  ΥΓΕΙΑ & ΑΣΦΑΛΕΙΑ
# ======================================================================
function Test-Vpn {
    Write-Step 'Έλεγχος σύνδεσης VPN (Mullvad)'
    Start-Progress 'Ρωτάω τον διακομιστή ελέγχου του Mullvad...'
    Update-Progress -1 '' -Force
    $r = Get-MullvadStatus
    if (-not $r) { Stop-Progress 'αποτυχία' 'Yellow'; Write-Bad 'Δεν ήταν δυνατή η σύνδεση με τον έλεγχο του Mullvad. Έλεγξε αν έχεις ίντερνετ.'; return }
    Stop-Progress
    $ok = [bool]$r.mullvad_exit_ip
    $rows = @(
        @("IP που βλέπουν οι άλλοι : $($r.ip)"),
        @("Τοποθεσία              : $($r.city), $($r.country)"),
        @("Πάροχος                : $($r.organization)"),
        '-'
    )
    if ($ok) { $rows += , @("● ΠΡΟΣΤΑΤΕΥΜΕΝΟΣ μέσω Mullvad ($($r.mullvad_exit_ip_hostname))", 'Green') }
    else { $rows += , @('● ΧΩΡΙΣ VPN: φαίνεται η πραγματική σου IP!', 'Red') }
    Write-Box 'ΚΑΤΑΣΤΑΣΗ VPN' $rows 70
}

function Show-Health {
    Write-Step 'Αναφορά υγείας υπολογιστή'
    Start-Progress 'Συλλογή πληροφοριών...'
    Update-Progress -1 '' -Force
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name })
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    Stop-Progress
    $totalRam = [double]$os.TotalVisibleMemorySize * 1KB
    $freeRam  = [double]$os.FreePhysicalMemory * 1KB
    $up = (Get-Date) - $os.LastBootUpTime
    $rows = @(
        @("Windows       : $($os.Caption)"),
        @("Επεξεργαστής  : $("$($cpu.Name)".Trim())"),
        @("Κάρτα γραφικών: $($gpus -join ' + ')"),
        @(('Σε λειτουργία : {0} μέρες, {1} ώρες από την τελευταία επανεκκίνηση' -f $up.Days, $up.Hours))
    )
    Write-Box 'ΣΥΣΤΗΜΑ' $rows 76
    if ($up.Days -ge 7) { Write-Note 'Το PC δεν έχει κάνει επανεκκίνηση πάνω από μια εβδομάδα. Μια επανεκκίνηση βοηθάει.' }

    Write-Host ''
    $load = @($cpu | ForEach-Object { $_.LoadPercentage } | Where-Object { $null -ne $_ })   # PCs with 2 processors return a list
    if ($load.Count -gt 0) { Write-Segs (Get-GaugeLine 'Επεξεργ.' ([double](($load | Measure-Object -Average).Average)) 'φόρτος τώρα' 70 90) }
    if ($totalRam -gt 0) {
        $rp = ($totalRam - $freeRam) / $totalRam * 100
        Write-Segs (Get-GaugeLine 'Μνήμη' $rp ('{0} από {1}' -f (Format-Size ($totalRam - $freeRam)), (Format-Size $totalRam)) 80 90)
    }
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size })) {
        $used = ($v.Size - $v.SizeRemaining) / $v.Size * 100
        Write-Segs (Get-GaugeLine ("Δίσκος $($v.DriveLetter)" + ':') $used ('{0} ελεύθερα από {1}' -f (Format-Size $v.SizeRemaining), (Format-Size $v.Size)) 80 90)
    }

    $drows = @()
    foreach ($d in $disks) {
        $rel = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        switch ("$($d.HealthStatus)") {
            'Healthy'   { $health = '● Υγιής';         $color = 'Green' }
            'Warning'   { $health = '● ΠΡΟΕΙΔΟΠΟΙΗΣΗ'; $color = 'Yellow' }
            'Unhealthy' { $health = '● ΠΡΟΒΛΗΜΑ: κράτα αντίγραφα των αρχείων σου!'; $color = 'Red' }
            default     { $health = "● $($d.HealthStatus)"; $color = 'Gray' }
        }
        $drows += , @(('{0} ({1}, {2})' -f $d.FriendlyName, $d.MediaType, (Format-Size $d.Size)), 'White')
        $extra = $health
        if ($rel.Temperature) { $extra += "   · θερμοκρασία $($rel.Temperature) °C" }
        if ("$($d.MediaType)" -eq 'SSD' -and $null -ne $rel.Wear) { $extra += "   · φθορά $($rel.Wear)%" }
        $drows += , @("   $extra", $color)
    }
    if ($drows.Count -gt 0) { Write-Box 'ΔΙΣΚΟΙ' $drows 76 }

    if (Get-CimInstance Win32_Battery) {
        if (Ask-Yes 'Βρέθηκε μπαταρία. Να φτιάξω αναλυτική αναφορά μπαταρίας;') {
            $rep = Join-Path $ToolDir 'battery-report.html'
            powercfg /batteryreport /output "$rep" | Out-Null
            Start-Process $rep
            Write-Note 'Στην αναφορά σύγκρινε DESIGN CAPACITY με FULL CHARGE CAPACITY: όσο πιο κοντά, τόσο καλύτερη η μπαταρία.'
        }
    }
}

function Repair-System {
    Write-Step 'Βήμα 1 από 2 · Έλεγχος εικόνας των Windows (DISM)'
    $c1 = Invoke-NativeProgress 'Dism.exe' '/Online /Cleanup-Image /RestoreHealth' 'Συνήθως 5-20 λεπτά. Αν το ποσοστό μείνει ώρα στο ίδιο σημείο, είναι φυσιολογικό.'
    Write-Step 'Βήμα 2 από 2 · Έλεγχος αρχείων συστήματος (SFC)'
    $c2 = Invoke-NativeProgress 'sfc.exe' '/scannow' 'Συνήθως 5-15 λεπτά.'
    if ($c1 -eq 0 -and $c2 -eq 0) { $m = 'Δεν βρέθηκαν προβλήματα ή επιδιορθώθηκαν όλα.' } else { $m = 'Δες τα μηνύματα στο παράθυρο του John''s Toolkit.' }
    Send-Toast 'John''s Toolkit: η επιδιόρθωση τελείωσε' $m
}

function New-RestorePoint {
    Write-Step 'Δημιουργία σημείου επαναφοράς...'
    Enable-ComputerRestore -ErrorAction SilentlyContinue -Drive "$env:SystemDrive\"
    $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    Checkpoint-Computer -ErrorAction SilentlyContinue -Description "John's Toolkit $(Get-Date -Format 'dd-MM-yyyy HH.mm')" -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
    $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    if ($after -gt $before) { Write-Ok 'Δημιουργήθηκε σημείο επαναφοράς' }
    else { Write-Note 'Δεν δημιουργήθηκε νέο: τα Windows επιτρέπουν ένα ανά 24 ώρες, άρα υπάρχει ήδη πρόσφατο.' }
    Write-Note 'Για επαναφορά: Έναρξη > γράψε rstrui > Enter.'
}

# ======================================================================
#  ΔΙΚΤΥΟ & VPN
# ======================================================================
$SigCache = @{}
$SuspiciousPorts = @{
    23='Telnet (χωρίς κρυπτογράφηση)'; 1080='SOCKS proxy'; 1337='συχνή σε κακόβουλα προγράμματα'
    3389='Απομακρυσμένη επιφάνεια εργασίας (RDP)'; 4444='συχνή σε backdoor/Metasploit'; 5555='συχνή σε backdoor'
    5900='VNC (απομακρυσμένος έλεγχος)'; 6666='IRC (συχνό σε botnets)'; 6667='IRC (συχνό σε botnets)'
    6697='IRC (συχνό σε botnets)'; 31337='συχνή σε backdoor'
}
$TorrentApps = 'qbittorrent|utorrent|bittorrent|transmission|deluge|tixati|vuze|biglybt|frostwire'
$RemoteAccessApps = 'anydesk|teamviewer|rustdesk|ultraviewer|supremo|screenconnect|connectwise|logmein|splashtop|ammyy|rutserv|rfusclient|tvnserver|winvnc|vncserver|radmin|quickassist'
$ThreatFeeds = @(
    @{ Name='abuse.ch Feodo Tracker (botnets)'; Url='https://feodotracker.abuse.ch/downloads/ipblocklist.txt' }
    @{ Name='Emerging Threats (παραβιασμένοι υπολογιστές)'; Url='https://rules.emergingthreats.net/blockrules/compromised-ips.txt' }
)

function Test-PrivateIp([string]$ip) {
    return ($ip -match '^(10\.|127\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|0\.0\.0\.0|::1$|::$|fe80:|f[cd])')
}

function Html([string]$t) { [System.Net.WebUtility]::HtmlEncode($t) }

function Get-TrustedList {
    $f = Join-Path $DataDir 'trusted.json'
    $out = @()
    if (Test-Path $f) {
        $raw = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
        if ($raw.Trim()) { foreach ($i in (ConvertFrom-Json $raw)) { if ($i) { $out += [string]$i } } }
    }
    return $out
}

function Save-TrustedList($list) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    $json = ConvertTo-Json -InputObject @($list)
    [IO.File]::WriteAllText((Join-Path $DataDir 'trusted.json'), $json, (New-Object System.Text.UTF8Encoding $false))
}

function Get-ThreatIps {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    $cache = Join-Path $DataDir 'threat-ips.txt'
    $fresh = (Test-Path $cache) -and (((Get-Date) - (Get-Item $cache).LastWriteTime).TotalHours -lt 24)
    if (-not $fresh) {
        Start-Progress 'Ενημέρωση λιστών γνωστών κακόβουλων διευθύνσεων...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $all = New-Object System.Collections.Generic.List[string]
        foreach ($feed in $ThreatFeeds) {
            Update-Progress -1 $feed.Name -Force
            try {
                $txt = (Invoke-WebRequest -Uri $feed.Url -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop).Content
                if ($txt -is [byte[]]) { $txt = [Text.Encoding]::ASCII.GetString($txt) }
                foreach ($line in ("$txt" -split "`n")) {
                    $l = $line.Trim()
                    if ($l -match '^\d{1,3}(\.\d{1,3}){3}$') { $all.Add($l) }
                }
            } catch { Write-Note "Δεν κατέβηκε η λίστα: $($feed.Name)" }
        }
        if ($all.Count -gt 0) { [IO.File]::WriteAllLines($cache, $all) }
        Stop-Progress "$($all.Count) διευθύνσεις"
    }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    if (Test-Path $cache) { foreach ($l in [IO.File]::ReadAllLines($cache)) { [void]$set.Add($l) } }
    return ,$set
}

function Get-IpInfo($ips) {
    $info = @{}
    $list = @($ips | Select-Object -Unique | Select-Object -First 100)
    if ($list.Count -eq 0) { return $info }
    try {
        $body = ConvertTo-Json -InputObject @($list) -Compress
        $res = Invoke-RestMethod -Uri 'http://ip-api.com/batch?fields=status,country,countryCode,org,as,query' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 20 -ErrorAction Stop
        foreach ($r in $res) {
            if ($r.status -eq 'success') {
                $org = $r.org; if (-not $org) { $org = $r.as }
                $info["$($r.query)"] = [pscustomobject]@{ Country = $r.country; Code = $r.countryCode; Org = $org }
            }
        }
    } catch { Write-Note 'Δεν ήταν δυνατή η αναζήτηση χώρας/εταιρείας (ip-api.com).' }
    return $info
}

function Get-MullvadStatus {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        return Invoke-RestMethod -Uri 'https://am.i.mullvad.net/json' -TimeoutSec 15 -ErrorAction Stop
    } catch { return $null }
}

function Get-VpnIps {
    $ad = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and ("$($_.Name) $($_.InterfaceDescription)" -match 'Mullvad|WireGuard|Wintun|NordLynx|NordVPN|ProtonVPN|Proton VPN|ExpressVPN|Lightway|Surfshark|Private Internet Access|CyberGhost|IPVanish|Windscribe|TunnelBear|Cloudflare|OpenVPN|TAP-Windows|ovpn-dco|AnyConnect|Cisco Secure Client|Fortinet|PANGP') })
    if ($ad.Count -eq 0) { return @() }
    return @(Get-NetIPAddress -ErrorAction SilentlyContinue -InterfaceIndex $ad.ifIndex | Select-Object -ExpandProperty IPAddress)
}

function Get-ProcInfo([int]$procId) {
    $p = Get-Process -Id $procId
    $name = "PID $procId"; if ($p) { $name = $p.ProcessName }
    $path = $p.Path
    if (-not $path) { $path = (Get-CimInstance Win32_Process -Filter "ProcessId=$procId").ExecutablePath }
    $sig = 'Άγνωστη υπογραφή'; $pub = ''
    if ($path) {
        if (-not $SigCache.ContainsKey($path)) { $SigCache[$path] = Get-AuthenticodeSignature -FilePath $path }
        $s = $SigCache[$path]
        if ("$($s.Status)" -eq 'Valid') {
            $sig = 'Υπογεγραμμένο'
            $pub = "$($s.SignerCertificate.Subject)" -replace '^CN="?([^,"]+).*', '$1'
        } else { $sig = 'ΧΩΡΙΣ ψηφιακή υπογραφή' }
    } elseif ($procId -eq 4) { $sig = 'Υπογεγραμμένο'; $pub = 'Windows (System)' }
    [pscustomobject]@{ Name = $name; Path = $path; Sig = $sig; Publisher = $pub; Unsigned = ($sig -eq 'ΧΩΡΙΣ ψηφιακή υπογραφή') }
}

function Get-NetReport($vpnIps, $threat, $trusted, $ipInfo) {
    $conns = @(Get-NetTCPConnection -ErrorAction SilentlyContinue -State Established | Where-Object { -not (Test-PrivateIp $_.RemoteAddress) })
    $groups = @($conns | Group-Object OwningProcess); $gi = 0
    $report = foreach ($g in $groups) {
        $gi++; Update-Progress (100.0 * $gi / [Math]::Max(1, $groups.Count)) "έλεγχος προγράμματος $gi από $($groups.Count)"
        $procId = [int]$g.Name
        $pi = Get-ProcInfo $procId
        $isTorrent = ($pi.Name -match $TorrentApps)
        $isTrusted = ($pi.Path -and ($trusted -contains $pi.Path.ToLower()))
        $flags = New-Object System.Collections.Generic.List[string]
        $level = 0

        # Ενδείξεις που ισχύουν ακόμα και για αξιόπιστα προγράμματα
        $bad = @($g.Group | Where-Object { $threat.Contains("$($_.RemoteAddress)") })
        if ($bad.Count -gt 0) {
            $ips = (@($bad.RemoteAddress) | Select-Object -Unique) -join ', '
            if ($isTorrent) {
                $flags.Add("Συνδέεται με $($bad.Count) IP από λίστα παραβιασμένων υπολογιστών ($ips). Στα torrent είναι συχνό (είναι άλλοι χρήστες), αλλά σταμάτα όποιο torrent δεν εμπιστεύεσαι.")
                if ($level -lt 1) { $level = 1 }
            } else { $flags.Add("ΣΥΝΔΕΕΤΑΙ ΜΕ ΓΝΩΣΤΗ ΚΑΚΟΒΟΥΛΗ IP: $ips"); $level = 2 }
        }
        if ($vpnIps.Count -gt 0 -and $pi.Name -notmatch '^(mullvad|nordvpn|nordlynx|protonvpn|expressvpn|surfshark|pia|cyberghost|ipvanish|windscribe|warp-svc|openvpn|wireguard|tunnelbear)') {
            $outside = @($g.Group | Where-Object { $vpnIps -notcontains $_.LocalAddress })
            if ($outside.Count -gt 0) {
                if ($isTorrent) { $flags.Add("Το TORRENT έχει $($outside.Count) σύνδεση/εις ΕΚΤΟΣ VPN: φαίνεται η πραγματική σου IP!"); $level = 2 }
                elseif (-not $isTrusted) { $flags.Add("$($outside.Count) σύνδεση/εις εκτός VPN (split tunneling ή διαρροή)"); if ($level -lt 1) { $level = 1 } }
            }
        }

        # Ενδείξεις που αγνοούνται για αξιόπιστα προγράμματα
        if (-not $isTrusted) {
            if ($pi.Unsigned) { $flags.Add('Δεν έχει ψηφιακή υπογραφή (συχνό και σε αθώα μικρά προγράμματα)'); if ($level -lt 1) { $level = 1 } }
            if ($pi.Path -match '\\(Temp|Downloads)\\') { $flags.Add('Τρέχει από φάκελο Temp ή Downloads: ασυνήθιστο για κανονικό πρόγραμμα'); $level = 2 }
            if ($pi.Name -match $RemoteAccessApps) {
                $flags.Add('Πρόγραμμα ΑΠΟΜΑΚΡΥΣΜΕΝΗΣ ΠΡΟΣΒΑΣΗΣ: αν δεν το χρησιμοποιείς εσύ αυτή τη στιγμή, κλείσε το (συχνό σε απάτες)')
                if ($pi.Unsigned) { $level = 2 } elseif ($level -lt 1) { $level = 1 }
            }
            foreach ($rp in (@($g.Group.RemotePort) | Select-Object -Unique)) {
                $port = [int]$rp
                if ($SuspiciousPorts.ContainsKey($port)) {
                    $flags.Add("Θύρα $port : $($SuspiciousPorts[$port])")
                    if ($pi.Unsigned) { $level = 2 } elseif ($level -lt 1) { $level = 1 }
                }
            }
        }

        $dest = ''
        if ($ipInfo.Count -gt 0) {
            $names = foreach ($c in $g.Group) { $i = $ipInfo["$($c.RemoteAddress)"]; if ($i) { "$($i.Org) ($($i.Code))" } }
            $dest = (@($names) | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
        }
        [pscustomobject]@{ Level = $level; Name = $pi.Name; PID = $procId; Count = $g.Count; Sig = $pi.Sig; Publisher = $pi.Publisher
                           Path = $pi.Path; Trusted = $isTrusted; Flags = @($flags | Select-Object -Unique); Dest = $dest; Conns = $g.Group }
    }
    return @($report | Sort-Object @{e = 'Level'; Descending = $true}, @{e = 'Count'; Descending = $true})
}

function Watch-Network($vpnIps, $threat) {
    Write-Step 'Ζωντανή παρακολούθηση νέων συνδέσεων. Πάτα οποιοδήποτε πλήκτρο για διακοπή.'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($c in (Get-NetTCPConnection -ErrorAction SilentlyContinue -State Established)) { [void]$seen.Add("$($c.OwningProcess)|$($c.RemoteAddress)|$($c.RemotePort)") }
    Write-Host "    Υπάρχουσες συνδέσεις: $($seen.Count). Από εδώ και πέρα εμφανίζονται μόνο οι καινούριες...`n" -ForegroundColor DarkGray
    while ($true) {
        for ($t = 0; $t -lt 10; $t++) {
            Start-Sleep -Milliseconds 300
            if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); Write-Ok 'Η παρακολούθηση σταμάτησε'; Start-Sleep 1; return }
        }
        $new = @(Get-NetTCPConnection -ErrorAction SilentlyContinue -State Established | Where-Object {
            -not (Test-PrivateIp $_.RemoteAddress) -and $seen.Add("$($_.OwningProcess)|$($_.RemoteAddress)|$($_.RemotePort)") })
        foreach ($g in ($new | Group-Object OwningProcess)) {
            $pi = Get-ProcInfo ([int]$g.Name)
            $time = Get-Date -Format 'HH:mm:ss'
            $isTorrent = ($pi.Name -match $TorrentApps)
            foreach ($c in ($g.Group | Select-Object -First 5)) {
                $warn = @(); $red = $false
                if ($threat.Contains("$($c.RemoteAddress)")) { $warn += 'ΚΑΚΟΒΟΥΛΗ IP'; if (-not $isTorrent) { $red = $true } }
                $via = ''
                if ($vpnIps.Count -gt 0 -and $pi.Name -notmatch '^(mullvad|nordvpn|nordlynx|protonvpn|expressvpn|surfshark|pia|cyberghost|ipvanish|windscribe|warp-svc|openvpn|wireguard|tunnelbear)') {
                    if ($vpnIps -contains $c.LocalAddress) { $via = '[VPN]' }
                    else { $via = '[ΕΚΤΟΣ VPN]'; $warn += 'εκτός VPN'; if ($isTorrent) { $red = $true } }
                }
                if ($pi.Name -match $RemoteAccessApps) { $warn += 'απομακρυσμένη πρόσβαση' }
                $col = 'Gray'
                if ($warn.Count -gt 0) { $col = 'Yellow' }
                if ($red) { $col = 'Red'; [Console]::Beep(1000, 250) }
                Write-Host ('    {0}  + {1,-18} -> {2}:{3}  {4} {5}' -f $time, $pi.Name, $c.RemoteAddress, $c.RemotePort, $via, ($warn -join ', ')) -ForegroundColor $col
            }
            if ($g.Count -gt 5) { Write-Host "    $time    ...και άλλες $($g.Count - 5) νέες συνδέσεις από $($pi.Name)" -ForegroundColor DarkGray }
        }
    }
}

function Export-NetReport($report, $st, $threatCount) {
    $dir = Join-Path $ToolDir 'reports'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir ('network-{0}.html' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!DOCTYPE html><html lang="el"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Αναφορά δικτύου</title><style>')
    [void]$sb.Append('body{font-family:"Segoe UI",Arial,sans-serif;margin:24px;background:#f4f5f7;color:#1d1d1f}h1{margin:0 0 4px}p.meta{color:#666;margin:0 0 16px}')
    [void]$sb.Append('.vpn{padding:10px 14px;border-radius:8px;margin-bottom:16px;font-weight:600}.ok{background:#e3f5e7;color:#1b6b2f}.bad{background:#fde4e4;color:#a11}')
    [void]$sb.Append('table{border-collapse:collapse;width:100%;background:#fff;border-radius:8px;overflow:hidden}th,td{padding:8px 10px;text-align:left;vertical-align:top;font-size:14px;border-bottom:1px solid #eee}')
    [void]$sb.Append('th{background:#2b2d31;color:#fff}.l0 td:first-child{border-left:6px solid #2e9e44}.l1 td:first-child{border-left:6px solid #e0a800}.l2{background:#fff3f3}.l2 td:first-child{border-left:6px solid #d33}')
    [void]$sb.Append('small{color:#777}ul{margin:0;padding-left:18px}</style></head><body>')
    [void]$sb.Append("<h1>Αναφορά δικτύου</h1><p class=""meta"">$(Get-Date -Format 'dd/MM/yyyy HH:mm') &middot; $(Html $env:COMPUTERNAME) &middot; λίστα κακόβουλων IP: $threatCount</p>")
    if ($st) {
        if ($st.mullvad_exit_ip) { [void]$sb.Append("<div class=""vpn ok"">VPN συνδεδεμένο μέσω Mullvad ($(Html $st.mullvad_exit_ip_hostname)), δημόσια IP $(Html $st.ip), $(Html $st.country)</div>") }
        else { [void]$sb.Append("<div class=""vpn bad"">ΧΩΡΙΣ VPN: η δημόσια IP $(Html $st.ip) είναι η πραγματική</div>") }
    }
    [void]$sb.Append('<table><tr><th>Κατάσταση</th><th>Πρόγραμμα</th><th>Συνδέσεις</th><th>Υπογραφή</th><th>Προορισμοί</th><th>Ενδείξεις</th></tr>')
    $labels = @('OK', 'ΠΡΟΣΟΧΗ', 'ΕΛΕΓΞΕ ΤΟ')
    foreach ($r in $report) {
        $who = $r.Sig; if ($r.Publisher) { $who = "$($r.Sig): $($r.Publisher)" }
        if ($r.Trusted) { $who += ' (αξιόπιστο)' }
        $flags = ''
        if ($r.Flags.Count -gt 0) { $flags = '<ul>' + (($r.Flags | ForEach-Object { "<li>$(Html $_)</li>" }) -join '') + '</ul>' }
        [void]$sb.Append("<tr class=""l$($r.Level)""><td>$($labels[$r.Level])</td><td><b>$(Html $r.Name)</b><br><small>$(Html $r.Path)</small></td><td>$($r.Count)</td><td>$(Html $who)</td><td>$(Html $r.Dest)</td><td>$flags</td></tr>")
    }
    [void]$sb.Append('</table><p class="meta" style="margin-top:16px">Οι ενδείξεις δεν είναι βεβαιότητα. Για σίγουρη απάντηση κάνε σάρωση με antivirus.</p></body></html>')
    [IO.File]::WriteAllText($file, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    Start-Process $file
    Write-Ok "Η αναφορά αποθηκεύτηκε: $file"
    Write-Note 'Περιέχει τις IP των συνδέσεών σου. Μοιράσου την μόνο με όποιον εμπιστεύεσαι.'
    Start-Sleep 2
}

# ======================================================================
#  ΑΥΤΟΜΑΤΙΣΜΟΙ
# ======================================================================
function Set-AutoClean {
    if (Get-ScheduledTask -ErrorAction SilentlyContinue -TaskName $TaskName) {
        Write-Note 'Ο αυτόματος καθαρισμός είναι ΗΔΗ ΕΝΕΡΓΟΣ (κάθε Κυριακή 20:00).'
        if (Ask-Yes 'Να τον απενεργοποιήσω;') {
            Unregister-ScheduledTask -ErrorAction SilentlyContinue -TaskName $TaskName -Confirm:$false
            Write-Ok 'Απενεργοποιήθηκε'
        }
        return
    }
    $loader = Join-Path $ToolDir '_loader.ps1'
    if ($AppRoot) { $loader = Join-Path $AppRoot 'app\Launcher.ps1' }
    try {
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$loader`" -Auto"
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '20:00'
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        Write-Ok 'Ενεργοποιήθηκε: κάθε Κυριακή στις 20:00 (ή μόλις ανοίξει το PC, αν ήταν κλειστό).'
        Write-Note 'Μην μετακινήσεις τον φάκελο PC-Tools. Αν τον μετακινήσεις, τρέξε ξανά αυτή την επιλογή.'
        Write-Note "Ιστορικό καθαρισμών: $ToolDir\logs\auto-cleanup.log"
    } catch {
        Write-Bad "Δεν ήταν δυνατή η ενεργοποίηση: $($_.Exception.Message)"
    }
}

function Invoke-AutoClean {
    $logDir = Join-Path $ToolDir 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $before = Get-FreeGB
    Clear-TempFiles; Clear-UpdateCache; Clear-Dns
    $freed = [math]::Round((Get-FreeGB) - $before, 2)
    Add-Content -Path (Join-Path $logDir 'auto-cleanup.log') -Encoding UTF8 -Value "$(Get-Date -Format 'dd/MM/yyyy HH:mm')  Ελευθερώθηκαν $freed GB"
    if ($freed -gt 0.05) { Send-Toast 'John''s Toolkit: αυτόματος καθαρισμός' "Ελευθερώθηκαν $freed GB." }
}

# ======================================================================
#  ΕΛΕΓΧΟΣ ΥΠΟΛΕΙΜΜΑΤΩΝ (με αντίγραφο ασφαλείας και επαναφορά)
# ======================================================================
function Get-ExePathFromCommand([string]$cmd) {
    if (-not $cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c -match '^"([^"]+)"') { return $matches[1] }
    if ($c -match '^(.+?\.(exe|com|bat|cmd|lnk|vbs|ps1))(\s|$)') { return $matches[1] }
    return ($c -split ' ')[0]
}
function Test-MissingPath([string]$p) {
    if (-not $p) { return $false }
    try {
        if (-not [IO.Path]::IsPathRooted($p)) { return $false }
        if ($p -match '^\\\\') { return $false }
        $root = [IO.Path]::GetPathRoot($p)
        if (-not (Test-Path -LiteralPath $root)) { return $false }
        return (-not (Test-Path -LiteralPath $p))
    } catch { return $false }
}
function Get-ShortcutTarget([string]$file) {
    try { $ws = New-Object -ComObject WScript.Shell; return $ws.CreateShortcut($file).TargetPath } catch { return $null }
}
function Get-RegExportPath([string]$psPath) {
    return ($psPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\')
}

function Find-Leftovers {
    $found = @()
    Start-Progress 'Ψάχνω υπολείμματα...'

    Update-Progress 5 'προγράμματα εκκίνησης' -Force
    foreach ($e in @(Get-StartupEntries)) {
        if ($e.Kind -eq 'Folder') { $target = $e.Command; if ($e.Command -match '\.lnk$') { $target = Get-ShortcutTarget $e.Command } }
        else { $target = Get-ExePathFromCommand $e.Command }
        if (Test-MissingPath $target) {
            $found += [pscustomobject]@{ Cat = 'startup'; Label = $e.Name; Missing = $target; E = $e
                                         Why = 'Πρόγραμμα εκκίνησης που δείχνει σε αρχείο που δεν υπάρχει πια. Τα Windows το ψάχνουν σε κάθε εκκίνηση χωρίς λόγο.' }
        }
    }

    $dirs = @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ }
    $lnks = @(foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Filter *.lnk -Recurse -File -Force -ErrorAction SilentlyContinue })
    $i = 0
    foreach ($l in $lnks) {
        $i++; if ($i % 10 -eq 0) { Update-Progress (10 + 50.0 * $i / [Math]::Max(1, $lnks.Count)) "συντομεύσεις $i/$($lnks.Count)" }
        $t = Get-ShortcutTarget $l.FullName
        if (-not $t -or $t -match '://') { continue }
        if (Test-MissingPath $t) {
            $found += [pscustomobject]@{ Cat = 'shortcut'; Label = $l.BaseName; Missing = $t; File = $l.FullName
                                         Why = "Συντόμευση που δείχνει σε πρόγραμμα ή αρχείο που δεν υπάρχει πια. Βρίσκεται στο: $($l.DirectoryName)" }
        }
    }

    Update-Progress 65 'λίστα εγκατεστημένων εφαρμογών' -Force
    $ukeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($uk in $ukeys) {
        foreach ($sub in @(Get-ChildItem -Path $uk -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.DisplayName) { continue }
            if ($p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.WindowsInstaller -eq 1) { continue }
            $u = "$($p.UninstallString)"
            if (-not $u -or $u -match 'msiexec') { continue }
            $exe = Get-ExePathFromCommand $u
            if (-not (Test-MissingPath $exe)) { continue }
            if ($p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation)) { continue }
            $found += [pscustomobject]@{ Cat = 'uninstall'; Label = "$($p.DisplayName)"; Missing = $exe; RegPath = $sub.PSPath; RegName = $sub.Name
                                         Why = 'Εμφανίζεται στις "Εγκατεστημένες εφαρμογές", αλλά το πρόγραμμα έχει ήδη σβηστεί και δεν απεγκαθίσταται.' }
        }
    }

    Update-Progress 85 'προγραμματισμένες εργασίες' -Force
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        if ($t.TaskPath -like '\Microsoft\*' -or $t.TaskName -eq $TaskName) { continue }
        $acts = @($t.Actions | Where-Object { $_.Execute })
        if ($acts.Count -eq 0) { continue }
        $miss = $true; $first = $null
        foreach ($a in $acts) {
            $e = Get-ExePathFromCommand ('"' + "$($a.Execute)".Trim('"') + '"')
            if (-not $first) { $first = $e }
            if (-not (Test-MissingPath $e)) { $miss = $false }
        }
        if ($miss) {
            $found += [pscustomobject]@{ Cat = 'task'; Label = "$($t.TaskPath)$($t.TaskName)"; Missing = $first; T = $t
                                         Why = 'Προγραμματισμένη εργασία προγράμματος που έχει σβηστεί. Τα Windows προσπαθούν μάταια να την τρέξουν.' }
        }
    }
    Stop-Progress "βρέθηκαν $($found.Count)"
    return $found
}

function Remove-Leftovers($list) {
    $dir = Join-Path $DataDir ('backup\' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $manifest = @(); $ok = 0; $fail = 0; $n = 0
    Start-Progress 'Αφαίρεση με αντίγραφο ασφαλείας...'
    foreach ($x in $list) {
        $n++; Update-Progress (100.0 * $n / $list.Count) $x.Label -Force
        $done = $false
        try {
            if ($x.Cat -eq 'startup' -and $x.E.Kind -eq 'Run') {
                $f = Join-Path $dir ("startup_$n.reg")
                & reg.exe export (Get-RegExportPath $x.E.Key) $f /y 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Remove-ItemProperty -Path $x.E.Key -Name $x.E.Name -ErrorAction Stop
                    Remove-ItemProperty -Path $x.E.Appr -Name $x.E.Name -ErrorAction SilentlyContinue
                    $manifest += [pscustomobject]@{ Type = 'reg'; Label = $x.Label; File = $f; Extra = '' }; $done = $true
                }
            }
            elseif (($x.Cat -eq 'startup' -and $x.E.Kind -eq 'Folder') -or $x.Cat -eq 'shortcut') {
                $src = $x.File; if ($x.Cat -eq 'startup') { $src = $x.E.Command }
                $f = Join-Path $dir ("file_$n" + [IO.Path]::GetExtension($src))
                Move-Item -LiteralPath $src -Destination $f -Force -ErrorAction Stop
                $manifest += [pscustomobject]@{ Type = 'file'; Label = $x.Label; File = $f; Extra = $src }; $done = $true
            }
            elseif ($x.Cat -eq 'uninstall') {
                $f = Join-Path $dir ("uninstall_$n.reg")
                & reg.exe export $x.RegName $f /y 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Remove-Item -LiteralPath $x.RegPath -Recurse -Force -ErrorAction Stop
                    $manifest += [pscustomobject]@{ Type = 'reg'; Label = $x.Label; File = $f; Extra = '' }; $done = $true
                }
            }
            elseif ($x.Cat -eq 'task') {
                $f = Join-Path $dir ("task_$n.xml")
                $xml = Export-ScheduledTask -TaskName $x.T.TaskName -TaskPath $x.T.TaskPath -ErrorAction Stop
                [IO.File]::WriteAllText($f, $xml, [Text.Encoding]::Unicode)
                Unregister-ScheduledTask -TaskName $x.T.TaskName -TaskPath $x.T.TaskPath -Confirm:$false -ErrorAction Stop
                $manifest += [pscustomobject]@{ Type = 'task'; Label = $x.Label; File = $f; Extra = "$($x.T.TaskPath)|$($x.T.TaskName)" }; $done = $true
            }
        } catch { $done = $false }
        if ($done) { $ok++; Write-Log "Υπόλειμμα: αφαιρέθηκε $($x.Label)" } else { $fail++ }
    }
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), (ConvertTo-Json -InputObject @($manifest) -Depth 3), (New-Object System.Text.UTF8Encoding $false))
    Stop-Progress "αφαιρέθηκαν $ok"
    return [pscustomobject]@{ Ok = $ok; Fail = $fail; Dir = $dir }
}

function Show-Leftovers {
    Write-Header 'Έλεγχος υπολειμμάτων'
    $found = @(Find-Leftovers)
    if ($found.Count -eq 0) { Write-Box 'ΑΠΟΤΕΛΕΣΜΑ' @(, @('● Δεν βρέθηκαν σπασμένες εγγραφές. Όλα καθαρά!', 'Green')) 64; Pause-Key; return }
    $names = @{ startup = 'ΠΡΟΓΡΑΜΜΑΤΑ ΕΚΚΙΝΗΣΗΣ ΧΩΡΙΣ ΑΡΧΕΙΟ'; shortcut = 'ΣΠΑΣΜΕΝΕΣ ΣΥΝΤΟΜΕΥΣΕΙΣ'; uninstall = '"ΦΑΝΤΑΣΜΑΤΑ" ΣΤΙΣ ΕΓΚΑΤΕΣΤΗΜΕΝΕΣ ΕΦΑΡΜΟΓΕΣ'; task = 'ΟΡΦΑΝΕΣ ΠΡΟΓΡΑΜΜΑΤΙΣΜΕΝΕΣ ΕΡΓΑΣΙΕΣ' }
    $order = @{ startup = 0; shortcut = 1; uninstall = 2; task = 3 }
    $found = @($found | Sort-Object @{ e = { $order[$_.Cat] } }, Label)
    $items = @(); $pre = @()
    for ($i = 0; $i -lt $found.Count; $i++) {
        $x = $found[$i]; $pre += $i
        $items += @{ Label = $x.Label; Group = $names[$x.Cat]
                     Lines = @((L $x.Why $Theme.Text), (L "Λείπει: $($x.Missing)" $Theme.Dim), (L 'Κρατιέται αντίγραφο ασφαλείας: επαναφέρεται από το "Επαναφορά υπολειμμάτων".' $Theme.Ok)) }
    }
    $res = Show-Choice -Title 'Έλεγχος υπολειμμάτων' -Items $items -Multi -PreChecked $pre `
            -HeaderLines @((L "  Βρέθηκαν $($found.Count) σπασμένες εγγραφές. Όλες είναι τσεκαρισμένες: ξετσέκαρε με Space όσες θέλεις να μείνουν." $Theme.Text))
    if ($res -is [int]) { return }
    $picked = @($res | ForEach-Object { $found[$_] })
    Write-Header 'Έλεγχος υπολειμμάτων'
    if ($picked.Count -eq 0) { Write-Note 'Δεν επέλεξες κάτι.'; Pause-Key; return }
    if (-not (Ask-Yes "Να αφαιρεθούν $($picked.Count) εγγραφές; (κρατιέται αντίγραφο)")) { return }
    $r = Remove-Leftovers $picked
    $rows = @(, @("● Αφαιρέθηκαν: $($r.Ok)", 'Green'))
    if ($r.Fail -gt 0) { $rows += , @("● Δεν ήταν δυνατή η αφαίρεση: $($r.Fail) (ίσως προστατεύονται)", 'Yellow') }
    $rows += , @('Αντίγραφο: Καθαρισμός χώρου > Επαναφορά υπολειμμάτων', $Theme.Dim)
    Write-Box 'ΑΠΟΤΕΛΕΣΜΑ' $rows 70
    Pause-Key
}

function Show-LeftoverRestore {
    $root = Join-Path $DataDir 'backup'
    $sessions = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } | Sort-Object Name -Descending)
    if ($sessions.Count -eq 0) { Write-Header 'Επαναφορά υπολειμμάτων'; Write-Note 'Δεν υπάρχουν αντίγραφα ασφαλείας ακόμα.'; Pause-Key; return }
    $items = @()
    foreach ($s in $sessions) {
        $m = @(); foreach ($e in (ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $s.FullName 'manifest.json'), [Text.Encoding]::UTF8)))) { if ($e.Type) { $m += $e } }
        $when = $s.Name -replace '^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2}).*', '$3/$2/$1 $4:$5'
        $lines = @((L 'Enter = επαναφορά όλων όσων αφαιρέθηκαν τότε:' $Theme.Warn))
        foreach ($e in ($m | Select-Object -First 6)) { $lines += (L "· $($e.Label)" $Theme.Text) }
        if ($m.Count -gt 6) { $lines += (L "· ...και άλλα $($m.Count - 6)" $Theme.Dim) }
        $items += @{ Label = "$when   ($($m.Count) εγγραφές)"; Lines = $lines; M = $m; Dir = $s.FullName }
    }
    $x = Show-Choice -Title 'Επαναφορά υπολειμμάτων' -Items $items
    if ($x -lt 0) { return }
    Write-Header 'Επαναφορά υπολειμμάτων'
    if (-not (Ask-Yes 'Να επαναφερθούν όλα από αυτό το αντίγραφο;')) { return }
    $ok = 0; $fail = 0
    foreach ($e in $items[$x].M) {
        try {
            if ($e.Type -eq 'reg') { & reg.exe import $e.File 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'reg' } }
            elseif ($e.Type -eq 'file') { $d = Split-Path $e.Extra -Parent; New-Item -ItemType Directory -Path $d -Force | Out-Null; Move-Item -LiteralPath $e.File -Destination $e.Extra -Force -ErrorAction Stop }
            elseif ($e.Type -eq 'task') {
                $tp, $tn = $e.Extra -split '\|', 2
                Register-ScheduledTask -Xml ([IO.File]::ReadAllText($e.File)) -TaskName $tn -TaskPath $tp -Force -ErrorAction Stop | Out-Null
            }
            $ok++
        } catch { $fail++ }
    }
    if ($fail -eq 0) { Remove-Item -LiteralPath $items[$x].Dir -Recurse -Force }
    Write-Log "Επαναφορά υπολειμμάτων: $ok επιτυχίες, $fail αποτυχίες"
    Write-Box 'ΑΠΟΤΕΛΕΣΜΑ' @(, @("● Επαναφέρθηκαν: $ok", 'Green')) 64
    if ($fail -gt 0) { Write-Note "Δεν ήταν δυνατή η επαναφορά για $fail εγγραφές." }
    Pause-Key
}

# ======================================================================
#  ΕΛΕΓΧΟΣ ΑΣΦΑΛΕΙΑΣ
# ======================================================================
function Show-SecurityCheck {
    Write-Step 'Έλεγχος ασφάλειας'
    Start-Progress 'Έλεγχος ρυθμίσεων ασφαλείας...'
    Update-Progress -1 '' -Force
    $rows = @(); $bad = 0
    function Add-Row([string]$txt, [string]$state) {
        $c = 'Green'; $dot = '●'
        if ($state -eq 'warn') { $c = 'Yellow' } elseif ($state -eq 'bad') { $c = 'Red' } elseif ($state -eq 'info') { $c = 'Gray'; $dot = '○' }
        $script:secRows += , @("$dot $txt", $c)
    }
    $script:secRows = @()

    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object { $_.displayName } | Select-Object -Unique)
    if ($mp -and $mp.RealTimeProtectionEnabled) {
        Add-Row 'Microsoft Defender: προστασία σε πραγματικό χρόνο ενεργή' 'ok'
        if ($mp.AntivirusSignatureAge -gt 3) { Add-Row "Οι ορισμοί ιών είναι $($mp.AntivirusSignatureAge) ημερών: κάνε Windows Update" 'warn' }
    } elseif ($av.Count -gt 0 -and @($av | Where-Object { $_ -notmatch 'Defender' }).Count -gt 0) {
        Add-Row "Antivirus: $(($av | Where-Object { $_ -notmatch 'Defender' }) -join ', ')" 'ok'
    } else { Add-Row 'ΔΕΝ βρέθηκε ενεργή προστασία από ιούς!' 'bad' }

    $fw = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    if ($fw.Count -gt 0) {
        $off = @($fw | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
        if ($off.Count -eq 0) { Add-Row 'Τείχος προστασίας: ενεργό σε όλα τα δίκτυα' 'ok' } else { Add-Row "Τείχος προστασίας ΚΛΕΙΣΤΟ για: $($off -join ', ')" 'bad' }
    }
    if ("$(Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA')" -eq '0') { Add-Row 'Ο Έλεγχος λογαριασμού χρήστη (UAC) είναι κλειστός' 'bad' } else { Add-Row 'Έλεγχος λογαριασμού χρήστη (UAC): ενεργός' 'ok' }
    if ("$(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections')" -eq '0') { Add-Row 'Η Απομακρυσμένη επιφάνεια εργασίας (RDP) είναι ανοιχτή: κλείσ'' την αν δεν τη χρειάζεσαι' 'warn' } else { Add-Row 'Απομακρυσμένη επιφάνεια εργασίας: κλειστή' 'ok' }
    $smb = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($smb) { if ($smb.EnableSMB1Protocol) { Add-Row 'Το παλιό SMBv1 είναι ενεργό (στόχος παλιών ιών): καλύτερα να κλείσει' 'warn' } else { Add-Row 'SMBv1 (παλιό, επικίνδυνο πρωτόκολλο): κλειστό' 'ok' } }
    try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { Add-Row 'Secure Boot: ενεργό' 'ok' } else { Add-Row 'Secure Boot: ανενεργό' 'warn' } } catch {}
    $hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($hf) {
        $days = [int]((Get-Date) - $hf.InstalledOn).TotalDays
        if ($days -le 40) { Add-Row "Τελευταία ενημέρωση Windows: πριν από $days ημέρες" 'ok' } else { Add-Row "Τελευταία ενημέρωση Windows: πριν από $days ημέρες. Κάνε Windows Update" 'warn' }
    }
    $ra = @()
    foreach ($uk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($sub in @(Get-ChildItem -Path $uk -ErrorAction SilentlyContinue)) { $n = (Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue).DisplayName; if ("$n" -match 'TeamViewer|AnyDesk|RustDesk|UltraViewer|Supremo|ScreenConnect|Splashtop|LogMeIn|Ammyy|Radmin|VNC') { $ra += "$n" } }
    }
    if ($ra.Count -gt 0) { Add-Row "Προγράμματα απομακρυσμένης πρόσβασης: $(($ra | Select-Object -Unique) -join ', '). Κράτα τα μόνο αν τα χρησιμοποιείς" 'info' }
    Stop-Progress

    $rows = $script:secRows
    $bad = @($rows | Where-Object { $_[1] -eq 'Red' }).Count; $warn = @($rows | Where-Object { $_[1] -eq 'Yellow' }).Count
    $wrapped = @()
    foreach ($r in $rows) { $first = $true; foreach ($l in @(Wrap-Text $r[0] 70 '')) { if ($first) { $wrapped += , @($l, $r[1]); $first = $false } else { $wrapped += , @("  $l", $r[1]) } } }
    $wrapped += '-'
    if ($bad -eq 0 -and $warn -eq 0) { $wrapped += , @('Όλα εντάξει!', 'Green') } else { $wrapped += , @("Σοβαρά: $bad · Προειδοποιήσεις: $warn", 'Yellow') }
    Write-Box 'ΕΛΕΓΧΟΣ ΑΣΦΑΛΕΙΑΣ' $wrapped 76
    if ($bad -gt 0 -or $warn -gt 0) {
        if (Ask-Yes 'Να ανοίξω την Ασφάλεια των Windows για να τα διορθώσεις;') { Start-Process 'windowsdefender:' }
    }
    $mpExe = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if ($mp -and (Test-Path $mpExe)) {
        if (Ask-Yes 'Να κάνω γρήγορη σάρωση για ιούς με τον Defender; (λίγα λεπτά)') {
            Write-Step 'Γρήγορη σάρωση Microsoft Defender'
            $null = Invoke-NativeProgress $mpExe '-Scan -ScanType 1' 'Σάρωση σημείων όπου κρύβονται συνήθως οι ιοί...'
            Send-Toast 'John''s Toolkit: σάρωση ιών' 'Η γρήγορη σάρωση τελείωσε. Δες το αποτέλεσμα στο John''s Toolkit.'
        }
    }
}

function Show-NetDetails($r, $vpnIps, $ipInfo) {
    $changed = $false; $hash = $null; $dns = @{}
    if ($r.Path) { $hash = (Get-FileHash -Path $r.Path -Algorithm SHA256).Hash }
    $sel = 0; $msg = ''; $mcol = 'Green'
    while ($true) {
        $isTr = ($r.Path -and (@(Get-TrustedList) -contains $r.Path.ToLower()))
        $hdr = @((L "  Αρχείο : $($r.Path)" 'Gray'))
        if ($hash) { $hdr += (L "  SHA256 : $hash" 'DarkGray') }
        $hdr += (L ''); $hdr += (L "  Συνδέσεις ($($r.Count)):" 'Cyan')
        foreach ($c in ($r.Conns | Select-Object -First 8)) {
            $via = ''
            if ($vpnIps.Count -gt 0) { if ($vpnIps -contains $c.LocalAddress) { $via = '[VPN]' } else { $via = '[ΕΚΤΟΣ VPN]' } }
            $extra = ''
            $i = $ipInfo["$($c.RemoteAddress)"]; if ($i) { $extra = "$($i.Org), $($i.Country)" }
            if ($dns.ContainsKey("$($c.RemoteAddress)")) { $extra = "$extra  $($dns["$($c.RemoteAddress)"])".Trim() }
            $col = 'Gray'; if ($via -eq '[ΕΚΤΟΣ VPN]') { $col = 'Yellow' }
            $hdr += (L ('    {0,-28} :{1,-6} {2,-12} {3}' -f $c.RemoteAddress, $c.RemotePort, $via, $extra) $col)
        }
        if ($r.Count -gt 8) { $hdr += (L "    ...και άλλες $($r.Count - 8)" 'DarkGray') }
        $trLabel = 'Σήμανση ως αξιόπιστο'; if ($isTr) { $trLabel = 'Αφαίρεση από τα αξιόπιστα' }
        $acts = @(
            @{ Key = '1'; A = 'O'; Label = 'Άνοιγμα φακέλου του προγράμματος'; What = 'Ανοίγει την Εξερεύνηση στο σημείο όπου βρίσκεται το αρχείο.'; Affects = 'Τίποτα.' }
            @{ Key = '2'; A = 'S'; Label = 'Σάρωση με Microsoft Defender'; What = 'Ελέγχει το αρχείο του προγράμματος για ιούς. Διαρκεί λίγα δευτερόλεπτα.'; Affects = 'Τίποτα.' }
            @{ Key = '3'; A = 'V'; Label = 'Έλεγχος στο VirusTotal'; What = 'Ανοίγει στον browser την αναζήτηση με το "αποτύπωμα" (SHA256) του αρχείου, για να δεις τι λένε 70+ antivirus.'; Affects = 'Το αρχείο σου ΔΕΝ ανεβαίνει πουθενά. Αν το VirusTotal δεν το γνωρίζει, δεν σημαίνει απαραίτητα κάτι κακό.' }
            @{ Key = '4'; A = 'D'; Label = 'Ονόματα διακομιστών (DNS)'; What = 'Βρίσκει το όνομα πίσω από κάθε IP (π.χ. ...1e100.net = Google).'; Affects = 'Παίρνει λίγα δευτερόλεπτα.' }
            @{ Key = '5'; A = 'T'; Label = $trLabel; What = 'Τα αξιόπιστα προγράμματα δεν εμφανίζονται πια με κίτρινο για μικροπράγματα (π.χ. χωρίς υπογραφή).'; Affects = 'Για ασφάλεια, κακόβουλες IP και torrent εκτός VPN εμφανίζονται ΠΑΝΤΑ.' }
            @{ Key = '6'; A = 'K'; Label = 'Κλείσιμο του προγράμματος'; What = 'Τερματίζει αμέσως το πρόγραμμα και όλες τις συνδέσεις του.'; Affects = 'Ό,τι δεν έχει αποθηκευτεί χάνεται. Αν είναι πρόγραμμα των Windows, μπορεί να προκαλέσει προβλήματα.' }
        )
        $x = Show-Choice -Title "Δίκτυο › $($r.Name)" -Items $acts -Start $sel -Message $msg -MessageColor $mcol -HeaderLines $hdr
        if ($x -lt 0) { return $changed }
        $sel = $x; $a = $acts[$x].A; $mcol = 'Green'
        if (-not $r.Path -and $a -ne 'K' -and $a -ne 'D') { $msg = 'Δεν είναι γνωστό το αρχείο αυτού του προγράμματος.'; $mcol = 'Yellow'; continue }
        if ($a -eq 'O') { Start-Process explorer.exe -ArgumentList "/select,`"$($r.Path)`""; $msg = 'Άνοιξε η Εξερεύνηση.' }
        elseif ($a -eq 'S') {
            Write-Header "Σάρωση: $($r.Name)"
            $mp = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
            if (Test-Path $mp) { Write-Step "Σάρωση του $($r.Name) με Microsoft Defender..."; & $mp -Scan -ScanType 3 -File "$($r.Path)" | Out-Host }
            else { Write-Bad 'Δεν βρέθηκε ο Microsoft Defender (ίσως έχεις άλλο antivirus: σάρωσε το αρχείο από εκεί).' }
            Pause-Key; $msg = ''
        }
        elseif ($a -eq 'V') { Start-Process "https://www.virustotal.com/gui/file/$hash"; $msg = 'Άνοιξε το VirusTotal στον browser.' }
        elseif ($a -eq 'D') {
            foreach ($c in ($r.Conns | Select-Object -First 8)) {
                $hn = (Resolve-DnsName -ErrorAction SilentlyContinue -Name $c.RemoteAddress -Type PTR -DnsOnly -QuickTimeout | Select-Object -First 1).NameHost
                if ($hn) { $dns["$($c.RemoteAddress)"] = $hn } else { $dns["$($c.RemoteAddress)"] = '(χωρίς όνομα)' }
            }
            $msg = 'Τα ονόματα φαίνονται δίπλα σε κάθε σύνδεση.'
        }
        elseif ($a -eq 'T') {
            $key = $r.Path.ToLower(); $list = @(Get-TrustedList)
            if ($list -contains $key) { $list = @($list | Where-Object { $_ -ne $key }); $msg = 'Αφαιρέθηκε από τα αξιόπιστα.' }
            else { $list += $key; $msg = 'Σημειώθηκε ως αξιόπιστο.' }
            Save-TrustedList $list; $changed = $true
        }
        elseif ($a -eq 'K') {
            Write-Header "Κλείσιμο: $($r.Name)"
            if ($r.Publisher -match 'Microsoft') { Write-Note 'Είναι πρόγραμμα της Microsoft/Windows. Το κλείσιμό του μπορεί να προκαλέσει προβλήματα.' }
            if (Ask-Yes "Σίγουρα να κλείσει το $($r.Name);") { Stop-Process -Id $r.PID -Force; Write-Log "Κλείσιμο προγράμματος: $($r.Name)"; return $changed }
            $msg = ''
        }
    }
}

function Show-Network {
    Write-Header 'Διαγνωστικό δικτύου'
    Write-Step 'Προετοιμασία...'
    $st = Get-MullvadStatus
    $vpnIps = @(Get-VpnIps)
    $threat = Get-ThreatIps
    $trusted = @(Get-TrustedList)
    $ipInfo = @{}
    if (Ask-Yes 'Να δείξω σε ποια χώρα/εταιρεία ανήκει κάθε σύνδεση; (στέλνει τη λίστα των IP στο ip-api.com)') {
        $ips = @(Get-NetTCPConnection -ErrorAction SilentlyContinue -State Established | Where-Object { -not (Test-PrivateIp $_.RemoteAddress) } | Select-Object -ExpandProperty RemoteAddress)
        $ipInfo = Get-IpInfo $ips
    }
    $sel = 0; $msg = ''
    while ($true) {
        Write-Header 'Διαγνωστικό δικτύου'
        Start-Progress 'Ανάλυση συνδέσεων και ψηφιακών υπογραφών...'
        $report = @(Get-NetReport $vpnIps $threat $trusted $ipInfo)
        Stop-Progress "$($report.Count) προγράμματα"
        $total = 0; foreach ($r in $report) { $total += $r.Count }

        $hdr = @()
        if ($st) {
            if ($st.mullvad_exit_ip) { $hdr += (L '  VPN      : ' 'DarkGray' $null "ΣΥΝΔΕΔΕΜΕΝΟ μέσω Mullvad ($($st.mullvad_exit_ip_hostname)), δημόσια IP $($st.ip), $($st.country)" 'Green') }
            else { $hdr += (L '  VPN      : ' 'DarkGray' $null "ΟΧΙ! Η δημόσια IP σου ($($st.ip), $($st.country)) είναι η πραγματική" 'Red') }
        } else { $hdr += (L '  VPN      : ' 'DarkGray' $null 'δεν ήταν δυνατός ο έλεγχος (χωρίς ίντερνετ;)' 'Yellow') }
        $hdr += (L '  Συνδέσεις: ' 'DarkGray' $null "$total προς το ίντερνετ, από $($report.Count) προγράμματα   ·   λίστα κακόβουλων IP: $($threat.Count)" 'Gray')
        $hdr += (L '  Χρώματα  : ' 'DarkGray' $null 'πράσινο = εντάξει · κίτρινο = ρίξε μια ματιά · κόκκινο = έλεγξέ το' 'Gray')

        $items = @()
        foreach ($r in $report) {
            if ($r.Level -eq 2) { $col = 'Red'; $tag = '[ΕΛΕΓΞΕ ΤΟ]' } elseif ($r.Level -eq 1) { $col = 'Yellow'; $tag = '[ΠΡΟΣΟΧΗ] ' } else { $col = 'Green'; $tag = '[OK]      ' }
            $who = $r.Sig; if ($r.Publisher) { $who = "$($r.Sig) από: $($r.Publisher)" }
            if ($r.Trusted) { $who += '  (σημειωμένο ως αξιόπιστο)' }
            $lines = @((L $who 'Gray'))
            if ($r.Dest) { $lines += (L "Προς: $($r.Dest)" 'Gray') }
            if ($r.Flags.Count -eq 0) { $lines += (L 'Δεν βρέθηκε τίποτα ύποπτο.' 'Green') }
            foreach ($f in $r.Flags) { $lines += (L "! $f" $col) }
            $lines += (L 'Enter = λεπτομέρειες και ενέργειες (σάρωση, VirusTotal, αξιόπιστο, κλείσιμο).' 'DarkGray')
            $items += @{ Label = ('{0} {1}  ({2})' -f $tag, $r.Name, $r.Count); Group = 'ΠΡΟΓΡΑΜΜΑΤΑ ΜΕ ΣΥΝΔΕΣΗ ΣΤΟ ΙΝΤΕΡΝΕΤ'; Color = $col; Lines = $lines; R = $r }
        }
        $pl = @()
        $listen = @(Get-NetTCPConnection -ErrorAction SilentlyContinue -State Listen | Where-Object { $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq '::' })
        foreach ($lg in ($listen | Group-Object OwningProcess)) {
            $pn = (Get-Process -Id ([int]$lg.Name)).ProcessName; if (-not $pn) { $pn = "PID $($lg.Name)" }
            $pl += (L ("{0}: θύρες {1}" -f $pn, ((@($lg.Group.LocalPort) | Sort-Object -Unique) -join ', ')) 'Gray')
        }
        $pl += (L 'Οι svchost, lsass, wininit, services, spoolsv και System είναι των Windows. Μία θύρα του torrent είναι φυσιολογική. Το Τείχος προστασίας τις φιλτράρει.' 'DarkGray')
        $items += @{ Label = 'Ανοιχτές θύρες για εισερχόμενες συνδέσεις'; Group = 'ΑΛΛΑ'; Lines = $pl; Action = 'none' }

        $x = Show-Choice -Title 'Διαγνωστικό δικτύου' -Items $items -Start $sel -Message $msg -HeaderLines $hdr `
              -ExtraKeys @{ M = -10; R = -11; F5 = -12 } -Footer 'M παρακολούθηση | R αναφορά HTML | F5 ανανέωση'
        $msg = ''
        if ($x -eq -1) { return }
        if ($x -eq -10) { Write-Header 'Ζωντανή παρακολούθηση'; Watch-Network $vpnIps $threat; continue }
        if ($x -eq -11) { Write-Header 'Αναφορά δικτύου'; Export-NetReport $report $st $threat.Count; $msg = 'Η αναφορά άνοιξε στον browser (φάκελος reports).'; continue }
        if ($x -eq -12) { $msg = 'Ανανεώθηκε.'; continue }
        $sel = $x
        if ($items[$x].R) { if (Show-NetDetails $items[$x].R $vpnIps $ipInfo) { $trusted = @(Get-TrustedList) } }
    }
}

function Start-Monitor { Watch-Network @(Get-VpnIps) (Get-ThreatIps) }

function Reset-Step { $State.Step = @{ Status = 'ok'; Note = ''; Freed = 0.0 } }

function Invoke-QuickFull {
    $t0 = Get-Date
    if (Ask-Yes 'Να φτιάξω πρώτα σημείο επαναφοράς; (συνιστάται)') { New-RestorePoint }
    $steps = @(
        @{ N = 'Προσωρινά αρχεία'; R = { Clear-TempFiles } }
        @{ N = 'Cache του Windows Update'; R = { Clear-UpdateCache } }
        @{ N = 'Παλιές ενημερώσεις συστήματος'; R = { Invoke-ComponentCleanup }; Measure = $true }
        @{ N = 'DNS cache'; R = { Clear-Dns } }
        @{ N = 'Βελτιστοποίηση δίσκων'; R = { Optimize-Drives } }
    )
    $res = @()
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $s = $steps[$i]
        $bar = Get-Bar (100.0 * $i / $steps.Count) 20
        Write-Host ''
        Write-Segs (Seg @(@('  ═══ ', $Theme.Accent), @("Βήμα $($i + 1) από $($steps.Count)  ", $Theme.Title), @($bar[0], $Theme.Ok), @($bar[1], 'DarkGray'), @("  $($s.N)", $Theme.Title)))
        Reset-Step
        $ts = Get-Date; $bs = Get-FreeBytes
        & $s.R
        $freed = [double]$State.Step.Freed
        if ($s.Measure -and $freed -le 0) { $freed = [Math]::Max(0, (Get-FreeBytes) - $bs) }
        $res += [pscustomobject]@{ N = $s.N; T = ((Get-Date) - $ts).TotalSeconds; F = $freed; S = $State.Step.Status; Note = $State.Step.Note }
    }
    $total = ((Get-Date) - $t0).TotalSeconds
    $freedAll = 0.0; foreach ($r in $res) { $freedAll += $r.F }
    $rows = @()
    foreach ($r in $res) {
        $f = '-'; if ($r.F -gt 1MB) { $f = Format-Size $r.F } elseif ($r.F -gt 0) { $f = '< 1 MB' }
        $st = '● OK'; $c = 'Gray'; if ($r.S -ne 'ok') { $st = '● ΠΡΟΣΟΧΗ'; $c = 'Yellow' }
        $rows += , @(('{0,-30} {1,-10} {2,7}  {3,10}' -f $r.N, $st, (Format-Time $r.T), $f), $c)
    }
    $rows += '-'
    $rows += , @(('{0,-30} {1,-10} {2,7}  {3,10}' -f 'ΣΥΝΟΛΟ', '', (Format-Time $total), (Format-Size $freedAll)), 'Green')
    $warns = @($res | Where-Object { $_.S -ne 'ok' -and $_.Note })
    if ($warns.Count -gt 0) {
        $rows += '-'
        foreach ($w in $warns) { $rows += , @("$($w.N):", 'Yellow'); foreach ($l in @(Wrap-Text $w.Note 66 '   ')) { $rows += , @($l, 'Yellow') } }
    }
    Write-Box ('{0,-30} {1,-10} {2,7}  {3,10}' -f 'ΑΠΟΤΕΛΕΣΜΑ', 'κατάσταση', 'χρόνος', 'κέρδος') $rows 70
    Write-Host '     Το κέρδος μετριέται από τα αρχεία που σβήστηκαν πραγματικά (δεν επηρεάζεται από downloads).' -ForegroundColor $Theme.Dim
    $tmsg = "Ελευθερώθηκαν $(Format-Size $freedAll) σε $(Format-Time $total)."
    if ($warns.Count -gt 0) { $tmsg += " $($warns.Count) βήμα(τα) θέλουν προσοχή." }
    Send-Toast 'John''s Toolkit: ο καθαρισμός τελείωσε' $tmsg
}

function Test-PendingReboot {
    return ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
}

function New-DesktopShortcut {
    $desk = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desk 'John''s Toolkit.lnk'
    try {
        $ws = New-Object -ComObject WScript.Shell
        $s = $ws.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $ToolDir 'Start-PCTools.bat'
        $s.WorkingDirectory = $ToolDir
        if ($AppRoot) { $s.TargetPath = Join-Path $AppRoot 'Start-JohnsToolkit.bat'; $s.WorkingDirectory = $AppRoot }
        $s.IconLocation = "$env:SystemRoot\System32\shell32.dll,15"
        $s.Description = 'John''s Toolkit by nmx88'
        $s.Save()
        Write-Ok "Δημιουργήθηκε η συντόμευση 'John's Toolkit' στην Επιφάνεια εργασίας."
        Write-Note 'Αν μετακινήσεις τον φάκελο PC-Tools, ξαναφτιάξε τη συντόμευση από εδώ.'
    } catch { Write-Bad "Δεν ήταν δυνατή η δημιουργία: $($_.Exception.Message)" }
}

function Show-History {
    $f = Join-Path $LogDir 'history.log'
    Write-Step 'Οι τελευταίες 30 ενέργειες:'
    if (-not (Test-Path $f)) { Write-Note 'Δεν υπάρχει ακόμα ιστορικό.'; return }
    foreach ($l in @(Get-Content $f -Encoding UTF8 -Tail 30)) { Write-Host "     $l" }
    $a = Join-Path $LogDir 'auto-cleanup.log'
    if (Test-Path $a) {
        Write-Step 'Αυτόματοι καθαρισμοί:'
        foreach ($l in @(Get-Content $a -Encoding UTF8 -Tail 10)) { Write-Host "     $l" }
    }
}

function Show-Help {
    $sections = @(
        @('ΠΩΣ ΤΟ ΧΡΗΣΙΜΟΠΟΙΩ', @(
            'Μετακινείσαι με τα βελάκια ↑↓ και πατάς Enter. Με Esc γυρνάς πίσω. Μπορείς να πατήσεις και τον αριθμό μιας επιλογής για να πας κατευθείαν.',
            'Κάτω από το μενού βλέπεις πάντα τι κάνει η επιλογή που έχεις διαλέξει και τι επηρεάζει.',
            'Στις ερωτήσεις πατάς Y για ναι ή N για όχι (δουλεύει και με ελληνικό πληκτρολόγιο).')),
        @('ΑΠΟ ΠΟΥ ΝΑ ΞΕΚΙΝΗΣΩ', @(
            '1) Ρυθμίσεις Windows 11 > Εφαρμογή όλων των προτεινόμενων.',
            '2) Επιδόσεις > Προγράμματα εκκίνησης: κλείσε όσα δεν χρειάζεσαι.',
            '3) Γρήγορος καθαρισμός, όταν δεν κατεβάζεις κάτι.',
            '4) Αυτοματισμοί > Αυτόματος εβδομαδιαίος καθαρισμός.')),
        @('ΠΩΣ ΑΝΑΙΡΩ ΜΙΑ ΑΛΛΑΓΗ', @(
            'Ρυθμίσεις Windows 11: πατάς ξανά Enter στη ρύθμιση, ή "Επαναφορά όλων".',
            'Προγράμματα εκκίνησης: ξανά Enter. Εφαρμογές που αφαίρεσες: Microsoft Store.',
            'Για όλα τα άλλα: σημείο επαναφοράς (Έναρξη > γράψε rstrui > Enter).')),
        @('VPN & TORRENT', @(
            'Κανένα εργαλείο εδώ δεν αλλάζει ρυθμίσεις του Mullvad.',
            'Η ενημέρωση προγραμμάτων μπορεί να ενημερώσει και το Mullvad (πέφτει για λίγο). Κάνε πρώτα παύση στο torrent.',
            'Αν το διαγνωστικό δικτύου δείξει κόκκινο "TORRENT ΕΚΤΟΣ VPN", κλείσε αμέσως το torrent.'))
    )
    $w = (Get-Width) - 2
    foreach ($s in $sections) {
        Write-Host "`n  $($s[0])" -ForegroundColor Cyan
        foreach ($t in $s[1]) { foreach ($l in @(Wrap-Text $t $w '     ')) { Write-Host $l } }
    }
}

# ======================================================================
#  ΜΕΝΟΥ
# ======================================================================
function Get-Dashboard {
    $out = @()
    $c = Get-PSDrive C
    $tot = [double]$c.Free + [double]$c.Used
    if ($tot -gt 0) {
        $used = [double]$c.Used / $tot * 100
        $out += (Get-GaugeLine 'Δίσκος C' $used ('{0} ελεύθερα από {1}' -f (Format-Size $c.Free), (Format-Size $tot)) 80 90)
    }
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os) {
        $totalRam = [double]$os.TotalVisibleMemorySize * 1KB; $freeRam = [double]$os.FreePhysicalMemory * 1KB
        if ($totalRam -gt 0) { $out += (Get-GaugeLine 'Μνήμη' (($totalRam - $freeRam) / $totalRam * 100) ('{0} από {1} σε χρήση' -f (Format-Size ($totalRam - $freeRam)), (Format-Size $totalRam)) 80 90) }
        $up = (Get-Date) - $os.LastBootUpTime
        $upTxt = '{0} μέρες, {1} ώρες' -f $up.Days, $up.Hours
    }
    $vpn = (@(Get-VpnIps).Count -gt 0)
    $vs = @(, @(('  {0,-10} ' -f 'VPN'), $Theme.Dim))
    if ($vpn) { $vs += , @('● Mullvad συνδεδεμένο', $Theme.Ok) } else { $vs += , @('○ δεν βρέθηκε ενεργό Mullvad', $Theme.Warn) }
    if ($upTxt) { $vs += , @("      σε λειτουργία $upTxt", $Theme.Dim) }
    $out += (Seg $vs)
    if ($State.NeedsRestart -or (Test-PendingReboot)) { $out += (Seg @(@('  ', 'Gray'), @(' ! ', 'Black', 'Yellow'), @(' Χρειάζεται επανεκκίνηση για να ολοκληρωθούν κάποιες αλλαγές (επιλογή 8).', $Theme.Warn))) }
    return $out
}

function Invoke-Action($it) {
    if ($it.Interactive) { & $it.Run; return }
    Write-Header $it.Label
    if ($it.Confirm) {
        Write-Host ''
        foreach ($l in @(Wrap-Text "Επηρεάζει: $($it.Affects)" ((Get-Width) - 2) '     ')) { Write-Host $l -ForegroundColor $Theme.Warn }
        if (-not (Ask-Yes $it.Confirm)) { return }
    }
    $t0 = Get-Date; $b0 = Get-FreeBytes
    Reset-Step
    & $it.Run
    Write-Log $it.Label
    if ($it.NoSummary) { Pause-Key; return }
    $el = ((Get-Date) - $t0).TotalSeconds
    $freed = [double]$State.Step.Freed
    if ($freed -le 0) { $freed = (Get-FreeBytes) - $b0 }
    $rows = @(, @("Χρόνος: $(Format-Time $el)"))
    if ($freed -gt 10MB) { $rows += , @("Ελευθερώθηκαν: $(Format-Size $freed)", 'Green') }
    if ($State.Step.Status -ne 'ok' -and $State.Step.Note) { foreach ($l in @(Wrap-Text $State.Step.Note 58 '')) { $rows += , @($l, 'Yellow') } }
    if ($State.NeedsRestart) { $rows += , @('Χρειάζεται επανεκκίνηση για να ισχύσουν όλα.', 'Yellow') }
    if ($el -ge 2 -or $State.Step.Status -ne 'ok') { Write-Box "Τέλος: $($it.Label)" $rows 64 }
    if ($el -ge 60) { Send-Toast "John's Toolkit: $($it.Label)" "Τελείωσε σε $(Format-Time $el)." }
    Pause-Key
}

function Invoke-Menu([string]$Title, [scriptblock]$GetItems, [scriptblock]$Header = $null, [string]$EscText = 'πίσω', [switch]$Banner) {
    $sel = 0
    while ($true) {
        $items = @(& $GetItems)
        $r = Show-Choice -Title $Title -Items $items -Header $Header -Start $sel -EscText $EscText -Banner:$Banner
        if ($r -lt 0) { return }
        $sel = $r
        $it = $items[$r]
        if ($it.Sub) { & $it.Sub } else { Invoke-Action $it }
    }
}

function Show-CleanMenu {
    Invoke-Menu -Title 'Καθαρισμός χώρου' -GetItems { @(
        @{ Key = '1'; Label = 'Προσωρινά αρχεία'; Run = { Clear-TempFiles }
           What = 'Σβήνει προσωρινά αρχεία των Windows και των προγραμμάτων, την cache του Edge/Internet Explorer και αναφορές σφαλμάτων.'; Affects = 'Μόνο αρχεία που ξαναφτιάχνονται μόνα τους. Ασφαλές με VPN/torrent.' }
        @{ Key = '2'; Label = 'Cache του Windows Update'; Run = { Clear-UpdateCache }
           What = 'Σβήνει αρχεία ενημερώσεων που έχουν ήδη εγκατασταθεί.'; Affects = 'Μόνο το Windows Update. Αν μια ενημέρωση ήταν στη μέση, απλώς θα ξανακατέβει.' }
        @{ Key = '3'; Label = 'Κάδος Ανακύκλωσης'; Run = { Clear-Bin }; Confirm = 'Να αδειάσει οριστικά ο Κάδος;'
           What = 'Αδειάζει τον Κάδο Ανακύκλωσης σε όλους τους δίσκους.'; Affects = 'ΟΡΙΣΤΙΚΗ διαγραφή: ό,τι είναι στον κάδο δεν επαναφέρεται.' }
        @{ Key = '4'; Label = 'Παλιές ενημερώσεις συστήματος (DISM)'; Run = { Invoke-ComponentCleanup }
           What = 'Αφαιρεί παλιές εκδόσεις αρχείων συστήματος που έμειναν από ενημερώσεις. Συχνά ελευθερώνει αρκετά GB.'; Affects = 'Μετά δεν μπορείς να απεγκαταστήσεις τις ήδη περασμένες ενημερώσεις. Αργεί λίγα λεπτά.' }
        @{ Key = '5'; Label = 'DNS cache'; Run = { Clear-Dns }
           What = 'Σβήνει τη λίστα διευθύνσεων ιστοσελίδων που έχει κρατήσει το PC. Βοηθά όταν κάποια σελίδα δεν ανοίγει.'; Affects = 'Τίποτα σημαντικό. Το VPN συνεχίζει κανονικά.' }
        @{ Key = '6'; Label = 'Εύρεση μεγάλων αρχείων'; Run = { Find-BigFiles }; Interactive = $true
           What = 'Βρίσκει τα 40 μεγαλύτερα αρχεία σε έναν φάκελο, για να δεις τι τρώει χώρο.'; Affects = 'Τίποτα. Δεν σβήνει, μόνο σου δείχνει.' }
        @{ Key = '7'; Label = 'Έλεγχος υπολειμμάτων (σπασμένες εγγραφές)'; Run = { Show-Leftovers }; Interactive = $true
           What = 'Βρίσκει προγράμματα εκκίνησης χωρίς αρχείο, σπασμένες συντομεύσεις, "φαντάσματα" στις εγκατεστημένες εφαρμογές και ορφανές προγραμματισμένες εργασίες. Σου τα δείχνει πριν σβήσει οτιδήποτε.'
           Affects = 'Μόνο ό,τι τσεκάρεις. Κρατιέται πάντα αντίγραφο ασφαλείας. Δεν είναι "καθαριστής registry": αγγίζει μόνο εγγραφές που αποδεδειγμένα δείχνουν σε αρχεία που δεν υπάρχουν.' }
        @{ Key = '8'; Label = 'Επαναφορά υπολειμμάτων από αντίγραφο'; Run = { Show-LeftoverRestore }; Interactive = $true
           What = 'Επαναφέρει ό,τι αφαίρεσε ο έλεγχος υπολειμμάτων, αν κάτι σου λείψει.'; Affects = 'Ξαναβάζει τις εγγραφές όπως ήταν.' }
    ) }
}

function Show-PerfMenu {
    Invoke-Menu -Title 'Επιδόσεις' -GetItems { @(
        @{ Key = '1'; Label = 'Σχέδιο ενέργειας'; Run = { Set-PowerPlan }; Interactive = $true
           Status = { param($it) $g = Get-ActivePlanGuid; $n = 'άλλο'; if ($g -eq '381b4222-f694-41f0-9685-ff5bb260df2e') { $n = 'Ισορροπημένο' } elseif ($g -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') { $n = 'Υψηλές επιδόσεις' } elseif ($g -and $g -eq (Get-UltimateGuid)) { $n = 'Απόλυτες επιδόσεις' }; @{ Text = "τώρα: $n"; Color = 'DarkGray' } }
           What = 'Διαλέγεις ανάμεσα σε Ισορροπημένο, Υψηλές επιδόσεις και Απόλυτες επιδόσεις (Ultimate Performance).'; Affects = 'Μεγαλύτερη απόδοση = περισσότερη κατανάλωση. Αναιρείται εύκολα.' }
        @{ Key = '2'; Label = 'Προγράμματα εκκίνησης'; Run = { Show-StartupManager }; Interactive = $true
           What = 'Δείχνει ποια προγράμματα ανοίγουν μόνα τους με τα Windows και τα ενεργοποιείς/απενεργοποιείς με Enter. Αυτό κάνει συνήθως τη μεγαλύτερη διαφορά στην ταχύτητα εκκίνησης.'; Affects = 'Μόνο το αν ανοίγουν αυτόματα. Τα προγράμματα δεν σβήνονται.' }
        @{ Key = '3'; Label = 'Αφαίρεση περιττών εφαρμογών'; Run = { Remove-Bloat }; Interactive = $true
           What = 'Δείχνει προεγκατεστημένες εφαρμογές της Microsoft (Ειδήσεις, Solitaire, Teams, Xbox κ.λπ.) και αφαιρεί όσες τσεκάρεις.'; Affects = 'Μόνο όσες διαλέξεις. Ξαναμπαίνουν από το Microsoft Store.' }
        @{ Key = '4'; Label = 'Ενημέρωση προγραμμάτων (με επιλογή)'; Run = { Update-Apps }; Interactive = $true
           What = 'Δείχνει όλες τις διαθέσιμες ενημερώσεις με τικ. Τα ασφαλή είναι ήδη τσεκαρισμένα, τα "επικίνδυνα" (Docker, VirtualBox, Visual Studio κ.λπ.) σημειώνονται με εξήγηση. Στο τέλος βλέπεις τι ενημερώθηκε και τι απέτυχε και γιατί.'
           Affects = 'Τα προγράμματα που ενημερώνονται κλείνουν για λίγο. Αποδέχεται αυτόματα τους όρους του winget.' }
        @{ Key = '6'; Label = 'Παγωμένα προγράμματα (να μην ενημερώνονται)'; Run = { Show-WingetPins }; Interactive = $true
           What = 'Διαλέγεις προγράμματα που δεν θέλεις να εμφανίζονται στις ενημερώσεις (π.χ. Visual Studio Build Tools, Windows Installation Assistant).'; Affects = 'Μόνο τις ενημερώσεις μέσω winget. Ξεπαγώνουν όποτε θέλεις.' }
        @{ Key = '5'; Label = 'Βελτιστοποίηση δίσκων'; Run = { Optimize-Drives }
           What = 'Σε SSD κάνει TRIM (λίγα δευτερόλεπτα). Σε HDD κάνει ανασυγκρότηση, που μπορεί να πάρει ώρα.'; Affects = 'Σε HDD επιβραδύνει torrent/downloads όσο τρέχει.' }
    ) }
}

function Show-NetMenu {
    Invoke-Menu -Title 'Δίκτυο & VPN' -GetItems { @(
        @{ Key = '1'; Label = 'Έλεγχος VPN (Mullvad)'; Run = { Test-Vpn }
           What = 'Δείχνει ποια IP και χώρα βλέπουν οι άλλοι και αν η κίνησή σου περνά από το Mullvad.'; Affects = 'Τίποτα, μόνο έλεγχος.' }
        @{ Key = '2'; Label = 'Διαγνωστικό δικτύου (ενεργές συνδέσεις)'; Run = { Show-Network }; Interactive = $true
           What = 'Δείχνει ποια προγράμματα είναι συνδεδεμένα στο ίντερνετ, πού, αν βγαίνουν εκτός VPN και αν μιλάνε με γνωστές κακόβουλες IP. Από εκεί κάνεις σάρωση, έλεγχο VirusTotal ή κλείσιμο.'; Affects = 'Τίποτα, μόνο έλεγχος. Κατεβάζει λίστες κακόβουλων IP μία φορά τη μέρα.' }
        @{ Key = '3'; Label = 'Ζωντανή παρακολούθηση νέων συνδέσεων'; Run = { Start-Monitor }
           What = 'Εμφανίζει κάθε νέα σύνδεση τη στιγμή που ανοίγει. Κάνει ήχο αν κάτι βγει κόκκινο (π.χ. torrent εκτός VPN).'; Affects = 'Τίποτα. Σταματά με οποιοδήποτε πλήκτρο.' }
    ) }
}

function Show-HealthMenu {
    Invoke-Menu -Title 'Υγεία & επιδιόρθωση' -GetItems { @(
        @{ Key = '1'; Label = 'Αναφορά υγείας PC'; Run = { Show-Health }
           What = 'Δείχνει επεξεργαστή, μνήμη, κατάσταση και θερμοκρασία δίσκων, ελεύθερο χώρο και (σε laptop) αναφορά μπαταρίας.'; Affects = 'Τίποτα, μόνο έλεγχος.' }
        @{ Key = '2'; Label = 'Επιδιόρθωση αρχείων συστήματος (SFC/DISM)'; Run = { Repair-System }; Confirm = 'Να ξεκινήσει η επιδιόρθωση; (10-30 λεπτά)'
           What = 'Ελέγχει και επιδιορθώνει κατεστραμμένα αρχεία των Windows. Χρήσιμο αν έχεις κολλήματα ή περίεργα σφάλματα.'; Affects = 'Αργεί 10-30 λεπτά και φορτώνει το PC. Δεν αγγίζει τα αρχεία σου.' }
        @{ Key = '4'; Label = 'Έλεγχος ασφάλειας'; Run = { Show-SecurityCheck }
           What = 'Ελέγχει antivirus, τείχος προστασίας, UAC, απομακρυσμένη επιφάνεια εργασίας, SMBv1, Secure Boot, πότε έγινε η τελευταία ενημέρωση των Windows και αν υπάρχουν προγράμματα απομακρυσμένης πρόσβασης. Προαιρετικά κάνει γρήγορη σάρωση για ιούς.'
           Affects = 'Τίποτα, μόνο έλεγχος. Δεν αλλάζει ρυθμίσεις ασφαλείας: σου ανοίγει τη σωστή σελίδα για να τις διορθώσεις εσύ.' }
        @{ Key = '3'; Label = 'Σημείο επαναφοράς'; Run = { New-RestorePoint }
           What = 'Κρατά ένα "στιγμιότυπο" των ρυθμίσεων συστήματος για να γυρίσεις πίσω αν κάτι πάει στραβά.'; Affects = 'Πιάνει λίγο χώρο. Δεν αγγίζει τα αρχεία σου.' }
    ) }
}

function Show-ToolsMenu {
    Invoke-Menu -Title 'Αυτοματισμοί & εργαλείο' -GetItems { @(
        @{ Key = '1'; Label = 'Αυτόματος εβδομαδιαίος καθαρισμός'; Run = { Set-AutoClean }
           Status = { param($it) if (Get-ScheduledTask -ErrorAction SilentlyContinue -TaskName $TaskName) { @{ Text = '● Ενεργός'; Color = 'Green' } } else { @{ Text = '○ Όχι'; Color = 'DarkGray' } } }
           What = 'Κάθε Κυριακή 20:00 καθαρίζει στο παρασκήνιο προσωρινά αρχεία, cache Windows Update και DNS. Ξαναπατώντας το, τον απενεργοποιείς.'; Affects = 'Προσθέτει μια εργασία στον Χρονοπρογραμματιστή. Ασφαλές με VPN/torrent.' }
        @{ Key = '2'; Label = 'Συντόμευση στην Επιφάνεια εργασίας'; Run = { New-DesktopShortcut }
           What = 'Φτιάχνει εικονίδιο "John''s Toolkit" στην Επιφάνεια εργασίας, για να το ανοίγεις με διπλό κλικ.'; Affects = 'Τίποτα άλλο.' }
        @{ Key = '3'; Label = 'Ιστορικό ενεργειών'; Run = { Show-History }
           What = 'Δείχνει τι έχεις κάνει με το εργαλείο και πότε.'; Affects = 'Τίποτα, μόνο προβολή.' }
        @{ Key = '4'; Label = 'Βοήθεια & οδηγίες'; Run = { Show-Help }
           What = 'Πώς χρησιμοποιείται το εργαλείο, από πού να ξεκινήσεις και πώς αναιρείς κάθε αλλαγή.'; Affects = 'Τίποτα.' }
    ) }
}

if ($Auto) { Invoke-AutoClean; return }

Initialize-Console
Invoke-Menu -Title 'Κεντρικό μενού' -Header { Get-Dashboard } -EscText 'έξοδος' -Banner -GetItems { @(
    @{ Key = '1'; Label = 'Γρήγορος καθαρισμός (συνιστάται)'; Run = { Invoke-QuickFull }; NoSummary = $true
       What = 'Με ένα πάτημα: προσωρινά αρχεία, cache ενημερώσεων, παλιές ενημερώσεις, DNS και βελτιστοποίηση δίσκων. Προαιρετικά φτιάχνει πρώτα σημείο επαναφοράς.'; Affects = 'Αργεί λίγα λεπτά. Σε HDD επιβραδύνει τα downloads όσο τρέχει.' }
    @{ Key = '2'; Label = 'Καθαρισμός χώρου'; Sub = { Show-CleanMenu }
       What = 'Καθαρισμός ένα-ένα: προσωρινά αρχεία, Windows Update, Κάδος, παλιές ενημερώσεις, DNS, εύρεση μεγάλων αρχείων.'; Affects = 'Ανοίγει υπομενού.' }
    @{ Key = '3'; Label = 'Επιδόσεις'; Sub = { Show-PerfMenu }
       What = 'Σχέδιο ενέργειας (και Ultimate Performance), προγράμματα εκκίνησης, αφαίρεση περιττών εφαρμογών, ενημέρωση προγραμμάτων, δίσκοι.'; Affects = 'Ανοίγει υπομενού.' }
    @{ Key = '4'; Label = 'Ρυθμίσεις Windows 11 (γραφικά, gaming, σύστημα)'; Sub = { Show-TweakMenu }
       What = 'Ρυθμίσεις που κάνουν το PC πιο γρήγορο: οπτικά εφέ, κάρτα γραφικών (HAGS), Game Mode, ποντίκι, παρασκήνιο, διαφημίσεις κ.ά. Βλέπεις τι είναι ενεργό και το αλλάζεις με Enter.'; Affects = 'Όλες αναιρούνται, και υπάρχει "Επαναφορά όλων".' }
    @{ Key = '5'; Label = 'Δίκτυο & VPN'; Sub = { Show-NetMenu }
       What = 'Έλεγχος VPN, διαγνωστικό ενεργών συνδέσεων, ζωντανή παρακολούθηση.'; Affects = 'Ανοίγει υπομενού.' }
    @{ Key = '6'; Label = 'Υγεία & επιδιόρθωση'; Sub = { Show-HealthMenu }
       What = 'Αναφορά υγείας, επιδιόρθωση αρχείων συστήματος, σημείο επαναφοράς.'; Affects = 'Ανοίγει υπομενού.' }
    @{ Key = '7'; Label = 'Αυτοματισμοί & εργαλείο'; Sub = { Show-ToolsMenu }
       What = 'Αυτόματος εβδομαδιαίος καθαρισμός, συντόμευση στην Επιφάνεια εργασίας, ιστορικό, βοήθεια.'; Affects = 'Ανοίγει υπομενού.' }
    @{ Key = '8'; Label = 'Επανεκκίνηση υπολογιστή'; Run = { Restart-Computer -Force }; Confirm = 'Να γίνει επανεκκίνηση τώρα;'
       What = 'Κάνει επανεκκίνηση για να ισχύσουν οι αλλαγές που το χρειάζονται.'; Affects = 'Κλείνουν όλα τα ανοιχτά προγράμματα. Αποθήκευσε πρώτα τη δουλειά σου.' }
) }
Clear-Host
Write-Host "`n  Ευχαριστώ που χρησιμοποίησες το John's Toolkit!`n" -ForegroundColor $Theme.Ok
Set-TaskbarProgress 101
