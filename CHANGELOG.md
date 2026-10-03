# Changelog

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
