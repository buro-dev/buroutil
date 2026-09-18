namespace WinUtil.Agent.Models;

public sealed class TweakDefinition
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Scope { get; set; } = "System";
    public string Provider { get; set; } = string.Empty;
    public string Risk { get; set; } = "Low";
    public bool RequiresAdmin { get; set; }
    public bool Reversible { get; set; }
    public bool EnabledByDefault { get; set; }
    public bool RequiresRestorePoint { get; set; }
    public string[] Tags { get; set; } = [];
    public string[] SupportedOS { get; set; } = [];
    public Dictionary<string, object?> Settings { get; set; } = new();
}
