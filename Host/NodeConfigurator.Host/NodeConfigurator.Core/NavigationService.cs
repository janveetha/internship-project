using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// Owns shell navigation state. The selected node is backed by the shared state
/// store (so extensions can observe it), while the active extension is local.
/// </summary>
public sealed class NavigationService : INavigationService
{
    private readonly ISharedStateStore _sharedState;
    private string? _activeExtensionId;
    private ActivePane _activePane = ActivePane.Node;

    public NavigationService(ISharedStateStore sharedState)
    {
        _sharedState = sharedState;
    }

    /// <inheritdoc />
    public string? SelectedNodeId => _sharedState.SelectedNodeId;

    /// <inheritdoc />
    public string? ActiveExtensionId => _activeExtensionId;

    /// <inheritdoc />
    public ActivePane ActivePane => _activePane;

    /// <inheritdoc />
    public ShellState CurrentShellState => new(SelectedNodeId, ActiveExtensionId, _activePane);

    /// <inheritdoc />
    public void SelectNode(string? id)
    {
        var paneChanged = _activePane != ActivePane.Node;
        _activePane = ActivePane.Node;

        if (string.Equals(_sharedState.SelectedNodeId, id, StringComparison.Ordinal))
        {
            if (paneChanged)
                PaneChanged?.Invoke();
            return;
        }

        _sharedState.SelectedNodeId = id;
        NodeChanged?.Invoke();

        if (paneChanged)
            PaneChanged?.Invoke();
    }

    /// <inheritdoc />
    public void ActivateExtension(string? id)
    {
        var paneChanged = _activePane != ActivePane.Extension;
        _activePane = ActivePane.Extension;

        if (string.Equals(_activeExtensionId, id, StringComparison.Ordinal))
        {
            if (paneChanged)
                PaneChanged?.Invoke();
            return;
        }

        _activeExtensionId = id;
        ExtensionChanged?.Invoke();

        if (paneChanged)
            PaneChanged?.Invoke();
    }

    /// <inheritdoc />
    public void SetActivePane(ActivePane pane)
    {
        if (_activePane == pane)
            return;

        _activePane = pane;
        PaneChanged?.Invoke();
    }

    /// <inheritdoc />
    public event Action? NodeChanged;

    /// <inheritdoc />
    public event Action? ExtensionChanged;

    /// <inheritdoc />
    public event Action? PaneChanged;
}
