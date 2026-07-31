using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// In-memory implementation of <see cref="ISharedStateStore"/> that raises
/// <see cref="Changed"/> with the property name whenever a value actually changes.
/// </summary>
public sealed class SharedStateStore : ISharedStateStore
{
    private string? _selectedNodeId;
    private string? _centralNodeId;
    private string? _mode;

    /// <inheritdoc />
    public string? SelectedNodeId
    {
        get => _selectedNodeId;
        set => SetValue(ref _selectedNodeId, value, nameof(SelectedNodeId));
    }

    /// <inheritdoc />
    public string? CentralNodeId
    {
        get => _centralNodeId;
        set => SetValue(ref _centralNodeId, value, nameof(CentralNodeId));
    }

    /// <inheritdoc />
    public string? Mode
    {
        get => _mode;
        set => SetValue(ref _mode, value, nameof(Mode));
    }

    /// <inheritdoc />
    public event Action<string>? Changed;

    private void SetValue(ref string? field, string? value, string key)
    {
        if (string.Equals(field, value, StringComparison.Ordinal))
            return;

        field = value;
        Changed?.Invoke(key);
    }
}
