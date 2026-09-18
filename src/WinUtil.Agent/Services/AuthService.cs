using System.Security.Cryptography;
using System.Text;

namespace WinUtil.Agent.Services;

public sealed class AuthService
{
    private readonly byte[] _token;
    private readonly HashSet<string> _allowedOrigins;

    public AuthService(string token, IEnumerable<string> allowedOrigins)
    {
        _token = Encoding.UTF8.GetBytes(token);
        _allowedOrigins = new HashSet<string>(
            allowedOrigins.Where(x => !string.IsNullOrWhiteSpace(x)),
            StringComparer.OrdinalIgnoreCase);
    }

    public bool IsAuthorized(string candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate)) return false;
        var candidateBytes = Encoding.UTF8.GetBytes(candidate);
        return CryptographicOperations.FixedTimeEquals(_token, candidateBytes);
    }

    /// <summary>
    /// A browser always sends Origin on a cross-origin fetch, and the agent serves no
    /// pages of its own, so a state-changing request without an Origin is not coming
    /// from the site. GET stays permissive for CLI/desktop callers.
    /// </summary>
    public bool IsOriginAllowed(string? origin, bool required)
    {
        if (string.IsNullOrWhiteSpace(origin)) return !required;
        return _allowedOrigins.Contains(origin);
    }

    /// <summary>
    /// DNS-rebinding defence. An attacker can point evil.example at 127.0.0.1, in which
    /// case the browser happily connects and sends Host: evil.example. Only loopback
    /// host values on the configured port are accepted.
    /// </summary>
    public static bool IsHostAllowed(string? host, int port)
    {
        if (string.IsNullOrWhiteSpace(host)) return false;

        var value = host.Trim();
        var colon = value.LastIndexOf(':');

        if (colon > 0 && value.LastIndexOf(']') < colon)
        {
            if (!int.TryParse(value[(colon + 1)..], out var parsed) || parsed != port) return false;
            value = value[..colon];
        }

        value = value.Trim('[', ']');

        return value.Equals("127.0.0.1", StringComparison.Ordinal)
            || value.Equals("localhost", StringComparison.OrdinalIgnoreCase)
            || value.Equals("::1", StringComparison.Ordinal);
    }
}
