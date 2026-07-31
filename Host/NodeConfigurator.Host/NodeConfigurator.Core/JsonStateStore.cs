using System.Text.Json;
using NodeConfigurator.Abstractions;

namespace NodeConfigurator.Core;

/// <summary>
/// <see cref="IStateStore"/> backed by a JSON file. Writes are atomic: the
/// snapshot is written to a sibling ".tmp" file which is then moved (renamed)
/// over the real file so a crash mid-write cannot corrupt existing state.
/// </summary>
public sealed class JsonStateStore : IStateStore
{
    private readonly string _filePath;

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    public JsonStateStore(string filePath)
    {
        _filePath = filePath;
    }

    /// <inheritdoc />
    public async Task<AppSnapshot?> LoadAsync()
    {
        if (!File.Exists(_filePath))
            return null;

        await using var stream = File.OpenRead(_filePath);
        return await JsonSerializer.DeserializeAsync<AppSnapshot>(stream, Options).ConfigureAwait(false);
    }

    /// <inheritdoc />
    public async Task SaveAsync(AppSnapshot snapshot)
    {
        var directory = Path.GetDirectoryName(_filePath);
        if (!string.IsNullOrEmpty(directory))
            Directory.CreateDirectory(directory);

        var tempPath = _filePath + ".tmp";

        await using (var stream = File.Create(tempPath))
        {
            await JsonSerializer.SerializeAsync(stream, snapshot, Options).ConfigureAwait(false);
            await stream.FlushAsync().ConfigureAwait(false);
        }

        // Atomic replace of the real file with the freshly written temp file.
        File.Move(tempPath, _filePath, overwrite: true);
    }
}
