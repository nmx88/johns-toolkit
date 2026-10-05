# John's Toolkit by nmx88 - Search (Ctrl+K): jump to any page, tab, setting or action by typing
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# Lower case, no accents ("Θύρα" = "θυρα"), final sigma = sigma
function ConvertTo-SearchText([string]$s) {
    $d = "$s".ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) } }
    return ($sb.ToString() -replace 'ς', 'σ')
}
function Get-EnglishText([string]$key) {
    if (-not $App.EnText) {
        $App.EnText = @{}
        try { foreach ($p in ([IO.File]::ReadAllText((Join-Path $AppRoot 'lang\en.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json).PSObject.Properties) { $App.EnText[$p.Name] = "$($p.Value)" } } catch {}
    }
    return "$($App.EnText[$key])"
}
function Get-PaletteEntries([string]$query) {
    $L = [System.Collections.ArrayList]::new()
    $add = {
        param([string]$label, [string]$subKey, [string]$enLabel, [string]$extra, [scriptblock]$run)
        $clean = ($label -replace '^[^\p{L}\p{N}]+', '').Trim()
        [void]$L.Add([pscustomobject]@{ Label = $clean; Sub = (T $subKey); Hay = (ConvertTo-SearchText "$clean $enLabel $extra"); Run = $run })
    }
    # every page
    $pages = [ordered]@{ Home = 'nav.home'; Clean = 'nav.clean'; Tweaks = 'nav.tweaks'; Apps = 'nav.apps'; Net = 'nav.net'; Security = 'nav.security'; Diag = 'nav.diag'; Dev = 'nav.dev'; Repair = 'nav.repair'; History = 'nav.history'; Settings = 'nav.settings' }
    foreach ($k in $pages.Keys) { & $add (T $pages[$k]) 'pal.sub.page' (Get-EnglishText $pages[$k]) (T "page.$($k.ToLower()).s") ([scriptblock]::Create("Show-Page '$k'")) }
    # every tab
    $tabs = @(
        @('clean.tab.temp', '$App.CleanTab = ''temp''; Show-Page ''Clean''; Build-CleanTabs'), @('clean.tab.left', '$App.CleanTab = ''left''; Show-Page ''Clean''; Build-CleanTabs'),
        @('clean.tab.big', '$App.CleanTab = ''big''; Show-Page ''Clean''; Build-CleanTabs'), @('clean.tab.dupes', '$App.CleanTab = ''dupes''; Show-Page ''Clean''; Build-CleanTabs'),
        @('apps.tab.startup', '$App.AppsTab = ''startup''; Show-Page ''Apps''; Build-AppsPage'), @('apps.tab.updates', '$App.AppsTab = ''updates''; Show-Page ''Apps''; Build-AppsPage'),
        @('apps.tab.uninstall', '$App.AppsTab = ''uninstall''; Show-Page ''Apps''; Build-AppsPage'), @('apps.tab.bloat', '$App.AppsTab = ''bloat''; Show-Page ''Apps''; Build-AppsPage'),
        @('diag.tab.crash', '$App.DiagTab = ''crash''; Show-Page ''Diag''; Build-DiagPage'), @('diag.tab.devices', '$App.DiagTab = ''devices''; Show-Page ''Diag''; Build-DiagPage'),
        @('diag.tab.wu', '$App.DiagTab = ''wu''; Show-Page ''Diag''; Build-DiagPage'),
        @('dev.tab.path', '$App.DevTab = ''path''; Show-Page ''Dev''; Build-DevPage'), @('dev.tab.ports', '$App.DevTab = ''ports''; Show-Page ''Dev''; Build-DevPage'), @('dev.tab.dns', '$App.DevTab = ''dns''; Show-Page ''Dev''; Build-DevPage')
    )
    foreach ($t in $tabs) { & $add (T $t[0]) 'pal.sub.tab' (Get-EnglishText $t[0]) '' ([scriptblock]::Create($t[1])) }
    # actions (they call the same functions as the buttons)
    $acts = @(
        @('home.btn.clean', '$UI.NavClean.IsChecked = $true; Start-Clean -Defaults'), @('home.btn.restore', 'Start-Task ''rep.rp.t'' ''New-RestorePointCore'' @{} { param($TK); if ($TK.Result) { [void](Add-History ''repair'' ''hist.restorepoint'') } }'),
        @('sp.run', 'Show-Page ''Net''; Start-SpeedTest'), @('net.analyze', 'Show-Page ''Net''; Start-NetAnalysis'),
        @('upd.scan', '$App.AppsTab = ''updates''; Show-Page ''Apps''; Build-AppsPage; Start-UpdateScan'), @('lo.scan', '$App.CleanTab = ''left''; Show-Page ''Clean''; Build-CleanTabs; Start-LeftoverScan'),
        @('pal.seccheck', 'Show-Page ''Security''; Start-SecurityCheck'), @('pal.appupdate', 'Start-AppUpdateCheck'), @('tw.btn.rec', 'Show-Page ''Tweaks''')
    )
    foreach ($a in $acts) { & $add (T $a[0]) 'pal.sub.action' (Get-EnglishText $a[0]) '' ([scriptblock]::Create($a[1])) }
    # every Windows setting (opens the Windows settings page)
    foreach ($tw in @(Get-VisibleTweaks)) { & $add (Get-TweakText $tw 'l') 'pal.sub.setting' (Get-EnglishText "tw.$($tw.Id).l") (Get-TweakText $tw 'w') ([scriptblock]::Create("Show-Page 'Tweaks'")) }
    # themes and languages
    foreach ($th in @(@($Themes.Keys) + 'auto')) { & $add ((T 'pal.theme') -f (T "theme.$th")) 'pal.sub.theme' "theme $th $(Get-EnglishText "theme.$th")" '' ([scriptblock]::Create("`$App.Settings.theme = '$th'; Save-AppSettings `$App.Settings; Set-Theme '$th'; Build-SettingsPage")) }
    foreach ($lg in $Languages.Keys) { & $add ((T 'pal.lang') -f $Languages[$lg]) 'pal.sub.lang' "language glossa $lg" '' ([scriptblock]::Create("`$App.Settings.lang = '$lg'; Save-AppSettings `$App.Settings; Set-AppLanguage '$lg'; Set-AllTexts")) }
    # "5432" -> who is using port 5432
    $n = 0
    if ([int]::TryParse("$query".Trim(), [ref]$n) -and $n -ge 1 -and $n -le 65535) {
        $e = [pscustomobject]@{ Label = ((T 'pal.port') -f $n); Sub = (T 'pal.sub.action'); Hay = ''; Run = [scriptblock]::Create("`$App.DevTab = 'ports'; Show-Page 'Dev'; Build-DevPage; Invoke-PortSearch '$n'"); Top = $true }
        [void]$L.Insert(0, $e)
    }
    return $L
}
function Show-Palette {
    $UI.Palette.Visibility = 'Visible'; $App.PalSel = 0
    $UI.PaletteBox.Text = ''
    Update-PaletteResults
    [void]$UI.PaletteBox.Focus()
}
function Hide-Palette { $UI.Palette.Visibility = 'Collapsed' }
function Update-PaletteResults {
    $q = "$($UI.PaletteBox.Text)"
    $words = @((ConvertTo-SearchText $q) -split '\s+' | Where-Object { $_ })
    $all = Get-PaletteEntries $q
    $hits = @(foreach ($e in $all) {
        if ($e.Top) { $e | Add-Member -NotePropertyName Rank -NotePropertyValue -1 -Force -PassThru; continue }
        $ok = $true; foreach ($w in $words) { if (-not $e.Hay.Contains($w)) { $ok = $false; break } }
        if (-not $ok) { continue }
        $lab = ConvertTo-SearchText $e.Label; $rank = 2
        if ($words.Count -gt 0 -and $lab.StartsWith($words[0])) { $rank = 0 } elseif ($words.Count -gt 0 -and $lab.Contains($words[0])) { $rank = 1 }
        $e | Add-Member -NotePropertyName Rank -NotePropertyValue $rank -Force -PassThru
    })
    $App.PalItems = @($hits | Sort-Object Rank | Select-Object -First 12)
    if ($App.PalSel -ge $App.PalItems.Count) { $App.PalSel = [Math]::Max(0, $App.PalItems.Count - 1) }
    $UI.PaletteList.Children.Clear()
    if ($App.PalItems.Count -eq 0) { [void]$UI.PaletteList.Children.Add((New-Text (T 'pal.none') 13 'SubBrush')); return }
    for ($i = 0; $i -lt $App.PalItems.Count; $i++) {
        $e = $App.PalItems[$i]
        $b = [Windows.Controls.Border]::new(); $b.CornerRadius = 8; $b.Padding = '12,7'; $b.Margin = '0,0,0,4'; $b.BorderThickness = 1; $b.Tag = $i; $b.Cursor = 'Hand'
        if ($i -eq $App.PalSel) { $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'ActiveBrush'); $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') }
        else { $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'PanelBrush') }
        $s = [Windows.Controls.StackPanel]::new()
        [void]$s.Children.Add((New-Text $e.Label 14 'TextBrush' 'SemiBold'))
        [void]$s.Children.Add((New-Text $e.Sub 11 'SubBrush'))
        $b.Child = $s
        $b.Add_MouseLeftButtonUp({ Invoke-PaletteEntry ([int]$this.Tag) })
        [void]$UI.PaletteList.Children.Add($b)
    }
}
function Invoke-PaletteEntry([int]$i) {
    $e = @($App.PalItems)[$i]; if (-not $e) { return }
    Hide-Palette
    & $e.Run
}
function Invoke-PaletteKey($e) {
    switch ("$($e.Key)") {
        'Escape' { Hide-Palette; $e.Handled = $true }
        'Down' { if ($App.PalSel -lt @($App.PalItems).Count - 1) { $App.PalSel++; Update-PaletteResults }; $e.Handled = $true }
        'Up' { if ($App.PalSel -gt 0) { $App.PalSel--; Update-PaletteResults }; $e.Handled = $true }
        'Return' { Invoke-PaletteEntry $App.PalSel; $e.Handled = $true }
    }
}
