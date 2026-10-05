# John's Toolkit by nmx88 - Network & VPN, speed test, network repair, live monitor
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ---------- Speedtest & επιδιόρθωση δικτύου (κάρτες στη σελίδα Δίκτυο) ----------
function Add-SpeedCard($p) {
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'sp.t') 16 'TextBrush' 'SemiBold'))
    $d = New-Text (T 'sp.d') 12 'SubBrush'; $d.Margin = '0,2,0,10'; [void]$sp.Children.Add($d)
    $last = $App.Speed
    if (-not $last) { $h = @(Get-SpeedHistory); if ($h.Count -gt 0) { $last = $h[0] } }
    if ($last) {
        $grid = [Windows.Controls.Grid]::new()
        foreach ($i in 0..3) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = '*'; [void]$grid.ColumnDefinitions.Add($cd) }
        $vals = @(@('sp.l.down', ('{0}' -f $last.Down), 'Mbps', 'AccentBrush'), @('sp.l.up', ('{0}' -f $last.Up), 'Mbps', 'Accent2Brush'), @('sp.l.ping', ('{0}' -f $last.Ping), 'ms', 'TextBrush'), @('sp.l.jitter', ('{0}' -f $last.Jitter), 'ms', 'TextBrush'))
        for ($i = 0; $i -lt 4; $i++) {
            $col = [Windows.Controls.StackPanel]::new()
            [void]$col.Children.Add((New-Text (T $vals[$i][0]) 12 'SubBrush'))
            $num = New-Text ("$($vals[$i][1]) $($vals[$i][2])") 26 $vals[$i][3] 'Bold'; [void]$col.Children.Add($num)
            [Windows.Controls.Grid]::SetColumn($col, $i); [void]$grid.Children.Add($col)
        }
        [void]$sp.Children.Add($grid)
        $when = ''; try { $when = ([datetime]$last.When).ToString('g', (Get-LangCulture)) } catch {}
        $meta = (T 'sp.meta') -f $when, $last.Where
        $vpn = @(Get-VpnStatus | Where-Object { $_.Kind -eq 'vpn' } | ForEach-Object { $_.Name })
        if ($vpn.Count -gt 0) { $meta += ' · ' + ((T 'sp.viavpn') -f ($vpn -join ' + ')) }
        $m = New-Text $meta 12 'SubBrush'; $m.Margin = '0,8,0,0'; [void]$sp.Children.Add($m)
        $hist = @(Get-SpeedHistory | Select-Object -Skip 1 -First 4)
        if ($hist.Count -gt 0) {
            $ht = (T 'sp.history') + '  ' + (($hist | ForEach-Object { '↓{0} ↑{1}' -f $_.Down, $_.Up }) -join '   ·   ')
            $hh = New-Text $ht 11 'SubBrush'; $hh.Margin = '0,4,0,0'; [void]$sp.Children.Add($hh)
        }
    }
    $b = New-Button (T 'sp.run') 'Primary'; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,12,0,0'
    $b.Add_Click({ Start-SpeedTest })
    [void]$sp.Children.Add($b)
    $card.Child = $sp; [void]$p.Children.Add($card)
}

