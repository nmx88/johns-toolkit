# John's Toolkit by nmx88 - Helpers: theme, small UI builders, background tasks, navigation, texts
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function Write-GuiStage([string]$t) { if (Get-Command Write-Stage -ErrorAction SilentlyContinue) { Write-Stage $t } }

# Ασφαλής εκδοχή: χωρίς εφέ λάμψης (για κάρτες γραφικών/οδηγούς που δεν τα αντέχουν)
function Get-SafeXaml([string]$x) { return [regex]::Replace($x, '<(\w+)\.Effect>.*?</\1\.Effect>', '', 'Singleline') }

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
    $App.Pal = $t
    if ($UI.NeonLetters) { Build-NeonSign }
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
    if ($App.Busy) {
        # Background conveniences (PC specs, app lists) wait their turn instead of interrupting the user
        if ($Silent) { if (-not $App.Queue) { $App.Queue = [System.Collections.ArrayList]::new() }; [void]$App.Queue.Add(@{ Key = $titleKey; Work = $workText; Args = $taskArgs; OnDone = $onDone }); return }
        Show-Info (T 'task.busy'); return
    }
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
        if (-not $App.Busy -and $App.Queue -and $App.Queue.Count -gt 0) { $q = $App.Queue[0]; $App.Queue.RemoveAt(0); Start-Task $q.Key $q.Work $q.Args $q.OnDone -Silent }
    }
}

function Show-Page([string]$name) {
    $App.Page = $name
    foreach ($k in $Pages.Keys) { if ($k -eq $name) { $UI[$Pages[$k]].Visibility = 'Visible' } else { $UI[$Pages[$k]].Visibility = 'Collapsed' } }
    $UI.PageTitle.Text = T "page.$($name.ToLower()).t"
    if ($name -eq 'Home') { $UI.PageTitle.Visibility = 'Collapsed'; $UI.NeonSign.Visibility = 'Visible' } else { $UI.PageTitle.Visibility = 'Visible'; $UI.NeonSign.Visibility = 'Collapsed' }
    Update-SignTimer
    $UI.PageSub.Text = T "page.$($name.ToLower()).s"
    if ($name -eq 'Home') { Update-Dashboard -Force }
    if ($name -eq 'Security' -and $null -eq $App.Security -and -not $App.Busy) { Start-SecurityCheck }
    if ($name -eq 'Clean' -and $App.CleanTab -eq 'left') { Build-LeftoverList }
    if ($name -eq 'Diag') { Build-DiagBody }
    if ($name -eq 'Dev') { Build-DevBody }
    if ($name -eq 'Apps' -and $App.AppsTab -eq 'startup') { Build-AppsBody }
}

# Κάθε λίστα που επιστρέφει μια εργασία περνά από εδώ: χωρίς κενά στοιχεία, πάντα πίνακας.
# (Στο PowerShell το @($null) έχει 1 στοιχείο· αυτό έκανε σελίδες να μένουν κενές.)
function ConvertTo-CleanList($x) { return , @(@($x) | Where-Object { $null -ne $_ }) }

# ---------- Μικρά βοηθητικά για τις νέες σελίδες ----------
function New-Row($left, $right) {
    $g = [Windows.Controls.Grid]::new()
    foreach ($w in @('*', 'Auto')) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
    $left.Margin = '0,0,16,0'
    [Windows.Controls.Grid]::SetColumn($right, 1); $right.VerticalAlignment = 'Center'
    [void]$g.Children.Add($left); [void]$g.Children.Add($right)
    return $g
}

function New-Pill([string]$text, [string]$tag, [string]$group, [bool]$checked) {
    $rb = [Windows.Controls.RadioButton]::new(); $rb.Style = $Win.FindResource('Pill'); $rb.GroupName = $group
    $rb.Content = $text; $rb.Tag = $tag; $rb.IsChecked = $checked
    return $rb
}

function New-Dot([string]$state) {
    $map = @{ ok = 'GoodBrush'; warn = 'WarnBrush'; bad = 'BadBrush'; info = 'SubBrush' }
    $sym = '●'; if ($state -eq 'info') { $sym = '○' }
    $t = New-Text $sym 18 $map[$state]; $t.Margin = '0,0,14,0'; $t.VerticalAlignment = 'Center'
    return $t
}

# ======================================================================
#  v2.5: DEVELOPER (PATH | Θύρες | DNS), ΔΙΑΓΝΩΣΗ, ΑΠΕΓΚΑΤΑΣΤΑΣΗ, ΔΙΠΛΑ ΑΡΧΕΙΑ
# ======================================================================
function New-TextBox([string]$text, [double]$width) {
    $tb = [Windows.Controls.TextBox]::new(); $tb.Text = $text; $tb.Width = $width; $tb.FontSize = 15; $tb.Padding = '8,6'; $tb.Margin = '0,0,10,8'
    $tb.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush')
    $tb.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'TextBrush')
    $tb.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'LineBrush')
    return $tb
}

