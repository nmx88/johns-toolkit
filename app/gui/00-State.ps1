# John's Toolkit by nmx88 - Shared state: settings, themes, pages, XAML text
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ======================================================================
#  John's Toolkit by nmx88 - Παράθυρο (WPF)
# ======================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$App = @{
    Settings = Get-AppSettings; Busy = $false; Task = $null; Marq = 0; Page = 'Home'
    CleanSel = @{}; SizeLabels = @{}; Engine = $WorkerEngine; NeedsRestart = $false; LastDash = [datetime]::MinValue
    Os = (Get-OSInfo); AppsTab = 'startup'; Updates = $null; Pins = @(); UpdSel = @{}; NoWinget = $false; Bloat = $null; BloatSel = @{}; Security = $null; StartupEntries = @()
    CleanTab = 'temp'; Leftovers = $null; LeftSel = @{}; LeftMsg = ''; BigLoc = 'user'; Big = $null
    Net = $null; NetOpen = -1; Threat = $null; MonOn = $false; MonList = $null; MonLast = [datetime]::MinValue
    DevTab = 'path'; PathSel = $null; PortBox = $null; PortNum = 0; PortRes = @(); DnsPick = $null; DnsTimes = $null
    DiagTab = 'crash'; Crash = $null; Devices = $null; Wu = $null
    Programs = $null; UnBox = $null; UnRows = $null; UnSort = 'name'; UnLeft = $null; UnLeftSel = @{}
    DupLoc = 'user'; DupMin = '10'; Dupes = $null; DupSel = @{}
    Rand = [Random]::new(); SignLetters = @(); SignBroken = -1; SignOff = @{}; SignFrameOff = 0; Pal = $null
}

Set-AppLanguage $App.Settings.lang

if ($null -eq $App.Settings.flicker) { $App.Settings.flicker = $true }

if ($null -eq $App.Settings.netGeo) { $App.Settings.netGeo = $false }

# ---------- Κείμενο παραθύρου ----------
$xamlText = [IO.File]::ReadAllText((Join-Path $AppRoot 'app\MainWindow.xaml'), [Text.Encoding]::UTF8)

