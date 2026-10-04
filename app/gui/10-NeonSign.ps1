# John's Toolkit by nmx88 - Neon "Welcome" sign on the Home page
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

# ======================================================================
#  ΠΙΝΑΚΙΔΑ NEON "WELCOME" (μισοχαλασμένη, σαν ταμπέλα μπαρ)
# ======================================================================
function ConvertTo-WpfColor([string]$hex) { return [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex) }

function Get-Lighter([Windows.Media.Color]$c, [double]$k) {
    return [Windows.Media.Color]::FromRgb([byte]($c.R + (255 - $c.R) * $k), [byte]($c.G + (255 - $c.G) * $k), [byte]($c.B + (255 - $c.B) * $k))
}

function New-Glow([Windows.Media.Color]$c, [double]$blur) {
    $e = [Windows.Media.Effects.DropShadowEffect]::new(); $e.Color = $c; $e.BlurRadius = $blur; $e.ShadowDepth = 0; $e.Opacity = 1
    return $e
}

function Build-NeonSign {
    $p = $UI.NeonLetters; $p.Children.Clear()
    $pal = $App.Pal; if (-not $pal) { return }
    $acc = ConvertTo-WpfColor $pal.Accent; $acc2 = ConvertTo-WpfColor $pal.Accent2
    $core = [Windows.Media.SolidColorBrush]::new((Get-Lighter $acc 0.6)); $core.Freeze()
    $gas = [Windows.Media.SolidColorBrush]::new($acc); $gas.Opacity = 0.22; $gas.Freeze()
    $halo = [Windows.Media.SolidColorBrush]::new($acc); $halo.Opacity = 0.45; $halo.Freeze()
    $text = T 'home.sign'
    $App.SignLetters = @()
    $tf = $null
    try { $tf = [Windows.Media.Typeface]::new([Windows.Media.FontFamily]::new('Segoe Script'), [Windows.FontStyles]::Normal, [Windows.FontWeights]::Bold, [Windows.FontStretches]::Normal) } catch {}
    foreach ($ch in $text.ToCharArray()) {
        $cell = $null
        if ($tf -and "$ch".Trim()) {
            try {
                # Γράμμα σαν σωλήνας neon: περίγραμμα του γράμματος + αέριο μέσα + εξωτερική λάμψη
                $ft = [Windows.Media.FormattedText]::new([string]$ch, [Globalization.CultureInfo]::CurrentUICulture, [Windows.FlowDirection]::LeftToRight, $tf, 50.0, $core)
                $geo = $ft.BuildGeometry([Windows.Point]::new(0, 0))
                $g = [Windows.Controls.Grid]::new(); $g.Width = $ft.WidthIncludingTrailingWhitespace; $g.Height = $ft.Height
                $back = [Windows.Shapes.Path]::new(); $back.Data = $geo; $back.Stroke = $halo; $back.StrokeThickness = 6; $back.StrokeLineJoin = 'Round'
                $back.Effect = New-Glow $acc 34
                $tube = [Windows.Shapes.Path]::new(); $tube.Data = $geo; $tube.Stroke = $core; $tube.StrokeThickness = 2.2; $tube.StrokeLineJoin = 'Round'; $tube.Fill = $gas
                $tube.Effect = New-Glow $acc 12
                [void]$g.Children.Add($back); [void]$g.Children.Add($tube)
                $cell = $g
            } catch { $cell = $null }
        }
        if (-not $cell) {
            $tb = [Windows.Controls.TextBlock]::new()
            $tb.Text = [string]$ch; $tb.FontSize = 46; $tb.FontWeight = 'Bold'
            $tb.FontFamily = [Windows.Media.FontFamily]::new('Segoe Script, Segoe UI')
            $tb.Foreground = $core; $tb.Effect = New-Glow $acc 26
            $cell = $tb
        }
        [void]$p.Children.Add($cell)
        $App.SignLetters += $cell
    }
    # μικρή πινακίδα "OPEN" δίπλα
    $open = [Windows.Controls.Border]::new()
    $open.CornerRadius = 8; $open.BorderThickness = 2; $open.Padding = '9,1,9,2'; $open.Margin = '22,0,0,0'; $open.VerticalAlignment = 'Center'
    $open.BorderBrush = [Windows.Media.SolidColorBrush]::new((Get-Lighter $acc2 0.35)); $open.Effect = New-Glow $acc2 16
    $ot = [Windows.Controls.TextBlock]::new(); $ot.Text = T 'home.open'; $ot.FontSize = 15; $ot.FontWeight = 'Bold'
    $ot.Foreground = [Windows.Media.SolidColorBrush]::new((Get-Lighter $acc2 0.55))
    $open.Child = $ot
    [void]$p.Children.Add($open); $App.SignOpen = $open
    $UI.NeonSign.BorderBrush = [Windows.Media.SolidColorBrush]::new((Get-Lighter $acc2 0.35))
    $UI.NeonSign.Effect = New-Glow $acc2 24
    $idx = @(); for ($i = 1; $i -lt $App.SignLetters.Count; $i++) { if ("$($text[$i])".Trim()) { $idx += $i } }
    $App.SignBroken = -1; if ($idx.Count -gt 0) { $App.SignBroken = $idx[$App.Rand.Next($idx.Count)] }
    # "άναμμα": κάθε γράμμα ανάβει σε τυχαία στιγμή τα πρώτα ~1,5 δευτερόλεπτα
    $App.SignOff = @{}; $App.SignFrameOff = 0; $App.SignTick = 0; $App.SignBoot = @{}
    for ($i = 0; $i -lt $App.SignLetters.Count; $i++) { $App.SignBoot[$i] = $App.Rand.Next(3, 24) }
    $App.SignBuzzAt = $App.Rand.Next(180, 420)
    if (-not (Test-SignMotion)) { Set-SignStatic }
}

