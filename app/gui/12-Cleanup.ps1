# John's Toolkit by nmx88 - Cleanup: temporary files, leftovers, large files, duplicates
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ---------- Καθαρισμός ----------
function Update-AgeLabel {
    $v = [int]$UI.SldAge.Value
    if ($v -eq 0) { $UI.TxtAgeV.Text = T 'clean.age.all' } else { $UI.TxtAgeV.Text = (T 'clean.age.v') -f $v }
}

function Get-SelectedCleanIds { return @($App.CleanSel.Keys | Where-Object { $App.CleanSel[$_] }) }

function Build-CleanList {
    $UI.CleanList.Children.Clear(); $App.SizeLabels = @{}
    foreach ($c in Get-CleanCategories) {
        if (-not $App.CleanSel.ContainsKey($c.Id)) { $App.CleanSel[$c.Id] = [bool]$c.Def }
        $card = New-Card; $card.Padding = '18,12'; $card.Margin = '0,0,0,8'
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in @('Auto', '*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Tag = $c.Id; $chk.IsChecked = $App.CleanSel[$c.Id]; $chk.Margin = '0,0,16,0'
        $chk.Add_Click({ $App.CleanSel[[string]$this.Tag] = [bool]$this.IsChecked })
        $sp = [Windows.Controls.StackPanel]::new()
        [void]$sp.Children.Add((New-Text (T "cat.$($c.Id).t") 15 'TextBrush' 'SemiBold'))
        $d = New-Text (T "cat.$($c.Id).d") 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$sp.Children.Add($d)
        $warnKey = "cat.$($c.Id).w"; $wt = T $warnKey
        if ($wt -ne $warnKey) { $w2 = New-Text ('⚠ ' + $wt) 12 'WarnBrush'; $w2.Margin = '0,4,0,0'; [void]$sp.Children.Add($w2) }
        $size = New-Text '—' 15 'AccentBrush' 'Bold'; $size.VerticalAlignment = 'Center'; $size.Margin = '16,0,0,0'
        $App.SizeLabels[$c.Id] = $size
        [Windows.Controls.Grid]::SetColumn($sp, 1); [Windows.Controls.Grid]::SetColumn($size, 2)
        [void]$g.Children.Add($chk); [void]$g.Children.Add($sp); [void]$g.Children.Add($size)
        $card.Child = $g
        [void]$UI.CleanList.Children.Add($card)
    }
}

function Start-Scan {
    $ids = @(Get-CleanCategories | ForEach-Object { $_.Id })
    Start-Task 'clean.scanning' 'Measure-CleanCategories $TK.Args.Ids $TK.Args.Days' @{ Ids = $ids; Days = [int]$UI.SldAge.Value } {
        param($TK)
        $res = $TK.Result; if (-not $res) { return }
        $sel = 0.0
        foreach ($k in $res.Keys) {
            if ($App.SizeLabels.ContainsKey($k)) {
                $b = [double]$res[$k].Bytes
                if ($k -eq 'dns' -or $k -eq 'component') { $App.SizeLabels[$k].Text = '' } else { $App.SizeLabels[$k].Text = Format-Size $b }
                if ($App.CleanSel[$k]) { $sel += $b }
            }
        }
        $UI.TxtCleanSum.Text = (T 'clean.selected') -f (Format-Size $sel)
    }
}

function Start-Clean([switch]$Defaults) {
    if ($Defaults) { foreach ($c in Get-CleanCategories) { $App.CleanSel[$c.Id] = [bool]$c.Def }; Build-CleanList }
    $ids = @(Get-SelectedCleanIds)
    if ($ids.Count -eq 0) { Show-Info (T 'clean.none'); return }
    $warn = @()
    foreach ($id in @('recycle', 'winold', 'browsers', 'shader', 'component')) { if ($ids -contains $id) { $warn += '• ' + (T "cat.$id.t") + ': ' + (T "cat.$id.w") } }
    $msg = (T 'clean.confirm') -f $ids.Count
    if ($warn.Count -gt 0) { $msg += "`n`n" + ($warn -join "`n") }
    if (-not (Confirm-Box $msg)) { return }
    Start-Task 'clean.running' 'Invoke-Clean $TK.Args.Ids $TK.Args.Days' @{ Ids = $ids; Days = [int]$UI.SldAge.Value } {
        param($TK)
        $r = $TK.Result; if (-not $r) { return }
        foreach ($k in $r.Results.Keys) { if ($App.SizeLabels.ContainsKey($k) -and $k -ne 'dns') { $App.SizeLabels[$k].Text = '✓ ' + (Format-Size $r.Results[$k].Freed) } }
        $UI.TxtCleanSum.Text = (T 'clean.result') -f (Format-Size $r.Total), (Format-Time $r.Seconds)
        $App.Settings.totalFreed = [double]$App.Settings.totalFreed + [double]$r.Total
        if ([double]$r.Total -gt 0) { [void](Add-History 'cleanup' 'hist.cleanup' @((Format-Size $r.Total))) }
        $App.Settings.lastClean = (Get-Date).ToString('s')
        Save-AppSettings $App.Settings
        if ($r.Seconds -ge 60) { Send-Toast $AppName ((T 'clean.result') -f (Format-Size $r.Total), (Format-Time $r.Seconds)) }
    }
}

# ======================================================================
#  ΚΑΘΑΡΙΣΜΟΣ: ΚΑΡΤΕΛΕΣ (Προσωρινά | Υπολείμματα | Μεγάλα αρχεία)
# ======================================================================
function Build-CleanTabs {
    $UI.CleanTabs.Children.Clear()
    foreach ($tab in @('temp', 'left', 'big', 'dupes')) {
        $rb = New-Pill (T "clean.tab.$tab") $tab 'cleantab' ($tab -eq $App.CleanTab)
        $rb.Add_Checked({ $App.CleanTab = [string]$this.Tag; Show-CleanTab })
        [void]$UI.CleanTabs.Children.Add($rb)
    }
    Show-CleanTab
}

function Show-CleanTab {
    $UI.CleanMain.Visibility = 'Collapsed'; $UI.LeftBody.Visibility = 'Collapsed'; $UI.BigBody.Visibility = 'Collapsed'; $UI.DupeBody.Visibility = 'Collapsed'
    switch ($App.CleanTab) {
        'temp' { $UI.CleanMain.Visibility = 'Visible' }
        'left' { $UI.LeftBody.Visibility = 'Visible'; Build-LeftoverList }
        'big' { $UI.BigBody.Visibility = 'Visible'; Build-BigList }
        'dupes' { $UI.DupeBody.Visibility = 'Visible'; Build-DupeList }
    }
}

# ---------- Υπολείμματα ----------
function Build-LeftoverList {
    $p = $UI.LeftBody; $p.Children.Clear()
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'lo.intro') 13 'SubBrush'))
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $b1 = New-Button (T 'lo.scan') 'Secondary'; $b1.Margin = '0,0,10,8'; $b1.Add_Click({ Start-LeftoverScan }); [void]$wp.Children.Add($b1)
    if ($App.Leftovers -and $App.Leftovers.Count -gt 0) {
        $n = 0; for ($j = 0; $j -lt $App.Leftovers.Count; $j++) { if ($App.LeftSel[$j]) { $n++ } }
        $b2 = New-Button ((T 'lo.remove') -f $n) 'Primary'; $b2.Margin = '0,0,10,8'; $b2.Add_Click({ Start-LeftoverRemove }); [void]$wp.Children.Add($b2)
    }
    if ($App.LeftMsg) { $m = New-Text $App.LeftMsg 13 'GoodBrush' 'SemiBold'; $m.Margin = '0,4,0,0'; [void]$sp.Children.Add($m) }
    [void]$sp.Children.Add($wp); $card.Child = $sp; [void]$p.Children.Add($card)
    if ($null -eq $App.Leftovers) { [void]$p.Children.Add((New-Text (T 'lo.notscanned') 14 'SubBrush')) }
    elseif ($App.Leftovers.Count -eq 0) { [void]$p.Children.Add((New-Text (T 'lo.none') 15 'GoodBrush' 'SemiBold')) }
    else {
        $grp = $null
        for ($i = 0; $i -lt $App.Leftovers.Count; $i++) {
            $x = $App.Leftovers[$i]
            if ($x.Cat -ne $grp) { $grp = $x.Cat; [void]$p.Children.Add((New-GroupHeader (T "lo.cat.$grp"))) }
            $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
            $g = [Windows.Controls.Grid]::new()
            foreach ($w in @('Auto', '*')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
            $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Tag = $i; $chk.Margin = '0,0,16,0'
            $chk.IsChecked = [bool]$App.LeftSel[$i]
            $chk.Add_Click({ $App.LeftSel[[int]$this.Tag] = [bool]$this.IsChecked; Build-LeftoverList })
            $s = [Windows.Controls.StackPanel]::new()
            [void]$s.Children.Add((New-Text "$($x.Label)" 15 'TextBrush' 'SemiBold'))
            $d = New-Text ((T "lo.why.$($x.Cat)")) 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
            $mm = New-Text ((T 'lo.missing') -f $x.Missing) 12 'Accent2Brush'; $mm.Margin = '0,4,0,0'; [void]$s.Children.Add($mm)
            [Windows.Controls.Grid]::SetColumn($s, 1)
            [void]$g.Children.Add($chk); [void]$g.Children.Add($s); $c.Child = $g; [void]$p.Children.Add($c)
        }
    }
    # αντίγραφα ασφαλείας
    $bk = @(Get-LeftoverBackups)
    if ($bk.Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'lo.backups')))
        foreach ($b in $bk) {
            $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
            $s = [Windows.Controls.StackPanel]::new()
            [void]$s.Children.Add((New-Text ((T 'lo.backup.t') -f $b.When.ToString('g', (Get-LangCulture)), $b.Count) 14 'TextBrush' 'SemiBold'))
            $d = New-Text ((@($b.Labels) | Select-Object -First 5) -join ' · ') 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
            $rb = New-Button (T 'lo.restore') 'Secondary'; $rb.Tag = $b.Dir
            $rb.Add_Click({
                if (-not (Confirm-Box (T 'lo.restore.confirm'))) { return }
                Start-Task 'lo.restoring' 'Restore-LeftoverBackupCore $TK.Args.Dir' @{ Dir = [string]$this.Tag } { param($TK); $App.LeftMsg = (T 'lo.restored') -f $TK.Result.Ok; Build-LeftoverList }
            })
            $c.Child = (New-Row $s $rb); [void]$p.Children.Add($c)
        }
    }
}

