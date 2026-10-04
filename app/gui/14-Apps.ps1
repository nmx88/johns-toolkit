# John's Toolkit by nmx88 - Apps: startup, updates, uninstall, pre-installed apps
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function Set-AppsMsg([string]$text, [string]$brush = 'GoodBrush') { $UI.TxtAppsMsg.Text = $text; $UI.TxtAppsMsg.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $brush) }

# ---------- Εφαρμογές ----------
function Build-AppsPage {
    $UI.AppsTabs.Children.Clear()
    foreach ($tab in @('startup', 'updates', 'uninstall', 'bloat')) {
        $rb = New-Pill (T "apps.tab.$tab") $tab 'appstab' ($tab -eq $App.AppsTab)
        $rb.Add_Checked({ $App.AppsTab = [string]$this.Tag; Set-AppsMsg ''; Build-AppsBody })
        [void]$UI.AppsTabs.Children.Add($rb)
    }
    Build-AppsBody
}

function Build-AppsBody {
    $UI.AppsBody.Children.Clear()
    switch ($App.AppsTab) { 'startup' { Build-StartupList } 'updates' { Build-UpdatesList } 'uninstall' { Build-UninstallTab } 'bloat' { Build-BloatList } }
}

function Build-StartupList {
    $p = $UI.AppsBody
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'st.intro') 13 'SubBrush'))
    $b = New-Button (T 'st.taskmgr') 'Secondary'; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,12,0,0'
    $b.Add_Click({ Start-Process taskmgr.exe -ArgumentList '/0 /startup' }); [void]$sp.Children.Add($b)
    $card.Child = $sp; [void]$p.Children.Add($card)
    $App.StartupEntries = @(Get-StartupEntries)
    if ($App.StartupEntries.Count -eq 0) { [void]$p.Children.Add((New-Text (T 'st.none') 14 'SubBrush')); return }
    for ($i = 0; $i -lt $App.StartupEntries.Count; $i++) {
        $e = $App.StartupEntries[$i]
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text "$($e.Name)" 15 'TextBrush' 'SemiBold'))
        $scope = T 'st.scope.all'; if ("$($e.Appr)" -like 'HKCU:*') { $scope = T 'st.scope.user' }
        $d = New-Text ("$scope · $($e.Command)") 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
        $hk = $null
        $all = "$($e.Name) $($e.Command)"
        if ($all -match 'mullvad|nordvpn|proton|expressvpn|surfshark|windscribe|cyberghost|ipvanish|tunnelbear|warp') { $hk = 'st.hint.vpn' }
        elseif ($all -match 'SecurityHealth|Defender') { $hk = 'st.hint.security' }
        elseif ($all -match $TorrentApps) { $hk = 'st.hint.torrent' }
        if ($hk) { $h = New-Text ('↳ ' + (T $hk)) 12 'Accent2Brush'; $h.Margin = '0,4,0,0'; [void]$s.Children.Add($h) }
        $sw = [Windows.Controls.CheckBox]::new(); $sw.Style = $Win.FindResource('Switch'); $sw.Tag = $i; $sw.IsChecked = [bool]$e.Enabled
        $sw.Add_Click({
            $en = $App.StartupEntries[[int]$this.Tag]; $on = [bool]$this.IsChecked
            Set-StartupEnabled $en $on
            Write-AppLog "Startup: $($en.Name) -> $on"
            if ($on) { Set-AppsMsg ((T 'st.on') -f $en.Name) } else { Set-AppsMsg ((T 'st.off') -f $en.Name) }
        })
        $c.Child = (New-Row $s $sw); [void]$p.Children.Add($c)
    }
}

function Get-UpdSelected { if (-not $App.Updates) { return @() }; return @($App.Updates | Where-Object { $_ -and $App.UpdSel["$($_.Id)"] }) }

