# John's Toolkit by nmx88 - Window: create, wire up and show; safe-mode retry
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function New-MainWindow([string]$xaml) {
    # Creates the window, wires every handler and builds all pages. Does NOT show it (the tests use this too).
    try {
        $script:Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    } catch {
        Write-GuiStage ("XAML LOAD FAILED: " + $_.Exception.ToString())
        return $false
    }
    Write-GuiStage 'window created'
    $script:UI = @{}
    foreach ($m in [regex]::Matches($xaml, 'x:Name="([^"]+)"')) { $n = $m.Groups[1].Value; $o = $Win.FindName($n); if ($o) { $UI[$n] = $o } }
    $ico = Join-Path $AppRoot 'assets\icon.png'
    if (Test-Path -LiteralPath $ico) { try { $Win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $ico)) } catch {} }

    # Κάθε σφάλμα σχεδίασης καταγράφεται και δεν κλείνει το παράθυρο
    $App.UiErrors = 0
    $Win.Dispatcher.Add_UnhandledException({
        param($s, $e)
        $App.UiErrors++
        if ($App.UiErrors -le 5) { Write-GuiStage ("UI ERROR: " + $e.Exception.ToString()) }
        if (-not $App.Shown -and $App.UiErrors -ge 3) { $e.Handled = $false } else { $e.Handled = $true }
    })

    # ---------- Συνδέσεις κουμπιών ----------
    $UI.NavHome.Add_Checked({ Show-Page 'Home' })
    $UI.NavClean.Add_Checked({ Show-Page 'Clean' })
    $UI.NavTweaks.Add_Checked({ Show-Page 'Tweaks' })
    $UI.NavApps.Add_Checked({ Show-Page 'Apps' })
    $UI.NavSecurity.Add_Checked({ Show-Page 'Security' })
    $UI.NavNet.Add_Checked({ Show-Page 'Net' })
    $UI.NavHistory.Add_Checked({ Show-Page 'History' })
    $UI.NavDiag.Add_Checked({ Show-Page 'Diag' })
    $UI.NavDev.Add_Checked({ Show-Page 'Dev' })
    $UI.NavRepair.Add_Checked({ Show-Page 'Repair' })
    $UI.NavTools.Add_Checked({ Show-Page 'Tools' })
    $UI.NavSettings.Add_Checked({ Show-Page 'Settings' })

    $UI.BtnQuickClean.Add_Click({ $UI.NavClean.IsChecked = $true; Start-Clean -Defaults })
    $UI.BtnQuickTweaks.Add_Click({ $UI.NavTweaks.IsChecked = $true })
    $UI.BtnQuickRestore.Add_Click({ Start-Task 'rep.rp.t' 'New-RestorePointCore' @{} { param($TK); if ($TK.Result) { [void](Add-History 'repair' 'hist.restorepoint') } } })
    # Search (Ctrl+K)
    $UI.BtnSearch.Add_Click({ Show-Palette })
    $UI.PaletteBox.Add_TextChanged({ $App.PalSel = 0; Update-PaletteResults })
    $UI.Palette.Add_MouseLeftButtonDown({ param($src, $e) if ($e.OriginalSource -eq $UI.Palette) { Hide-Palette } })
    $Win.Add_PreviewKeyDown({
        param($src, $e)
        if ("$($e.Key)" -eq 'K' -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) { Show-Palette; $e.Handled = $true; return }
        if ($UI.Palette.Visibility -eq 'Visible') { Invoke-PaletteKey $e }
    })
    # Update
    $UI.BtnUpdateBanner.Add_Click({ Show-AppUpdateOffer })
    $UI.ChkAutoUpdate.Add_Click({ $App.Settings.autoUpdate = [bool]$UI.ChkAutoUpdate.IsChecked; Save-AppSettings $App.Settings })
    $UI.BtnQuickClassic.Add_Click({ $UI.NavNet.IsChecked = $true })
    $UI.BtnCopySpecs.Add_Click({ Copy-Specs })

    $UI.SldAge.Value = [int]$App.Settings.ageDays
    $UI.SldAge.Add_ValueChanged({ Update-AgeLabel; $App.Settings.ageDays = [int]$UI.SldAge.Value; Save-AppSettings $App.Settings })
    $UI.BtnScan.Add_Click({ Start-Scan })
    $UI.BtnClean.Add_Click({ Start-Clean })
    $UI.BtnCleanDefaults.Add_Click({ foreach ($c in Get-CleanCategories) { $App.CleanSel[$c.Id] = [bool]$c.Def }; Build-CleanList })

    $UI.BtnRec.Add_Click({
        $n = 0; $changed = @()
        foreach ($t in (Get-VisibleTweaks | Where-Object { $_.Recommended })) { if (-not (Get-TweakState $t)) { Set-Tweak $t $true; $n++; $changed += @{ Id = $t.Id; Was = $false } } }
        if ($n -gt 0) { [void](Add-History 'tweak' 'hist.rec' @($n) @{ Type = 'tweaks'; Items = $changed }) }
        Build-TweakList
        if ($n -gt 0) { $UI.TxtTweakMsg.Text = (T 'tw.rec.done') -f $n; $App.NeedsRestart = $true; $UI.RestartBanner.Visibility = 'Visible' } else { $UI.TxtTweakMsg.Text = T 'tw.rec.none' }
    })
    $UI.BtnRestoreAll.Add_Click({
        if (-not (Confirm-Box (T 'tw.restore.confirm'))) { return }
        $n = Restore-AllTweaks
        if ($n -gt 0) { [void](Add-History 'tweak' 'hist.restoreall' @($n)) }
        Build-TweakList
        if ($n -gt 0) { $UI.TxtTweakMsg.Text = T 'tw.restore.done'; $App.NeedsRestart = $true; $UI.RestartBanner.Visibility = 'Visible' } else { $UI.TxtTweakMsg.Text = T 'tw.restore.none' }
    })
    $UI.BtnExplorer.Add_Click({
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        $UI.TxtTweakMsg.Text = T 'tw.explorer.done'
    })

    $UI.ChkAuto.Add_Click({
        $on = [bool]$UI.ChkAuto.IsChecked
        $ok = Set-AutoCleanTask $on
        $UI.ChkAuto.IsChecked = Test-AutoClean
        if (-not $ok) { $UI.TxtSetMsg.Text = T 'set.auto.fail' } elseif ($on) { $UI.TxtSetMsg.Text = T 'set.auto.on' } else { $UI.TxtSetMsg.Text = T 'set.auto.off' }
    })
    $UI.ChkFlicker.Add_Click({ $App.Settings.flicker = [bool]$UI.ChkFlicker.IsChecked; Save-AppSettings $App.Settings; Update-SignTimer })
    $UI.BtnShortcut.Add_Click({ if (New-AppShortcut) { $UI.TxtSetMsg.Text = T 'set.shortcut.ok' } else { $UI.TxtSetMsg.Text = T 'set.shortcut.fail' } })
    $UI.BtnLogs.Add_Click({ New-Item -ItemType Directory -Path $CoreLogs -Force | Out-Null; Start-Process explorer.exe -ArgumentList "`"$CoreLogs`"" })
    $UI.BtnClassic.Add_Click({ Start-Classic })
    $UI.BtnGithub.Add_Click({ Start-Process ("https://github.com/" + (Get-RepoSlug)) })
    $UI.BtnUpdate.Add_Click({ Start-AppUpdateCheck })
    $UI.BtnLog.Add_Click({
        if ($UI.LogList.Visibility -eq 'Visible') { $UI.LogList.Visibility = 'Collapsed'; $UI.BtnLog.Content = T 'log.show' }
        else { $UI.LogList.Visibility = 'Visible'; $UI.BtnLog.Content = T 'log.hide' }
    })

    $Win.Add_Closing({
        param($src, $e)
        if ($App.Busy -and -not (Confirm-Box (T 'task.closebusy'))) { $e.Cancel = $true }
    })

    # ---------- Χρονόμετρο (πρόοδος εργασιών + ανανέωση αρχικής) ----------
    $script:Timer = [Windows.Threading.DispatcherTimer]::new()
    $Timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $Timer.Add_Tick({
        if ($App.MonOn -and ((Get-Date) - $App.MonLast).TotalSeconds -ge 2) { Step-LiveMonitor }
    if ($App.Task) { Update-TaskUI }
        elseif ($App.Page -eq 'Home') { Update-Dashboard }
    })

    # Το παράθυρο έρχεται πάντα μπροστά (ξεκινά από το παρασκήνιο)
    $Win.Add_ContentRendered({
        $Win.Activate() | Out-Null
        $Win.Topmost = $true; $Win.Topmost = $false
        $App.Shown = $true
        Write-GuiStage 'window shown'
        if (-not $App.SpecsLang) { $App.SpecsLang = $script:LangCode; Start-SpecsScan }
        if (Test-UpdateCheckDue) { Start-AppUpdateCheck -Quiet }   # once a day, silent, waits behind the specs scan
    })

    # ---------- Εκκίνηση ----------
    Set-Theme $App.Settings.theme
    Write-GuiStage 'theme applied'
    Set-AllTexts
    Write-GuiStage 'texts and pages built'
    Add-LogLine ("$AppName v$AppVersion · $($App.Os.Name) $($App.Os.Version) (build $($App.Os.Build))") 'step'
    if ($App.SafeMode) { Add-LogLine 'Safe display mode (no glow effects)' 'warn' }
    $script:SignTimer = [Windows.Threading.DispatcherTimer]::new()
    $SignTimer.Interval = [TimeSpan]::FromMilliseconds(70)
    $SignTimer.Add_Tick({ Step-NeonSign })
    return $true
}

function Open-MainWindow([string]$xaml) {
    $App.Shown = $false
    if (-not (New-MainWindow $xaml)) { return }
    Update-SignTimer
    $Timer.Start()
    Write-GuiStage 'showing window...'
    try { [void]$Win.ShowDialog() }
    catch { Write-GuiStage ("SHOWDIALOG ERROR: " + $_.Exception.ToString()) }
    $Timer.Stop(); $SignTimer.Stop(); $App.MonOn = $false
}

# ---------- Start: normal look first, then safe display mode ----------
function Start-JohnsToolkitWindow {
    $App.SafeMode = $false
    Open-MainWindow $xamlText
    if (-not $App.Shown) {
        Write-GuiStage 'window was not shown: retrying in safe display mode (no glow effects)'
        $App.SafeMode = $true; $App.Busy = $false; $App.Task = $null
        Open-MainWindow (Get-SafeXaml $xamlText)
        if (-not $App.Shown) {
            Write-GuiStage 'safe mode also failed'
            [void][System.Windows.MessageBox]::Show("John's Toolkit could not open its window.`n`nPlease send the file logs\startup.log to the developer.", "John's Toolkit")
        }
    }
}