function Start-LeftoverScan {
    $App.LeftMsg = ''
    Start-Task 'lo.scanning' 'Find-LeftoversCore' @{} {
        param($TK)
        $order = @{ startup = 0; shortcut = 1; uninstall = 2; task = 3 }
        $list = [System.Collections.ArrayList]::new()
        foreach ($x in ((ConvertTo-CleanList $TK.Result) | Sort-Object @{ e = { $order["$($_.Cat)"] } }, Label)) { [void]$list.Add($x) }
        $App.Leftovers = $list; $App.LeftSel = @{}; for ($i = 0; $i -lt $list.Count; $i++) { $App.LeftSel[$i] = $true }
        Build-LeftoverList
    }
}

function Start-LeftoverRemove {
    $sel = @(); for ($i = 0; $i -lt $App.Leftovers.Count; $i++) { if ($App.LeftSel[$i]) { $sel += $App.Leftovers[$i] } }
    if ($sel.Count -eq 0) { Show-Info (T 'lo.none.sel'); return }
    if (-not (Confirm-Box ((T 'lo.confirm') -f $sel.Count))) { return }
    Start-Task 'lo.removing' 'Remove-LeftoversCore $TK.Args.Items' @{ Items = $sel } {
        param($TK)
        $r = $TK.Result; if ($r) { $App.LeftMsg = (T 'lo.result') -f $r.Ok, $r.Fail; if ($r.Ok -gt 0) { [void](Add-History 'leftovers' 'hist.leftovers' @($r.Ok) @{ Type = 'leftovers'; Dir = "$($r.Dir)" }) } }
        $App.Leftovers = $null; Build-LeftoverList
    }
}