function Build-UpdatesList {
    $p = $UI.AppsBody
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'upd.intro') 13 'SubBrush'))
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $bs = New-Button (T 'upd.scan') 'Secondary'; $bs.Add_Click({ Start-UpdateScan }); [void]$wp.Children.Add($bs)
    if ($App.Updates -and @($App.Updates).Count -gt 0) {
        $br = New-Button (T 'upd.selrec') 'Secondary'
        $br.Add_Click({ foreach ($u in $App.Updates) { $App.UpdSel[$u.Id] = ($u.Level -lt 2) }; Build-AppsBody }); [void]$wp.Children.Add($br)
        $bu = New-Button ((T 'upd.run') -f @(Get-UpdSelected).Count) 'Primary'; $bu.Add_Click({ Start-UpdateRun }); [void]$wp.Children.Add($bu)
    }
    [void]$sp.Children.Add($wp); $card.Child = $sp; [void]$p.Children.Add($card)

    if ($null -eq $App.Updates) { [void]$p.Children.Add((New-Text (T 'upd.notscanned') 14 'SubBrush')); return }
    if ($App.NoWinget) { [void]$p.Children.Add((New-Text (T 'upd.nowinget') 14 'WarnBrush')); return }
    if (@($App.Updates).Count -eq 0) { [void]$p.Children.Add((New-Text (T 'upd.none') 15 'GoodBrush' 'SemiBold')) }
    $grp = -1
    foreach ($u in $App.Updates) {
        if ($u.Level -ne $grp) { $grp = $u.Level; [void]$p.Children.Add((New-GroupHeader (T (@('upd.g.safe', 'upd.g.major', 'upd.g.careful')[$grp])))) }
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in @('Auto', '*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Tag = $u.Id; $chk.Margin = '0,0,16,0'
        $chk.IsChecked = [bool]$App.UpdSel[$u.Id]
        $chk.Add_Click({ $App.UpdSel[[string]$this.Tag] = [bool]$this.IsChecked; Build-AppsBody })
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text ("$($u.Name)   $($u.Version) → $($u.Available)") 15 'TextBrush' 'SemiBold'))
        $rb = 'SubBrush'; if ($u.Level -gt 0) { $rb = 'WarnBrush' }
        $why = T $u.K; if (@($u.A).Count -gt 0) { $why = $why -f @($u.A) }
        $d = New-Text $why 12 $rb; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
        $fz = New-Button (T 'upd.freeze') 'Secondary'; $fz.Tag = $u.Id; $fz.VerticalAlignment = 'Center'; $fz.Margin = '12,0,0,0'
        $fz.ToolTip = T 'upd.freeze.d'
        $fz.Add_Click({ Start-PinChange ([string]$this.Tag) $true })
        [Windows.Controls.Grid]::SetColumn($s, 1); [Windows.Controls.Grid]::SetColumn($fz, 2)
        [void]$g.Children.Add($chk); [void]$g.Children.Add($s); [void]$g.Children.Add($fz)
        $c.Child = $g; [void]$p.Children.Add($c)
    }
    if (@($App.Pins).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'upd.pinned')))
        foreach ($pin in $App.Pins) {
            $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
            $s = [Windows.Controls.StackPanel]::new()
            [void]$s.Children.Add((New-Text "$($pin.Name)" 15 'TextBrush' 'SemiBold'))
            $d = New-Text (T 'upd.pinned.d') 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
            $uf = New-Button (T 'upd.unfreeze') 'Secondary'; $uf.Tag = $pin.Id
            $uf.Add_Click({ Start-PinChange ([string]$this.Tag) $false })
            $c.Child = (New-Row $s $uf); [void]$p.Children.Add($c)
        }
    }
}

