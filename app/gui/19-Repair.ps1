# John's Toolkit by nmx88 - Repair and (hidden) classic tools page
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ---------- Επιδιόρθωση ----------
function Add-ActionCard($panel, [string]$tKey, [string]$dKey, [string]$aKey, $buttons) {
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T $tKey) 17 'TextBrush' 'SemiBold'))
    $d = New-Text (T $dKey) 13 'SubBrush'; $d.Margin = '0,6,0,0'; [void]$sp.Children.Add($d)
    if ($aKey) { $a = New-Text ('↳ ' + (T $aKey)) 12 'Accent2Brush'; $a.Margin = '0,6,0,0'; [void]$sp.Children.Add($a) }
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,14,0,0'
    foreach ($b in $buttons) { [void]$wp.Children.Add($b) }
    [void]$sp.Children.Add($wp)
    $card.Child = $sp; [void]$panel.Children.Add($card)
}

function Build-RepairList {
    $p = $UI.RepairList; $p.Children.Clear()
    $b1 = New-Button (T 'rep.wu.btn') 'Primary'
    $b1.Add_Click({ if (Confirm-Box (T 'rep.wu.confirm')) { Start-Task 'rep.wu.t' 'Repair-WindowsUpdate' @{} { param($TK); if ($TK.Result -and $TK.Result.Ok) { [void](Add-History 'repair' 'hist.wurepair'); Show-Info (T 'rep.wu.after') } } } })
    $b2 = New-Button (T 'rep.wu.open') 'Secondary'; $b2.Add_Click({ Start-Process 'ms-settings:windowsupdate' })
    Add-ActionCard $p 'rep.wu.t' 'rep.wu.d' 'rep.wu.a' @($b1, $b2)

    $b3 = New-Button (T 'rep.sys.btn') 'Primary'
    $b3.Add_Click({ if (Confirm-Box (T 'rep.sys.confirm')) { Start-Task 'rep.sys.t' 'Invoke-SystemRepair' @{} { param($TK); Send-Toast $AppName (T 'rep.sys.toast') } } })
    Add-ActionCard $p 'rep.sys.t' 'rep.sys.d' 'rep.sys.a' @($b3)

    $b4 = New-Button (T 'rep.rp.btn') 'Primary'
    $b4.Add_Click({ Start-Task 'rep.rp.t' 'New-RestorePointCore' @{} { param($TK); if ($TK.Result) { [void](Add-History 'repair' 'hist.restorepoint') } } })
    $b5 = New-Button (T 'rep.rp.open') 'Secondary'; $b5.Add_Click({ Start-Process 'rstrui.exe' })
    Add-ActionCard $p 'rep.rp.t' 'rep.rp.d' 'rep.rp.a' @($b4, $b5)

    $b6 = New-Button (T 'rep.ts.btn') 'Secondary'; $b6.Add_Click({ Start-Process 'ms-settings:troubleshoot' })
    Add-ActionCard $p 'rep.ts.t' 'rep.ts.d' $null @($b6)
}

# ---------- Προηγμένα εργαλεία (κλασική λειτουργία) ----------
function Start-Classic {
    $l = Join-Path $AppRoot 'classic\_loader.ps1'
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$l`""
}

function Build-ToolsList {
    $p = $UI.ToolsList; $p.Children.Clear()
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    [void]$sp.Children.Add((New-Text (T 'tools.intro.t') 17 'TextBrush' 'SemiBold'))
    $d = New-Text (T 'tools.intro.d') 13 'SubBrush'; $d.Margin = '0,6,0,12'; [void]$sp.Children.Add($d)
    $b = New-Button (T 'tools.open') 'Primary'; $b.HorizontalAlignment = 'Left'; $b.Add_Click({ Start-Classic }); [void]$sp.Children.Add($b)
    $card.Child = $sp; [void]$p.Children.Add($card)
    foreach ($k in @('net', 'leftovers', 'health', 'bigfiles')) {
        $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text (T "tools.$k.t") 15 'TextBrush' 'SemiBold'))
        $dd = New-Text (T "tools.$k.d") 12 'SubBrush'; $dd.Margin = '0,2,0,0'; [void]$s.Children.Add($dd)
        $hint = New-Text ('→ ' + (T 'tools.cardhint')) 11 'AccentBrush'; $hint.Margin = '0,4,0,0'; [void]$s.Children.Add($hint)
        $c.Child = $s; $c.Cursor = 'Hand'; $c.ToolTip = T 'tools.cardhint'
        $c.Add_MouseLeftButtonUp({ Start-Classic })
        [void]$p.Children.Add($c)
    }
}
