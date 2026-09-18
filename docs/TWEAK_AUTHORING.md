# Tweak authoring guide

The manifest is the primary inventory and policy source.

## Example Registry tweak

```json
{
  "Id": "Privacy.Example",
  "Name": "Example policy",
  "Description": "Human-readable explanation.",
  "Category": "Privacy",
  "Scope": "System",
  "Provider": "Registry",
  "Risk": "Low",
  "RequiresAdmin": true,
  "Reversible": true,
  "EnabledByDefault": false,
  "RequiresRestorePoint": true,
  "Tags": ["privacy"],
  "SupportedOS": ["Windows 10", "Windows 11"],
  "Settings": {
    "RegistryPath": "HKLM:\\SOFTWARE\\Policies\\Vendor\\Example",
    "ValueName": "Enabled",
    "DesiredValue": 0,
    "PropertyType": "DWord"
  }
}
```

The generic Registry provider:

1. Creates the key if it does not exist.
2. Captures old value + type.
3. Uses `Set-ItemProperty` for in-place writes where the type already matches.
4. Uses `New-ItemProperty` when a value or type must be created.
5. Verifies the resulting value.
6. Captures enough state for rollback when marked reversible.

## Non-registry provider

For operations such as DISM, SFC, Network or Appx, use a provider that has an explicit implementation in `Operations.ps1`.

Do not accept arbitrary provider names from the browser. The agent validates IDs against the manifest and the PowerShell engine maintains a closed provider list.