function Start-UpdateScan {
    Start-Task 'upd.scanning' 'Get-UpdateInfo' @{} {
        param($TK)
        $r = $TK.Result; if (-not $r) { return }
        $App.NoWinget = [bool]$r.NoWinget; $App.Updates = ConvertTo-CleanList $r.Updates; $App.Pins = ConvertTo-CleanList $r.Pins; $App.UpdSel = @{}
        foreach ($u in $App.Updates) { $App.UpdSel[$u.Id] = ($u.Level -lt 2) }
        Set-AppsMsg ((T 'upd.found') -f @($App.Updates).Count)
        if ($App.AppsTab -eq 'updates') { Build-AppsBody }
    }
}

function Start-UpdateRun {
    $sel = @(Get-UpdSelected)
    if ($sel.Count -eq 0) { Show-Info (T 'upd.none.sel'); return }
    $msg = (T 'upd.confirm') -f $sel.Count
    if (@($sel | Where-Object { $_.K -eq 'upd.r.vpn' }).Count -gt 0) { $msg += "`n`n" + (T 'upd.vpnwarn') }
    if (-not (Confirm-Box $msg)) { return }
    $items = @($sel | ForEach-Object { @{ Id = $_.Id; Name = $_.Name; Version = $_.Version; Available = $_.Available } })
    Start-Task 'upd.running' 'Update-AppsCore $TK.Args.Items' @{ Items = $items } {
        param($TK)
        $r = $TK.Result; if (-not $r) { return }
        $m = (T 'upd.result') -f $r.Ok, @($r.Fail).Count
        if (@($r.Fail).Count -gt 0) { Set-AppsMsg $m 'WarnBrush' } else { Set-AppsMsg $m }
        Send-Toast $AppName $m
        Start-UpdateScan
    }
}

function Start-PinChange([string]$id, [bool]$pin) {
    Start-Task 'upd.pinning' 'Set-PinCore $TK.Args.Id $TK.Args.Pin' @{ Id = $id; Pin = $pin } {
        param($TK)
        if ($TK.Result -eq 0) { if ($TK.Args.Pin) { Set-AppsMsg ((T 'upd.frozen') -f $TK.Args.Id) } else { Set-AppsMsg ((T 'upd.unfrozen') -f $TK.Args.Id) }; Start-UpdateScan }
        else { Set-AppsMsg (T 'upd.pinfail') 'WarnBrush' }
    }
}

function Build-BloatList {
    $p = $UI.AppsBody
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'bl.intro') 13 'SubBrush'))
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $sel = @(Get-BloatSelected)
    $b = New-Button ((T 'bl.remove') -f $sel.Count) 'Primary'; $b.Add_Click({ Start-BloatRemove }); [void]$wp.Children.Add($b)
    [void]$sp.Children.Add($wp); $card.Child = $sp; [void]$p.Children.Add($card)
    if ($null -eq $App.Bloat) {
        [void]$p.Children.Add((New-Text (T 'bl.loading') 14 'SubBrush'))
        if (-not $App.Busy) {
            Start-Task 'bl.loading' 'Get-BloatInstalled' @{} { param($TK); $App.Bloat = ConvertTo-CleanList $TK.Result; if ($App.AppsTab -eq 'bloat') { Build-AppsBody } } -Silent
        }
        return
    }
    if (@($App.Bloat).Count -eq 0) { [void]$p.Children.Add((New-Text (T 'bl.none') 15 'GoodBrush' 'SemiBold')); return }
    foreach ($a in $App.Bloat) {
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in @('Auto', '*')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Tag = $a.Pkg; $chk.Margin = '0,0,16,0'
        $chk.IsChecked = [bool]$App.BloatSel[$a.Pkg]
        $chk.Add_Click({ $App.BloatSel[[string]$this.Tag] = [bool]$this.IsChecked; Build-AppsBody })
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text "$($a.Name)" 15 'TextBrush' 'SemiBold'))
        $dt = $a.Pkg; if ($a.Note) { $dt = (T $a.Note) + ' · ' + $a.Pkg }
        $d = New-Text $dt 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$s.Children.Add($d)
        [Windows.Controls.Grid]::SetColumn($s, 1)
        [void]$g.Children.Add($chk); [void]$g.Children.Add($s)
        $c.Child = $g; [void]$p.Children.Add($c)
    }
}

