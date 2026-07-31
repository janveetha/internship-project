using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// Holds the canonical list of nodes for the session. Acts as a shared seam so
/// the context and the save coordinator can read nodes without a dependency cycle.
/// </summary>
public sealed class NodeStore
{
    /// <summary>The current nodes. Set once during startup.</summary>
    public IReadOnlyList<Node> Nodes { get; set; } = Array.Empty<Node>();
}
