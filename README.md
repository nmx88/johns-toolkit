<p align="center">
  <img src="assets/icon.png" width="110" alt="John's Toolkit">
</p>

<h1 align="center">John's Toolkit</h1>
<p align="center"><b>by nmx88</b> · Cleanup, performance & repair for <b>Windows 10 / 11</b></p>
<p align="center">
  🇬🇷 Ελληνικά · 🇬🇧 English · 🇩🇪 Deutsch · 🇮🇹 Italiano · 🇫🇷 Français · 🇪🇸 Español
  <br><a href="README.el.md">Διάβασε στα ελληνικά</a>
</p>

---

A friendly, portable toolkit with a neon dark/light interface. No installation, no ads, no telemetry.
**Every change can be undone.**

## ✨ Features

| | |
|---|---|
| 🧹 **Smart cleanup** | Removes only files that are *not in use* (age filter), Windows Update leftovers, error reports, crash dumps, browser cache, shader cache, `Windows.old` and more. Scan sizes first, then decide. |
| ⚙️ **Windows settings** | 19 tweaks with on/off switches: visual effects, file extensions, faster menus, classic right-click, "End task", HAGS, Game Mode, Game DVR, mouse acceleration, ads, widgets and more. One click for all recommended, one click to restore everything. |
| 🛠️ **Repair** | Windows Update reset (for errors like `0x80070490`), DISM + SFC system repair, restore points. Error codes are explained in plain language. |
| 📦 **Apps** | Startup programs on/off, program updates with winget (risky ones explained, freeze option), removal of pre-installed apps. |
| 🛡️ **Security** | Antivirus, firewall, UAC, Remote Desktop, SMBv1, Secure Boot, TPM, VPN and remote-access check, with quick fixes and a Defender scan. |
| 🌐 **Network & VPN** | Every program connected to the internet, VPN leak check for any VPN, known malicious IPs, Defender/VirusTotal checks, live monitoring and HTML report. |
| 🧩 **Leftovers & large files** | Broken startup items, shortcuts, ghost apps and orphaned tasks (with backup and restore); the 40 largest files with "send to Recycle Bin". |
| ❤️ **Health** | Disk health, temperature and SSD wear, uptime, battery report. |
| ✨ **Neon sign** | A half-broken flickering neon "Welcome" sign on Home (can be turned off). |
| 🔄 **Automation** | Optional weekly background cleanup, desktop shortcut, update check. |
| 🖥️ **Your PC** | Full specs at a glance (CPU, RAM, GPU, disks, BIOS, TPM...) with one-click copy. VPN status for Mullvad, NordVPN, Proton, ExpressVPN, Surfshark and many more. |
| 🧑‍💻 **Developer tools** | PATH cleaner with backup, "who uses port X", DNS switcher with speed test. |
| 🩺 **Diagnostics** | Crash history explained, problem devices and drivers, Windows Update history/pending/hide with explained error codes. |
| 📤 **Uninstaller & duplicates** | Uninstall programs and remove what they leave behind; find identical files by content. |
| ⚡ **Speed test & network repair** | Download/upload/ping/jitter with history; quick network fix and full Winsock/TCP-IP reset. |
| 🐳 **WSL / Docker** | Shrink virtual disks to give back unused space; VM, Docker and database files are protected from accidental deletion. |
| 🎨 **14 themes + automatic** | Neon cyan, Synthwave, Matrix, Cyberpunk, Ocean, Crimson, Aurora, Vaporwave, Toxic, Ice, Gold, Sunset, Nightclub and Light, plus "same as Windows". |
| 🌍 **6 languages** | Greek, English, German, Italian, French, Spanish. |

## 📥 Download & run

1. Download the latest **`JohnsToolkit-vX.Y.Z.zip`** from [Releases](../../releases).
2. Right-click the zip → **Properties** → tick **Unblock** → OK.
3. Extract it anywhere (Desktop, USB stick...). It is fully portable.
4. Double-click **`Start-JohnsToolkit.bat`** (or `JohnsToolkit.exe` from the *with-exe* zip) and accept the administrator prompt.

> **Nothing happens?** Run **`Start-Debug.bat`**: it opens a visible window that shows every startup step and any error. A log is also written to `logs\startup.log`. Some security programs (e.g. Malwarebytes Exploit Protection) may block hidden PowerShell windows; add the folder as an exclusion if needed.

> **Requirements:** Windows 10 or 11 and administrator rights. Everything else (PowerShell 5.1, .NET) is already part of Windows.
> Windows 7/8 are not supported: they no longer receive security updates.

### About the .exe and antivirus warnings
`JohnsToolkit.exe` is a tiny launcher that only starts `app\Launcher.ps1`. Its source code is in [`build/JohnsToolkit.cs`](build/JohnsToolkit.cs).
Because it is not code-signed, Windows SmartScreen may show *"Unknown publisher"*, and some antivirus programs may flag it. If you prefer, use the **.bat** version: it does exactly the same thing.
Every release includes `SHA256SUMS.txt` so you can verify your download.

## 🔒 Privacy

- No telemetry, no accounts, nothing is uploaded.
- Web services are contacted **only when you use the matching feature**: [ip-api.com](https://ip-api.com) (country/company of connections, free for non-commercial use), [abuse.ch](https://abuse.ch) and Emerging Threats (malicious IP lists), [Mullvad](https://mullvad.net) (VPN check), Cloudflare speed servers (speed test), GitHub (update check). VirusTotal is only opened as a *search by file hash*; files are never uploaded.
- Your settings, logs and backups stay in the `data`, `logs` and `reports` folders next to the app.

## ↩️ Undo

- **Windows settings:** switch it off again, or press **Restore all to original**.
- **Leftover check:** every removed entry is backed up and can be restored.
- **Anything else:** create a restore point first (*Repair › Restore point*).

## 🏗️ Build from source

```powershell
powershell -ExecutionPolicy Bypass -File build\Build-Release.ps1
```
This checks every script, compiles the optional `.exe` with the C# compiler that ships with Windows, and creates the zips in `dist\`.
Pushing a tag like `v2.0.0` builds and publishes a release automatically (GitHub Actions).

## 🌍 Translations

Language files are simple JSON in [`lang/`](lang). Corrections from native speakers are very welcome: open a pull request.

## ⚠️ Disclaimer

This software is provided "as is", without warranty of any kind. You use it at your own risk. Keep backups of important files.

## 📄 License

[MIT](LICENSE) © nmx88

## For developers

```
app/Launcher.ps1      start-up: administrator rights, loads everything below
app/Core.ps1          all the work (cleanup, network, PATH, updates...) - no window code
app/gui/*.ps1         the window, one file per page, loaded in name order
app/MainWindow.xaml   window layout and styles
classic/PCTools.ps1   classic console mode (also provides shared functions)
lang/*.json           texts in 6 languages (same keys in every file)
tests/Run-Tests.ps1   automated tests
```

**Tests:** `powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1`. On Windows they use real WPF and real (read-only) system calls and save a screenshot of every page in `tests\out\screens`; on other systems a small stand-in for WPF is used. Nothing on the PC is changed. GitHub Actions runs them on every push (download the *test-results-and-screenshots* artifact from the run), and a release is only published when they pass.
