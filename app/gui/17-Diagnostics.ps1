# John's Toolkit by nmx88 - Diagnostics: crashes, devices & drivers, Windows Update
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ---------- Διάγνωση ----------
function Build-DiagPage {
    $UI.DiagTabs.Children.Clear()
    foreach ($tab in @('crash', 'devices', 'wu')) {
        $rb = New-Pill (T "diag.tab.$tab") $tab 'diagtab' ($tab -eq $App.DiagTab)
        $rb.Add_Checked({ $App.DiagTab = [string]$this.Tag; Build-DiagBody })
        [void]$UI.DiagTabs.Children.Add($rb)
    }
    Build-DiagBody
}

function Build-DiagBody {
    $UI.DiagBody.Children.Clear()
    switch ($App.DiagTab) { 'crash' { Build-CrashTab } 'devices' { Build-DeviceTab } 'wu' { Build-WuTab } }
}

function Start-DiagLoad([string]$what) {
    switch ($what) {
        'crash' { Start-Task 'cr.loading' 'Get-CrashHistory 30' @{} { param($TK); if ($TK.Result) { $App.Crash = $TK.Result } else { $App.Crash = @{ Failed = $true } }; Build-DiagBody } }
        'devices' { Start-Task 'dv.loading' 'Get-DeviceReport' @{} { param($TK); if ($TK.Result) { $App.Devices = $TK.Result } else { $App.Devices = @{ Failed = $true } }; Build-DiagBody } }
        'wu' { Start-Task 'wu.loading' 'Get-WuInfo' @{} { param($TK); if ($TK.Result) { $App.Wu = $TK.Result } else { $App.Wu = @{ Failed = $true } }; Build-DiagBody } }
    }
}

function Add-DiagHeader($p, [string]$tkey, [string]$dkey, [string]$what, $extra) {
    $ic = New-InfoCard (T $tkey) (T $dkey)
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $b = New-Button (T 'diag.refresh') 'Primary'; $b.Margin = '0,0,10,8'; $b.Tag = $what; $b.Add_Click({ Start-DiagLoad ([string]$this.Tag) }); [void]$wp.Children.Add($b)
    foreach ($x in @($extra)) { if ($x) { $x.Margin = '0,0,10,8'; [void]$wp.Children.Add($x) } }
    [void]$ic.Panel.Children.Add($wp)
    return $ic
}

function Build-CrashTab {
    $p = $UI.DiagBody; $d = $App.Crash
    $rel = New-Button (T 'cr.rel') 'Secondary'; $rel.Add_Click({ Start-Process 'perfmon.exe' -ArgumentList '/rel' })
    $ic = Add-DiagHeader $p 'cr.t' 'cr.d' 'crash' @($rel)
    if (-not $d) { [void]$ic.Panel.Children.Insert(1, (New-Text (T 'diag.notloaded') 13 'SubBrush')); [void]$p.Children.Add($ic.Card); if (-not $App.Busy -and $App.Page -eq 'Diag') { Start-DiagLoad 'crash' }; return }
    if ($d.Failed) { [void]$ic.Panel.Children.Insert(1, (New-Text (T 'diag.failed') 14 'WarnBrush' 'SemiBold')); [void]$p.Children.Add($ic.Card); return }
    $nApps = 0; foreach ($a in @($d.Apps)) { if ($a) { $nApps += $a.Crashes + $a.Hangs } }
    $br = 'GoodBrush'; if (@($d.Bsod).Count -gt 0) { $br = 'BadBrush' } elseif (@($d.Power).Count -gt 0 -or $nApps -gt 0) { $br = 'WarnBrush' }
    $sum = New-Text ((T 'cr.summary') -f $d.Days, @($d.Bsod).Count, @($d.Power).Count, $nApps) 16 $br 'SemiBold'; $sum.Margin = '0,10,0,0'
    [void]$ic.Panel.Children.Insert(1, $sum); [void]$p.Children.Add($ic.Card)
    if (@($d.Bsod).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'cr.bsod')))
        foreach ($b in @($d.Bsod)) {
            $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
            [void]$s.Children.Add((New-Text ("$($b.When.ToString('g', (Get-LangCulture)))   ·   $($b.Code)") 14 'BadBrush' 'SemiBold'))
            [void]$s.Children.Add((New-Text (T "cr.k.$($b.Kind)") 12 'SubBrush'))
            $c.Child = $s; [void]$p.Children.Add($c)
        }
        if ($d.Dumps -gt 0) { [void]$p.Children.Add((New-Text ((T 'cr.dumps') -f $d.Dumps) 12 'SubBrush')) }
    }
    if (@($d.Power).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'cr.power')))
        $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text ((@($d.Power) | Select-Object -First 8 | ForEach-Object { $_.ToString('g', (Get-LangCulture)) }) -join '   ·   ') 13 'WarnBrush'))
        [void]$s.Children.Add((New-Text (T 'cr.power.d') 12 'SubBrush'))
        $c.Child = $s; [void]$p.Children.Add($c)
    }
    if (@($d.Apps).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'cr.apps')))
        foreach ($a in @($d.Apps)) {
            $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
            [void]$s.Children.Add((New-Text ((T 'cr.app') -f $a.Name, $a.Crashes, $a.Hangs) 14 'TextBrush' 'SemiBold'))
            $line = (T 'cr.last') -f $a.Last.ToString('g', (Get-LangCulture)); if ($a.Module) { $line += ' · ' + ((T 'cr.module') -f $a.Module) }
            [void]$s.Children.Add((New-Text $line 12 'SubBrush'))
            if ($a.Hint) { [void]$s.Children.Add((New-Text ('↳ ' + (T "cr.h.$($a.Hint)")) 12 'Accent2Brush')) }
            $c.Child = $s; [void]$p.Children.Add($c)
        }
    }
    if (@($d.Bsod).Count -eq 0 -and @($d.Power).Count -eq 0 -and $nApps -eq 0) { [void]$p.Children.Add((New-Text (T 'cr.none') 15 'GoodBrush' 'SemiBold')) }
}

