# John's Toolkit by nmx88 - Developer: PATH, ports, DNS
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function Set-DevMsg([string]$t, [string]$b = 'GoodBrush') { $UI.TxtDevMsg.Text = $t; $UI.TxtDevMsg.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $b) }

# ---------- Developer ----------
function Build-DevPage {
    $UI.DevTabs.Children.Clear()
    foreach ($tab in @('path', 'ports', 'dns')) {
        $rb = New-Pill (T "dev.tab.$tab") $tab 'devtab' ($tab -eq $App.DevTab)
        $rb.Add_Checked({ $App.DevTab = [string]$this.Tag; Set-DevMsg ''; Build-DevBody })
        [void]$UI.DevTabs.Children.Add($rb)
    }
    Build-DevBody
}

function Build-DevBody {
    $UI.DevBody.Children.Clear()
    switch ($App.DevTab) { 'path' { Build-PathTab } 'ports' { Build-PortsTab } 'dns' { Build-DnsTab } }
}

function Build-PathTab {
    $p = $UI.DevBody
    $rep = Get-PathReport
    if ($null -eq $App.PathSel) { $App.PathSel = @{}; foreach ($e in @($rep.Machine) + @($rep.User)) { if ($e -and $e.State -ne 'ok') { $App.PathSel["$($e.Scope)|$($e.Index)"] = $true } } }
    $ic = New-InfoCard (T 'path.t') (T 'path.d')
    if ($rep.FirstPython) {
        $fp = $rep.FirstPython; $nm = $fp.Python; if ($nm -eq 'store-alias') { $nm = T 'path.py.store' }
        $t = New-Text ((T 'path.py') -f $nm, $fp.Expanded) 13 'AccentBrush' 'SemiBold'; $t.Margin = '0,10,0,0'; [void]$ic.Panel.Children.Add($t)
        if ($fp.Python -eq 'store-alias') { $w = New-Text (T 'path.py.storehint') 12 'WarnBrush'; [void]$ic.Panel.Children.Add($w) }
    }
    $sel = @($App.PathSel.Keys | Where-Object { $App.PathSel[$_] })
    $b = New-Button ((T 'path.clean') -f $sel.Count) 'Primary'; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,12,0,0'
    $b.Add_Click({
        $keys = @($App.PathSel.Keys | Where-Object { $App.PathSel[$_] })
        if ($keys.Count -eq 0) { Show-Info (T 'path.none.sel'); return }
        if (-not (Confirm-Box ((T 'path.confirm') -f $keys.Count))) { return }
        foreach ($scope in 'Machine', 'User') {
            $idx = @($keys | Where-Object { $_ -like "$scope|*" } | ForEach-Object { [int]($_ -split '\|')[1] })
            if ($idx.Count -gt 0) { [void](Set-CleanPath $scope $idx) }
        }
        $App.PathSel = $null; Set-DevMsg ((T 'path.done') -f $keys.Count); Build-DevBody
    })
    [void]$ic.Panel.Children.Add($b); [void]$p.Children.Add($ic.Card)
    foreach ($scope in 'Machine', 'User') {
        [void]$p.Children.Add((New-GroupHeader (T "path.scope.$($scope.ToLower())")))
        foreach ($e in @($rep[$scope])) {
            if (-not $e) { continue }
            $c = New-ItemCard; $c.Padding = '16,8'; $c.Margin = '0,0,0,6'
            $g = [Windows.Controls.Grid]::new()
            foreach ($w in @('Auto', '*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
            $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Margin = '0,0,14,0'; $chk.Tag = "$($e.Scope)|$($e.Index)"
            $chk.IsChecked = [bool]$App.PathSel[$chk.Tag]; $chk.ToolTip = T 'path.remove'
            $chk.Add_Click({ $App.PathSel[[string]$this.Tag] = [bool]$this.IsChecked; Build-DevBody })
            $s = [Windows.Controls.StackPanel]::new()
            $shown = $e.Raw; if (-not $shown.Trim()) { $shown = T 'path.emptyentry' }
            $tb = New-Text $shown 13 'TextBrush'; $tb.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas'); [void]$s.Children.Add($tb)
            if ($e.Raw -ne $e.Expanded -and $e.Raw.Trim()) { [void]$s.Children.Add((New-Text ('= ' + $e.Expanded) 11 'SubBrush')) }
            if ($e.Python) { $nm = $e.Python; if ($nm -eq 'store-alias') { $nm = T 'path.py.store' }; [void]$s.Children.Add((New-Text ('🐍 ' + $nm) 11 'AccentBrush')) }
            $map = @{ ok = 'GoodBrush'; missing = 'BadBrush'; dup = 'WarnBrush'; empty = 'WarnBrush' }
            $bd = New-Badge (T "path.st.$($e.State)") $map[$e.State]; $bd.VerticalAlignment = 'Center'; $bd.Margin = '12,0,0,0'
            [Windows.Controls.Grid]::SetColumn($s, 1); [Windows.Controls.Grid]::SetColumn($bd, 2)
            [void]$g.Children.Add($chk); [void]$g.Children.Add($s); [void]$g.Children.Add($bd)
            $c.Child = $g; [void]$p.Children.Add($c)
        }
    }
    $bk = @(Get-PathBackups)
    if ($bk.Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'path.backups')))
        foreach ($f in $bk) {
            $c = New-ItemCard
            $s = New-Text ("$($f.LastWriteTime.ToString('g', (Get-LangCulture)))   ·   $($f.Name)") 13 'TextBrush'
            $rb = New-Button (T 'lo.restore') 'Secondary'; $rb.Tag = $f.FullName
            $rb.Add_Click({ if (Confirm-Box (T 'path.restore.confirm')) { $sc = Restore-PathBackup ([string]$this.Tag); $App.PathSel = $null; Set-DevMsg ((T 'path.restored') -f $sc); Build-DevBody } })
            $c.Child = (New-Row $s $rb); [void]$p.Children.Add($c)
        }
    }
}