function Set-SignStatic {
    foreach ($l in @($App.SignLetters)) { $l.Opacity = 1 }
    if ($App.SignBroken -ge 0 -and @($App.SignLetters).Count -gt $App.SignBroken) { $App.SignLetters[$App.SignBroken].Opacity = 0.28 }
    if ($App.SignOpen) { $App.SignOpen.Opacity = 1 }
    $UI.NeonSign.Opacity = 1
}

function Test-SignMotion { return [bool]$App.Settings.flicker }

function Step-NeonSign {
    $L = @($App.SignLetters); if ($L.Count -eq 0) { return }
    $r = $App.Rand; $App.SignTick++
    $t = $App.SignTick
    # "βουητό": όλη η πινακίδα σβήνει-ανάβει γρήγορα κάθε 15-30 δευτερόλεπτα
    $buzz = ($t -ge $App.SignBuzzAt -and $t -lt $App.SignBuzzAt + 5)
    if ($t -eq $App.SignBuzzAt + 5) { $App.SignBuzzAt = $t + $r.Next(220, 450) }
    for ($i = 0; $i -lt $L.Count; $i++) {
        $boot = $App.SignBoot[$i]
        if ($t -lt $boot - 3) { $L[$i].Opacity = 0.05; continue }
        if ($t -lt $boot) { $L[$i].Opacity = @(0.05, 0.9)[$r.Next(2)]; continue }
        if ($buzz -and ($t % 2 -eq 0)) { $L[$i].Opacity = 0.15; continue }
        if ($i -eq $App.SignBroken) {
            if ($App.SignOff[$i] -gt 0) { $App.SignOff[$i]--; $L[$i].Opacity = 1 }
            elseif ($r.NextDouble() -lt 0.09) { $App.SignOff[$i] = $r.Next(1, 4); $L[$i].Opacity = 1 }
            else { $L[$i].Opacity = 0.15 + $r.NextDouble() * 0.2 }
            continue
        }
        if ($App.SignOff[$i] -gt 0) { $App.SignOff[$i]--; $L[$i].Opacity = 0.12; continue }
        $L[$i].Opacity = 1
        if ($r.NextDouble() -lt 0.006) { $App.SignOff[$i] = $r.Next(1, 3) }
    }
    if ($App.SignOpen) {
        if ($t -lt 26) { $App.SignOpen.Opacity = 0.08 }
        elseif ($buzz) { $App.SignOpen.Opacity = 0.2 }
        else { $App.SignOpen.Opacity = @(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0.25)[$r.Next(20)] }
    }
    if ($App.SignFrameOff -gt 0) { $App.SignFrameOff--; $UI.NeonSign.Opacity = 0.35 }
    elseif ($buzz) { $UI.NeonSign.Opacity = @(0.3, 1)[$t % 2] }
    else { $UI.NeonSign.Opacity = 1; if ($r.NextDouble() -lt 0.003) { $App.SignFrameOff = $r.Next(1, 3) } }
}

function Update-SignTimer {
    if (-not $SignTimer) { return }
    if ($App.Page -eq 'Home' -and (Test-SignMotion)) { if (-not $SignTimer.IsEnabled) { $SignTimer.Start() } }
    else { if ($SignTimer.IsEnabled) { $SignTimer.Stop() }; Set-SignStatic }
}
