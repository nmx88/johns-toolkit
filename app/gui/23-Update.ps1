# John's Toolkit by nmx88 - In-app update: check GitHub, download, verify SHA-256, replace files, restart
# Part of the window code: app\Launcher.ps1 loads every file in app\gui in name order.

function Start-AppUpdateCheck([switch]$Quiet) {
    Start-Task 'set.update.checking' 'Get-LatestRelease' @{ Quiet = [bool]$Quiet } {
        param($TK); $r = $TK.Result
        $App.Settings.lastUpdateCheck = (Get-Date).ToString('s'); Save-AppSettings $App.Settings
        if (-not $r -or -not $r.Ok) { if (-not $TK.Args.Quiet) { Show-Info (T 'set.update.fail') }; return }
        $App.Release = $r
        if ($r.Newer) {
            $UI.BtnUpdateBanner.Content = (T 'upd.app.banner') -f $r.Latest; $UI.BtnUpdateBanner.Visibility = 'Visible'
            if (-not $TK.Args.Quiet) { Show-AppUpdateOffer }
        } elseif (-not $TK.Args.Quiet) { Show-Info ((T 'set.update.latest') -f $AppVersion) }
    } -Silent:$Quiet
}
function Test-UpdateCheckDue {
    if ($App.Settings.autoUpdate -eq $false) { return $false }
    $last = $null; try { $last = [datetime]::Parse("$($App.Settings.lastUpdateCheck)", [Globalization.CultureInfo]::InvariantCulture) } catch {}
    return (-not $last -or ((Get-Date) - $last).TotalHours -ge 20)
}
function Show-AppUpdateOffer {
    $r = $App.Release; if (-not $r) { return }
    if (Test-GitCheckout) { Show-Info ((T 'upd.app.git') -f $r.Latest); return }
    $notes = ("$($r.Notes)" -replace '(?m)^#+\s*', '' -replace '\*\*', '' -replace '`', '').Trim()
    if ($notes.Length -gt 700) { $notes = $notes.Substring(0, 700) + ' ...' }
    if (-not (Confirm-Box ((T 'upd.app.confirm') -f $r.Latest, $AppVersion, $notes))) { return }
    Start-Task 'upd.app.running' 'Install-AppUpdate $TK.Args.Rel' @{ Rel = $r } {
        param($TK); $x = $TK.Result
        if (-not $x -or -not $x.Ok) { $why = 'other'; if ($x -and $x.Why) { $why = $x.Why }; Show-Info (T "upd.app.fail.$why"); return }
        [void](Add-History 'update' 'hist.update' @($x.Version))
        if (Confirm-Box ((T 'upd.app.restart') -f $x.Version)) { Start-AppUpdater $x; $Win.Close() } else { Show-Info (T 'upd.app.later') }
    }
}
