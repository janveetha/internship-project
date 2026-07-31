using System.Text.Json;

namespace NodeConfigurator.Abstractions;

/// <summary>
/// A computer that can be configured by the application.
/// </summary>
/// <param name="Id">Stable unique identifier for the node.</param>
/// <param name="Name">Human readable display name (e.g. "Computer-1").</param>
public record Node(string Id, string Name);

/// <summary>
/// A single piece of information shown for a node. Extensions contribute these
/// in addition to the base "Name" detail provided by the host.
/// </summary>
/// <param name="Label">The detail label (e.g. "Central Node").</param>
/// <param name="Value">The detail value (e.g. "local").</param>
public record NodeDetail(string Label, string Value);

/// <summary>
/// Identifies which main content pane the shell was last showing.
/// </summary>
public enum ActivePane
{
    /// <summary>The selected node's read-only aggregated details.</summary>
    Node,

    /// <summary>The selected extension's configuration panel.</summary>
    Extension
}

/// <summary>
/// Persisted shell (host) state describing what the user was looking at.
/// </summary>
/// <param name="SelectedNodeId">Id of the node that was selected, or null.</param>
/// <param name="ActiveExtensionId">Id of the extension tab that was active, or null.</param>
/// <param name="ActivePane">Which pane (node details or extension config) was last shown.</param>
public record ShellState(string? SelectedNodeId, string? ActiveExtensionId, ActivePane ActivePane = ActivePane.Node);

/// <summary>
/// An opaque, versioned blob of configuration owned by a single extension.
/// The host never inspects <see cref="Config"/>; it only round-trips it back
/// to the owning extension during hydration.
/// </summary>
/// <param name="Version">Schema version the extension wrote.</param>
/// <param name="Config">Opaque extension configuration as raw JSON.</param>
public record ExtensionSlice(int Version, JsonElement Config);

/// <summary>
/// The complete persisted state of the application written to / read from disk.
/// </summary>
/// <param name="Shell">Host shell state (selection / active tab).</param>
/// <param name="Nodes">The list of configured nodes.</param>
/// <param name="Extensions">Per-extension opaque configuration keyed by extension id.</param>
public record AppSnapshot(
    ShellState Shell,
    List<Node> Nodes,
    Dictionary<string, ExtensionSlice> Extensions);
