using System.Text.Json;

namespace NodeConfigurator.Abstractions;

/// <summary>
/// The services the host exposes to every extension. Passed to an extension via
/// <see cref="IExtension.InitializeAsync"/> and to its UI component as a parameter.
/// </summary>
public interface IExtensionContext
{
    /// <summary>The shared in-process message bus.</summary>
    IEventBus Bus { get;  }

    /// <summary>Shared cross-extension state values.</summary>
    ISharedStateStore SharedState { get; }

    /// <summary>The current list of nodes.</summary>
    IReadOnlyList<Node> Nodes { get; }

    /// <summary>The coordinator used to request/perform saves.</summary>
    ISaveCoordinator SaveCoordinator { get; }
}

/// <summary>
/// A pluggable UI extension. The implementation is the authoritative owner of the
/// extension's state so that <see cref="Validate"/> works even when its UI is not
/// currently rendered (e.g. for tab badges).
/// </summary>
public interface IExtension
{
    /// <summary>Stable unique id (e.g. "ext.central").</summary>
    string Id { get; }

    /// <summary>Human readable name shown on the extension's tab.</summary>
    string DisplayName { get; }

    /// <summary>The Razor component type that renders this extension's UI.</summary>
    Type ComponentType { get; }

    /// <summary>Called once at startup to give the extension its context.</summary>
    Task InitializeAsync(IExtensionContext context);

    /// <summary>Restores the extension from its previously saved config (null if none).</summary>
    Task HydrateAsync(JsonElement? savedConfig);

    /// <summary>Serializes the extension's current state to opaque JSON for persistence.</summary>
    JsonElement SerializeConfig();

    /// <summary>
    /// Validates the extension's current state. Returns false and an
    /// <paramref name="error"/> message when there is a (possibly cross-extension) conflict.
    /// </summary>
    bool Validate(out string? error);
}

/// <summary>
/// Implemented by extensions that contribute additional details to a node's
/// aggregated detail view.
/// </summary>
public interface IDetailContributor
{
    /// <summary>Returns the details this extension contributes for the given node.</summary>
    IEnumerable<NodeDetail> GetDetailsFor(string nodeId);
}

/// <summary>wwwwwwwwweeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
/// Implemented by extensions that render a node-scoped editor inline on a node's
/// page (rather than as a separate sidebar tab). The host passes the id of the node
/// being rendered to the editor component via a <c>NodeId</c> parameter.
/// </summary>
public interface INodeEditorContributor
{
    /// <summary>The Razor component type that renders this extension's node-scoped editor.</summary>
    Type NodeEditorComponentType { get; }

    /// <summary>Returns true when the editor should be rendered for the given node.</summary>
    bool RendersForNode(string nodeId);
}
