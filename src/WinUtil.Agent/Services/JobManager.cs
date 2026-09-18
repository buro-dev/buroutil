using System.Text.Json;
using System.Diagnostics;
using WinUtil.Agent.Models;

namespace WinUtil.Agent.Services;

public sealed class JobManager
{
    private readonly string _jobsDirectory;
    private readonly string _transactionsDirectory;
    private readonly PowerShellRunner _runner;
    private readonly ManifestService _manifest;
    private readonly Dictionary<string, JobState> _jobs = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();

    public JobManager(
        string jobsDirectory,
        string transactionsDirectory,
        PowerShellRunner runner,
        ManifestService manifest)
    {
        _jobsDirectory = jobsDirectory;
        _transactionsDirectory = transactionsDirectory;
        _runner = runner;
        _manifest = manifest;
    }

    public async Task<WorkerResult> ScanAsync(IReadOnlyList<TweakDefinition> tweaks, CancellationToken ct)
    {
        var request = new WorkerRequest
        {
            Action = "scan",
            TweakIds = tweaks.Select(x => x.Id).ToArray()
        };
        return await _runner.ExecuteLocalAsync(request, ct);
    }

    public async Task<WorkerResult> PreviewAsync(
        IReadOnlyList<TweakDefinition> tweaks,
        string profile,
        CancellationToken ct)
    {
        var filtered = FilterProfile(tweaks, profile);
        var request = new WorkerRequest
        {
            Action = "preview",
            TweakIds = filtered.Select(x => x.Id).ToArray(),
            Profile = profile
        };
        return await _runner.ExecuteLocalAsync(request, ct);
    }

    public async Task<WorkerResult> PlanAsync(
        IReadOnlyList<TweakDefinition> tweaks, string profile, CancellationToken ct)
    {
        // Deliberately unfiltered: the PowerShell planner reports the tweaks the
        // profile refuses instead of silently dropping them.
        return await _runner.ExecuteLocalAsync(new WorkerRequest
        {
            Action = "plan",
            TweakIds = tweaks.Select(x => x.Id).ToArray(),
            Profile = profile
        }, ct);
    }

    public async Task<WorkerResult> SimpleAsync(string action, CancellationToken ct)
        => await _runner.ExecuteLocalAsync(new WorkerRequest
        {
            Action = action,
            TweakIds = Array.Empty<string>()
        }, ct);

    public async Task<JobState> StartApplyAsync(ApplyPlan plan, CancellationToken ct)
    {
        var selected = _manifest.ValidateIds(plan.TweakIds);

        // Do not silently drop profile-blocked items here. The PowerShell engine
        // is the final authority and returns BlockedByPolicy rows to the caller.
        // Plan first only to reject a request where nothing is actionable.
        var planResult = await PlanAsync(selected, plan.Profile, ct);
        if (!planResult.Success || planResult.Data is null)
            throw new InvalidOperationException(
                planResult.Message ?? "Unable to build apply plan.");

        using (JsonDocument planDoc = JsonDocument.Parse(
            JsonSerializer.Serialize(planResult.Data, JsonOptions.Default)))
        {
            var actionableCount =
                planDoc.RootElement.TryGetProperty("actionableCount", out var ac)
                    ? ac.GetInt32()
                    : 0;

            if (actionableCount == 0)
                throw new ArgumentException(
                    "No selected tweaks are permitted by the chosen profile.");
        }

        var id = Guid.NewGuid().ToString("N");
        var job = new JobState
        {
            Id = id,
            State = "Queued",
            Progress = 0,
            Stage = "Queued",
            TransactionId = plan.TransactionId
        };

        AddJob(job);

        _ = Task.Run(async () =>
        {
            try
            {
                Update(id, "Running", 10, "Preparing transaction...");
                var request = new WorkerRequest
                {
                    Action = "apply",
                    TweakIds = selected.Select(x => x.Id).ToArray(),
                    TransactionId = plan.TransactionId,
                    Profile = plan.Profile,
                    AllowWithoutRestorePoint = plan.AllowWithoutRestorePoint
                };

                // Agent is designed to run as the current administrator user.
                // The scheduled task created by install.ps1 uses Highest privileges.
                Update(id, "Running", 30, "Creating backup and restore point...");
                var result = await _runner.ExecuteLocalAsync(request, CancellationToken.None);

                Update(
                    id,
                    result.Success ? "Completed" : "Failed",
                    100,
                    result.Success ? "Completed" : "Failed",
                    result.Success,
                    result.Message,
                    result,
                    plan.TransactionId);
            }
            catch (Exception ex)
            {
                Update(id, "Failed", 100, "Exception", false, ex.Message, null, plan.TransactionId);
            }
        }, CancellationToken.None);

        await Task.CompletedTask;
        return job;
    }

