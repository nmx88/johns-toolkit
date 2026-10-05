# John's Toolkit by nmx88 - Windows settings and power plan
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function Get-VisibleTweaks { return @($Tweaks | Where-Object { $App.Os.IsWin11 -or ($Win11Only -notcontains $_.Id) }) }

function Get-TweakText($t, [string]$part) {
    $k = "tw.$($t.Id).$part"; $v = T $k
    if ($v -ne $k) { return $v }
    switch ($part) { 'l' { return $t.Label } 'w' { return $t.What } 'a' { return $t.Affects } }
}

function Build-TweakList {
    $UI.TweakList.Children.Clear()
    $grp = $null
    foreach ($t in Get-VisibleTweaks) {
        if ($t.Group -ne $grp) { $grp = $t.Group; $gk = $GroupKeys[$grp]; $gt = $grp; if ($gk) { $gt = T $gk }; [void]$UI.TweakList.Children.Add((New-GroupHeader $gt)) }
        $card = New-Card
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in @('*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Margin = '0,0,20,0'
        [void]$sp.Children.Add((New-Text (Get-TweakText $t 'l') 16 'TextBrush' 'SemiBold'))
        $badges = [Windows.Controls.WrapPanel]::new(); $badges.Margin = '0,6,0,2'
        if ($t.Recommended) { [void]$badges.Children.Add((New-Badge (T 'badge.rec') 'GoodBrush')) }
        if ($Win11Only -contains $t.Id) { [void]$badges.Children.Add((New-Badge 'Windows 11' 'AccentBrush')) }
        if ($t.Restart -eq 'restart') { [void]$badges.Children.Add((New-Badge (T 'badge.restart') 'WarnBrush')) }
        elseif ($t.Restart -eq 'signout') { [void]$badges.Children.Add((New-Badge (T 'badge.signout') 'WarnBrush')) }
        elseif ($t.Restart -eq 'explorer') { [void]$badges.Children.Add((New-Badge (T 'badge.explorer') 'WarnBrush')) }
        if ($badges.Children.Count -gt 0) { [void]$sp.Children.Add($badges) }
        $d = New-Text (Get-TweakText $t 'w') 13 'SubBrush'; $d.Margin = '0,4,0,0'; [void]$sp.Children.Add($d)
        $a = New-Text ('↳ ' + (Get-TweakText $t 'a')) 12 'Accent2Brush'; $a.Margin = '0,6,0,0'; [void]$sp.Children.Add($a)
        $sw = [Windows.Controls.CheckBox]::new(); $sw.Style = $Win.FindResource('Switch'); $sw.Tag = $t.Id; $sw.IsChecked = [bool](Get-TweakState $t)
        $sw.Add_Click({
            $id = [string]$this.Tag; $tw = $Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
            if (-not $tw) { return }
            $on = [bool]$this.IsChecked
            $was = [bool](Get-TweakState $tw)
            Set-Tweak $tw $on
            $this.IsChecked = [bool](Get-TweakState $tw)
            $name = Get-TweakText $tw 'l'
            if ([bool]$this.IsChecked -ne $was) { [void](Add-History 'tweak' $(if ($on) { 'hist.tweak.on' } else { 'hist.tweak.off' }) @($name) @{ Type = 'tweaks'; Items = @(@{ Id = $tw.Id; Was = $was }) }) }
            if ($on) { $UI.TxtTweakMsg.Text = (T 'tw.on') -f $name } else { $UI.TxtTweakMsg.Text = (T 'tw.off') -f $name }
            if ($tw.Restart -and $tw.Restart -ne 'explorer') { $App.NeedsRestart = $true; $UI.RestartBanner.Visibility = 'Visible' }
        })
        [Windows.Controls.Grid]::SetColumn($sw, 1)
        [void]$g.Children.Add($sp); [void]$g.Children.Add($sw)
        $card.Child = $g
        [void]$UI.TweakList.Children.Add($card)
    }
    Add-PowerCard
    # Ακεραιότητα μνήμης (μόνο πληροφορίες)
    [void]$UI.TweakList.Children.Add((New-GroupHeader (T 'tg.security')))
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    $hv = "$(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled')" -eq '1'
    $st = T 'hvci.off'; if ($hv) { $st = T 'hvci.on' }
    [void]$sp.Children.Add((New-Text ((T 'hvci.t') + '  ·  ' + $st) 16 'TextBrush' 'SemiBold'))
    $d = New-Text (T 'hvci.d') 13 'SubBrush'; $d.Margin = '0,6,0,10'; [void]$sp.Children.Add($d)
    $b = New-Button (T 'hvci.btn') 'Secondary'; $b.HorizontalAlignment = 'Left'; $b.Add_Click({ Start-Process 'windowsdefender://coreisolation' }); [void]$sp.Children.Add($b)
    $card.Child = $sp; [void]$UI.TweakList.Children.Add($card)
}

# ---------- Σχέδιο ενέργειας (στην κορυφή των Ρυθμίσεων Windows) ----------
function Add-PowerCard {
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'pw.t') 16 'TextBrush' 'SemiBold'))
    $d = New-Text (T 'pw.d') 13 'SubBrush'; $d.Margin = '0,4,0,10'; [void]$sp.Children.Add($d)
    $wp = [Windows.Controls.WrapPanel]::new()
    $cur = Get-PowerPlanName
    foreach ($pl in @('balanced', 'high', 'ultimate')) {
        $rb = New-Pill (T "pw.$pl") $pl 'power' ($pl -eq $cur)
        $rb.Add_Checked({
            $which = [string]$this.Tag; $before = Get-ActivePlanGuid
            if (Set-PowerPlanCore $which) {
                $UI.TxtTweakMsg.Text = (T 'pw.ok') -f (T "pw.$which")
                if ($before -and $before -ne (Get-ActivePlanGuid)) { [void](Add-History 'power' 'hist.power' @((T "pw.$which")) @{ Type = 'power'; Guid = $before }) }
            } else { $UI.TxtTweakMsg.Text = T 'pw.fail' }
        })
        [void]$wp.Children.Add($rb)
    }
    [void]$sp.Children.Add($wp)
    $a = New-Text ('↳ ' + (T 'pw.note')) 12 'Accent2Brush'; $a.Margin = '0,2,0,0'; [void]$sp.Children.Add($a)
    $card.Child = $sp
    [void]$UI.TweakList.Children.Insert(0, $card)
}
