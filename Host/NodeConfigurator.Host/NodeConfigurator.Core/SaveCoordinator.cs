using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// Composes the full <see cref="AppSnapshot"/> from all extensions and writes it
/// via the <see cref="IStateStore"/>. Saving is strictly action-based: there is
/// no debounce timer and no auto-save on every change. Each trigger writes once.
/// </summary>
public sealed class SaveCoordinator : ISaveCoordinator
{
    private readonly IStateStore _store;
    private readonly INavigationService _navigation;
    private readonly NodeStore _nodes;
    private readonly IReadOnlyList<IExtension> _extensions;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly List<IDisposable> _subscriptions = new();

    public SaveCoordinator(
        IStateStore store,
        INavigationService navigation,
        NodeStore nodes,
        IEnumerable<IExtension> extensions,
        IEventBus bus)
    {
        _store = store;
        _navigation = navigation;
        _nodes = nodes;
        _extensions = extensions.ToList();

        // An extension publishes "{id}.save" when the user navigates away from it.
        foreach (var ext in _extensions)
            _subscriptions.Add(bus.Subscribe($"{ext.Id}.save", _ => RequestSave($"{ext.Id}.save")));
    }

    /// <inheritdoc />
    public void RequestSave(string reason)
    {
        // No debounce: each trigger writes the whole snapshot once.
        _ = SaveNow();
    }

    /// <inheritdoc />
    public async Task SaveNow()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var extensions = new Dictionary<string, ExtensionSlice>();
            foreach (var ext in _extensions)
                extensions[ext.Id] = new ExtensionSlice(1, ext.SerializeConfig());

            var snapshot = new AppSnapshot(
                _navigation.CurrentShellState,
                _nodes.Nodes.ToList(),
                extensions);

            await _store.SaveAsync(snapshot).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }
}