function Add-NetRepairCard($p) {
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'nr.t') 16 'TextBrush' 'SemiBold'))
    $d = New-Text (T 'nr.d') 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$sp.Children.Add($d)
    $a = New-Text ('↳ ' + (T 'nr.a')) 12 'Accent2Brush'; $a.Margin = '0,6,0,0'; [void]$sp.Children.Add($a)
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $b1 = New-Button (T 'nr.quick') 'Primary'; $b1.Margin = '0,0,10,8'
    $b1.Add_Click({
        if (-not (Confirm-Box (T 'nr.quick.confirm'))) { return }
        Start-Task 'nr.quick' 'Invoke-NetworkQuickFix' @{} {
            param($TK); $r = $TK.Result
            if ($r -and $r.Ip -and $r.Dns) { Show-Info (T 'nr.ok') } elseif ($r -and $r.Ip) { Show-Info (T 'nr.nodns') } else { Show-Info (T 'nr.offline') }
        }
    }); [void]$wp.Children.Add($b1)
    $b2 = New-Button (T 'nr.reset') 'Secondary'; $b2.Margin = '0,0,10,8'
    $b2.Add_Click({
        if (-not (Confirm-Box (T 'nr.reset.confirm'))) { return }
        Start-Task 'nr.reset' 'Invoke-NetworkReset' @{} { param($TK); [void](Add-History 'network' 'hist.netreset'); $App.NeedsRestart = $true; $UI.RestartBanner.Visibility = 'Visible'; Show-Info (T 'nr.reset.after') }
    }); [void]$wp.Children.Add($b2)
    $b3 = New-Button (T 'nr.ts') 'Secondary'; $b3.Margin = '0,0,10,8'; $b3.Add_Click({ Start-Process 'ms-settings:troubleshoot' }); [void]$wp.Children.Add($b3)
    [void]$sp.Children.Add($wp)
    $card.Child = $sp; [void]$p.Children.Add($card)
}