function Add-Detached($panel, $el) { if ($el.Parent) { $el.Parent.Children.Remove($el) }; [void]$panel.Children.Add($el) }

function New-InfoCard([string]$title, [string]$desc) {
    $card = New-Card; $sp = [Windows.Controls.StackPanel]::new()
    if ($title) { [void]$sp.Children.Add((New-Text $title 16 'TextBrush' 'SemiBold')) }
    if ($desc) { $d = New-Text $desc 12 'SubBrush'; $d.Margin = '0,2,0,0'; [void]$sp.Children.Add($d) }
    $card.Child = $sp
    return @{ Card = $card; Panel = $sp }
}

function New-ItemCard { $c = New-Card; $c.Padding = '18,12'; $c.Margin = '0,0,0,8'; return $c }

# ---------- Κείμενα σε όλο το παράθυρο ----------
function Set-AllTexts {
    $Win.Title = "John's Toolkit by nmx88 · Windows 10/11"
    $os = $App.Os
    $UI.TxtOs.Text = "$($os.Name) $($os.Version)".Trim()
    $UI.TxtVersion.Text = "v$AppVersion · $(T 'app.for')"
    $nav = @{ NavHome = 'nav.home'; NavClean = 'nav.clean'; NavTweaks = 'nav.tweaks'; NavApps = 'nav.apps'; NavNet = 'nav.net'; NavSecurity = 'nav.security'; NavDiag = 'nav.diag'; NavDev = 'nav.dev'; NavRepair = 'nav.repair'; NavTools = 'nav.tools'; NavSettings = 'nav.settings' }
    foreach ($k in $nav.Keys) { $UI[$k].Content = T $nav[$k] }
    $txt = @{
        TxtRestart = 'restart.banner'; GDiskT = 'home.disk'; GRamT = 'home.ram'; GCpuT = 'home.cpu'; InfVpnT = 'home.vpn'; InfUpT = 'home.uptime'
        InfFreedT = 'home.freed'; QuickT = 'home.quick'; TxtTip = 'home.tip'; TxtAgeT = 'clean.age.t'; TxtAgeD = 'clean.age.d'
        SpecT = 'spec.title'; SetFlickerT = 'set.flicker.t'; SetFlickerD = 'set.flicker.d'; SetLangT = 'set.lang'; SetThemeT = 'set.theme'; SetAutoT = 'set.auto.t'; SetAutoD = 'set.auto.d'; AboutT = 'about.t'
    }
    foreach ($k in $txt.Keys) { $UI[$k].Text = T $txt[$k] }
    $UI.AboutD.Text = (T 'about.d') -f $AppVersion
    $btn = @{
        BtnQuickClean = 'home.btn.clean'; BtnQuickTweaks = 'home.btn.tweaks'; BtnQuickRestore = 'home.btn.restore'; BtnQuickClassic = 'home.btn.net'
        BtnScan = 'clean.btn.scan'; BtnClean = 'clean.btn.clean'; BtnCleanDefaults = 'clean.btn.defaults'
        BtnRec = 'tw.btn.rec'; BtnRestoreAll = 'tw.btn.restore'; BtnExplorer = 'tw.btn.explorer'
        BtnShortcut = 'set.btn.shortcut'; BtnLogs = 'set.btn.logs'; BtnUpdate = 'set.btn.update'; BtnClassic = 'set.btn.classic'; BtnGithub = 'about.github'; BtnCopySpecs = 'spec.copy'
    }
    foreach ($k in $btn.Keys) { $UI[$k].Content = T $btn[$k] }
    if ($UI.LogList.Visibility -eq 'Visible') { $UI.BtnLog.Content = T 'log.hide' } else { $UI.BtnLog.Content = T 'log.show' }
    Update-AgeLabel
    Build-CleanList; Build-TweakList; Build-RepairList; Build-ToolsList; Build-SettingsPage; Build-SpecGrid; Build-AppsPage; Build-SecurityPage; Build-NetPage; Build-CleanTabs; Build-NeonSign; Build-DevPage; Build-DiagPage
    if ($App.SpecsLang -and $App.SpecsLang -ne $script:LangCode -and -not $App.Busy) { $App.SpecsLang = $script:LangCode; Start-SpecsScan }
    if (-not $App.Busy) { Set-Ready }
    Show-Page $App.Page
}
