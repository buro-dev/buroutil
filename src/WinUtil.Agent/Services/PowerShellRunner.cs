using System.Diagnostics;
using System.Text;
using System.Text.Json;
using WinUtil.Agent.Models;

namespace WinUtil.Agent.Services;

public sealed class PowerShellRunner
{
    private readonly string _entryScript;
    private readonly string _logDirectory;

    public PowerShellRunner(string entryScript, string logDirectory)
    {
        _entryScript = entryScript;
        _logDirectory = logDirectory;
    }

    public async Task<WorkerResult> ExecuteLocalAsync(WorkerRequest request, CancellationToken ct)
    {
        return await RunProcessAsync(request, ct);
    }
    private async Task<WorkerResult> RunProcessAsync(WorkerRequest request, CancellationToken ct)
    {
        Directory.CreateDirectory(_logDirectory);

        var tempRoot = Path.Combine(Path.GetTempPath(), "WinUtil-NG");
        Directory.CreateDirectory(tempRoot);

        var requestPath = Path.Combine(tempRoot, $"request-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(
            requestPath,
            JsonSerializer.Serialize(request, JsonOptions.Default),
            ct);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = ResolveWindowsPowerShell(),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = AppContext.BaseDirectory
            };

            psi.ArgumentList.Add("-NoLogo");
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-NonInteractive");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("RemoteSigned");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(_entryScript);
            psi.ArgumentList.Add("-RequestFile");
            psi.ArgumentList.Add(requestPath);

            using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
            process.Start();

            var stdoutTask = process.StandardOutput.ReadToEndAsync(ct);
            var stderrTask = process.StandardError.ReadToEndAsync(ct);

            await process.WaitForExitAsync(ct);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;

            if (!string.IsNullOrWhiteSpace(stderr))
            {
                await File.AppendAllTextAsync(
                    Path.Combine(_logDirectory, "powershell.stderr.log"),
                    $"[{DateTimeOffset.UtcNow:O}] {stderr}\r\n",
                    ct);
            }

            var result = TryParseWorkerResult(stdout);
            if (result is not null)
                return result;

            return new WorkerResult
            {
                Success = process.ExitCode == 0,
                Message = process.ExitCode == 0 ? "PowerShell completed." : "PowerShell failed.",
                Output = stdout + (string.IsNullOrWhiteSpace(stderr) ? string.Empty : "\n" + stderr)
            };
        }
        finally
        {
            try { File.Delete(requestPath); } catch { }
        }
    }

    private static string ResolveWindowsPowerShell()
    {
        var systemRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (!string.IsNullOrWhiteSpace(systemRoot))
        {
            var path = Path.Combine(systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            if (File.Exists(path)) return path;
        }

        return "powershell.exe";
    }

    private static WorkerResult? TryParseWorkerResult(string stdout)
    {
        var trimmed = stdout.Trim();
        if (string.IsNullOrWhiteSpace(trimmed)) return null;

        // entry.ps1 writes a single JSON document as its final line.
        var lines = trimmed.Split('\n');
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var line = lines[i].Trim();
            if (!line.StartsWith("{")) continue;
            try
            {
                return JsonSerializer.Deserialize<WorkerResult>(line, JsonOptions.Default);
            }
            catch
            {
                // Keep searching for the JSON result.
            }
        }

        return null;
    }
}
