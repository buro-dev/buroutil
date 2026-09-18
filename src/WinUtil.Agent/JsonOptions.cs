using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinUtil.Agent;

public static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };
}
