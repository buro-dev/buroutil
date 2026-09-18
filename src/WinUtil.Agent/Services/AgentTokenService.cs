using System.Security.Cryptography;
using System.Text;

namespace WinUtil.Agent.Services;

public sealed class AgentTokenService
{
    private readonly string _path;

    public AgentTokenService(string path) => _path = path;

    public string GetOrCreateToken()
    {
        if (File.Exists(_path))
        {
            var existing = File.ReadAllText(_path).Trim();
            if (existing.Length >= 32)
                return existing;
        }

        var bytes = RandomNumberGenerator.GetBytes(32);
        var token = Convert.ToBase64String(bytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');

        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        File.WriteAllText(_path, token, new UTF8Encoding(false));
        TryRestrictToLocalMachineUsers(_path);
        return token;
    }

    public string RotateToken()
    {
        try { File.Delete(_path); } catch { }
        return GetOrCreateToken();
    }

    private static void TryRestrictToLocalMachineUsers(string path)
    {
        // ACL hardening is also applied by install.ps1. Keeping this method
        // best-effort means the agent remains portable during development.
        try
        {
            if (!OperatingSystem.IsWindows()) return;
            using var process = new System.Diagnostics.Process();
            process.StartInfo.FileName = "icacls.exe";
            var user = System.Security.Principal.WindowsIdentity.GetCurrent().Name;
            process.StartInfo.Arguments = $"\"{path}\" /inheritance:r /grant \"{user}\":R /grant SYSTEM:F /grant Administrators:F";
            process.StartInfo.CreateNoWindow = true;
            process.StartInfo.UseShellExecute = false;
            process.Start();
            process.WaitForExit(3000);
        }
        catch
        {
            // Install script provides the authoritative ACLs.
        }
    }
}
