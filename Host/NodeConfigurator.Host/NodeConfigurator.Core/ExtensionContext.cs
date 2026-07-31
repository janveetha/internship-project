using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// Default <see cref="IExtensionContext"/> exposing the host services to extensions.
/// Nodes are read live from the shared <see cref="NodeStore"/>.
/// </summary>
public sealed class ExtensionContext : IExtensionContext
{
    private readonly NodeStore _nodes;

    public ExtensionContext(
        IEventBus bus,
        ISharedStateStore sharedState,
        NodeStore nodes,
        ISaveCoordinator saveCoordinator)
    {
        Bus = bus;
        SharedState = sharedState;
        _nodes = nodes;
        SaveCoordinator = saveCoordinator;
    }

    /// <inheritdoc />
    public IEventBus Bus { get; }

    /// <inheritdoc />
    public ISharedStateStore SharedState { get; }

    /// <inheritdoc />
    public IReadOnlyList<Node> Nodes => _nodes.Nodes;

    /// <inheritdoc />
    public ISaveCoordinator SaveCoordinator { get; }
}