function Build-PortsTab {
    $p = $UI.DevBody
    $ic = New-InfoCard (T 'port.t') (T 'port.d')
    $row = [Windows.Controls.WrapPanel]::new(); $row.Margin = '0,12,0,0'
    if (-not $App.PortBox) {
        $App.PortBox = New-TextBox '' 120
        $App.PortBox.Add_KeyDown({ if ("$($_.Key)" -eq 'Return') { Invoke-PortSearch $App.PortBox.Text } })
    }
    Add-Detached $row $App.PortBox
    $b = New-Button (T 'port.find') 'Primary'; $b.Margin = '0,0,10,8'; $b.Add_Click({ Invoke-PortSearch $App.PortBox.Text }); [void]$row.Children.Add($b)
    $b2 = New-Button (T 'port.all') 'Secondary'; $b2.Margin = '0,0,10,8'; $b2.Add_Click({ $App.PortNum = -1; Build-DevBody }); [void]$row.Children.Add($b2)
    [void]$ic.Panel.Children.Add($row)
    $quick = [Windows.Controls.WrapPanel]::new()
    foreach ($q in 80, 443, 3000, 5000, 5432, 1433, 3306, 6379, 8080, 27017) {
        $qb = New-Pill "$q" "$q" 'portq' ($App.PortNum -eq $q)
        $qb.Add_Checked({ $App.PortBox.Text = [string]$this.Tag; Invoke-PortSearch ([string]$this.Tag) })
        [void]$quick.Children.Add($qb)
    }
    [void]$ic.Panel.Children.Add($quick); [void]$p.Children.Add($ic.Card)
    if ($App.PortNum -eq -1) {
        [void]$p.Children.Add((New-GroupHeader (T 'port.listening')))
        $groups = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Group-Object OwningProcess)
        foreach ($g in $groups) {
            $pr = Get-Process -Id ([int]$g.Name) -ErrorAction SilentlyContinue
            $nm = if ($pr) { $pr.ProcessName } elseif ([int]$g.Name -eq 4) { 'System' } else { "PID $($g.Name)" }
            $ports = (@($g.Group | ForEach-Object { [int]$_.LocalPort }) | Sort-Object -Unique) -join ', '
            $c = New-ItemCard; $c.Padding = '16,8'; $c.Margin = '0,0,0,6'
            $c.Child = (New-Text ("$nm  (PID $($g.Name))   →   $ports") 13 'TextBrush'); [void]$p.Children.Add($c)
        }
        return
    }
    if ($App.PortNum -le 0) { return }
    $res = @($App.PortRes)
    if ($res.Count -eq 0) { [void]$p.Children.Add((New-Text ((T 'port.free') -f $App.PortNum) 15 'GoodBrush' 'SemiBold')); return }
    [void]$p.Children.Add((New-GroupHeader ((T 'port.used') -f $App.PortNum)))
    foreach ($r in $res) {
        $c = New-ItemCard; $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text ("$($r.Name)   (PID $($r.PID))") 15 'TextBrush' 'SemiBold'))
        if ($r.Path) { [void]$s.Children.Add((New-Text $r.Path 12 'SubBrush')) }
        if (@($r.Services).Count -gt 0) { [void]$s.Children.Add((New-Text ((T 'port.services') -f (@($r.Services) -join ', ')) 12 'AccentBrush')) }
        foreach ($l in @($r.Lines)) { $lt = New-Text ("$($l.Proto)  $($l.Local)  $($l.Remote)  $($l.State)") 12 'SubBrush'; $lt.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas'); [void]$s.Children.Add($lt) }
        $k = New-Button (T 'net.a.kill') 'Secondary'; $k.Tag = $r
        $k.Add_Click({
            $x = $this.Tag; $msg = (T 'net.kill.confirm') -f $x.Name
            if ($x.PID -le 4 -or $x.Name -match '^(svchost|lsass|wininit|services|System)$' -or @($x.Services).Count -gt 0) { $msg += "`n`n" + (T 'port.kill.sys') }
            if (Confirm-Box $msg) { Stop-Process -Id $x.PID -Force -ErrorAction SilentlyContinue; Write-AppLog "Kill port owner $($x.Name)"; Invoke-PortSearch "$($App.PortNum)" }
        })
        $c.Child = (New-Row $s $k); [void]$p.Children.Add($c)
    }
}