# ---------- Μεγάλα αρχεία ----------
function Build-BigList {
    $p = $UI.BigBody; $p.Children.Clear()
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'bf.intro') 13 'SubBrush'))
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,4'
    $locs = [System.Collections.ArrayList]::new()
    [void]$locs.Add(@('user', (T 'bf.loc.user'))); [void]$locs.Add(@('downloads', (T 'bf.loc.downloads')))
    foreach ($dv in @(Get-FixedDrives)) {
        $lbl = (T 'bf.loc.drive') -f $dv.Letter, (Format-Size $dv.Free); if ($dv.Label) { $lbl = "$($dv.Label) ($lbl)" }
        [void]$locs.Add(@($dv.Root, $lbl))
    }
    [void]$locs.Add(@('pick', (T 'bf.loc.pick')))
    foreach ($l in $locs) {
        $rb = New-Pill $l[1] $l[0] 'bigloc' ($l[0] -eq $App.BigLoc)
        $rb.Add_Checked({ $App.BigLoc = [string]$this.Tag })
        [void]$wp.Children.Add($rb)
    }
    [void]$sp.Children.Add($wp)
    $b = New-Button (T 'bf.scan') 'Primary'; $b.HorizontalAlignment = 'Left'
    $b.Add_Click({
        $root = switch ($App.BigLoc) { 'user' { $env:USERPROFILE } 'downloads' { Join-Path $env:USERPROFILE 'Downloads' } 'pick' { Select-Folder } default { $App.BigLoc } }
        if (-not $root) { return }
        Start-Task 'bf.scanning' 'Find-BigFilesCore $TK.Args.Root' @{ Root = $root } { param($TK); $App.Big = $TK.Result; Build-BigList }
    })
    [void]$sp.Children.Add($b)
    $card.Child = $sp; [void]$p.Children.Add($card)
    Add-WslCard $p
    if (-not $App.Big) { return }
    [void]$p.Children.Add((New-GroupHeader ((T 'bf.result') -f @($App.Big.Files).Count, $App.Big.Root)))
    foreach ($f in @($App.Big.Files)) {
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text ("$(Format-Size $f.Size)   $($f.Name)") 15 'TextBrush' 'SemiBold'))
        $d = New-Text ("$($f.Dir) · $($f.Date.ToString('d', (Get-LangCulture)))") 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
        $crit = Test-CriticalFile $f.Path
        if ($crit) { $w = New-Text ('⚠ ' + (T 'bf.crit')) 12 'BadBrush' 'SemiBold'; $w.Margin = '0,4,0,0'; [void]$s.Children.Add($w) }
        $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'
        $o = New-Button (T 'bf.open') 'Secondary'; $o.Tag = $f.Path; $o.Add_Click({ Start-Process explorer.exe -ArgumentList "/select,`"$([string]$this.Tag)`"" }); [void]$btns.Children.Add($o)
        $r = New-Button (T 'bf.recycle') 'Secondary'; $r.Tag = $f.Path; $r.Margin = '0'
        $r.Add_Click({
            $path = [string]$this.Tag
            $q = (T 'bf.recycle.confirm') -f (Split-Path $path -Leaf)
            if (Test-CriticalFile $path) { $q = (T 'bf.crit.confirm') -f (Split-Path $path -Leaf) }
            if (-not (Confirm-Box $q)) { return }
            try {
                Add-Type -AssemblyName Microsoft.VisualBasic
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                Write-AppLog "Recycle: $path"; [void](Add-History 'recycle' 'hist.recycle1' @((Split-Path $path -Leaf)) @{ Type = 'recyclebin' })
                $App.Big.Files = @($App.Big.Files | Where-Object { $_.Path -ne $path }); Build-BigList
            } catch { Show-Info ((T 'bf.recycle.fail') -f $_.Exception.Message) }
        })
        [void]$btns.Children.Add($r)
        $c.Child = (New-Row $s $btns); [void]$p.Children.Add($c)
    }
}

# ---------- Συμπίεση δίσκων WSL/Docker (στα Μεγάλα αρχεία) ----------
function Add-WslCard($p) {
    $disks = @(Get-WslDisks)
    if ($disks.Count -eq 0) { return }
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'wsl.t') 16 'TextBrush' 'SemiBold'))
    $d = New-Text (T 'wsl.d') 12 'SubBrush'; $d.Margin = '0,2,0,6'; [void]$sp.Children.Add($d)
    foreach ($x in $disks) { [void]$sp.Children.Add((New-Text ("• $(Format-Size $x.Size)   $($x.Path)") 12 'TextBrush')) }
    $a = New-Text ('↳ ' + (T 'wsl.a')) 12 'Accent2Brush'; $a.Margin = '0,6,0,0'; [void]$sp.Children.Add($a)
    $b = New-Button (T 'wsl.btn') 'Primary'; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,12,0,0'
    $b.Add_Click({
        if (Test-DockerRunning) { Show-Info (T 'wsl.docker'); return }
        if (-not (Confirm-Box (T 'wsl.confirm'))) { return }
        $paths = @(Get-WslDisks | ForEach-Object { $_.Path })
        Start-Task 'wsl.running' 'Invoke-CompactWslDisks $TK.Args.Paths' @{ Paths = $paths } { param($TK); if ($TK.Result) { Show-Info ((T 'wsl.done') -f (Format-Size $TK.Result.Saved)); [void](Add-History 'cleanup' 'hist.wsl' @((Format-Size $TK.Result.Saved))) }; Build-BigList }
    })
    [void]$sp.Children.Add($b)
    $card.Child = $sp; [void]$p.Children.Add($card)
}

# ---------- Διπλά αρχεία (καρτέλα στον Καθαρισμό) ----------
function Build-DupeList {
    $p = $UI.DupeBody; $p.Children.Clear()
    $ic = New-InfoCard '' (T 'du.intro')
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,4'
    $locs = [System.Collections.ArrayList]::new()
    [void]$locs.Add(@('user', (T 'bf.loc.user'))); [void]$locs.Add(@('downloads', (T 'bf.loc.downloads')))
    foreach ($dv in @(Get-FixedDrives)) { [void]$locs.Add(@($dv.Root, ((T 'bf.loc.drive') -f $dv.Letter, (Format-Size $dv.Free)))) }
    [void]$locs.Add(@('pick', (T 'bf.loc.pick')))
    foreach ($l in $locs) { $rb = New-Pill $l[1] $l[0] 'duploc' ($l[0] -eq $App.DupLoc); $rb.Add_Checked({ $App.DupLoc = [string]$this.Tag }); [void]$wp.Children.Add($rb) }
    [void]$ic.Panel.Children.Add($wp)
    $mp = [Windows.Controls.WrapPanel]::new()
    foreach ($m in @(@('1', '1 MB'), @('10', '10 MB'), @('100', '100 MB'))) { $rb = New-Pill ((T 'du.min') -f $m[1]) $m[0] 'dupmin' ($m[0] -eq $App.DupMin); $rb.Add_Checked({ $App.DupMin = [string]$this.Tag }); [void]$mp.Children.Add($rb) }
    [void]$ic.Panel.Children.Add($mp)
    $bw = [Windows.Controls.WrapPanel]::new(); $bw.Margin = '0,8,0,0'
    $b = New-Button (T 'du.scan') 'Primary'; $b.Margin = '0,0,10,8'
    $b.Add_Click({
        $root = switch ($App.DupLoc) { 'user' { $env:USERPROFILE } 'downloads' { Join-Path $env:USERPROFILE 'Downloads' } 'pick' { Select-Folder } default { $App.DupLoc } }
        if (-not $root) { return }
        Start-Task 'du.scanning' 'Find-DuplicatesCore $TK.Args.Root $TK.Args.Min' @{ Root = $root; Min = ([double]$App.DupMin * 1MB) } {
            param($TK); $App.DupSel = @{}
            if (-not $TK.Result) { $App.Dupes = $null; Show-Info (T 'diag.failed'); Build-DupeList; return }
            $App.Dupes = $TK.Result; $App.Dupes.Groups = ConvertTo-CleanList $App.Dupes.Groups
            foreach ($g in $App.Dupes.Groups) { $i = 0; foreach ($f in (ConvertTo-CleanList $g.Files)) { $App.DupSel["$($f.Path)"] = ($i -gt 0); $i++ } }
            Build-DupeList
        }
    }); [void]$bw.Children.Add($b)
    if ($App.Dupes -and @($App.Dupes.Groups).Count -gt 0) {
        $sel = @($App.DupSel.Keys | Where-Object { $App.DupSel[$_] })
        $size = 0.0; foreach ($g in @($App.Dupes.Groups)) { foreach ($f in @($g.Files)) { if ($App.DupSel[$f.Path]) { $size += $g.Size } } }
        $r = New-Button ((T 'du.recycle') -f $sel.Count, (Format-Size $size)) 'Secondary'; $r.Margin = '0,0,10,8'
        $r.Add_Click({
            $sel = @($App.DupSel.Keys | Where-Object { $App.DupSel[$_] })
            if ($sel.Count -eq 0) { Show-Info (T 'lo.none.sel'); return }
            # ασφάλεια: ποτέ όλα τα αντίγραφα μιας ομάδας
            foreach ($g in @($App.Dupes.Groups)) { if (@($g.Files | Where-Object { -not $App.DupSel[$_.Path] }).Count -eq 0) { Show-Info (T 'du.keepone'); return } }
            if (-not (Confirm-Box ((T 'du.confirm') -f $sel.Count))) { return }
            Add-Type -AssemblyName Microsoft.VisualBasic
            $ok = 0
            foreach ($f in $sel) { try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f, 'OnlyErrorDialogs', 'SendToRecycleBin'); $ok++; $App.DupSel.Remove($f) } catch {} }
            Write-AppLog "Duplicates to Recycle Bin: $ok"; if ($ok -gt 0) { [void](Add-History 'recycle' 'hist.dupes' @($ok) @{ Type = 'recyclebin' }) }
            foreach ($g in @($App.Dupes.Groups)) { $g.Files = @($g.Files | Where-Object { Test-Path -LiteralPath $_.Path }) }
            $App.Dupes.Groups = @($App.Dupes.Groups | Where-Object { @($_.Files).Count -gt 1 })
            Show-Info ((T 'du.recycled') -f $ok); Build-DupeList
        }); [void]$bw.Children.Add($r)
    }
    [void]$ic.Panel.Children.Add($bw); [void]$p.Children.Add($ic.Card)
    if (-not $App.Dupes) { return }
    if (@($App.Dupes.Groups).Count -eq 0) { [void]$p.Children.Add((New-Text (T 'du.none') 15 'GoodBrush' 'SemiBold')); return }
    [void]$p.Children.Add((New-GroupHeader ((T 'du.result') -f $App.Dupes.Total, (Format-Size $App.Dupes.Wasted))))
    foreach ($g in @($App.Dupes.Groups)) {
        $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text ((T 'du.group') -f $g.Count, (Format-Size $g.Size), (Format-Size $g.Wasted)) 14 'TextBrush' 'SemiBold'))
        $i = 0
        foreach ($f in @($g.Files)) {
            $row = [Windows.Controls.Grid]::new(); $row.Margin = '0,6,0,0'
            foreach ($w in @('Auto', '*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$row.ColumnDefinitions.Add($cd) }
            $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Margin = '0,0,12,0'; $chk.Tag = $f.Path
            $chk.IsChecked = [bool]$App.DupSel[$f.Path]; $chk.ToolTip = T 'du.tick'
            $chk.Add_Click({ $App.DupSel[[string]$this.Tag] = [bool]$this.IsChecked; Build-DupeList })
            $tx = [Windows.Controls.StackPanel]::new()
            [void]$tx.Children.Add((New-Text $f.Path 12 'TextBrush'))
            $note = $f.Date.ToString('g', (Get-LangCulture)); if ($i -eq 0) { $note += '  · ' + (T 'du.oldest') }
            [void]$tx.Children.Add((New-Text $note 11 'SubBrush'))
            $o = New-Button (T 'bf.open') 'Secondary'; $o.Tag = $f.Path; $o.Margin = '8,0,0,0'
            $o.Add_Click({ Start-Process explorer.exe -ArgumentList "/select,`"$([string]$this.Tag)`"" })
            [Windows.Controls.Grid]::SetColumn($tx, 1); [Windows.Controls.Grid]::SetColumn($o, 2)
            [void]$row.Children.Add($chk); [void]$row.Children.Add($tx); [void]$row.Children.Add($o)
            [void]$s.Children.Add($row); $i++
        }
        $c.Child = $s; [void]$p.Children.Add($c)
    }
}
