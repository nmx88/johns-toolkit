# John's Toolkit by nmx88 - Home: dashboard and PC specs
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ---------- Αρχική ----------
function Update-Dashboard([switch]$Force) {
    if (-not $Force -and ((Get-Date) - $App.LastDash).TotalSeconds -lt 4) { return }
    $App.LastDash = Get-Date
    $d = Get-Dashboard
    if ($null -ne $d.DiskPct) {
        $UI.GDiskV.Text = '{0:0}%' -f $d.DiskPct; $UI.GDiskBar.Value = $d.DiskPct
        $dc = 'TextBrush'; if ($d.DiskPct -ge 95) { $dc = 'BadBrush' } elseif ($d.DiskPct -ge 85) { $dc = 'WarnBrush' }
        $UI.GDiskV.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $dc)
        $UI.GDiskD.Text = (T 'home.disk.d') -f (Format-Size $d.DiskFree), (Format-Size $d.DiskTotal)
    }
    if ($null -ne $d.RamPct) {
        $UI.GRamV.Text = '{0:0}%' -f $d.RamPct; $UI.GRamBar.Value = $d.RamPct
        $UI.GRamD.Text = (T 'home.ram.d') -f (Format-Size $d.RamUsed), (Format-Size $d.RamTotal)
    }
    if ($null -ne $d.CpuPct) { $UI.GCpuV.Text = '{0:0}%' -f $d.CpuPct; $UI.GCpuBar.Value = $d.CpuPct; $UI.GCpuD.Text = "$($d.CpuName)" }
    $vpn = @($d.Vpns | Where-Object { $_.Kind -eq 'vpn' } | ForEach-Object { $_.Name })
    $mesh = @($d.Vpns | Where-Object { $_.Kind -eq 'mesh' } | ForEach-Object { $_.Name })
    if ($vpn.Count -gt 0) {
        $UI.InfVpn.Text = '● ' + ((T 'home.vpn.on') -f ($vpn -join ' + '))
        $UI.InfVpn.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'GoodBrush')
    } elseif ($mesh.Count -gt 0) {
        $UI.InfVpn.Text = '○ ' + ((T 'home.vpn.mesh') -f ($mesh -join ' + '))
        $UI.InfVpn.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnBrush')
    } else {
        $UI.InfVpn.Text = '○ ' + (T 'home.vpn.off')
        $UI.InfVpn.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnBrush')
    }
    if ($d.Uptime) { $UI.InfUp.Text = (T 'home.uptime.v') -f $d.Uptime.Days, $d.Uptime.Hours }
    $UI.InfFreed.Text = Format-Size ([double]$App.Settings.totalFreed)
    $need = $d.Reboot -or $App.NeedsRestart -or $State.NeedsRestart
    if ($need) { $UI.RestartBanner.Visibility = 'Visible' } else { $UI.RestartBanner.Visibility = 'Collapsed' }
}

# ---------- Τεχνικά χαρακτηριστικά ----------
function Build-SpecGrid {
    $grid = $UI.SpecGrid
    $grid.Children.Clear(); $grid.RowDefinitions.Clear(); $grid.ColumnDefinitions.Clear()
    foreach ($w in @('190', '*')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$grid.ColumnDefinitions.Add($cd) }
    $specs = @($App.Specs)
    if ($specs.Count -eq 0) {
        $t = New-Text (T 'spec.loading') 13 'SubBrush'; [void]$grid.Children.Add($t); return
    }
    for ($i = 0; $i -lt $specs.Count; $i++) {
        $rd = [Windows.Controls.RowDefinition]::new(); $rd.Height = 'Auto'; [void]$grid.RowDefinitions.Add($rd)
        $k = New-Text (T $specs[$i].K) 13 'SubBrush'; $k.Margin = '0,4,12,4'
        $v = New-Text ([string]$specs[$i].V) 13 'TextBrush' 'SemiBold'; $v.Margin = '0,4,0,4'
        [Windows.Controls.Grid]::SetRow($k, $i); [Windows.Controls.Grid]::SetRow($v, $i); [Windows.Controls.Grid]::SetColumn($v, 1)
        [void]$grid.Children.Add($k); [void]$grid.Children.Add($v)
    }
}

function Start-SpecsScan {
    $App.Specs = @(); Build-SpecGrid
    Start-Task 'spec.loading' 'Get-PcSpecs' @{} { param($TK); $App.Specs = ConvertTo-CleanList $TK.Result; Build-SpecGrid } -Silent
}

function Copy-Specs {
    $lines = @("John's Toolkit v$AppVersion - " + (T 'spec.title'), '')
    foreach ($s in @($App.Specs)) {
        $vals = ([string]$s.V) -split "`n"
        $lines += ('{0}: {1}' -f (T $s.K), $vals[0])
        foreach ($x in ($vals | Select-Object -Skip 1)) { $lines += ('    ' + $x) }
    }
    try { [System.Windows.Clipboard]::SetText(($lines -join "`r`n")); $UI.TaskLabel.Text = T 'spec.copied' } catch {}
}