function Invoke-PortSearch([string]$txt) {
    $n = 0
    if (-not [int]::TryParse("$txt".Trim(), [ref]$n) -or $n -lt 1 -or $n -gt 65535) { Set-DevMsg (T 'port.bad') 'WarnBrush'; return }
    $App.PortNum = $n; $App.PortRes = @(Find-PortUsers $n); Set-DevMsg ''; Build-DevBody
}

function Build-DnsTab {
    $p = $UI.DevBody
    $ic = New-InfoCard (T 'dns.t') (T 'dns.d')
    $vpn = @(Get-VpnStatus | Where-Object { $_.Kind -eq 'vpn' } | ForEach-Object { $_.Name })
    if ($vpn.Count -gt 0) { $w = New-Text ('⚠ ' + ((T 'dns.vpn') -f ($vpn -join ' + '))) 12 'WarnBrush' 'SemiBold'; $w.Margin = '0,8,0,0'; [void]$ic.Panel.Children.Add($w) }
    foreach ($a in @(Get-DnsStatus)) {
        $t = New-Text ((T 'dns.now') -f $a.Name, (T "dns.p.$($a.Preset)"), $a.Servers) 13 'TextBrush'; $t.Margin = '0,8,0,0'; [void]$ic.Panel.Children.Add($t)
    }
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    foreach ($k in $DnsPresets.Keys) {
        $lbl = T "dns.p.$k"
        if ($App.DnsTimes -and $App.DnsTimes.Contains($k)) { $ms = $App.DnsTimes[$k]; if ($ms -ge 0) { $lbl += "  · $ms ms" } else { $lbl += '  · —' } }
        $rb = New-Pill $lbl $k 'dnsp' ($k -eq $App.DnsPick)
        $rb.Add_Checked({ $App.DnsPick = [string]$this.Tag })
        [void]$wp.Children.Add($rb)
    }
    [void]$ic.Panel.Children.Add($wp)
    $bw = [Windows.Controls.WrapPanel]::new(); $bw.Margin = '0,8,0,0'
    $b1 = New-Button (T 'dns.apply') 'Primary'; $b1.Margin = '0,0,10,8'
    $b1.Add_Click({
        if (-not $App.DnsPick) { Show-Info (T 'dns.pick'); return }
        if (-not (Confirm-Box ((T 'dns.confirm') -f (T "dns.p.$($App.DnsPick)")))) { return }
        $n = Set-DnsPreset $App.DnsPick; Set-DevMsg ((T 'dns.done') -f (T "dns.p.$($App.DnsPick)"), $n); Build-DevBody
    }); [void]$bw.Children.Add($b1)
    $b2 = New-Button (T 'dns.measure') 'Secondary'; $b2.Margin = '0,0,10,8'
    $b2.Add_Click({ Start-Task 'dns.measuring' 'Measure-DnsPresets' @{} { param($TK); if ($TK.Result) { $App.DnsTimes = $TK.Result }; Build-DevBody } }); [void]$bw.Children.Add($b2)
    [void]$ic.Panel.Children.Add($bw)
    $n = New-Text ('↳ ' + (T 'dns.note')) 12 'Accent2Brush'; $n.Margin = '0,4,0,0'; [void]$ic.Panel.Children.Add($n)
    [void]$p.Children.Add($ic.Card)
}
