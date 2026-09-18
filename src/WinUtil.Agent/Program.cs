using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using WinUtil.Agent.Models;
using WinUtil.Agent.Services;

var argsMap = ParseArgs(args);

var dataRoot = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
    "WinUtil");

Directory.CreateDirectory(dataRoot);

var tokenPath = Path.Combine(dataRoot, "agent.token");
var jobsPath = Path.Combine(dataRoot, "Jobs");
var transactionsPath = Path.Combine(dataRoot, "Transactions");
var logsPath = Path.Combine(dataRoot, "Logs");

foreach (var path in new[] { jobsPath, transactionsPath, logsPath })
    Directory.CreateDirectory(path);

var tokenService = new AgentTokenService(tokenPath);
var token = tokenService.GetOrCreateToken();

if (argsMap.ContainsKey("--rotate-token"))
{
    Console.WriteLine(tokenService.RotateToken());
    return;
}

if (argsMap.ContainsKey("--show-token"))
{
    Console.WriteLine(token);
    return;
}

var manifestPath = Path.Combine(AppContext.BaseDirectory, "Config", "Tweaks.json");
var powershellEntry = Path.Combine(AppContext.BaseDirectory, "PowerShell", "entry.ps1");

if (!File.Exists(manifestPath))
    throw new FileNotFoundException("Tweak manifest not found.", manifestPath);

if (!File.Exists(powershellEntry))
    throw new FileNotFoundException("PowerShell entry script not found.", powershellEntry);

var options = new AgentOptions();
var appSettingsPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
if (File.Exists(appSettingsPath))
{
    try
    {
        var json = await File.ReadAllTextAsync(appSettingsPath);
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.TryGetProperty("Agent", out var agent))
        {
            if (agent.TryGetProperty("Name", out var name)) options.Name = name.GetString() ?? options.Name;
            if (agent.TryGetProperty("Version", out var version)) options.Version = version.GetString() ?? options.Version;
            if (agent.TryGetProperty("BindAddress", out var bind)) options.BindAddress = bind.GetString() ?? options.BindAddress;
            if (agent.TryGetProperty("Port", out var port)) options.Port = port.GetInt32();
            if (agent.TryGetProperty("AllowedOrigins", out var origins) && origins.ValueKind == JsonValueKind.Array)
                options.AllowedOrigins = origins.EnumerateArray().Select(x => x.GetString()).Where(x => !string.IsNullOrWhiteSpace(x)).Cast<string>().ToArray();
        }
    }
    catch (Exception ex)
    {
        File.AppendAllText(Path.Combine(logsPath, "agent-startup.log"), $"Config warning: {ex}\r\n");
    }
}

var manifest = new ManifestService(manifestPath);
var runner = new PowerShellRunner(powershellEntry, logsPath);
var jobManager = new JobManager(jobsPath, transactionsPath, runner, manifest);
var auth = new AuthService(token, options.AllowedOrigins);

if (argsMap.ContainsKey("--maintenance"))
{
    var maintenance = await runner.ExecuteLocalAsync(new WorkerRequest
    {
        Action = "maintenance",
        TweakIds = Array.Empty<string>()
    }, CancellationToken.None);
    Console.WriteLine(JsonSerializer.Serialize(maintenance, JsonOptions.Default));
    return;
}

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://{options.BindAddress}:{options.Port}");

builder.Services.AddCors(cors =>
{
    cors.AddPolicy("StaticSite", policy =>
    {
        policy.WithOrigins(options.AllowedOrigins)
              .WithMethods("GET", "POST", "OPTIONS")
              .WithHeaders("Content-Type", "X-WinUtil-Token")
              .SetPreflightMaxAge(TimeSpan.FromMinutes(30));
    });
});

var app = builder.Build();
app.UseCors("StaticSite");

app.Use(async (context, next) =>
{
    var path = context.Request.Path.Value ?? string.Empty;

    if (!path.StartsWith("/api/v1", StringComparison.OrdinalIgnoreCase))
    {
        await next();
        return;
    }

    if (HttpMethods.IsOptions(context.Request.Method) ||
        path.Equals("/api/v1/health", StringComparison.OrdinalIgnoreCase))
    {
        await next();
        return;
    }

    if (!AuthService.IsHostAllowed(context.Request.Host.Value, options.Port))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsJsonAsync(new { error = "Host header is not a loopback address." });
        return;
    }

    var originRequired = !HttpMethods.IsGet(context.Request.Method);

    if (!auth.IsOriginAllowed(context.Request.Headers.Origin.ToString(), originRequired))
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        await context.Response.WriteAsJsonAsync(new { error = "Origin missing or not allowed." });
        return;
    }

    if (!auth.IsAuthorized(context.Request.Headers["X-WinUtil-Token"].ToString()))
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(new { error = "Invalid or missing agent token." });
        return;
    }

    await next();
});

