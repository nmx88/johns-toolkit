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
    return $L
}
function Get-PortSuggestion([string]$query) {
    $n = 0
    if (-not [int]::TryParse("$query".Trim(), [ref]$n) -or $n -lt 1 -or $n -gt 65535) { return $null }
    return [pscustomobject]@{ Label = ((T 'pal.port') -f $n); Sub = (T 'pal.sub.action'); Hay = ''; Run = [scriptblock]::Create("`$App.DevTab = 'ports'; Show-Page 'Dev'; Build-DevPage; Invoke-PortSearch '$n'") }
}
# Score of one entry for the typed words (0 = no match). Start of a word in the title counts most;
# a piece inside another word ("παράθυρα" for "θυρα") counts least; "θυρα" also matches "θυρες" (same stem).
function Get-PaletteScore($e, [string[]]$words) {
    if ($words.Count -eq 0) { return 1 }
    $lab = ConvertTo-SearchText $e.Label
    $labWords = @($lab -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
    $hayWords = @($e.Hay -split '[^\p{L}\p{N}]+' | Where-Object { $_ })
    $total = 0.0
    foreach ($w in $words) {
        $stem = $w; if ($w.Length -ge 4) { $stem = $w.Substring(0, $w.Length - 1) }
        $sc = 0.0
        if (@($labWords | Where-Object { $_.StartsWith($w) }).Count) { $sc = 10 }
        elseif (@($labWords | Where-Object { $_.StartsWith($stem) }).Count) { $sc = 8 }
        elseif (@($hayWords | Where-Object { $_.StartsWith($w) }).Count) { $sc = 5 }
        elseif (@($hayWords | Where-Object { $_.StartsWith($stem) }).Count) { $sc = 4 }
        elseif ($lab.Contains($w)) { $sc = 2 }
        elseif ($e.Hay.Contains($w)) { $sc = 1 }
        if ($sc -eq 0) { return 0 }
        $total += $sc
    }
    return $total
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
    $scored = foreach ($e in @(Get-PaletteEntries $q)) { $sc = Get-PaletteScore $e $words; if ($sc -gt 0) { [pscustomobject]@{ E = $e; S = $sc; L = $e.Label.Length } } }
    $items = @(@($scored) | Sort-Object @{ e = 'S'; Descending = $true }, @{ e = 'L'; Descending = $false } | Select-Object -First 12 | ForEach-Object { $_.E })
    $port = Get-PortSuggestion $q
    if ($port) { $items = @($port) + @($items | Select-Object -First 11) }
    $App.PalItems = $items
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
