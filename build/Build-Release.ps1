# John's Toolkit - build the release zips (and the optional .exe)
# Run on Windows:  powershell -ExecutionPolicy Bypass -File build\Build-Release.ps1
param([switch]$NoExe)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cfg = Get-Content (Join-Path $root 'app\config.json') -Raw | ConvertFrom-Json
$ver = $cfg.version
Write-Host "John's Toolkit v$ver - build" -ForegroundColor Cyan

# 1) Syntax check of every PowerShell file
$bad = 0
foreach ($f in Get-ChildItem $root -Recurse -Include *.ps1 | Where-Object { $_.FullName -notmatch '\\dist\\' }) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { $bad++; Write-Host "  ERROR in $($f.Name): $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))" -ForegroundColor Red }
}
foreach ($j in Get-ChildItem (Join-Path $root 'lang') -Filter *.json) { try { Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null } catch { $bad++; Write-Host "  ERROR in $($j.Name)" -ForegroundColor Red } }
try { [xml](Get-Content (Join-Path $root 'app\MainWindow.xaml') -Raw -Encoding UTF8) | Out-Null } catch { $bad++; Write-Host '  ERROR in MainWindow.xaml' -ForegroundColor Red }
if ($bad -gt 0) { throw "$bad file(s) have errors. Nothing was built." }
Write-Host '  Syntax check: OK' -ForegroundColor Green

# 2) Optional .exe launcher (uses the C# compiler that ships with Windows)
$exe = Join-Path $root 'JohnsToolkit.exe'
if (-not $NoExe) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$root\assets\icon.ico" "/win32manifest:$PSScriptRoot\app.manifest" /r:System.Windows.Forms.dll "$PSScriptRoot\JohnsToolkit.cs"
    if ($LASTEXITCODE -ne 0) { throw 'The .exe could not be compiled.' }
    Write-Host "  Built: JohnsToolkit.exe" -ForegroundColor Green
}

# 3) Zips
$dist = Join-Path $root 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
$stage = Join-Path $dist 'JohnsToolkit'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($item in @('app', 'classic', 'lang', 'assets', 'Start-JohnsToolkit.bat', 'Start-Classic.bat', 'Start-Debug.bat', 'README.md', 'README.el.md', 'LICENSE', 'CHANGELOG.md')) {
    Copy-Item (Join-Path $root $item) -Destination $stage -Recurse -Force
}
$zip1 = Join-Path $dist "JohnsToolkit-v$ver.zip"
Compress-Archive -Path $stage -DestinationPath $zip1 -Force
Write-Host "  Built: $(Split-Path $zip1 -Leaf)" -ForegroundColor Green
if (-not $NoExe -and (Test-Path $exe)) {
    Copy-Item $exe -Destination $stage -Force
    $zip2 = Join-Path $dist "JohnsToolkit-v$ver-with-exe.zip"
    Compress-Archive -Path $stage -DestinationPath $zip2 -Force
    Write-Host "  Built: $(Split-Path $zip2 -Leaf)" -ForegroundColor Green
}
Remove-Item $stage -Recurse -Force

# 4) SHA256 checksums (people can verify their download)
$sums = foreach ($z in Get-ChildItem $dist -Filter *.zip) { "{0}  {1}" -f (Get-FileHash $z.FullName -Algorithm SHA256).Hash.ToLower(), $z.Name }
$sums | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "  Done: $dist" -ForegroundColor Cyan
