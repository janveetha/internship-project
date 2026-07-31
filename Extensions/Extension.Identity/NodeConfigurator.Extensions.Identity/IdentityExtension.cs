using System.Text.Json;
using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Extensions.Identity;

/// <summary>The supported identity providers.</summary>
public enum IdentityProvider
{
    /// <summary>No identity provider.</summary>
    None,

    /// <summary>GitHub (requires email).</summary>
    GitHub,

    /// <summary>Microsoft Entra ID (requires email + tenant).</summary>
    EntraID,

    /// <summary>PingID (requires email + PIN).</summary>
    PingID
}

/// <summary>
/// Extension "ext.identity": picks an identity provider for the central node.
/// Only enabled when a central node exists. Enforces the cross-extension rule that
/// "Connected" mode requires EntraID with email + tenant, otherwise reporting a conflict.
/// </summary>
public sealed class IdentityExtension : IExtension, IDetailContributor, INodeEditorContributor
{
    private IExtensionContext? _context;

    /// <inheritdoc />
    public string Id => "ext.identity";

    /// <inheritdoc />
    public string DisplayName => "Identity";

    /// <inheritdoc />
    public Type ComponentType => typeof(IdentityView);

    /// <inheritdoc />
    public Type NodeEditorComponentType => typeof(IdentityView);

    /// <summary>The identity editor is shown only on the central node's page.</summary>
    public bool RendersForNode(string nodeId) =>
        !string.IsNullOrEmpty(_context?.SharedState.CentralNodeId) &&
        string.Equals(nodeId, _context!.SharedState.CentralNodeId, StringComparison.Ordinal);

    /// <summary>The selected identity provider.</summary>
    public IdentityProvider Provider { get; private set; } = IdentityProvider.None;

    /// <summary>Email address (GitHub / EntraID / PingID).</summary>
    public string? Email { get; private set; }

    /// <summary>Tenant (EntraID only).</summary>
    public string? Tenant { get; private set; }

    /// <summary>PIN (PingID only).</summary>
    public string? Pin { get; private set; }

    /// <summary>True only when a central node has been chosen.</summary>
    public bool IsEnabled => !string.IsNullOrEmpty(_context?.SharedState.CentralNodeId);


    /// <inheritdoc />
    public Task InitializeAsync(IExtensionContext context)
    {
        _context = context;

        // Dependency-isolation smoke test: touches Newtonsoft.Json + Markdig (so publish
        // keeps their DLLs) and logs versions/paths/ALC. No UI impact.
        IsolationSmokeTest.Run(Id);

        return Task.CompletedTask;
    }


    /// <inheritdoc />
    public Task HydrateAsync(JsonElement? savedConfig)
    {
        if (savedConfig is { ValueKind: JsonValueKind.Object } config)
        {
            if (config.TryGetProperty("provider", out var p) && p.ValueKind == JsonValueKind.String &&
                Enum.TryParse<IdentityProvider>(p.GetString(), out var parsed))
            {
                Provider = parsed;
            }

            Email = GetString(config, "email");
            Tenant = GetString(config, "tenant");
            Pin = GetString(config, "pin");
        }

        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public JsonElement SerializeConfig() =>
        JsonSerializer.SerializeToElement(new
        {
            provider = Provider.ToString(),
            email = Email,
            tenant = Tenant,
            pin = Pin
        });

    /// <inheritdoc />
    public bool Validate(out string? error)
    {
        error = null;

        // No central node means there is no identity to configure, so nothing to validate.
        if (string.IsNullOrEmpty(_context?.SharedState.CentralNodeId))
            return true;

        var mode = _context?.SharedState.Mode;
        if (string.Equals(mode, "Connected", StringComparison.OrdinalIgnoreCase))
        {
            if (Provider != IdentityProvider.EntraID ||
                string.IsNullOrWhiteSpace(Email) ||
                string.IsNullOrWhiteSpace(Tenant))
            {
                error = "Connected mode requires the EntraID provider configured with an email and tenant.";
                return false;
            }
        }

        return true;
    }

    /// <inheritdoc />
    public IEnumerable<NodeDetail> GetDetailsFor(string nodeId)
    {
        var central = _context?.SharedState.CentralNodeId;
        if (string.IsNullOrEmpty(central) || !string.Equals(nodeId, central, StringComparison.Ordinal))
            yield break;

        if (Provider == IdentityProvider.None)
            yield break;

        yield return new NodeDetail("Identity Provider", Provider.ToString());

        switch (Provider)
        {
            case IdentityProvider.GitHub:
                if (!string.IsNullOrWhiteSpace(Email))
                    yield return new NodeDetail("Email", Email!);
                break;

            case IdentityProvider.EntraID:
                if (!string.IsNullOrWhiteSpace(Email))
                    yield return new NodeDetail("Email", Email!);
                if (!string.IsNullOrWhiteSpace(Tenant))
                    yield return new NodeDetail("Tenant", Tenant!);
                break;

            case IdentityProvider.PingID:
                if (!string.IsNullOrWhiteSpace(Email))
                    yield return new NodeDetail("Email", Email!);
                if (!string.IsNullOrWhiteSpace(Pin))
                    yield return new NodeDetail("PIN", Pin!);
                break;
        }
    }

    /// <summary>Sets the provider and notifies listeners.</summary>
    public void SetProvider(IdentityProvider provider)
    {
        Provider = provider;
        Publish();
    }

    /// <summary>Sets the email and notifies listeners.</summary>
    public void SetEmail(string? email)
    {
        Email = email;
        Publish();
    }

    /// <summary>Sets the tenant and notifies listeners.</summary>
    public void SetTenant(string? tenant)
    {
        Tenant = tenant;
        Publish();
    }

    /// <summary>Sets the PIN and notifies listeners.</summary>
    public void SetPin(string? pin)
    {
        Pin = pin;
        Publish();
    }

    private static string? GetString(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private void Publish()
    {
        _context?.Bus.Publish(new BusMessage(
            "ext.identity.changed",
            Id,
            JsonSerializer.SerializeToElement(new { provider = Provider.ToString() })));
    }
}
