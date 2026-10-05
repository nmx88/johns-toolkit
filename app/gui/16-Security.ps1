# John's Toolkit by nmx88 - Security & health
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ---------- Ασφάλεια ----------
function Build-SecurityPage {
    $p = $UI.SecurityBody; $p.Children.Clear()
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    $items = @($App.Security)
    if ($null -eq $App.Security) { [void]$sp.Children.Add((New-Text (T 'sec.loading') 15 'SubBrush')) }
    else {
        $ok = @($items | Where-Object { $_.S -eq 'ok' }).Count; $warn = @($items | Where-Object { $_.S -eq 'warn' }).Count; $bad = @($items | Where-Object { $_.S -eq 'bad' }).Count
        $br = 'GoodBrush'; if ($bad -gt 0) { $br = 'BadBrush' } elseif ($warn -gt 0) { $br = 'WarnBrush' }
        [void]$sp.Children.Add((New-Text ((T 'sec.summary') -f $ok, $warn, $bad) 18 $br 'SemiBold'))
    }
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,14,0,0'
    $b1 = New-Button (T 'sec.recheck') 'Secondary'; $b1.Margin = '0,0,10,8'; $b1.Add_Click({ Start-SecurityCheck }); [void]$wp.Children.Add($b1)
    $b2 = New-Button (T 'sec.scan') 'Primary'; $b2.Margin = '0,0,10,8'
    $b2.Add_Click({ if (Confirm-Box (T 'sec.scan.confirm')) { Start-Task 'sec.scanning' 'Invoke-QuickScanCore' @{} { param($TK); Send-Toast $AppName (T 'sec.scan.done'); Show-Info (T 'sec.scan.done') } } })
    [void]$wp.Children.Add($b2)
    $b3 = New-Button (T 'sec.open') 'Secondary'; $b3.Margin = '0,0,10,8'; $b3.Add_Click({ Start-Process 'windowsdefender:' }); [void]$wp.Children.Add($b3)
    [void]$sp.Children.Add($wp); $card.Child = $sp; [void]$p.Children.Add($card)
    $grp = $null
    foreach ($it in $items) {
        $gg = "$($it.G)"; if (-not $gg) { $gg = 'sec' }
        if ($gg -ne $grp) { $grp = $gg; [void]$p.Children.Add((New-GroupHeader (T "sec.g.$gg"))) }
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in @('Auto', '*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $dot = New-Dot $it.S
        $txt = T $it.K; if (@($it.A).Count -gt 0) { $txt = $txt -f @($it.A) }
        $tb = New-Text $txt 14 'TextBrush'; $tb.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($tb, 1); [void]$g.Children.Add($dot); [void]$g.Children.Add($tb)
        $act = $null
        switch ($it.K) {
            'sec.ext.hidden' { $act = New-Button (T 'sec.fix.ext') 'Secondary'; $act.Add_Click({ $t = $Tweaks | Where-Object { $_.Id -eq 'fileext' } | Select-Object -First 1; if ($t) { Set-Tweak $t $true }; Start-SecurityCheck }) }
            'sec.upd.old' { $act = New-Button (T 'rep.wu.open') 'Secondary'; $act.Add_Click({ Start-Process 'ms-settings:windowsupdate' }) }
            'sec.rdp.on' { $act = New-Button (T 'sec.fix.rdp') 'Secondary'; $act.Add_Click({ Start-Process 'ms-settings:remotedesktop' }) }
            'sec.hvci.off' { $act = New-Button (T 'hvci.btn') 'Secondary'; $act.Add_Click({ Start-Process 'windowsdefender://coreisolation' }) }
            'sec.fw.off' { $act = New-Button (T 'sec.open') 'Secondary'; $act.Add_Click({ Start-Process 'windowsdefender://network' }) }
            'sec.av.none' { $act = New-Button (T 'sec.open') 'Secondary'; $act.Add_Click({ Start-Process 'windowsdefender:' }) }
            'hl.battery' { $act = New-Button (T 'hl.battery.btn') 'Secondary'; $act.Add_Click({ $f = New-BatteryReport; if ($f -and (Test-Path -LiteralPath $f)) { Start-Process $f } else { Show-Info (T 'diag.failed') } }) }
            'hl.uptime.long' { $act = New-Button (T 'hl.restart.btn') 'Secondary'; $act.Add_Click({ if (Confirm-Box (T 'hl.restart.confirm')) { Restart-Computer -Force } }) }
        }
        if ($act) { $act.Margin = '12,0,0,0'; $act.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($act, 2); [void]$g.Children.Add($act) }
        $c.Child = $g; [void]$p.Children.Add($c)
    }
}

function Start-SecurityCheck {
    $App.Security = $null; Build-SecurityPage
    Start-Task 'sec.loading' 'Get-SecurityAndHealth' @{} { param($TK); $App.Security = ConvertTo-CleanList $TK.Result; Build-SecurityPage }
}