# ======================================================================
#  ΔΙΚΤΥΟ & VPN
# ======================================================================
function Build-NetPage {
    $p = $UI.NetBody; $p.Children.Clear()
    $d = $App.Net
    # κατάσταση
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    if ($d -and $d.Status) {
        if (@($d.VpnNames).Count -gt 0) { $t = New-Text ('● ' + ((T 'net.vpn.on') -f (@($d.VpnNames) -join ' + '), $d.Status.Ip, $d.Status.Country)) 17 'GoodBrush' 'SemiBold' }
        else { $t = New-Text ('● ' + ((T 'net.vpn.off') -f $d.Status.Ip, $d.Status.Country)) 17 'BadBrush' 'SemiBold' }
        [void]$sp.Children.Add($t)
        $s2 = New-Text ((T 'net.summary') -f $d.Total, @($d.Report).Count, $d.ThreatCount) 12 'SubBrush'; $s2.Margin = '0,4,0,0'; [void]$sp.Children.Add($s2)
    } elseif ($d) { [void]$sp.Children.Add((New-Text (T 'net.nostatus') 15 'WarnBrush' 'SemiBold')) }
    else { [void]$sp.Children.Add((New-Text (T 'net.intro') 13 'SubBrush')) }
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,14,0,0'
    $b1 = New-Button (T 'net.analyze') 'Primary'; $b1.Margin = '0,0,10,8'; $b1.Add_Click({ Start-NetAnalysis }); [void]$wp.Children.Add($b1)
    if ($d) { $b2 = New-Button (T 'net.export') 'Secondary'; $b2.Margin = '0,0,10,8'; $b2.Add_Click({ $f = Export-NetReportCore $App.Net; Start-Process $f }); [void]$wp.Children.Add($b2) }
    [void]$sp.Children.Add($wp)
    $geo = [Windows.Controls.CheckBox]::new(); $geo.Style = $Win.FindResource('Check'); $geo.IsChecked = [bool]$App.Settings.netGeo
    $geoT = New-Text (T 'net.geo.opt') 12 'SubBrush'; $geoT.Margin = '10,0,0,0'; $geoT.VerticalAlignment = 'Center'
    $geoRow = [Windows.Controls.StackPanel]::new(); $geoRow.Orientation = 'Horizontal'; $geoRow.Margin = '0,6,0,0'
    $geo.Add_Click({ $App.Settings.netGeo = [bool]$this.IsChecked; Save-AppSettings $App.Settings })
    [void]$geoRow.Children.Add($geo); [void]$geoRow.Children.Add($geoT); [void]$sp.Children.Add($geoRow)
    $card.Child = $sp; [void]$p.Children.Add($card)
    Add-SpeedCard $p
    Add-NetRepairCard $p

    # ζωντανή παρακολούθηση
    $mc = New-Card; $ms = [Windows.Controls.StackPanel]::new()
    $ml = [Windows.Controls.StackPanel]::new()
    [void]$ml.Children.Add((New-Text (T 'net.mon.t') 16 'TextBrush' 'SemiBold'))
    $md = New-Text (T 'net.mon.d') 12 'SubBrush'; $md.Margin = '0,2,0,0'; [void]$ml.Children.Add($md)
    $sw = [Windows.Controls.CheckBox]::new(); $sw.Style = $Win.FindResource('Switch'); $sw.IsChecked = [bool]$App.MonOn
    $sw.Add_Click({ if ([bool]$this.IsChecked) { Start-LiveMonitor } else { $App.MonOn = $false } })
    [void]$ms.Children.Add((New-Row $ml $sw))
    if (-not $App.MonList) {
        $App.MonList = [Windows.Controls.ListBox]::new(); $App.MonList.Height = 170; $App.MonList.Margin = '0,12,0,0'
        $App.MonList.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas'); $App.MonList.FontSize = 12
        $App.MonList.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush')
        $App.MonList.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'LineBrush')
    }
    $parent = $App.MonList.Parent; if ($parent) { $parent.Children.Remove($App.MonList) }
    if ($App.MonOn -or $App.MonList.Items.Count -gt 0) { [void]$ms.Children.Add($App.MonList) }
    $mc.Child = $ms; [void]$p.Children.Add($mc)

    if (-not $d) { return }
    [void]$p.Children.Add((New-GroupHeader (T 'net.programs')))
    foreach ($r in $d.Report) {
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $s = [Windows.Controls.StackPanel]::new()
        $lvBrush = @('GoodBrush', 'WarnBrush', 'BadBrush')[$r.Level]
        $head = [Windows.Controls.WrapPanel]::new()
        [void]$head.Children.Add((New-Badge (T ('net.lv.' + $r.Level)) $lvBrush))
        $nm = New-Text ("$($r.Name)   ") 15 'TextBrush' 'SemiBold'; $nm.Margin = '6,0,0,0'; [void]$head.Children.Add($nm)
        [void]$head.Children.Add((New-Text ((T 'net.conns') -f $r.Count) 13 'SubBrush'))
        [void]$s.Children.Add($head)
        $sig = T $r.SigKey; if ($r.Publisher) { $sig += ": $($r.Publisher)" }; if ($r.Trusted) { $sig += '  · ' + (T 'net.trusted') }
        $sg = New-Text $sig 12 'SubBrush'; $sg.Margin = '0,4,0,0'; [void]$s.Children.Add($sg)
        if ($r.Dest) { $ds = New-Text ((T 'net.dest') -f $r.Dest) 12 'SubBrush'; [void]$s.Children.Add($ds) }
        foreach ($f in @($r.Flags)) { $ft = T $f.K; if (@($f.A).Count) { $ft = $ft -f @($f.A) }; $fl = New-Text ('! ' + $ft) 12 $lvBrush; $fl.Margin = '0,3,0,0'; [void]$s.Children.Add($fl) }
        $btn = New-Button (T 'net.details') 'Secondary'; $btn.Tag = $r.PID
        $btn.Add_Click({ if ($App.NetOpen -eq [int]$this.Tag) { $App.NetOpen = -1 } else { $App.NetOpen = [int]$this.Tag }; Build-NetPage })
        $row = New-Row $s $btn
        if ($App.NetOpen -eq $r.PID) {
            $outer = [Windows.Controls.StackPanel]::new(); [void]$outer.Children.Add($row)
            [void]$outer.Children.Add((New-NetDetails $r)); $c.Child = $outer
        } else { $c.Child = $row }
        [void]$p.Children.Add($c)
    }
    if (@($d.Listen).Count -gt 0) {
        [void]$p.Children.Add((New-GroupHeader (T 'net.listen')))
        $c = New-Card; $s = [Windows.Controls.StackPanel]::new()
        foreach ($l in $d.Listen) { [void]$s.Children.Add((New-Text ("$($l.Name): $($l.Ports)") 13 'TextBrush')) }
        $n = New-Text (T 'net.listen.d') 12 'SubBrush'; $n.Margin = '0,8,0,0'; [void]$s.Children.Add($n)
        $c.Child = $s; [void]$p.Children.Add($c)
    }
}

