using System.Text.Json;
using WinUtil.Agent.Models;

namespace WinUtil.Agent.Services;

public sealed class ManifestService
{
    private readonly string _path;
    private readonly IReadOnlyList<TweakDefinition> _tweaks;

    public ManifestService(string path)
    {
        _path = path;
        var json = File.ReadAllText(path);
        var manifest = JsonSerializer.Deserialize<TweakManifest>(json, JsonOptions.Default)
            ?? throw new InvalidDataException("Invalid tweak manifest.");

        _tweaks = manifest.Tweaks.AsReadOnly();
        ValidateManifest(_tweaks);
    }

    public IReadOnlyList<TweakDefinition> GetAll() => _tweaks;

    public IReadOnlyList<TweakDefinition> ValidateIds(IEnumerable<string> ids)
    {
        var requested = ids
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (requested.Length == 0)
            throw new ArgumentException("At least one tweak id is required.");

        var map = _tweaks.ToDictionary(x => x.Id, StringComparer.OrdinalIgnoreCase);
        var missing = requested.Where(id => !map.ContainsKey(id)).ToArray();
        if (missing.Length > 0)
            throw new ArgumentException("Unknown tweak id(s): " + string.Join(", ", missing));

        return requested.Select(id => map[id]).ToArray();
    }

    private static void ValidateManifest(IReadOnlyList<TweakDefinition> tweaks)
    {
        var duplicates = tweaks
            .GroupBy(x => x.Id, StringComparer.OrdinalIgnoreCase)
            .Where(g => g.Count() > 1)
            .Select(g => g.Key)
            .ToArray();

        if (duplicates.Length > 0)
            throw new InvalidDataException("Duplicate tweak ids: " + string.Join(", ", duplicates));

        foreach (var tweak in tweaks)
        {
            if (string.IsNullOrWhiteSpace(tweak.Id) || string.IsNullOrWhiteSpace(tweak.Provider))
                throw new InvalidDataException("Each tweak requires Id and Provider.");
        }
    }

    private sealed class TweakManifest
    {
        public int SchemaVersion { get; set; }
        public List<TweakDefinition> Tweaks { get; set; } = [];
    }
}
