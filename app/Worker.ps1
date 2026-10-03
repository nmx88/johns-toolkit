# Αντικαθιστά τις "κονσολικές" συναρτήσεις της κλασικής λειτουργίας όταν τρέχουν
# στο παρασκήνιο του παραθύρου: αντί να γράφουν στην οθόνη, στέλνουν πρόοδο στο $TK.
function Write-Step([string]$t) { Add-TKLog $t 'step' }
function Write-Ok([string]$t = 'OK') { Add-TKLog $t 'ok' }
function Write-Note([string]$t) { Add-TKLog $t 'warn' }
function Write-Bad([string]$t) { Add-TKLog $t 'bad' }
function Write-Header([string]$t) { }
function Pause-Key { }
function Ask-Yes([string]$q) { return [bool]$TK.Yes }
function Show-Choice { return -1 }
function Set-TaskbarProgress { }
function Start-Progress([string]$label) { Set-TK -1 $label '' }
function Update-Progress([double]$pct = -1, [string]$detail = '', [switch]$Force) { if ($TK) { $TK.Pct = $pct; if ($detail) { $TK.Detail = $detail } } }
function Stop-Progress([string]$msg = '', [string]$color = 'Green') { if ($msg) { $l = 'ok'; if ($color -ne 'Green') { $l = 'warn' }; Add-TKLog $msg $l } }
function Write-Box($title, $rows, $width = 64) { if ($title) { Add-TKLog $title 'step' }; foreach ($r in @($rows)) { if ($r -is [array]) { Add-TKLog ("  " + $r[0]) 'info' } } }
function Write-Segs($line) { Add-TKLog ((@($line.S) | ForEach-Object { $_[0] }) -join '') 'info' }