function Build-DeviceTab {
    $p = $UI.DiagBody; $d = $App.Devices
    $dm = New-Button (T 'dv.devmgr') 'Secondary'; $dm.Add_Click({ Start-Process 'devmgmt.msc' })
    $sc = New-Button (T 'dv.scan') 'Secondary'; $sc.Add_Click({ Start-Process 'pnputil.exe' -ArgumentList '/scan-devices' -WindowStyle Hidden; Show-Info (T 'dv.scanned') })
    $ic = Add-DiagHeader $p 'dv.t' 'dv.d' 'devices' @($dm, $sc)
    [void]$p.Children.Add($ic.Card)
    if (-not $d) { [void]$p.Children.Add((New-Text (T 'diag.notloaded') 13 'SubBrush')); if (-not $App.Busy -and $App.Page -eq 'Diag') { Start-DiagLoad 'devices' }; return }
    if ($d.Failed) { [void]$p.Children.Add((New-Text (T 'diag.failed') 14 'WarnBrush' 'SemiBold')); return }
    [void]$p.Children.Add((New-GroupHeader (T 'dv.problems')))
    if (@($d.Problems).Count -eq 0) { [void]$p.Children.Add((New-Text (T 'dv.noproblems') 14 'GoodBrush' 'SemiBold')) }
    foreach ($x in @($d.Problems)) {
        $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text ("$($x.Name)") 14 'BadBrush' 'SemiBold'))
        $ck = "dv.c.$($x.Code)"; $txt = T $ck; if ($txt -eq $ck) { $txt = (T 'dv.c.other') -f $x.Code }
        [void]$s.Children.Add((New-Text $txt 12 'SubBrush'))
        $c.Child = $s; [void]$p.Children.Add($c)
    }
    if (@($d.Gpu).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'dv.gpu')))
        foreach ($g in @($d.Gpu)) {
            $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
            [void]$s.Children.Add((New-Text $g.Name 14 'TextBrush' 'SemiBold'))
            $age = [int]((Get-Date) - $g.Date).TotalDays
            $br = 'SubBrush'; if ($age -gt 365) { $br = 'WarnBrush' }
            [void]$s.Children.Add((New-Text ((T 'dv.gpu.ver') -f $g.Version, $g.Date.ToString('d', (Get-LangCulture)), $age) 12 $br))
            $url = $null
            if ($g.Name -match 'NVIDIA') { $url = 'https://www.nvidia.com/Download/index.aspx' } elseif ($g.Name -match 'AMD|Radeon') { $url = 'https://www.amd.com/en/support/download/drivers.html' } elseif ($g.Name -match 'Intel') { $url = 'https://www.intel.com/content/www/us/en/support/detect.html' }
            if ($url) { $b = New-Button (T 'dv.gpu.get') 'Secondary'; $b.Tag = $url; $b.Add_Click({ Start-Process ([string]$this.Tag) }); $c.Child = (New-Row $s $b) } else { $c.Child = $s }
            [void]$p.Children.Add($c)
        }
    }
    if (@($d.Old).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'dv.old')))
        foreach ($o in @($d.Old)) {
            $c = New-ItemCard; $c.Padding = '16,8'; $c.Margin = '0,0,0,6'
            $c.Child = (New-Text ("$($o.Name)  ·  $($o.Provider)  ·  $($o.Date.ToString('d', (Get-LangCulture)))") 13 'TextBrush'); [void]$p.Children.Add($c)
        }
        [void]$p.Children.Add((New-Text (T 'dv.old.d') 12 'SubBrush'))
    }
    if (@($d.Unsigned).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'dv.unsigned')))
        [void]$p.Children.Add((New-Text ((@($d.Unsigned)) -join ' · ') 13 'WarnBrush'))
    }
}

