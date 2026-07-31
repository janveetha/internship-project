using System.Text.Json;
using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Extensions.CentralNode;

/// <summary>
/// Extension "ext.central": lets the user pick a single node as the central node.
/// Contributes a "Central Node" detail to every node ("local" on the chosen node,
/// the chosen node's name on all others).
/// </summary>
public sealed class CentralNodeExtension : IExtension, IDetailContributor, INodeEditorContributor
{
    private IExtensionContext? _context;

    /// <inheritdoc />
    public string Id => "ext.central";

    /// <inheritdoc />
    public string DisplayName => "Central Node";

    /// <inheritdoc />
    public Type ComponentType => typeof(CentralNodeView);

    /// <inheritdoc />
    public Type NodeEditorComponentType => typeof(CentralNodeView);

    /// <summary>The central node editor is shown on every node's page.</summary>
    public bool RendersForNode(string nodeId) => true;

    /// <summary>Id of the node chosen as central, or null if none.</summary>
    public string? CentralNodeId { get; private set; }

    

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
        if (savedConfig is { ValueKind: JsonValueKind.Object } config &&
            config.TryGetProperty("centralNodeId", out var prop) &&
            prop.ValueKind == JsonValueKind.String)
        {
            CentralNodeId = prop.GetString();
        }

        if (_context is not null)
            _context.SharedState.CentralNodeId = CentralNodeId;

        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public JsonElement SerializeConfig() =>
        JsonSerializer.SerializeToElement(new { centralNodeId = CentralNodeId });

    /// <inheritdoc />
    public bool Validate(out string? error)
    {
        error = null;
        return true;
    }

    /// <inheritdoc />
    public IEnumerable<NodeDetail> GetDetailsFor(string nodeId)
    {
        if (string.IsNullOrEmpty(CentralNodeId))
            yield break;

        if (string.Equals(nodeId, CentralNodeId, StringComparison.Ordinal))
        {
            yield return new NodeDetail("Central Node", "local");
        }
        else
        {
            var name = _context?.Nodes.FirstOrDefault(n => n.Id == CentralNodeId)?.Name ?? CentralNodeId;
            yield return new NodeDetail("Central Node", name);
        }
    }

    /// <summary>
    /// Updates the central node, mirrors it into shared state and notifies listeners.
    /// Called by the UI component when the user changes the selection.
    /// </summary>
    public void SetCentral(string? nodeId)
    {
        CentralNodeId = nodeId;
        if (_context is null)
            return;

        _context.SharedState.CentralNodeId = nodeId;
        _context.Bus.Publish(new BusMessage(
            "ext.central.changed",
            Id,
            JsonSerializer.SerializeToElement(new { centralNodeId = nodeId })));
    }
}
