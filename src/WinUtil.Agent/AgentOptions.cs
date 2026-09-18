namespace WinUtil.Agent;

public sealed class AgentOptions
{
    public string Name { get; set; } = "WinUtil NG Agent";
    public string Version { get; set; } = "0.2.1";
    public string BindAddress { get; set; } = "127.0.0.1";
    public int Port { get; set; } = 15721;
    public string[] AllowedOrigins { get; set; } = ["http://localhost:5173"];
}
