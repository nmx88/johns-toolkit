# ======================================================================
#  John's Toolkit by nmx88 - Παράθυρο (WPF)
# ======================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$App = @{
    Settings = Get-AppSettings; Busy = $false; Task = $null; Marq = 0; Page = 'Home'
    CleanSel = @{}; SizeLabels = @{}; Engine = $WorkerEngine; NeedsRestart = $false; LastDash = [datetime]::MinValue
    Os = (Get-OSInfo)
}
Set-AppLanguage $App.Settings.lang

# ---------- Κείμενο παραθύρου ----------
$xamlText = [IO.File]::ReadAllText((Join-Path $AppRoot 'app\MainWindow.xaml'), [Text.Encoding]::UTF8)
function Write-GuiStage([string]$t) { if (Get-Command Write-Stage -ErrorAction SilentlyContinue) { Write-Stage $t } }
# Ασφαλής εκδοχή: χωρίς εφέ λάμψης (για κάρτες γραφικών/οδηγούς που δεν τα αντέχουν)
function Get-SafeXaml([string]$x) { return [regex]::Replace($x, '<(\w+)\.Effect>.*?</\1\.Effect>', '', 'Singleline') }

# ---------- Θέματα ----------
$Themes = [ordered]@{
    dark      = @{ Bg = '#0A0E1A'; Panel = '#0F1526'; Card = '#141C30'; Line = '#22304D'; Text = '#E8F1FF'; Sub = '#8C9DBA'; Accent = '#00E5FF'; Accent2 = '#FF2BD6'; Good = '#3DFF9A'; Warn = '#FFC53D'; Bad = '#FF4D6D'; Hover = '#1A2440'; Active = '#16233F'; OnAccent = '#06121F' }
    synthwave = @{ Bg = '#12071F'; Panel = '#190A2B'; Card = '#221037'; Line = '#3A1B5C'; Text = '#FCE8FF'; Sub = '#B79BD1'; Accent = '#FF2BD6'; Accent2 = '#FF8A00'; Good = '#3DFF9A'; Warn = '#FFD23F'; Bad = '#FF4D6D'; Hover = '#2B1545'; Active = '#2A1240'; OnAccent = '#1A0526' }
    matrix    = @{ Bg = '#030A05'; Panel = '#06120A'; Card = '#0A1A0F'; Line = '#153321'; Text = '#D8FFE4'; Sub = '#7FB894'; Accent = '#00FF6A'; Accent2 = '#A6FF00'; Good = '#00FF6A'; Warn = '#E6FF3D'; Bad = '#FF4D4D'; Hover = '#0E2416'; Active = '#0C2114'; OnAccent = '#021006' }
    cyberpunk = @{ Bg = '#0B0B12'; Panel = '#11111C'; Card = '#181826'; Line = '#2C2C44'; Text = '#FFF8D6'; Sub = '#A8A6C0'; Accent = '#FCEE0A'; Accent2 = '#00F0FF'; Good = '#3DFF9A'; Warn = '#FF9F1C'; Bad = '#FF3864'; Hover = '#1E1E30'; Active = '#22222F'; OnAccent = '#12110A' }
    ocean     = @{ Bg = '#04111C'; Panel = '#071A2A'; Card = '#0B2236'; Line = '#163B57'; Text = '#E3F6FF'; Sub = '#86A9C2'; Accent = '#00B3FF'; Accent2 = '#00FFC6'; Good = '#3DFFB0'; Warn = '#FFC53D'; Bad = '#FF5C7A'; Hover = '#0F2C45'; Active = '#0E2A40'; OnAccent = '#021422' }
    crimson   = @{ Bg = '#12060A'; Panel = '#1A0A10'; Card = '#231017'; Line = '#43202C'; Text = '#FFE8EE'; Sub = '#C49AA6'; Accent = '#FF2E63'; Accent2 = '#FF9E2C'; Good = '#3DFF9A'; Warn = '#FFD23F'; Bad = '#FF2E2E'; Hover = '#2E1520'; Active = '#2B121C'; OnAccent = '#1C0409' }
    aurora    = @{ Bg = '#070B14'; Panel = '#0B1120'; Card = '#10182B'; Line = '#22304A'; Text = '#EAF2FF'; Sub = '#93A3C4'; Accent = '#3DFFB5'; Accent2 = '#A855F7'; Good = '#3DFFB5'; Warn = '#FFD23F'; Bad = '#FF5C7A'; Hover = '#172036'; Active = '#142034'; OnAccent = '#04140E' }
    light     = @{ Bg = '#F3F6FC'; Panel = '#FFFFFF'; Card = '#FFFFFF'; Line = '#DCE4F2'; Text = '#0E1726'; Sub = '#5A6A85'; Accent = '#00A3C4'; Accent2 = '#C21BD8'; Good = '#0E9F6E'; Warn = '#B86E00'; Bad = '#E0344E'; Hover = '#EAF1FB'; Active = '#E1F6FB'; OnAccent = '#FFFFFF' }
}
# Βάζει μια τιμή στους πόρους του παραθύρου ΧΩΡΙΣ το "περιτύλιγμα" του PowerShell (PSObject),
# γιατί το WPF δεν το αναγνωρίζει (σφάλμα "Unable to cast PSObject to Brush").
function Set-WinResource([string]$key, $value) {
    $raw = $value
    if ($raw -is [System.Management.Automation.PSObject]) { $raw = $raw.PSObject.BaseObject }
    if ($Win.Resources.Contains($key)) { $Win.Resources.Remove($key) }
    $Win.Resources.Add($key, $raw)
}
function Set-Theme([string]$name) {
    $n = $name
    if ($n -eq 'auto') {
        $n = 'dark'
        if ("$(Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme')" -eq '1') { $n = 'light' }
    }
    if (-not $Themes.Contains($n)) { $n = 'dark' }
    $t = $Themes[$n]
    $map = @{ BgBrush = 'Bg'; PanelBrush = 'Panel'; CardBrush = 'Card'; LineBrush = 'Line'; TextBrush = 'Text'; SubBrush = 'Sub'; AccentBrush = 'Accent'; Accent2Brush = 'Accent2'
              GoodBrush = 'Good'; WarnBrush = 'Warn'; BadBrush = 'Bad'; HoverBrush = 'Hover'; ActiveBrush = 'Active'; OnAccentBrush = 'OnAccent' }
    foreach ($k in $map.Keys) {
        $col = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($t[$map[$k]])
        $br = [Windows.Media.SolidColorBrush]::new($col)
        $br.Freeze()
        Set-WinResource $k $br
    }
    Set-WinResource 'AccentColor' ([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($t.Accent))
    Set-WinResource 'Accent2Color' ([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($t.Accent2))
}

# ---------- Βοηθητικά για δημιουργία στοιχείων ----------
function New-Text([string]$text, [double]$size = 14, [string]$brush = 'TextBrush', [string]$weight = 'Normal') {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $text; $tb.FontSize = $size; $tb.TextWrapping = 'Wrap'; $tb.FontWeight = $weight
    $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $brush)
    return $tb
}
function New-Card { $b = [Windows.Controls.Border]::new(); $b.Style = $Win.FindResource('Card'); return $b }
function New-Button([string]$text, [string]$style = 'Secondary') {
    $b = [Windows.Controls.Button]::new(); $b.Content = $text; $b.Style = $Win.FindResource($style); return $b
}
function New-Badge([string]$text, [string]$brush) {
    $b = [Windows.Controls.Border]::new()
    $b.CornerRadius = 8; $b.Padding = '8,2'; $b.Margin = '0,0,6,4'; $b.BorderThickness = 1
    $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $brush)
    $b.Child = New-Text $text 11 $brush 'SemiBold'
    return $b
}
function New-GroupHeader([string]$text) {
    $t = New-Text $text.ToUpper() 12 'AccentBrush' 'Bold'
    $t.Margin = '4,14,0,8'
    return $t
}
function Confirm-Box([string]$text) {
    return ([System.Windows.MessageBox]::Show($Win, $text, $AppName, 'YesNo', 'Question') -eq 'Yes')
}
function Show-Info([string]$text) { [void][System.Windows.MessageBox]::Show($Win, $text, $AppName, 'OK', 'Information') }

