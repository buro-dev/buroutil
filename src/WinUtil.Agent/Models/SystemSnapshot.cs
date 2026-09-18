using System.Runtime.InteropServices;

namespace WinUtil.Agent.Models;

public sealed class SystemSnapshot
{
    public string OsDescription { get; init; } = string.Empty;
    public string OsVersion { get; init; } = string.Empty;
    public string Architecture { get; init; } = string.Empty;
    public string MachineName { get; init; } = string.Empty;
    public string UserName { get; init; } = string.Empty;
    public bool Is64Bit { get; init; }
    public bool IsAdministrator { get; init; }
    public bool IsWindows10Or11 { get; init; }
    public long WorkingSetMb { get; init; }
    public long FreeSystemDriveGb { get; init; }

    public static SystemSnapshot Create()
    {
        var os = Environment.OSVersion;
        var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");

        return new SystemSnapshot
        {
            OsDescription = RuntimeInformation.OSDescription,
            OsVersion = os.VersionString,
            Architecture = RuntimeInformation.OSArchitecture.ToString(),
            MachineName = Environment.MachineName,
            UserName = Environment.UserName,
            Is64Bit = Environment.Is64BitOperatingSystem,
            IsAdministrator = new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent()).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator),
            IsWindows10Or11 = RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            WorkingSetMb = Environment.WorkingSet / 1024 / 1024,
            FreeSystemDriveGb = drive.AvailableFreeSpace / 1024 / 1024 / 1024
        };
    }
}