    public async Task<JobState> StartRollbackAsync(string transactionId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(transactionId))
            throw new ArgumentException("Transaction id is required.");

        var id = Guid.NewGuid().ToString("N");
        var job = new JobState
        {
            Id = id,
            State = "Queued",
            Progress = 0,
            Stage = "Queued",
            TransactionId = transactionId
        };
        AddJob(job);

        _ = Task.Run(async () =>
        {
            try
            {
                Update(id, "Running", 30, "Rolling back transaction...");
                var result = await _runner.ExecuteLocalAsync(new WorkerRequest
                {
                    Action = "rollback",
                    TransactionId = transactionId
                }, CancellationToken.None);

                Update(id, result.Success ? "Completed" : "Failed", 100,
                    result.Success ? "Rollback completed" : "Rollback failed",
                    result.Success, result.Message, result, transactionId);
            }
            catch (Exception ex)
            {
                Update(id, "Failed", 100, "Exception", false, ex.Message, null, transactionId);
            }
        }, CancellationToken.None);

        await Task.CompletedTask;
        return job;
    }

    public JobState? Get(string id)
    {
        lock (_gate)
            return _jobs.TryGetValue(id, out var state) ? Clone(state) : null;
    }

    public IReadOnlyList<TransactionSummary> ListTransactions()
    {
        Directory.CreateDirectory(_transactionsDirectory);
        var result = new List<TransactionSummary>();
        foreach (var file in Directory.EnumerateFiles(_transactionsDirectory, "*.summary.json"))
        {
            try
            {
                var summary = JsonSerializer.Deserialize<TransactionSummary>(File.ReadAllText(file), JsonOptions.Default);
                if (summary is not null) result.Add(summary);
            }
            catch { }
        }
        return result.OrderByDescending(x => x.CreatedUtc).Take(100).ToArray();
    }

    private IReadOnlyList<TweakDefinition> FilterProfile(IReadOnlyList<TweakDefinition> tweaks, string profile)
    {
        var allowedRisk = profile.ToLowerInvariant() switch
        {
            "safe" => new[] { "Low" },
            "balanced" => new[] { "Low", "Medium" },
            "aggressive" => new[] { "Low", "Medium", "High" },
            _ => throw new ArgumentException("Profile must be safe, balanced or aggressive.")
        };

        return tweaks.Where(t => allowedRisk.Contains(t.Risk, StringComparer.OrdinalIgnoreCase)).ToArray();
    }

    private void AddJob(JobState job)
    {
        lock (_gate)
            _jobs[job.Id] = job;
    }

    private void Update(
        string id,
        string state,
        int progress,
        string stage,
        bool success = false,
        string message = "",
        object? result = null,
        string? transactionId = null)
    {
        lock (_gate)
        {
            if (!_jobs.TryGetValue(id, out var job)) return;
            job.State = state;
            job.Progress = progress;
            job.Stage = stage;
            job.Success = success;
            job.Message = message;
            job.Result = result;
            job.TransactionId = transactionId ?? job.TransactionId;
            if (state is "Completed" or "Failed")
                job.FinishedUtc = DateTimeOffset.UtcNow;
        }
    }

    private static JobState Clone(JobState state) => new()
    {
        Id = state.Id,
        State = state.State,
        Progress = state.Progress,
        Stage = state.Stage,
        Success = state.Success,
        Message = state.Message,
        TransactionId = state.TransactionId,
        CreatedUtc = state.CreatedUtc,
        FinishedUtc = state.FinishedUtc,
        Result = state.Result
    };
}