# ---------- Μπάρα εργασιών & ιστορικό ----------
function Add-LogLine([string]$text, [string]$lvl = 'info') {
    $brush = 'TextBrush'
    switch ($lvl) { 'ok' { $brush = 'GoodBrush' } 'warn' { $brush = 'WarnBrush' } 'bad' { $brush = 'BadBrush' } 'step' { $brush = 'AccentBrush' } }
    $tb = New-Text ("$(Get-Date -Format 'HH:mm:ss')  $text") 12 $brush
    [void]$UI.LogList.Items.Add($tb)
    while ($UI.LogList.Items.Count -gt 400) { $UI.LogList.Items.RemoveAt(0) }
    $UI.LogList.ScrollIntoView($tb)
}
function Set-Ready { $UI.TaskLabel.Text = T 'task.ready'; $UI.TaskDetail.Text = ''; $UI.TaskBar.Value = 0 }

# Εργασία στο παρασκήνιο: το παράθυρο μένει ζωντανό όσο τρέχει
function Start-Task([string]$titleKey, [string]$workText, [hashtable]$taskArgs = @{}, [scriptblock]$onDone = $null, [switch]$Silent) {
    if ($App.Busy) { Show-Info (T 'task.busy'); return }
    $App.Busy = $true
    if (-not $Silent) { $UI.PagesHost.IsEnabled = $false }
    $TK = [hashtable]::Synchronized(@{ Pct = -1; Label = (T $titleKey); Detail = ''; Log = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'); Done = $false; Result = $null; Error = $null; Args = $taskArgs; Yes = $false })
    if (-not $Silent) { Add-LogLine (T $titleKey) 'step' }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $script = {
        param($TK, $EngineCode, $WorkText, $AppRoot, $ToolDir, $LangCode)
        $ErrorActionPreference = 'SilentlyContinue'
        . ([scriptblock]::Create($EngineCode))
        Set-AppLanguage $LangCode
        try { $TK.Result = & ([scriptblock]::Create($WorkText)) } catch { $TK.Error = "$($_.Exception.Message)" }
        $TK.Done = $true
    }
    [void]$ps.AddScript($script.ToString()).AddArgument($TK).AddArgument($App.Engine).AddArgument($workText).AddArgument($AppRoot).AddArgument($ToolDir).AddArgument($script:LangCode)
    $App.Task = @{ TK = $TK; PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $onDone; Start = (Get-Date); Silent = [bool]$Silent }
}

function Update-TaskUI {
    $t = $App.Task
    if (-not $t) { return }
    $TK = $t.TK
    $item = $null
    while ($TK.Log.TryDequeue([ref]$item)) { Add-LogLine $item[1] $item[0] }
    $UI.TaskLabel.Text = $TK.Label
    $el = Format-Time ((Get-Date) - $t.Start).TotalSeconds
    $d = "$el"; if ($TK.Detail) { $d += "  ·  $($TK.Detail)" }
    $p = [double]$TK.Pct
    if ($p -ge 0) {
        $UI.TaskBar.Value = [Math]::Min(100, $p)
        if ($p -ge 3 -and $p -lt 100) { $sec = ((Get-Date) - $t.Start).TotalSeconds; $d += '  ·  ' + ((T 'task.left') -f (Format-Time ($sec * (100 - $p) / $p))) }
    } else { $App.Marq = ($App.Marq + 3) % 100; $UI.TaskBar.Value = $App.Marq }
    $UI.TaskDetail.Text = $d
    if ($TK.Done) {
        try { $t.PS.EndInvoke($t.Handle) | Out-Null } catch {}
        $t.PS.Dispose(); $t.RS.Close(); $t.RS.Dispose()
        $App.Task = $null; $App.Busy = $false
        $UI.PagesHost.IsEnabled = $true
        if ($t.Silent) { Set-Ready }
        else { $UI.TaskBar.Value = 100; $UI.TaskLabel.Text = (T 'task.done') + " · $el"; $UI.TaskDetail.Text = '' }
        if ($TK.Error) { Add-LogLine $TK.Error 'bad' }
        if ($t.OnDone) { & $t.OnDone $TK }
        Update-Dashboard
    }
}

# ---------- Πλοήγηση ----------
$Pages = [ordered]@{ Home = 'PageHome'; Clean = 'PageClean'; Tweaks = 'PageTweaks'; Repair = 'PageRepair'; Tools = 'PageTools'; Settings = 'PageSettings' }
function Show-Page([string]$name) {
    $App.Page = $name
    foreach ($k in $Pages.Keys) { if ($k -eq $name) { $UI[$Pages[$k]].Visibility = 'Visible' } else { $UI[$Pages[$k]].Visibility = 'Collapsed' } }
    $UI.PageTitle.Text = T "page.$($name.ToLower()).t"
    $UI.PageSub.Text = T "page.$($name.ToLower()).s"
    if ($name -eq 'Home') { Update-Dashboard -Force }
}

# ---------- Αρχική ----------
function Update-Dashboard([switch]$Force) {
    if (-not $Force -and ((Get-Date) - $App.LastDash).TotalSeconds -lt 4) { return }
    $App.LastDash = Get-Date
    $d = Get-Dashboard
    if ($d.DiskPct -ne $null) {
        $UI.GDiskV.Text = '{0:0}%' -f $d.DiskPct; $UI.GDiskBar.Value = $d.DiskPct
        $dc = 'TextBrush'; if ($d.DiskPct -ge 95) { $dc = 'BadBrush' } elseif ($d.DiskPct -ge 85) { $dc = 'WarnBrush' }
        $UI.GDiskV.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $dc)
        $UI.GDiskD.Text = (T 'home.disk.d') -f (Format-Size $d.DiskFree), (Format-Size $d.DiskTotal)
    }
    if ($d.RamPct -ne $null) {
        $UI.GRamV.Text = '{0:0}%' -f $d.RamPct; $UI.GRamBar.Value = $d.RamPct
        $UI.GRamD.Text = (T 'home.ram.d') -f (Format-Size $d.RamUsed), (Format-Size $d.RamTotal)
    }
    if ($d.CpuPct -ne $null) { $UI.GCpuV.Text = '{0:0}%' -f $d.CpuPct; $UI.GCpuBar.Value = $d.CpuPct; $UI.GCpuD.Text = "$($d.CpuName)" }
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
    Start-Task 'spec.loading' 'Get-PcSpecs' @{} { param($TK); $App.Specs = @($TK.Result); Build-SpecGrid } -Silent
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

# ---------- Καθαρισμός ----------
function Update-AgeLabel {
    $v = [int]$UI.SldAge.Value
    if ($v -eq 0) { $UI.TxtAgeV.Text = T 'clean.age.all' } else { $UI.TxtAgeV.Text = (T 'clean.age.v') -f $v }
}
function Get-SelectedCleanIds { return @($App.CleanSel.Keys | Where-Object { $App.CleanSel[$_] }) }
function Build-CleanList {
    $UI.CleanList.Children.Clear(); $App.SizeLabels = @{}
    foreach ($c in Get-CleanCategories) {
        if (-not $App.CleanSel.ContainsKey($c.Id)) { $App.CleanSel[$c.Id] = [bool]$c.Def }
        $card = New-Card; $card.Padding = '18,12'; $card.Margin = '0,0,0,8'
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in @('Auto', '*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $chk = [Windows.Controls.CheckBox]::new(); $chk.Style = $Win.FindResource('Check'); $chk.Tag = $c.Id; $chk.IsChecked = $App.CleanSel[$c.Id]; $chk.Margin = '0,0,16,0'
        $chk.Add_Click({ $App.CleanSel[[string]$this.Tag] = [bool]$this.IsChecked })
        $sp = [Windows.Controls.StackPanel]::new()
        [void]$sp.Children.Add((New-Text (T "cat.$($c.Id).t") 15 'TextBrush' 'SemiBold'))
        $d = New-Text (T "cat.$($c.Id).d") 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$sp.Children.Add($d)
        $warnKey = "cat.$($c.Id).w"; $wt = T $warnKey
        if ($wt -ne $warnKey) { $w2 = New-Text ('⚠ ' + $wt) 12 'WarnBrush'; $w2.Margin = '0,4,0,0'; [void]$sp.Children.Add($w2) }
        $size = New-Text '—' 15 'AccentBrush' 'Bold'; $size.VerticalAlignment = 'Center'; $size.Margin = '16,0,0,0'
        $App.SizeLabels[$c.Id] = $size
        [Windows.Controls.Grid]::SetColumn($sp, 1); [Windows.Controls.Grid]::SetColumn($size, 2)
        [void]$g.Children.Add($chk); [void]$g.Children.Add($sp); [void]$g.Children.Add($size)
        $card.Child = $g
        [void]$UI.CleanList.Children.Add($card)
    }
}
function Start-Scan {
    $ids = @(Get-CleanCategories | ForEach-Object { $_.Id })
    Start-Task 'clean.scanning' 'Measure-CleanCategories $TK.Args.Ids $TK.Args.Days' @{ Ids = $ids; Days = [int]$UI.SldAge.Value } {
        param($TK)
        $res = $TK.Result; if (-not $res) { return }
        $sel = 0.0
        foreach ($k in $res.Keys) {
            if ($App.SizeLabels.ContainsKey($k)) {
                $b = [double]$res[$k].Bytes
                if ($k -eq 'dns' -or $k -eq 'component') { $App.SizeLabels[$k].Text = '' } else { $App.SizeLabels[$k].Text = Format-Size $b }
                if ($App.CleanSel[$k]) { $sel += $b }
            }
        }
        $UI.TxtCleanSum.Text = (T 'clean.selected') -f (Format-Size $sel)
    }
}
function Start-Clean([switch]$Defaults) {
    if ($Defaults) { foreach ($c in Get-CleanCategories) { $App.CleanSel[$c.Id] = [bool]$c.Def }; Build-CleanList }
    $ids = @(Get-SelectedCleanIds)
    if ($ids.Count -eq 0) { Show-Info (T 'clean.none'); return }
    $warn = @()
    foreach ($id in @('recycle', 'winold', 'browsers', 'shader', 'component')) { if ($ids -contains $id) { $warn += '• ' + (T "cat.$id.t") + ': ' + (T "cat.$id.w") } }
    $msg = (T 'clean.confirm') -f $ids.Count
    if ($warn.Count -gt 0) { $msg += "`n`n" + ($warn -join "`n") }
    if (-not (Confirm-Box $msg)) { return }
    Start-Task 'clean.running' 'Invoke-Clean $TK.Args.Ids $TK.Args.Days' @{ Ids = $ids; Days = [int]$UI.SldAge.Value } {
        param($TK)
        $r = $TK.Result; if (-not $r) { return }
        foreach ($k in $r.Results.Keys) { if ($App.SizeLabels.ContainsKey($k) -and $k -ne 'dns') { $App.SizeLabels[$k].Text = '✓ ' + (Format-Size $r.Results[$k].Freed) } }
        $UI.TxtCleanSum.Text = (T 'clean.result') -f (Format-Size $r.Total), (Format-Time $r.Seconds)
        $App.Settings.totalFreed = [double]$App.Settings.totalFreed + [double]$r.Total
        $App.Settings.lastClean = (Get-Date).ToString('s')
        Save-AppSettings $App.Settings
        if ($r.Seconds -ge 60) { Send-Toast $AppName ((T 'clean.result') -f (Format-Size $r.Total), (Format-Time $r.Seconds)) }
    }
}

# ---------- Ρυθμίσεις Windows ----------
$Win11Only = @('classicmenu', 'endtask', 'windowed')
$GroupKeys = @{ 'ΓΡΑΦΙΚΑ & ΕΦΕ' = 'tg.gfx'; 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ' = 'tg.explorer'; 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING' = 'tg.gaming'; 'ΣΥΣΤΗΜΑ' = 'tg.system'; 'ΔΙΚΤΥΟ' = 'tg.network' }
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
            Set-Tweak $tw $on
            $this.IsChecked = [bool](Get-TweakState $tw)
            $name = Get-TweakText $tw 'l'
            if ($on) { $UI.TxtTweakMsg.Text = (T 'tw.on') -f $name } else { $UI.TxtTweakMsg.Text = (T 'tw.off') -f $name }
            if ($tw.Restart -and $tw.Restart -ne 'explorer') { $App.NeedsRestart = $true; $UI.RestartBanner.Visibility = 'Visible' }
        })
        [Windows.Controls.Grid]::SetColumn($sw, 1)
        [void]$g.Children.Add($sp); [void]$g.Children.Add($sw)
        $card.Child = $g
        [void]$UI.TweakList.Children.Add($card)
    }
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
    $b1.Add_Click({ if (Confirm-Box (T 'rep.wu.confirm')) { Start-Task 'rep.wu.t' 'Repair-WindowsUpdate' @{} { param($TK); if ($TK.Result -and $TK.Result.Ok) { Show-Info (T 'rep.wu.after') } } } })
    $b2 = New-Button (T 'rep.wu.open') 'Secondary'; $b2.Add_Click({ Start-Process 'ms-settings:windowsupdate' })
    Add-ActionCard $p 'rep.wu.t' 'rep.wu.d' 'rep.wu.a' @($b1, $b2)

    $b3 = New-Button (T 'rep.sys.btn') 'Primary'
    $b3.Add_Click({ if (Confirm-Box (T 'rep.sys.confirm')) { Start-Task 'rep.sys.t' 'Invoke-SystemRepair' @{} { param($TK); Send-Toast $AppName (T 'rep.sys.toast') } } })
    Add-ActionCard $p 'rep.sys.t' 'rep.sys.d' 'rep.sys.a' @($b3)

    $b4 = New-Button (T 'rep.rp.btn') 'Primary'
    $b4.Add_Click({ Start-Task 'rep.rp.t' 'New-RestorePointCore' @{} $null })
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
    foreach ($k in @('net', 'upd', 'startup', 'bloat', 'leftovers', 'security', 'health', 'power', 'bigfiles')) {
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

# ---------- Ρυθμίσεις εφαρμογής ----------
function Build-SettingsPage {
    $UI.LangPanel.Children.Clear()
    foreach ($code in $Languages.Keys) {
        $rb = [Windows.Controls.RadioButton]::new(); $rb.Style = $Win.FindResource('Pill'); $rb.GroupName = 'lang'
        $rb.Content = $Languages[$code]; $rb.Tag = $code; $rb.IsChecked = ($code -eq $script:LangCode)
        $rb.Add_Checked({ $c = [string]$this.Tag; if ($c -ne $script:LangCode) { $App.Settings.lang = $c; Save-AppSettings $App.Settings; Set-AppLanguage $c; Set-AllTexts } })
        [void]$UI.LangPanel.Children.Add($rb)
    }
    $UI.ThemePanel.Children.Clear()
    foreach ($th in @(@($Themes.Keys) + 'auto')) {
        $rb = [Windows.Controls.RadioButton]::new(); $rb.Style = $Win.FindResource('Pill'); $rb.GroupName = 'theme'
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $sw = [Windows.Shapes.Ellipse]::new(); $sw.Width = 14; $sw.Height = 14; $sw.Margin = '0,0,8,0'; $sw.VerticalAlignment = 'Center'
        if ($th -eq 'auto') { $c1 = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString('#0A0E1A'); $c2 = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString('#F3F6FC') }
        else { $c1 = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($Themes[$th].Accent); $c2 = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($Themes[$th].Accent2) }
        $sw.Fill = [Windows.Media.LinearGradientBrush]::new($c1, $c2, 45.0)
        $tb = [Windows.Controls.TextBlock]::new(); $tb.Text = T "theme.$th"; $tb.VerticalAlignment = 'Center'
        $bind = [Windows.Data.Binding]::new('Foreground')
        $bind.RelativeSource = [Windows.Data.RelativeSource]::new([Windows.Data.RelativeSourceMode]::FindAncestor, [Windows.Controls.RadioButton], 1)
        [void]$tb.SetBinding([Windows.Controls.TextBlock]::ForegroundProperty, $bind)
        [void]$sp.Children.Add($sw); [void]$sp.Children.Add($tb)
        $rb.Content = $sp; $rb.Tag = $th; $rb.IsChecked = ($th -eq $App.Settings.theme)
        $rb.Add_Checked({ $App.Settings.theme = [string]$this.Tag; Save-AppSettings $App.Settings; Set-Theme $App.Settings.theme })
        [void]$UI.ThemePanel.Children.Add($rb)
    }
    $UI.ChkAuto.IsChecked = Test-AutoClean
}

# ---------- Κείμενα σε όλο το παράθυρο ----------
function Set-AllTexts {
    $Win.Title = "John's Toolkit by nmx88 · Windows 10/11"
    $os = $App.Os
    $UI.TxtOs.Text = "$($os.Name) $($os.Version)".Trim()
    $UI.TxtVersion.Text = "v$AppVersion · $(T 'app.for')"
    $nav = @{ NavHome = 'nav.home'; NavClean = 'nav.clean'; NavTweaks = 'nav.tweaks'; NavRepair = 'nav.repair'; NavTools = 'nav.tools'; NavSettings = 'nav.settings' }
    foreach ($k in $nav.Keys) { $UI[$k].Content = T $nav[$k] }
    $txt = @{
        TxtRestart = 'restart.banner'; GDiskT = 'home.disk'; GRamT = 'home.ram'; GCpuT = 'home.cpu'; InfVpnT = 'home.vpn'; InfUpT = 'home.uptime'
        InfFreedT = 'home.freed'; QuickT = 'home.quick'; TxtTip = 'home.tip'; TxtAgeT = 'clean.age.t'; TxtAgeD = 'clean.age.d'
        SpecT = 'spec.title'; SetLangT = 'set.lang'; SetThemeT = 'set.theme'; SetAutoT = 'set.auto.t'; SetAutoD = 'set.auto.d'; AboutT = 'about.t'
    }
    foreach ($k in $txt.Keys) { $UI[$k].Text = T $txt[$k] }
    $UI.AboutD.Text = (T 'about.d') -f $AppVersion
    $btn = @{
        BtnQuickClean = 'home.btn.clean'; BtnQuickTweaks = 'home.btn.tweaks'; BtnQuickRestore = 'home.btn.restore'; BtnQuickClassic = 'home.btn.classic'
        BtnScan = 'clean.btn.scan'; BtnClean = 'clean.btn.clean'; BtnCleanDefaults = 'clean.btn.defaults'
        BtnRec = 'tw.btn.rec'; BtnRestoreAll = 'tw.btn.restore'; BtnExplorer = 'tw.btn.explorer'
        BtnShortcut = 'set.btn.shortcut'; BtnLogs = 'set.btn.logs'; BtnUpdate = 'set.btn.update'; BtnClassic = 'set.btn.classic'; BtnGithub = 'about.github'; BtnCopySpecs = 'spec.copy'
    }
    foreach ($k in $btn.Keys) { $UI[$k].Content = T $btn[$k] }
    if ($UI.LogList.Visibility -eq 'Visible') { $UI.BtnLog.Content = T 'log.hide' } else { $UI.BtnLog.Content = T 'log.show' }
    Update-AgeLabel
    Build-CleanList; Build-TweakList; Build-RepairList; Build-ToolsList; Build-SettingsPage; Build-SpecGrid
    if ($App.SpecsLang -and $App.SpecsLang -ne $script:LangCode -and -not $App.Busy) { $App.SpecsLang = $script:LangCode; Start-SpecsScan }
    if (-not $App.Busy) { Set-Ready }
    Show-Page $App.Page
}

function Open-MainWindow([string]$xaml) {
    $App.Shown = $false
    try {
        $Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    } catch {
        Write-GuiStage ("XAML LOAD FAILED: " + $_.Exception.ToString())
        return
    }
    Write-GuiStage 'window created'
    $UI = @{}
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
    $UI.NavRepair.Add_Checked({ Show-Page 'Repair' })
    $UI.NavTools.Add_Checked({ Show-Page 'Tools' })
    $UI.NavSettings.Add_Checked({ Show-Page 'Settings' })

    $UI.BtnQuickClean.Add_Click({ $UI.NavClean.IsChecked = $true; Start-Clean -Defaults })
    $UI.BtnQuickTweaks.Add_Click({ $UI.NavTweaks.IsChecked = $true })
    $UI.BtnQuickRestore.Add_Click({ Start-Task 'rep.rp.t' 'New-RestorePointCore' @{} $null })
    $UI.BtnQuickClassic.Add_Click({ Start-Classic })
    $UI.BtnCopySpecs.Add_Click({ Copy-Specs })

    $UI.SldAge.Value = [int]$App.Settings.ageDays
    $UI.SldAge.Add_ValueChanged({ Update-AgeLabel; $App.Settings.ageDays = [int]$UI.SldAge.Value; Save-AppSettings $App.Settings })
    $UI.BtnScan.Add_Click({ Start-Scan })
    $UI.BtnClean.Add_Click({ Start-Clean })
    $UI.BtnCleanDefaults.Add_Click({ foreach ($c in Get-CleanCategories) { $App.CleanSel[$c.Id] = [bool]$c.Def }; Build-CleanList })

    $UI.BtnRec.Add_Click({
        $n = 0
        foreach ($t in (Get-VisibleTweaks | Where-Object { $_.Recommended })) { if (-not (Get-TweakState $t)) { Set-Tweak $t $true; $n++ } }
        Build-TweakList
        if ($n -gt 0) { $UI.TxtTweakMsg.Text = (T 'tw.rec.done') -f $n; $App.NeedsRestart = $true; $UI.RestartBanner.Visibility = 'Visible' } else { $UI.TxtTweakMsg.Text = T 'tw.rec.none' }
    })
    $UI.BtnRestoreAll.Add_Click({
        if (-not (Confirm-Box (T 'tw.restore.confirm'))) { return }
        $n = Restore-AllTweaks
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
    $UI.BtnShortcut.Add_Click({ if (New-AppShortcut) { $UI.TxtSetMsg.Text = T 'set.shortcut.ok' } else { $UI.TxtSetMsg.Text = T 'set.shortcut.fail' } })
    $UI.BtnLogs.Add_Click({ New-Item -ItemType Directory -Path $CoreLogs -Force | Out-Null; Start-Process explorer.exe -ArgumentList "`"$CoreLogs`"" })
    $UI.BtnClassic.Add_Click({ Start-Classic })
    $UI.BtnGithub.Add_Click({ Start-Process ("https://github.com/" + (Get-RepoSlug)) })
    $UI.BtnUpdate.Add_Click({
        Start-Task 'set.update.checking' 'Test-NewVersion' @{} {
            param($TK)
            $r = $TK.Result
            if (-not $r -or -not $r.Ok) { Show-Info (T 'set.update.fail'); return }
            if ($r.Newer) { if (Confirm-Box ((T 'set.update.new') -f $r.Latest)) { Start-Process $r.Url } }
            else { Show-Info ((T 'set.update.latest') -f $AppVersion) }
        }
    })
    $UI.BtnLog.Add_Click({
        if ($UI.LogList.Visibility -eq 'Visible') { $UI.LogList.Visibility = 'Collapsed'; $UI.BtnLog.Content = T 'log.show' }
        else { $UI.LogList.Visibility = 'Visible'; $UI.BtnLog.Content = T 'log.hide' }
    })

    $Win.Add_Closing({
        param($sender, $e)
        if ($App.Busy -and -not (Confirm-Box (T 'task.closebusy'))) { $e.Cancel = $true }
    })

    # ---------- Χρονόμετρο (πρόοδος εργασιών + ανανέωση αρχικής) ----------
    $Timer = [Windows.Threading.DispatcherTimer]::new()
    $Timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $Timer.Add_Tick({
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
    })

    # ---------- Εκκίνηση ----------
    Set-Theme $App.Settings.theme
    Write-GuiStage 'theme applied'
    Set-AllTexts
    Write-GuiStage 'texts and pages built'
    Add-LogLine ("$AppName v$AppVersion · $($App.Os.Name) $($App.Os.Version) (build $($App.Os.Build))") 'step'
    if ($App.SafeMode) { Add-LogLine 'Safe display mode (no glow effects)' 'warn' }
    $Timer.Start()
    Write-GuiStage 'showing window...'
    try { [void]$Win.ShowDialog() }
    catch { Write-GuiStage ("SHOWDIALOG ERROR: " + $_.Exception.ToString()) }
    $Timer.Stop()

}

# ---------- Άνοιγμα: πρώτα κανονικά, αλλιώς σε ασφαλή εμφάνιση ----------
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