function Build-WuTab {
    $p = $UI.DiagBody; $d = $App.Wu
    $o = New-Button (T 'rep.wu.open') 'Secondary'; $o.Add_Click({ Start-Process 'ms-settings:windowsupdate' })
    $r = New-Button (T 'wu.repair') 'Secondary'; $r.Add_Click({ $UI.NavRepair.IsChecked = $true })
    $ic = Add-DiagHeader $p 'wu.t' 'wu.d' 'wu' @($o, $r)
    [void]$p.Children.Add($ic.Card)
    if (-not $d) { [void]$p.Children.Add((New-Text (T 'wu.notloaded') 13 'SubBrush')); return }
    if ($d.Failed) { [void]$p.Children.Add((New-Text (T 'diag.failed') 14 'WarnBrush' 'SemiBold')); return }
    [void]$p.Children.Add((New-GroupHeader ((T 'wu.pending') -f @($d.Pending).Count)))
    if (@($d.Pending).Count -eq 0) { [void]$p.Children.Add((New-Text (T 'wu.nopending') 14 'GoodBrush' 'SemiBold')) }
    foreach ($u in @($d.Pending)) { [void]$p.Children.Add((New-WuRow $u $true)) }
    if (@($d.Hidden).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'wu.hidden')))
        foreach ($u in @($d.Hidden)) { [void]$p.Children.Add((New-WuRow $u $false)) }
    }
    if (@($d.History).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'wu.history')))
        foreach ($h in (@($d.History) | Select-Object -First 25)) {
            $c = New-ItemCard; $c.Padding = '16,8'; $c.Margin = '0,0,0,6'
            $s = [Windows.Controls.StackPanel]::new()
            $res = @{ 1 = 'wu.r.progress'; 2 = 'wu.r.ok'; 3 = 'wu.r.okerr'; 4 = 'wu.r.fail'; 5 = 'wu.r.abort' }[$h.Result]; if (-not $res) { $res = 'wu.r.ok' }
            $br = 'GoodBrush'; if ($h.Result -ge 4) { $br = 'BadBrush' } elseif ($h.Result -eq 3) { $br = 'WarnBrush' }
            $head = [Windows.Controls.WrapPanel]::new(); [void]$head.Children.Add((New-Badge (T $res) $br))
            $tt = New-Text ("  $($h.Date.ToString('d', (Get-LangCulture)))   $($h.Title)") 13 'TextBrush'; [void]$head.Children.Add($tt); [void]$s.Children.Add($head)
            if ($h.HResult -and $h.Result -ge 3) {
                $why = Get-CodeText ([Convert]::ToInt32($h.HResult, 16))
                [void]$s.Children.Add((New-Text $why 12 $br))
            }
            $c.Child = $s; [void]$p.Children.Add($c)
        }
    }
}

function New-WuRow($u, [bool]$pending) {
    $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
    [void]$s.Children.Add((New-Text $u.Title 14 'TextBrush' 'SemiBold'))
    $meta = @($u.KB, $u.Cat) | Where-Object { $_ }; if ($u.Size -gt 0) { $meta += Format-Size $u.Size }; if ($u.Downloaded) { $meta += (T 'wu.downloaded') }
    [void]$s.Children.Add((New-Text ($meta -join ' · ') 12 'SubBrush'))
    $k = 'wu.hide'; if (-not $pending) { $k = 'wu.unhide' }
    $b = New-Button (T $k) 'Secondary'; $b.Tag = @{ Id = $u.Id; Hide = $pending; Title = $u.Title }
    $b.Add_Click({
        $x = $this.Tag
        if ($x.Hide -and -not (Confirm-Box ((T 'wu.hide.confirm') -f $x.Title))) { return }
        Start-Task 'wu.changing' 'Set-WuHidden $TK.Args.Id $TK.Args.Hide' @{ Id = $x.Id; Hide = $x.Hide; Title = $x.Title } { param($TK); if ($TK.Result) { [void](Add-History 'wu' $(if ($TK.Args.Hide) { 'hist.wu.hide' } else { 'hist.wu.show' }) @($TK.Args.Title) @{ Type = 'wu'; Id = $TK.Args.Id; Hidden = [bool]$TK.Args.Hide }) }; Start-DiagLoad 'wu' }
    })
    $c.Child = (New-Row $s $b)
    return $c
}