function Get-BloatSelected { if (-not $App.Bloat) { return @() }; return @($App.Bloat | Where-Object { $_ -and $App.BloatSel["$($_.Pkg)"] }) }

function Start-BloatRemove {
    $sel = @(Get-BloatSelected)
    if ($sel.Count -eq 0) { Show-Info (T 'bl.none.sel'); return }
    if (-not (Confirm-Box ((T 'bl.confirm') -f $sel.Count, (($sel | ForEach-Object { '• ' + $_.Name }) -join "`n")))) { return }
    $items = @($sel | ForEach-Object { @{ Pkg = $_.Pkg; Name = $_.Name } })
    Start-Task 'bl.running' 'Remove-BloatCore $TK.Args.Items' @{ Items = $items } {
        param($TK)
        if ($TK.Result) { Set-AppsMsg ((T 'bl.done') -f $TK.Result.Removed) }
        $App.Bloat = $null; $App.BloatSel = @{}; Build-AppsBody
    }
}

# ---------- Απεγκατάσταση (καρτέλα στις Εφαρμογές) ----------
function Build-UninstallTab {
    $p = $UI.AppsBody
    if ($App.UnLeft) {
        $lc = New-Card; $ls = [Windows.Controls.StackPanel]::new()
        [void]$ls.Children.Add((New-Text ((T 'un.left.t') -f $App.UnLeft.Name) 16 'TextBrush' 'SemiBold'))
        if (@($App.UnLeft.Items).Count -eq 0) { [void]$ls.Children.Add((New-Text (T 'un.left.none') 13 'GoodBrush')) }
        foreach ($it in @($App.UnLeft.Items)) {
            $g = [Windows.Controls.Grid]::new(); $g.Margin = '0,8,0,0'
            foreach ($w in @('Auto', '*')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
            $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Margin = '0,0,14,0'; $chk.Tag = $it.Path
            if ($null -eq $App.UnLeftSel[$it.Path]) { $App.UnLeftSel[$it.Path] = [bool]$it.Sure }
            $chk.IsChecked = [bool]$App.UnLeftSel[$it.Path]
            $chk.Add_Click({ $App.UnLeftSel[[string]$this.Tag] = [bool]$this.IsChecked })
            $s = [Windows.Controls.StackPanel]::new()
            $sz = ''; if ($it.Size -gt 0) { $sz = '   ' + (Format-Size $it.Size) }
            [void]$s.Children.Add((New-Text ("$($it.Path)$sz") 13 'TextBrush'))
            $nk = 'un.left.check'; if ($it.Sure) { $nk = 'un.left.sure' }
            [void]$s.Children.Add((New-Text (T $nk) 11 'SubBrush'))
            [Windows.Controls.Grid]::SetColumn($s, 1); [void]$g.Children.Add($chk); [void]$g.Children.Add($s); [void]$ls.Children.Add($g)
        }
        $bw = [Windows.Controls.WrapPanel]::new(); $bw.Margin = '0,12,0,0'
        if (@($App.UnLeft.Items).Count -gt 0) {
            $b = New-Button (T 'un.left.remove') 'Primary'; $b.Margin = '0,0,10,0'
            $b.Add_Click({
                $sel = @($App.UnLeft.Items | Where-Object { $_ -and $App.UnLeftSel["$($_.Path)"] })
                if ($sel.Count -eq 0) { Show-Info (T 'lo.none.sel'); return }
                if (-not (Confirm-Box ((T 'un.left.confirm') -f $sel.Count))) { return }
                Start-Task 'un.left.removing' 'Remove-AppLeftovers $TK.Args.Items' @{ Items = $sel } { param($TK); if ($TK.Result) { Set-AppsMsg ((T 'un.left.result') -f $TK.Result.Ok) }; $App.UnLeft = $null; Build-AppsBody }
            }); [void]$bw.Children.Add($b)
        }
        $x = New-Button (T 'un.left.skip') 'Secondary'; $x.Add_Click({ $App.UnLeft = $null; Build-AppsBody }); [void]$bw.Children.Add($x)
        [void]$ls.Children.Add($bw); $lc.Child = $ls; [void]$p.Children.Add($lc)
    }
    $ic = New-InfoCard '' (T 'un.intro')
    $row = [Windows.Controls.WrapPanel]::new(); $row.Margin = '0,12,0,0'
    if (-not $App.UnBox) { $App.UnBox = New-TextBox '' 260; $App.UnBox.Add_TextChanged({ Build-UninstallRows }) }
    Add-Detached $row $App.UnBox
    foreach ($so in 'name', 'size', 'date') {
        $rb = New-Pill (T "un.sort.$so") $so 'unsort' ($so -eq $App.UnSort)
        $rb.Add_Checked({ $App.UnSort = [string]$this.Tag; Build-UninstallRows })
        [void]$row.Children.Add($rb)
    }
    [void]$ic.Panel.Children.Add($row); [void]$p.Children.Add($ic.Card)
    if (-not $App.UnRows) { $App.UnRows = [Windows.Controls.StackPanel]::new() }
    Add-Detached $p $App.UnRows
    if ($null -eq $App.Programs) {
        $App.UnRows.Children.Clear(); [void]$App.UnRows.Children.Add((New-Text (T 'un.loading') 14 'SubBrush'))
        if (-not $App.Busy) { Start-Task 'un.loading' 'Get-InstalledPrograms' @{} { param($TK); $App.Programs = ConvertTo-CleanList $TK.Result; if ($App.AppsTab -eq 'uninstall') { Build-UninstallRows } } -Silent }
        return
    }
    Build-UninstallRows
}

function Build-UninstallRows {
    if (-not $App.UnRows -or $null -eq $App.Programs) { return }
    $App.UnRows.Children.Clear()
    $q = "$($App.UnBox.Text)".Trim()
    $list = @($App.Programs | Where-Object { $_ -and (-not $q -or $_.Name -like "*$q*" -or $_.Publisher -like "*$q*") })
    switch ($App.UnSort) { 'size' { $list = @($list | Sort-Object Size -Descending) } 'date' { $list = @($list | Sort-Object { if ($_.Date) { $_.Date } else { [datetime]::MinValue } } -Descending) } default { $list = @($list | Sort-Object Name) } }
    [void]$App.UnRows.Children.Add((New-GroupHeader ((T 'un.count') -f $list.Count)))
    foreach ($a in ($list | Select-Object -First 150)) {
        $c = New-ItemCard; $c.Padding = '16,10'; $c.Margin = '0,0,0,6'
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text $a.Name 14 'TextBrush' 'SemiBold'))
        $meta = @($a.Publisher, $a.Version) | Where-Object { $_ }
        if ($a.Size -gt 0) { $meta += Format-Size $a.Size }; if ($a.Date) { $meta += $a.Date.ToString('d', (Get-LangCulture)) }
        [void]$s.Children.Add((New-Text ($meta -join ' · ') 12 'SubBrush'))
        $b = New-Button (T 'un.btn') 'Secondary'; $b.Tag = $a
        $b.Add_Click({
            $x = $this.Tag
            if (-not (Confirm-Box ((T 'un.confirm') -f $x.Name))) { return }
            Start-Task 'un.running' 'Invoke-UninstallCore $TK.Args.App' @{ App = $x } {
                param($TK); $r = $TK.Result
                if ($r) { $App.UnLeft = @{ Name = $TK.Args.App.Name; Items = (ConvertTo-CleanList $r.Leftovers) }; $App.UnLeftSel = @{} }
                $App.Programs = $null; Build-AppsBody
            }
        })
        $c.Child = (New-Row $s $b); [void]$App.UnRows.Children.Add($c)
    }
}
