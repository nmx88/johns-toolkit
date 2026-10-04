# John's Toolkit by nmx88 - Settings page
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

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
    $UI.ChkFlicker.IsChecked = [bool]$App.Settings.flicker
}