app.MapGet("/api/v1/health", () => Results.Ok(new
{
    name = options.Name,
    version = options.Version,
    protocol = 1,
    status = "ok",
    utc = DateTimeOffset.UtcNow
}));

app.MapGet("/api/v1/status", () => Results.Ok(SystemSnapshot.Create()));

app.MapGet("/api/v1/tweaks", () => Results.Ok(manifest.GetAll()));

app.MapPost("/api/v1/scan", async (ScanRequest request, CancellationToken ct) =>
{
    var selected = manifest.ValidateIds(request.TweakIds);
    var result = await jobManager.ScanAsync(selected, ct);
    return Results.Ok(result);
});

app.MapPost("/api/v1/preview", async (ApplyRequest request, CancellationToken ct) =>
{
    var selected = manifest.ValidateIds(request.TweakIds);
    var result = await jobManager.PreviewAsync(selected, request.Profile ?? "safe", ct);
    return Results.Ok(result);
});

app.MapPost("/api/v1/plan", async (ApplyRequest request, CancellationToken ct) =>
{
    var selected = manifest.ValidateIds(request.TweakIds);
    var result = await jobManager.PlanAsync(selected, request.Profile ?? "safe", ct);
    return Results.Ok(result);
});

app.MapGet("/api/v1/providers", async (CancellationToken ct) =>
    Results.Ok(await jobManager.SimpleAsync("providers", ct)));

app.MapGet("/api/v1/audit", async (CancellationToken ct) =>
    Results.Ok(await jobManager.SimpleAsync("audit", ct)));

app.MapPost("/api/v1/apply", async (ApplyRequest request, CancellationToken ct) =>
{
    if (request.AllowWithoutRestorePoint)
    {
        return Results.BadRequest(new
        {
            error = "allowWithoutRestorePoint is not permitted through the browser API."
        });
    }

    var selected = manifest.ValidateIds(request.TweakIds);
    var plan = new ApplyPlan
    {
        TransactionId = Guid.NewGuid().ToString("N"),
        TweakIds = selected.Select(t => t.Id).ToArray(),
        Profile = request.Profile ?? "safe",
        AllowWithoutRestorePoint = request.AllowWithoutRestorePoint
    };

    var job = await jobManager.StartApplyAsync(plan, ct);
    return Results.Accepted($"/api/v1/jobs/{job.Id}", job);
});

app.MapGet("/api/v1/jobs/{id}", (string id) =>
{
    var job = jobManager.Get(id);
    return job is null ? Results.NotFound() : Results.Ok(job);
});

app.MapPost("/api/v1/rollback/{transactionId}", async (string transactionId, CancellationToken ct) =>
{
    var job = await jobManager.StartRollbackAsync(transactionId, ct);
    return Results.Accepted($"/api/v1/jobs/{job.Id}", job);
});

app.MapGet("/api/v1/transactions", () => Results.Ok(jobManager.ListTransactions()));

app.MapPost("/api/v1/task/install", async (CancellationToken ct) =>
{
    var result = await runner.ExecuteLocalAsync(new WorkerRequest
    {
        Action = "install-tasks",
        TweakIds = Array.Empty<string>(),
        TransactionId = null
    }, ct);
    return Results.Ok(result);
});

app.MapPost("/api/v1/task/remove", async (CancellationToken ct) =>
{
    var result = await runner.ExecuteLocalAsync(new WorkerRequest
    {
        Action = "remove-tasks",
        TweakIds = Array.Empty<string>(),
        TransactionId = null
    }, ct);
    return Results.Ok(result);
});

Console.WriteLine($"{options.Name} {options.Version}");
Console.WriteLine($"Listening: http://{options.BindAddress}:{options.Port}");
Console.WriteLine("Use --show-token to display the local site token.");

await app.RunAsync();

static Dictionary<string, string?> ParseArgs(string[] args)
{
    var dict = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
    for (var i = 0; i < args.Length; i++)
    {
        var arg = args[i];
        if (!arg.StartsWith("--", StringComparison.Ordinal))
            continue;

        if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
            dict[arg] = args[++i];
        else
            dict[arg] = null;
    }
    return dict;
}
