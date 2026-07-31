using System.Text.Json;
using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Extensions.Mode;

/// <summary>
/// Extension "ext.mode": lets the user choose the application mode
/// ("Connected" / "Disconnected"). Not tied to any node. Publishes
/// "ext.mode.changed" so dependent extensions (identity) can re-validate.
/// </summary>
public sealed class ModeExtension : IExtension
{
    /// <summary>The "Connected" mode value.</summary>
    public const string Connected = "Connected";

    /// <summary>The "Disconnected" mode value.</summary>
    public const string Disconnected = "Disconnected" ;

    private IExtensionContext? _context;

    /// <inheritdoc />
    public string Id => "ext.mode";

    /// <inheritdoc />
    public string DisplayName => "Mode";

    /// <inheritdoc />
    public Type ComponentType => typeof(ModeView);

    /// <summary>The currently selected mode.</summary>
    public string Mode { get; private set; } = Disconnected;

    /// <inheritdoc />
    public Task InitializeAsync(IExtensionContext context)
    {
        _context = context;
        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public Task HydrateAsync(JsonElement? savedConfig)
    {
        if (savedConfig is { ValueKind: JsonValueKind.Object } config &&
            config.TryGetProperty("mode", out var prop) &&
            prop.ValueKind == JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(prop.GetString()))
        {
            Mode = prop.GetString()!;
        }

        if (_context is not null)
            _context.SharedState.Mode = Mode;

        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public JsonElement SerializeConfig() =>
        JsonSerializer.SerializeToElement(new { mode = Mode });

    /// <inheritdoc />
    public bool Validate(out string? error)
    {
        error = null;
        return true;
    }

    /// <summary>Sets the mode, mirrors it into shared state and notifies listeners.</summary>
    public void SetMode(string mode)
    {
        Mode = mode;
        if (_context is null)
            return;

        _context.SharedState.Mode = mode;
        _context.Bus.Publish(new BusMessage(
            "ext.mode.changed",
            Id,
            JsonSerializer.SerializeToElement(new { mode })));
    }
}