# ---------- Θέματα ----------
$Themes = [ordered]@{
    dark      = @{ Bg = '#0A0E1A'; Panel = '#0F1526'; Card = '#141C30'; Line = '#22304D'; Text = '#E8F1FF'; Sub = '#8C9DBA'; Accent = '#00E5FF'; Accent2 = '#FF2BD6'; Good = '#3DFF9A'; Warn = '#FFC53D'; Bad = '#FF4D6D'; Hover = '#1A2440'; Active = '#16233F'; OnAccent = '#06121F' }
    synthwave = @{ Bg = '#12071F'; Panel = '#190A2B'; Card = '#221037'; Line = '#3A1B5C'; Text = '#FCE8FF'; Sub = '#B79BD1'; Accent = '#FF2BD6'; Accent2 = '#FF8A00'; Good = '#3DFF9A'; Warn = '#FFD23F'; Bad = '#FF4D6D'; Hover = '#2B1545'; Active = '#2A1240'; OnAccent = '#1A0526' }
    matrix    = @{ Bg = '#030A05'; Panel = '#06120A'; Card = '#0A1A0F'; Line = '#153321'; Text = '#D8FFE4'; Sub = '#7FB894'; Accent = '#00FF6A'; Accent2 = '#A6FF00'; Good = '#00FF6A'; Warn = '#E6FF3D'; Bad = '#FF4D4D'; Hover = '#0E2416'; Active = '#0C2114'; OnAccent = '#021006' }
    cyberpunk = @{ Bg = '#0B0B12'; Panel = '#11111C'; Card = '#181826'; Line = '#2C2C44'; Text = '#FFF8D6'; Sub = '#A8A6C0'; Accent = '#FCEE0A'; Accent2 = '#00F0FF'; Good = '#3DFF9A'; Warn = '#FF9F1C'; Bad = '#FF3864'; Hover = '#1E1E30'; Active = '#22222F'; OnAccent = '#12110A' }
    ocean     = @{ Bg = '#04111C'; Panel = '#071A2A'; Card = '#0B2236'; Line = '#163B57'; Text = '#E3F6FF'; Sub = '#86A9C2'; Accent = '#00B3FF'; Accent2 = '#00FFC6'; Good = '#3DFFB0'; Warn = '#FFC53D'; Bad = '#FF5C7A'; Hover = '#0F2C45'; Active = '#0E2A40'; OnAccent = '#021422' }
    crimson   = @{ Bg = '#12060A'; Panel = '#1A0A10'; Card = '#231017'; Line = '#43202C'; Text = '#FFE8EE'; Sub = '#C49AA6'; Accent = '#FF2E63'; Accent2 = '#FF9E2C'; Good = '#3DFF9A'; Warn = '#FFD23F'; Bad = '#FF2E2E'; Hover = '#2E1520'; Active = '#2B121C'; OnAccent = '#1C0409' }
    aurora    = @{ Bg = '#070B14'; Panel = '#0B1120'; Card = '#10182B'; Line = '#22304A'; Text = '#EAF2FF'; Sub = '#93A3C4'; Accent = '#3DFFB5'; Accent2 = '#A855F7'; Good = '#3DFFB5'; Warn = '#FFD23F'; Bad = '#FF5C7A'; Hover = '#172036'; Active = '#142034'; OnAccent = '#04140E' }
    vaporwave = @{ Bg = '#140B24'; Panel = '#1B1030'; Card = '#24163D'; Line = '#3E2A63'; Text = '#FFF0FB'; Sub = '#BBA6D6'; Accent = '#FF71CE'; Accent2 = '#01CDFE'; Good = '#05FFA1'; Warn = '#FFFB96'; Bad = '#FF4F79'; Hover = '#2D1C4B'; Active = '#2A1946'; OnAccent = '#1A0B26' }
    toxic     = @{ Bg = '#0A0B06'; Panel = '#11130A'; Card = '#181B0E'; Line = '#2E3418'; Text = '#F3FFD6'; Sub = '#A3B07A'; Accent = '#B6FF00'; Accent2 = '#B026FF'; Good = '#B6FF00'; Warn = '#FFD23F'; Bad = '#FF3D57'; Hover = '#1F2312'; Active = '#1D2111'; OnAccent = '#0D1200' }
    ice       = @{ Bg = '#06101A'; Panel = '#0A1724'; Card = '#0F1F30'; Line = '#1D3550'; Text = '#EAF8FF'; Sub = '#8FB2CC'; Accent = '#9BE7FF'; Accent2 = '#5B8CFF'; Good = '#5CFFC8'; Warn = '#FFD66B'; Bad = '#FF6B8B'; Hover = '#142A40'; Active = '#13283C'; OnAccent = '#05121C' }
    gold      = @{ Bg = '#100C04'; Panel = '#171107'; Card = '#20180B'; Line = '#3D2E14'; Text = '#FFF6E0'; Sub = '#C2AD82'; Accent = '#FFD23F'; Accent2 = '#FF7A1A'; Good = '#7CFF6B'; Warn = '#FFB020'; Bad = '#FF4D4D'; Hover = '#2A2010'; Active = '#271E0F'; OnAccent = '#1A1200' }
    sunset    = @{ Bg = '#14070D'; Panel = '#1C0A13'; Card = '#26101B'; Line = '#46203A'; Text = '#FFEDF2'; Sub = '#C99AAE'; Accent = '#FF6B35'; Accent2 = '#FF2E97'; Good = '#4DFFB4'; Warn = '#FFD23F'; Bad = '#FF3B3B'; Hover = '#331626'; Active = '#2F1423'; OnAccent = '#1F0710' }
    nightclub = @{ Bg = '#08061A'; Panel = '#0D0A26'; Card = '#140F33'; Line = '#2A2058'; Text = '#F1EDFF'; Sub = '#A39BD1'; Accent = '#8B5CFF'; Accent2 = '#FF2BD6'; Good = '#3DFFB5'; Warn = '#FFD23F'; Bad = '#FF4D6D'; Hover = '#1C1645'; Active = '#1A1440'; OnAccent = '#0A0620' }
    light     = @{ Bg = '#F3F6FC'; Panel = '#FFFFFF'; Card = '#FFFFFF'; Line = '#DCE4F2'; Text = '#0E1726'; Sub = '#5A6A85'; Accent = '#00A3C4'; Accent2 = '#C21BD8'; Good = '#0E9F6E'; Warn = '#B86E00'; Bad = '#E0344E'; Hover = '#EAF1FB'; Active = '#E1F6FB'; OnAccent = '#FFFFFF' }
}

# ---------- Πλοήγηση ----------
$Pages = [ordered]@{ Home = 'PageHome'; Clean = 'PageClean'; Tweaks = 'PageTweaks'; Apps = 'PageApps'; Net = 'PageNet'; Security = 'PageSecurity'; Diag = 'PageDiag'; Dev = 'PageDev'; Repair = 'PageRepair'; Tools = 'PageTools'; Settings = 'PageSettings' }

# ---------- Ρυθμίσεις Windows ----------
$Win11Only = @('classicmenu', 'endtask', 'windowed')

$GroupKeys = @{ 'ΓΡΑΦΙΚΑ & ΕΦΕ' = 'tg.gfx'; 'ΕΞΕΡΕΥΝΗΣΗ & ΔΕΞΙ ΚΛΙΚ' = 'tg.explorer'; 'ΚΑΡΤΑ ΓΡΑΦΙΚΩΝ & GAMING' = 'tg.gaming'; 'ΣΥΣΤΗΜΑ' = 'tg.system'; 'ΔΙΚΤΥΟ' = 'tg.network' }
