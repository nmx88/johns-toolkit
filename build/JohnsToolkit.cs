// John's Toolkit by nmx88 - small launcher (Windows 10/11)
// It only starts app\Launcher.ps1 with PowerShell. All the logic is in the open .ps1 files.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("John's Toolkit")]
[assembly: AssemblyProduct("John's Toolkit by nmx88")]
[assembly: AssemblyCompany("nmx88")]
[assembly: AssemblyDescription("Cleanup, performance and repair toolkit for Windows 10/11")]
[assembly: AssemblyCopyright("MIT License - nmx88")]
[assembly: AssemblyVersion("2.1.1.0")]
[assembly: AssemblyFileVersion("2.1.1.0")]

static class Program
{
    [STAThread]
    static int Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(Path.Combine(root, "app"), "Launcher.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("The 'app' folder was not found next to JohnsToolkit.exe.\n\nKeep JohnsToolkit.exe inside the John's Toolkit folder (do not move it alone).",
                            "John's Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        ProcessStartInfo psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = root;
        try { Process.Start(psi); }
        catch (Exception e) { MessageBox.Show(e.Message, "John's Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
        return 0;
    }
}
