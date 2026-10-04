# Changelog

## v2.5.0
- New **Developer** page: **PATH cleaner** (missing/duplicate/empty entries, which python runs first, backup and restore), **port finder** (who holds port 5432/8080..., with services and end-process), **DNS switcher** (Cloudflare, Quad9, Google, AdGuard, Mullvad, automatic) with speed measurement and a VPN warning.
- New **Diagnostics** page: **crash history** (blue screens with plain explanations, unexpected shutdowns, crashing programs with GPU-driver detection), **devices & drivers** (error codes explained, graphics driver age with vendor links, old and unsigned drivers), **Windows Update** (pending, hidden, history with 13 explained error codes, hide/unhide).
- **Apps › Uninstall**: installed programs with search and sorting; after uninstalling, leftovers are found (only the install folder is pre-ticked; registry keys are backed up).
- **Cleanup › Duplicates**: identical files by content (SHA-256), oldest copy always kept, code folders skipped, never all copies of a file.
- Fixes found by the automated tests: Duplicates page crash after a failed scan; Diagnostics could retry a failed load forever; leftover names like "Notepad++ (64-bit x64)".

## v2.4.1
- Fix: the "Remove apps" tab stayed empty the first time it was opened, after removing apps, and when no unneeded apps were left.
- Fix: every list returned by a background task is now cleaned the same way (no empty "ghost" items).
- Speed test sends a User-Agent header.
- New automated test: every button, switch and tab on every page is clicked with safe stand-ins.

## v2.4.0
- **Neon sign 2.0**: real neon-tube letters (outlined glyphs with glowing gas inside and an outer halo), power-on sequence when the app opens, a half-broken letter, a periodic "buzz" and a small flickering "OPEN" sign. Fix: it did not flicker when "Fewer visual effects" was on.
- **Internet speed test** (download, upload, ping, jitter) with server location and history.
- **Network repair**: quick fix (DNS/ARP cache, renew IP, restart adapters, connection test) and full reset (Winsock, TCP/IP, proxy).
- **Large files**: choose any disk; files of virtual machines, Docker/WSL, databases and Outlook are marked as critical and need an extra confirmation.
- **Shrink WSL/Docker virtual disks** (compact vhdx) to give back unused space.
- **Startup time** of Windows in Health; new settings: turn off hibernation, Storage Sense.
- 6 new neon themes: Vaporwave, Toxic, Ice, Gold, Sunset, Nightclub (14 themes in total).
- Fixes: the Leftovers tab stayed empty; "Details" on the Network page would have crashed.

## v2.3.0
- **Neon "Welcome" sign** on Home: glowing letters in the theme colours, one half-broken letter that sputters and an occasional flicker, like a real bar sign. Can be turned off in Settings (and stays still when Windows animations are off).
- New **Network & VPN** page: every program connected to the internet, VPN/leak check (any VPN, not only Mullvad), known malicious IPs, details per program (open folder, Defender scan, VirusTotal search, trust, end program), listening ports, live monitoring with a beep on red, HTML report.
- **Cleanup** now has tabs: Temporary files · **Leftovers** (with backup and restore) · **Large files** (send to Recycle Bin).
- **Health** on the Security page: disk health, temperature and SSD wear, uptime, battery report.
- Everything now lives in the window; the classic console mode is no longer needed (still available from Settings).
- All files use Windows line endings (no more Git warnings).

## v2.2.0
- New **Apps** page: startup programs (on/off switches), program updates with winget (safe ones pre-ticked, risky ones explained, freeze/unfreeze) and removal of pre-installed apps.
- New **Security** page: antivirus, firewall, UAC, Remote Desktop, SMBv1, Secure Boot, TPM, Windows Update age, memory integrity, file extensions, VPN and remote-access programs, with one-click fixes and a quick Defender scan.
- **Power plan** (Balanced / High / Ultimate) at the top of Windows settings.
- All new screens in 6 languages.

## v2.1.1
- Display: real resolution and refresh rate read from each monitor (was wrong on PCs with two graphics cards); all monitors are listed.
- Integrated graphics are shown as "integrated (uses system RAM)" instead of a misleading memory size.
- The background PC-info scan no longer leaves "Finished" in the status bar.

## v2.1.0
- Home: full PC specifications (model, Windows, CPU, RAM, graphics card with real VRAM, display, disks, motherboard, BIOS, network, Secure Boot/TPM) with a "Copy specs" button.
- 7 neon themes: Neon cyan, Synthwave, Matrix, Cyberpunk, Ocean, Crimson, Aurora, plus Light and "Same as Windows". Each theme shows a colour preview.
- VPN detection for many providers: Mullvad, NordVPN, Proton VPN, ExpressVPN, Surfshark, PIA, CyberGhost, IPVanish, Windscribe, TunnelBear, Cloudflare WARP, OpenVPN, WireGuard, Cisco, FortiClient, GlobalProtect and VPNs set up in Windows. Tailscale/ZeroTier/Hamachi are shown as mesh networks (they do not hide your IP).
- Numbers and dates follow the app language (141.63 GB in English, 141,63 GB in Greek).
- Disk C turns yellow/red when it is almost full.
- Advanced tools cards are clickable.
- Fix: the "Start repair" icon was missing.

## v2.0.3
- Fix: the window did not open ("Unable to cast PSObject to Brush" when applying the theme).
- Only one copy of the app can run at a time.

## v2.0.2
- If the window cannot be drawn, it opens again automatically in safe display mode (without glow effects).
- Drawing errors are written to `logs\startup.log` instead of closing the window silently.

## v2.0.1
- Fix: the administrator prompt is now requested from the visible window, so it always appears in front.
- The window always comes to the front when it opens.
- New `Start-Debug.bat` and `logs\startup.log` to find startup problems.

## v2.0.0
- New window interface (WPF) with neon dark / light / automatic theme.
- 6 languages: Greek, English, German, Italian, French, Spanish (automatic from Windows, changeable in Settings).
- New name: **John's Toolkit by nmx88**. Windows 10/11 only (polite message on Windows 7/8).
- Smart cleanup: only files not used for N days, scan sizes first, new locations (Delivery Optimization, error reports, crash dumps, old logs, browser cache, shader cache, Windows.old).
- New Windows settings: show file extensions, faster menus, "Copy to / Move to", classic right-click, "This PC", "End task".
- Windows 11-only settings are hidden on Windows 10.
- New repair: Windows Update reset (for errors such as 0x80070490).
- Error codes explained in plain language.
- Portable: optional `JohnsToolkit.exe` launcher, desktop shortcut, update check from GitHub.
- The previous console version is included as "classic mode" for the advanced tools.

## v1.x (PC Tools)
- Console version: cleanup, tweaks, network/VPN diagnostics, selective updates, leftovers, security check.
