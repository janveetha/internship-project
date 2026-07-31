namespace NodeConfigurator.Abstractions;

/// <summary>
/// Holds a small set of cross-cutting values that more than one extension or the
/// host needs to read/write, and raises change notifications when they change.
/// </summary>
public interface ISharedStateStore
{
    /// <summary>Id of the currently selected node, or null.</summary>
    string? SelectedNodeId { get; set; }

    /// <summary>Id of the node chosen as the central node, or null if none.</summary>
    string? CentralNodeId { get; set; }

    /// <summary>The current mode value ("Connected" / "Disconnected"), or null.</summary>
    string? Mode { get; set; }

    /// <summary>Raised with the changed key name whenever a value changes.</summary>
    event Action<string>? Changed;
}

/// <summary>
/// Owns shell navigation state (selected node and active extension tab) and keeps
/// it in sync with the persisted <see cref="ShellState"/>.
/// </summary>
public interface INavigationService
{
    /// <summary>Id of the currently selected node, or null.</summary>
    string? SelectedNodeId { get; }

    /// <summary>Id of the currently active extension tab, or null.</summary>
    string? ActiveExtensionId { get; }

    /// <summary>Which pane (node details or extension config) is currently shown.</summary>
    ActivePane ActivePane { get; }

    /// <summary>The current shell state composed from the live selection values.</summary>
    ShellState CurrentShellState { get; }

    /// <summary>Selects a node, switches to the node pane, and raises <see cref="NodeChanged"/>.</summary>
    void SelectNode(string? id);

    /// <summary>Activates an extension tab, switches to the extension pane, and raises <see cref="ExtensionChanged"/>.</summary>
    void ActivateExtension(string? id);

    /// <summary>Sets the active pane and raises <see cref="PaneChanged"/> when it changes.</summary>
    void SetActivePane(ActivePane pane);

    /// <summary>Raised whenever the selected node changes.</summary>
    event Action? NodeChanged;

    /// <summary>Raised whenever the active extension changes.</summary>
    event Action? ExtensionChanged;

    /// <summary>Raised whenever the active pane changes.</summary>
    event Action? PaneChanged;
}

/// <summary>
/// Coordinates writing the whole <see cref="AppSnapshot"/> to storage. Saving is
/// action-based only (no auto-save / debounce): it is triggered explicitly or via
/// the event bus on well-defined user actions.
/// </summary>
public interface ISaveCoordinator
{
    /// <summary>Requests a save; the reason is informational/diagnostic.</summary>
    void RequestSave(string reason);

    /// <summary>Composes the snapshot from all extensions and writes it now.</summary>
    Task SaveNow();
}

/// <summary>5
/// Reads and writes the persisted <see cref="AppSnapshot"/>.
/// </summary>
public interface IStateStore
{
    /// <summary>Loads the snapshot, or returns null if no state exists yet.</summary>
    Task<AppSnapshot?> LoadAsync();

    /// <summary>Persists the snapshot durably.</summary>
    Task SaveAsync(AppSnapshot snapshot);
}