function New-NetDetails($r) {
    $box = [Windows.Controls.StackPanel]::new(); $box.Margin = '0,14,0,0'
    [void]$box.Children.Add((New-Text ((T 'net.path') -f $r.Path) 12 'SubBrush'))
    foreach ($c in @($r.Conns)) {
        $via = ''; $br = 'TextBrush'
        if ($c.Via -eq 'vpn') { $via = '[VPN]' } elseif ($c.Via -eq 'out') { $via = '[' + (T 'net.outside') + ']'; $br = 'WarnBrush' }
        if ($c.Bad) { $br = 'BadBrush' }
        $t = New-Text ('{0}:{1}  {2}  {3}' -f $c.Ip, $c.Port, $via, $c.Org) 12 $br
        $t.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas'); [void]$box.Children.Add($t)
    }
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $mk = { param($key, $style) $b = New-Button (T $key) $style; $b.Margin = '0,0,10,8'; $b.Tag = $r; return $b }
    $b1 = & $mk 'net.a.folder' 'Secondary'; $b1.Add_Click({ if ($this.Tag.Path) { Start-Process explorer.exe -ArgumentList "/select,`"$($this.Tag.Path)`"" } }); [void]$wp.Children.Add($b1)
    $b2 = & $mk 'net.a.scan' 'Primary'
    $b2.Add_Click({
        $x = $this.Tag; if (-not $x.Path) { return }
        Start-Task 'net.scanning' 'Invoke-FileScanCore $TK.Args.Path' @{ Path = $x.Path } {
            param($TK)
            if ($TK.Result -eq 0) { Show-Info ((T 'net.scan.clean') -f (Split-Path $TK.Args.Path -Leaf)) }
            elseif ($TK.Result -eq 2) { Show-Info ((T 'net.scan.found') -f (Split-Path $TK.Args.Path -Leaf)) }
            else { Show-Info (Get-CodeText ([int]$TK.Result)) }
        }
    }); [void]$wp.Children.Add($b2)
    $b3 = & $mk 'net.a.vt' 'Secondary'; $b3.Add_Click({
        $x = $this.Tag
        if (-not $x.Path -or -not (Test-Path -LiteralPath $x.Path)) { Show-Info (T 'net.nofile'); return }
        $h = $null; try { $h = (Get-FileHash -LiteralPath $x.Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch {}
        if ($h) { Start-Process "https://www.virustotal.com/gui/file/$h" } else { Show-Info (T 'net.nofile') }
    }); [void]$wp.Children.Add($b3)
    $tk = 'net.a.trust'; if ($r.Trusted) { $tk = 'net.a.untrust' }
    $b4 = & $mk $tk 'Secondary'
    $b4.Add_Click({
        $x = $this.Tag; if (-not $x.Path) { return }
        $key = "$($x.Path)".ToLower(); $list = @(Get-TrustedList)
        if ($list -contains $key) { $list = @($list | Where-Object { $_ -ne $key }); $x.Trusted = $false } else { $list += $key; $x.Trusted = $true }
        Save-TrustedList $list; Build-NetPage
    }); [void]$wp.Children.Add($b4)
    $b5 = & $mk 'net.a.kill' 'Secondary'
    $b5.Add_Click({
        $x = $this.Tag
        $msg = (T 'net.kill.confirm') -f $x.Name; if ($x.Publisher -match 'Microsoft') { $msg += "`n`n" + (T 'net.kill.ms') }
        if (Confirm-Box $msg) { Stop-Process -Id $x.PID -Force -ErrorAction SilentlyContinue; Write-AppLog "Kill $($x.Name)"; $App.Net.Report = @($App.Net.Report | Where-Object { $_.PID -ne $x.PID }); Build-NetPage }
    }); [void]$wp.Children.Add($b5)
    [void]$box.Children.Add($wp)
    $note = New-Text (T 'net.vt.note') 11 'SubBrush'; [void]$box.Children.Add($note)
    return $box
}

function Start-NetAnalysis {
    $App.NetOpen = -1
    Start-Task 'net.analyzing' 'Get-NetReportCore $TK.Args.Geo' @{ Geo = [bool]$App.Settings.netGeo } {
        param($TK); $App.Net = $TK.Result; if ($TK.Result) { $App.Threat = $TK.Result.Threat }; Build-NetPage
    }
}

function Start-LiveMonitor {
    $App.MonSeen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($c in @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)) { [void]$App.MonSeen.Add("$($c.OwningProcess)|$($c.RemoteAddress)|$($c.RemotePort)") }
    $App.MonVpn = @(Get-VpnIps)
    if (-not $App.Threat) {
        $App.Threat = New-Object 'System.Collections.Generic.HashSet[string]'
        $cache = Join-Path $DataDir 'threat-ips.txt'
        if (Test-Path $cache) { foreach ($l in [IO.File]::ReadAllLines($cache)) { [void]$App.Threat.Add($l) } }
    }
    $App.MonOn = $true; $App.MonLast = Get-Date
    Add-MonLine ((T 'net.mon.started') -f $App.MonSeen.Count) 'SubBrush'
    Build-NetPage
}

function Add-MonLine([string]$text, [string]$brush) {
    $t = New-Text $text 12 $brush; $t.TextWrapping = 'NoWrap'
    [void]$App.MonList.Items.Add($t)
    while ($App.MonList.Items.Count -gt 300) { $App.MonList.Items.RemoveAt(0) }
    $App.MonList.ScrollIntoView($t)
}

function Step-LiveMonitor {
    $App.MonLast = Get-Date
    $new = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object {
        -not (Test-PrivateIp "$($_.RemoteAddress)") -and $App.MonSeen.Add("$($_.OwningProcess)|$($_.RemoteAddress)|$($_.RemotePort)") })
    $time = Get-Date -Format 'HH:mm:ss'
    foreach ($g in ($new | Group-Object OwningProcess)) {
        $pi = Get-ProcInfo ([int]$g.Name)
        $isTorrent = ("$($pi.Name)" -match $TorrentApps)
        foreach ($c in ($g.Group | Select-Object -First 4)) {
            $warn = @(); $red = $false
            if ($App.Threat -and $App.Threat.Contains("$($c.RemoteAddress)")) { $warn += (T 'net.mon.threat'); if (-not $isTorrent) { $red = $true } }
            $via = ''
            if ($App.MonVpn.Count -gt 0 -and "$($pi.Name)" -notmatch $VpnClientProc) {
                if ($App.MonVpn -contains "$($c.LocalAddress)") { $via = '[VPN]' } else { $via = '[' + (T 'net.outside') + ']'; if ($isTorrent) { $red = $true } else { $warn += (T 'net.outside') } }
            }
            if ("$($pi.Name)" -match $RemoteAccessApps) { $warn += (T 'net.mon.remote') }
            $br = 'TextBrush'; if ($warn.Count -gt 0) { $br = 'WarnBrush' }; if ($red) { $br = 'BadBrush'; [Console]::Beep(1000, 200) }
            Add-MonLine ('{0}  + {1,-18} → {2}:{3}  {4} {5}' -f $time, $pi.Name, $c.RemoteAddress, $c.RemotePort, $via, ($warn -join ', ')) $br
        }
        if ($g.Count -gt 4) { Add-MonLine ((T 'net.mon.more') -f $time, ($g.Count - 4), $pi.Name) 'SubBrush' }
    }
}

function Start-SpeedTest { Start-Task 'sp.running' 'Invoke-SpeedTest' @{} { param($TK); if ($TK.Result -and $TK.Result.Ok) { $App.Speed = $TK.Result } else { Show-Info (T 'sp.fail') }; Build-NetPage } }
