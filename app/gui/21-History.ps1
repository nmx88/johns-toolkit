# John's Toolkit by nmx88 - History page: every change the app made, with undo where possible
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function Build-HistoryPage {
    $p = $UI.HistoryBody; $p.Children.Clear()
    $ic = New-InfoCard (T 'hist.t') (T 'hist.d')
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = '0,12,0,0'
    $b1 = New-Button (T 'hist.openrecycle') 'Secondary'; $b1.Margin = '0,0,10,8'; $b1.Add_Click({ Start-Process 'shell:RecycleBinFolder' }); [void]$wp.Children.Add($b1)
    $b2 = New-Button (T 'hist.clear') 'Secondary'; $b2.Margin = '0,0,10,8'
    $b2.Add_Click({ if (Confirm-Box (T 'hist.clear.confirm')) { Save-ChangeHistory @(); Build-HistoryPage } }); [void]$wp.Children.Add($b2)
    [void]$ic.Panel.Children.Add($wp); [void]$p.Children.Add($ic.Card)
    $list = @(Get-ChangeHistory | Select-Object -First 100)
    if ($list.Count -eq 0) { [void]$p.Children.Add((New-Text (T 'hist.none') 14 'SubBrush')); return }
    $day = $null; $ci = Get-LangCulture
    foreach ($e in $list) {
        $when = [datetime]::Now; try { $when = [datetime]::Parse("$($e.When)", [Globalization.CultureInfo]::InvariantCulture) } catch {}
        $d = $when.ToString('D', $ci); if ($d -ne $day) { $day = $d; [void]$p.Children.Add((New-GroupHeader $d)) }
        $c = New-ItemCard; $c.Padding = '16,10'; $c.Margin = '0,0,0,6'
        $s = [Windows.Controls.StackPanel]::new()
        $titleBrush = 'TextBrush'; if ($e.Undone) { $titleBrush = 'SubBrush' }
        [void]$s.Children.Add((New-Text ("$($when.ToString('t', $ci))   $(Get-HistoryTitle $e)") 14 $titleBrush 'SemiBold'))
        $state = T "hist.k.$($e.Kind)"
        if ($e.Undone) { $state += ' · ' + (T 'hist.wasundone') }
        elseif ($e.Undo -and "$($e.Undo.Type)" -eq 'recyclebin') { $state += ' · ' + (T 'hist.inrecycle') }
        elseif (-not $e.Undo -and $e.Kind -ne 'undo') { $state += ' · ' + (T 'hist.noundo') }
        [void]$s.Children.Add((New-Text $state 12 'SubBrush'))
        $btn = $null
        if ($e.Undo -and -not $e.Undone) {
            if ("$($e.Undo.Type)" -eq 'recyclebin') { $btn = New-Button (T 'hist.openrecycle') 'Secondary'; $btn.Add_Click({ Start-Process 'shell:RecycleBinFolder' }) }
            else {
                $btn = New-Button (T 'hist.undo') 'Secondary'; $btn.Tag = $e
                $btn.Add_Click({
                    $x = $this.Tag
                    if (-not (Confirm-Box ((T 'hist.undo.confirm') -f (Get-HistoryTitle $x)))) { return }
                    Start-Task 'hist.undoing' 'Invoke-HistoryUndoCore $TK.Args.Id' @{ Id = "$($x.Id)" } {
                        param($TK); $r = $TK.Result
                        if ($r -and $r.Ok) { Show-Info ((T 'hist.undone') -f $r.Title) } else { Show-Info (T 'hist.undo.fail') }
                        # refresh every page an undo can affect (settings, startup apps, PATH, DNS, power plan)
                        Build-HistoryPage; Build-TweakList; Build-AppsBody; Build-DevBody
                    }
                })
            }
        }
        if ($btn) { $c.Child = (New-Row $s $btn) } else { $c.Child = $s }
        [void]$p.Children.Add($c)
    }
}
