namespace WinUtil.Agent.Models;

public sealed class ScanRequest
{
    public string[] TweakIds { get; set; } = [];
}

public sealed class ApplyRequest
{
    public string[] TweakIds { get; set; } = [];
    public string? Profile { get; set; }
    public bool AllowWithoutRestorePoint { get; set; }
}

public sealed class ApplyPlan
{
    public string TransactionId { get; set; } = string.Empty;
    public string[] TweakIds { get; set; } = [];
    public string Profile { get; set; } = "safe";
    public bool AllowWithoutRestorePoint { get; set; }
}

public sealed class WorkerRequest
{
    public string Action { get; set; } = string.Empty;
    public string[] TweakIds { get; set; } = [];
    public string? TransactionId { get; set; }
    public string Profile { get; set; } = "safe";
    public bool AllowWithoutRestorePoint { get; set; }
}

public sealed class WorkerResult
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public string Output { get; set; } = string.Empty;
    public object? Data { get; set; }
}

public sealed class JobState
{
    public string Id { get; init; } = string.Empty;
    public string State { get; set; } = "Queued";
    public int Progress { get; set; }
    public string Stage { get; set; } = string.Empty;
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? TransactionId { get; set; }
    public DateTimeOffset CreatedUtc { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? FinishedUtc { get; set; }
    public object? Result { get; set; }
}

public sealed class TransactionSummary
{
    public string TransactionId { get; set; } = string.Empty;
    public DateTimeOffset CreatedUtc { get; set; }
    public DateTimeOffset? CompletedUtc { get; set; }
    public string Status { get; set; } = string.Empty;
    public bool Reversible { get; set; }
    public string[] TweakIds { get; set; } = [];
}
